import 'package:audifac/models/audio_info.dart';
import 'package:audifac/models/backup.dart';
import 'package:audifac/models/song.dart';
import 'package:audifac/models/tag_edit.dart';
import 'package:flutter_test/flutter_test.dart';

Song _song(int id, {String title = 'Lucky Night', String album = 'FormatTest', int track = 2003}) => Song(
      id: id,
      uri: 'content://media/external/audio/media/$id',
      path: '/storage/emulated/0/Music/$id.flac',
      title: title,
      artist: 'Jody',
      artistId: 7,
      album: album,
      albumId: 9,
      duration: const Duration(minutes: 1),
      trackNumber: track,
      dateAdded: DateTime(2024),
    );

void main() {
  const info = AudioInfo(codec: 'FLAC', sampleRate: 44100, bitDepth: 16, genre: 'Pop', year: '2019');

  test('apply replaces tags; a new album moves the song, edited songs end up together', () {
    final a = const TagEdit(title: 'Lucky Night (Live)', album: 'Treasure Quest').apply(_song(1));
    expect(a.title, 'Lucky Night (Live)');
    expect(a.artist, 'Jody');
    expect(a.artistId, 7);
    expect(a.album, 'Treasure Quest');
    expect(a.albumId, isNot(9));
    final b = const TagEdit(album: 'Treasure Quest').apply(_song(2, album: 'Other'));
    expect(b.albumId, a.albumId);
    // Title only: same album.
    expect(const TagEdit(title: 'x').apply(_song(3)).albumId, 9);
    expect(const TagEdit(artist: 'Jody Marie Gnant').apply(_song(1)).artistId, isNot(7));
    expect(const TagEdit().apply(_song(1)), _song(1));
  });

  test('applyInfo replaces genre / year / album artist only', () {
    final i = const TagEdit(genre: 'Jazz', albumArtist: 'Various').applyInfo(info);
    expect((i.genre, i.year, i.albumArtist, i.codec, i.bitDepth), ('Jazz', '2019', 'Various', 'FLAC', 16));
    expect(identical(const TagEdit(title: 'x').applyInfo(info), info), isTrue);
  });

  test('diff keeps only what differs from the file; blank means the file tag; disc is kept', () {
    final file = _song(1);
    TagEdit diff({String title = 'Lucky Night', String genre = 'Pop', String year = '2019', String track = '3'}) =>
        TagEdit.diff(
          file: file,
          fileInfo: info,
          title: title,
          artist: 'Jody',
          album: 'FormatTest',
          albumArtist: '',
          genre: genre,
          year: year,
          track: track,
        );
    expect(diff().isEmpty, isTrue);
    expect(diff(title: '  Lucky Night ').isEmpty, isTrue);
    expect(diff(title: '').isEmpty, isTrue);
    expect(diff(genre: 'Jazz'), const TagEdit(genre: 'Jazz'));
    expect(diff(track: '5').track, 2005);
    expect(diff(track: '').track, isNull);
  });

  test('json and backup round trip', () {
    const edit = TagEdit(title: 't', artist: 'a', album: 'b', albumArtist: 'c', genre: 'g', year: '1999', track: 4);
    expect(TagEdit.decode(edit.encode()), edit);
    expect(const TagEdit(genre: 'g').toJson().keys, ['genre']);
    final data = BackupData(
      exportedAt: DateTime(2026),
      appVersion: '1',
      tagEdits: [TagEditBackup(song: SongRef.of(_song(1)), edit: edit)],
    );
    final back = BackupData.decode(data.encode());
    expect(back.tagEdits.single.edit, edit);
    expect(back.tagEdits.single.song.title, 'Lucky Night');
  });
}
