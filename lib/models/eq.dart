import 'dart:convert';
import 'dart:math' as math;

/// Same filter set as the native DSP (`Biquad.kt`).
enum EqFilterType {
  peaking('Peak', 'PK'),
  lowShelf('Low shelf', 'LSC'),
  highShelf('High shelf', 'HSC'),
  lowPass('Low-pass', 'LPQ'),
  highPass('High-pass', 'HPQ'),
  notch('Notch', 'NO');

  const EqFilterType(this.label, this.autoEqCode);
  final String label;

  /// Code used in AutoEQ / Equalizer APO "ParametricEQ.txt" files.
  final String autoEqCode;

  bool get hasGain => this == peaking || this == lowShelf || this == highShelf;

  String get nativeName => switch (this) {
        peaking => 'PEAKING',
        lowShelf => 'LOW_SHELF',
        highShelf => 'HIGH_SHELF',
        lowPass => 'LOW_PASS',
        highPass => 'HIGH_PASS',
        notch => 'NOTCH',
      };
}

class EqBand {
  const EqBand({
    this.type = EqFilterType.peaking,
    required this.frequency,
    this.gainDb = 0,
    this.q = 1.41,
  });

  final EqFilterType type;
  final double frequency;
  final double gainDb;
  final double q;

  static const minFrequency = 20.0;
  static const maxFrequency = 20000.0;
  static const maxGainDb = 24.0;

  EqBand copyWith({EqFilterType? type, double? frequency, double? gainDb, double? q}) => EqBand(
        type: type ?? this.type,
        frequency: (frequency ?? this.frequency).clamp(minFrequency, maxFrequency).toDouble(),
        gainDb: (gainDb ?? this.gainDb).clamp(-maxGainDb, maxGainDb).toDouble(),
        q: (q ?? this.q).clamp(0.1, 20.0).toDouble(),
      );

  Map<String, Object> toJson() => {'type': type.name, 'f': frequency, 'g': gainDb, 'q': q};

  Map<String, Object> toNative() => {
        'type': type.nativeName,
        'frequency': frequency,
        'gainDb': type.hasGain ? gainDb : 0.0,
        'q': q,
      };

  factory EqBand.fromJson(Map<String, dynamic> j) => EqBand(
        type: EqFilterType.values.where((t) => t.name == j['type']).firstOrNull ?? EqFilterType.peaking,
        frequency: (j['f'] as num).toDouble(),
        gainDb: (j['g'] as num?)?.toDouble() ?? 0,
        q: (j['q'] as num?)?.toDouble() ?? 1.41,
      );
}

enum EqPresetKind { sound, device }

/// A named set of filters. Sound presets shape the music to taste; device
/// presets correct a specific pair of headphones / speaker and also carry the
/// output options (crossfeed, balance, mono).
class EqPreset {
  const EqPreset({
    required this.id,
    required this.name,
    required this.kind,
    this.builtIn = false,
    this.graphic = false,
    this.preampDb = 0,
    this.bands = const [],
    this.crossfeed = 0,
    this.balance = 0,
    this.mono = false,
  });

  final String id;
  final String name;
  final EqPresetKind kind;
  final bool builtIn;

  /// Edited with the fixed 10-band sliders (else free parametric bands).
  final bool graphic;
  final double preampDb;
  final List<EqBand> bands;
  final double crossfeed;
  final double balance;
  final bool mono;

  static const maxBands = 20;

  /// 10-band graphic EQ centres (Hz) and their bandwidth (≈ one octave).
  static const graphicFrequencies = [31.0, 62.0, 125.0, 250.0, 500.0, 1000.0, 2000.0, 4000.0, 8000.0, 16000.0];
  static const graphicQ = 1.41;

  bool get isFlat =>
      preampDb == 0 &&
      crossfeed == 0 &&
      balance == 0 &&
      !mono &&
      bands.every((b) => b.type.hasGain && b.gainDb == 0);

