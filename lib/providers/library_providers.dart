import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../data/app_database.dart';
import '../data/media_library.dart';
import '../models/album.dart';
import '../models/artist.dart';
import '../models/app_settings.dart';
import '../models/song.dart';
import 'user_data_providers.dart';

final mediaLibraryProvider = Provider<MediaLibrary>((ref) => MediaLibrary());

class LibraryAccessDenied implements Exception {
  const LibraryAccessDenied({required this.permanent});

  /// The user picked "Don't ask again": only the system settings can fix it.
  final bool permanent;
}

// --- Storage scan status -------------------------------------------------------

class ScanStatus {
  const ScanStatus({this.running = false, this.last, this.lastAt, this.error});

  final bool running;
  final StorageScanResult? last;
  final DateTime? lastAt;
  final String? error;

  ScanStatus copyWith({bool? running, StorageScanResult? last, DateTime? lastAt, String? error}) =>
      ScanStatus(
        running: running ?? this.running,
        last: last ?? this.last,
        lastAt: lastAt ?? this.lastAt,
        error: error,
      );
}

final scanStatusProvider = NotifierProvider<ScanStatusNotifier, ScanStatus>(ScanStatusNotifier.new);

class ScanStatusNotifier extends Notifier<ScanStatus> {
  @override
  ScanStatus build() => const ScanStatus();

  void set(ScanStatus status) => state = status;
}

// --- Library -------------------------------------------------------------------

/// Every audio file found on the device, unfiltered: MediaStore's audio
/// collection plus files our own storage scan found in folders Android won't
/// index. UI code should use [songsProvider], which applies the user's filters.
final libraryProvider = AsyncNotifierProvider<LibraryNotifier, List<Song>>(
  LibraryNotifier.new,
  // A denied permission is not a transient error: don't auto-retry.
  retry: (_, _) => null,
);

class LibraryNotifier extends AsyncNotifier<List<Song>> {
  static const _autoScanInterval = Duration(minutes: 15);
  static const _metadataBatch = 40;

  StreamSubscription<void>? _changes;
  Future<void>? _scanInFlight;

  MediaLibrary get _library => ref.read(mediaLibraryProvider);
  AppDatabase get _db => ref.read(databaseProvider);

  @override
  Future<List<Song>> build() async {
    _changes ??= _library.changes.listen((_) => reload());
    ref.onDispose(() {
      _changes?.cancel();
      _changes = null;
    });

    final songs = await _loadIndexed(request: true);
    // The fast path shows MediaStore + cached files immediately; the full
    // storage walk runs in the background and updates the list when done.
    Future.microtask(() => scanStorage(onlyIfStale: true));
    return songs;
  }

  /// MediaStore + files remembered from the last storage scan.
  Future<List<Song>> _loadIndexed({required bool request}) async {
    final access = await _library.checkAccess(request: request);
    if (access != LibraryAccess.granted) {
      throw LibraryAccessDenied(permanent: access == LibraryAccess.permanentlyDenied);
    }
    final (indexed, cached) = await (_library.fetchSongs(), _db.fileMeta()).wait;
    return _merge(indexed, cached.values);
  }

  List<Song> _merge(List<Song> indexed, Iterable<FileMeta> files) {
    final indexedPaths = {for (final s in indexed) ?s.path};
    final fileSongs = [
      for (final f in files)
        if (f.readable && !indexedPaths.contains(f.path))
          Song.fromFile(
            path: f.path,
            location: f.location,
            modifiedMs: f.modified,
            sizeBytes: f.size,
            title: f.title,
            artist: f.artist,
            album: f.album,
            durationMs: f.durationMs,
            track: f.track,
            mimeType: f.mimeType,
          ),
    ];
    _library.registerFiles(fileSongs);
    return [...indexed, ...fileSongs];
  }

  /// Walks all storage for audio files (see `MediaLibraryChannel.scanStorage`).
  /// Concurrent calls share the same scan.
  Future<void> scanStorage({bool onlyIfStale = false}) {
    final status = ref.read(scanStatusProvider);
    final lastAt = status.lastAt;
    if (onlyIfStale && lastAt != null && DateTime.now().difference(lastAt) < _autoScanInterval) {
      return Future.value();
    }
    return _scanInFlight ??= _scan().whenComplete(() => _scanInFlight = null);
  }

