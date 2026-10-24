import 'package:audifac/models/app_settings.dart';
import 'package:audifac/models/audio_info.dart';
import 'package:audifac/models/loudness.dart';
import 'package:audifac/models/song.dart';
import 'package:audifac/models/song_source.dart';
import 'package:flutter_test/flutter_test.dart';

Song _song(int id) => Song(
      id: id,
      uri: 'content://media/external/audio/media/$id',
      path: '/storage/emulated/0/Music/$id.flac',
      title: 't$id',
      artist: 'a',
      artistId: 1,
      album: 'b',
      albumId: 1,
      duration: const Duration(minutes: 4),
      dateAdded: DateTime(2024),
      sizeBytes: 1000 + id,
      modifiedMs: 5000,
    );

void main() {
  const flac = AudioInfo(codec: 'FLAC', sampleRate: 44100, bitDepth: 16);
  const mp3 = AudioInfo(codec: 'MP3', sampleRate: 44100, bitrate: 320000);
  final s = _song(1);
  final source = SongSource.of(s);
  final cut = LoudnessInfo.fromNative({'ok': true, 'cutoffHz': 16000, 'brickwall': true}, s);
  final full = LoudnessInfo.fromNative({'ok': true, 'cutoffHz': 21800, 'brickwall': false}, s);

  test('fake-lossless filter: lossless files with a lossy-style cut only', () {
    const f = SongFilter(lossyCutoff: true);
    expect(f.isEmpty, isFalse);
    expect(f.matches(flac, source, cut), isTrue);
    expect(f.matches(flac, source, full), isFalse);
    expect(f.matches(flac, source), isFalse); // not analysed
    expect(f.matches(mp3, source, cut), isFalse); // an MP3 is expected to be cut
    expect(SongFilter.decode(f.encode()).lossyCutoff, isTrue);
    expect(const SongFilter().matches(flac, source, cut), isTrue);
  });

  test('audio-detail sorts are flagged', () {
    expect(SongSort.resolution.byAudio, isTrue);
    expect(SongSort.dynamicRange.byAudio, isTrue);
    expect(SongSort.title.byAudio, isFalse);
  });
}
