import 'dart:async';

import 'package:flutter/foundation.dart' show mergeSort;
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../models/audio_info.dart';
import '../models/app_settings.dart';
import '../models/duplicates.dart';
import '../models/song.dart';
import '../models/song_source.dart';
import 'library_providers.dart';
import 'loudness_providers.dart';
import 'user_data_providers.dart';

class AnalysisStatus {
  const AnalysisStatus({this.done = 0, this.total = 0});

  final int done;
  final int total;

  bool get running => done < total;
}

final analysisStatusProvider =
    NotifierProvider<AnalysisStatusNotifier, AnalysisStatus>(AnalysisStatusNotifier.new);

class AnalysisStatusNotifier extends Notifier<AnalysisStatus> {
  @override
  AnalysisStatus build() => const AnalysisStatus();

  void set(AnalysisStatus status) => state = status;
}

/// Codec analysis of every file, keyed by location. Loaded from the database
/// at startup, then completed in the background for new / changed files.
final audioInfoProvider =
    NotifierProvider<AudioInfoNotifier, Map<String, AudioInfo>>(AudioInfoNotifier.new);

class AudioInfoNotifier extends Notifier<Map<String, AudioInfo>> {
  static const _batch = 20;

  bool _running = false;
  List<Song>? _pending;

  @override
  Map<String, AudioInfo> build() {
    ref.listen(libraryProvider, (_, next) {
      final songs = next.value;
      if (songs != null) scheduleMicrotask(() => _analyse(songs));
    }, fireImmediately: true);
    return ref.read(bootstrapProvider).audioInfo;
  }

  bool _isCurrent(Song song) => state[song.location]?.describes(song) ?? false;

  Future<void> _analyse(List<Song> songs) async {
    if (_running) {
      _pending = songs; // Re-run with the newest library when done.
      return;
    }
    _running = true;
    final status = ref.read(analysisStatusProvider.notifier);
    try {
      // One analysis per file (a CUE album is many songs in one file).
      final seen = <String>{};
      final todo = songs.where((s) => !_isCurrent(s) && seen.add(s.location)).toList();
      status.set(AnalysisStatus(total: todo.length));
      for (var i = 0; i < todo.length; i += _batch) {
        final batch = todo.skip(i).take(_batch).toList();
        final results = await _inspect(batch);
        state = {...state, ...results};
        await ref.read(databaseProvider).putAudioInfo(results);
        status.set(AnalysisStatus(done: i + batch.length, total: todo.length));
      }
      await ref.read(databaseProvider).retainAudioInfo({for (final s in songs) s.location});
    } catch (_) {
      status.set(const AnalysisStatus());
    } finally {
      _running = false;
      final next = _pending;
      _pending = null;
      if (next != null) unawaited(_analyse(next));
    }
  }

  Future<Map<String, AudioInfo>> _inspect(List<Song> songs) async {
    final raw = await ref.read(mediaLibraryProvider).inspectAudio([for (final s in songs) s.location]);
    final results = <String, AudioInfo>{};
    for (final (i, song) in songs.indexed) {
      final native = i < raw.length ? AudioInfo.fromNative(raw[i], song) : null;
      // Unreadable: remember the guess for this file version so it isn't
      // retried on every launch.
      final guess = AudioInfo.guess(song);
      results[song.location] = native ??
          AudioInfo(
            codec: guess.codec,
            containerMime: guess.containerMime,
            sizeBytes: song.sizeBytes,
            modifiedMs: song.modifiedMs,
          );
    }
    return results;
  }

  /// Analyses [song] right away (song info sheet opened before the background
  /// pass reached it).
  Future<void> ensure(Song song) async {
    if (_isCurrent(song)) return;
    final results = await _inspect([song]);
    state = {...state, ...results};
    await ref.read(databaseProvider).putAudioInfo(results);
  }
}

