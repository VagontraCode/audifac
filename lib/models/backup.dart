import 'dart:convert';

import 'song.dart';
import 'tag_edit.dart';

/// A song reference that survives a new phone: MediaStore ids change between
/// devices, so songs are identified by storage-relative path and tags.
class SongRef {
  const SongRef({
    this.relativePath,
    required this.title,
    required this.artist,
    required this.album,
    required this.durationMs,
  });

  /// Path below the storage volume, e.g. `Music/Album/01 Song.flac`.
  final String? relativePath;
  final String title;
  final String artist;
  final String album;
  final int durationMs;

  static final _volume = RegExp(r'^/storage/(?:emulated/\d+|[0-9A-Fa-f]{4}-[0-9A-Fa-f]{4})/');

  /// `/storage/emulated/0/Music/a.mp3` → `Music/a.mp3` (also SD cards).
  static String? relative(String? path) {
    if (path == null) return null;
    final m = _volume.firstMatch(path);
    return m == null ? path : path.substring(m.end);
  }

  factory SongRef.of(Song s) => SongRef(
        relativePath: relative(s.path),
        title: s.title,
        artist: s.artist,
        album: s.album,
        durationMs: s.duration.inMilliseconds,
      );

  Map<String, Object?> toJson() => {
        'path': relativePath,
        'title': title,
        'artist': artist,
        'album': album,
        'ms': durationMs,
      };

  factory SongRef.fromJson(Map<String, dynamic> j) => SongRef(
        relativePath: j['path'] as String?,
        title: j['title'] as String? ?? '',
        artist: j['artist'] as String? ?? '',
        album: j['album'] as String? ?? '',
        durationMs: (j['ms'] as num?)?.toInt() ?? 0,
      );
}

/// Resolves [SongRef]s against the songs on this device.
class SongMatcher {
  SongMatcher(Iterable<Song> songs) {
    for (final s in songs) {
      final rel = SongRef.relative(s.path);
      if (rel != null) _byPath[rel.toLowerCase()] = s;
      _byTags.putIfAbsent(_tagKey(s.title, s.artist), () => []).add(s);
    }
  }

  final _byPath = <String, Song>{};
  final _byTags = <String, List<Song>>{};

  static String _tagKey(String title, String artist) =>
      '${title.trim().toLowerCase()}\u0000${artist.trim().toLowerCase()}';

  /// Same file path first; otherwise same title + artist, preferring the same
  /// album and a duration within 3 s.
  Song? match(SongRef ref) {
    final byPath = ref.relativePath == null ? null : _byPath[ref.relativePath!.toLowerCase()];
    if (byPath != null) return byPath;
    final candidates = _byTags[_tagKey(ref.title, ref.artist)];
    if (candidates == null || candidates.isEmpty) return null;
    int score(Song s) {
      var v = 0;
      if (s.album.toLowerCase() == ref.album.toLowerCase()) v += 2;
      if (ref.durationMs == 0 || (s.duration.inMilliseconds - ref.durationMs).abs() <= 3000) v += 1;
      return v;
    }
    final best = candidates.reduce((a, b) => score(b) > score(a) ? b : a);
    // Same title + artist but a very different length is a different recording.
    if (ref.durationMs > 0 && (best.duration.inMilliseconds - ref.durationMs).abs() > 15000) return null;
    return best;
  }
}

class PlaylistBackup {
  const PlaylistBackup({required this.name, required this.songs});

  final String name;
  final List<SongRef> songs;

  Map<String, Object?> toJson() => {'name': name, 'songs': [for (final s in songs) s.toJson()]};

  factory PlaylistBackup.fromJson(Map<String, dynamic> j) => PlaylistBackup(
        name: j['name'] as String? ?? 'Playlist',
        songs: [for (final s in (j['songs'] as List? ?? const []).cast<Map<String, dynamic>>()) SongRef.fromJson(s)],
      );
}

/// An EQ rule with its target made portable (song / album refs instead of ids).
class RuleBackup {
  const RuleBackup({required this.scope, required this.presetId, this.key, this.label = '', this.song, this.album, this.albumArtist});

  final String scope;
  final String presetId;

  /// For artist / genre / source rules (portable as-is).
  final String? key;
  final String label;
  final SongRef? song;
  final String? album;
  final String? albumArtist;

  Map<String, Object?> toJson() => {
        'scope': scope,
        'preset': presetId,
        'key': ?key,
        'label': label,
        if (song != null) 'song': song!.toJson(),
        'album': ?album,
        'albumArtist': ?albumArtist,
      };

  factory RuleBackup.fromJson(Map<String, dynamic> j) => RuleBackup(
        scope: j['scope'] as String,
        presetId: j['preset'] as String,
        key: j['key'] as String?,
        label: j['label'] as String? ?? '',
        song: j['song'] == null ? null : SongRef.fromJson(j['song'] as Map<String, dynamic>),
        album: j['album'] as String?,
        albumArtist: j['albumArtist'] as String?,
      );
}

/// Everything a user would hate to lose, as one JSON document.
class BackupData {
  const BackupData({
    required this.exportedAt,
    required this.appVersion,
    this.favorites = const [],
    this.recent = const [],
    this.playlists = const [],
    this.eqPresets = const [],
    this.eqRules = const [],
    this.eqSettings,
    this.settings = const {},
    this.plays = const [],
    this.tagEdits = const [],
  });