  EqPreset copyWith({
    String? id,
    String? name,
    EqPresetKind? kind,
    bool? builtIn,
    bool? graphic,
    double? preampDb,
    List<EqBand>? bands,
    double? crossfeed,
    double? balance,
    bool? mono,
  }) =>
      EqPreset(
        id: id ?? this.id,
        name: name ?? this.name,
        kind: kind ?? this.kind,
        builtIn: builtIn ?? this.builtIn,
        graphic: graphic ?? this.graphic,
        preampDb: preampDb ?? this.preampDb,
        bands: bands ?? this.bands,
        crossfeed: crossfeed ?? this.crossfeed,
        balance: balance ?? this.balance,
        mono: mono ?? this.mono,
      );

  /// A copy the user can edit.
  EqPreset duplicate({required String id, String? name}) =>
      copyWith(id: id, name: name ?? '${this.name} (copy)', builtIn: false);

  static EqPreset graphicPreset(String id, String name, List<double> gains, {bool builtIn = true}) => EqPreset(
        id: id,
        name: name,
        kind: EqPresetKind.sound,
        builtIn: builtIn,
        graphic: true,
        bands: [
          for (var i = 0; i < graphicFrequencies.length; i++)
            EqBand(frequency: graphicFrequencies[i], gainDb: gains[i], q: graphicQ),
        ],
      );

  static EqPreset flatGraphic({required String id, required String name, EqPresetKind kind = EqPresetKind.sound}) =>
      graphicPreset(id, name, List.filled(10, 0.0), builtIn: false).copyWith(kind: kind);

  Map<String, Object?> toJson() => {
        'id': id,
        'name': name,
        'kind': kind.name,
        'graphic': graphic,
        'preamp': preampDb,
        'bands': [for (final b in bands) b.toJson()],
        'crossfeed': crossfeed,
        'balance': balance,
        'mono': mono,
      };

  factory EqPreset.fromJson(Map<String, dynamic> j) => EqPreset(
        id: j['id'] as String,
        name: j['name'] as String? ?? 'Preset',
        kind: j['kind'] == 'device' ? EqPresetKind.device : EqPresetKind.sound,
        graphic: j['graphic'] as bool? ?? false,
        preampDb: (j['preamp'] as num?)?.toDouble() ?? 0,
        bands: [
          for (final b in (j['bands'] as List? ?? const []).cast<Map<String, dynamic>>()) EqBand.fromJson(b),
        ],
        crossfeed: (j['crossfeed'] as num?)?.toDouble() ?? 0,
        balance: (j['balance'] as num?)?.toDouble() ?? 0,
        mono: j['mono'] as bool? ?? false,
      );

  String encode() => jsonEncode(toJson());

  // --- AutoEQ / Equalizer APO "ParametricEQ.txt" -----------------------------

  /// `Preamp: -6.4 dB` / `Filter 1: ON PK Fc 105 Hz Gain -2.3 dB Q 0.70`.
  String toAutoEq() {
    final out = StringBuffer('Preamp: ${preampDb.toStringAsFixed(1)} dB\n');
    for (final (i, b) in bands.indexed) {
      out.write('Filter ${i + 1}: ON ${b.type.autoEqCode} Fc ${_num(b.frequency)} Hz');
      if (b.type.hasGain) out.write(' Gain ${b.gainDb.toStringAsFixed(1)} dB');
      out.write(' Q ${b.q.toStringAsFixed(2)}\n');
    }
    return out.toString();
  }

  static String _num(double v) => v == v.roundToDouble() ? '${v.round()}' : v.toStringAsFixed(1);

