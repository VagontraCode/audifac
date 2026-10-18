import 'dart:convert';

import 'package:path/path.dart' as p;
import 'package:sqflite/sqflite.dart';

import '../models/audio_info.dart';
import '../models/eq.dart';
import '../models/eq_rules.dart';
import '../models/loudness.dart';
import '../models/play_stats.dart';
import '../models/playlist.dart';

/// Everything the app stores itself: favorites, playlists, play history and
/// small key/value settings. Songs are referenced by their MediaStore id.
class AppDatabase {
  AppDatabase._(this._db);

  final Database _db;

  static const _recentLimit = 100;

  static Future<AppDatabase> open() async {
    final path = p.join(await getDatabasesPath(), 'audifac.db');
    final db = await openDatabase(
      path,
      version: 7,
      onConfigure: (db) => db.execute('PRAGMA foreign_keys = ON'),
      onCreate: (db, _) async {
        final batch = db.batch()
          ..execute('''
            CREATE TABLE favorites (
              song_id INTEGER PRIMARY KEY,
              added_at INTEGER NOT NULL
            )''')
          ..execute('''
            CREATE TABLE playlists (
              id INTEGER PRIMARY KEY AUTOINCREMENT,
              name TEXT NOT NULL,
              created_at INTEGER NOT NULL
            )''')
          ..execute('''
            CREATE TABLE playlist_songs (
              playlist_id INTEGER NOT NULL REFERENCES playlists(id) ON DELETE CASCADE,
              position INTEGER NOT NULL,
              song_id INTEGER NOT NULL,
              PRIMARY KEY (playlist_id, position)
            )''')
          ..execute('''
            CREATE TABLE recent (
              song_id INTEGER PRIMARY KEY,
              played_at INTEGER NOT NULL
            )''')
          ..execute('''
            CREATE TABLE kv (
              key TEXT PRIMARY KEY,
              value TEXT NOT NULL
            )''');
        _createFileMeta(batch);
        _createAudioInfo(batch);
        _createEq(batch);
        _createLoudness(batch);
        _createPlayLog(batch);
        await batch.commit(noResult: true);
      },
      onUpgrade: (db, from, _) async {
        final batch = db.batch();
        if (from < 3) {
          // file_meta is only a cache: recreate it rather than migrating.
          batch.execute('DROP TABLE IF EXISTS file_meta');
          _createFileMeta(batch);
        }
        if (from < 4) _createAudioInfo(batch);
        if (from < 5) _createEq(batch);
        if (from < 6) _createLoudness(batch);
        if (from < 7) _createPlayLog(batch);
        await batch.commit(noResult: true);
      },
    );
    return AppDatabase._(db);
  }

  /// v5: user EQ presets (JSON) and per song / album / artist / genre /
  /// source preset rules.
  static void _createEq(Batch batch) {
    batch
      ..execute('''
        CREATE TABLE eq_presets (
          id TEXT PRIMARY KEY,
          json TEXT NOT NULL
        )''')
      ..execute('''
        CREATE TABLE eq_rules (
          scope TEXT NOT NULL,
          key TEXT NOT NULL,
          json TEXT NOT NULL,
          PRIMARY KEY (scope, key)
        )''');
  }

  /// v7: every listen (play counts, last played, listening time, stats).
  static void _createPlayLog(Batch batch) {
    batch
      ..execute('''
        CREATE TABLE play_log (
          id INTEGER PRIMARY KEY AUTOINCREMENT,
          song_id INTEGER NOT NULL,
          played_at INTEGER NOT NULL,
          listened_ms INTEGER NOT NULL,
          counted INTEGER NOT NULL
        )''')
      ..execute('CREATE INDEX play_log_song ON play_log (song_id)');
  }

  /// v6: ReplayGain tags / R128 measurement per file (JSON), keyed by location.
  static void _createLoudness(Batch batch) {
    batch.execute('''
      CREATE TABLE loudness (
        location TEXT PRIMARY KEY,
        json TEXT NOT NULL
      )''');
  }

  /// v4: codec / sample rate / bit depth per file (JSON), keyed by location.
  static void _createAudioInfo(Batch batch) {
    batch.execute('''
      CREATE TABLE audio_info (
        location TEXT PRIMARY KEY,
        json TEXT NOT NULL
      )''');
  }

  /// Tags of audio files outside MediaStore, so rescans don't re-read them.
  /// v2 added the table, v3 the location / path split.
  static void _createFileMeta(Batch batch) {
    batch.execute('''
      CREATE TABLE file_meta (
        location TEXT PRIMARY KEY,
        path TEXT NOT NULL,
        size INTEGER NOT NULL,
        modified INTEGER NOT NULL,
        readable INTEGER NOT NULL,
        title TEXT,
        artist TEXT,
        album TEXT,
        duration_ms INTEGER,
        track INTEGER,
        mime_type TEXT
      )''');
  }

