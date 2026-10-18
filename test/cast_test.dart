import 'dart:io';
import 'dart:typed_data';

import 'package:audifac/cast/cast_server.dart';
import 'package:audifac/cast/cast_target.dart';
import 'package:audifac/cast/chromecast.dart';
import 'package:audifac/cast/dlna.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('HTTP ranges', () {
    test('parse', () {
      expect(CastServer.parseRange('bytes=0-99', 1000), (0, 99));
      expect(CastServer.parseRange('bytes=500-', 1000), (500, 999));
      expect(CastServer.parseRange('bytes=-200', 1000), (800, 999));
      expect(CastServer.parseRange('bytes=900-5000', 1000), (900, 999));
      expect(CastServer.parseRange('bytes=1000-', 1000), isNull);
      expect(CastServer.parseRange('items=0-1', 1000), isNull);
      expect(CastServer.parseRange(null, 1000), isNull);
    });

    test('the server serves shared files only, with ranges', () async {
      final dir = await Directory.systemTemp.createTemp('cast');
      final file = File('${dir.path}/song.mp3')..writeAsBytesSync(List.generate(1000, (i) => i % 256));
      final server = CastServer()..host = '127.0.0.1';
      await server.start();
      final url = server.share(file.path, 'audio/mpeg');
      final client = HttpClient();
      try {
        final full = await (await client.getUrl(Uri.parse(url))).close();
        expect(full.statusCode, 200);
        expect(full.headers.contentType?.mimeType, 'audio/mpeg');
        expect((await full.fold<List<int>>([], (a, b) => a..addAll(b))).length, 1000);

        final req = await client.getUrl(Uri.parse(url));
        req.headers.set(HttpHeaders.rangeHeader, 'bytes=10-19');
        final part = await req.close();
        expect(part.statusCode, 206);
        expect(part.headers.value(HttpHeaders.contentRangeHeader), 'bytes 10-19/1000');
        expect(await part.fold<List<int>>([], (a, b) => a..addAll(b)), List.generate(10, (i) => 10 + i));

        final other = await (await client.getUrl(Uri.parse(url.replaceAll(RegExp(r'/a/[0-9a-f]+'), '/a/deadbeef')))).close();
        expect(other.statusCode, 404);
        await other.drain<void>();
      } finally {
        client.close(force: true);
        await server.stop();
        await dir.delete(recursive: true);
      }
    });
  });

  test('Cast V2 frames round-trip (protobuf by hand)', () {
    const frame = CastFrame(
      source: 'sender-0',
      destination: 'receiver-0',
      namespace: 'urn:x-cast:com.google.cast.tp.connection',
      payload: '{"type":"CONNECT","note":"é ✓"}',
    );
    final bytes = frame.encode();
    final length = ByteData.view(bytes.buffer).getUint32(0);
    expect(length, bytes.length - 4);
    final back = CastFrame.decode(Uint8List.sublistView(bytes, 4))!;
    expect(back.source, frame.source);
    expect(back.destination, frame.destination);
    expect(back.namespace, frame.namespace);
    expect(back.payload, frame.payload);
    // A long payload needs a multi-byte length varint.
    final big = CastFrame(source: 'a', destination: 'b', namespace: 'c', payload: 'x' * 1000);
    expect(CastFrame.decode(Uint8List.sublistView(big.encode(), 4))!.payload.length, 1000);
  });

  group('DLNA', () {
    test('end to end: load → the renderer fetches the file, plays, pauses, reports', () async {
      final (renderer, actions, fetched) = await _fakeRenderer();
      final dir = await Directory.systemTemp.createTemp('cast');
      final file = File('${dir.path}/song.flac')..writeAsBytesSync(List.filled(4321, 7));
      final server = CastServer()..host = '127.0.0.1';
      await server.start();
      final base = Uri.parse('http://127.0.0.1:${renderer.port}/');
      final session = DlnaSession(DlnaTarget(id: 'x', name: 'Fake TV', avTransport: base.resolve('avt'), renderingControl: base.resolve('rc')));
      try {
        await session.load(CastMedia(url: server.share(file.path, 'audio/flac'), mime: 'audio/flac', title: 'T'));
        expect(await fetched(), 4321);
        var s = await session.status();
        expect(s.playback, CastPlayback.playing);
        expect(s.position, const Duration(seconds: 7));
        expect(s.duration, const Duration(minutes: 3));
        await session.pause();
        s = await session.status();
        expect(s.playback, CastPlayback.paused);
        await session.setVolume(0.4);
        expect(actions, containsAllInOrder(['SetAVTransportURI', 'Play', 'Pause', 'SetVolume']));
      } finally {
        await session.close();
        await server.stop();
        await renderer.close(force: true);
        await dir.delete(recursive: true);
      }
    });

    const description = '''<?xml version="1.0"?>
<root xmlns="urn:schemas-upnp-org:device-1-0">
  <device>
    <deviceType>urn:schemas-upnp-org:device:MediaRenderer:1</deviceType>
    <friendlyName>Living Room TV &amp; Sound</friendlyName>
    <UDN>uuid:1234</UDN>
    <serviceList>
      <service>
        <serviceType>urn:schemas-upnp-org:service:RenderingControl:1</serviceType>
        <controlURL>/upnp/control/rc</controlURL>
      </service>
      <service>
        <serviceType>urn:schemas-upnp-org:service:AVTransport:1</serviceType>
        <controlURL>upnp/control/avt</controlURL>
      </service>
    </serviceList>
  </device>
</root>''';

    test('device description → renderer with control URLs', () {
      final t = DlnaTarget.parseDescription(description, Uri.parse('http://192.168.1.20:49152/description.xml'))!;
      expect(t.name, 'Living Room TV & Sound');
      expect(t.id, 'uuid:1234');
      expect(t.avTransport.toString(), 'http://192.168.1.20:49152/upnp/control/avt');
      expect(t.renderingControl.toString(), 'http://192.168.1.20:49152/upnp/control/rc');
      expect(DlnaTarget.parseDescription('<root><friendlyName>x</friendlyName></root>', Uri.parse('http://h/')), isNull);
    });

    test('SSDP headers, times, DIDL escaping', () {
      expect(Dlna.headerValue('HTTP/1.1 200 OK\r\nLOCATION: http://h:1/d.xml\r\nST: x\r\n', 'location'), 'http://h:1/d.xml');
      expect(Dlna.parseTime('0:03:25.000'), const Duration(minutes: 3, seconds: 25));
      expect(Dlna.parseTime('NOT_IMPLEMENTED'), isNull);
      expect(Dlna.formatTime(const Duration(minutes: 61, seconds: 5)), '1:01:05');
      final didl = Dlna.didl(const CastMedia(url: 'http://h/a/1.mp3?x=1&y=2', mime: 'audio/mpeg', title: 'Rock & <Roll>', artist: 'A'));
      expect(didl, contains('Rock &amp; &lt;Roll&gt;'));
      expect(didl, contains('x=1&amp;y=2'));
      expect(didl, contains('http-get:*:audio/mpeg:*'));
    });
  });
}

