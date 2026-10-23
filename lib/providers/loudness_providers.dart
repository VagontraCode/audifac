import 'dart:async';

import 'package:audio_service/audio_service.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../models/loudness.dart';
import '../models/song.dart';
import 'eq_providers.dart';
import 'library_providers.dart';
import 'player_providers.dart';
import 'user_data_providers.dart';

final volumeMatchingProvider = NotifierProvider<VolumeMatchingNotifier, VolumeMatching>(VolumeMatchingNotifier.new);

class VolumeMatchingNotifier extends Notifier<VolumeMatching> {
  static const key = 'volume';

  @override
  VolumeMatching build() => VolumeMatching.decode(ref.read(bootstrapProvider).values[key]);

  void set(VolumeMatching next) {
    state = next;
    ref.read(databaseProvider).setValue(key, next.encode());
  }
}

/// Library-wide loudness analysis progress (Settings → Volume matching).
class LoudnessScanStatus {
  const LoudnessScanStatus({this.done = 0, this.total = 0});

  final int done;
  final int total;

  bool get running => done < total;
}

final loudnessScanStatusProvider =
    NotifierProvider<LoudnessScanStatusNotifier, LoudnessScanStatus>(LoudnessScanStatusNotifier.new);

class LoudnessScanStatusNotifier extends Notifier<LoudnessScanStatus> {
  @override
  LoudnessScanStatus build() => const LoudnessScanStatus();

  void set(LoudnessScanStatus status) => state = status;
}

/// ReplayGain tags / R128 measurements by file location. Upcoming songs are
/// analysed on their own while volume matching is on; the whole library only
/// when asked.
final loudnessProvider = NotifierProvider<LoudnessNotifier, Map<String, LoudnessInfo>>(LoudnessNotifier.new);

class LoudnessNotifier extends Notifier<Map<String, LoudnessInfo>> {
  /// Waiting files, the next one first.
  final _todo = <Song>[];
  bool _running = false;

  // Library pass bookkeeping (for the progress line).
  int _libraryTotal = 0;
  int _libraryDone = 0;

  @override
  Map<String, LoudnessInfo> build() => ref.read(bootstrapProvider).loudness;

  bool isKnown(Song song) => state[song.location]?.describes(song) ?? false;

  /// Analyses [songs] before anything else waiting (the upcoming tracks).
  void prioritise(List<Song> songs) {
    final missing = songs.where((s) => !isKnown(s)).toList();
    if (missing.isEmpty) return;
    final ids = {for (final s in missing) s.location};
    _todo
      ..removeWhere((s) => ids.contains(s.location))
      ..insertAll(0, missing);
    _pump();
  }

  /// Every library song not analysed yet.
  void analyseLibrary() {
    final missing = ref.read(songsProvider).where((s) => !isKnown(s)).toList();
    final queued = {for (final s in _todo) s.location};
    _todo.addAll(missing.where((s) => !queued.contains(s.location)));
    _libraryTotal = _libraryDone + missing.length;
    _report();
    _pump();
  }

  void cancelLibrary() {
    _todo.clear();
    _libraryTotal = _libraryDone = 0;
    _report();
  }

  void _report() =>
      ref.read(loudnessScanStatusProvider.notifier).set(LoudnessScanStatus(done: _libraryDone, total: _libraryTotal));

  Future<void> _pump() async {
    if (_running) return;
    _running = true;
    try {
      while (_todo.isNotEmpty) {
        final song = _todo.removeAt(0);
        if (isKnown(song)) continue;
        final raw = await ref.read(dspChannelProvider).analyseLoudness([song.location]);
        final info = raw.isEmpty
            ? LoudnessInfo(source: LoudnessSource.none, sizeBytes: song.sizeBytes, modifiedMs: song.modifiedMs)
            : LoudnessInfo.fromNative(raw.first, song);
        state = {...state, song.location: info};
        await ref.read(databaseProvider).putLoudness({song.location: info});
        if (_libraryTotal > 0) {
          _libraryDone++;
          if (_libraryDone >= _libraryTotal) _libraryTotal = _libraryDone = 0;
          _report();
        }
      }
    } catch (_) {
      // Native side unavailable (tests): stop quietly.
      _todo.clear();
      _libraryTotal = _libraryDone = 0;
      _report();
    } finally {
      _running = false;
    }
  }
}

/// The queue as songs, in play order, and where playback is in it.
final playQueueProvider = Provider<({List<Song> songs, int current, bool shuffled})>((ref) {
  final items = ref.watch(queueProvider).value ?? const <MediaItem>[];
  final byId = ref.watch(songsByIdProvider);
  final state = ref.watch(playbackStateProvider.select((s) => (s.value?.queueIndex, s.value?.shuffleMode)));
  final shuffled = state.$2 != null && state.$2 != AudioServiceShuffleMode.none;
  final order = shuffled ? ref.read(audioHandlerProvider).playOrder : [for (var i = 0; i < items.length; i++) i];
  final songs = <Song>[];
  var current = 0;
  for (final i in order) {
    if (i >= items.length) continue;
    final song = byId[items[i].extras?['songId'] as int?];
    if (song == null) continue;
    if (i == state.$1) current = songs.length;
    songs.add(song);
  }
  return (songs: songs, current: current, shuffled: shuffled);
});

/// Keeps the native side's settings and per-file gains in step with the queue,
/// and has the current + next few songs analysed in time.
final volumeSyncProvider = Provider<void>((ref) {
  final settings = ref.watch(volumeMatchingProvider);
  final queue = ref.watch(playQueueProvider);
  final known = ref.watch(loudnessProvider);
  final channel = ref.read(dspChannelProvider);

  channel.setVolumeMatching(settings.toNative(albumInOrder: isAlbumInOrder(queue.songs, shuffled: queue.shuffled)));
  if (settings.mode == VolumeMode.off) return;

  final upcoming = queue.songs.skip(queue.current).take(4).toList();
  scheduleMicrotask(() => ref.read(loudnessProvider.notifier).prioritise(upcoming));
  channel.setGains(gainsFor(queue.songs, known: known, library: ref.read(songsProvider)));
});

/// Crossfade length, album keys for the queue and album-aware shuffle.
final playbackOptionsSyncProvider = Provider<void>((ref) {
  final settings = ref.watch(settingsProvider.select((s) => (s.crossfadeSeconds, s.keepAlbumsTogether, s.bitPerfectUsb, s.hqResampler)));
  ref.read(dspChannelProvider).setResampler(settings.$4);
  ref.read(dspChannelProvider).setBitPerfect(settings.$3);
  final queue = ref.watch(playQueueProvider);
  ref.read(audioHandlerProvider).keepAlbumsTogether = settings.$2;
  ref.read(dspChannelProvider).setCrossfade(settings.$1, {
    if (settings.$1 > 0)
      for (final s in queue.songs) nativeKey(s.uri): s.albumId,
  });
});
