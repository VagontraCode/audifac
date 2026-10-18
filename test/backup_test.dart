import 'package:audifac/models/backup.dart';
import 'package:audifac/models/song.dart';
import 'package:flutter_test/flutter_test.dart';

Song _song(int id, String path, {String title = 'Song', String artist = 'Artist', String album = 'Album', int seconds = 200}) =>
    Song(
      id: id,
      uri: 'content://media/external/audio/media/$id',
      path: path,
      title: title,
      artist: artist,
      artistId: 1,
      album: album,
      albumId: 1,
      duration: Duration(seconds: seconds),
      dateAdded: DateTime(2024),
    );

void main() {
  test('relative paths drop the storage volume (internal and SD)', () {
    expect(SongRef.relative('/storage/emulated/0/Music/a.flac'), 'Music/a.flac');
    expect(SongRef.relative('/storage/1A2B-3C4D/Music/a.flac'), 'Music/a.flac');
    expect(SongRef.relative(null), isNull);
  });

  group('SongMatcher (new phone = new MediaStore ids)', () {
    final device = [
      _song(501, '/storage/emulated/0/Music/Album/01.flac', title: 'Intro'),
      _song(502, '/storage/1A2B-3C4D/Other/Hello.mp3', title: 'Hello', artist: 'Adele', album: '25', seconds: 295),
      _song(503, '/storage/emulated/0/Download/hello live.mp3', title: 'Hello', artist: 'Adele', album: 'Live', seconds: 360),
    ];
    final matcher = SongMatcher(device);

    test('same relative path wins, even on another volume', () {
      final ref = SongRef.of(_song(7, '/storage/9999-0000/Music/Album/01.flac', title: 'Renamed tag'));
      expect(matcher.match(ref)?.id, 501);
    });

    test('falls back to title + artist, preferring album and duration', () {
      const ref = SongRef(relativePath: 'Old/Place/Hello.mp3', title: 'hello', artist: 'ADELE', album: '25', durationMs: 296000);
      expect(matcher.match(ref)?.id, 502);
      const live = SongRef(relativePath: null, title: 'Hello', artist: 'Adele', album: 'Live', durationMs: 361000);
      expect(matcher.match(live)?.id, 503);
    });

    test('very different length = different recording → no match', () {
      const ref = SongRef(relativePath: null, title: 'Intro', artist: 'Artist', album: 'Album', durationMs: 600000);
      expect(matcher.match(ref), isNull);
      const unknown = SongRef(relativePath: 'x.mp3', title: 'Nope', artist: 'None', album: '', durationMs: 0);
      expect(matcher.match(unknown), isNull);
    });
  });

  test('backup round-trips through JSON', () {
    final original = BackupData(
      exportedAt: DateTime.utc(2026, 10, 18, 14, 30),
      appVersion: '0.1.0+3',
      favorites: [SongRef.of(_song(1, '/storage/emulated/0/Music/a.mp3', title: 'A'))],
      recent: [SongRef.of(_song(2, '/storage/emulated/0/Music/b.mp3', title: 'B'))],
      playlists: [
        PlaylistBackup(name: 'Run', songs: [SongRef.of(_song(3, '/storage/emulated/0/Music/c.mp3', title: 'C'))]),
      ],
      eqPresets: const [
        {'id': 'u_1', 'name': 'Mine', 'kind': 'sound', 'graphic': false, 'preamp': -3.0, 'bands': []},
      ],
      eqRules: const [
        RuleBackup(scope: 'artist', presetId: 'u_1', key: 'Adele', label: 'Adele'),
        RuleBackup(scope: 'album', presetId: 'u_1', album: '25', albumArtist: 'Adele'),
      ],
      eqSettings: '{"enabled":true}',
      settings: const {'themeMode': 'dark'},
    );
    final back = BackupData.decode(original.encode());
    expect(back.appVersion, '0.1.0+3');
    expect(back.exportedAt, original.exportedAt);
    expect(back.favorites.single.relativePath, 'Music/a.mp3');
    expect(back.recent.single.title, 'B');
    expect(back.playlists.single.name, 'Run');
    expect(back.playlists.single.songs.single.title, 'C');
    expect(back.eqPresets.single['name'], 'Mine');
    expect(back.eqRules.map((r) => r.scope), ['artist', 'album']);
    expect(back.eqRules.last.albumArtist, 'Adele');
    expect(back.eqSettings, '{"enabled":true}');
    expect(back.settings['themeMode'], 'dark');
  });

  test('rejects files that are not backups, or from a newer version', () {
    expect(() => BackupData.decode('not json'), throwsFormatException);
    expect(() => BackupData.decode('{"format":"something-else"}'), throwsFormatException);
    expect(() => BackupData.decode('{"format":"audifac-backup","version":99}'), throwsFormatException);
  });
}
