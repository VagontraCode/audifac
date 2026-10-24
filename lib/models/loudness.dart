import 'dart:convert';
import 'dart:math' as math;

import 'song.dart';

enum VolumeMode {
  off('Off'),
  track('Track'),
  album('Album'),

  /// Album gain while an album plays in order, track gain otherwise.
  smart('Smart');

  const VolumeMode(this.label);
  final String label;
}

/// Volume matching (ReplayGain) settings.
class VolumeMatching {
  const VolumeMatching({
    this.mode = VolumeMode.off,
    this.preampDb = 0,
    this.preventClipping = true,
    this.untaggedGainDb = 0,
  });

  final VolumeMode mode;

  /// Added to every gain. ReplayGain's −18 LUFS reference is quiet next to
  /// modern masters; +3…+6 dB is common.
  final double preampDb;

  /// Never raise a track past its peak.
  final bool preventClipping;

  /// Gain for files with neither tags nor a scan.
  final double untaggedGainDb;

  VolumeMatching copyWith({VolumeMode? mode, double? preampDb, bool? preventClipping, double? untaggedGainDb}) =>
      VolumeMatching(
        mode: mode ?? this.mode,
        preampDb: preampDb ?? this.preampDb,
        preventClipping: preventClipping ?? this.preventClipping,
        untaggedGainDb: untaggedGainDb ?? this.untaggedGainDb,
      );

  /// The gain the native side applies to a file with [gains] (mirrors
  /// `VolumeMatching.linearGain` in Kotlin), in dB. Null when off.
  double? appliedDb(Gains? gains, {required bool albumInOrder}) {
    final album = switch (mode) {
      VolumeMode.off => null,
      VolumeMode.track => false,
      VolumeMode.album => true,
      VolumeMode.smart => albumInOrder,
    };
    if (album == null) return null;
    final gain = album ? gains?.albumGainDb ?? gains?.trackGainDb : gains?.trackGainDb ?? gains?.albumGainDb;
    final peak = album ? gains?.albumPeak ?? gains?.trackPeak : gains?.trackPeak ?? gains?.albumPeak;
    var db = (gain ?? untaggedGainDb) + preampDb;
    if (preventClipping && gain != null && peak != null && peak > 0) {
      db = math.min(db, -20 * math.log(peak) / math.ln10);
    }
    return db;
  }

  /// What the native side applies: [mode] resolved for the current queue.
  Map<String, Object> toNative({required bool albumInOrder}) => {
        'mode': switch (mode) {
          VolumeMode.off => 'OFF',
          VolumeMode.track => 'TRACK',
          VolumeMode.album => 'ALBUM',
          VolumeMode.smart => albumInOrder ? 'ALBUM' : 'TRACK',
        },
        'preampDb': preampDb,
        'preventClipping': preventClipping,
        'untaggedGainDb': untaggedGainDb,
      };

  Map<String, Object?> toJson() => {
        'mode': mode.name,
        'preampDb': preampDb,
        'preventClipping': preventClipping,
        'untaggedGainDb': untaggedGainDb,
      };

  String encode() => jsonEncode(toJson());

  factory VolumeMatching.fromJson(Map<String, dynamic> j) => VolumeMatching(
        mode: VolumeMode.values.asNameMap()[j['mode']] ?? VolumeMode.off,
        preampDb: ((j['preampDb'] as num?)?.toDouble() ?? 0).clamp(-15, 15).toDouble(),
        preventClipping: j['preventClipping'] as bool? ?? true,
        untaggedGainDb: ((j['untaggedGainDb'] as num?)?.toDouble() ?? 0).clamp(-15, 15).toDouble(),
      );

  static VolumeMatching decode(String? raw) {
    if (raw == null) return const VolumeMatching();
    try {
      return VolumeMatching.fromJson(jsonDecode(raw) as Map<String, dynamic>);
    } catch (_) {
      return const VolumeMatching();
    }
  }
}

enum LoudnessSource { tags, scan, none }

/// A file's loudness, from its ReplayGain / R128 tags or measured (EBU R128).
/// Gains are dB to −18 LUFS; peaks are linear (1.0 = full scale).
class LoudnessInfo {
  const LoudnessInfo({
    required this.source,
    this.lufs,
    this.trackGainDb,
    this.trackPeak,
    this.albumGainDb,
    this.albumPeak,
    this.sizeBytes = 0,
    this.modifiedMs = 0,
    this.scanVersion = currentScanVersion,
    this.dr,
    this.cutoffHz,
    this.brickwall = false,
  });

  /// Bump to re-measure every scanned file. 2: the scanner no longer asks
  /// for float output, which Samsung decoders mislabel (garbage loudness).
  /// 3: dynamic range and spectrum cutoff (tagged files are decoded too).
  /// 4: brick-wall detection that sees through the noise floor.
  static const currentScanVersion = 4;

  final LoudnessSource source;

  /// Measurement logic that produced a scan (tags don't depend on it).
  final int scanVersion;

  /// Measured integrated loudness (scans only).
  final double? lufs;
  final double? trackGainDb;
  final double? trackPeak;
  final double? albumGainDb;
  final double? albumPeak;

  /// The file version this describes.
  final int sizeBytes;
  final int modifiedMs;

  /// Dynamic range (DR14-style), null when unknown.
  final int? dr;

  /// Highest frequency with real content (Hz), and whether it ends in a
  /// brick wall (a lowpass, as lossy encoders apply).
  final int? cutoffHz;
  final bool brickwall;

