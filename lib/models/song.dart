/// A playable track: either indexed by Android's MediaStore (positive [id],
/// `content://` [uri]) or found by our own storage scan in a folder Android
/// won't index (negative [id], `file://` [uri]).
class Song {
  final int id;
  final String uri;
  final String? path;
  final String title;
  final String artist;
  final int artistId;
  final String album;
  final int albumId;
  final Duration duration;
  final int trackNumber;
  final DateTime dateAdded;
  final String? mimeType;

  /// File size and last modification (ms since epoch); together with the
  /// location they tell whether cached audio analysis is still valid.
  final int sizeBytes;
  final int modifiedMs;

  /// MediaStore type flags (used to hide ringtones, voice notes, …).
  final bool isMusic;
  final bool isSystemSound;
  final bool isRecording;
  final bool isPodcast;

  const Song({
    required this.id,
    required this.uri,
    this.path,
    required this.title,
    required this.artist,
    required this.artistId,
    required this.album,
    required this.albumId,
    required this.duration,
    this.trackNumber = 0,
    required this.dateAdded,
    this.mimeType,
    this.sizeBytes = 0,
    this.modifiedMs = 0,
    this.isMusic = true,
    this.isSystemSound = false,
    this.isRecording = false,
    this.isPodcast = false,
  });

  static const unknownArtist = 'Unknown artist';
  static const unknownAlbum = 'Unknown album';

  /// True for files outside MediaStore, played straight from their path (or
  /// from a folder granted through the system picker).
  bool get isFile => id < 0;

  /// What the native side opens: a `content://` URI or an absolute path.
  String get location => uri.startsWith('content://') ? uri : (path ?? uri);

  /// Containing folder, e.g. `/storage/emulated/0/Download`.
  String? get folder {
    final p = path;
    if (p == null) return null;
    final cut = p.lastIndexOf('/');
    return cut > 0 ? p.substring(0, cut) : null;
  }

  static String _clean(Object? value, String fallback) {
    final s = (value as String?)?.trim();
    // MediaStore reports missing tags as "<unknown>".
    if (s == null || s.isEmpty || s == '<unknown>') return fallback;
    return s;
  }

  factory Song.fromMap(Map<dynamic, dynamic> map) {
    final path = map['path'] as String?;
    return Song(
      id: (map['id'] as num).toInt(),
      uri: map['uri'] as String,
      path: path,
      title: tidyTitle(_clean(map['title'], 'Untitled')),
      artist: _clean(map['artist'], unknownArtist),
      artistId: (map['artistId'] as num?)?.toInt() ?? 0,
      album: _clean(map['album'], unknownAlbum),
      albumId: (map['albumId'] as num?)?.toInt() ?? 0,
      duration: Duration(milliseconds: (map['durationMs'] as num?)?.toInt() ?? 0),
      // MediaStore encodes disc number in the thousands (e.g. 2003 = disc 2, track 3).
      trackNumber: (map['track'] as num?)?.toInt() ?? 0,
      dateAdded: DateTime.fromMillisecondsSinceEpoch(
        ((map['dateAdded'] as num?)?.toInt() ?? 0) * 1000,
      ),
      mimeType: map['mimeType'] as String?,
      sizeBytes: (map['size'] as num?)?.toInt() ?? 0,
      modifiedMs: ((map['dateModified'] as num?)?.toInt() ?? 0) * 1000,
      isMusic: map['isMusic'] as bool? ?? true,
      isSystemSound: map['isSystemSound'] as bool? ?? false,
      isRecording: (map['isRecording'] as bool? ?? false) || looksLikeRecording(path),
      isPodcast: map['isPodcast'] as bool? ?? false,
    );
  }

  /// A file found by our storage scan, with tags read by the native side.
  ///
  /// [location] defaults to [path]; pass a `content://` URI for files in
  /// folders granted through the system picker.
  factory Song.fromFile({
    required String path,
    String? location,
    required int modifiedMs,
    int sizeBytes = 0,
    String? title,
    String? artist,
    String? album,
    int? durationMs,
    int? track,
    String? mimeType,
  }) {
    final name = path.substring(path.lastIndexOf('/') + 1);
    final dot = name.lastIndexOf('.');
    final baseName = dot > 0 ? name.substring(0, dot) : name;
    final folder = path.substring(0, path.lastIndexOf('/').clamp(0, path.length));
    final cleanAlbum = _clean(album, unknownAlbum);
    final cleanArtist = _clean(artist, unknownArtist);
    final opens = location ?? path;
    return Song(
      id: -stableId(path),
      uri: opens.startsWith('content://') ? opens : Uri.file(opens).toString(),
      path: path,
      title: tidyTitle(_clean(title, baseName)),
      artist: cleanArtist,
      artistId: -stableId('artist:$cleanArtist'),
      album: cleanAlbum,
      // Untagged files are grouped per folder rather than into one huge
      // "Unknown album".
      albumId: -stableId('album:${album == null ? folder : '$cleanArtist/$cleanAlbum'}'),
      duration: Duration(milliseconds: durationMs ?? 0),
      trackNumber: track ?? 0,
      dateAdded: DateTime.fromMillisecondsSinceEpoch(modifiedMs),
      mimeType: mimeType,
      sizeBytes: sizeBytes,
      modifiedMs: modifiedMs,
      isRecording: looksLikeRecording(path),
    );
  }

  /// Untagged files get their file name as title (`My_Song_(Live)`): turn
  /// underscores into spaces when the title has no spaces of its own.
  static String tidyTitle(String title) =>
      title.contains('_') && !title.contains(' ') ? title.replaceAll('_', ' ') : title;

  /// Voice notes / call & voice recorder output, by folder name.
  static bool looksLikeRecording(String? path) {
    if (path == null) return false;
    final p = path.toLowerCase();
    return const [
      '/recordings/',
      '/voice notes/',
      '/whatsapp voice notes/',
      '/voice recorder/',
      '/soundrecorder/',
      '/call/',
      '/callrecord',
      '/call recordings/',
    ].any(p.contains);
  }

  /// Positive 52-bit FNV-1a hash: stable across runs (unlike `String.hashCode`)
  /// and safe as a Dart int on every platform.
  static int stableId(String key) {
    var hash = 0xcbf29ce484222325;
    for (final unit in key.codeUnits) {
      hash ^= unit;
      hash *= 0x100000001b3; // Wraps at 64 bits on the Dart VM.
    }
    final id = hash & 0xFFFFFFFFFFFFF;
    return id == 0 ? 1 : id;
  }

  @override
  bool operator ==(Object other) => other is Song && other.id == id;

  @override
  int get hashCode => id.hashCode;
}
