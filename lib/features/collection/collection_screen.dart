import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:hugeicons/hugeicons.dart';

import '../../core/format.dart';
import '../../core/theme/app_colors.dart';
import '../../models/album.dart';
import '../../models/artist.dart';
import '../../models/song.dart';
import '../../providers/player_providers.dart';
import '../../widgets/artwork.dart';
import '../../widgets/entrance.dart';
import '../../widgets/pill_button.dart';
import '../../widgets/song_tile.dart';

/// Detail page for an album or an artist: artwork header, Play / Shuffle,
/// then the track list.
class CollectionScreen extends ConsumerWidget {
  const CollectionScreen({
    super.key,
    required this.title,
    required this.subtitle,
    required this.songs,
    this.isAlbum = false,
  });

  final String title;
  final String subtitle;
  final List<Song> songs;
  final bool isAlbum;

  static Future<void> openAlbum(BuildContext context, Album album) {
    return Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => CollectionScreen(
          title: album.title,
          subtitle: album.artist,
          songs: album.songs,
          isAlbum: true,
        ),
      ),
    );
  }

  static Future<void> openArtist(BuildContext context, Artist artist) {
    return Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => CollectionScreen(
          title: artist.name,
          subtitle: pluralize(artist.albums.length, 'album'),
          songs: artist.songs,
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final handler = ref.read(audioHandlerProvider);
    final total = songs.fold(Duration.zero, (sum, s) => sum + s.duration);

    return Scaffold(
      body: EntranceScope(
        child: CustomScrollView(
          slivers: [
            const CollectionAppBar(),
            SliverToBoxAdapter(
              child: CollectionHeader(
                cover: Artwork.song(
                  songs.first,
                  size: 210,
                  radius: 22,
                  circle: !isAlbum,
                  shadow: true,
                ),
                title: title,
                subtitle: '$subtitle · ${pluralize(songs.length, 'song')} · ${formatTotalDuration(total)}',
                onPlay: () => handler.playSongs(songs),
                onShuffle: () => handler.playSongs(songs, shuffle: true),
              ),
            ),
            SliverList.builder(
              itemCount: songs.length,
              itemBuilder: (context, index) {
                final song = songs[index];
                // MediaStore stores disc * 1000 + track.
                final track = song.trackNumber % 1000;
                return Entrance(
                  index: index,
                  child: SongTile(
                    song: song,
                    trackNumber: isAlbum ? (track > 0 ? track : index + 1) : null,
                    showAlbum: !isAlbum,
                    onTap: () => handler.playSongs(songs, startIndex: index),
                  ),
                );
              },
            ),
            const SliverToBoxAdapter(child: SizedBox(height: 24)),
          ],
        ),
      ),
    );
  }
}

class CollectionAppBar extends StatelessWidget {
  const CollectionAppBar({super.key, this.actions});

  final List<Widget>? actions;

  @override
  Widget build(BuildContext context) {
    return SliverAppBar(
      pinned: true,
      leading: IconButton(
        tooltip: 'Back',
        onPressed: () => Navigator.of(context).pop(),
        icon: HugeIcon(icon: HugeIcons.strokeRoundedArrowLeft01, color: context.palette.ink, size: 26),
      ),
      actions: actions,
    );
  }
}

/// Artwork, title, subtitle and the Play / Shuffle buttons.
class CollectionHeader extends StatelessWidget {
  const CollectionHeader({
    super.key,
    required this.cover,
    required this.title,
    required this.subtitle,
    required this.onPlay,
    required this.onShuffle,
  });

  final Widget cover;
  final String title;
  final String subtitle;
  final VoidCallback? onPlay;
  final VoidCallback? onShuffle;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.fromLTRB(28, 0, 28, 20),
      child: Column(
        children: [
          cover,
          const SizedBox(height: 24),
          Text(
            title,
            textAlign: TextAlign.center,
            style: theme.textTheme.headlineSmall?.copyWith(fontWeight: FontWeight.w800),
          ),
          const SizedBox(height: 6),
          Text(subtitle, textAlign: TextAlign.center, style: theme.textTheme.bodyMedium),
          const SizedBox(height: 20),
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              PillButton(icon: HugeIcons.strokeRoundedPlay, label: 'Play', onPressed: onPlay),
              const SizedBox(width: 14),
              PillButton(
                icon: HugeIcons.strokeRoundedShuffle,
                label: 'Shuffle',
                filled: false,
                onPressed: onShuffle,
              ),
            ],
          ),
        ],
      ),
    );
  }
}
