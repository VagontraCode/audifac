import 'package:audifac/models/song.dart';
import 'package:audifac/models/song_features.dart';
import 'package:audifac/providers/soiree_providers.dart';
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

  test('corrections: tempo replaced, danceability and energy nudged within 0–100', () {
    final f = SongFeatures.fromNative({'bpm': 56.0, 'danceability': 90, 'energy': 60, 'excerptEnergy': [50, 60, 70]}, _song());
    final o = const FeatureOverride().copyWith(bpm: () => 112, nudge: 30);
    final a = f.adjusted(o);
    expect((a.bpm, a.danceability, a.energy), (112.0, 100, 75));
    expect(a.excerptEnergy, [65, 75, 85]);
    expect(f.adjusted(const FeatureOverride()), same(f));
    expect(const FeatureOverride().copyWith(nudge: 500).nudge, 60);
    final all = FeatureOverride.decodeAll(FeatureOverride.encodeAll({'a': o, 'empty': const FeatureOverride()}));
    expect(all.keys, ['a']);
    expect((all['a']!.bpm, all['a']!.nudge), (112.0, 30));
  });

  test('tap tempo uses the taps since the last pause', () {
    expect(tapTempo([0, 500, 1000]), isNull);
    expect(tapTempo([0, 500, 1000, 1500]), 120.0);
    // A pause of 3 s starts over.
    expect(tapTempo([0, 400, 800, 3800, 4345, 4890, 5435]), closeTo(110.1, 0.1));
  });

  test('soirées skip voice notes, recordings, long talks and beatless tracks', () {
    Song at(String path, {int minutes = 3}) => Song(
          id: 2,
          uri: 'content://media/external/audio/media/2',
          path: path,
          title: 't',
          artist: 'a',
          artistId: 1,
          album: 'b',
          albumId: 1,
          duration: Duration(minutes: minutes),
          dateAdded: DateTime(2024),
        );
    expect(SongFeaturesNotifier.worthIt(at('/storage/emulated/0/Music/song.mp3')), isTrue);
    expect(SongFeaturesNotifier.worthIt(at('/storage/emulated/0/Music/talk.mp3', minutes: 12)), isFalse);
    expect(SongFeaturesNotifier.worthIt(at('/storage/emulated/0/Android/media/com.whatsapp/WhatsApp/Media/WhatsApp Audio/a.mp3')), isFalse);
    SongFeatures f(int groove, int bass) =>
        SongFeatures(bpm: 100, confidence: 0, groove: groove, bassPunch: bass, energy: 30, danceability: 30, sizeBytes: 0, modifiedMs: 0);
    expect(noBeat(f(10, 20)), isTrue);
    expect(noBeat(f(10, 60)), isFalse); // a bass line is a beat
    expect(noBeat(f(45, 20)), isFalse);
  });
}
