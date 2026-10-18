import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../core/audio/browse_tree.dart';
import 'library_providers.dart';
import 'player_providers.dart';
import 'user_data_providers.dart';

/// Gives Android Auto (and other media browsers) the current library.
final browseSyncProvider = Provider<void>((ref) {
  final byId = ref.watch(songsByIdProvider);
  ref.read(audioHandlerProvider).browseTree = BrowseTree(
    all: ref.watch(songsProvider),
    recent: ref.watch(recentSongsProvider),
    favorites: ref.watch(favoriteSongsProvider),
    playlists: [
      for (final p in ref.watch(playlistsProvider))
        BrowseList(
          id: 'playlist:${p.id}',
          title: p.name,
          subtitle: '${p.songIds.length} songs',
          songs: [for (final id in p.songIds) if (byId[id] case final s?) s],
        ),
    ],
    albums: ref.watch(albumsProvider),
    artists: ref.watch(artistsProvider),
  );
});