  static int get _now => DateTime.now().millisecondsSinceEpoch;

  // --- Favorites -------------------------------------------------------------

  /// Most recently liked first.
  Future<List<int>> favoriteIds() async {
    final rows = await _db.query('favorites', orderBy: 'added_at DESC');
    return [for (final r in rows) r['song_id'] as int];
  }

  Future<void> setFavorite(int songId, bool favorite) async {
    if (favorite) {
      await _db.insert(
        'favorites',
        {'song_id': songId, 'added_at': _now},
        conflictAlgorithm: ConflictAlgorithm.replace,
      );
    } else {
      await _db.delete('favorites', where: 'song_id = ?', whereArgs: [songId]);
    }
  }

  // --- Playlists -------------------------------------------------------------

  Future<List<Playlist>> playlists() async {
    final lists = await _db.query('playlists', orderBy: 'created_at DESC');
    final songs = await _db.query('playlist_songs', orderBy: 'playlist_id, position');
    final byPlaylist = <int, List<int>>{};
    for (final row in songs) {
      byPlaylist.putIfAbsent(row['playlist_id'] as int, () => []).add(row['song_id'] as int);
    }
    return [
      for (final row in lists)
        Playlist(
          id: row['id'] as int,
          name: row['name'] as String,
          songIds: byPlaylist[row['id']] ?? const [],
          createdAt: DateTime.fromMillisecondsSinceEpoch(row['created_at'] as int),
        ),
    ];
  }

  Future<Playlist> createPlaylist(String name) async {
    final now = _now;
    final id = await _db.insert('playlists', {'name': name, 'created_at': now});
    return Playlist(
      id: id,
      name: name,
      songIds: const [],
      createdAt: DateTime.fromMillisecondsSinceEpoch(now),
    );
  }

  Future<void> renamePlaylist(int id, String name) =>
      _db.update('playlists', {'name': name}, where: 'id = ?', whereArgs: [id]);

  Future<void> deletePlaylist(int id) =>
      _db.delete('playlists', where: 'id = ?', whereArgs: [id]);

  /// Rewrites the playlist's track list (used for add, remove and reorder).
  Future<void> setPlaylistSongs(int id, List<int> songIds) {
    return _db.transaction((txn) async {
      await txn.delete('playlist_songs', where: 'playlist_id = ?', whereArgs: [id]);
      final batch = txn.batch();
      for (var i = 0; i < songIds.length; i++) {
        batch.insert('playlist_songs', {
          'playlist_id': id,
          'position': i,
          'song_id': songIds[i],
        });
      }
      await batch.commit(noResult: true);
    });
  }

  // --- Recently played -------------------------------------------------------

  Future<List<int>> recentIds() async {
    final rows = await _db.query('recent', orderBy: 'played_at DESC', limit: _recentLimit);
    return [for (final r in rows) r['song_id'] as int];
  }