  /// Cut sharply below 20 kHz: in a lossless file, a sign it was made from a
  /// lossy one ("fake lossless").
  bool get lossyCutoff => brickwall && cutoffHz != null && cutoffHz! < 20000;

  bool describes(Song song) =>
      sizeBytes == song.sizeBytes &&
      modifiedMs == song.modifiedMs &&
      scanVersion >= currentScanVersion;

  static LoudnessInfo fromNative(Map<dynamic, dynamic> m, Song song) {
    double? d(String k) => (m[k] as num?)?.toDouble();
    return LoudnessInfo(
      source: m['ok'] == true
          ? (m['source'] == 'tags' ? LoudnessSource.tags : LoudnessSource.scan)
          : LoudnessSource.none,
      lufs: d('lufs'),
      trackGainDb: d('trackGainDb'),
      trackPeak: d('trackPeak'),
      albumGainDb: d('albumGainDb'),
      albumPeak: d('albumPeak'),
      sizeBytes: song.sizeBytes,
      modifiedMs: song.modifiedMs,
      dr: (m['dr'] as num?)?.toInt(),
      cutoffHz: (m['cutoffHz'] as num?)?.toInt(),
      brickwall: m['brickwall'] == true,
    );
  }

  Map<String, Object?> toJson() => {
        'source': source.name,
        'lufs': lufs,
        'trackGainDb': trackGainDb,
        'trackPeak': trackPeak,
        'albumGainDb': albumGainDb,
        'albumPeak': albumPeak,
        'sizeBytes': sizeBytes,
        'modifiedMs': modifiedMs,
        'scanVersion': scanVersion,
        'dr': dr,
        'cutoffHz': cutoffHz,
        'brickwall': brickwall,
      };

  factory LoudnessInfo.fromJson(Map<String, dynamic> j) {
    double? d(String k) => (j[k] as num?)?.toDouble();
    return LoudnessInfo(
      source: LoudnessSource.values.asNameMap()[j['source']] ?? LoudnessSource.none,
      lufs: d('lufs'),
      trackGainDb: d('trackGainDb'),
      trackPeak: d('trackPeak'),
      albumGainDb: d('albumGainDb'),
      albumPeak: d('albumPeak'),
      sizeBytes: (j['sizeBytes'] as num?)?.toInt() ?? 0,
      modifiedMs: (j['modifiedMs'] as num?)?.toInt() ?? 0,
      scanVersion: (j['scanVersion'] as num?)?.toInt() ?? 1,
      dr: (j['dr'] as num?)?.toInt(),
      cutoffHz: (j['cutoffHz'] as num?)?.toInt(),
      brickwall: j['brickwall'] == true,
    );
  }
}

/// Gains as sent to the native side for one file.
typedef Gains = ({double? trackGainDb, double? trackPeak, double? albumGainDb, double? albumPeak});

/// Album gain from its tracks' gains: the duration-weighted power mean of
/// their loudness (what a whole-album measurement gives, minus gating
/// subtleties), and the loudest peak. Null when no track has a gain.
({double gainDb, double? peak})? combineAlbum(Iterable<({double gainDb, double? peak, Duration duration})> tracks) {
  var energy = 0.0;
  var weight = 0.0;
  double? peak;
  for (final t in tracks) {
    // A missing duration still counts, as one second.
    final w = math.max(1.0, t.duration.inMilliseconds / 1000);
    energy += w * math.pow(10, -t.gainDb / 10);
    weight += w;
    if (t.peak != null) peak = math.max(peak ?? 0, t.peak!);
  }
  if (weight == 0) return null;
  return (gainDb: -10 * math.log(energy / weight) / math.ln10, peak: peak);
}

/// Gains for every song in [songs], album gains completed from the other
/// tracks of the same album in [library] when the file has no album tag.
Map<String, Gains> gainsFor(
  Iterable<Song> songs, {
  required Map<String, LoudnessInfo> known,
  required Iterable<Song> library,
}) {
  final byAlbum = <int, List<Song>>{};
  for (final s in library) {
    byAlbum.putIfAbsent(s.albumId, () => []).add(s);
  }
  final albumCache = <int, ({double gainDb, double? peak})?>{};
  ({double gainDb, double? peak})? album(int albumId) => albumCache.putIfAbsent(albumId, () {
        return combineAlbum([
          for (final s in byAlbum[albumId] ?? const <Song>[])
              if (known[s.location] case final i? when i.trackGainDb != null && i.describes(s))
                (gainDb: i.trackGainDb!, peak: i.trackPeak, duration: s.duration),
        ]);
      });

  return {
    for (final s in songs)
      if (known[s.location] case final i? when i.describes(s) && i.trackGainDb != null)
        nativeKey(s.uri): (
          trackGainDb: i.trackGainDb,
          trackPeak: i.trackPeak,
          albumGainDb: i.albumGainDb ?? album(s.albumId)?.gainDb,
          albumPeak: i.albumGainDb != null ? i.albumPeak : album(s.albumId)?.peak,
        ),
  };
}

/// The key the native extractor tags tracks with (`SourceUri.keyOf`).
String nativeKey(String uri) {
  try {
    return Uri.decodeFull(uri);
  } catch (_) {
    return uri;
  }
}

/// Smart mode: is the queue one album, played in order?
bool isAlbumInOrder(List<Song> queue, {required bool shuffled}) {
  if (shuffled || queue.length < 2) return false;
  final album = queue.first.albumId;
  return queue.every((s) => s.albumId == album);
}
