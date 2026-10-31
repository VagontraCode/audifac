import 'dart:convert';

import 'song.dart';

/// What makes a song danceable (soirée builder), measured on the phone from
/// three excerpts (`RhythmAnalyser.kt`). Scores are 0–100.
class SongFeatures {
  const SongFeatures({
    required this.bpm,
    required this.confidence,
    required this.groove,
    required this.bassPunch,
    required this.energy,
    required this.danceability,
    this.excerptEnergy = const [],
    required this.sizeBytes,
    required this.modifiedMs,
    this.version = currentVersion,
    this.failed = false,
  });

  /// Bump to re-analyse every song (analysis changed).
  static const currentVersion = 1;

  final double bpm;

  /// 0…1: how clearly one tempo stands out.
  final double confidence;
  final int groove;
  final int bassPunch;
  final int energy;
  final int danceability;

  /// Energy of each excerpt (start, middle, end of the song).
  final List<int> excerptEnergy;

  /// The file it was measured from.
  final int sizeBytes;
  final int modifiedMs;
  final int version;

  /// Couldn't be decoded or nearly silent: not tried again until the file changes.
  final bool failed;

  int get introEnergy => excerptEnergy.isEmpty ? energy : excerptEnergy.first;
  int get outroEnergy => excerptEnergy.isEmpty ? energy : excerptEnergy.last;

  bool describes(Song song) => version == currentVersion && sizeBytes == song.sizeBytes && modifiedMs == song.modifiedMs;

  factory SongFeatures.failedFor(Song song) => SongFeatures(
        bpm: 0,
        confidence: 0,
        groove: 0,
        bassPunch: 0,
        energy: 0,
        danceability: 0,
        sizeBytes: song.sizeBytes,
        modifiedMs: song.modifiedMs,
        failed: true,
      );

  /// From `RhythmAnalyser.Result.toMap()`; null map = failed.
  factory SongFeatures.fromNative(Map<dynamic, dynamic>? m, Song song) {
    if (m == null) return SongFeatures.failedFor(song);
    int i(String k) => (m[k] as num?)?.round() ?? 0;
    return SongFeatures(
      bpm: (m['bpm'] as num?)?.toDouble() ?? 0,
      confidence: (m['confidence'] as num?)?.toDouble() ?? 0,
      groove: i('groove'),
      bassPunch: i('bassPunch'),
      energy: i('energy'),
      danceability: i('danceability'),
      excerptEnergy: [for (final e in (m['excerptEnergy'] as List? ?? const [])) (e as num).round()],
      sizeBytes: song.sizeBytes,
      modifiedMs: song.modifiedMs,
    );
  }

  Map<String, Object?> toJson() => {
        'bpm': bpm,
        'confidence': confidence,
        'groove': groove,
        'bassPunch': bassPunch,
        'energy': energy,
        'danceability': danceability,
        'excerptEnergy': excerptEnergy,
        'sizeBytes': sizeBytes,
        'modifiedMs': modifiedMs,
        'version': version,
        if (failed) 'failed': true,
      };

  factory SongFeatures.fromJson(Map<String, dynamic> j) => SongFeatures(
        bpm: (j['bpm'] as num?)?.toDouble() ?? 0,
        confidence: (j['confidence'] as num?)?.toDouble() ?? 0,
        groove: (j['groove'] as num?)?.toInt() ?? 0,
        bassPunch: (j['bassPunch'] as num?)?.toInt() ?? 0,
        energy: (j['energy'] as num?)?.toInt() ?? 0,
        danceability: (j['danceability'] as num?)?.toInt() ?? 0,
        excerptEnergy: [for (final e in (j['excerptEnergy'] as List? ?? const [])) (e as num).toInt()],
        sizeBytes: (j['sizeBytes'] as num?)?.toInt() ?? 0,
        modifiedMs: (j['modifiedMs'] as num?)?.toInt() ?? 0,
        version: (j['version'] as num?)?.toInt() ?? 0,
        failed: j['failed'] == true,
      );

  String encode() => jsonEncode(toJson());

  static SongFeatures decode(String s) => SongFeatures.fromJson(jsonDecode(s) as Map<String, dynamic>);
}

/// The owner's corrections to a song's analysis, and what soirées taught.
class FeatureOverride {
  const FeatureOverride({this.bpm, this.nudge = 0, this.learned = 0});

  /// Tempo set by tap-tempo (fixes half / double-time readings).
  final double? bpm;

  /// "More / less danceable": added to danceability (and half to energy).
  final int nudge;

  /// From soirées: played through at the peak (+), skipped (−).
  final int learned;

  bool get isEmpty => bpm == null && nudge == 0 && learned == 0;

  FeatureOverride copyWith({double? Function()? bpm, int? nudge, int? learned}) => FeatureOverride(
        bpm: bpm == null ? this.bpm : bpm(),
        nudge: (nudge ?? this.nudge).clamp(-60, 60),
        learned: (learned ?? this.learned).clamp(-40, 40),
      );

  Map<String, Object?> toJson() => {'bpm': ?bpm, if (nudge != 0) 'nudge': nudge, if (learned != 0) 'learned': learned};

  factory FeatureOverride.fromJson(Map<String, dynamic> j) => FeatureOverride(
        bpm: (j['bpm'] as num?)?.toDouble(),
        nudge: (j['nudge'] as num?)?.toInt() ?? 0,
        learned: (j['learned'] as num?)?.toInt() ?? 0,
      );

  static Map<String, FeatureOverride> decodeAll(String? s) {
    if (s == null) return const {};
    try {
      final j = jsonDecode(s) as Map<String, dynamic>;
      return {for (final e in j.entries) e.key: FeatureOverride.fromJson((e.value as Map).cast<String, dynamic>())};
    } catch (_) {
      return const {};
    }
  }

  static String encodeAll(Map<String, FeatureOverride> all) =>
      jsonEncode({for (final e in all.entries) if (!e.value.isEmpty) e.key: e.value.toJson()});
}

extension SongFeaturesOverride on SongFeatures {
  /// With [o] applied: the owner's tempo, danceability (and energy) nudged.
  SongFeatures adjusted(FeatureOverride? o) {
    if (o == null || o.isEmpty) return this;
    final delta = o.nudge + o.learned;
    return SongFeatures(
      bpm: o.bpm ?? bpm,
      confidence: o.bpm != null ? 1 : confidence,
      groove: groove,
      bassPunch: bassPunch,
      energy: (energy + delta ~/ 2).clamp(0, 100),
      danceability: (danceability + delta).clamp(0, 100),
      excerptEnergy: [for (final e in excerptEnergy) (e + delta ~/ 2).clamp(0, 100)],
      sizeBytes: sizeBytes,
      modifiedMs: modifiedMs,
      version: version,
      failed: failed,
    );
  }
}

/// Tap tempo: BPM from tap times (ms), using the taps since the last pause
/// of more than 2 s; null with fewer than 4 taps.
double? tapTempo(List<int> tapsMs) {
  var start = tapsMs.length - 1;
  while (start > 0 && tapsMs[start] - tapsMs[start - 1] <= 2000) {
    start--;
  }
  final taps = tapsMs.sublist(start);
  if (taps.length < 4) return null;
  final recent = taps.length > 9 ? taps.sublist(taps.length - 9) : taps;
  final interval = (recent.last - recent.first) / (recent.length - 1);
  return interval <= 0 ? null : (60000 / interval * 10).roundToDouble() / 10;
}
