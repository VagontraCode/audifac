import 'dart:convert';
import 'dart:io';

/// Lyrics from LRCLIB (lrclib.net): free, no account, synced (LRC) when
/// available. Only asked when the user taps "Search online".
class LrcLib {
  static const _host = 'lrclib.net';

  /// LRCLIB asks clients to name themselves. The app, never the user.
  static const _userAgent = 'audifac (local music player)';

  /// How far a result's length may be from the song's.
  static const durationTolerance = Duration(seconds: 3);

  /// The best lyrics for a song (LRC text, synced preferred), or null.
  Future<String?> find({
    required String title,
    required String artist,
    String? album,
    required Duration duration,
  }) async {
    // Exact lookup first (title + artist + album + length), then a search.
    final exact = await _get('/api/get', {
      'track_name': title,
      'artist_name': artist,
      if (album != null && album.isNotEmpty) 'album_name': album,
      if (duration > Duration.zero) 'duration': '${duration.inSeconds}',
    });
    if (exact is Map) {
      if (lyricsOf(exact) case final text?) return text;
    }
    final results = await _get('/api/search', {'track_name': title, 'artist_name': artist});
    if (results is! List) return null;
    return pickBest(results, duration);
  }

  /// The lyrics text of one LRCLIB record: synced, else plain, else null
  /// (instrumentals and empty records).
  static String? lyricsOf(Map<dynamic, dynamic> record) {
    if (record['instrumental'] == true) return null;
    for (final field in ['syncedLyrics', 'plainLyrics']) {
      final text = record[field];
      if (text is String && text.trim().isNotEmpty) return text;
    }
    return null;
  }

  /// Among search [results]: those of about the song's length (when known),
  /// synced first, closest length first.
  static String? pickBest(List<dynamic> results, Duration duration) {
    final candidates = <(Map<dynamic, dynamic>, double)>[];
    for (final r in results) {
      if (r is! Map || lyricsOf(r) == null) continue;
      final seconds = (r['duration'] as num?)?.toDouble();
      final gap = duration <= Duration.zero || seconds == null ? 0.0 : (seconds - duration.inMilliseconds / 1000).abs();
      if (gap > durationTolerance.inSeconds) continue;
      candidates.add((r, gap));
    }
    if (candidates.isEmpty) return null;
    int synced(Map<dynamic, dynamic> r) => r['syncedLyrics'] is String && (r['syncedLyrics'] as String).trim().isNotEmpty ? 0 : 1;
    candidates.sort((a, b) {
      final bySync = synced(a.$1).compareTo(synced(b.$1));
      return bySync != 0 ? bySync : a.$2.compareTo(b.$2);
    });
    return lyricsOf(candidates.first.$1);
  }

  /// JSON from LRCLIB; null when not found. Throws [IOException] when the
  /// network fails.
  Future<Object?> _get(String path, Map<String, String> query) async {
    final client = HttpClient()
      ..connectionTimeout = const Duration(seconds: 10)
      ..userAgent = _userAgent;
    try {
      final request = await client.getUrl(Uri.https(_host, path, query));
      final response = await request.close().timeout(const Duration(seconds: 15));
      final body = await response.transform(utf8.decoder).join();
      if (response.statusCode == HttpStatus.notFound) return null;
      if (response.statusCode != HttpStatus.ok) throw HttpException('LRCLIB answered ${response.statusCode}');
      try {
        return jsonDecode(body);
      } on FormatException {
        throw const HttpException('LRCLIB answered something unreadable');
      }
    } finally {
      client.close();
    }
  }
}
