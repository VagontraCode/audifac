import 'package:audifac/models/m3u.dart';
import 'package:audifac/models/song.dart';
import 'package:flutter_test/flutter_test.dart';

Song _song(int id, String path, {String title = 't', String artist = 'a'}) => Song(
      id: id,
      uri: 'content://media/external/audio/media/$id',
      path: path,
      title: title,
      artist: artist,
      artistId: 1,
      album: 'b',
      albumId: 1,
      duration: const Duration(seconds: 215),
      dateAdded: DateTime(2024),
    );

void main() {
  final library = [
    _song(1, '/storage/emulated/0/Music/Album A/01 Intro.flac', title: 'Intro', artist: 'X'),
    _song(2, '/storage/emulated/0/Music/Album B/01 Intro.flac', title: 'Intro', artist: 'Y'),
    _song(3, '/storage/1234-ABCD/Music/Été.mp3', title: 'Été', artist: 'Zaz'),
    _song(4, '/storage/emulated/0/Download/Lonely.mp3', title: 'Lonely', artist: 'Joeboy'),
  ];

  test('parse: EXTINF details, comments, CRLF, BOM, name', () {
    const text = '\uFEFF#EXTM3U\r\n#PLAYLIST:Road trip\r\n#EXTINF:215,Joeboy - Lonely\r\nLonely.mp3\r\n\r\n# comment\r\n'
        '#EXTINF:-1 tvg-id="x",Radio\r\nhttp://radio.example/stream\r\n'
        r'C:\Music\Album B\01 Intro.flac'
        '\r\n';
    final e = M3u.parse(text);
    expect(M3u.name(text), 'Road trip');
    expect(e.map((x) => x.location), ['Lonely.mp3', 'http://radio.example/stream', r'C:\Music\Album B\01 Intro.flac']);
    expect((e[0].artist, e[0].title, e[0].seconds), ('Joeboy', 'Lonely', 215));
    expect((e[1].title, e[1].seconds), ('Radio', -1));
    expect(e[2].title, isNull);
  });

  test('components: file URIs, Windows paths, relative paths, streams', () {
    expect(M3u.components('file:///storage/emulated/0/Music/%C3%89t%C3%A9.mp3'), ['storage', 'emulated', '0', 'music', 'été.mp3']);
    expect(M3u.components(r'C:\Music\x.flac'), ['music', 'x.flac']);
    expect(M3u.components('../Album/x.flac'), ['album', 'x.flac']);
    expect(M3u.components('https://x/y.mp3'), isNull);
  });

  test('match by path (deepest common folders), then by tags', () {
    final entries = M3u.parse([
      '/storage/emulated/0/Music/Album A/01 Intro.flac', // absolute
      r'D:\Rips\Album B\01 Intro.flac', // a PC's path: the folder picks B
      'Music/Été.mp3', // relative, other volume
      '#EXTINF:180,Joeboy - Lonely',
      '/sdcard/Old/Lonely (1).mp3', // renamed: tags
      '#EXTINF:100,Nobody - Nothing',
      'missing.mp3',
      'http://stream',
    ].join('\n'));
    expect(M3u.match(entries, library).map((s) => s?.id), [1, 2, 3, 4, null, null]);
  });

  test('write then read back', () {
    final text = M3u.write('Mix', [library[3], library[2]]);
    expect(text, startsWith('#EXTM3U\n#PLAYLIST:Mix\n#EXTINF:215,Joeboy - Lonely\n/storage/emulated/0/Download/Lonely.mp3\n'));
    expect(M3u.name(text), 'Mix');
    expect(M3u.match(M3u.parse(text), library).map((s) => s?.id), [4, 3]);
  });
}
