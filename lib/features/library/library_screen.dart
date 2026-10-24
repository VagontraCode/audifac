import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:hugeicons/hugeicons.dart';

import '../../core/theme/app_colors.dart';
import '../../models/app_settings.dart';
import '../../models/m3u.dart';
import '../../providers/audio_info_providers.dart';
import '../../providers/library_providers.dart';
import '../../providers/player_providers.dart';
import '../../providers/smart_playlist_providers.dart';
import '../../providers/user_data_providers.dart';
import '../../widgets/artwork.dart';
import '../../widgets/empty_state.dart';
import '../../widgets/entrance.dart';
import '../../widgets/pill_button.dart';
import '../../widgets/playlist_dialogs.dart';
import '../../widgets/song_tile.dart';
import '../collection/collection_screen.dart';
import '../collection/playlist_screen.dart';
import '../collection/smart_playlist_screen.dart';
import '../favorites/favorites_screen.dart';
import 'folder_screen.dart';
import 'library_gate.dart';
import 'song_filter_bar.dart';
import '../../l10n/l10n.dart';
import '../../l10n/labels.dart';

class LibraryScreen extends ConsumerWidget {
  const LibraryScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final palette = context.palette;

    return Scaffold(
      body: SafeArea(
        bottom: false,
        child: DefaultTabController(
          length: 5,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(20, 16, 8, 4),
                child: Row(
                  children: [
                    Expanded(
                      child: Text(
                        context.l10n.tabLibrary,
                        style: theme.textTheme.headlineLarge,
                      ),
                    ),
                    IconButton(
                      tooltip: context.l10n.rescanLibrary,
                      onPressed: () =>
                          ref.read(libraryProvider.notifier).refresh(),
                      icon: HugeIcon(
                        icon: HugeIcons.strokeRoundedRefresh,
                        color: palette.ink,
                        size: 24,
                      ),
                    ),
                  ],
                ),
              ),
              TabBar(
                isScrollable: true,
                padding: EdgeInsets.symmetric(horizontal: 8),
                tabs: [
                  Tab(text: context.l10n.songsTitle.toUpperCase()),
                  Tab(text: context.l10n.albumsTitle.toUpperCase()),
                  Tab(text: context.l10n.artists.toUpperCase()),
                  Tab(text: context.l10n.playlistsTitle.toUpperCase()),
                  Tab(text: context.l10n.foldersTitle.toUpperCase()),
                ],
              ),
              const SizedBox(height: 8),
              Expanded(
                child: LibraryGate(
                  builder: (context, _) => const EntranceScope(
                    child: TabBarView(
                      children: [
                        _SongsTab(),
                        _AlbumsTab(),
                        _ArtistsTab(),
                        PlaylistsTab(),
                        FoldersTab(),
                      ],
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Pull-to-refresh wrapper used by every tab.
class _Refreshable extends ConsumerWidget {
  const _Refreshable({required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return RefreshIndicator(
      color: context.palette.ink,
      backgroundColor: context.palette.surface,
      onRefresh: () => ref.read(libraryProvider.notifier).refresh(),
      child: child,
    );
  }
}

class _SongsTab extends ConsumerWidget {
  const _SongsTab();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final handler = ref.read(audioHandlerProvider);
    final songs = ref.watch(filteredSongsProvider);
    final total = ref.watch(songsProvider).length;
    final sort = ref.watch(settingsProvider.select((s) => s.songSort));
    final filter = ref.watch(settingsProvider.select((s) => s.songFilter));
    final palette = context.palette;
    final countLabel = songs.length == total
        ? context.l10n.songs(total)
        : context.l10n.songsOf(songs.length, total);

    return _Refreshable(
      child: ListView.builder(
        key: const PageStorageKey('songs'),
        physics: const AlwaysScrollableScrollPhysics(),
        padding: const EdgeInsets.only(bottom: 16),
        itemCount: songs.length + (songs.isEmpty ? 2 : 1),
        itemBuilder: (context, index) {
          if (index == 1 && songs.isEmpty) {
            return Padding(
              padding: const EdgeInsets.only(top: 48),
              child: EmptyState(
                icon: HugeIcons.strokeRoundedFilterHorizontal,
                title: context.l10n.noSongsMatch,
                message: context.l10n.noSongsMatchHint,
                actionLabel: context.l10n.clearFilters,
                onAction: () => ref
                    .read(settingsProvider.notifier)
                    .setSongFilter(const SongFilter()),
              ),
            );
          }
          if (index == 0) {
            return Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: Column(
                children: [
                  Padding(
                    padding: const EdgeInsets.fromLTRB(12, 0, 20, 4),
                    child: Row(
                      children: [
                        PopupMenuButton<SongSort>(
                          tooltip: context.l10n.sort,
                          initialValue: sort,
                          onSelected: ref
                              .read(settingsProvider.notifier)
                              .setSongSort,
                          itemBuilder: (_) => [
                            for (final s in SongSort.values)
                              PopupMenuItem(value: s, child: Text(context.l10n.songSort(s))),
                          ],
                          child: Padding(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 8,
                              vertical: 10,
                            ),
                            child: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                HugeIcon(
                                  icon: HugeIcons.strokeRoundedSorting05,
                                  color: palette.ink,
                                  size: 18,
                                ),
                                const SizedBox(width: 6),
                                Text(
                                  '$countLabel · ${context.l10n.songSort(sort)}',
                                  style: Theme.of(context).textTheme.bodyMedium
                                      ?.copyWith(
                                        color: palette.ink,
                                        fontWeight: FontWeight.w600,
                                      ),
                                ),
                              ],
                            ),
                          ),
                        ),
                        const Spacer(),
                        if (!filter.isEmpty)
                          IconButton(
                            tooltip: context.l10n.clearFilters,
                            onPressed: () => ref
                                .read(settingsProvider.notifier)
                                .setSongFilter(const SongFilter()),
                            icon: HugeIcon(
                              icon: HugeIcons.strokeRoundedCancel01,
                              color: palette.inkMuted,
                              size: 20,
                            ),
                          ),
                        PillButton(
                          icon: HugeIcons.strokeRoundedShuffle,
                          label: context.l10n.shuffle,
                          onPressed: songs.isEmpty
                              ? null
                              : () => handler.playSongs(songs, shuffle: true),
                        ),
                      ],
                    ),
                  ),
                  const SongFilterBar(),
                ],
              ),
            );
          }
          final i = index - 1;
          return Entrance(
            index: i,
            child: SongTile(
              song: songs[i],
              showAlbum: true,
              onTap: () => handler.playSongs(songs, startIndex: i),
            ),
          );
        },
      ),
    );
  }
}

class _AlbumsTab extends ConsumerWidget {
  const _AlbumsTab();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final albums = ref.watch(albumsProvider);
    final theme = Theme.of(context);
    final palette = context.palette;

    return _Refreshable(
      child: CustomScrollView(
        key: const PageStorageKey('albums'),
        physics: const AlwaysScrollableScrollPhysics(),
        slivers: [
          SliverToBoxAdapter(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(20, 4, 20, 12),
              child: Row(
                children: [
                  Expanded(child: Text(context.l10n.albums(albums.length), style: theme.textTheme.titleSmall)),
                  PillButton(
                    icon: HugeIcons.strokeRoundedShuffle,
                    label: context.l10n.shuffleAlbums,
                    onPressed: albums.isEmpty
                        ? null
                        : () => ref.read(audioHandlerProvider).playSongs(
                              [for (final a in albums) ...a.songs],
                              shuffle: true,
                              albumShuffle: true,
                            ),
                  ),
                ],
              ),
            ),
          ),
          SliverPadding(
            padding: const EdgeInsets.fromLTRB(20, 0, 20, 16),
            sliver: SliverGrid.builder(
        gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(
          maxCrossAxisExtent: 220,
          mainAxisSpacing: 20,
          crossAxisSpacing: 16,
          childAspectRatio: 0.72,
        ),
        itemCount: albums.length,
        itemBuilder: (context, index) {
          final album = albums[index];
          return Entrance(
            index: index,
            child: GestureDetector(
              onTap: () => CollectionScreen.openAlbum(context, album),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  LayoutBuilder(
                    builder: (context, constraints) => Artwork.song(
                      album.coverSong,
                      size: constraints.maxWidth,
                      radius: 16,
                    ),
                  ),
                  const SizedBox(height: 10),
                  Text(
                    album.title,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: theme.textTheme.titleSmall?.copyWith(
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  Text(
                    album.artist,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: palette.inkMuted,
                    ),
                  ),
                ],
              ),
            ),
          );
        },
            ),
          ),
        ],
      ),
    );
  }
}

