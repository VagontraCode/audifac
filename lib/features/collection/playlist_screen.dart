import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:hugeicons/hugeicons.dart';
import '../../l10n/l10n.dart';

import '../../core/audio/queue_logic.dart';
import '../../core/format.dart';
import '../../core/theme/app_colors.dart';
import '../../models/m3u.dart';
import '../../providers/library_providers.dart';
import '../../providers/player_providers.dart';
import '../../providers/user_data_providers.dart';
import '../../widgets/empty_state.dart';
import '../../widgets/playlist_dialogs.dart';
import '../../widgets/song_actions_sheet.dart';
import '../../widgets/song_tile.dart';
import 'collection_screen.dart';

/// A user playlist: play / shuffle, drag to reorder, swipe to remove,
/// rename / delete from the menu.
class PlaylistScreen extends ConsumerWidget {
  const PlaylistScreen({super.key, required this.playlistId});

  final int playlistId;

  static Future<void> open(BuildContext context, int playlistId) {
    return Navigator.of(context).push(
      MaterialPageRoute<void>(builder: (_) => PlaylistScreen(playlistId: playlistId)),
    );
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final playlist = ref.watch(playlistProvider(playlistId));
    final songs = ref.watch(playlistSongsProvider(playlistId));
    final handler = ref.read(audioHandlerProvider);
    final notifier = ref.read(playlistsProvider.notifier);
    final palette = context.palette;

    if (playlist == null) {
      // Deleted while open.
      return const Scaffold(body: SizedBox.shrink());
    }

    final total = songs.fold(Duration.zero, (sum, s) => sum + s.duration);

    Future<void> rename() async {
      final name = await showPlaylistNameDialog(
        context,
        title: context.l10n.renamePlaylist,
        action: context.l10n.rename,
        initial: playlist.name,
      );
      if (name != null) await notifier.rename(playlistId, name);
    }

    Future<void> exportM3u() async {
      final messenger = ScaffoldMessenger.of(context);
      final l10n = context.l10n;
      final name = playlist.name.replaceAll(RegExp(r'[\/:*?"<>|]'), '_');
      final saved = await ref.read(mediaLibraryProvider).saveTextDocument(
            name: '$name.m3u8',
            text: M3u.write(playlist.name, songs),
            mime: 'audio/x-mpegurl',
          );
      if (saved != null) messenger.showSnackBar(SnackBar(content: Text(l10n.savedAs(saved))));
    }

    Future<void> delete() async {
      final confirmed = await showDialog<bool>(
        context: context,
        builder: (context) => AlertDialog(
          title: Text(context.l10n.deletePlaylistTitle),
          content: Text(context.l10n.deletePlaylistBody(playlist.name)),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(false),
              child: Text(context.l10n.cancel, style: TextStyle(color: palette.inkMuted)),
            ),
            FilledButton(
              style: FilledButton.styleFrom(backgroundColor: const Color(0xFFD70015)),
              onPressed: () => Navigator.of(context).pop(true),
              child: Text(context.l10n.delete),
            ),
          ],
        ),
      );
      if (confirmed == true && context.mounted) {
        Navigator.of(context).pop();
        await notifier.delete(playlistId);
      }
    }

    // Song ids that resolve to songs on the device, with their position in
    // the stored playlist (missing files are skipped but kept in storage).
    final positions = <int>[
      for (final (i, id) in playlist.songIds.indexed)
        if (songs.any((s) => s.id == id)) i,
    ];

    return Scaffold(
      body: CustomScrollView(
        slivers: [
          CollectionAppBar(
            actions: [
              PopupMenuButton<String>(
                tooltip: context.l10n.playlistOptions,
                icon: HugeIcon(icon: HugeIcons.strokeRoundedMoreVertical, color: palette.ink, size: 24),
                onSelected: (value) => switch (value) {
                  'rename' => rename(),
                  'export' => exportM3u(),
                  _ => delete(),
                },
                itemBuilder: (_) => [
                  PopupMenuItem(value: 'rename', child: Text(context.l10n.rename)),
                  PopupMenuItem(value: 'export', child: Text(context.l10n.exportM3u)),
                  PopupMenuItem(value: 'delete', child: Text(context.l10n.delete)),
                ],
              ),
            ],
          ),
          SliverToBoxAdapter(
            child: CollectionHeader(
              cover: PlaylistCover(playlist: playlist, size: 210, radius: 22),
              title: playlist.name,
              subtitle: songs.isEmpty
                  ? context.l10n.emptyPlaylist
                  : '${context.l10n.songs(songs.length)} · ${formatTotalDuration(total)}',
              onPlay: songs.isEmpty ? null : () => handler.playSongs(songs),
              onShuffle: songs.isEmpty ? null : () => handler.playSongs(songs, shuffle: true),
            ),
          ),
          if (songs.isEmpty)
            SliverToBoxAdapter(
              child: Padding(
                padding: EdgeInsets.only(top: 24),
                child: EmptyState(
                  icon: HugeIcons.strokeRoundedPlayListAdd,
                  title: context.l10n.noSongsYet,
                  message: context.l10n.noSongsYetHint,
                ),
              ),
            )
          else
            SliverReorderableList(
              itemCount: songs.length,
              onReorderItem: (oldIndex, newIndex) {
                HapticFeedback.selectionClick();
                final ids = moveItem(
                  playlist.songIds,
                  positions[oldIndex],
                  positions[newIndex],
                );
                notifier.setSongs(playlistId, ids);
              },
              itemBuilder: (context, index) {
                final song = songs[index];
                return Dismissible(
                  key: ValueKey('${playlist.id}-${positions[index]}-${song.id}'),
                  direction: DismissDirection.endToStart,
                  background: Container(
                    color: const Color(0xFFD70015),
                    alignment: Alignment.centerRight,
                    padding: const EdgeInsets.only(right: 24),
                    child: const HugeIcon(
                      icon: HugeIcons.strokeRoundedDelete02,
                      color: Colors.white,
                      size: 22,
                    ),
                  ),
                  onDismissed: (_) => notifier.removeAt(playlistId, positions[index]),
                  child: Material(
                    color: palette.background,
                    child: SongTile(
                      song: song,
                      showAlbum: true,
                      onTap: () => handler.playSongs(songs, startIndex: index),
                      extraActions: [
                        SongMenuAction(
                          icon: HugeIcons.strokeRoundedRemoveCircle,
                          label: context.l10n.removeFromPlaylist,
                          onSelected: () => notifier.removeAt(playlistId, positions[index]),
                        ),
                      ],
                      trailing: ReorderableDragStartListener(
                        index: index,
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
                  ),
                );
              },
            ),
          const SliverToBoxAdapter(child: SizedBox(height: 24)),
        ],
      ),
    );
  }
}