/// A minimal DLNA renderer: records SOAP actions, fetches the media it's
/// given (like a TV would), reports PLAYING once it has it.
Future<(HttpServer, List<String>, Future<int> Function())> _fakeRenderer() async {
  final actions = <String>[];
  var fetched = 0;
  var state = 'STOPPED';
  final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
  server.listen((req) async {
    final body = await req.fold<List<int>>([], (a, b) => a..addAll(b));
    final text = String.fromCharCodes(body);
    final action = (req.headers.value('SOAPACTION') ?? '').split('#').last.replaceAll('"', '');
    actions.add(action);
    var reply = '';
    switch (action) {
      case 'SetAVTransportURI':
        final url = Dlna.unescape(RegExp(r'<CurrentURI>(.*?)</CurrentURI>').firstMatch(text)!.group(1)!);
        final client = HttpClient();
        final res = await (await client.getUrl(Uri.parse(url))).close();
        fetched = (await res.fold<List<int>>([], (a, b) => a..addAll(b))).length;
        client.close();
      case 'Play':
        state = 'PLAYING';
      case 'Pause':
        state = 'PAUSED_PLAYBACK';
      case 'GetTransportInfo':
        reply = '<CurrentTransportState>$state</CurrentTransportState>';
      case 'GetPositionInfo':
        reply = '<RelTime>0:00:07</RelTime><TrackDuration>0:03:00</TrackDuration>';
    }
    req.response
      ..headers.contentType = ContentType('text', 'xml')
      ..write('<s:Envelope><s:Body><u:${action}Response>$reply</u:${action}Response></s:Body></s:Envelope>');
    await req.response.close();
  });
  return (server, actions, () async => fetched);
}
