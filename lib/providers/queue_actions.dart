import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../models/song.dart';
import 'player_providers.dart';
import 'soiree_plan_provider.dart';

/// What adding to the queue did (for the snackbar).
enum Enqueued { next, end, soireeNext, soireeSpread }

/// Play next / Add to queue from anywhere. While a soirée plays, the songs
/// join its plan instead — right after the current song ([next]) or spread
/// where they fit the rest of the evening — so reading the room keeps them.
Future<Enqueued> enqueueSongs(WidgetRef ref, List<Song> songs, {required bool next}) async {
  final handler = ref.read(audioHandlerProvider);
  final now = ref.read(soireeNowProvider);
  if (now != null && songs.isNotEmpty) {
    final upcoming = ref.read(soireeProvider.notifier).addLive(now + 1, songs, next: next);
    await handler.replaceUpcoming([for (final s in upcoming) s.song]);
    return next ? Enqueued.soireeNext : Enqueued.soireeSpread;
  }
  await (next ? handler.playNext(songs) : handler.addToQueue(songs));
  return next ? Enqueued.next : Enqueued.end;
}
