import 'package:audio_service/audio_service.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:hugeicons/hugeicons.dart';
import '../../l10n/l10n.dart';

import '../../core/audio/queue_logic.dart';
import '../../core/theme/app_colors.dart';
import '../../providers/player_providers.dart';
import '../../widgets/artwork.dart';
import '../../widgets/now_playing_bars.dart';

/// Bottom sheet with the current track and what plays next (in real play
/// order, shuffle included). Drag to reorder, swipe to remove, tap to jump.
class QueueSheet extends ConsumerWidget {
  const QueueSheet({super.key, required this.scrollController});

  final ScrollController scrollController;

  static Future<void> show(BuildContext context) {
    return showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      useRootNavigator: true,
      builder: (_) => DraggableScrollableSheet(
        expand: false,
        initialChildSize: 0.65,
        maxChildSize: 0.92,
        builder: (_, controller) => QueueSheet(scrollController: controller),
      ),
    );
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final handler = ref.read(audioHandlerProvider);
    final queue = ref.watch(queueProvider).value ?? const <MediaItem>[];
    final state = ref.watch(playbackStateProvider).value;
    final current = state?.queueIndex;
    final shuffling = state?.shuffleMode == AudioServiceShuffleMode.all;
    final playing = state?.playing ?? false;
    final theme = Theme.of(context);
    final palette = context.palette;

    final next = upNext(playOrder: handler.playOrder, currentIndex: current)
        .where((i) => i < queue.length)
        .toList();
    final nowPlaying = current != null && current < queue.length ? queue[current] : null;

    Widget titleStyle(String text) => Padding(
          padding: const EdgeInsets.fromLTRB(24, 12, 24, 4),
          child: Text(
            text,
            style: theme.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w800),
          ),
        );

    return ReorderableListView.builder(
      scrollController: scrollController,
      buildDefaultDragHandles: false,
      padding: const EdgeInsets.only(bottom: 24),
      header: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (nowPlaying != null) ...[
            titleStyle(context.l10n.nowPlaying),
            _QueueRow(item: nowPlaying, trailing: NowPlayingBars(playing: playing)),
          ],
          Padding(
            padding: const EdgeInsets.only(right: 24),
            child: Row(
              children: [
                Expanded(child: titleStyle(context.l10n.upNext)),
                if (shuffling)
                  Text(context.l10n.shuffled, style: theme.textTheme.bodySmall?.copyWith(color: palette.inkMuted)),
              ],
            ),
          ),
          if (next.isEmpty)
            Padding(
              padding: const EdgeInsets.fromLTRB(24, 8, 24, 0),
              child: Text(context.l10n.nothingQueued, style: theme.textTheme.bodyMedium),
            ),
        ],
      ),
      itemCount: next.length,
      onReorderItem: (oldIndex, newIndex) {
        if (shuffling || current == null) return;
        HapticFeedback.selectionClick();
        handler.moveInQueue(next[oldIndex], current + 1 + newIndex);
      },
      itemBuilder: (context, i) {
        final seqIndex = next[i];
        final item = queue[seqIndex];
        return Dismissible(
          key: ObjectKey(item),
          direction: DismissDirection.endToStart,
          background: Container(
            color: const Color(0xFFD70015),
            alignment: Alignment.centerRight,
            padding: const EdgeInsets.only(right: 24),
            child: const HugeIcon(icon: HugeIcons.strokeRoundedDelete02, color: Colors.white, size: 22),
          ),
          onDismissed: (_) => handler.removeFromQueue(seqIndex),
          child: _QueueRow(
            item: item,
            onTap: () => handler.skipToQueueItem(seqIndex),
            trailing: shuffling
                ? null
                : ReorderableDragStartListener(
                    index: i,
                    child: Padding(
                      padding: const EdgeInsets.all(8),
                      child: HugeIcon(
                        icon: HugeIcons.strokeRoundedDragDropVertical,
                        color: palette.inkMuted,
                        size: 22,
                      ),
                    ),
                  ),
          ),
        );
      },
    );
  }
}

class _QueueRow extends StatelessWidget {
  const _QueueRow({required this.item, this.trailing, this.onTap});

  final MediaItem item;
  final Widget? trailing;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: context.palette.surface,
      child: ListTile(
        contentPadding: const EdgeInsets.only(left: 24, right: 16),
        onTap: onTap,
        leading: Artwork(
          songId: item.extras?['songId'] as int? ?? 0,
          albumId: item.extras?['albumId'] as int? ?? 0,
          size: 44,
          radius: 8,
        ),
        title: Text(
          item.title,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: const TextStyle(fontWeight: FontWeight.w600),
        ),
        subtitle: Text(item.artist ?? '', maxLines: 1, overflow: TextOverflow.ellipsis),
        trailing: trailing,
      ),
    );
  }
}
