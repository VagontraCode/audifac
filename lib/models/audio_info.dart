import 'song.dart';

enum AudioQuality {
  hiRes('Hi-Res'),
  lossless('Lossless'),
  lossy('Lossy'),
  unknown('Unknown');

  const AudioQuality(this.label);
  final String label;

  bool get isLossless => this == hiRes || this == lossless;
}

/// Technical details of an audio file, read natively (see `AudioInspector.kt`)
/// or guessed from the MIME type / extension until the file is analysed.
class AudioInfo {
  const AudioInfo({
    required this.codec,
    this.codecMime,
    this.containerMime,
    this.sampleRate,
    this.channels,
    this.bitrate,
    this.bitDepth,
    this.genre,
    this.year,
    this.composer,
    this.albumArtist,
    this.disc,
    this.analysed = true,
    this.sizeBytes = 0,
    this.modifiedMs = 0,
    this.schema = currentSchema,
  });

  /// Display name: FLAC, ALAC, WAV, MP3, AAC, HE-AAC, Opus, Vorbis, AMR-WB…
  final String codec;
  final String? codecMime;
  final String? containerMime;
  final int? sampleRate;
  final int? channels;

  /// Bits per second (average).
  final int? bitrate;
  final int? bitDepth;
  final String? genre;
  final String? year;
  final String? composer;
  final String? albumArtist;
  final String? disc;

  /// False when guessed from the file type (no stream details yet).
  final bool analysed;

  /// The file version this describes (cache validity).
  final int sizeBytes;
  final int modifiedMs;

  /// Analysis logic version; bump [currentSchema] to re-analyse every file
  /// (e.g. after adding a format).
  final int schema;
  static const currentSchema = 5;

  static const losslessCodecs = {
    'FLAC', 'ALAC', 'WAV', 'AIFF', 'TrueHD', 'DSD', 'WMA Lossless', 'APE', 'WavPack', 'TTA',
  };

  /// With some tags replaced (in-app tag edits).
  AudioInfo copyWith({String? genre, String? year, String? albumArtist}) => AudioInfo(
        codec: codec,
        codecMime: codecMime,
        containerMime: containerMime,
        sampleRate: sampleRate,
        channels: channels,
        bitrate: bitrate,
        bitDepth: bitDepth,
        genre: genre ?? this.genre,
        year: year ?? this.year,
        composer: composer,
        albumArtist: albumArtist ?? this.albumArtist,
        disc: disc,
        analysed: analysed,
        sizeBytes: sizeBytes,
        modifiedMs: modifiedMs,
        schema: schema,
      );

  AudioQuality get quality {
    if (!losslessCodecs.contains(codec)) {
      return codec == 'Unknown' ? AudioQuality.unknown : AudioQuality.lossy;
    }
    final hiRes = (sampleRate ?? 0) > 48000 || (bitDepth ?? 0) > 16;
    return hiRes ? AudioQuality.hiRes : AudioQuality.lossless;
  }

  bool describes(Song song) =>
      schema == currentSchema &&
      analysed && sizeBytes == song.sizeBytes && modifiedMs == song.modifiedMs;

  /// Short label for song rows: `MP3 320`, `AAC 256`, `FLAC 16/44.1`, `FLAC 24/96`.
  String get badge {
    // DSD is named by its rate multiple: DSD64 = 2.8224 MHz, DSD128…
    if (codec == 'DSD' && sampleRate != null) return 'DSD${(sampleRate! / 44100).round()}';
    if (quality.isLossless) {
      final rate = sampleRate == null ? null : formatSampleRate(sampleRate!);
      if (bitDepth != null && rate != null) return '$codec $bitDepth/$rate';
      if (rate != null) return '$codec $rate kHz';
      return codec;
    }
    final kbps = kbpsOrNull;
    return kbps == null ? codec : '$codec $kbps';
  }