  /// Parses AutoEQ's ParametricEQ.txt (also Equalizer APO configs). Returns
  /// null when no filter could be read.
  static EqPreset? fromAutoEq(String text, {required String id, required String name, EqPresetKind kind = EqPresetKind.device}) {
    var preamp = 0.0;
    final bands = <EqBand>[];
    final preampRe = RegExp(r'^\s*Preamp:\s*(-?[\d.]+)\s*dB', caseSensitive: false);
    final filterRe = RegExp(
      r'^\s*Filter\s*\d*\s*:\s*(ON|OFF)\s+([A-Z]+)\s+Fc\s+([\d.]+)\s*Hz(?:\s+Gain\s+(-?[\d.]+)\s*dB)?(?:\s+Q\s+([\d.]+))?',
      caseSensitive: false,
    );
    for (final line in const LineSplitter().convert(text)) {
      final p = preampRe.firstMatch(line);
      if (p != null) {
        preamp = double.tryParse(p.group(1)!) ?? 0;
        continue;
      }
      final f = filterRe.firstMatch(line);
      if (f == null || f.group(1)!.toUpperCase() == 'OFF') continue;
      final type = switch (f.group(2)!.toUpperCase()) {
        'PK' || 'PEQ' => EqFilterType.peaking,
        'LS' || 'LSC' || 'LSQ' => EqFilterType.lowShelf,
        'HS' || 'HSC' || 'HSQ' => EqFilterType.highShelf,
        'LP' || 'LPQ' => EqFilterType.lowPass,
        'HP' || 'HPQ' => EqFilterType.highPass,
        'NO' => EqFilterType.notch,
        _ => null,
      };
      final freq = double.tryParse(f.group(3)!);
      if (type == null || freq == null) continue;
      final defaultQ = type == EqFilterType.peaking ? 1.0 : 0.707;
      bands.add(EqBand(
        type: type,
        frequency: freq,
        gainDb: double.tryParse(f.group(4) ?? '') ?? 0,
        q: double.tryParse(f.group(5) ?? '') ?? defaultQ,
      ));
      if (bands.length == maxBands) break;
    }
    if (bands.isEmpty) return null;
    return EqPreset(id: id, name: name, kind: kind, preampDb: preamp, bands: bands);
  }
}

/// Built-in presets (read-only; duplicate to edit).
abstract final class BuiltInPresets {
  static const deviceNone = EqPreset(id: 'b_device_none', name: 'No correction', kind: EqPresetKind.device, builtIn: true);
  static final soundFlat = EqPreset.graphicPreset('b_flat', 'Flat', List.filled(10, 0.0));

  /// Bands: 31, 62, 125, 250, 500, 1k, 2k, 4k, 8k, 16k Hz.
  static final sound = <EqPreset>[
    soundFlat,
    EqPreset.graphicPreset('b_bass_boost', 'Bass boost', [6, 5, 4, 2, 0, 0, 0, 0, 0, 0]),
    EqPreset.graphicPreset('b_bass_reducer', 'Bass reducer', [-6, -5, -4, -2, 0, 0, 0, 0, 0, 0]),
    EqPreset.graphicPreset('b_treble_boost', 'Treble boost', [0, 0, 0, 0, 0, 0, 1, 3, 5, 6]),
    EqPreset.graphicPreset('b_treble_reducer', 'Treble reducer', [0, 0, 0, 0, 0, 0, -1, -3, -5, -6]),
    EqPreset.graphicPreset('b_vocal', 'Vocal', [-2, -2, -1, 0, 2, 4, 4, 2, 0, -1]),
    EqPreset.graphicPreset('b_rock', 'Rock', [4, 3, 2, 0, -1, -1, 1, 2, 3, 4]),
    EqPreset.graphicPreset('b_pop', 'Pop', [-1, 0, 2, 3, 3, 1, 0, -1, -1, -1]),
    EqPreset.graphicPreset('b_jazz', 'Jazz', [3, 2, 1, 2, -1, -1, 0, 1, 2, 3]),
    EqPreset.graphicPreset('b_classical', 'Classical', [3, 2, 1, 0, 0, 0, 0, 1, 2, 3]),
    EqPreset.graphicPreset('b_electronic', 'Electronic', [5, 4, 1, 0, -2, 1, 0, 1, 4, 5]),
    EqPreset.graphicPreset('b_hiphop', 'Hip-hop', [5, 4, 2, 3, -1, -1, 1, -1, 2, 3]),
    EqPreset.graphicPreset('b_acoustic', 'Acoustic', [3, 2, 1, 1, 2, 2, 3, 3, 2, 1]),
    EqPreset.graphicPreset('b_loudness', 'Loudness', [6, 4, 1, 0, -1, 0, 0, 1, 4, 5]),
    EqPreset.graphicPreset('b_late_night', 'Late night', [-3, -2, 0, 1, 2, 2, 1, 0, -1, -2]),
    EqPreset.graphicPreset('b_small_speakers', 'Small speakers', [-6, -3, 2, 3, 2, 1, 0, 1, 2, 2]),
    EqPreset.graphicPreset('b_spoken', 'Spoken word', [-4, -3, -1, 1, 3, 4, 3, 1, -1, -3]),
  ];

