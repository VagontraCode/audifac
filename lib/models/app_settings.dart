import 'dart:convert';

import 'package:flutter/material.dart';

import 'audio_info.dart';
import 'song_source.dart';

enum SongSort {
  title('Title'),
  artist('Artist'),
  album('Album'),
  dateAdded('Recently added');

  const SongSort(this.label);
  final String label;
}

/// Songs tab filters. Codecs and categories are OR-ed within their group;
/// the groups are AND-ed together.
class SongFilter {
  const SongFilter({this.quality, this.codecs = const {}, this.categories = const {}});

  /// Null = any quality. [AudioQuality.lossless] also matches Hi-Res.
  final AudioQuality? quality;
  final Set<String> codecs;
  final Set<SourceCategory> categories;

  bool get isEmpty => quality == null && codecs.isEmpty && categories.isEmpty;

  bool matches(AudioInfo info, SongSource source) {
    if (quality != null) {
      final q = info.quality;
      final ok = switch (quality!) {
        AudioQuality.lossless => q.isLossless,
        _ => q == quality,
      };
      if (!ok) return false;
    }
    if (codecs.isNotEmpty && !codecs.contains(info.codec)) return false;
    if (categories.isNotEmpty && !categories.contains(source.category)) return false;
    return true;
  }

  SongFilter copyWith({
    AudioQuality? Function()? quality,
    Set<String>? codecs,
    Set<SourceCategory>? categories,
  }) =>
      SongFilter(
        quality: quality == null ? this.quality : quality(),
        codecs: codecs ?? this.codecs,
        categories: categories ?? this.categories,
      );

  String encode() => jsonEncode({
        'quality': quality?.name,
        'codecs': codecs.toList()..sort(),
        'categories': [for (final c in categories) c.name]..sort(),
      });

  static SongFilter decode(String? raw) {
    if (raw == null) return const SongFilter();
    try {
      final m = jsonDecode(raw) as Map<String, dynamic>;
      return SongFilter(
        quality: AudioQuality.values.where((q) => q.name == m['quality']).firstOrNull,
        codecs: (m['codecs'] as List? ?? const []).cast<String>().toSet(),
        categories: {
          for (final name in (m['categories'] as List? ?? const []).cast<String>())
            ...SourceCategory.values.where((c) => c.name == name),
        },
      );
    } catch (_) {
      return const SongFilter();
    }
  }
}

class AppSettings {
  final ThemeMode themeMode;
  final SongSort songSort;

  /// Audio shorter than this is hidden (0 = show everything).
  final int minDurationSeconds;

  /// Show voice notes and recorder files.
  final bool includeRecordings;

  /// Folders (absolute paths) whose audio is hidden and not scanned.
  final Set<String> excludedFolders;

  /// Source + codec labels under each song.
  final bool showLabels;
  final SongFilter songFilter;

  /// Shuffle keeps each album's tracks together, in order.
  final bool keepAlbumsTogether;

  /// Seconds of crossfade between songs (0 = gapless, no crossfade).
  final int crossfadeSeconds;

  /// UI language: '' = the system's, 'en', 'fr'.
  final String languageCode;

  /// Bit-perfect USB DAC output when nothing needs processing (Android 14+).
  final bool bitPerfectUsb;

  /// Convert songs to the mixer rate with our own high-quality resampler
  /// (speaker and headphone jack; Android's resampler otherwise).
  final bool hqResampler;

  const AppSettings({
    this.themeMode = ThemeMode.system,
    this.songSort = SongSort.title,
    this.minDurationSeconds = 30,
    this.includeRecordings = false,
    this.excludedFolders = const {},
    this.showLabels = true,
    this.songFilter = const SongFilter(),
    this.keepAlbumsTogether = false,
    this.crossfadeSeconds = 0,
    this.languageCode = '',
    this.bitPerfectUsb = false,
    this.hqResampler = false,
  });

  static const crossfadeChoices = [0, 2, 4, 6, 8, 12];

  static const minDurationChoices = [0, 15, 30, 60];

  AppSettings copyWith({
    ThemeMode? themeMode,
    SongSort? songSort,
    int? minDurationSeconds,
    bool? includeRecordings,
    Set<String>? excludedFolders,
    bool? showLabels,
    SongFilter? songFilter,
    bool? keepAlbumsTogether,
    int? crossfadeSeconds,
    String? languageCode,
    bool? bitPerfectUsb,
    bool? hqResampler,
  }) =>
      AppSettings(
        themeMode: themeMode ?? this.themeMode,
        songSort: songSort ?? this.songSort,
        minDurationSeconds: minDurationSeconds ?? this.minDurationSeconds,
        includeRecordings: includeRecordings ?? this.includeRecordings,
        excludedFolders: excludedFolders ?? this.excludedFolders,
        showLabels: showLabels ?? this.showLabels,
        songFilter: songFilter ?? this.songFilter,
        keepAlbumsTogether: keepAlbumsTogether ?? this.keepAlbumsTogether,
        crossfadeSeconds: crossfadeSeconds ?? this.crossfadeSeconds,
        languageCode: languageCode ?? this.languageCode,
        bitPerfectUsb: bitPerfectUsb ?? this.bitPerfectUsb,
        hqResampler: hqResampler ?? this.hqResampler,
      );

  /// Whether [folder] (or one of its parents) is excluded.
  bool isExcluded(String? folder) {
    if (folder == null) return false;
    return excludedFolders.any((e) => folder == e || folder.startsWith('$e/'));
  }

  Map<String, String> toKeyValues() => {
        'themeMode': themeMode.name,
        'songSort': songSort.name,
        'minDurationSeconds': '$minDurationSeconds',
        'includeRecordings': '$includeRecordings',
        'excludedFolders': jsonEncode(excludedFolders.toList()..sort()),
        'showLabels': '$showLabels',
        'songFilter': songFilter.encode(),
        'keepAlbumsTogether': '$keepAlbumsTogether',
        'crossfadeSeconds': '$crossfadeSeconds',
        'languageCode': languageCode,
        'bitPerfectUsb': '$bitPerfectUsb',
        'hqResampler': '$hqResampler',
      };

  factory AppSettings.fromKeyValues(Map<String, String> kv) {
    T byName<T extends Enum>(List<T> values, String? name, T fallback) =>
        values.where((v) => v.name == name).firstOrNull ?? fallback;

    Set<String> folders() {
      try {
        return (jsonDecode(kv['excludedFolders'] ?? '[]') as List).cast<String>().toSet();
      } catch (_) {
        return const {};
      }
    }

    return AppSettings(
      themeMode: byName(ThemeMode.values, kv['themeMode'], ThemeMode.system),
      songSort: byName(SongSort.values, kv['songSort'], SongSort.title),
      minDurationSeconds: int.tryParse(kv['minDurationSeconds'] ?? '') ?? 30,
      includeRecordings: kv['includeRecordings'] == 'true',
      excludedFolders: folders(),
      showLabels: kv['showLabels'] != 'false',
      songFilter: SongFilter.decode(kv['songFilter']),
      keepAlbumsTogether: kv['keepAlbumsTogether'] == 'true',
      crossfadeSeconds: (int.tryParse(kv['crossfadeSeconds'] ?? '') ?? 0).clamp(0, 12),
      languageCode: const {'en', 'fr'}.contains(kv['languageCode']) ? kv['languageCode']! : '',
      bitPerfectUsb: kv['bitPerfectUsb'] == 'true',
      hqResampler: kv['hqResampler'] == 'true',
    );
  }
}
