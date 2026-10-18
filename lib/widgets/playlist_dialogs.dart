import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:hugeicons/hugeicons.dart';
import '../l10n/l10n.dart';

import '../core/theme/app_colors.dart';
import '../models/playlist.dart';
import '../providers/library_providers.dart';
import '../providers/user_data_providers.dart';
import 'artwork.dart';

/// Asks for a playlist name. Returns null when cancelled.
Future<String?> showPlaylistNameDialog(
  BuildContext context, {
  String? title,
  String? action,
  String initial = '',
}) {
  return showDialog<String>(
    context: context,
    builder: (context) => _PlaylistNameDialog(
      title: title ?? context.l10n.newPlaylist,
      action: action ?? context.l10n.create,
      initial: initial,
    ),
  );
}

class _PlaylistNameDialog extends StatefulWidget {
  const _PlaylistNameDialog({required this.title, required this.action, required this.initial});

  final String title;
  final String action;
  final String initial;

  @override
  State<_PlaylistNameDialog> createState() => _PlaylistNameDialogState();
}

class _PlaylistNameDialogState extends State<_PlaylistNameDialog> {
  late final _controller = TextEditingController(text: widget.initial);

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _submit() {
    final name = _controller.text.trim();
    if (name.isNotEmpty) Navigator.of(context).pop(name);
  }

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    return AlertDialog(
      title: Text(widget.title),
      content: TextField(
        controller: _controller,
        autofocus: true,
        textCapitalization: TextCapitalization.sentences,
        onSubmitted: (_) => _submit(),
        decoration: InputDecoration(
          hintText: context.l10n.playlistName,
          fillColor: palette.background,
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: Text(context.l10n.cancel, style: TextStyle(color: palette.inkMuted)),
        ),
        ValueListenableBuilder(
          valueListenable: _controller,
          builder: (context, value, _) => FilledButton(
            onPressed: value.text.trim().isEmpty ? null : _submit,
            child: Text(widget.action),
          ),
        ),
      ],
    );
  }
}

/// Bottom sheet to add [songIds] to an existing or new playlist.
class AddToPlaylistSheet extends ConsumerWidget {
  const AddToPlaylistSheet({super.key, required this.songIds});

  final List<int> songIds;

  static Future<void> show(BuildContext context, List<int> songIds) {
    return showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      useRootNavigator: true,
      builder: (_) => AddToPlaylistSheet(songIds: songIds),
    );
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final playlists = ref.watch(playlistsProvider);
    final messenger = ScaffoldMessenger.of(context);
    final l10n = context.l10n;
    final palette = context.palette;

    Future<void> addTo(Playlist playlist) async {
      final added = await ref.read(playlistsProvider.notifier).addSongs(playlist.id, songIds);
      if (context.mounted) Navigator.of(context).pop();
      messenger.showSnackBar(SnackBar(
        content: Text(added == 0
            ? l10n.alreadyIn(playlist.name)
            : l10n.addedSongsTo(added, playlist.name)),
      ));
    }

    Future<void> createNew() async {
      final name = await showPlaylistNameDialog(context);
      if (name == null) return;
      final playlist = await ref.read(playlistsProvider.notifier).create(name, songIds: songIds);
      if (context.mounted) Navigator.of(context).pop();
      messenger.showSnackBar(SnackBar(content: Text(l10n.createdPlaylist(playlist.name))));
    }

    return ConstrainedBox(
      constraints: BoxConstraints(maxHeight: MediaQuery.sizeOf(context).height * 0.7),
      child: ListView(
        shrinkWrap: true,
        padding: const EdgeInsets.only(bottom: 24),
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(24, 0, 24, 8),
            child: Text(
              context.l10n.addToPlaylist,
              style: Theme.of(context).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w800),
            ),
          ),
          ListTile(
            contentPadding: const EdgeInsets.symmetric(horizontal: 24),
            leading: Container(
              width: 48,
              height: 48,
              decoration: BoxDecoration(
                color: palette.ink,
                borderRadius: BorderRadius.circular(10),
              ),
              child: Center(
                child: HugeIcon(icon: HugeIcons.strokeRoundedAdd01, color: palette.onInk, size: 24),
              ),
            ),
            title: Text(context.l10n.newPlaylist, style: TextStyle(fontWeight: FontWeight.w700)),
            onTap: createNew,
          ),
          for (final playlist in playlists)
            ListTile(
              contentPadding: const EdgeInsets.symmetric(horizontal: 24),
              leading: PlaylistCover(playlist: playlist, size: 48),
              title: Text(playlist.name, maxLines: 1, overflow: TextOverflow.ellipsis),
              subtitle: Text(context.l10n.songs(playlist.songIds.length)),
              onTap: () => addTo(playlist),
            ),
        ],
      ),
    );
  }
}

/// Artwork of the playlist's first song, or a placeholder.
class PlaylistCover extends ConsumerWidget {
  const PlaylistCover({super.key, required this.playlist, required this.size, this.radius = 10});

  final Playlist playlist;
  final double size;
  final double radius;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final byId = ref.watch(songsByIdProvider);
    final first = playlist.songIds.map((id) => byId[id]).nonNulls.firstOrNull;
    if (first == null) {
      return ArtworkPlaceholder(
        size: size,
        radius: radius,
        icon: HugeIcons.strokeRoundedPlaylist01,
      );
    }
    return Artwork.song(first, size: size, radius: radius);
  }
}
