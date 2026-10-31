import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../models/song.dart';
import '../models/song_features.dart';
import 'eq_providers.dart';
import 'library_providers.dart';
import 'stats_providers.dart';
import 'user_data_providers.dart';

/// Progress of the soirée analysis of the library.
class RhythmStatus {
  const RhythmStatus({this.done = 0, this.total = 0, this.running = false, this.msPerSong});

  final int done;
  final int total;
  final bool running;

  /// Average analysis time on this phone (for the "≈ x min left" estimate).
  final int? msPerSong;

  Duration? get remaining => msPerSong == null ? null : Duration(milliseconds: msPerSong! * (total - done));
}

final rhythmStatusProvider = NotifierProvider<RhythmStatusNotifier, RhythmStatus>(RhythmStatusNotifier.new);

class RhythmStatusNotifier extends Notifier<RhythmStatus> {
  @override
  RhythmStatus build() => const RhythmStatus();

  void set(RhythmStatus s) => state = s;
}

/// Soirée analysis by [Song.key]. Once switched on (the first time the soirée
/// builder opens), the whole library is analysed in the background — songs
/// played most and favourites first — and new songs as they arrive.
final songFeaturesProvider = NotifierProvider<SongFeaturesNotifier, Map<String, SongFeatures>>(SongFeaturesNotifier.new);

class SongFeaturesNotifier extends Notifier<Map<String, SongFeatures>> {
  static const enabledKey = 'soiree_analysis';
  static const _batch = 2;

  bool _running = false;
  bool _again = false;

  @override
  Map<String, SongFeatures> build() {
    _enabled = ref.read(bootstrapProvider).values[enabledKey] == '1';
    return ref.read(bootstrapProvider).songFeatures;
  }

  bool get enabled => _enabled;
  late bool _enabled;

  /// Turns the library analysis on or off (kept across restarts).
  Future<void> setEnabled(bool on) async {
    _enabled = on;
    ref.invalidate(rhythmEnabledProvider);
    await ref.read(databaseProvider).setValue(enabledKey, on ? '1' : '0');
    if (on) unawaited(analyseLibrary());
  }

  /// Turns the library analysis on (the soirée builder opening) and starts it.
  Future<void> enable() => _enabled ? analyseLibrary() : setEnabled(true);

  bool isKnown(Song s) => state[s.key]?.describes(s) ?? false;

  /// Songs worth analysing: music longer than 45 s.
  static bool worthIt(Song s) => s.duration >= const Duration(seconds: 45) && !s.isRecording;

  Future<void> analyseLibrary() async {
    if (!enabled) return;
    if (_running) {
      _again = true;
      return;
    }
    _running = true;
    final status = ref.read(rhythmStatusProvider.notifier);
    try {
      do {
        _again = false;
        final stats = ref.read(songStatsProvider);
        final favorites = ref.read(favoritesProvider).toSet();
        int weight(Song s) => (favorites.contains(s.id) ? 1000 : 0) + (stats[s.id]?.plays ?? 0);
        final todo = ref.read(songsProvider).where((s) => worthIt(s) && !isKnown(s)).toList()
          ..sort((a, b) => weight(b).compareTo(weight(a)));
        var spent = 0;
        for (var i = 0; i < todo.length && _enabled; i += _batch) {
          status.set(RhythmStatus(
            done: i,
            total: todo.length,
            running: true,
            msPerSong: i == 0 ? null : spent ~/ i,
          ));
          final batch = todo.skip(i).take(_batch).toList();
          final watch = Stopwatch()..start();
          final raw = await ref.read(dspChannelProvider).analyseRhythm(batch);
          spent += watch.elapsedMilliseconds;
          final results = {
            for (final (j, s) in batch.indexed) s.key: SongFeatures.fromNative(j < raw.length ? raw[j] : null, s),
          };
          state = {...state, ...results};
          await ref.read(databaseProvider).putSongFeatures(results);
        }
      } while (_again);
    } finally {
      _running = false;
      status.set(const RhythmStatus());
    }
  }
}

/// Keeps the analysis going as the library changes. Watched by the app shell.
final soireeAnalysisControllerProvider = Provider<void>((ref) {
  ref.listen(songsProvider, (_, _) => Future.microtask(ref.read(songFeaturesProvider.notifier).analyseLibrary), fireImmediately: true);
});

/// Whether the library analysis is on (Settings switch).
final rhythmEnabledProvider = Provider<bool>((ref) => ref.read(songFeaturesProvider.notifier).enabled);

/// The owner's corrections (tap tempo, more / less danceable) and what
/// soirées learned, by [Song.key].
final featureOverridesProvider = NotifierProvider<FeatureOverridesNotifier, Map<String, FeatureOverride>>(FeatureOverridesNotifier.new);

class FeatureOverridesNotifier extends Notifier<Map<String, FeatureOverride>> {
  static const key = 'feature_overrides';

  @override
  Map<String, FeatureOverride> build() => FeatureOverride.decodeAll(ref.read(bootstrapProvider).values[key]);

  void update(Song song, FeatureOverride Function(FeatureOverride) change) {
    final next = change(state[song.key] ?? const FeatureOverride());
    state = next.isEmpty ? ({...state}..remove(song.key)) : {...state, song.key: next};
    ref.read(databaseProvider).setValue(key, FeatureOverride.encodeAll(state));
  }
}

/// Analysis with the owner's corrections, by [Song.key]; songs that couldn't
/// be analysed are left out.
final soireeFeaturesProvider = Provider<Map<String, SongFeatures>>((ref) {
  final measured = ref.watch(songFeaturesProvider);
  final overrides = ref.watch(featureOverridesProvider);
  return {
    for (final e in measured.entries)
      if (!e.value.failed) e.key: e.value.adjusted(overrides[e.key]),
  };
});
