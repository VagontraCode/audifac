import 'package:audio_service/audio_service.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../core/app_visibility.dart';
import '../core/audio/audio_handler.dart';
import '../data/artwork_colors.dart';
import '../models/song.dart';
import 'library_providers.dart';

/// Overridden in `main()` with the handler returned by `AudioService.init`.
final audioHandlerProvider = Provider<AudifacAudioHandler>(
  (ref) => throw UnimplementedError('audioHandlerProvider must be overridden'),
);

final mediaItemProvider = StreamProvider<MediaItem?>(
  (ref) => ref.watch(audioHandlerProvider).mediaItem,
);

final playbackStateProvider = StreamProvider<PlaybackState>(
  (ref) => ref.watch(audioHandlerProvider).playbackState,
);

final queueProvider = StreamProvider<List<MediaItem>>(
  (ref) => ref.watch(audioHandlerProvider).queue,
);

/// Fine-grained position (up to every 16–200 ms), for the seek bar and
/// lyrics. Nothing while the app is in the background: no one sees it.
final positionProvider = StreamProvider<Duration>(
  (ref) => ref.watch(audioHandlerProvider).positionStream.where((_) => AppVisibility.visible),
);

/// Position once a second (and on seeks / play / pause): enough for the mini
/// player's 2 px progress line, at a fifth of the repaints.
final coarsePositionProvider = StreamProvider<Duration>((ref) {
  final handler = ref.watch(audioHandlerProvider);
  final playing = ref.watch(isPlayingProvider);
  ref.watch(playbackStateProvider.select((s) => s.value?.updatePosition));
  Stream<Duration> ticks() async* {
    yield handler.position;
    if (!playing) return;
    yield* Stream<Duration>.periodic(const Duration(seconds: 1), (_) => handler.position)
        .where((_) => AppVisibility.visible);
  }

  return ticks();
});

/// "Couldn't play …" messages, shown as snackbars by the shell.
final playbackErrorsProvider = StreamProvider<String>(
  (ref) => ref.watch(audioHandlerProvider).errors,
);

final isPlayingProvider = Provider<bool>(
  (ref) => ref.watch(playbackStateProvider).value?.playing ?? false,
);

/// MediaStore id of the song currently loaded in the player, if any.
final currentSongIdProvider = Provider<int?>(
  (ref) => ref.watch(mediaItemProvider).value?.extras?['songId'] as int?,
);

final currentSongProvider = Provider<Song?>((ref) {
  final id = ref.watch(currentSongIdProvider);
  return id == null ? null : ref.watch(songsByIdProvider)[id];
});

/// Seed color of an album's artwork (null when it has none or is grayscale).
/// Cached per album for the session.
final artworkSeedProvider = FutureProvider.family<int?, ({int songId, int albumId})>(
  (ref, key) async {
    final bytes = await ref
        .read(mediaLibraryProvider)
        .artworkFor(songId: key.songId, albumId: key.albumId);
    if (bytes == null) return null;
    try {
      return await extractSeedColor(bytes);
    } catch (_) {
      return null;
    }
  },
);
