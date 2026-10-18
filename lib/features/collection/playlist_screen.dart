import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:hugeicons/hugeicons.dart';

import '../../core/audio/queue_logic.dart';
import '../../core/format.dart';
import '../../core/theme/app_colors.dart';
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
        title: 'Rename playlist',
        action: 'Rename',
        initial: playlist.name,
      );
      if (name != null) await notifier.rename(playlistId, name);
    }

    Future<void> delete() async {
      final confirmed = await showDialog<bool>(
        context: context,
        builder: (context) => AlertDialog(
          title: const Text('Delete playlist?'),
          content: Text('"${playlist.name}" will be deleted. Your songs stay on the device.'),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(false),
              child: Text('Cancel', style: TextStyle(color: palette.inkMuted)),
            ),
            FilledButton(
              style: FilledButton.styleFrom(backgroundColor: const Color(0xFFD70015)),
              onPressed: () => Navigator.of(context).pop(true),
              child: const Text('Delete'),
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
                tooltip: 'Playlist options',
                icon: HugeIcon(icon: HugeIcons.strokeRoundedMoreVertical, color: palette.ink, size: 24),
                onSelected: (value) => value == 'rename' ? rename() : delete(),
                itemBuilder: (_) => const [
                  PopupMenuItem(value: 'rename', child: Text('Rename')),
                  PopupMenuItem(value: 'delete', child: Text('Delete')),
                ],
              ),
            ],
          ),
          SliverToBoxAdapter(
            child: CollectionHeader(
              cover: PlaylistCover(playlist: playlist, size: 210, radius: 22),
              title: playlist.name,
              subtitle: songs.isEmpty
                  ? 'Empty playlist'
                  : '${pluralize(songs.length, 'song')} · ${formatTotalDuration(total)}',
              onPlay: songs.isEmpty ? null : () => handler.playSongs(songs),
              onShuffle: songs.isEmpty ? null : () => handler.playSongs(songs, shuffle: true),
            ),
          ),
          if (songs.isEmpty)
            const SliverToBoxAdapter(
              child: Padding(
                padding: EdgeInsets.only(top: 24),
                child: EmptyState(
                  icon: HugeIcons.strokeRoundedPlayListAdd,
                  title: 'No songs yet',
                  message: 'Use "Add to playlist…" from any song\'s menu.',
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
                          label: 'Remove from playlist',
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
