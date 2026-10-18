import 'package:audifac/data/lastfm.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('signature: sorted name+value pairs, then the secret, md5 (format excluded)', () {
    final sig = LastFmClient.sign({
      'username': 'georges',
      'method': 'auth.getMobileSession',
      'password': 'päss',
      'api_key': 'KEY',
      'format': 'json',
    }, 'SECRET');
    expect(sig, '6ca2af366d6cb8d070da5e1d5e34df2c'); // md5sum of the same string
  });

  test('login sends a signed request and returns the session', () async {
    late Map<String, String> sent;
    final client = LastFmClient(apiKey: 'KEY', secret: 'SECRET', transport: (p) async {
      sent = p;
      return {'session': {'name': 'georges', 'key': 'SK123'}};
    });
    expect(await client.login('georges', 'päss'), 'SK123');
    expect(sent['method'], 'auth.getMobileSession');
    expect(sent['format'], 'json');
    expect(sent['api_sig'], LastFmClient.sign({...sent}..remove('api_sig'), 'SECRET'));
  });

  test('scrobble batches indexed fields, at most 50', () async {
    late Map<String, String> sent;
    final client = LastFmClient(apiKey: 'K', secret: 'S', transport: (p) async {
      sent = p;
      return {'scrobbles': {}};
    });
    final at = DateTime.fromMillisecondsSinceEpoch(1700000000000);
    await client.scrobble('SK', [
      for (var i = 0; i < 60; i++)
        Scrobble(artist: 'A$i', track: 'T$i', album: i.isEven ? 'B' : null, startedAt: at, duration: const Duration(minutes: 3)),
    ]);
    expect(sent['method'], 'track.scrobble');
    expect(sent['artist[0]'], 'A0');
    expect(sent['timestamp[49]'], '1700000000');
    expect(sent['duration[1]'], '180');
    expect(sent.containsKey('album[1]'), isFalse);
    expect(sent.containsKey('artist[50]'), isFalse);
  });

  test('API errors surface with their code; auth errors are recognised', () async {
    final client = LastFmClient(apiKey: 'K', secret: 'S', transport: (p) async => {'error': 9, 'message': 'Invalid session key'});
    await expectLater(
      client.nowPlaying('SK', artist: 'a', track: 't'),
      throwsA(isA<LastFmException>().having((e) => e.isAuth, 'isAuth', isTrue)),
    );
    expect(const LastFmException(11, 'Service offline').isAuth, isFalse);
  });

  test('queued scrobbles survive JSON', () {
    final s = Scrobble(artist: 'Asake', track: 'Lonely', album: 'Work of Art', startedAt: DateTime(2026, 10, 18, 9), duration: const Duration(seconds: 200));
    final back = Scrobble.fromJson(s.toJson().cast<String, dynamic>())!;
    expect(back.artist, 'Asake');
    expect(back.startedAt, s.startedAt);
    expect(back.duration, s.duration);
    expect(Scrobble.fromJson({'artist': 'x'}), isNull);
  });
}
