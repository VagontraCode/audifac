import 'package:audifac/models/loudness.dart';
import 'package:audifac/models/playback_memory.dart';
import 'package:audifac/models/song.dart';
import 'package:flutter_test/flutter_test.dart';

Song _song(int id, {int albumId = 1, String artist = 'Miles Davis'}) => Song(
      id: id,
      uri: 'content://media/external/audio/media/$id',
      path: '/storage/emulated/0/Music/$id.flac',
      title: 't$id',
      artist: artist,
      artistId: 1,
      album: 'b',
      albumId: albumId,
      duration: const Duration(minutes: 4),
      dateAdded: DateTime(2024),
    );

void main() {
  test("an album's memory beats its artist's, field by field", () {
    final m = const PlaybackMemories()
        .withArtist('Miles Davis', const PlaybackMemory(speed: 1.25, volume: VolumeMode.track))
        .withAlbum(1, const PlaybackMemory(volume: VolumeMode.album));
    expect(m.forSong(_song(1)), const PlaybackMemory(speed: 1.25, volume: VolumeMode.album));
    expect(m.forSong(_song(2, albumId: 2)), const PlaybackMemory(speed: 1.25, volume: VolumeMode.track));
    expect(m.forSong(_song(3, albumId: 2, artist: '  MILES davis ')).speed, 1.25); // case / spaces
    expect(m.forSong(_song(4, albumId: 3, artist: 'Coltrane')).isEmpty, isTrue);
  });

  test('clearing every field forgets the entry; encode / decode round trip', () {
    var m = const PlaybackMemories().withAlbum(7, const PlaybackMemory(speed: 1.5));
    m = m.withAlbum(7, m.album(7).copyWith(speed: () => null));
    expect(m.albums, isEmpty);
    final full = const PlaybackMemories()
        .withAlbum(7, const PlaybackMemory(speed: 1.4, volume: VolumeMode.smart))
        .withArtist('Podcast Show', const PlaybackMemory(speed: 2));
    final back = PlaybackMemories.decode(full.encode());
    expect(back.album(7), const PlaybackMemory(speed: 1.4, volume: VolumeMode.smart));
    expect(back.artist('podcast show').speed, 2);
    expect(PlaybackMemories.decode('nonsense').albums, isEmpty);
    expect(PlaybackMemories.decode(null).artists, isEmpty);
  });

  test('gainsFor sends a remembered mode, even for a file not measured yet', () {
    final measured = _song(1);
    final unknown = _song(2);
    final known = {
      measured.location: LoudnessInfo(source: LoudnessSource.tags, trackGainDb: -6, trackPeak: 0.9, sizeBytes: 0, modifiedMs: 0),
    };
    final g = gainsFor([measured, unknown], known: known, library: [measured, unknown], modeFor: (s) => s.id == 2 ? 'OFF' : null);
    expect(g[nativeKey(measured.uri)]?.trackGainDb, -6);
    expect(g[nativeKey(measured.uri)]?.mode, isNull);
    expect(g[nativeKey(unknown.uri)], (trackGainDb: null, trackPeak: null, albumGainDb: null, albumPeak: null, mode: 'OFF'));
    expect(VolumeMatching.nativeMode(VolumeMode.smart, albumInOrder: true), 'ALBUM');
  });
}