  Future<void> _scan() async {
    // Only after a successful, permitted load: e.g. returning from the
    // permission dialog resumes the app (which requests a scan) while the
    // first load is still waiting for the answer. Without permission Android
    // returns empty results, which would wrongly show "No audio found".
    if (!state.hasValue || state.hasError) return;
    if (await _library.checkAccess() != LibraryAccess.granted) return;
    final statusNotifier = ref.read(scanStatusProvider.notifier);
    statusNotifier.set(ref.read(scanStatusProvider).copyWith(running: true));
    try {
      final excluded = ref.read(settingsProvider).excludedFolders;
      final result = await _library.scanStorage(excluded: excluded);

      // Reuse cached tags when the file is unchanged; read the rest.
      final cache = await _db.fileMeta();
      final metas = <FileMeta>[];
      final toRead = <UnindexedFile>[];
      for (final f in result.unindexed) {
        final cached = cache[f.location];
        if (cached != null && cached.matches(f.size, f.modified)) {
          metas.add(cached);
        } else {
          toRead.add(f);
        }
      }
      for (var i = 0; i < toRead.length; i += _metadataBatch) {
        final batch = toRead.skip(i).take(_metadataBatch).toList();
        final read = await _library.readMetadata([for (final f in batch) f.location]);
        for (final (j, m) in read.indexed) {
          final f = batch[j];
          metas.add(FileMeta.fromNative(m, path: f.path, size: f.size, modified: f.modified));
        }
      }
      await _db.replaceFileMeta(metas);

      final indexed = await _library.fetchSongs();
      state = AsyncData(_merge(indexed, metas));
      statusNotifier.set(ScanStatus(last: result, lastAt: DateTime.now()));
    } catch (e) {
      statusNotifier.set(ref.read(scanStatusProvider).copyWith(running: false, error: '$e'));
    }
  }

  /// Quick re-read of MediaStore + cached files (e.g. after a download).
  Future<void> reload() async {
    if (!state.hasValue || state.hasError) return;
    final result = await AsyncValue.guard(() => _loadIndexed(request: false));
    state = result;
  }

  /// Pull-to-refresh / "Scan now": quick reload, then a full storage scan,
  /// keeping the current list on screen.
  Future<void> refresh() async {
    await reload();
    await scanStorage();
  }

  /// Called from the "Allow access" button.
  Future<void> requestAccess() async {
    final error = state.error;
    if (error is LibraryAccessDenied && error.permanent) {
      await _library.openSettings();
      return; // Re-checked when the app resumes, see [recheckAccess].
    }
    await rescan(request: true);
  }

  /// Called when the app resumes, e.g. after returning from system settings.
  Future<void> recheckAccess() async {
    if (state.error is LibraryAccessDenied) await rescan();
  }

  /// Full reload with a loading state (after errors / permission changes).
  Future<void> rescan({bool request = false}) async {
    state = const AsyncLoading();
    state = await AsyncValue.guard(() => _loadIndexed(request: request));
    if (state.hasValue) unawaited(scanStorage());
  }
}

/// Folders granted through the system picker (for hidden folders).
final grantedFoldersProvider = FutureProvider<List<GrantedFolder>>(
  (ref) => ref.read(mediaLibraryProvider).grantedFolders(),
);

/// Whether [song] passes the user's library filters.
bool isVisibleSong(Song song, AppSettings settings) {
  if (song.isSystemSound && !song.isMusic) return false;
  if (song.isRecording && !settings.includeRecordings) return false;
  final min = Duration(seconds: settings.minDurationSeconds);
  if (song.duration > Duration.zero && song.duration < min) return false;
  return !settings.isExcluded(song.folder);
}

/// The library as shown everywhere in the UI: filtered by the user's settings
/// (minimum length, recordings, excluded folders) and without ringtones /
/// notification sounds.
final songsProvider = Provider<List<Song>>((ref) {
  final all = ref.watch(libraryProvider).value ?? const <Song>[];
  final settings = ref.watch(settingsProvider);
  return all.where((s) => isVisibleSong(s, settings)).toList(growable: false);
});

