import 'package:audio_service/audio_service.dart';

import '../../models/album.dart';
import '../../models/artist.dart';
import '../../models/song.dart';

/// A named list of songs that can be browsed and played (an album, a
/// playlist, recently played…).
class BrowseList {
  const BrowseList({required this.id, required this.title, this.subtitle, required this.songs});

  final String id;
  final String title;
  final String? subtitle;
  final List<Song> songs;
}

/// The library as Android Auto / other media browsers see it:
///
/// root → Recently played · Favorites · Playlists · Albums · Artists · Shuffle all
///
/// A song's id carries its list (`album:12|song:345`), so choosing it plays
/// the whole list from there.
class BrowseTree {
  BrowseTree({
    required this.all,
    this.recent = const [],
    this.favorites = const [],
    this.playlists = const [],
    this.albums = const [],
    this.artists = const [],
  });

  final List<Song> all;
  final List<Song> recent;
  final List<Song> favorites;
  final List<BrowseList> playlists;
  final List<Album> albums;
  final List<Artist> artists;

  static const root = AudioService.browsableRootId;
  static const recentId = AudioService.recentRootId;
  static const favoritesId = 'favorites';
  static const playlistsId = 'playlists';
  static const albumsId = 'albums';
  static const artistsId = 'artists';
  static const shuffleId = 'shuffle';

  /// Media browsers show lists this long at most; more just costs memory.
  static const maxItems = 500;

  static MediaItem _folder(String id, String title, {String? subtitle}) =>
      MediaItem(id: id, title: title, displaySubtitle: subtitle, playable: false);

  static MediaItem _song(String listId, Song s) => MediaItem(
        id: '$listId|song:${s.id}',
        title: s.title,
        artist: s.artist,
        album: s.album,
        duration: s.duration == Duration.zero ? null : s.duration,
        playable: true,
      );

  List<MediaItem> children(String parentId) {
    switch (parentId) {
      case root:
        return [
          if (recent.isNotEmpty) _folder(recentId, 'Recently played'),
          if (favorites.isNotEmpty) _folder(favoritesId, 'Favorites'),
          if (playlists.isNotEmpty) _folder(playlistsId, 'Playlists'),
          _folder(albumsId, 'Albums'),
          _folder(artistsId, 'Artists'),
          MediaItem(id: shuffleId, title: 'Shuffle all', displaySubtitle: '${all.length} songs', playable: true),
        ];
      case playlistsId:
        return [for (final p in playlists) _folder('playlist:${p.id.split(':').last}', p.title, subtitle: p.subtitle)];
      case albumsId:
        return [for (final a in albums.take(maxItems)) _folder('album:${a.id}', a.title, subtitle: a.artist)];
      case artistsId:
        return [for (final a in artists.take(maxItems)) _folder('artist:${a.id}', a.name, subtitle: '${a.songs.length} songs')];
    }
    final list = listFor(parentId);
    return list == null ? const [] : [for (final s in list.songs.take(maxItems)) _song(parentId, s)];
  }

  /// The songs behind a browsable id.
  BrowseList? listFor(String id) {
    if (id == recentId) return BrowseList(id: id, title: 'Recently played', songs: recent);
    if (id == favoritesId) return BrowseList(id: id, title: 'Favorites', songs: favorites);
    if (id == shuffleId) return BrowseList(id: id, title: 'Shuffle all', songs: all);
    final colon = id.indexOf(':');
    if (colon < 0) return null;
    final kind = id.substring(0, colon);
    final key = id.substring(colon + 1);
    switch (kind) {
      case 'playlist':
        return playlists.where((p) => p.id == 'playlist:$key').firstOrNull;
      case 'album':
        final a = albums.where((a) => '${a.id}' == key).firstOrNull;
        return a == null ? null : BrowseList(id: id, title: a.title, subtitle: a.artist, songs: a.songs);
      case 'artist':
        final a = artists.where((a) => '${a.id}' == key).firstOrNull;
        return a == null ? null : BrowseList(id: id, title: a.name, songs: a.songs);
    }
    return null;
  }

  /// What to play for [mediaId]: a list and where to start (shuffled for
  /// "Shuffle all").
  ({List<Song> songs, int index, bool shuffle})? playable(String mediaId) {
    if (mediaId == shuffleId) return all.isEmpty ? null : (songs: all, index: 0, shuffle: true);
    final bar = mediaId.lastIndexOf('|song:');
    if (bar < 0) {
      final list = listFor(mediaId);
      return list == null || list.songs.isEmpty ? null : (songs: list.songs, index: 0, shuffle: false);
    }
    final list = listFor(mediaId.substring(0, bar));
    final songId = int.tryParse(mediaId.substring(bar + 6));
    if (list == null || songId == null) return null;
    final index = list.songs.indexWhere((s) => s.id == songId);
    return index < 0 ? null : (songs: list.songs, index: index, shuffle: false);
  }

  /// Voice / text search ("play Burna Boy"): matching songs, best first.
  List<Song> search(String query) {
    final q = query.trim().toLowerCase();
    if (q.isEmpty) return const [];
    int score(Song s) {
      final t = s.title.toLowerCase(), a = s.artist.toLowerCase(), b = s.album.toLowerCase();
      if (t == q) return 0;
      if (a == q || b == q) return 1;
      if (t.startsWith(q)) return 2;
      if (t.contains(q)) return 3;
      if (a.contains(q) || b.contains(q)) return 4;
      return 99;
    }
    final hits = [for (final s in all) if (score(s) < 99) s]..sort((x, y) => score(x).compareTo(score(y)));
    return hits;
  }
}
