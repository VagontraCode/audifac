import 'dart:async';

import 'package:audio_service/audio_service.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../core/audio/queue_logic.dart';
import '../models/saved_session.dart';
import '../models/song.dart';
import 'library_providers.dart';
import 'player_providers.dart';
import 'user_data_providers.dart';

/// Keeps playback and the database in sync:
///  - restores the last queue + position once the library is loaded,
///  - saves the queue / position as they change,
///  - records "recently played".
///
/// Watched once by the app shell so it lives as long as the app.
final sessionControllerProvider = Provider<void>((ref) {
  final handler = ref.read(audioHandlerProvider);
  final db = ref.read(databaseProvider);
  const key = 'session';

  // Notification / lock-screen artwork for every song.
  handler.artworkFileResolver = ref.read(mediaLibraryProvider).cachedArtworkFile;

  var restored = false;
  var hadQueue = false;
  Timer? saveDebounce;
  Timer? positionTicker;

  Future<void> save() async {
    final items = handler.queue.value;
    final state = handler.playbackState.value;
    if (items.isEmpty) {
      // Dismissed (a queue existed, now it's gone): nothing to restore next time.
      if (hadQueue) await db.deleteValue(key);
      return;
    }
    hadQueue = true;
    if (state.queueIndex == null) return;
    final session = SavedSession(
      songIds: [for (final i in items) i.extras?['songId'] as int? ?? -1],
      index: state.queueIndex!,
      position: handler.position,
      shuffle: state.shuffleMode == AudioServiceShuffleMode.all,
      repeat: repeatModeName(state.repeatMode),
    );
    await db.setValue(key, session.encode());
  }

  void scheduleSave() {
    if (!restored) return; // Don't overwrite the saved session before restoring it.
    saveDebounce?.cancel();
    saveDebounce = Timer(const Duration(seconds: 1), save);
  }

  Future<void> restore() async {
    restored = true;
    if (handler.queue.value.isNotEmpty) return; // Already playing something.
    // From the library itself: derived providers (songsByIdProvider) aren't
    // recomputed yet inside this listener and would still be empty.
    final byId = {for (final s in ref.read(libraryProvider).value ?? const <Song>[]) s.id: s};
    final saved = SavedSession.decode(ref.read(bootstrapProvider).values[key])
        ?.retainWhere(byId.containsKey);
    if (saved == null) return;
    await handler.restoreSession(
      [for (final id in saved.songIds) byId[id]!],
      index: saved.index,
      position: saved.position,
      shuffle: saved.shuffle,
      repeat: repeatModeFromName(saved.repeat),
    );
  }

  // 1. Restore once the library is available (or give up if access is denied).
  ref.listen(libraryProvider, (_, next) {
    if (restored) return;
    if (next.hasValue) {
      restore();
    } else if (next.hasError) {
      restored = true;
    }
  }, fireImmediately: true);

  // 2. Save on queue / track / mode changes, and every few seconds while playing.
  final subscriptions = [
    handler.queue.listen((_) => scheduleSave()),
    handler.mediaItem.listen((_) => scheduleSave()),
    handler.playbackState
        .map((s) => (s.playing, s.shuffleMode, s.repeatMode, s.queueIndex))
        .distinct()
        .listen((s) {
      scheduleSave();
      positionTicker?.cancel();
      if (s.$1) {
        positionTicker = Timer.periodic(const Duration(seconds: 5), (_) => save());
      }
    }),
  ];

  // 3. Recently played: a song counts once it actually plays.
  int? lastRecorded;
  void maybeRecord() {
    final id = ref.read(currentSongIdProvider);
    if (id != null && id != lastRecorded && ref.read(isPlayingProvider)) {
      lastRecorded = id;
      ref.read(recentIdsProvider.notifier).record(id);
    }
  }

  ref.listen(currentSongIdProvider, (_, _) => maybeRecord());
  ref.listen(isPlayingProvider, (_, _) => maybeRecord());

  ref.onDispose(() {
    saveDebounce?.cancel();
    positionTicker?.cancel();
    for (final s in subscriptions) {
      s.cancel();
    }
  });
});