/// Folders that contain audio, with how many files each holds (unfiltered),
/// for the folder picker in Settings.
final audioFoldersProvider = Provider<List<({String path, int count})>>((ref) {
  final all = ref.watch(libraryProvider).value ?? const <Song>[];
  final counts = <String, int>{};
  for (final song in all) {
    if (song.isSystemSound && !song.isMusic) continue;
    final folder = song.folder;
    if (folder != null) counts[folder] = (counts[folder] ?? 0) + 1;
  }
  final folders = [for (final e in counts.entries) (path: e.key, count: e.value)];
  folders.sort((a, b) => a.path.toLowerCase().compareTo(b.path.toLowerCase()));
  return folders;
});

/// Every visible song by id, to resolve favorites, playlists and history.
final songsByIdProvider = Provider<Map<int, Song>>((ref) {
  final songs = ref.watch(songsProvider);
  return {for (final s in songs) s.id: s};
});

/// Songs tab content, ordered by the user's sort setting.
final sortedSongsProvider = Provider<List<Song>>((ref) {
  final songs = ref.watch(songsProvider);
  final sort = ref.watch(settingsProvider.select((s) => s.songSort));
  int text(String a, String b) => a.toLowerCase().compareTo(b.toLowerCase());
  final sorted = [...songs];
  switch (sort) {
    case SongSort.title:
      sorted.sort((a, b) => text(a.title, b.title));
    case SongSort.artist:
      sorted.sort((a, b) {
        final c = text(a.artist, b.artist);
        return c != 0 ? c : text(a.title, b.title);
      });
    case SongSort.album:
      sorted.sort((a, b) {
        final c = text(a.album, b.album);
        return c != 0 ? c : a.trackNumber.compareTo(b.trackNumber);
      });
    case SongSort.dateAdded:
      sorted.sort((a, b) => b.dateAdded.compareTo(a.dateAdded));
  }
  return sorted;
});

/// Albums ordered by their newest song, for the Home screen.
final recentlyAddedAlbumsProvider = Provider<List<Album>>((ref) {
  DateTime newest(Album a) =>
      a.songs.map((s) => s.dateAdded).reduce((x, y) => x.isAfter(y) ? x : y);
  final albums = [...ref.watch(albumsProvider)];
  albums.sort((a, b) => newest(b).compareTo(newest(a)));
  return albums.take(12).toList();
});

final albumsProvider = Provider<List<Album>>((ref) {
  final songs = ref.watch(songsProvider);
  final byId = <int, List<Song>>{};
  for (final song in songs) {
    byId.putIfAbsent(song.albumId, () => []).add(song);
  }

  final albums = [
    for (final entry in byId.entries)
      Album(
        id: entry.key,
        title: entry.value.first.album,
        artist: _albumArtist(entry.value),
        songs: entry.value..sort(_byTrack),
      ),
  ]..sort((a, b) => a.title.toLowerCase().compareTo(b.title.toLowerCase()));
  return albums;
});

final artistsProvider = Provider<List<Artist>>((ref) {
  final albums = ref.watch(albumsProvider);
  final songs = ref.watch(songsProvider);

  final songsByArtist = <String, List<Song>>{};
  for (final song in songs) {
    songsByArtist.putIfAbsent(song.artist, () => []).add(song);
  }

  final artists = [
    for (final entry in songsByArtist.entries)
      () {
        final artistAlbums =
            albums.where((a) => a.songs.any((s) => s.artist == entry.key)).toList();
        // Order the artist's songs album by album, in track order.
        final ordered = [
          for (final album in artistAlbums)
            ...album.songs.where((s) => s.artist == entry.key),
        ];
        return Artist(
          id: entry.value.first.artistId,
          name: entry.key,
          songs: ordered,
          albums: artistAlbums,
        );
      }(),
  ]..sort((a, b) => a.name.toLowerCase().compareTo(b.name.toLowerCase()));
  return artists;
});

int _byTrack(Song a, Song b) {
  final byTrack = a.trackNumber.compareTo(b.trackNumber);
  return byTrack != 0 ? byTrack : a.title.compareTo(b.title);
}

/// "Various artists" when an album's tracks have different artists.
String _albumArtist(List<Song> songs) {
  final first = songs.first.artist;
  return songs.every((s) => s.artist == first) ? first : 'Various artists';
}
