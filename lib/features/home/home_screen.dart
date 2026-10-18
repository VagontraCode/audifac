import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:hugeicons/hugeicons.dart';

import '../../core/theme/app_colors.dart';
import '../../l10n/l10n.dart';
import '../../models/album.dart';
import '../../models/song.dart';
import '../../providers/library_providers.dart';
import '../../providers/player_providers.dart';
import '../../providers/user_data_providers.dart';
import '../../widgets/artwork.dart';
import '../../widgets/entrance.dart';
import '../../widgets/playlist_dialogs.dart';
import '../../widgets/song_actions_sheet.dart';
import '../collection/collection_screen.dart';
import '../collection/playlist_screen.dart';
import '../favorites/favorites_screen.dart';
import '../library/library_gate.dart';
import 'settings_sheet.dart';
import 'stats_screen.dart';

/// Landing page: quick actions, recently played, recently added, playlists.
class HomeScreen extends ConsumerWidget {
  const HomeScreen({super.key});

  static String _greeting(AppLocalizations l10n) {
    final hour = DateTime.now().hour;
    if (hour < 5) return l10n.goodNight;
    if (hour < 12) return l10n.goodMorning;
    if (hour < 18) return l10n.goodAfternoon;
    return l10n.goodEvening;
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final palette = context.palette;

    return Scaffold(
      body: SafeArea(
        bottom: false,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 16, 8, 8),
              child: Row(
                children: [
                  Expanded(child: Text(_greeting(context.l10n), style: theme.textTheme.headlineLarge)),
                  IconButton(
                    tooltip: context.l10n.yourStats,
                    onPressed: () => StatsScreen.open(context),
                    icon: HugeIcon(icon: HugeIcons.strokeRoundedAnalytics01, color: palette.ink, size: 24),
                  ),
                  IconButton(
                    tooltip: context.l10n.settings,
                    onPressed: () => SettingsSheet.show(context),
                    icon: HugeIcon(icon: HugeIcons.strokeRoundedSettings02, color: palette.ink, size: 24),
                  ),
                ],
              ),
            ),
            Expanded(
              child: LibraryGate(
                builder: (context, songs) => RefreshIndicator(
                  color: palette.ink,
                  backgroundColor: palette.surface,
                  onRefresh: () => ref.read(libraryProvider.notifier).refresh(),
                  child: EntranceScope(child: _HomeContent(allSongs: songs)),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _HomeContent extends ConsumerWidget {
  const _HomeContent({required this.allSongs});

  final List<Song> allSongs;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final handler = ref.read(audioHandlerProvider);
    final recent = ref.watch(recentSongsProvider).take(20).toList();
    final recentAlbums = ref.watch(recentlyAddedAlbumsProvider);
    final favorites = ref.watch(favoriteSongsProvider);
    final playlists = ref.watch(playlistsProvider);

    var section = 0;
    Widget animated(Widget child) => Entrance(index: section++, child: child);

    return ListView(
      physics: const AlwaysScrollableScrollPhysics(),
      padding: const EdgeInsets.only(bottom: 24),
      children: [
        animated(
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 4, 20, 8),
            child: Row(
              children: [
                Expanded(
                  child: _QuickTile(
                    icon: HugeIcons.strokeRoundedShuffle,
                    title: context.l10n.shuffleAll,
                    subtitle: context.l10n.songs(allSongs.length),
                    filled: true,
                    onTap: () => handler.playSongs(allSongs, shuffle: true),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: _QuickTile(
                    icon: HugeIcons.strokeRoundedFavourite,
                    title: context.l10n.favorites,
                    subtitle: context.l10n.songs(favorites.length),
                    onTap: () => FavoritesScreen.open(context),
                  ),
                ),
              ],
            ),
          ),
        ),
        if (recent.isNotEmpty) ...[
          animated(_SectionTitle(context.l10n.recentlyPlayed)),
          animated(
            _HorizontalList(
              itemCount: recent.length,
              itemBuilder: (context, i) => _Card(
                cover: Artwork.song(recent[i], size: 140, radius: 16),
                title: recent[i].title,
                subtitle: recent[i].artist,
                onTap: () => handler.playSongs(recent, startIndex: i),
                onLongPress: () => SongActionsSheet.show(context, recent[i]),
              ),
            ),
          ),
        ],
        if (recentAlbums.isNotEmpty) ...[
          animated(_SectionTitle(context.l10n.recentlyAdded)),
          animated(
            _HorizontalList(
              itemCount: recentAlbums.length,
              itemBuilder: (context, i) {
                final Album album = recentAlbums[i];
                return _Card(
                  cover: Artwork.song(album.coverSong, size: 140, radius: 16),
                  title: album.title,
                  subtitle: album.artist,
                  onTap: () => CollectionScreen.openAlbum(context, album),
                );
              },
            ),
          ),
        ],
        animated(_SectionTitle(context.l10n.yourPlaylists)),
        animated(
          _HorizontalList(
            itemCount: playlists.length + 1,
            itemBuilder: (context, i) {
              if (i == 0) {
                return _Card(
                  cover: _NewPlaylistCover(size: 140),
                  title: context.l10n.newPlaylist,
                  subtitle: context.l10n.create,
                  onTap: () async {
                    final name = await showPlaylistNameDialog(context);
                    if (name == null) return;
                    final playlist = await ref.read(playlistsProvider.notifier).create(name);
                    if (context.mounted) PlaylistScreen.open(context, playlist.id);
                  },
                );
              }
              final playlist = playlists[i - 1];
              return _Card(
                cover: PlaylistCover(playlist: playlist, size: 140, radius: 16),
                title: playlist.name,
                subtitle: context.l10n.songs(playlist.songIds.length),
                onTap: () => PlaylistScreen.open(context, playlist.id),
              );
            },
          ),
        ),
      ],
    );
  }
}

class _SectionTitle extends StatelessWidget {
  const _SectionTitle(this.title);

  final String title;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 20, 20, 12),
      child: Text(
        title,
        style: Theme.of(context).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w800),
      ),
    );
  }
}