  static final all = <EqPreset>[deviceNone, ...sound];
}

/// Frequency response maths — the same RBJ cookbook formulas as `Biquad.kt`.
abstract final class EqMath {
  static const referenceRate = 48000.0;

  /// Magnitude response of [bands] at [frequency], in dB.
  static double responseDb(List<EqBand> bands, double frequency, {double sampleRate = referenceRate}) {
    var db = 0.0;
    for (final b in bands) {
      db += _bandDb(b, frequency, sampleRate);
    }
    return db;
  }

  static double _bandDb(EqBand band, double frequency, double fs) {
    final c = coefficients(band, fs);
    final w = 2 * math.pi * frequency / fs;
    // |H(e^jw)| for b0 + b1 z^-1 + b2 z^-2 over 1 + a1 z^-1 + a2 z^-2.
    final cos1 = math.cos(w), sin1 = math.sin(w), cos2 = math.cos(2 * w), sin2 = math.sin(2 * w);
    final numRe = c.b0 + c.b1 * cos1 + c.b2 * cos2;
    final numIm = -(c.b1 * sin1 + c.b2 * sin2);
    final denRe = 1 + c.a1 * cos1 + c.a2 * cos2;
    final denIm = -(c.a1 * sin1 + c.a2 * sin2);
    final mag2 = (numRe * numRe + numIm * numIm) / (denRe * denRe + denIm * denIm);
    return 10 * math.log(mag2) / math.ln10;
  }

  static ({double b0, double b1, double b2, double a1, double a2}) coefficients(EqBand band, double fs) {
    final f0 = band.frequency.clamp(10.0, fs * 0.49);
    final q = band.q.clamp(0.05, 30.0);
    final a = math.pow(10, (band.type.hasGain ? band.gainDb : 0) / 40).toDouble();
    final w0 = 2 * math.pi * f0 / fs;
    final cosW = math.cos(w0);
    final alpha = math.sin(w0) / (2 * q);
    final s = 2 * math.sqrt(a) * alpha;
    final (b0, b1, b2, a0, a1, a2) = switch (band.type) {
      EqFilterType.peaking => (1 + alpha * a, -2 * cosW, 1 - alpha * a, 1 + alpha / a, -2 * cosW, 1 - alpha / a),
      EqFilterType.lowShelf => (
          a * ((a + 1) - (a - 1) * cosW + s),
          2 * a * ((a - 1) - (a + 1) * cosW),
          a * ((a + 1) - (a - 1) * cosW - s),
          (a + 1) + (a - 1) * cosW + s,
          -2 * ((a - 1) + (a + 1) * cosW),
          (a + 1) + (a - 1) * cosW - s,
        ),
      EqFilterType.highShelf => (
          a * ((a + 1) + (a - 1) * cosW + s),
          -2 * a * ((a - 1) + (a + 1) * cosW),
          a * ((a + 1) + (a - 1) * cosW - s),
          (a + 1) - (a - 1) * cosW + s,
          2 * ((a - 1) - (a + 1) * cosW),
          (a + 1) - (a - 1) * cosW - s,
        ),
      EqFilterType.lowPass => ((1 - cosW) / 2, 1 - cosW, (1 - cosW) / 2, 1 + alpha, -2 * cosW, 1 - alpha),
      EqFilterType.highPass => ((1 + cosW) / 2, -(1 + cosW), (1 + cosW) / 2, 1 + alpha, -2 * cosW, 1 - alpha),
      EqFilterType.notch => (1.0, -2 * cosW, 1.0, 1 + alpha, -2 * cosW, 1 - alpha),
    };
    return (b0: b0 / a0, b1: b1 / a0, b2: b2 / a0, a1: a1 / a0, a2: a2 / a0);
  }

