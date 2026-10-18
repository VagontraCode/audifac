import 'dart:async';
import 'dart:io';
import 'dart:math';

/// Serves the songs being cast to TVs / speakers on the local network, with
/// HTTP Range support (renderers seek by requesting byte ranges).
///
/// Each file gets an unguessable token; only shared files can be fetched.
class CastServer {
  HttpServer? _server;
  final _files = <String, ({String path, String mime})>{};
  final _random = Random.secure();

  /// The phone's address on the Wi-Fi network.
  String? host;

  bool get running => _server != null;

  Future<void> start() async {
    if (_server != null) return;
    host ??= await localAddress();
    _server = await HttpServer.bind(InternetAddress.anyIPv4, 0);
    _server!.listen(_handle, onError: (_) {});
  }

  Future<void> stop() async {
    await _server?.close(force: true);
    _server = null;
    _files.clear();
  }

  /// A URL the renderer can fetch [path] from.
  String share(String path, String mime) {
    final token = List.generate(16, (_) => _random.nextInt(256).toRadixString(16).padLeft(2, '0')).join();
    _files[token] = (path: path, mime: mime);
    final ext = path.contains('.') ? path.substring(path.lastIndexOf('.')) : '';
    return 'http://$host:${_server!.port}/a/$token$ext';
  }

  /// The first private IPv4 address (Wi-Fi), or null when offline.
  static Future<String?> localAddress() async {
    final interfaces = await NetworkInterface.list(type: InternetAddressType.IPv4);
    String? fallback;
    for (final i in interfaces) {
      for (final a in i.addresses) {
        if (a.isLoopback) continue;
        final ip = a.address;
        final private = ip.startsWith('192.168.') || ip.startsWith('10.') || RegExp(r'^172\.(1[6-9]|2\d|3[01])\.').hasMatch(ip);
        if (private && i.name.toLowerCase().contains('wlan')) return ip;
        if (private) fallback ??= ip;
      }
    }
    return fallback;
  }

  /// `bytes=500-` / `bytes=0-999` → (start, end inclusive), clamped to [length].
  static (int, int)? parseRange(String? header, int length) {
    if (header == null || !header.startsWith('bytes=')) return null;
    final spec = header.substring(6).split(',').first.trim();
    final dash = spec.indexOf('-');
    if (dash < 0) return null;
    final a = spec.substring(0, dash), b = spec.substring(dash + 1);
    int start, end;
    if (a.isEmpty) {
      // Suffix: the last N bytes.
      final n = int.tryParse(b);
      if (n == null) return null;
      start = max(0, length - n);
      end = length - 1;
    } else {
      start = int.tryParse(a) ?? -1;
      end = b.isEmpty ? length - 1 : min(length - 1, int.tryParse(b) ?? -1);
    }
    if (start < 0 || start >= length || end < start) return null;
    return (start, end);
  }

  Future<void> _handle(HttpRequest request) async {
    final response = request.response;
    try {
      final segments = request.uri.pathSegments;
      final token = segments.length == 2 && segments[0] == 'a' ? segments[1].split('.').first : null;
      final file = token == null ? null : _files[token];
      if (file == null || (request.method != 'GET' && request.method != 'HEAD')) {
        response.statusCode = HttpStatus.notFound;
        await response.close();
        return;
      }
      final f = File(file.path);
      final length = await f.length();
      response.headers
        ..set(HttpHeaders.contentTypeHeader, file.mime)
        ..set(HttpHeaders.acceptRangesHeader, 'bytes')
        // DLNA renderers like these: streaming, seekable by byte.
        ..set('transferMode.dlna.org', 'Streaming')
        ..set('contentFeatures.dlna.org', 'DLNA.ORG_OP=01;DLNA.ORG_FLAGS=01700000000000000000000000000000');
      final range = parseRange(request.headers.value(HttpHeaders.rangeHeader), length);
      if (range != null) {
        response.statusCode = HttpStatus.partialContent;
        response.headers.set(HttpHeaders.contentRangeHeader, 'bytes ${range.$1}-${range.$2}/$length');
        response.contentLength = range.$2 - range.$1 + 1;
      } else {
        response.contentLength = length;
      }
      if (request.method == 'HEAD') {
        await response.close();
        return;
      }
      await response.addStream(f.openRead(range?.$1 ?? 0, range == null ? null : range.$2 + 1));
      await response.close();
    } catch (_) {
      // Renderer hung up (seeking, stopping): nothing to do.
      try {
        await response.close();
      } catch (_) {}
    }
  }
}
