import 'package:audifac/models/song.dart';
import 'package:audifac/providers/library_providers.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

Song _song(int id, {required String artist, required int artistId, required String album, required int albumId, int track = 0}) =>
    Song(
      id: id,
      uri: 'content://media/external/audio/media/$id',
      path: '/storage/emulated/0/Music/$id.mp3',
      title: 't$id',
      artist: artist,
      artistId: artistId,
      album: album,
      albumId: albumId,
      trackNumber: track,
      duration: const Duration(minutes: 3),
      dateAdded: DateTime(2024),
    );

void main() {
  test('artists: albums in album order, songs album by album in track order', () {
    // Library order on purpose differs from album / track order.
    final songs = [
      _song(3, artist: 'Ann', artistId: 10, album: 'Zed', albumId: 1, track: 3),
      _song(4, artist: 'bob', artistId: 20, album: 'alpha', albumId: 2, track: 1),
      _song(2, artist: 'bob', artistId: 21, album: 'Zed', albumId: 1, track: 2),
      _song(1, artist: 'Ann', artistId: 11, album: 'Zed', albumId: 1, track: 1),
      _song(5, artist: 'Cy', artistId: 30, album: 'alpha', albumId: 2, track: 2),
    ];
    final container = ProviderContainer(overrides: [songsProvider.overrideWithValue(songs)]);
    addTearDown(container.dispose);

    final albums = container.read(albumsProvider);
    expect(albums.map((a) => a.title), ['alpha', 'Zed']);
    expect(albums.last.songs.map((s) => s.id), [1, 2, 3]);
    expect(albums.last.artist, 'Various artists');

    final artists = container.read(artistsProvider);
    expect(artists.map((a) => a.name), ['Ann', 'bob', 'Cy']);
    final ann = artists[0], bob = artists[1];
    expect(ann.id, 10, reason: 'id of the artist\'s first song in library order');
    expect(ann.albums.map((a) => a.title), ['Zed']);
    expect(ann.songs.map((s) => s.id), [1, 3]);
    expect(bob.id, 20);
    expect(bob.albums.map((a) => a.title), ['alpha', 'Zed']);
    expect(bob.songs.map((s) => s.id), [4, 2]);
  });

  test('caseInsensitiveCompare orders like toLowerCase', () {
    final names = ['beta', 'Alpha', 'alpha2', 'Gamma', 'BETA'];
    final cmp = caseInsensitiveCompare();
    for (final a in names) {
      for (final b in names) {
        expect(cmp(a, b).sign, a.toLowerCase().compareTo(b.toLowerCase()).sign);
      }
    }
  });
}
