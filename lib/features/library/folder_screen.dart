import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:hugeicons/hugeicons.dart';
import '../../l10n/l10n.dart';

import '../../core/theme/app_colors.dart';
import '../../models/folder_tree.dart';
import '../../providers/library_providers.dart';
import '../../providers/player_providers.dart';
import '../../widgets/entrance.dart';
import '../../widgets/song_tile.dart';

/// Library → Folders: storage volumes (or, with one volume, its folders).
class FoldersTab extends ConsumerWidget {
  const FoldersTab({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final tree = ref.watch(folderTreeProvider);
    final entries = tree.roots.length == 1 ? tree.foldersIn(tree.roots.single) : [for (final r in tree.roots) tree.entry(r)];
    final rootSongs = tree.roots.length == 1 ? tree.songsIn(tree.roots.single) : const [];
    return ListView(
      key: const PageStorageKey('folders'),
      padding: const EdgeInsets.only(bottom: 16),
      children: [
        for (final (i, e) in entries.indexed) Entrance(index: i, child: FolderTile(entry: e)),
        if (rootSongs.isNotEmpty)
          FolderTile(entry: FolderEntry(path: tree.roots.single, name: context.l10n.looseFiles, songCount: rootSongs.length, folderCount: 0)),
      ],
    );
  }
}

class FolderTile extends StatelessWidget {
  const FolderTile({super.key, required this.entry});

  final FolderEntry entry;

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    return ListTile(
      contentPadding: const EdgeInsets.symmetric(horizontal: 20, vertical: 2),
      leading: Container(
        width: 48,
        height: 48,
        decoration: BoxDecoration(color: palette.artwork, borderRadius: BorderRadius.circular(12)),
        child: Center(child: HugeIcon(icon: HugeIcons.strokeRoundedFolder01, color: palette.ink, size: 24)),
      ),
      title: Text(entry.name, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontWeight: FontWeight.w700)),
      subtitle: Text([
        context.l10n.songs(entry.songCount),
        if (entry.folderCount > 0) context.l10n.folders(entry.folderCount),
      ].join(' · ')),
      trailing: HugeIcon(icon: HugeIcons.strokeRoundedArrowRight01, color: palette.inkMuted, size: 20),
      onTap: () => FolderScreen.open(context, entry.path, entry.name),
    );
  }
}

/// One folder: its subfolders, then its songs; play / shuffle everything below.
class FolderScreen extends ConsumerWidget {
  const FolderScreen({super.key, required this.path, required this.title});

  final String path;
  final String title;

  static Future<void> open(BuildContext context, String path, String title) => Navigator.of(context)
      .push(MaterialPageRoute<void>(builder: (_) => FolderScreen(path: path, title: title)));

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final tree = ref.watch(folderTreeProvider);
    final folders = tree.foldersIn(path);
    final songs = tree.songsIn(path);
    final all = tree.allUnder(path);
    final handler = ref.read(audioHandlerProvider);
    final theme = Theme.of(context);
    final palette = context.palette;

    return Scaffold(
      body: SafeArea(
        bottom: false,
        child: CustomScrollView(
          slivers: [
            SliverToBoxAdapter(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(8, 16, 20, 4),
                child: Row(
                  children: [
                    IconButton(
                      tooltip: context.l10n.back,
                      onPressed: () => Navigator.of(context).pop(),
                      icon: HugeIcon(icon: HugeIcons.strokeRoundedArrowLeft01, color: palette.ink, size: 26),
                    ),
                    Expanded(
                      child: Text(title, maxLines: 1, overflow: TextOverflow.ellipsis, style: theme.textTheme.headlineMedium),
                    ),
                  ],
                ),
              ),
            ),
            SliverToBoxAdapter(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(20, 0, 20, 8),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(path, style: theme.textTheme.bodySmall?.copyWith(color: palette.inkMuted)),
                    const SizedBox(height: 12),
                    Row(
                      children: [
                        FilledButton.icon(
                          onPressed: all.isEmpty ? null : () => handler.playSongs(all),
                          icon: HugeIcon(icon: HugeIcons.strokeRoundedPlay, color: palette.onInk, size: 18),
                          label: Text(context.l10n.playCount(all.length)),
                        ),
                        const SizedBox(width: 10),
                        OutlinedButton.icon(
                          onPressed: all.isEmpty ? null : () => handler.playSongs(all, shuffle: true),
                          icon: HugeIcon(icon: HugeIcons.strokeRoundedShuffle, color: palette.ink, size: 18),
                          label: Text(context.l10n.shuffle),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ),
            SliverList.list(children: [for (final f in folders) FolderTile(entry: f)]),
            SliverList.builder(
              itemCount: songs.length,
              itemBuilder: (context, i) => SongTile(
                song: songs[i],
                showAlbum: true,
                onTap: () => handler.playSongs(songs, startIndex: i),
              ),
            ),
            const SliverToBoxAdapter(child: SizedBox(height: 24)),
          ],
        ),
      ),
    );
  }
}
