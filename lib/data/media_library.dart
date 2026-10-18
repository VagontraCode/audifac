import 'dart:async';
import 'dart:io';

import 'package:flutter/services.dart';
import 'package:permission_handler/permission_handler.dart';

import '../models/song.dart';

enum LibraryAccess { granted, denied, permanentlyDenied }

/// A file our storage scan found but Android won't index.
///
/// [location] is what opens it (an absolute path, or a `content://` URI for
/// folders granted through the system picker); [path] is its readable
/// absolute path, used for folders, titles and de-duplication.
typedef UnindexedFile = ({String location, String path, int size, int modified});

/// A folder the user granted through the system folder picker.
typedef GrantedFolder = ({String uri, String? path});

class StorageScanResult {
  const StorageScanResult({
    required this.found,
    required this.newlyIndexed,
    required this.unindexed,
    required this.elapsed,
  });

  /// Audio files seen on disk.
  final int found;

  /// Files Android had missed and has now indexed at our request.
  final int newlyIndexed;
  final List<UnindexedFile> unindexed;
  final Duration elapsed;
}

/// Reads the device's audio through the native `audifac/media_library`
/// MethodChannel (see `MediaLibraryChannel.kt`).
class MediaLibrary {
  MediaLibrary() {
    _channel.setMethodCallHandler((call) async {
      if (call.method == 'mediaChanged') _changes.add(null);
    });
  }

  static const _channel = MethodChannel('audifac/media_library');

  final _changes = StreamController<void>.broadcast();

  /// Fires (debounced) when Android's audio collection changes.
  Stream<void> get changes => _changes.stream;

  /// Paths of songs outside MediaStore, for artwork lookups.
  final _filePaths = <int, String>{};

  /// Artwork is keyed by album: songs of one album share the same picture,
  /// so this keeps memory bounded by the number of visible albums.
  final _artwork = _LruCache<int, _Artwork>(capacity: 200);
  int? _sdkInt;

  Future<LibraryAccess> checkAccess({bool request = false}) async {
    if (!Platform.isAndroid) return LibraryAccess.granted;

    // Android 13+ (API 33) uses READ_MEDIA_AUDIO; older versions use
    // READ_EXTERNAL_STORAGE.
    _sdkInt ??= await _channel.invokeMethod<int>('sdkInt') ?? 33;
    final permission = _sdkInt! >= 33 ? Permission.audio : Permission.storage;
    final status = request ? await permission.request() : await permission.status;

    if (status.isGranted || status.isLimited) return LibraryAccess.granted;
    if (status.isPermanentlyDenied) return LibraryAccess.permanentlyDenied;
    return LibraryAccess.denied;
  }

  Future<void> openSettings() => openAppSettings();

  /// Everything in MediaStore's audio collection (unfiltered).
  Future<List<Song>> fetchSongs() async {
    final raw = await _channel.invokeListMethod<Map<dynamic, dynamic>>('getSongs');
    return (raw ?? const []).map(Song.fromMap).toList(growable: false);
  }

  /// Walks every storage volume, gets Android to index audio it missed, and
  /// returns the files it can't index.
  Future<StorageScanResult> scanStorage({Set<String> excluded = const {}}) async {
    final raw = await _channel.invokeMapMethod<String, dynamic>(
      'scanStorage',
      {'excluded': excluded.toList()},
    );
    final files = (raw?['unindexed'] as List? ?? const []).cast<Map<dynamic, dynamic>>();
    return StorageScanResult(
      found: (raw?['found'] as num?)?.toInt() ?? 0,
      newlyIndexed: (raw?['newlyIndexed'] as num?)?.toInt() ?? 0,
      unindexed: [
        for (final f in files)
          (
            location: f['location'] as String,
            path: f['path'] as String,
            size: (f['size'] as num).toInt(),
            modified: (f['modified'] as num).toInt(),
          ),
      ],
      elapsed: Duration(milliseconds: (raw?['elapsedMs'] as num?)?.toInt() ?? 0),
    );
  }

  /// Tags of files outside MediaStore (title, artist, album, duration…),
  /// by location.
  Future<List<Map<dynamic, dynamic>>> readMetadata(List<String> locations) async {
    if (locations.isEmpty) return const [];
    final raw = await _channel.invokeListMethod<Map<dynamic, dynamic>>(
      'readMetadata',
      {'paths': locations},
    );
    return raw ?? const [];
  }

  /// Codec, sample rate, bit depth… of each location (see `AudioInspector.kt`),
  /// in the same order.
  Future<List<Map<dynamic, dynamic>>> inspectAudio(List<String> locations) async {
    if (locations.isEmpty) return const [];
    final raw = await _channel.invokeListMethod<Map<dynamic, dynamic>>(
      'inspectAudio',
      {'locations': locations},
    );
    return raw ?? const [];
  }

