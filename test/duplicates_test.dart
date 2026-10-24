import 'package:audifac/models/audio_info.dart';
import 'package:audifac/models/duplicates.dart';
import 'package:audifac/models/loudness.dart';
import 'package:audifac/models/song.dart';
import 'package:flutter_test/flutter_test.dart';

Song _song(int id, String title, {String artist = 'Daft Punk', int seconds = 240}) => Song(
      id: id,
      uri: 'content://media/external/audio/media/$id',
      path: '/storage/emulated/0/Music/$id',
      title: title,
      artist: artist,
      artistId: 1,
      album: 'b',
      albumId: 1,
      duration: Duration(seconds: seconds),
      dateAdded: DateTime(2024),
      sizeBytes: 1000 + id,
      modifiedMs: 5000,
    );

void main() {
  const mp3 = AudioInfo(codec: 'MP3', sampleRate: 44100, bitrate: 320000);
  const mp3Low = AudioInfo(codec: 'MP3', sampleRate: 44100, bitrate: 128000);
  const flac = AudioInfo(codec: 'FLAC', sampleRate: 44100, bitDepth: 16);
  const hiRes = AudioInfo(codec: 'FLAC', sampleRate: 96000, bitDepth: 24);

  test('normalize ignores case, punctuation and featured artists', () {
    expect(Duplicates.normalize('One More Time!'), 'one more time');
    expect(Duplicates.normalize('Get Lucky (feat. Pharrell Williams)'), 'get lucky');
    expect(Duplicates.normalize('Get Lucky ft. Pharrell'), 'get lucky');
    expect(Duplicates.normalize('Été'), 'été');
  });

  test('groups copies, best first; other lengths and songs stay apart', () {
    final songs = [
      _song(1, 'Get Lucky', seconds: 248),
      _song(2, 'get lucky (feat. Pharrell Williams)', seconds: 249),
      _song(3, 'Get Lucky', seconds: 250),
      _song(4, 'Get Lucky', seconds: 369), // the album version
      _song(5, 'Get Lucky', artist: 'Someone else', seconds: 248),
      _song(6, 'Around the World'),
    ];
    final infos = {1: mp3Low, 2: hiRes, 3: flac, 4: flac, 5: mp3, 6: mp3};
    final groups = Duplicates.find(songs, (s) => infos[s.id]!, (_) => null);
    expect(groups, hasLength(1));
    expect(groups.single.songs.map((s) => s.id), [2, 3, 1]);
  });

  test('a fake-lossless file ranks with lossy ones', () {
    final cut = LoudnessInfo.fromNative({'ok': true, 'cutoffHz': 16000, 'brickwall': true}, _song(1, 'x'));
    expect(Duplicates.rank(flac, cut)[0], Duplicates.rank(mp3, null)[0]);
    expect(Duplicates.rank(flac, null)[0], greaterThan(Duplicates.rank(mp3, null)[0]));
    final songs = [_song(1, 'x'), _song(2, 'x')];
    final groups = Duplicates.find(songs, (s) => s.id == 1 ? flac : mp3, (s) => s.id == 1 ? cut : null);
    // Same tier: the real 320 kbps MP3 beats the FLAC made from a lossy file.
    expect(groups.single.best.id, 2);
    // An MP3 is cut by design; that doesn't hide its bitrate.
    expect(Duplicates.rank(mp3, cut), Duplicates.rank(mp3, null));
  });
}
