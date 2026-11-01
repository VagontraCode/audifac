import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:hugeicons/hugeicons.dart';

import '../core/theme/app_colors.dart';
import '../l10n/l10n.dart';
import '../models/album.dart';
import '../models/song.dart';
import '../providers/library_providers.dart';
import '../providers/queue_actions.dart';
import 'artwork.dart';
import 'playlist_dialogs.dart';
import 'song_actions_sheet.dart';

/// Play next / Add to queue for [songs], with the snackbar saying where
/// they went (a live soirée spreads them).
Future<void> enqueueWithToast(BuildContext context, WidgetRef ref, List<Song> songs, {required bool next}) async {
  if (songs.isEmpty) return;
  final messenger = ScaffoldMessenger.of(context);
  final l10n = context.l10n;
  final done = await enqueueSongs(ref, songs, next: next);
  messenger.showSnackBar(SnackBar(
    duration: const Duration(seconds: 2),
    content: Text(switch (done) {
      Enqueued.next || Enqueued.soireeNext => l10n.playingSongsNext(songs.length),
      Enqueued.end => l10n.addedSongsToQueue(songs.length),
      Enqueued.soireeSpread => l10n.spreadInSoiree(songs.length),
    }),
  ));
}

/// "More" menu for a whole album / artist / folder / playlist: Play next,
/// Add to queue, Add to playlist…, then [extraActions].
class CollectionActionsSheet extends ConsumerWidget {
  const CollectionActionsSheet({
    super.key,
    required this.title,
    required this.songs,
    required this.hostContext,
    this.extraActions = const [],
    this.allowAddToPlaylist = true,
  });

  final String title;
  final List<Song> songs;
  final BuildContext hostContext;
  final List<SongMenuAction> extraActions;
  final bool allowAddToPlaylist;

  static Future<void> show(
    BuildContext context, {
    required String title,
    required List<Song> songs,
    List<SongMenuAction> extraActions = const [],
    bool allowAddToPlaylist = true,
  }) {
    if (songs.isEmpty && extraActions.isEmpty) return Future.value();
    HapticFeedback.selectionClick();
    return showModalBottomSheet<void>(
      context: context,
      useRootNavigator: true,
      isScrollControlled: true,
      builder: (_) => CollectionActionsSheet(
        title: title,
        songs: songs,
        hostContext: context,
        extraActions: extraActions,
        allowAddToPlaylist: allowAddToPlaylist,
      ),
    );
  }

  static Future<void> showAlbum(BuildContext context, Album album) =>
      show(context, title: album.title, songs: album.songs);

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = context.l10n;
    final theme = Theme.of(context);
    final palette = context.palette;

    void close() => Navigator.of(context).pop();

    final actions = <SongMenuAction>[
      if (songs.isNotEmpty) ...[
        SongMenuAction(
          icon: HugeIcons.strokeRoundedTextIndentMore,
          label: l10n.playNext,
          onSelected: () {
            enqueueWithToast(hostContext, ref, songs, next: true);
            close();
          },
        ),
        SongMenuAction(
          icon: HugeIcons.strokeRoundedQueue01,
          label: l10n.addToQueue,
          onSelected: () {
            enqueueWithToast(hostContext, ref, songs, next: false);
            close();
          },
        ),
        if (allowAddToPlaylist)
          SongMenuAction(
            icon: HugeIcons.strokeRoundedPlayListAdd,
            label: l10n.addToPlaylistEllipsis,
            onSelected: () {
              close();
              AddToPlaylistSheet.show(hostContext, [for (final s in songs) s.id]);
            },
          ),
      ],
      for (final a in extraActions)
        SongMenuAction(
          icon: a.icon,
          label: a.label,
          onSelected: () {
            close();
            a.onSelected();
          },
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
                if (songs.isNotEmpty) ...[
                  Artwork.song(songs.first, size: 56, radius: 12),
                  const SizedBox(width: 14),
                ],
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        title,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: theme.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w800),
                      ),
                      Text(l10n.songs(songs.length), style: theme.textTheme.bodyMedium),
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

/// Queue → "Add an album": pick one, it goes to the end of the queue (or
/// into the soirée that's playing).
class AlbumPickerSheet extends ConsumerStatefulWidget {
  const AlbumPickerSheet({super.key});

  /// The album picked, or null.
  static Future<Album?> pick(BuildContext context) => showModalBottomSheet<Album>(
        context: context,
        useRootNavigator: true,
        isScrollControlled: true,
        builder: (_) => const AlbumPickerSheet(),
      );

  @override
  ConsumerState<AlbumPickerSheet> createState() => _AlbumPickerSheetState();
}

class _AlbumPickerSheetState extends ConsumerState<AlbumPickerSheet> {
  var _query = '';

  @override
  Widget build(BuildContext context) {
    final q = _query.toLowerCase();
    final albums = ref.watch(albumsProvider);
    final shown = [
      for (final a in albums)
        if (q.isEmpty || '${a.title} ${a.artist}'.toLowerCase().contains(q)) a,
    ];
    return SizedBox(
      height: MediaQuery.sizeOf(context).height * 0.8,
      child: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 8, 20, 8),
            child: TextField(
              decoration: InputDecoration(hintText: context.l10n.searchAlbums, prefixIcon: const Icon(Icons.search)),
              onChanged: (v) => setState(() => _query = v),
            ),
          ),
          Expanded(
            child: ListView.builder(
              itemCount: shown.length,
              itemBuilder: (context, i) => ListTile(
                leading: Artwork.song(shown[i].coverSong, size: 44, radius: 8),
                title: Text(shown[i].title, maxLines: 1, overflow: TextOverflow.ellipsis),
                subtitle: Text(
                  '${shown[i].artist} · ${context.l10n.songs(shown[i].songs.length)}',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
                onTap: () => Navigator.pop(context, shown[i]),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
