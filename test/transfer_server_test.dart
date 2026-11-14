import 'dart:convert';
import 'dart:io';

import 'package:audifac/transfer/transfer_server.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  late Directory temp;
  late TransferServer server;
  final imported = <String, List<int>>{};
  final client = HttpClient();

  setUp(() async {
    temp = await Directory.systemTemp.createTemp('transfer_test');
    imported.clear();
    server = TransferServer(
      tempDir: temp,
      page: '<html>upload page</html>',
      import: (file, name) async {
        imported[name] = await file.readAsBytes();
        return null;
      },
    );
    await server.start(address: InternetAddress.loopbackIPv4);
  });

  tearDown(() async {
    await server.dispose();
    await temp.delete(recursive: true);
  });

  Future<(int, String)> send(String method, String path, [List<int>? body]) async {
    final request = await client.openUrl(method, Uri.parse('http://127.0.0.1:${server.port}$path'));
    if (body != null) {
      request.contentLength = body.length;
      request.add(body);
    }
    final response = await request.close();
    return (response.statusCode, await response.transform(utf8.decoder).join());
  }

  test('the page needs the token', () async {
    expect((await send('GET', '/')).$1, 404);
    expect((await send('GET', '/wrong1/')).$1, 404);
    final (status, body) = await send('GET', '/${server.token}/');
    expect(status, 200);
    expect(body, contains('upload page'));
  });

  test('saves an audio file byte for byte, then removes the temp copy', () async {
    final bytes = List.generate(300000, (i) => i % 251);
    final (status, _) = await send('PUT', '/${server.token}/upload?name=My%20Song.flac', bytes);
    expect(status, 200);
    expect(imported['My Song.flac'], bytes);
    expect(temp.listSync(), isEmpty);
  });

  test('refuses non-audio files, folder tricks and a wrong token', () async {
    expect((await send('PUT', '/${server.token}/upload?name=evil.apk', [1, 2, 3])).$1, 415);
    expect((await send('PUT', '/nope42/upload?name=a.mp3', [1, 2, 3])).$1, 404);
    final (status, _) = await send('PUT', '/${server.token}/upload?name=..%2F..%2Fdata%2Fx.mp3', [1, 2, 3]);
    expect(status, 200);
    expect(imported.keys, ['x.mp3'], reason: 'only the file name is kept');
  });

  test('file names are cleaned', () {
    expect(TransferServer.sanitizeName(r'C:\Music\a:b?.mp3'), 'a_b_.mp3');
    expect(TransferServer.sanitizeName('...hidden.mp3'), 'hidden.mp3');
    expect(TransferServer.sanitizeName('   '), isNull);
    expect(TransferServer.isAccepted('Track.FLAC'), isTrue);
    expect(TransferServer.isAccepted('song.lrc'), isTrue);
    expect(TransferServer.isAccepted('virus.exe'), isFalse);
    expect(TransferServer.isAccepted('noextension'), isFalse);
  });
}