class _ArtistsTab extends ConsumerWidget {
  const _ArtistsTab();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final artists = ref.watch(artistsProvider);
    final theme = Theme.of(context);
    final palette = context.palette;

    return _Refreshable(
      child: ListView.builder(
        key: const PageStorageKey('artists'),
        physics: const AlwaysScrollableScrollPhysics(),
        padding: const EdgeInsets.only(bottom: 16),
        itemCount: artists.length,
        itemBuilder: (context, index) {
          final artist = artists[index];
          return Entrance(
            index: index,
            child: InkWell(
              onTap: () => CollectionScreen.openArtist(context, artist),
              child: Padding(
                padding: const EdgeInsets.symmetric(
                  horizontal: 20,
                  vertical: 8,
                ),
                child: Row(
                  children: [
                    Artwork.song(artist.coverSong, size: 56, circle: true),
                    const SizedBox(width: 14),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            artist.name,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: theme.textTheme.titleMedium,
                          ),
                          Text(
                            '${context.l10n.albums(artist.albums.length)} · ${context.l10n.songs(artist.songs.length)}',
                            style: theme.textTheme.bodyMedium,
                          ),
                        ],
                      ),
                    ),
                    HugeIcon(
                      icon: HugeIcons.strokeRoundedArrowRight01,
                      color: palette.inkMuted,
                      size: 20,
                    ),
                  ],
                ),
              ),
            ),
          );
        },
      ),
    );
  }
}

