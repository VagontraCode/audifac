import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:hugeicons/hugeicons.dart';
import '../l10n/l10n.dart';

import '../core/format.dart';
import '../core/theme/app_colors.dart';
import '../models/song.dart';
import '../providers/player_providers.dart';
import '../providers/user_data_providers.dart';
import 'artwork.dart';
import 'now_playing_bars.dart';
import 'song_actions_sheet.dart';
import 'song_labels.dart';

/// A song row. Shows artwork (or a track number inside an album), an
/// animated indicator when it is playing, and a "more" menu.
class SongTile extends ConsumerWidget {
  const SongTile({
    super.key,
    required this.song,
    required this.onTap,
    this.trackNumber,
    this.showAlbum = false,
    this.trailing,
    this.extraActions = const [],
  });

  final Song song;
  final VoidCallback onTap;

  /// When set, a track number replaces the artwork (album view).
  final int? trackNumber;
  final bool showAlbum;

  /// Replaces the duration + "more" button (e.g. a drag handle).
  final Widget? trailing;

  /// Added to the long-press / "more" menu.
  final List<SongMenuAction> extraActions;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final isCurrent = ref.watch(currentSongIdProvider.select((id) => id == song.id));
    final isPlaying = isCurrent && ref.watch(isPlayingProvider);
    final showLabels = ref.watch(settingsProvider.select((s) => s.showLabels));
    final theme = Theme.of(context);
    final palette = context.palette;

    void openMenu() => SongActionsSheet.show(context, song, extraActions: extraActions);

    final leading = trackNumber != null
        ? SizedBox(
            width: 32,
            child: Center(
              child: isCurrent
                  ? NowPlayingBars(playing: isPlaying)
                  : Text(
                      '$trackNumber',
                      style: theme.textTheme.titleSmall?.copyWith(color: palette.inkMuted),
                    ),
            ),
          )
        : Stack(
            alignment: Alignment.center,
            children: [
              Artwork.song(song, size: 52, radius: 10),
              AnimatedOpacity(
                opacity: isCurrent ? 1 : 0,
                duration: const Duration(milliseconds: 200),
                child: Container(
                  width: 52,
                  height: 52,
                  decoration: BoxDecoration(
                    color: Colors.black.withValues(alpha: 0.5),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Center(
                    child: isCurrent ? NowPlayingBars(playing: isPlaying, color: Colors.white) : null,
                  ),
                ),
              ),
            ],
          );

    final subtitle = [song.artist, if (showAlbum) song.album].join(' · ');

    return InkWell(
      onTap: onTap,
      onLongPress: openMenu,
      child: Padding(
        padding: EdgeInsets.fromLTRB(20, 8, trailing == null ? 4 : 12, 8),
        child: Row(
          children: [
            leading,
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    song.title,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: theme.textTheme.titleMedium?.copyWith(
                      fontWeight: isCurrent ? FontWeight.w800 : FontWeight.w600,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    subtitle,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: theme.textTheme.bodyMedium,
                  ),
                  if (showLabels) ...[
                    const SizedBox(height: 4),
                    SongLabels(song: song),
                  ],
                ],
              ),
            ),
            const SizedBox(width: 8),
            ?trailing,
            if (trailing == null) ...[
              Text(
                formatDuration(song.duration),
                style: theme.textTheme.bodySmall?.copyWith(color: palette.inkMuted),
              ),
              IconButton(
                tooltip: context.l10n.more,
                onPressed: openMenu,
                icon: HugeIcon(
                  icon: HugeIcons.strokeRoundedMoreVertical,
                  color: palette.inkMuted,
                  size: 20,
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}