  Future<void> recordPlayed(int songId) async {
    await _db.insert(
      'recent',
      {'song_id': songId, 'played_at': _now},
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
    await _db.execute(
      'DELETE FROM recent WHERE song_id NOT IN '
      '(SELECT song_id FROM recent ORDER BY played_at DESC LIMIT $_recentLimit)',
    );
  }

  /// Rewrites the history in [songIds] order (newest first).
  Future<void> setRecentOrder(List<int> songIds) => _db.transaction((txn) async {
        await txn.delete('recent');
        final now = _now;
        final batch = txn.batch();
        for (final (i, id) in songIds.indexed) {
          batch.insert('recent', {'song_id': id, 'played_at': now - i * 1000});
        }
        await batch.commit(noResult: true);
      });

  // --- Files outside MediaStore ----------------------------------------------

  /// Every cached file, keyed by location.
  Future<Map<String, FileMeta>> fileMeta() async {
    final rows = await _db.query('file_meta');
    return {for (final r in rows) r['location'] as String: FileMeta.fromRow(r)};
  }

  /// Replaces the cache with [entries] (files that no longer exist drop out).
  Future<void> replaceFileMeta(Iterable<FileMeta> entries) {
    return _db.transaction((txn) async {
      await txn.delete('file_meta');
      final batch = txn.batch();
      for (final e in entries) {
        batch.insert('file_meta', e.toRow());
      }
      await batch.commit(noResult: true);
    });
  }

  // --- Audio analysis ----------------------------------------------------------

  Future<Map<String, AudioInfo>> audioInfo() async {
    final rows = await _db.query('audio_info');
    final result = <String, AudioInfo>{};
    for (final r in rows) {
      try {
        result[r['location'] as String] =
            AudioInfo.fromJson(jsonDecode(r['json'] as String) as Map<String, dynamic>);
      } catch (_) {
        // Corrupt row: it will simply be re-analysed.
      }
    }
    return result;
  }

  Future<void> putAudioInfo(Map<String, AudioInfo> entries) {
    final batch = _db.batch();
    entries.forEach((location, info) {
      batch.insert(
        'audio_info',
        {'location': location, 'json': jsonEncode(info.toJson())},
        conflictAlgorithm: ConflictAlgorithm.replace,
      );
    });
    return batch.commit(noResult: true);
  }

  /// Drops analysis of files that are no longer in the library.
  Future<void> retainAudioInfo(Set<String> locations) async {
    final stale = (await _db.query('audio_info', columns: ['location']))
        .map((r) => r['location'] as String)
        .where((l) => !locations.contains(l))
        .toList();
    if (stale.isEmpty) return;
    final batch = _db.batch();
    for (final l in stale) {
      batch.delete('audio_info', where: 'location = ?', whereArgs: [l]);
    }
    await batch.commit(noResult: true);
  }

  // --- Play log ----------------------------------------------------------------

  Future<List<PlayEvent>> playLog() async {
    final rows = await _db.query('play_log', orderBy: 'played_at');
    return [for (final r in rows) PlayEvent.fromRow(r)];
  }

  Future<void> addPlays(Iterable<PlayEvent> events) {
    final batch = _db.batch();
    for (final e in events) {
      batch.insert('play_log', e.toRow());
    }
    return batch.commit(noResult: true);
  }

  // --- Loudness ----------------------------------------------------------------

  Future<Map<String, LoudnessInfo>> loudness() async {
    final rows = await _db.query('loudness');
    return {
      for (final r in rows)
        if (_tryJson(r['json'] as String) case final j?) r['location'] as String: LoudnessInfo.fromJson(j),
    };
  }

  Future<void> putLoudness(Map<String, LoudnessInfo> entries) {
    final batch = _db.batch();
    entries.forEach((location, info) {
      batch.insert(
        'loudness',
        {'location': location, 'json': jsonEncode(info.toJson())},
        conflictAlgorithm: ConflictAlgorithm.replace,
      );
    });
    return batch.commit(noResult: true);
  }

  // --- Equalizer ---------------------------------------------------------------

  Future<List<EqPreset>> eqPresets() async {
    final rows = await _db.query('eq_presets');
    return [
      for (final r in rows)
        if (_tryJson(r['json'] as String) case final j?) EqPreset.fromJson(j),
    ];
  }

  Future<void> putEqPreset(EqPreset preset) => _db.insert(
        'eq_presets',
        {'id': preset.id, 'json': preset.encode()},
        conflictAlgorithm: ConflictAlgorithm.replace,
      );

  Future<void> deleteEqPreset(String id) => _db.transaction((txn) async {
        await txn.delete('eq_presets', where: 'id = ?', whereArgs: [id]);
        // Rules pointing at it would be ignored anyway; drop them.
        final rules = await txn.query('eq_rules');
        for (final r in rules) {
          final j = _tryJson(r['json'] as String);
          if (j?['preset'] == id) {
            await txn.delete('eq_rules', where: 'scope = ? AND key = ?', whereArgs: [r['scope'], r['key']]);
          }
        }
      });

  Future<List<EqRule>> eqRules() async {
    final rows = await _db.query('eq_rules');
    return [
      for (final r in rows)
        if (_tryJson(r['json'] as String) case final j?) EqRule.fromJson(j),
    ];
  }

  Future<void> putEqRule(EqRule rule) => _db.insert(
        'eq_rules',
        {'scope': rule.scope.name, 'key': rule.key, 'json': jsonEncode(rule.toJson())},
        conflictAlgorithm: ConflictAlgorithm.replace,
      );

  Future<void> deleteEqRule(EqScope scope, String key) =>
      _db.delete('eq_rules', where: 'scope = ? AND key = ?', whereArgs: [scope.name, key]);

  static Map<String, dynamic>? _tryJson(String raw) {
    try {
      return jsonDecode(raw) as Map<String, dynamic>;
    } catch (_) {
      return null;
    }
  }

  // --- Key / value -----------------------------------------------------------

  Future<Map<String, String>> allValues() async {
    final rows = await _db.query('kv');
    return {for (final r in rows) r['key'] as String: r['value'] as String};
  }

  Future<String?> getValue(String key) async {
    final rows = await _db.query('kv', where: 'key = ?', whereArgs: [key]);
    return rows.isEmpty ? null : rows.first['value'] as String;
  }

  Future<void> deleteValue(String key) => _db.delete('kv', where: 'key = ?', whereArgs: [key]);

  Future<void> setValue(String key, String value) => _db.insert(
        'kv',
        {'key': key, 'value': value},
        conflictAlgorithm: ConflictAlgorithm.replace,
      );

  Future<void> setValues(Map<String, String> values) {
    final batch = _db.batch();
    values.forEach((key, value) {
      batch.insert(
        'kv',
        {'key': key, 'value': value},
        conflictAlgorithm: ConflictAlgorithm.replace,
      );
    });
    return batch.commit(noResult: true);
  }
}

/// Everything loaded at startup, so the first frame already has the user's
/// theme, favorites and playlists (no flicker).
class Bootstrap {
  const Bootstrap({
    required this.favoriteIds,
    required this.playlists,
    required this.recentIds,
    required this.values,
    required this.audioInfo,
    required this.eqPresets,
    required this.eqRules,
    this.loudness = const {},
    this.playLog = const [],
  });

