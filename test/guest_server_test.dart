import 'dart:convert';
import 'dart:io';

import 'package:audifac/transfer/guest_server.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  late GuestServer server;
  final client = HttpClient();

  setUp(() async {
    server = GuestServer(
      page: '<html>guest page</html>',
      search: (q) => [for (var i = 0; i < 40; i++) (id: i, title: 'Song $i $q', artist: 'Artist')],
    );
    await server.start(address: InternetAddress.loopbackIPv4);
  });

  tearDown(() => server.dispose());

  Future<(int, String)> call(String method, String path, [Object? json]) async {
    final request = await client.openUrl(method, Uri.parse('http://127.0.0.1:${server.port}$path'));
    if (json != null) {
      final bytes = utf8.encode(jsonEncode(json));
      request.headers.contentType = ContentType.json;
      request.contentLength = bytes.length;
      request.add(bytes);
    }
    final response = await request.close();
    return (response.statusCode, await response.transform(utf8.decoder).join());
  }

  test('nothing without the token', () async {
    expect((await call('GET', '/')).$1, 404);
    expect((await call('GET', '/zzzzzz/search?q=ab')).$1, 404);
    expect((await call('GET', '/${server.token}/')).$2, contains('guest page'));
  });

  test('search answers at most 25 songs, not for one letter', () async {
    final (_, one) = await call('GET', '/${server.token}/search?q=a');
    expect(jsonDecode(one), isEmpty);
    final (_, body) = await call('GET', '/${server.token}/search?q=love');
    final list = jsonDecode(body) as List;
    expect(list, hasLength(25));
    expect(list.first, {'id': 0, 'title': 'Song 0 love', 'artist': 'Artist'});
  });

  test('requests reach the host; a guest is limited to 5 a minute', () async {
    final got = <GuestRequest>[];
    server.requests.listen(got.add);
    for (var i = 0; i < 5; i++) {
      expect((await call('POST', '/${server.token}/request', {'id': i, 'from': 'Ama'})).$1, 200);
    }
    expect((await call('POST', '/${server.token}/request', {'id': 9, 'from': 'Ama'})).$1, 429);
    expect((await call('POST', '/${server.token}/request', {'id': 9, 'from': 'Kofi'})).$1, 200);
    await Future<void>.delayed(Duration.zero);
    expect(got.map((r) => r.songId), [0, 1, 2, 3, 4, 9]);
    expect(got.last.from, ['Kofi']);
  });

  test('garbage is refused', () async {
    expect((await call('POST', '/${server.token}/request', {'nope': 1})).$1, 400);
  });
}