  int? get kbpsOrNull {
    final b = bitrate;
    if (b == null || b <= 0) return null;
    return (b / 1000).round();
  }

  /// 44100 → "44.1", 48000 → "48", 96000 → "96".
  static String formatSampleRate(int hz) {
    final khz = hz / 1000;
    return khz == khz.roundToDouble() ? '${khz.round()}' : khz.toStringAsFixed(1);
  }

  /// Display codec name from a stream MIME type.
  static String codecFromMime(String? mime, {int? aacProfile, String? containerMime}) {
    switch (mime?.toLowerCase()) {
      case 'audio/flac':
        return 'FLAC';
      case 'audio/alac':
        return 'ALAC';
      case 'audio/raw':
      case 'audio/wav':
      case 'audio/x-wav':
      case 'audio/wave':
        return 'WAV';
      case 'audio/mpeg':
        return 'MP3';
      case 'audio/mpeg-l2':
        return 'MP2';
      case 'audio/mp4a-latm':
      case 'audio/aac':
        return switch (aacProfile) {
          5 => 'HE-AAC',
          29 => 'HE-AACv2',
          _ => 'AAC',
        };
      case 'audio/opus':
        return 'Opus';
      case 'audio/vorbis':
        return 'Vorbis';
      case 'audio/3gpp':
      case 'audio/amr':
        return 'AMR';
      case 'audio/amr-wb':
        return 'AMR-WB';
      case 'audio/ac3':
        return 'AC-3';
      case 'audio/eac3':
      case 'audio/eac3-joc':
        return 'E-AC-3';
      case 'audio/true-hd':
        return 'TrueHD';
      case 'audio/vnd.dts':
        return 'DTS';
      case 'audio/vnd.dts.hd':
        return 'DTS-HD';
      case 'audio/mpeg-l1':
        return 'MP1';
      case 'audio/x-aiff':
        return 'AIFF';
      case 'audio/x-dsd':
        return 'DSD';
      case 'audio/x-ms-wma':
        return 'WMA';
      case 'audio/x-ms-wma-pro':
        return 'WMA Pro';
      case 'audio/x-ms-wma-lossless':
        return 'WMA Lossless';
      case 'audio/x-ape':
        return 'APE';
      case 'audio/x-wavpack':
        return 'WavPack';
      case 'audio/x-tta':
        return 'TTA';
      case null:
        return 'Unknown';
      default:
        final subtype = mime!.split('/').last;
        return subtype.isEmpty ? 'Unknown' : subtype.toUpperCase();
    }
  }

  /// Best guess before the file has been analysed (from MediaStore's MIME
  /// type, else the extension). `.m4a` is guessed as AAC — analysis may
  /// reveal ALAC.
  factory AudioInfo.guess(Song song) {
    final mime = song.mimeType?.toLowerCase();
    final ext = (song.path ?? song.uri).split('.').last.toLowerCase();
    final codec = switch ((mime, ext)) {
      ('audio/flac' || 'audio/x-flac', _) || (_, 'flac') => 'FLAC',
      ('audio/x-wav' || 'audio/wav', _) || (_, 'wav' || 'wave') => 'WAV',
      ('audio/mpeg', _) || (_, 'mp3') => 'MP3',
      ('audio/opus', _) || (_, 'opus') => 'Opus',
      ('audio/mp4' || 'audio/aac' || 'audio/x-m4a', _) || (_, 'm4a' || 'm4b' || 'aac') => 'AAC',
      ('audio/ogg' || 'application/ogg', _) || (_, 'ogg' || 'oga') => 'Vorbis',
      ('audio/amr' || 'audio/3gpp', _) || (_, 'amr' || '3gp' || '3ga') => 'AMR',
      ('audio/amr-wb', _) || (_, 'awb') => 'AMR-WB',
      ('audio/ac3', _) || (_, 'ac3') => 'AC-3',
      ('audio/eac3', _) || (_, 'eac3' || 'ec3') => 'E-AC-3',
      (_, 'mp2' || 'mpa' || 'm2a') => 'MP2',
      (_, 'mp1') => 'MP1',
      ('audio/x-aiff' || 'audio/aiff', _) || (_, 'aif' || 'aiff' || 'aifc') => 'AIFF',
      (_, 'dsf' || 'dff') => 'DSD',
      ('audio/x-ms-wma', _) || (_, 'wma' || 'asf') => 'WMA',
      (_, 'ape') => 'APE',
      (_, 'wv') => 'WavPack',
      (_, 'tta') => 'TTA',
      _ => 'Unknown',
    };
    return AudioInfo(codec: codec, containerMime: song.mimeType, analysed: false);
  }

