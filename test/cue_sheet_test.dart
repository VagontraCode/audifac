import 'package:audifac/models/cue_sheet.dart';
import 'package:audifac/models/song.dart';
import 'package:audifac/models/tag_edit.dart';
import 'package:flutter_test/flutter_test.dart';

const _cue = '''
REM GENRE "Jazz"
REM DATE 1959
PERFORMER "Miles Davis"
TITLE "Kind of Blue"
FILE "Kind of Blue.wav" WAVE
  TRACK 01 AUDIO
    TITLE "So What"
    INDEX 01 00:00:00
  TRACK 02 AUDIO
    TITLE "Freddie Freeloader"
    PERFORMER "Miles Davis Sextet"
    INDEX 00 09:20:00
    INDEX 01 09:22:37
  TRACK 03 AUDIO
    TITLE "Blue in Green"
    INDEX 01 19:08:00
''';

Song _file(int id, String path, {int minutes = 25}) => Song(
      id: id,
      uri: 'content://media/external/audio/media/$id',
      path: path,
      title: 'Kind of Blue',
      artist: 'Unknown artist',
      artistId: 1,
      album: 'Unknown album',
      albumId: 2,
      duration: Duration(minutes: minutes),
      dateAdded: DateTime(2024),
      sizeBytes: 300000000,
    );

void main() {
  test('parse: album and track details, INDEX 01 at 75 frames a second', () {
    final sheet = CueSheet.parse(_cue, '/storage/emulated/0/Music/Miles/Kind of Blue.cue')!;
    expect((sheet.title, sheet.performer, sheet.genre, sheet.date, sheet.file), ('Kind of Blue', 'Miles Davis', 'Jazz', '1959', 'Kind of Blue.wav'));
    expect(sheet.folder, '/storage/emulated/0/Music/Miles');
    expect(sheet.tracks.map((t) => t.title), ['So What', 'Freddie Freeloader', 'Blue in Green']);
    expect(sheet.tracks[1].start, const Duration(minutes: 9, seconds: 22, microseconds: 493333));
    expect(sheet.tracks[1].performer, 'Miles Davis Sextet');
  });

  test('parse rejects sheets that are not one file with tracks', () {
    expect(CueSheet.parse('FILE "a.wav" WAVE\n  TRACK 01 AUDIO\n    INDEX 01 00:00:00\n', '/x/a.cue'), isNull);
    expect(CueSheet.parse('$_cue\nFILE "b.wav" WAVE\n  TRACK 04 AUDIO\n    INDEX 01 00:00:00\n', '/x/a.cue'), isNull);
    expect(CueSheet.parse('hello', '/x/a.cue'), isNull);
  });

  test('a data track title does not become the album title', () {
    final sheet = CueSheet.parse('TITLE "Album"\nFILE "a.flac" WAVE\n  TRACK 01 AUDIO\n    INDEX 01 00:00:00\n'
        '  TRACK 02 AUDIO\n    INDEX 01 01:00:00\n  TRACK 03 MODE1/2352\n    TITLE "Data"\n    INDEX 01 02:00:00\n', '/x/a.cue')!;
    expect(sheet.title, 'Album');
    expect(sheet.tracks, hasLength(2));
  });

  test('apply: the file (here FLAC, sheet says WAV) becomes clipped tracks', () {
    final sheet = CueSheet.parse(_cue, '/storage/emulated/0/Music/Miles/Kind of Blue.cue')!;
    final flac = _file(1, '/storage/emulated/0/Music/Miles/Kind of Blue.flac');
    final other = _file(2, '/storage/emulated/0/Music/Other/x.flac');
    final songs = CueSheet.apply([other, flac], [sheet]);
    expect(songs.map((s) => s.title), ['Kind of Blue', 'So What', 'Freddie Freeloader', 'Blue in Green']);
    final tracks = songs.skip(1).toList();
    expect(tracks.every((s) => s.isCueTrack && s.uri == flac.uri && s.album == 'Kind of Blue'), isTrue);
    expect(tracks.map((s) => s.artist), ['Miles Davis', 'Miles Davis Sextet', 'Miles Davis']);
    expect(tracks.map((s) => s.trackNumber), [1, 2, 3]);
    expect(tracks.first.clipStart, Duration.zero);
    expect(tracks.first.clipEnd, tracks[1].clipStart);
    expect(tracks.last.clipEnd, isNull);
    expect(tracks.last.duration, const Duration(minutes: 25) - const Duration(minutes: 19, seconds: 8));
    expect(tracks.map((s) => s.albumId).toSet(), hasLength(1));
    expect(tracks.map((s) => s.id).toSet(), hasLength(3));
    expect(tracks.map((s) => s.key).toSet(), hasLength(3)); // tag edits stay per track
    // Stable ids across rescans.
    expect(CueSheet.apply([flac], [sheet]).map((s) => s.id), tracks.map((s) => s.id));
    // A tag edit keeps the clip.
    expect(const TagEdit(title: 'x').apply(tracks[1]).clipStart, tracks[1].clipStart);
  });

  test('apply leaves files alone when the sheet does not fit', () {
    final sheet = CueSheet.parse(_cue, '/storage/emulated/0/Music/Miles/Kind of Blue.cue')!;
    final short = _file(1, '/storage/emulated/0/Music/Miles/Kind of Blue.flac', minutes: 5);
    expect(CueSheet.apply([short], [sheet]), [short]);
    final elsewhere = _file(1, '/storage/emulated/0/Music/Kind of Blue.flac');
    expect(CueSheet.apply([elsewhere], [sheet]), [elsewhere]);
  });
}
