import 'package:audifac/models/song.dart';
import 'package:audifac/models/song_features.dart';
import 'package:flutter_test/flutter_test.dart';

Song _song({int size = 1000, int modified = 5}) => Song(
      id: 1,
      uri: 'content://media/external/audio/media/1',
      path: '/storage/emulated/0/Music/a.mp3',
      title: 'a',
      artist: 'b',
      artistId: 1,
      album: 'c',
      albumId: 1,
      duration: const Duration(minutes: 3),
      dateAdded: DateTime(2024),
      sizeBytes: size,
      modifiedMs: modified,
    );

void main() {
  test('from native, JSON round trip, describes the file it came from', () {
    final f = SongFeatures.fromNative({
      'bpm': 112.4,
      'confidence': 0.4,
      'groove': 81,
      'bassPunch': 70,
      'energy': 66,
      'danceability': 84,
      'excerptEnergy': [40, 70, 75],
    }, _song());
    final back = SongFeatures.decode(f.encode());
    expect((back.bpm, back.groove, back.danceability, back.introEnergy, back.outroEnergy), (112.4, 81, 84, 40, 75));
    expect(back.describes(_song()), isTrue);
    expect(back.describes(_song(size: 2)), isFalse);
    expect(back.failed, isFalse);
  });

  test('a song that could not be analysed is remembered as failed', () {
    final f = SongFeatures.fromNative(null, _song());
    expect(f.failed, isTrue);
    expect(SongFeatures.decode(f.encode()).failed, isTrue);
    expect(f.describes(_song()), isTrue); // not retried until the file changes
  });
}
