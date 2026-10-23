import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../data/app_database.dart';
import '../models/app_settings.dart';
import '../models/playlist.dart';
import '../models/song.dart';
import 'library_providers.dart';

/// Overridden in `main()` once the database is open.
final databaseProvider = Provider<AppDatabase>(
  (ref) => throw UnimplementedError('databaseProvider must be overridden'),
);

/// Overridden in `main()` with data loaded before the first frame.
final bootstrapProvider = Provider<Bootstrap>(
  (ref) => throw UnimplementedError('bootstrapProvider must be overridden'),
);

// --- Settings ----------------------------------------------------------------

final settingsProvider = NotifierProvider<SettingsNotifier, AppSettings>(SettingsNotifier.new);

class SettingsNotifier extends Notifier<AppSettings> {
  @override
  AppSettings build() => AppSettings.fromKeyValues(ref.read(bootstrapProvider).values);

  void setThemeMode(ThemeMode mode) => _update(state.copyWith(themeMode: mode));

  void setSongSort(SongSort sort) => _update(state.copyWith(songSort: sort));

  void setMinDuration(int seconds) => _update(state.copyWith(minDurationSeconds: seconds));

  void setIncludeRecordings(bool include) => _update(state.copyWith(includeRecordings: include));

  void setShowLabels(bool show) => _update(state.copyWith(showLabels: show));

  void setKeepAlbumsTogether(bool keep) => _update(state.copyWith(keepAlbumsTogether: keep));

  void setCrossfade(int seconds) => _update(state.copyWith(crossfadeSeconds: seconds));

  void setLanguage(String code) => _update(state.copyWith(languageCode: code));

  void setBitPerfectUsb(bool on) => _update(state.copyWith(bitPerfectUsb: on));
  void setHqResampler(bool on) => _update(state.copyWith(hqResampler: on));

  /// Restore from a backup.
  void replace(AppSettings settings) => _update(settings);

  void setSongFilter(SongFilter filter) => _update(state.copyWith(songFilter: filter));

  void setFolderExcluded(String folder, bool excluded) {
    final folders = {...state.excludedFolders};
    excluded ? folders.add(folder) : folders.remove(folder);
    _update(state.copyWith(excludedFolders: folders));
  }

  void _update(AppSettings next) {
    state = next;
    ref.read(databaseProvider).setValues(next.toKeyValues());
  }
}

// --- Favorites ---------------------------------------------------------------

/// Liked song ids, most recent first.
final favoritesProvider = NotifierProvider<FavoritesNotifier, List<int>>(FavoritesNotifier.new);

class FavoritesNotifier extends Notifier<List<int>> {
  @override
  List<int> build() => ref.read(bootstrapProvider).favoriteIds;

  bool isFavorite(int songId) => state.contains(songId);

  /// Adds [songIds] that aren't favorites yet (backup restore); returns how many.
  int addAll(List<int> songIds) {
    final fresh = songIds.where((id) => !state.contains(id)).toList();
    if (fresh.isEmpty) return 0;
    state = [...fresh, ...state];
    final db = ref.read(databaseProvider);
    // Oldest first so the newest ends up on top (ordered by added_at).
    for (final id in fresh.reversed) {
      db.setFavorite(id, true);
    }
    return fresh.length;
  }

  /// Returns the new state (true = now a favorite).
  bool toggle(int songId) {
    final favorite = !state.contains(songId);
    state = favorite ? [songId, ...state] : state.where((id) => id != songId).toList();
    ref.read(databaseProvider).setFavorite(songId, favorite);
    return favorite;
  }
}

final isFavoriteProvider = Provider.family<bool, int>(
  (ref, songId) => ref.watch(favoritesProvider).contains(songId),
);

final favoriteSongsProvider = Provider<List<Song>>((ref) {
  final byId = ref.watch(songsByIdProvider);
  return [
    for (final id in ref.watch(favoritesProvider))
      if (byId[id] case final song?) song,
  ];
});

// --- Playlists ---------------------------------------------------------------

final playlistsProvider = NotifierProvider<PlaylistsNotifier, List<Playlist>>(PlaylistsNotifier.new);

class PlaylistsNotifier extends Notifier<List<Playlist>> {
  @override
  List<Playlist> build() => ref.read(bootstrapProvider).playlists;

  AppDatabase get _db => ref.read(databaseProvider);

  Future<Playlist> create(String name, {List<int> songIds = const []}) async {
    var playlist = await _db.createPlaylist(name.trim());
    if (songIds.isNotEmpty) {
      playlist = playlist.copyWith(songIds: songIds);
      await _db.setPlaylistSongs(playlist.id, songIds);
    }
    state = [playlist, ...state];
    return playlist;
  }

  Future<void> rename(int id, String name) async {
    _replace(id, (p) => p.copyWith(name: name.trim()));
    await _db.renamePlaylist(id, name.trim());
  }

  Future<void> delete(int id) async {
    state = state.where((p) => p.id != id).toList();
    await _db.deletePlaylist(id);
  }

  /// Adds songs that are not already in the playlist; returns how many were added.
  Future<int> addSongs(int id, List<int> songIds) async {
    final playlist = state.firstWhere((p) => p.id == id);
    final toAdd = songIds.where((s) => !playlist.songIds.contains(s)).toList();
    if (toAdd.isEmpty) return 0;
    await setSongs(id, [...playlist.songIds, ...toAdd]);
    return toAdd.length;
  }

  Future<void> removeAt(int id, int index) async {
    final playlist = state.firstWhere((p) => p.id == id);
    await setSongs(id, [...playlist.songIds]..removeAt(index));
  }

  Future<void> setSongs(int id, List<int> songIds) async {
    _replace(id, (p) => p.copyWith(songIds: songIds));
    await _db.setPlaylistSongs(id, songIds);
  }

  void _replace(int id, Playlist Function(Playlist) update) {
    state = [for (final p in state) p.id == id ? update(p) : p];
  }
}

final playlistProvider = Provider.family<Playlist?, int>(
  (ref, id) => ref.watch(playlistsProvider).where((p) => p.id == id).firstOrNull,
);

/// A playlist's songs that still exist on the device, in order.
final playlistSongsProvider = Provider.family<List<Song>, int>((ref, id) {
  final playlist = ref.watch(playlistProvider(id));
  final byId = ref.watch(songsByIdProvider);
  if (playlist == null) return const [];
  return [
    for (final songId in playlist.songIds)
      if (byId[songId] case final song?) song,
  ];
});

// --- Recently played ---------------------------------------------------------

final recentIdsProvider = NotifierProvider<RecentNotifier, List<int>>(RecentNotifier.new);

class RecentNotifier extends Notifier<List<int>> {
  @override
  List<int> build() => ref.read(bootstrapProvider).recentIds;

  /// Puts restored history after (older than) the current one.
  Future<int> restore(List<int> songIds) async {
    final fresh = songIds.where((id) => !state.contains(id)).toList();
    if (fresh.isEmpty) return 0;
    state = [...state, ...fresh].take(100).toList();
    await ref.read(databaseProvider).setRecentOrder(state);
    return fresh.length;
  }

  void record(int songId) {
    if (state.isNotEmpty && state.first == songId) return;
    state = [songId, ...state.where((id) => id != songId)].take(100).toList();
    ref.read(databaseProvider).recordPlayed(songId);
  }
}

final recentSongsProvider = Provider<List<Song>>((ref) {
  final byId = ref.watch(songsByIdProvider);
  return [
    for (final id in ref.watch(recentIdsProvider))
      if (byId[id] case final song?) song,
  ];
});
