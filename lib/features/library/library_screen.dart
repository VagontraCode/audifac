import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:hugeicons/hugeicons.dart';

import '../../core/format.dart';
import '../../core/theme/app_colors.dart';
import '../../models/app_settings.dart';
import '../../providers/audio_info_providers.dart';
import '../../providers/library_providers.dart';
import '../../providers/player_providers.dart';
import '../../providers/user_data_providers.dart';
import '../../widgets/artwork.dart';
import '../../widgets/empty_state.dart';
import '../../widgets/entrance.dart';
import '../../widgets/pill_button.dart';
import '../../widgets/playlist_dialogs.dart';
import '../../widgets/song_tile.dart';
import '../collection/collection_screen.dart';
import '../collection/playlist_screen.dart';
import '../favorites/favorites_screen.dart';
import 'library_gate.dart';
import 'song_filter_bar.dart';

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
          length: 4,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(20, 16, 8, 4),
                child: Row(
                  children: [
                    Expanded(
                      child: Text(
                        'Library',
                        style: theme.textTheme.headlineLarge,
                      ),
                    ),
                    IconButton(
                      tooltip: 'Rescan library',
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
              const TabBar(
                isScrollable: true,
                padding: EdgeInsets.symmetric(horizontal: 8),
                tabs: [
                  Tab(text: 'SONGS'),
                  Tab(text: 'ALBUMS'),
                  Tab(text: 'ARTISTS'),
                  Tab(text: 'PLAYLISTS'),
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
        ? pluralize(total, 'song')
        : '${songs.length} of ${pluralize(total, 'song')}';

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
                title: 'No songs match',
                message: 'Try another quality, codec or source.',
                actionLabel: 'Clear filters',
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
                          tooltip: 'Sort',
                          initialValue: sort,
                          onSelected: ref
                              .read(settingsProvider.notifier)
                              .setSongSort,
                          itemBuilder: (_) => [
                            for (final s in SongSort.values)
                              PopupMenuItem(value: s, child: Text(s.label)),
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
                                  '$countLabel · ${sort.label}',
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
                            tooltip: 'Clear filters',
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
                          label: 'Shuffle',
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
      child: GridView.builder(
        key: const PageStorageKey('albums'),
        physics: const AlwaysScrollableScrollPhysics(),
        padding: const EdgeInsets.fromLTRB(20, 4, 20, 16),
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
                            '${pluralize(artist.albums.length, 'album')} · '
                            '${pluralize(artist.songs.length, 'song')}',
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
          title: const Text(
            'New playlist',
            style: TextStyle(fontWeight: FontWeight.w700),
          ),
          onTap: create,
        ),
        ListTile(
          contentPadding: const EdgeInsets.symmetric(
            horizontal: 20,
            vertical: 4,
          ),
          leading: iconTile(HugeIcons.strokeRoundedFavourite),
          title: const Text(
            'Favorites',
            style: TextStyle(fontWeight: FontWeight.w700),
          ),
          subtitle: Text(pluralize(favorites.length, 'song')),
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
              subtitle: Text(pluralize(playlist.songIds.length, 'song')),
              onTap: () => PlaylistScreen.open(context, playlist.id),
            ),
          ),
      ],
    );
  }
}