/// Playlists tab: "New playlist", "Favorites", then the user's playlists.
class PlaylistsTab extends ConsumerWidget {
  const PlaylistsTab({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final playlists = ref.watch(playlistsProvider);
    final favorites = ref.watch(favoriteSongsProvider);
    final palette = context.palette;
    final smart = ref.watch(smartPlaylistsProvider);

    Widget iconTile(List<List<dynamic>> icon) => Container(
      width: 56,
      height: 56,
      decoration: BoxDecoration(
        color: palette.ink,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Center(
        child: HugeIcon(icon: icon, color: palette.onInk, size: 26),
      ),
    );

    Future<void> create() async {
      final name = await showPlaylistNameDialog(context);
      if (name == null) return;
      final playlist = await ref.read(playlistsProvider.notifier).create(name);
      if (context.mounted) PlaylistScreen.open(context, playlist.id);
    }

    Future<void> importM3u() async {
      final messenger = ScaffoldMessenger.of(context);
      final l10n = context.l10n;
      final ({String? name, String text})? doc;
      try {
        doc = await ref.read(mediaLibraryProvider).openTextDocument(anyType: true);
      } on PlatformException {
        messenger.showSnackBar(SnackBar(content: Text(l10n.notAPlaylist)));
        return;
      }
      if (doc == null) return;
      final entries = M3u.parse(doc.text);
      final found = M3u.match(entries, ref.read(songsProvider)).nonNulls.toList();
      if (found.isEmpty) {
        messenger.showSnackBar(SnackBar(content: Text(entries.isEmpty ? l10n.notAPlaylist : l10n.m3uNoneFound)));
        return;
      }
      final name = M3u.name(doc.text) ?? doc.name ?? l10n.imported;
      final playlist = await ref.read(playlistsProvider.notifier).create(name, songIds: [for (final s in found) s.id]);
      messenger.showSnackBar(SnackBar(content: Text(l10n.m3uImported(found.length, entries.length))));
      if (context.mounted) PlaylistScreen.open(context, playlist.id);
    }

    return ListView(
      key: const PageStorageKey('playlists'),
      padding: const EdgeInsets.only(bottom: 16),
      children: [
        ListTile(
          contentPadding: const EdgeInsets.symmetric(
            horizontal: 20,
            vertical: 4,
          ),
          leading: iconTile(HugeIcons.strokeRoundedAdd01),
          title: Text(
            context.l10n.newPlaylist,
            style: TextStyle(fontWeight: FontWeight.w700),
          ),
          onTap: create,
        ),
        ListTile(
          contentPadding: const EdgeInsets.symmetric(
            horizontal: 20,
            vertical: 4,
          ),
          leading: iconTile(HugeIcons.strokeRoundedFileImport),
          title: Text(
            context.l10n.importM3u,
            style: TextStyle(fontWeight: FontWeight.w700),
          ),
          subtitle: Text(context.l10n.importM3uHint),
          onTap: importM3u,
        ),
        ListTile(
          contentPadding: const EdgeInsets.symmetric(
            horizontal: 20,
            vertical: 4,
          ),
          leading: iconTile(HugeIcons.strokeRoundedFavourite),
          title: Text(
            context.l10n.favorites,
            style: TextStyle(fontWeight: FontWeight.w700),
          ),
          subtitle: Text(context.l10n.songs(favorites.length)),
          onTap: () => FavoritesScreen.open(context),
        ),
        for (final (i, playlist) in playlists.indexed)
          Entrance(
            index: i,
            child: ListTile(
              contentPadding: const EdgeInsets.symmetric(
                horizontal: 20,
                vertical: 4,
              ),
              leading: PlaylistCover(playlist: playlist, size: 56, radius: 12),
              title: Text(
                playlist.name,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(fontWeight: FontWeight.w700),
              ),
              subtitle: Text(context.l10n.songs(playlist.songIds.length)),
              onTap: () => PlaylistScreen.open(context, playlist.id),
            ),
          ),
        Padding(
          padding: const EdgeInsets.fromLTRB(20, 20, 8, 4),
          child: Row(
            children: [
              Expanded(
                child: Text(
                  context.l10n.smartPlaylists,
                  style: Theme.of(context).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w800),
                ),
              ),
              TextButton.icon(
                onPressed: () async {
                  final list = await SmartPlaylistEditor.open(context, SmartPlaylistEditor.blank());
                  if (list == null) return;
                  ref.read(smartPlaylistsProvider.notifier).save(list);
                  if (context.mounted) SmartPlaylistScreen.open(context, list.id);
                },
                icon: HugeIcon(icon: HugeIcons.strokeRoundedAdd01, color: palette.ink, size: 18),
                label: Text(context.l10n.newLabel),
              ),
            ],
          ),
        ),
        for (final list in smart)
          ListTile(
            contentPadding: const EdgeInsets.symmetric(horizontal: 20, vertical: 4),
            leading: SmartCover(list: list, size: 56),
            title: Text(
              context.l10n.smartName(list),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(fontWeight: FontWeight.w700),
            ),
            subtitle: Text(
              '${context.l10n.songs(ref.watch(smartSongsProvider(list.id)).length)} · ${context.l10n.smartDescribe(list)}',
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
            onTap: () => SmartPlaylistScreen.open(context, list.id),
          ),
      ],
    );
  }
}
