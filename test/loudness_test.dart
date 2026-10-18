import 'package:audifac/models/loudness.dart';
import 'package:audifac/models/song.dart';
import 'package:flutter_test/flutter_test.dart';

Song _song(int id, {int albumId = 1, int minutes = 4, String? uri}) => Song(
      id: id,
      uri: uri ?? 'content://media/external/audio/media/$id',
      path: '/storage/emulated/0/Music/$id.flac',
      title: 't$id',
      artist: 'a',
      artistId: 1,
      album: 'b',
      albumId: albumId,
      duration: Duration(minutes: minutes),
      dateAdded: DateTime(2024),
      sizeBytes: 1000 + id,
      modifiedMs: 5000,
    );

LoudnessInfo _scan(Song s, double gain, {double? peak, double? albumGain}) => LoudnessInfo(
      source: LoudnessSource.scan,
      trackGainDb: gain,
      trackPeak: peak,
      albumGainDb: albumGain,
      sizeBytes: s.sizeBytes,
      modifiedMs: s.modifiedMs,
    );

void main() {
  group('combineAlbum', () {
    test('equal tracks: the same gain, loudest peak', () {
      final a = combineAlbum([
        (gainDb: -6.0, peak: 0.8, duration: const Duration(minutes: 3)),
        (gainDb: -6.0, peak: 0.9, duration: const Duration(minutes: 5)),
      ])!;
      expect(a.gainDb, closeTo(-6.0, 1e-9));
      expect(a.peak, 0.9);
    });

    test('loud tracks dominate (power mean, duration weighted)', () {
      // Two equal-length tracks at −10 / 0 dB gain: album gain = −10·log10((10 + 1) / 2) ≈ −7.40 dB.
      final a = combineAlbum([
        (gainDb: -10.0, peak: null, duration: const Duration(minutes: 4)),
        (gainDb: 0.0, peak: null, duration: const Duration(minutes: 4)),
      ])!;
      expect(a.gainDb, closeTo(-7.404, 1e-3));
      expect(a.peak, isNull);
      expect(combineAlbum(const []), isNull);
    });
  });

  group('gainsFor', () {
    test('completes album gain from the other tracks; keeps album tags', () {
      final s1 = _song(1), s2 = _song(2), other = _song(3, albumId: 2);
      final known = {
        s1.location: _scan(s1, -8, peak: 0.7),
        s2.location: _scan(s2, -8, peak: 0.95),
        other.location: _scan(other, -2, albumGain: -3),
      };
      final g = gainsFor([s1, other], known: known, library: [s1, s2, other]);
      expect(g[nativeKey(s1.uri)]!.albumGainDb, closeTo(-8, 1e-9));
      expect(g[nativeKey(s1.uri)]!.albumPeak, 0.95);
      expect(g[nativeKey(other.uri)]!.albumGainDb, -3);
      expect(g.containsKey(nativeKey(s2.uri)), isFalse, reason: 'only the requested songs');
    });

    test('stale or missing analyses are left out', () {
      final s1 = _song(1);
      final stale = LoudnessInfo(source: LoudnessSource.scan, trackGainDb: -5, sizeBytes: 1, modifiedMs: 1);
      expect(gainsFor([s1], known: {s1.location: stale}, library: [s1]), isEmpty);
      expect(gainsFor([s1], known: const {}, library: [s1]), isEmpty);
    });

    test('native key matches the decoded URI the extractor sees', () {
      final s = _song(1, uri: Uri.file('/storage/emulated/0/Music/My Song #1.flac').toString());
      expect(nativeKey(s.uri), 'file:///storage/emulated/0/Music/My Song #1.flac');
    });
  });

  group('settings', () {
    test('applied gain mirrors the native rule', () {
      const gains = (trackGainDb: -6.0, trackPeak: 0.5, albumGainDb: -4.0, albumPeak: 0.6);
      expect(const VolumeMatching().appliedDb(gains, albumInOrder: true), isNull);
      expect(const VolumeMatching(mode: VolumeMode.track).appliedDb(gains, albumInOrder: true), -6.0);
      expect(const VolumeMatching(mode: VolumeMode.album).appliedDb(gains, albumInOrder: false), -4.0);
      expect(const VolumeMatching(mode: VolumeMode.smart).appliedDb(gains, albumInOrder: true), -4.0);
      expect(const VolumeMatching(mode: VolumeMode.smart).appliedDb(gains, albumInOrder: false), -6.0);
      // +8 dB on a −6 dBFS peak: capped at +6.02 dB.
      const quiet = (trackGainDb: 8.0, trackPeak: 0.5, albumGainDb: null, albumPeak: null);
      expect(const VolumeMatching(mode: VolumeMode.track).appliedDb(quiet, albumInOrder: false), closeTo(6.0206, 1e-3));
      expect(const VolumeMatching(mode: VolumeMode.track, untaggedGainDb: -3, preampDb: 2).appliedDb(null, albumInOrder: false),
          -1.0);
    });

    test('native map resolves smart mode', () {
      const v = VolumeMatching(mode: VolumeMode.smart, preampDb: 3);
      expect(v.toNative(albumInOrder: true)['mode'], 'ALBUM');
      expect(v.toNative(albumInOrder: false)['mode'], 'TRACK');
      expect(const VolumeMatching().toNative(albumInOrder: true)['mode'], 'OFF');
    });

    test('round-trips and tolerates junk', () {
      const v = VolumeMatching(mode: VolumeMode.album, preampDb: 4.5, preventClipping: false, untaggedGainDb: -6);
      final back = VolumeMatching.decode(v.encode());
      expect(back.mode, VolumeMode.album);
      expect(back.preampDb, 4.5);
      expect(back.preventClipping, isFalse);
      expect(back.untaggedGainDb, -6);
      expect(VolumeMatching.decode('{nope').mode, VolumeMode.off);
      expect(VolumeMatching.decode('{"mode":"loud","preampDb":99}').preampDb, 15);
    });

    test('smart mode: one album in order', () {
      final album = [_song(1), _song(2), _song(3)];
      expect(isAlbumInOrder(album, shuffled: false), isTrue);
      expect(isAlbumInOrder(album, shuffled: true), isFalse);
      expect(isAlbumInOrder([...album, _song(4, albumId: 9)], shuffled: false), isFalse);
      expect(isAlbumInOrder([_song(1)], shuffled: false), isFalse);
    });
  });

  test('loudness info JSON round-trip', () {
    final s = _song(1);
    final info = LoudnessInfo.fromNative(
      {'ok': true, 'source': 'scan', 'lufs': -11.5, 'trackGainDb': -6.5, 'trackPeak': 0.99},
      s,
    );
    final back = LoudnessInfo.fromJson(info.toJson());
    expect(back.source, LoudnessSource.scan);
    expect(back.lufs, -11.5);
    expect(back.trackGainDb, -6.5);
    expect(back.describes(s), isTrue);
    expect(LoudnessInfo.fromNative({'ok': false}, s).source, LoudnessSource.none);
  });
}