class _HorizontalList extends StatelessWidget {
  const _HorizontalList({required this.itemCount, required this.itemBuilder});

  final int itemCount;
  final IndexedWidgetBuilder itemBuilder;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 196,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 20),
        itemCount: itemCount,
        separatorBuilder: (_, _) => const SizedBox(width: 14),
        itemBuilder: itemBuilder,
      ),
    );
  }
}

class _Card extends StatelessWidget {
  const _Card({
    required this.cover,
    required this.title,
    required this.subtitle,
    required this.onTap,
    this.onLongPress,
  });

  final Widget cover;
  final String title;
  final String subtitle;
  final VoidCallback onTap;
  final VoidCallback? onLongPress;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return GestureDetector(
      onTap: onTap,
      onLongPress: onLongPress,
      child: SizedBox(
        width: 140,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            cover,
            const SizedBox(height: 8),
            Text(
              title,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: theme.textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w700),
            ),
            Text(
              subtitle,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: theme.textTheme.bodySmall?.copyWith(color: context.palette.inkMuted),
            ),
          ],
        ),
      ),
    );
  }
}

class _NewPlaylistCover extends StatelessWidget {
  const _NewPlaylistCover({required this.size});

  final double size;

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        color: palette.surface,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: palette.line, width: 1.5),
      ),
      child: Center(child: HugeIcon(icon: HugeIcons.strokeRoundedAdd01, color: palette.ink, size: 36)),
    );
  }
}

class _QuickTile extends StatelessWidget {
  const _QuickTile({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.onTap,
    this.filled = false,
  });

  final List<List<dynamic>> icon;
  final String title;
  final String subtitle;
  final VoidCallback onTap;
  final bool filled;

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    final fg = filled ? palette.onInk : palette.ink;
    return Material(
      color: filled ? palette.ink : palette.surface,
      borderRadius: BorderRadius.circular(18),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              HugeIcon(icon: icon, color: fg, size: 26),
              const SizedBox(height: 18),
              Text(title, style: TextStyle(color: fg, fontWeight: FontWeight.w800, fontSize: 16)),
              Text(subtitle, style: TextStyle(color: fg.withValues(alpha: 0.7), fontSize: 13)),
            ],
          ),
        ),
      ),
    );
  }
}