  /// Log-spaced frequencies from 20 Hz to 20 kHz.
  static List<double> logFrequencies(int count) => [
        for (var i = 0; i < count; i++) 20 * math.pow(1000, i / (count - 1)).toDouble(),
      ];

  /// Highest boost of [bands] across the audible range (≥ 0 dB).
  static double maxBoostDb(List<EqBand> bands) {
    if (bands.isEmpty) return 0;
    var max = 0.0;
    for (final f in logFrequencies(240)) {
      max = math.max(max, responseDb(bands, f));
    }
    return max;
  }
}

/// A known output (headphones, speaker…) and the correction used with it.
class EqDevice {
  const EqDevice({
    required this.key,
    required this.name,
    required this.kind,
    required this.presetId,
    this.irPath,
    this.irName,
  });

  /// `speaker`, `wired`, `bt:<product name>`, `usb:<product name>`.
  final String key;
  final String name;

  /// speaker / wired / bluetooth / usb.
  final String kind;
  final String presetId;

  /// Impulse response (app's own copy of a WAV) convolved for this output.
  final String? irPath;
  final String? irName;

  EqDevice copyWith({String? presetId}) =>
      EqDevice(key: key, name: name, kind: kind, presetId: presetId ?? this.presetId, irPath: irPath, irName: irName);

  /// With [path] / [name] as its impulse response (null: none).
  EqDevice withImpulseResponse(String? path, String? name) =>
      EqDevice(key: key, name: this.name, kind: kind, presetId: presetId, irPath: path, irName: path == null ? null : name);

  Map<String, Object> toJson() => {
        'key': key,
        'name': name,
        'kind': kind,
        'preset': presetId,
        if (irPath != null) 'ir': irPath!,
        if (irName != null) 'irName': irName!,
      };

  factory EqDevice.fromJson(Map<String, dynamic> j) => EqDevice(
        key: j['key'] as String,
        name: j['name'] as String? ?? j['key'] as String,
        kind: j['kind'] as String? ?? 'speaker',
        presetId: j['preset'] as String? ?? BuiltInPresets.deviceNone.id,
        irPath: j['ir'] as String?,
        irName: j['irName'] as String?,
      );

  factory EqDevice.fromNative(Map<dynamic, dynamic> m) => EqDevice(
        key: m['key'] as String? ?? 'speaker',
        name: m['name'] as String? ?? 'Phone speaker',
        kind: m['kind'] as String? ?? 'speaker',
        presetId: BuiltInPresets.deviceNone.id,
      );
}

/// Global tone controls, applied on top of both layers.
class Tone {
  const Tone({this.bassDb = 0, this.trebleDb = 0, this.tiltDb = 0, this.loudness = false});

  /// Low shelf at 105 Hz, −12…+12 dB.
  final double bassDb;

  /// High shelf at 9 kHz, −12…+12 dB.
  final double trebleDb;

  /// Whole-spectrum tilt around 1 kHz, −6…+6 dB (positive: brighter).
  final double tiltDb;

  /// Loudness compensation: bass / treble follow the volume (done natively).
  final bool loudness;

  static const maxDb = 12.0;
  static const maxTiltDb = 6.0;

  bool get isNeutral => bassDb == 0 && trebleDb == 0 && tiltDb == 0 && !loudness;

