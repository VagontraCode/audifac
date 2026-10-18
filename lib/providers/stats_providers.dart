import 'dart:async';
import 'dart:convert';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../models/play_stats.dart';
import '../models/song.dart';
import 'library_providers.dart';
import 'player_providers.dart';
import 'user_data_providers.dart';

/// Every listen, oldest first.
final playLogProvider = NotifierProvider<PlayLogNotifier, List<PlayEvent>>(PlayLogNotifier.new);

class PlayLogNotifier extends Notifier<List<PlayEvent>> {
  static const pendingKey = 'pending_listen';

  @override
  List<PlayEvent> build() {
    final boot = ref.read(bootstrapProvider);
    // A listen that was in progress when the app was closed.
    final pending = _decodePending(boot.values[pendingKey]);
    if (pending != null) {
      scheduleMicrotask(() async {
        await ref.read(databaseProvider).addPlays([pending]);
        await ref.read(databaseProvider).setValue(pendingKey, '');
      });
      return [...boot.playLog, pending];
    }
    return boot.playLog;
  }

  Future<void> add(PlayEvent event) async {
    state = [...state, event];
    await ref.read(databaseProvider).addPlays([event]);
  }

  /// From a backup: only listens not already here (same song and start time).
  Future<int> restore(List<PlayEvent> events) async {
    final have = {for (final e in state) (e.songId, e.at.millisecondsSinceEpoch)};
    final fresh = events.where((e) => !have.contains((e.songId, e.at.millisecondsSinceEpoch))).toList();
    if (fresh.isEmpty) return 0;
    state = [...state, ...fresh]..sort((a, b) => a.at.compareTo(b.at));
    await ref.read(databaseProvider).addPlays(fresh);
    return fresh.length;
  }

  Future<void> savePending(PlayEvent? event) =>
      ref.read(databaseProvider).setValue(pendingKey, event == null ? '' : jsonEncode(event.toRow()));

  static PlayEvent? _decodePending(String? raw) {
    if (raw == null || raw.isEmpty) return null;
    try {
      return PlayEvent.fromRow((jsonDecode(raw) as Map).cast<String, Object?>());
    } catch (_) {
      return null;
    }
  }
}

/// All-time plays / listening time / last played per song.
final songStatsProvider = Provider<Map<int, SongStats>>((ref) => songStats(ref.watch(playLogProvider)));

final statsRangeProvider = NotifierProvider<StatsRangeNotifier, StatsRange>(StatsRangeNotifier.new);

class StatsRangeNotifier extends Notifier<StatsRange> {
  @override
  StatsRange build() => StatsRange.month;

  void set(StatsRange range) => state = range;
}

final statsSummaryProvider = Provider<StatsSummary>((ref) {
  final range = ref.watch(statsRangeProvider);
  return StatsSummary.of(
    ref.watch(playLogProvider),
    ref.watch(songsByIdProvider),
    since: range.since(DateTime.now()),
  );
});

/// Watches playback and logs listens. Watched once by the app shell.
final playTrackerProvider = Provider<void>((ref) {
  final handler = ref.read(audioHandlerProvider);
  final tracker = PlayTracker();
  var sincePendingSave = 0;
  Timer? ticker;

  Song? song() => ref.read(currentSongProvider);

  void record(PlayEvent? event) {
    if (event == null) return;
    ref.read(playLogProvider.notifier).add(event);
    ref.read(playLogProvider.notifier).savePending(null);
  }

  void tick() {
    final s = song();
    record(tracker.tick(
      songId: s?.id,
      duration: s?.duration ?? Duration.zero,
      position: handler.position,
      playing: ref.read(isPlayingProvider),
    ));
    if (++sincePendingSave >= 15) {
      sincePendingSave = 0;
      ref.read(playLogProvider.notifier).savePending(tracker.current);
    }
  }

  void onPlaying(bool playing) {
    ticker?.cancel();
    tick();
    if (playing) ticker = Timer.periodic(const Duration(seconds: 1), (_) => tick());
  }

  ref.listen(currentSongIdProvider, (_, _) => tick());
  ref.listen(isPlayingProvider, (_, playing) => onPlaying(playing), fireImmediately: true);
  ref.onDispose(() {
    ticker?.cancel();
    record(tracker.finish());
  });
});