  /// Every listen, oldest first.
  final List<PlayEvent> playLog;

  /// Cached ReplayGain / loudness scans, by file location.
  final Map<String, LoudnessInfo> loudness;

  /// User-made EQ presets (built-ins live in code) and preset rules.
  final List<EqPreset> eqPresets;
  final List<EqRule> eqRules;

  final List<int> favoriteIds;
  final List<Playlist> playlists;
  final List<int> recentIds;
  final Map<String, String> values;

  /// Cached codec analysis, by file location.
  final Map<String, AudioInfo> audioInfo;

  static Future<Bootstrap> load(AppDatabase db) async {
    final (favoriteIds, playlists, recentIds, values, audioInfo, eqPresets, eqRules, loudness, playLog) = await (
      db.favoriteIds(),
      db.playlists(),
      db.recentIds(),
      db.allValues(),
      db.audioInfo(),
      db.eqPresets(),
      db.eqRules(),
      db.loudness(),
      db.playLog(),
    ).wait;
    return Bootstrap(
      favoriteIds: favoriteIds,
      playlists: playlists,
      recentIds: recentIds,
      values: values,
      audioInfo: audioInfo,
      eqPresets: eqPresets,
      eqRules: eqRules,
      loudness: loudness,
      playLog: playLog,
    );
  }
}

/// Cached tags of an audio file that is not in MediaStore.
class FileMeta {
  const FileMeta({
    required this.location,
    required this.path,
    required this.size,
    required this.modified,
    required this.readable,
    this.title,
    this.artist,
    this.album,
    this.durationMs,
    this.track,
    this.mimeType,
  });

  /// What opens the file: an absolute path or a `content://` URI.
  final String location;

  /// Readable absolute path (folders, titles, de-duplication).
  final String path;
  final int size;
  final int modified;

  /// False when the file could not be opened (corrupt / unsupported).
  final bool readable;
  final String? title;
  final String? artist;
  final String? album;
  final int? durationMs;
  final int? track;
  final String? mimeType;

  /// Still describes the file on disk?
  bool matches(int size, int modified) => this.size == size && this.modified == modified;

  factory FileMeta.fromRow(Map<String, Object?> r) => FileMeta(
        location: r['location'] as String,
        path: r['path'] as String,
        size: r['size'] as int,
        modified: r['modified'] as int,
        readable: r['readable'] == 1,
        title: r['title'] as String?,
        artist: r['artist'] as String?,
        album: r['album'] as String?,
        durationMs: r['duration_ms'] as int?,
        track: r['track'] as int?,
        mimeType: r['mime_type'] as String?,
      );

  /// From the native `readMetadata` result for a scanned file.
  factory FileMeta.fromNative(
    Map<dynamic, dynamic> m, {
    required String path,
    required int size,
    required int modified,
  }) =>
      FileMeta(
        location: m['path'] as String,
        path: path,
        size: size,
        modified: modified,
        readable: m['readable'] as bool? ?? false,
        title: m['title'] as String?,
        artist: m['artist'] as String?,
        album: m['album'] as String?,
        durationMs: (m['durationMs'] as num?)?.toInt(),
        track: (m['track'] as num?)?.toInt(),
        mimeType: m['mimeType'] as String?,
      );

  Map<String, Object?> toRow() => {
        'location': location,
        'path': path,
        'size': size,
        'modified': modified,
        'readable': readable ? 1 : 0,
        'title': title,
        'artist': artist,
        'album': album,
        'duration_ms': durationMs,
        'track': track,
        'mime_type': mimeType,
      };
}
