import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:hugeicons/hugeicons.dart';
import '../../l10n/l10n.dart';

import '../../core/theme/app_colors.dart';
import '../../providers/library_providers.dart';
import '../../providers/player_providers.dart';
import '../../widgets/artwork.dart';
import '../../widgets/empty_state.dart';
import '../../widgets/song_tile.dart';
import '../collection/collection_screen.dart';

/// Instant local search over songs, albums and artists.
class SearchScreen extends ConsumerStatefulWidget {
  const SearchScreen({super.key});

  @override
  ConsumerState<SearchScreen> createState() => _SearchScreenState();
}

class _SearchScreenState extends ConsumerState<SearchScreen> {
  final _controller = TextEditingController();
  String _query = '';

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final palette = context.palette;
    final q = _query.trim().toLowerCase();

    final songs = ref
        .watch(songsProvider)
        .where((s) =>
            q.isNotEmpty &&
            (s.title.toLowerCase().contains(q) ||
                s.artist.toLowerCase().contains(q) ||
                s.album.toLowerCase().contains(q)))
        .toList();
    final albums = ref
        .watch(albumsProvider)
        .where((a) =>
            q.isNotEmpty &&
            (a.title.toLowerCase().contains(q) || a.artist.toLowerCase().contains(q)))
        .take(6)
        .toList();
    final artists = ref
        .watch(artistsProvider)
        .where((a) => q.isNotEmpty && a.name.toLowerCase().contains(q))
        .take(4)
        .toList();
    final hasResults = songs.isNotEmpty || albums.isNotEmpty || artists.isNotEmpty;

    return Scaffold(
      body: SafeArea(
        bottom: false,
        child: CustomScrollView(
          keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
          slivers: [
            SliverToBoxAdapter(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(20, 16, 20, 12),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(context.l10n.tabSearch, style: theme.textTheme.headlineLarge),
                    const SizedBox(height: 16),
                    TextField(
                      controller: _controller,
                      onChanged: (v) => setState(() => _query = v),
                      textInputAction: TextInputAction.search,
                      decoration: InputDecoration(
                        hintText: context.l10n.searchHint,
                        prefixIcon: Padding(
                          padding: const EdgeInsets.all(12),
                          child: HugeIcon(
                            icon: HugeIcons.strokeRoundedSearch01,
                            color: palette.inkMuted,
                            size: 22,
                          ),
                        ),
                        suffixIcon: _query.isEmpty
                            ? null
                            : IconButton(
                                onPressed: () {
                                  _controller.clear();
                                  setState(() => _query = '');
                                },
                                icon: HugeIcon(
                                  icon: HugeIcons.strokeRoundedCancel01,
                                  color: palette.inkMuted,
                                  size: 20,
                                ),
                              ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
            if (q.isEmpty)
              SliverFillRemaining(
                hasScrollBody: false,
                child: EmptyState(
                  icon: HugeIcons.strokeRoundedSearch01,
                  title: context.l10n.findYourMusic,
                  message: context.l10n.searchBy,
                ),
              )
            else if (!hasResults)
              SliverFillRemaining(
                hasScrollBody: false,
                child: EmptyState(
                  icon: HugeIcons.strokeRoundedMusicNote03,
                  title: context.l10n.noResults,
                  message: context.l10n.nothingMatches(_query),
                ),
              )
            else ...[
              if (artists.isNotEmpty) ...[
                _SectionHeader(context.l10n.artists),
                SliverList.builder(
                  itemCount: artists.length,
                  itemBuilder: (context, i) {
                    final artist = artists[i];
                    return ListTile(
                      contentPadding: const EdgeInsets.symmetric(horizontal: 20),
                      leading: Artwork.song(artist.coverSong, size: 48, circle: true),
                      title: Text(artist.name, style: theme.textTheme.titleMedium),
                      subtitle: Text(context.l10n.songs(artist.songs.length)),
                      onTap: () => CollectionScreen.openArtist(context, artist),
                    );
                  },
                ),
              ],
              if (albums.isNotEmpty) ...[
                _SectionHeader(context.l10n.albumsTitle),
                SliverList.builder(
                  itemCount: albums.length,
                  itemBuilder: (context, i) {
                    final album = albums[i];
                    return ListTile(
                      contentPadding: const EdgeInsets.symmetric(horizontal: 20),
                      leading: Artwork.song(album.coverSong, size: 48, radius: 10),
                      title: Text(album.title, style: theme.textTheme.titleMedium),
                      subtitle: Text(album.artist),
                      onTap: () => CollectionScreen.openAlbum(context, album),
                    );
                  },
                ),
              ],
              if (songs.isNotEmpty) ...[
                _SectionHeader(context.l10n.songsTitle),
                SliverList.builder(
                  itemCount: songs.length,
                  itemBuilder: (context, i) => SongTile(
                    song: songs[i],
                    showAlbum: true,
                    onTap: () =>
                        ref.read(audioHandlerProvider).playSongs(songs, startIndex: i),
                  ),
                ),
              ],
              const SliverToBoxAdapter(child: SizedBox(height: 16)),
            ],
          ],
        ),
      ),
    );
  }
}

class _SectionHeader extends StatelessWidget {
  const _SectionHeader(this.title);

  final String title;

  @override
  Widget build(BuildContext context) {
    return SliverToBoxAdapter(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(20, 16, 20, 4),
        child: Text(
          title,
          style: Theme.of(context).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w800),
        ),
      ),
    );
  }
}
