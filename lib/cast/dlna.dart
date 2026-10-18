import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'cast_target.dart';

/// UPnP / DLNA media renderers (smart TVs, AV receivers, network speakers):
/// SSDP discovery, then AVTransport + RenderingControl over SOAP.
class Dlna {
  static const _ssdpAddress = '239.255.255.250';
  static const _ssdpPort = 1900;
  static const _renderer = 'urn:schemas-upnp-org:device:MediaRenderer:1';

  /// Renderers that answer within [timeout].
  static Future<List<DlnaTarget>> discover({Duration timeout = const Duration(seconds: 4)}) async {
    final socket = await RawDatagramSocket.bind(InternetAddress.anyIPv4, 0);
    final locations = <String>{};
    final sub = socket.listen((event) {
      if (event != RawSocketEvent.read) return;
      final d = socket.receive();
      if (d == null) return;
      final location = headerValue(utf8.decode(d.data, allowMalformed: true), 'location');
      if (location != null) locations.add(location);
    });
    final search = 'M-SEARCH * HTTP/1.1\r\n'
        'HOST: $_ssdpAddress:$_ssdpPort\r\n'
        'MAN: "ssdp:discover"\r\n'
        'MX: 2\r\n'
        'ST: $_renderer\r\n\r\n';
    for (var i = 0; i < 3; i++) {
      socket.send(utf8.encode(search), InternetAddress(_ssdpAddress), _ssdpPort);
      await Future<void>.delayed(timeout ~/ 3);
    }
    await sub.cancel();
    socket.close();

    final targets = <DlnaTarget>[];
    for (final location in locations) {
      try {
        final t = await DlnaTarget.fromDescription(Uri.parse(location));
        if (t != null && !targets.any((x) => x.id == t.id)) targets.add(t);
      } catch (_) {
        // Unreachable or not a renderer we can drive.
      }
    }
    return targets;
  }

  /// A header from an SSDP / HTTP response (case-insensitive).
  static String? headerValue(String response, String name) {
    for (final line in const LineSplitter().convert(response)) {
      final colon = line.indexOf(':');
      if (colon > 0 && line.substring(0, colon).trim().toLowerCase() == name) return line.substring(colon + 1).trim();
    }
    return null;
  }

  /// Text of the first `<tag>…</tag>` (namespace prefixes ignored).
  static String? tag(String xml, String name, {int from = 0}) {
    final m = RegExp('<(?:\\w+:)?$name(?:\\s[^>]*)?>([\\s\\S]*?)</(?:\\w+:)?$name>').firstMatch(xml.substring(from));
    return m?.group(1)?.trim();
  }

  static String escape(String s) =>
      s.replaceAll('&', '&amp;').replaceAll('<', '&lt;').replaceAll('>', '&gt;').replaceAll('"', '&quot;');

  static String unescape(String s) =>
      s.replaceAll('&lt;', '<').replaceAll('&gt;', '>').replaceAll('&quot;', '"').replaceAll('&apos;', "'").replaceAll('&amp;', '&');

  /// `01:02:03` / `0:04:05.000` → Duration.
  static Duration? parseTime(String? s) {
    if (s == null || s.isEmpty || s == 'NOT_IMPLEMENTED') return null;
    final parts = s.split('.').first.split(':').map(int.tryParse).toList();
    if (parts.length != 3 || parts.contains(null)) return null;
    return Duration(hours: parts[0]!, minutes: parts[1]!, seconds: parts[2]!);
  }

  static String formatTime(Duration d) {
    String two(int n) => n.toString().padLeft(2, '0');
    return '${d.inHours}:${two(d.inMinutes.remainder(60))}:${two(d.inSeconds.remainder(60))}';
  }

  /// DIDL-Lite item describing a track (most TVs want it to show title / art).
  static String didl(CastMedia m) {
    final duration = m.duration == null ? '' : ' duration="${formatTime(m.duration!)}.000"';
    return '<DIDL-Lite xmlns="urn:schemas-upnp-org:metadata-1-0/DIDL-Lite/" '
        'xmlns:dc="http://purl.org/dc/elements/1.1/" xmlns:upnp="urn:schemas-upnp-org:metadata-1-0/upnp/">'
        '<item id="1" parentID="0" restricted="1">'
        '<dc:title>${escape(m.title)}</dc:title>'
        '${m.artist == null ? '' : '<upnp:artist>${escape(m.artist!)}</upnp:artist><dc:creator>${escape(m.artist!)}</dc:creator>'}'
        '${m.album == null ? '' : '<upnp:album>${escape(m.album!)}</upnp:album>'}'
        '<upnp:class>object.item.audioItem.musicTrack</upnp:class>'
        '<res protocolInfo="http-get:*:${m.mime}:*"$duration>${escape(m.url)}</res>'
        '</item></DIDL-Lite>';
  }
}

class DlnaTarget implements CastTarget {
  DlnaTarget({required this.id, required this.name, required this.avTransport, this.renderingControl});