  Tone copyWith({double? bassDb, double? trebleDb, double? tiltDb, bool? loudness}) => Tone(
        bassDb: bassDb ?? this.bassDb,
        trebleDb: trebleDb ?? this.trebleDb,
        tiltDb: tiltDb ?? this.tiltDb,
        loudness: loudness ?? this.loudness,
      );

  /// The shelves that make the tone (none when neutral).
  List<EqBand> get bands => [
        if (bassDb != 0) EqBand(type: EqFilterType.lowShelf, frequency: 105, gainDb: bassDb, q: 0.707),
        if (trebleDb != 0) EqBand(type: EqFilterType.highShelf, frequency: 9000, gainDb: trebleDb, q: 0.707),
        // A tilt: half down below 1 kHz, half up above (gentle slopes).
        if (tiltDb != 0) EqBand(type: EqFilterType.lowShelf, frequency: 1000, gainDb: -tiltDb / 2, q: 0.5),
        if (tiltDb != 0) EqBand(type: EqFilterType.highShelf, frequency: 1000, gainDb: tiltDb / 2, q: 0.5),
      ];

  Map<String, Object> toJson() => {'bass': bassDb, 'treble': trebleDb, 'tilt': tiltDb, 'loudness': loudness};

  factory Tone.fromJson(Map<String, dynamic>? j) => j == null
      ? const Tone()
      : Tone(
          bassDb: ((j['bass'] as num?)?.toDouble() ?? 0).clamp(-maxDb, maxDb),
          trebleDb: ((j['treble'] as num?)?.toDouble() ?? 0).clamp(-maxDb, maxDb),
          tiltDb: ((j['tilt'] as num?)?.toDouble() ?? 0).clamp(-maxTiltDb, maxTiltDb),
          loudness: j['loudness'] as bool? ?? false,
        );
}

/// Global stereo tools, applied on top of both layers.
class Stereo {
  const Stereo({this.width = 1, this.delayMs = 0, this.invertLeft = false, this.invertRight = false});

  /// 0 = mono, 1 = as recorded, 2 = twice the side signal.
  final double width;

  /// Positive delays the right channel, negative the left (speakers at
  /// different distances: ~2.9 ms per metre).
  final double delayMs;
  final bool invertLeft;
  final bool invertRight;

  static const maxWidth = 2.0;
  static const maxDelayMs = 20.0;

  bool get isNeutral => width == 1 && delayMs == 0 && !invertLeft && !invertRight;

  Stereo copyWith({double? width, double? delayMs, bool? invertLeft, bool? invertRight}) => Stereo(
        width: width ?? this.width,
        delayMs: delayMs ?? this.delayMs,
        invertLeft: invertLeft ?? this.invertLeft,
        invertRight: invertRight ?? this.invertRight,
      );

  Map<String, Object> toJson() => {'width': width, 'delay': delayMs, 'invL': invertLeft, 'invR': invertRight};

  factory Stereo.fromJson(Map<String, dynamic>? j) => j == null
      ? const Stereo()
      : Stereo(
          width: ((j['width'] as num?)?.toDouble() ?? 1).clamp(0, maxWidth),
          delayMs: ((j['delay'] as num?)?.toDouble() ?? 0).clamp(-maxDelayMs, maxDelayMs),
          invertLeft: j['invL'] as bool? ?? false,
          invertRight: j['invR'] as bool? ?? false,
        );
}

class EqSettings {
  const EqSettings({
    this.enabled = false,
    this.defaultSoundId = 'b_flat',
    this.askOnPlay = true,
    this.autoPreamp = true,
    this.devices = const {},
    this.tone = const Tone(),
    this.stereo = const Stereo(),
    this.linearPhase = false,
    this.compressor = 0,
  });

  final bool enabled;
  final String defaultSoundId;

  /// Offer a preset choice when a new queue starts and no rule decides.
  final bool askOnPlay;

  /// Lower the preamp by the largest boost so boosts never clip.
  final bool autoPreamp;

  /// Known outputs by key, with their correction preset.
  final Map<String, EqDevice> devices;

