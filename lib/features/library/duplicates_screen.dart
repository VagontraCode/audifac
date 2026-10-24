import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:hugeicons/hugeicons.dart';

import '../../core/theme/app_colors.dart';
import '../../providers/audio_info_providers.dart';
import '../../providers/player_providers.dart';
import '../../providers/user_data_providers.dart';
import '../../widgets/empty_state.dart';
import '../../widgets/song_labels.dart';
import '../../widgets/song_tile.dart';
import '../../l10n/l10n.dart';
import '../home/folders_screen.dart';

/// Songs found in several files, the best copy first in each group. Only
/// shows them: files are never deleted.
class DuplicatesScreen extends ConsumerWidget {
  const DuplicatesScreen({super.key});

  static Future<void> open(BuildContext context) =>
      Navigator.of(context).push(MaterialPageRoute<void>(builder: (_) => const DuplicatesScreen()));

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final groups = ref.watch(duplicatesProvider);
    final handler = ref.read(audioHandlerProvider);
    // Song rows already show the labels when this is on.
    final showLabels = ref.watch(settingsProvider.select((s) => s.showLabels));
    final theme = Theme.of(context);
    final palette = context.palette;

    return Scaffold(
      appBar: AppBar(
        title: Text(context.l10n.duplicatesTitle, style: const TextStyle(fontWeight: FontWeight.w800)),
        leading: IconButton(
          tooltip: context.l10n.back,
          onPressed: () => Navigator.of(context).pop(),
          icon: HugeIcon(icon: HugeIcons.strokeRoundedArrowLeft01, color: palette.ink, size: 26),
        ),
      ),
      body: groups.isEmpty
          ? Center(
              child: EmptyState(
                icon: HugeIcons.strokeRoundedCopy01,
                title: context.l10n.duplicatesNone,
                message: context.l10n.duplicatesNoneHint,
              ),
            )
          : ListView(
              padding: const EdgeInsets.only(bottom: 24),
              children: [
                Padding(
                  padding: const EdgeInsets.fromLTRB(20, 4, 20, 8),
                  child: Text(
                    context.l10n.duplicatesHint,
                    style: theme.textTheme.bodySmall?.copyWith(color: palette.inkMuted),
                  ),
                ),
                for (final group in groups) ...[
                  Padding(
                    padding: const EdgeInsets.fromLTRB(20, 16, 20, 4),
                    child: Row(
                      children: [
                        Expanded(
                          child: Text(
                            '${group.best.title} · ${group.best.artist}',
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: theme.textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w800),
                          ),
                        ),
                        const SizedBox(width: 8),
                        Text(
                          context.l10n.copies(group.songs.length),
                          style: theme.textTheme.bodySmall?.copyWith(color: palette.inkMuted),
                        ),
                      ],
                    ),
                  ),
                  for (final (i, song) in group.songs.indexed) ...[
                    SongTile(
                      song: song,
                      showAlbum: true,
                      onTap: () => handler.playSongs(group.songs, startIndex: i),
                    ),
                    if (i == 0 || !showLabels)
                      Padding(
                        padding: const EdgeInsets.fromLTRB(88, 0, 20, 6),
                        child: Row(
                          children: [
                            if (i == 0) ...[
                              HugeIcon(
                                icon: HugeIcons.strokeRoundedCheckmarkBadge01,
                                color: palette.lossless,
                                size: 14,
                              ),
                              const SizedBox(width: 4),
                              Text(
                                context.l10n.bestVersion,
                                style: theme.textTheme.labelSmall?.copyWith(
                                  color: palette.lossless,
                                  fontWeight: FontWeight.w800,
                                ),
                              ),
                              const SizedBox(width: 8),
                            ],
                            if (!showLabels) Flexible(child: SongLabels(song: song)),
                          ],
                        ),
                      ),
                    if (song.folder != null)
                      Padding(
                        padding: const EdgeInsets.fromLTRB(88, 0, 20, 8),
                        child: Text(
                          FoldersScreen.label(context.l10n, song.folder!),
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: theme.textTheme.bodySmall?.copyWith(color: palette.inkMuted),
                        ),
                      ),
                  ],
                ],
              ],
            ),
    );
  }
}
