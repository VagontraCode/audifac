import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';

/// Sends one signed request; returns the decoded JSON (throws on HTTP errors).
typedef LastFmTransport = Future<Map<String, dynamic>> Function(Map<String, String> params);

/// What the user registered at last.fm/api, plus the session from logging in.
class LastFmAccount {
  const LastFmAccount({required this.apiKey, required this.secret, this.username, this.sessionKey});

  final String apiKey;
  final String secret;
  final String? username;
  final String? sessionKey;

  bool get connected => sessionKey != null && sessionKey!.isNotEmpty;

  Map<String, Object?> toJson() => {'apiKey': apiKey, 'secret': secret, 'username': username, 'sessionKey': sessionKey};

  static LastFmAccount? fromJson(Map<String, dynamic>? j) {
    if (j == null || j['apiKey'] is! String || j['secret'] is! String) return null;
    return LastFmAccount(
      apiKey: j['apiKey'] as String,
      secret: j['secret'] as String,
      username: j['username'] as String?,
      sessionKey: j['sessionKey'] as String?,
    );
  }
}

/// A listen waiting to be scrobbled.
class Scrobble {
  const Scrobble({required this.artist, required this.track, this.album, required this.startedAt, this.duration});

  final String artist;
  final String track;
  final String? album;
  final DateTime startedAt;
  final Duration? duration;

  Map<String, Object?> toJson() => {
        'artist': artist,
        'track': track,
        'album': album,
        'at': startedAt.millisecondsSinceEpoch,
        'ms': duration?.inMilliseconds,
      };

  static Scrobble? fromJson(Map<String, dynamic> j) {
    if (j['artist'] is! String || j['track'] is! String || j['at'] is! num) return null;
    return Scrobble(
      artist: j['artist'] as String,
      track: j['track'] as String,
      album: j['album'] as String?,
      startedAt: DateTime.fromMillisecondsSinceEpoch((j['at'] as num).toInt()),
      duration: j['ms'] == null ? null : Duration(milliseconds: (j['ms'] as num).toInt()),
    );
  }
}

class LastFmException implements Exception {
  const LastFmException(this.code, this.message);

  final int code;
  final String message;

  /// Bad credentials / revoked session: retrying won't help.
  bool get isAuth => code == 4 || code == 9 || code == 10 || code == 14 || code == 26;

  @override
  String toString() => 'Last.fm error $code: $message';
}

/// The few Last.fm API calls a player needs.
class LastFmClient {
  LastFmClient({required this.apiKey, required this.secret, LastFmTransport? transport})
      : _transport = transport ?? _httpPost;

  static const endpoint = 'https://ws.audioscrobbler.com/2.0/';

  /// At most this many scrobbles per request (API limit).
  static const batch = 50;

  final String apiKey;
  final String secret;
  final LastFmTransport _transport;

  /// md5 of the sorted parameters (name + value, without `format`) + secret.
  static String sign(Map<String, String> params, String secret) {
    final keys = params.keys.where((k) => k != 'format' && k != 'callback').toList()..sort();
    final buffer = StringBuffer();
    for (final k in keys) {
      buffer
        ..write(k)
        ..write(params[k]);
    }
    buffer.write(secret);
    return md5.convert(utf8.encode(buffer.toString())).toString();
  }

  Future<Map<String, dynamic>> _call(String method, Map<String, String> params) async {
    final all = {...params, 'method': method, 'api_key': apiKey};
    all['api_sig'] = sign(all, secret);
    all['format'] = 'json';
    final json = await _transport(all);
    if (json['error'] != null) {
      throw LastFmException((json['error'] as num).toInt(), json['message'] as String? ?? '');
    }
    return json;
  }

  /// Logs in; returns the session key (the password isn't kept).
  Future<String> login(String username, String password) async {
    final json = await _call('auth.getMobileSession', {'username': username, 'password': password});
    final key = (json['session'] as Map?)?['key'] as String?;
    if (key == null) throw const LastFmException(0, 'No session in the answer');
    return key;
  }

  Future<void> nowPlaying(String sessionKey, {required String artist, required String track, String? album, Duration? duration}) =>
      _call('track.updateNowPlaying', {
        'sk': sessionKey,
        'artist': artist,
        'track': track,
        if (album != null && album.isNotEmpty) 'album': album,
        if (duration != null && duration > Duration.zero) 'duration': '${duration.inSeconds}',
      });

  /// Scrobbles up to [batch] listens in one request.
  Future<void> scrobble(String sessionKey, List<Scrobble> items) {
    final params = <String, String>{'sk': sessionKey};
    for (final (i, s) in items.take(batch).indexed) {
      params['artist[$i]'] = s.artist;
      params['track[$i]'] = s.track;
      params['timestamp[$i]'] = '${s.startedAt.millisecondsSinceEpoch ~/ 1000}';
      if (s.album != null && s.album!.isNotEmpty) params['album[$i]'] = s.album!;
      if (s.duration != null && s.duration! > Duration.zero) params['duration[$i]'] = '${s.duration!.inSeconds}';
    }
    return _call('track.scrobble', params);
  }

  static Future<Map<String, dynamic>> _httpPost(Map<String, String> params) async {
    final client = HttpClient()..connectionTimeout = const Duration(seconds: 15);
    try {
      final request = await client.postUrl(Uri.parse(endpoint));
      request.headers.contentType = ContentType('application', 'x-www-form-urlencoded', charset: 'utf-8');
      request.write(Uri(queryParameters: params).query);
      final response = await request.close().timeout(const Duration(seconds: 20));
      final body = await response.transform(utf8.decoder).join();
      try {
        return jsonDecode(body) as Map<String, dynamic>;
      } on FormatException {
        throw HttpException('Last.fm answered ${response.statusCode}');
      }
    } finally {
      client.close();
    }
  }
}