/// Analysed info for [song], or a guess from its file type until then.
final songAudioInfoProvider = Provider.family<AudioInfo, Song>((ref, song) {
  final cached = ref.watch(audioInfoProvider.select((m) => m[song.location]));
  final info = cached ?? AudioInfo.guess(song);
  return ref.watch(tagEditsProvider.select((m) => m[song.key]))?.applyInfo(info) ?? info;
});

/// The Songs tab: sorted, then filtered by quality / codec / source.
final filteredSongsProvider = Provider<List<Song>>((ref) {
  final songs = ref.watch(sortedSongsProvider);
  final filter = ref.watch(settingsProvider.select((s) => s.songFilter));
  final sort = ref.watch(settingsProvider.select((s) => s.songSort));
  if (filter.isEmpty && !sort.byAudio) return songs;
  final infos = ref.watch(audioInfoProvider);
  final loudness = ref.watch(loudnessProvider);
  AudioInfo info(Song s) => infos[s.location] ?? AudioInfo.guess(s);
  final out = filter.isEmpty
      ? [...songs]
      : songs.where((s) => filter.matches(info(s), SongSource.of(s), loudness[s.location])).toList();
  if (sort.byAudio) {
    // Highest first; unknown last; the title order (from sortedSongs) breaks ties.
    int key(Song s) {
      final i = info(s);
      return switch (sort) {
        // Lossless first: a 48 kHz MP3 isn't a higher resolution than a 16/44.1 FLAC.
        SongSort.resolution => (i.quality.isLossless ? 1 << 40 : 0) + (i.sampleRate ?? 0) * 64 + (i.bitDepth ?? 0),
        SongSort.bitrate => i.kbpsOrNull ?? 0,
        _ => loudness[s.location]?.dr ?? -1,
      };
    }
    final keys = {for (final s in out) s.location: key(s)};
    mergeSort(out, compare: (a, b) => keys[b.location]!.compareTo(keys[a.location]!));
  }
  return out;
});

/// How many visible songs each filter chip would match.
class FilterCounts {
  const FilterCounts({required this.quality, required this.codecs, required this.categories, this.lossyCutoff = 0});

  final Map<AudioQuality, int> quality;
  final Map<String, int> codecs;
  final Map<SourceCategory, int> categories;

  /// Lossless files cut like a lossy one.
  final int lossyCutoff;
}

final filterCountsProvider = Provider<FilterCounts>((ref) {
  final songs = ref.watch(songsProvider);
  final infos = ref.watch(audioInfoProvider);
  final quality = <AudioQuality, int>{};
  final codecs = <String, int>{};
  final categories = <SourceCategory, int>{};
  for (final s in songs) {
    final info = infos[s.location] ?? AudioInfo.guess(s);
    final q = info.quality;
    quality[q] = (quality[q] ?? 0) + 1;
    if (q == AudioQuality.hiRes) quality[AudioQuality.lossless] = (quality[AudioQuality.lossless] ?? 0) + 1;
    codecs[info.codec] = (codecs[info.codec] ?? 0) + 1;
    final c = SongSource.of(s).category;
    categories[c] = (categories[c] ?? 0) + 1;
  }
  final loudness = ref.watch(loudnessProvider);
  final fake = songs.where((s) => (infos[s.location] ?? AudioInfo.guess(s)).quality.isLossless && (loudness[s.location]?.lossyCutoff ?? false)).length;
  return FilterCounts(quality: quality, codecs: codecs, categories: categories, lossyCutoff: fake);
});

/// Songs found in several files, best copy first.
final duplicatesProvider = Provider<List<DuplicateGroup>>((ref) {
  final songs = ref.watch(songsProvider);
  final infos = ref.watch(audioInfoProvider);
  final loudness = ref.watch(loudnessProvider);
  return Duplicates.find(songs, (s) => infos[s.location] ?? AudioInfo.guess(s), (s) => loudness[s.location]);
});
