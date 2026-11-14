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
  /// [artist] is null when the file doesn't name one.
  Future<String?> find({
    required String title,
    required String? artist,
    String? album,
    required Duration duration,
  }) async {
    // As tagged first, then cleaned-up spellings ("Never Enough WMA",
    // "Joeboy - Show Me (Official Video)(256k)").
    for (final (title: t, artist: a) in searchVariants(title, artist)) {
      if (a == null) continue; // Too risky without an artist: another song's words.
      final exact = await _get('/api/get', {
        'track_name': t,
        'artist_name': a,
        if (album != null && album.isNotEmpty) 'album_name': album,
        if (duration > Duration.zero) 'duration': '${duration.inSeconds}',
      });
      if (exact is Map) {
        if (lyricsOf(exact) case final text?) return text;
      }
      final results = await _get('/api/search', {'track_name': t, 'artist_name': a});
      if (results is List) {
        if (pickBest(results, duration) case final text?) return text;
      }
    }
    // Free text last: finds versions the title doesn't name ("Never Enough
    // WMA" is the 80 s "Never Enough (Reprise)"); only the same artist's
    // songs, matched by length as always.
    for (final (title: t, artist: a) in searchVariants(title, artist).reversed) {
      if (a == null) continue;
      final results = await _get('/api/search', {'q': '$t $a'});
      if (results is List) {
        if (pickBest(sameArtist(results, a), duration) case final text?) return text;
      }
    }
    return null;
  }

  /// Search [results] by [artist] (as LRCLIB spells it, case aside).
  static List<dynamic> sameArtist(List<dynamic> results, String artist) {
    final want = artist.trim().toLowerCase();
    return [
      for (final r in results)
        if (r is Map && (r['artistName'] as String? ?? '').trim().toLowerCase() == want) r,
    ];
  }

  /// Bracketed parts that aren't part of a song's name.
  static final _noise = RegExp(
    r'\s*[\(\[][^\)\]]*\b(official|video|audio|lyrics?|visuali[sz]er|clip|hd|hq|4k|\d{2,3}\s?k(bps)?|kbps|mp3|m4a|flac|wma|remaster(ed)?)\b[^\)\]]*[\)\]]',
    caseSensitive: false,
  );

  /// File-format words stuck at the end of a title ("Never Enough WMA").
  static final _formatSuffix = RegExp(r'[\s._-]+(mp3|m4a|aac|flac|wav|wma|ogg|opus|alac|ape)\s*$', caseSensitive: false);

  /// Ways to ask LRCLIB for a song, most faithful first, without repeats:
  /// as tagged, then without noise, then "Artist - Title" split up when
  /// the file has no artist (or the title repeats it).
  static List<({String title, String? artist})> searchVariants(String title, String? artist) {
    String clean(String s) {
      var out = s;
      for (var i = 0; i < 3; i++) {
        out = out.replaceAll(_noise, '').replaceAll(_formatSuffix, '').trim();
      }
      return out.replaceAll(RegExp(r'\s{2,}'), ' ');
    }

    final out = <({String title, String? artist})>[];
    void add(String t, String? a) {
      final tt = t.trim(), aa = a?.trim();
      if (tt.isEmpty || out.any((v) => v.title.toLowerCase() == tt.toLowerCase() && v.artist?.toLowerCase() == aa?.toLowerCase())) return;
      out.add((title: tt, artist: aa == null || aa.isEmpty ? null : aa));
    }

    add(title, artist);
    final cleaned = clean(title);
    add(cleaned, artist);
    // "Joeboy - Show Me": the artist is in the title.
    final dash = RegExp(r'^(.+?)\s+[-–—]\s+(.+)$').firstMatch(cleaned);
    if (dash != null) {
      final (left, right) = (dash.group(1)!, clean(dash.group(2)!));
      if (artist == null || left.toLowerCase() == artist.toLowerCase()) add(right, left);
    }
    return out;
  }

  /// "[00:12.30] words" → "words": the text of synced lyrics, unsynced.
  static String plainOf(String lrc) => lrc
      .split('\n')
      .map((l) => l.replaceAll(RegExp(r'\[\d{1,3}:\d{1,2}(?:[.:]\d{1,3})?\]'), '').trim())
      .join('\n')
      .trim();

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

  /// How far another version (a video's longer intro, a radio edit) may be
  /// for its words to be shown, without timing.
  static const plainTolerance = Duration(seconds: 45);

  /// Among search [results]: those of about the song's length (when known),
  /// synced first, closest length first. A version of another length gives
  /// its words only (plain), since its timing wouldn't match.
  static String? pickBest(List<dynamic> results, Duration duration) {
    final candidates = <(Map<dynamic, dynamic>, double)>[];
    final others = <(Map<dynamic, dynamic>, double)>[];
    for (final r in results) {
      if (r is! Map || lyricsOf(r) == null) continue;
      final seconds = (r['duration'] as num?)?.toDouble();
      final gap = duration <= Duration.zero || seconds == null ? 0.0 : (seconds - duration.inMilliseconds / 1000).abs();
      if (gap <= durationTolerance.inSeconds) {
        candidates.add((r, gap));
      } else if (gap <= plainTolerance.inSeconds) {
        others.add((r, gap));
      }
    }
    if (candidates.isEmpty) {
      if (others.isEmpty) return null;
      others.sort((a, b) => a.$2.compareTo(b.$2));
      final r = others.first.$1;
      final plain = r['plainLyrics'];
      return plain is String && plain.trim().isNotEmpty ? plain : plainOf(lyricsOf(r)!);
    }
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