  @override
  final String id;
  @override
  final String name;
  final Uri avTransport;
  final Uri? renderingControl;

  @override
  CastKind get kind => CastKind.dlna;

  static Future<DlnaTarget?> fromDescription(Uri location) async {
    final client = HttpClient()..connectionTimeout = const Duration(seconds: 4);
    try {
      final res = await (await client.getUrl(location)).close().timeout(const Duration(seconds: 5));
      final xml = await res.transform(utf8.decoder).join();
      return parseDescription(xml, location);
    } finally {
      client.close();
    }
  }

  /// From a device description document.
  static DlnaTarget? parseDescription(String xml, Uri location) {
    final name = Dlna.tag(xml, 'friendlyName') ?? location.host;
    final udn = Dlna.tag(xml, 'UDN') ?? location.toString();
    final urlBase = Dlna.tag(xml, 'URLBase');
    final base = urlBase == null || urlBase.isEmpty ? location : Uri.tryParse(urlBase) ?? location;
    Uri? control(String service) {
      for (final m in RegExp(r'<(?:\w+:)?service>([\s\S]*?)</(?:\w+:)?service>').allMatches(xml)) {
        final block = m.group(1)!;
        if ((Dlna.tag(block, 'serviceType') ?? '').contains(service)) {
          final url = Dlna.tag(block, 'controlURL');
          if (url != null) return base.resolve(url);
        }
      }
      return null;
    }

    final av = control('AVTransport');
    if (av == null) return null;
    return DlnaTarget(id: udn, name: Dlna.unescape(name), avTransport: av, renderingControl: control('RenderingControl'));
  }

  @override
  Future<CastSession> connect() async => DlnaSession(this);
}

class DlnaSession implements CastSession {
  DlnaSession(this.target);

  final DlnaTarget target;
  final _client = HttpClient()..connectionTimeout = const Duration(seconds: 4);

  Future<String> _soap(Uri url, String service, String action, Map<String, String> args) async {
    final body = '<?xml version="1.0" encoding="utf-8"?>'
        '<s:Envelope xmlns:s="http://schemas.xmlsoap.org/soap/envelope/" s:encodingStyle="http://schemas.xmlsoap.org/soap/encoding/">'
        '<s:Body><u:$action xmlns:u="urn:schemas-upnp-org:service:$service:1">'
        '${args.entries.map((e) => '<${e.key}>${Dlna.escape(e.value)}</${e.key}>').join()}'
        '</u:$action></s:Body></s:Envelope>';
    final req = await _client.postUrl(url);
    req.headers
      ..set(HttpHeaders.contentTypeHeader, 'text/xml; charset="utf-8"')
      ..set('SOAPACTION', '"urn:schemas-upnp-org:service:$service:1#$action"');
    req.add(utf8.encode(body));
    final res = await req.close().timeout(const Duration(seconds: 6));
    final text = await res.transform(utf8.decoder).join();
    if (res.statusCode >= 400) throw HttpException('$action failed (${res.statusCode})');
    return text;
  }

  Future<String> _av(String action, [Map<String, String> args = const {}]) =>
      _soap(target.avTransport, 'AVTransport', action, {'InstanceID': '0', ...args});

  @override
  Future<void> load(CastMedia media) async {
    try {
      await _av('Stop');
    } catch (_) {}
    await _av('SetAVTransportURI', {'CurrentURI': media.url, 'CurrentURIMetaData': Dlna.didl(media)});
    await play();
  }

  @override
  Future<void> play() => _av('Play', {'Speed': '1'});

  @override
  Future<void> pause() => _av('Pause');

  @override
  Future<void> seek(Duration position) => _av('Seek', {'Unit': 'REL_TIME', 'Target': Dlna.formatTime(position)});

  @override
  Future<void> setVolume(double volume) async {
    final rc = target.renderingControl;
    if (rc == null) return;
    await _soap(rc, 'RenderingControl', 'SetVolume',
        {'InstanceID': '0', 'Channel': 'Master', 'DesiredVolume': '${(volume.clamp(0, 1) * 100).round()}'});
  }

  @override
  Future<CastStatus> status() async {
    final info = await _av('GetTransportInfo');
    final state = Dlna.tag(info, 'CurrentTransportState') ?? '';
    final pos = await _av('GetPositionInfo');
    return CastStatus(
      playback: switch (state) {
        'PLAYING' => CastPlayback.playing,
        'PAUSED_PLAYBACK' => CastPlayback.paused,
        'TRANSITIONING' => CastPlayback.loading,
        'STOPPED' => CastPlayback.finished,
        _ => CastPlayback.idle,
      },
      position: Dlna.parseTime(Dlna.tag(pos, 'RelTime')) ?? Duration.zero,
      duration: Dlna.parseTime(Dlna.tag(pos, 'TrackDuration')),
    );
  }

  @override
  Future<void> close() async {
    try {
      await _av('Stop');
    } catch (_) {}
    _client.close(force: true);
  }
}