  /// Android reports AIFF's big-endian PCM as plain "audio/raw" (= WAV).
  static String _aiffFix(String codec, Song song) {
    final ext = (song.path ?? song.uri).split('.').last.toLowerCase();
    return codec == 'WAV' && (ext == 'aif' || ext == 'aiff' || ext == 'aifc') ? 'AIFF' : codec;
  }

  /// From the native `inspectAudio` result.
  static AudioInfo? fromNative(Map<dynamic, dynamic> m, Song song) {
    if (m['ok'] != true) return null;
    int? asInt(Object? v) => (v as num?)?.toInt();
    final codecMime = m['codecMime'] as String?;
    var bitrate = asInt(m['bitrate']);
    // No bitrate in the file: estimate from size and duration.
    final durationMs = asInt(m['durationMs']) ?? song.duration.inMilliseconds;
    if ((bitrate == null || bitrate <= 0) && song.sizeBytes > 0 && durationMs > 0) {
      bitrate = (song.sizeBytes * 8 * 1000 / durationMs).round();
    }
    return AudioInfo(
      codec: _aiffFix(codecFromMime(codecMime, aacProfile: asInt(m['aacProfile'])), song),
      codecMime: codecMime,
      containerMime: m['containerMime'] as String?,
      sampleRate: asInt(m['sampleRate']),
      channels: asInt(m['channels']),
      bitrate: bitrate,
      bitDepth: switch (asInt(m['bitDepth'])) { final b? when b > 0 => b, _ => null },
      genre: m['genre'] as String?,
      year: m['year'] as String?,
      composer: m['composer'] as String?,
      albumArtist: m['albumArtist'] as String?,
      disc: m['disc'] as String?,
      sizeBytes: song.sizeBytes,
      modifiedMs: song.modifiedMs,
    );
  }

  Map<String, Object?> toJson() => {
        'codec': codec,
        'codecMime': codecMime,
        'containerMime': containerMime,
        'sampleRate': sampleRate,
        'channels': channels,
        'bitrate': bitrate,
        'bitDepth': bitDepth,
        'genre': genre,
        'year': year,
        'composer': composer,
        'albumArtist': albumArtist,
        'disc': disc,
        'sizeBytes': sizeBytes,
        'modifiedMs': modifiedMs,
        'schema': schema,
      };

  factory AudioInfo.fromJson(Map<String, dynamic> j) {
    int? asInt(Object? v) => (v as num?)?.toInt();
    return AudioInfo(
      codec: j['codec'] as String? ?? 'Unknown',
      codecMime: j['codecMime'] as String?,
      containerMime: j['containerMime'] as String?,
      sampleRate: asInt(j['sampleRate']),
      channels: asInt(j['channels']),
      bitrate: asInt(j['bitrate']),
      bitDepth: asInt(j['bitDepth']),
      genre: j['genre'] as String?,
      year: j['year'] as String?,
      composer: j['composer'] as String?,
      albumArtist: j['albumArtist'] as String?,
      disc: j['disc'] as String?,
      sizeBytes: asInt(j['sizeBytes']) ?? 0,
      modifiedMs: asInt(j['modifiedMs']) ?? 0,
      schema: asInt(j['schema']) ?? 1,
    );
  }
}