  /// Lets artwork be loaded for songs that only exist as files.
  void registerFiles(Iterable<Song> songs) {
    for (final song in songs) {
      if (song.isFile) _filePaths[song.id] = song.location;
    }
  }

  // --- Folders granted through the system picker -------------------------------

  /// Opens the system folder picker. Returns null when cancelled.
  Future<GrantedFolder?> pickFolder() async {
    final raw = await _channel.invokeMapMethod<String, dynamic>('pickFolder');
    return raw == null ? null : (uri: raw['uri'] as String, path: raw['path'] as String?);
  }

  /// Lets the user pick a small text file; returns its name and content.
  /// [anyType]: any file can be picked (lyrics: .lrc has no standard MIME type).
  Future<({String? name, String text})?> openTextDocument({bool anyType = false}) async {
    final raw = await _channel.invokeMapMethod<String, dynamic>('openTextDocument', {'anyType': anyType});
    if (raw == null) return null;
    return (name: raw['name'] as String?, text: raw['text'] as String);
  }

  /// "Save as" dialog writing [text]; returns the saved file name, or null if
  /// cancelled.
  Future<String?> saveTextDocument({required String name, required String text, String mime = 'application/json'}) =>
      _channel.invokeMethod<String>('saveTextDocument', {'name': name, 'text': text, 'mime': mime});

  /// Lyrics beside the file or in its tags: (text, source "file" | "tags"), or null.
  Future<({String text, String source})?> readLyrics(Song song) async {
    try {
      final raw = await _channel.invokeMapMethod<String, dynamic>('readLyrics', {'location': song.location, 'path': song.path});
      if (raw == null) return null;
      return (text: raw['text'] as String, source: raw['source'] as String? ?? 'tags');
    } on PlatformException {
      return null;
    } on MissingPluginException {
      return null;
    }
  }

  /// `0.1.0+3`.
  Future<String> appVersion() async {
    try {
      return await _channel.invokeMethod<String>('appVersion') ?? '?';
    } on PlatformException {
      return '?';
    }
  }

  Future<List<GrantedFolder>> grantedFolders() async {
    final raw = await _channel.invokeListMethod<Map<dynamic, dynamic>>('grantedFolders');
    return [
      for (final f in raw ?? const <Map<dynamic, dynamic>>[])
        (uri: f['uri'] as String, path: f['path'] as String?),
    ];
  }

  Future<void> removeFolder(String uri) => _channel.invokeMethod('removeFolder', {'uri': uri});

  /// Writes [song]'s artwork to a cache file and returns its `file://` URI, so
  /// the media notification can show it for any song.
  Future<Uri?> cachedArtworkFile(int songId, int albumId) async {
    final location = _filePaths[songId];
    try {
      final path = await _channel.invokeMethod<String>('cacheArtwork', {
        if (location != null) 'path': location else 'id': songId,
        'key': 'album_$albumId',
      });
      return path == null ? null : Uri.file(path);
    } on PlatformException {
      return null;
    }
  }

  /// Already-loaded artwork, available synchronously so list items don't
  /// flash a placeholder when they are rebuilt. Null when not loaded yet.
  ({Uint8List? bytes})? peekArtwork(int albumId) {
    final art = _artwork.get(albumId);
    return art != null && art.loaded ? (bytes: art.bytes) : null;
  }

  /// Embedded artwork of [songId], shared by every song of [albumId].
  Future<Uint8List?> artworkFor({required int songId, required int albumId}) {
    return _artwork.putIfAbsent(albumId, () => _Artwork(_loadArtwork(songId))).future;
  }

  Future<Uint8List?> _loadArtwork(int songId) async {
    final path = _filePaths[songId];
    try {
      return await _channel.invokeMethod<Uint8List>(
        'getArtwork',
        {if (path != null) 'path': path else 'id': songId, 'size': 512},
      );
    } on PlatformException {
      return null;
    }
  }
}

class _Artwork {
  _Artwork(this.future) {
    future.then((value) {
      bytes = value;
      loaded = true;
    });
  }

  final Future<Uint8List?> future;
  Uint8List? bytes;
  bool loaded = false;
}

class _LruCache<K, V> {
  _LruCache({required this.capacity});

  final int capacity;
  final _map = <K, V>{}; // Insertion-ordered (LinkedHashMap).

  V? get(K key) => _map[key];

  V putIfAbsent(K key, V Function() create) {
    final existing = _map.remove(key);
    if (existing != null) {
      _map[key] = existing; // Move to most-recently-used position.
      return existing;
    }
    final value = create();
    _map[key] = value;
    if (_map.length > capacity) _map.remove(_map.keys.first);
    return value;
  }
}
