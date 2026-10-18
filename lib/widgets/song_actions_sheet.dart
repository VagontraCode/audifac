import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:hugeicons/hugeicons.dart';

import '../core/theme/app_colors.dart';
import '../features/collection/collection_screen.dart';
import '../features/equalizer/quick_eq_sheet.dart';
import '../models/song.dart';
import '../providers/library_providers.dart';
import '../providers/player_providers.dart';
import '../providers/user_data_providers.dart';
import 'artwork.dart';
import 'playlist_dialogs.dart';
import 'song_info_sheet.dart';

/// An extra, context-specific entry (e.g. "Remove from playlist").
class SongMenuAction {
  const SongMenuAction({required this.icon, required this.label, required this.onSelected});

  final List<List<dynamic>> icon;
  final String label;
  final VoidCallback onSelected;
}

/// Long-press / "more" menu for a song.
class SongActionsSheet extends ConsumerWidget {
  const SongActionsSheet({
    super.key,
    required this.song,
    required this.hostContext,
    this.extraActions = const [],
    this.allowNavigation = true,
  });

  final Song song;

  /// Context of the screen that opened the sheet (for navigation & sheets).
  final BuildContext hostContext;
  final List<SongMenuAction> extraActions;
  final bool allowNavigation;

  static Future<void> show(
    BuildContext context,
    Song song, {
    List<SongMenuAction> extraActions = const [],
    bool allowNavigation = true,
  }) {
    HapticFeedback.selectionClick();
    return showModalBottomSheet<void>(
      context: context,
      useRootNavigator: true,
      isScrollControlled: true,
      builder: (_) => SongActionsSheet(
        song: song,
        hostContext: context,
        extraActions: extraActions,
        allowNavigation: allowNavigation,
      ),
    );
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final handler = ref.read(audioHandlerProvider);
    final isFavorite = ref.watch(isFavoriteProvider(song.id));
    final messenger = ScaffoldMessenger.of(context);
    final palette = context.palette;
    final theme = Theme.of(context);

    void close() => Navigator.of(context).pop();

    void toast(String message) =>
        messenger.showSnackBar(SnackBar(content: Text(message), duration: const Duration(seconds: 2)));

    final album = allowNavigation
        ? ref.watch(albumsProvider).where((a) => a.id == song.albumId).firstOrNull
        : null;
    final artist = allowNavigation
        ? ref.watch(artistsProvider).where((a) => a.name == song.artist).firstOrNull
        : null;

    final actions = <SongMenuAction>[
      SongMenuAction(
        icon: HugeIcons.strokeRoundedTextIndentMore,
        label: 'Play next',
        onSelected: () {
          close();
          handler.playNext([song]);
          toast('Playing "${song.title}" next');
        },
      ),
      SongMenuAction(
        icon: HugeIcons.strokeRoundedQueue01,
        label: 'Add to queue',
        onSelected: () {
          close();
          handler.addToQueue([song]);
          toast('Added to queue');
        },
      ),
      SongMenuAction(
        icon: HugeIcons.strokeRoundedPlayListAdd,
        label: 'Add to playlist…',
        onSelected: () {
          close();
          AddToPlaylistSheet.show(hostContext, [song.id]);
        },
      ),
      SongMenuAction(
        icon: HugeIcons.strokeRoundedFavourite,
        label: isFavorite ? 'Remove from favorites' : 'Add to favorites',
        onSelected: () {
          close();
          final nowFavorite = ref.read(favoritesProvider.notifier).toggle(song.id);
          toast(nowFavorite ? 'Added to favorites' : 'Removed from favorites');
        },
      ),
      SongMenuAction(
        icon: HugeIcons.strokeRoundedSlidersHorizontal,
        label: 'Sound preset…',
        onSelected: () {
          close();
          QuickEqSheet.show(hostContext, song: song, initialScope: ApplyScope.song);
        },
      ),
      SongMenuAction(
        icon: HugeIcons.strokeRoundedInformationCircle,
        label: 'Song info',
        onSelected: () {
          close();
          SongInfoSheet.show(hostContext, song);
        },
      ),
      if (album != null)
        SongMenuAction(
          icon: HugeIcons.strokeRoundedCd,
          label: 'Go to album',
          onSelected: () {
            close();
            CollectionScreen.openAlbum(hostContext, album);
          },
        ),
      if (artist != null)
        SongMenuAction(
          icon: HugeIcons.strokeRoundedUser,
          label: 'Go to artist',
          onSelected: () {
            close();
            CollectionScreen.openArtist(hostContext, artist);
          },
        ),
      ...extraActions.map(
        (a) => SongMenuAction(
          icon: a.icon,
          label: a.label,
          onSelected: () {
            close();
            a.onSelected();
          },
        ),
      ),
    ];

    return SafeArea(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(24, 0, 24, 12),
            child: Row(
              children: [
                Artwork.song(song, size: 56, radius: 12),
                const SizedBox(width: 14),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        song.title,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: theme.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w800),
                      ),
                      Text(
                        '${song.artist} · ${song.album}',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: theme.textTheme.bodyMedium,
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
          Divider(height: 1, color: palette.line),
          Flexible(
            child: ListView(
              shrinkWrap: true,
              padding: const EdgeInsets.symmetric(vertical: 8),
              children: [
                for (final action in actions)
                  ListTile(
                    contentPadding: const EdgeInsets.symmetric(horizontal: 24),
                    leading: HugeIcon(icon: action.icon, color: palette.ink, size: 22),
                    title: Text(action.label, style: const TextStyle(fontWeight: FontWeight.w600)),
                    onTap: action.onSelected,
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