  static const format = 'audifac-backup';
  static const version = 1;

  final DateTime exportedAt;
  final String appVersion;
  final List<SongRef> favorites;
  final List<SongRef> recent;
  final List<PlaylistBackup> playlists;

  /// User EQ presets as stored (`EqPreset.toJson`).
  final List<Map<String, dynamic>> eqPresets;
  final List<RuleBackup> eqRules;

  /// `EqSettings.encode()` output.
  final String? eqSettings;

  /// App settings key/values (theme, sort, filters, library options).
  final Map<String, String> settings;

  /// Listening history behind play counts and stats.
  final List<PlaysBackup> plays;

  /// Tags corrected in the app (the songs as their files tag them).
  final List<TagEditBackup> tagEdits;

  String encode() => const JsonEncoder.withIndent('  ').convert({
        'format': format,
        'version': version,
        'exportedAt': exportedAt.toIso8601String(),
        'appVersion': appVersion,
        'favorites': [for (final s in favorites) s.toJson()],
        'recent': [for (final s in recent) s.toJson()],
        'playlists': [for (final p in playlists) p.toJson()],
        'eq': {
          'presets': eqPresets,
          'rules': [for (final r in eqRules) r.toJson()],
          'settings': eqSettings,
        },
        'settings': settings,
        'plays': [for (final p in plays) p.toJson()],
        'tagEdits': [for (final t in tagEdits) t.toJson()],
      });

  /// Throws [FormatException] for files that aren't audifac backups.
  static BackupData decode(String text) {
    final Object? raw;
    try {
      raw = jsonDecode(text);
    } catch (_) {
      throw const FormatException('Not a JSON file');
    }
    if (raw is! Map<String, dynamic> || raw['format'] != format) {
      throw const FormatException('Not an audifac backup');
    }
    final v = (raw['version'] as num?)?.toInt() ?? 0;
    if (v > version) throw FormatException('Made by a newer audifac (backup v$v)');

    List<SongRef> refs(Object? list) => [
          for (final s in (list as List? ?? const []).cast<Map<String, dynamic>>()) SongRef.fromJson(s),
        ];
    final eq = raw['eq'] as Map<String, dynamic>? ?? const {};
    return BackupData(
      exportedAt: DateTime.tryParse(raw['exportedAt'] as String? ?? '') ?? DateTime.fromMillisecondsSinceEpoch(0),
      appVersion: raw['appVersion'] as String? ?? '?',
      favorites: refs(raw['favorites']),
      recent: refs(raw['recent']),
      playlists: [
        for (final p in (raw['playlists'] as List? ?? const []).cast<Map<String, dynamic>>()) PlaylistBackup.fromJson(p),
      ],
      eqPresets: (eq['presets'] as List? ?? const []).cast<Map<String, dynamic>>(),
      eqRules: [for (final r in (eq['rules'] as List? ?? const []).cast<Map<String, dynamic>>()) RuleBackup.fromJson(r)],
      eqSettings: eq['settings'] as String?,
      settings: (raw['settings'] as Map? ?? const {}).map((k, v) => MapEntry('$k', '$v')),
      plays: [for (final p in (raw['plays'] as List? ?? const []).cast<Map<String, dynamic>>()) PlaysBackup.fromJson(p)],
      tagEdits: [
        for (final t in (raw['tagEdits'] as List? ?? const []).cast<Map<String, dynamic>>()) TagEditBackup.fromJson(t),
      ],
    );
  }
}

/// What a restore did, for the summary dialog.
class RestoreReport {
  int favorites = 0;
  int playlists = 0;
  int playlistSongs = 0;
  int presets = 0;
  int rules = 0;
  int recent = 0;
  int plays = 0;
  int tagEdits = 0;
  int missingSongs = 0;
  bool settings = false;
}

/// One song's listens: `[startMs, listenedMs, counted]` triples.
class PlaysBackup {
  const PlaysBackup({required this.song, required this.events});

  final SongRef song;
  final List<(int at, int listenedMs, bool counted)> events;

  Map<String, Object?> toJson() => {
        'song': song.toJson(),
        'events': [for (final e in events) [e.$1, e.$2, if (e.$3) 1 else 0]],
      };

  factory PlaysBackup.fromJson(Map<String, dynamic> j) => PlaysBackup(
        song: SongRef.fromJson((j['song'] as Map).cast<String, dynamic>()),
        events: [
          for (final e in (j['events'] as List? ?? const []).cast<List<dynamic>>())
            if (e.length >= 3) ((e[0] as num).toInt(), (e[1] as num).toInt(), e[2] == 1),
        ],
      );
}

/// One song's in-app tag corrections.
class TagEditBackup {
  const TagEditBackup({required this.song, required this.edit});

  final SongRef song;
  final TagEdit edit;

  Map<String, Object?> toJson() => {'song': song.toJson(), 'edit': edit.toJson()};

  factory TagEditBackup.fromJson(Map<String, dynamic> j) => TagEditBackup(
        song: SongRef.fromJson((j['song'] as Map).cast<String, dynamic>()),
        edit: TagEdit.fromJson((j['edit'] as Map? ?? const {}).cast<String, dynamic>()),
      );
}
