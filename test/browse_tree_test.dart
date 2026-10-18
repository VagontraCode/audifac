import 'package:audifac/core/audio/browse_tree.dart';
import 'package:audifac/models/album.dart';
import 'package:audifac/models/artist.dart';
import 'package:audifac/models/song.dart';
import 'package:flutter_test/flutter_test.dart';

Song _s(int id, String title, {String artist = 'Asake', int album = 1}) => Song(
      id: id,
      uri: 'content://media/external/audio/media/$id',
      title: title,
      artist: artist,
      artistId: artist.hashCode,
      album: 'Album $album',
      albumId: album,
      duration: const Duration(minutes: 3),
      dateAdded: DateTime(2024),
    );

void main() {
  final a = _s(1, 'Lonely'), b = _s(2, 'Sungba'), c = _s(3, 'Buga', artist: 'Kizz Daniel', album: 2);
  final tree = BrowseTree(
    all: [a, b, c],
    recent: [c],
    playlists: [BrowseList(id: 'playlist:7', title: 'Road trip', songs: [c, a])],
    albums: [
      Album(id: 1, title: 'Album 1', artist: 'Asake', songs: [a, b]),
      Album(id: 2, title: 'Album 2', artist: 'Kizz Daniel', songs: [c]),
    ],
    artists: [Artist(id: 9, name: 'Asake', songs: [a, b], albums: const [])],
  );

  test('root lists only what exists', () {
    expect([for (final i in tree.children(BrowseTree.root)) i.id], ['recent', 'playlists', 'albums', 'artists', 'shuffle']);
    expect(tree.children(BrowseTree.root).last.playable, isTrue);
  });

  test('folders, then songs carrying their list', () {
    expect([for (final i in tree.children('albums')) i.title], ['Album 1', 'Album 2']);
    final songs = tree.children('album:1');
    expect([for (final i in songs) i.id], ['album:1|song:1', 'album:1|song:2']);
    expect(songs.every((i) => i.playable == true), isTrue);
    expect(tree.children('playlists').single.id, 'playlist:7');
    expect([for (final i in tree.children('playlist:7')) i.title], ['Buga', 'Lonely']);
  });

  test('playing a song plays its list from there', () {
    final hit = tree.playable('playlist:7|song:1')!;
    expect([for (final s in hit.songs) s.id], [3, 1]);
    expect(hit.index, 1);
    expect(tree.playable('shuffle')!.shuffle, isTrue);
    expect(tree.playable('album:2')!.songs.single.title, 'Buga');
    expect(tree.playable('album:99|song:1'), isNull);
    expect(tree.playable('nonsense'), isNull);
  });

  test('search ranks exact titles, then artists', () {
    expect([for (final s in tree.search('buga')) s.id], [3]);
    expect([for (final s in tree.search('asake')) s.id], [1, 2]);
    expect(tree.search('  '), isEmpty);
  });
}