  /// Bass / treble / tilt / loudness on top of the presets.
  final Tone tone;

  /// Width / delay / polarity on top of the presets.
  final Stereo stereo;

  /// Run the EQ as one linear-phase FIR (no phase shift; ~0.1 s more delay).
  final bool linearPhase;

  /// Dynamic range compression: 0 off, 1 light, 2 medium, 3 strong.
  final int compressor;

  EqSettings copyWith({
    bool? enabled,
    String? defaultSoundId,
    bool? askOnPlay,
    bool? autoPreamp,
    Map<String, EqDevice>? devices,
    Tone? tone,
    Stereo? stereo,
    bool? linearPhase,
    int? compressor,
  }) =>
      EqSettings(
        enabled: enabled ?? this.enabled,
        defaultSoundId: defaultSoundId ?? this.defaultSoundId,
        askOnPlay: askOnPlay ?? this.askOnPlay,
        autoPreamp: autoPreamp ?? this.autoPreamp,
        devices: devices ?? this.devices,
        tone: tone ?? this.tone,
        stereo: stereo ?? this.stereo,
        linearPhase: linearPhase ?? this.linearPhase,
        compressor: compressor ?? this.compressor,
      );

  String encode() => jsonEncode({
        'enabled': enabled,
        'default': defaultSoundId,
        'ask': askOnPlay,
        'autoPreamp': autoPreamp,
        'devices': [for (final d in devices.values) d.toJson()],
        'tone': tone.toJson(),
        'stereo': stereo.toJson(),
        'linearPhase': linearPhase,
        'compressor': compressor,
      });

  static EqSettings decode(String? raw) {
    if (raw == null) return const EqSettings();
    try {
      final j = jsonDecode(raw) as Map<String, dynamic>;
      final devices = [
        for (final d in (j['devices'] as List? ?? const []).cast<Map<String, dynamic>>()) EqDevice.fromJson(d),
      ];
      return EqSettings(
        enabled: j['enabled'] as bool? ?? false,
        defaultSoundId: j['default'] as String? ?? 'b_flat',
        askOnPlay: j['ask'] as bool? ?? true,
        autoPreamp: j['autoPreamp'] as bool? ?? true,
        devices: {for (final d in devices) d.key: d},
        tone: Tone.fromJson(j['tone'] as Map<String, dynamic>?),
        stereo: Stereo.fromJson(j['stereo'] as Map<String, dynamic>?),
        linearPhase: j['linearPhase'] as bool? ?? false,
        compressor: ((j['compressor'] as num?)?.toInt() ?? 0).clamp(0, 3),
      );
    } catch (_) {
      return const EqSettings();
    }
  }
}

/// What the native DSP receives: device correction + sound preset combined.
Map<String, Object> combineForNative({
  required bool enabled,
  required EqPreset device,
  required EqPreset sound,
  required bool autoPreamp,
  Tone tone = const Tone(),
  Stereo stereo = const Stereo(),
  String? irPath,
  bool linearPhase = false,
  int compressor = 0,
}) {
  final bands = [...device.bands, ...sound.bands, ...tone.bands];
  var preamp = device.preampDb + sound.preampDb;
  // Enough headroom for the biggest boost — without stacking on top of a
  // preamp the preset already has (AutoEQ profiles include one).
  if (autoPreamp) preamp = math.min(preamp, -EqMath.maxBoostDb(bands));
  return {
    'enabled': enabled,
    'preampDb': preamp,
    'bands': [for (final b in bands) b.toNative()],
    'balance': device.balance,
    'mono': device.mono,
    'crossfeed': device.crossfeed,
    'limiter': true,
    'loudness': tone.loudness,
    'width': stereo.width,
    'delayMs': stereo.delayMs,
    'invertLeft': stereo.invertLeft,
    'invertRight': stereo.invertRight,
    if (irPath != null) 'irPath': irPath,
    'linearPhase': linearPhase,
    'compressor': compressor,
  };
}
