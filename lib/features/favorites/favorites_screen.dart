import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:hugeicons/hugeicons.dart';
import '../../l10n/l10n.dart';

import '../../core/theme/app_colors.dart';
import '../../providers/player_providers.dart';
import '../../providers/user_data_providers.dart';
import '../../widgets/empty_state.dart';
import '../../widgets/entrance.dart';
import '../../widgets/pill_button.dart';
import '../../widgets/song_tile.dart';

/// Liked songs, newest first. Used as a tab root and as a pushed page.
class FavoritesScreen extends ConsumerWidget {
  const FavoritesScreen({super.key, this.pushed = false});

  /// Shows a back button when opened from another screen.
  final bool pushed;

  static Future<void> open(BuildContext context) => Navigator.of(context).push(
        MaterialPageRoute<void>(builder: (_) => const FavoritesScreen(pushed: true)),
      );

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final songs = ref.watch(favoriteSongsProvider);
    final handler = ref.read(audioHandlerProvider);
    final theme = Theme.of(context);
    final palette = context.palette;

    return Scaffold(
      body: SafeArea(
        bottom: false,
        child: EntranceScope(
          child: CustomScrollView(
            slivers: [
              SliverToBoxAdapter(
                child: Padding(
                  padding: EdgeInsets.fromLTRB(pushed ? 8 : 20, 16, 20, 8),
                  child: Row(
                    children: [
                      if (pushed)
                        IconButton(
                          tooltip: context.l10n.back,
                          onPressed: () => Navigator.of(context).pop(),
                          icon: HugeIcon(
                            icon: HugeIcons.strokeRoundedArrowLeft01,
                            color: palette.ink,
                            size: 26,
                          ),
                        ),
                      Expanded(child: Text(context.l10n.favorites, style: theme.textTheme.headlineLarge)),
                    ],
                  ),
                ),
              ),
              if (songs.isEmpty)
                SliverFillRemaining(
                  hasScrollBody: false,
                  child: EmptyState(
                    icon: HugeIcons.strokeRoundedFavourite,
                    title: context.l10n.noFavoritesYet,
                    message: context.l10n.noFavoritesHint,
                  ),
                )
              else ...[
                SliverToBoxAdapter(
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(20, 0, 20, 12),
                    child: Row(
                      children: [
                        Expanded(
                          child: Text(context.l10n.songs(songs.length), style: theme.textTheme.bodyMedium),
                        ),
                        PillButton(
                          icon: HugeIcons.strokeRoundedPlay,
                          label: context.l10n.play,
                          onPressed: () => handler.playSongs(songs),
                        ),
                        const SizedBox(width: 10),
                        PillButton(
                          icon: HugeIcons.strokeRoundedShuffle,
                          label: context.l10n.shuffle,
                          filled: false,
                          onPressed: () => handler.playSongs(songs, shuffle: true),
                        ),
                      ],
                    ),
                  ),
                ),
                SliverList.builder(
                  itemCount: songs.length,
                  itemBuilder: (context, i) => Entrance(
                    index: i,
                    child: SongTile(
                      song: songs[i],
                      showAlbum: true,
                      onTap: () => handler.playSongs(songs, startIndex: i),
                    ),
                  ),
                ),
                const SliverToBoxAdapter(child: SizedBox(height: 16)),
              ],
            ],
          ),
        ),
      ),
    );
  }
}
