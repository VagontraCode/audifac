import 'package:audio_service/audio_service.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:hugeicons/hugeicons.dart';
import '../l10n/l10n.dart';
import '../providers/cast_provider.dart';
import '../cast/cast_target.dart';

import '../core/theme/app_colors.dart';
import '../features/player/player_screen.dart';
import '../providers/player_providers.dart';
import 'artwork.dart';

/// Docked above the bottom navigation while something is loaded.
/// Tap or swipe up opens the full player; swipe sideways to change track.
class MiniPlayer extends ConsumerWidget {
  const MiniPlayer({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final item = ref.watch(mediaItemProvider).value;
    return AnimatedSwitcher(
      duration: const Duration(milliseconds: 350),
      switchInCurve: Curves.easeOutCubic,
      transitionBuilder: (child, animation) => SizeTransition(
        sizeFactor: animation,
        alignment: Alignment.topCenter,
        child: FadeTransition(opacity: animation, child: child),
      ),
      child: item == null
          ? const SizedBox(width: double.infinity)
          : _MiniPlayerBar(key: const ValueKey('mini-player'), item: item),
    );
  }
}

class _MiniPlayerBar extends ConsumerWidget {
  const _MiniPlayerBar({super.key, required this.item});

  final MediaItem item;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final handler = ref.read(audioHandlerProvider);
    final cast = ref.watch(castProvider);
    final castNotifier = ref.read(castProvider.notifier);
    final playing = cast.active ? cast.status.playback == CastPlayback.playing : ref.watch(isPlayingProvider);
    final theme = Theme.of(context);
    final palette = context.palette;
    final fg = palette.onElevated;

    return GestureDetector(
      onTap: () => PlayerScreen.open(context),
      onVerticalDragEnd: (d) {
        if ((d.primaryVelocity ?? 0) < -250) PlayerScreen.open(context);
      },
      onHorizontalDragEnd: (d) {
        final v = d.primaryVelocity ?? 0;
        if (v < -300) cast.active ? castNotifier.next() : handler.skipToNext();
        if (v > 300) handler.skipToPrevious();
      },
      child: Container(
        margin: const EdgeInsets.fromLTRB(12, 0, 12, 8),
        decoration: BoxDecoration(
          color: palette.elevated,
          borderRadius: BorderRadius.circular(18),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.22),
              blurRadius: 16,
              offset: const Offset(0, 6),
            ),
          ],
        ),
        clipBehavior: Clip.antiAlias,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(10, 10, 6, 8),
              child: Row(
                children: [
                  Hero(
                    tag: PlayerScreen.artworkHeroTag,
                    child: Artwork(
                      songId: item.extras?['songId'] as int? ?? 0,
                      albumId: item.extras?['albumId'] as int? ?? 0,
                      size: 44,
                      radius: 10,
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: AnimatedSwitcher(
                      duration: const Duration(milliseconds: 250),
                      layoutBuilder: (current, previous) => Stack(
                        alignment: Alignment.centerLeft,
                        children: [...previous, ?current],
                      ),
                      child: Column(
                        key: ValueKey(item.id),
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            item.title,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: theme.textTheme.titleSmall?.copyWith(
                              color: fg,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                          Text(
                            item.artist ?? '',
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: theme.textTheme.bodySmall?.copyWith(
                              color: fg.withValues(alpha: 0.65),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                  IconButton(
                    tooltip: playing ? context.l10n.pause : context.l10n.play,
                    onPressed: () {
                      HapticFeedback.selectionClick();
                      cast.active ? castNotifier.togglePlay() : handler.togglePlayPause();
                    },
                    icon: AnimatedSwitcher(
                      duration: const Duration(milliseconds: 200),
                      transitionBuilder: (child, a) => ScaleTransition(scale: a, child: child),
                      child: Icon(
                        playing ? Icons.pause_rounded : Icons.play_arrow_rounded,
                        key: ValueKey(playing),
                        color: fg,
                        size: 32,
                      ),
                    ),
                  ),
                  IconButton(
                    tooltip: context.l10n.next,
                    onPressed: cast.active ? castNotifier.next : handler.skipToNext,
                    icon: HugeIcon(icon: HugeIcons.strokeRoundedNext, color: fg, size: 24),
                  ),
                ],
              ),
            ),
            _ProgressLine(duration: item.duration, color: fg),
          ],
        ),
      ),
    );
  }
}

class _ProgressLine extends ConsumerWidget {
  const _ProgressLine({required this.duration, required this.color});

  final Duration? duration;
  final Color color;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final position = ref.watch(positionProvider).value ?? Duration.zero;
    final total = duration?.inMilliseconds ?? 0;
    final progress = total == 0 ? 0.0 : (position.inMilliseconds / total).clamp(0.0, 1.0);
    return LinearProgressIndicator(
      value: progress,
      minHeight: 2,
      backgroundColor: color.withValues(alpha: 0.12),
      valueColor: AlwaysStoppedAnimation(color),
    );
  }
}
