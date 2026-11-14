import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math';

/// One file received from the computer.
class ReceivedFile {
  ReceivedFile(this.name, this.bytes, {this.error});

  final String name;
  final int bytes;

  /// Why it was refused / failed, null when saved.
  final String? error;
}

/// Saves a received temp file into the music library; returns null when
/// saved, else a reason. (Android: MediaStore, `Music/audifac`.)
typedef ImportFile = Future<String?> Function(File temp, String name);

/// Wi-Fi transfer: a page on the local network where a computer's browser
/// drops audio files onto the phone.
///
/// Runs only while the transfer screen is open. The address carries a random
/// token: other devices on the Wi-Fi can't find or use it without seeing the
/// screen. Only audio files (and .lrc / .cue sheets) are accepted.
class TransferServer {
  TransferServer({required this.import, required this.page, Directory? tempDir})
      : _tempDir = tempDir ?? Directory.systemTemp;

  final ImportFile import;

  /// The upload page (HTML) for the browser.
  final String page;
  final Directory _tempDir;

  HttpServer? _server;
  late String token;
  final _received = StreamController<ReceivedFile>.broadcast();

  static const maxBytes = 4 << 30; // 4 GB (long DSD / hi-res files)

  static const audioExtensions = {
    'mp3', 'm4a', 'm4b', 'aac', 'flac', 'wav', 'ogg', 'oga', 'opus', 'aif', 'aiff', 'aifc', //
    'wma', 'ape', 'wv', 'tta', 'mka', 'dsf', 'dff', 'alac', 'mp2', 'ac3', 'amr', 'weba',
  };
  static const sidecarExtensions = {'lrc', 'cue'};

  Stream<ReceivedFile> get received => _received.stream;
  int? get port => _server?.port;

  /// Starts on [port] (0: any free one).
  Future<void> start({int port = 0, InternetAddress? address}) async {
    if (_server != null) return;
    final random = Random.secure();
    const alphabet = 'abcdefghijkmnpqrstuvwxyz23456789'; // nothing that looks alike
    token = List.generate(6, (_) => alphabet[random.nextInt(alphabet.length)]).join();
    _server = await HttpServer.bind(address ?? InternetAddress.anyIPv4, port);
    _server!.listen(_handle, onError: (_) {});
  }

  Future<void> stop() async {
    await _server?.close(force: true);
    _server = null;
  }

  Future<void> dispose() async {
    await stop();
    await _received.close();
  }

  /// A safe file name: no folders, no control or reserved characters.
  static String? sanitizeName(String raw) {
    var name = raw.split(RegExp(r'[/\\]')).last.trim();
    name = name.replaceAll(RegExp(r'[\x00-\x1f<>:"|?*]'), '_');
    while (name.startsWith('.')) {
      name = name.substring(1);
    }
    if (name.isEmpty || name.length > 200) return null;
    return name;
  }

  static bool isAccepted(String name) {
    final dot = name.lastIndexOf('.');
    if (dot < 0) return false;
    final ext = name.substring(dot + 1).toLowerCase();
    return audioExtensions.contains(ext) || sidecarExtensions.contains(ext);
  }

  Future<void> _handle(HttpRequest request) async {
    final response = request.response;
    try {
      final segments = request.uri.pathSegments.where((s) => s.isNotEmpty).toList();
      if (segments.isEmpty || segments.first != token) {
        response.statusCode = HttpStatus.notFound;
        return await response.close();
      }
      if (request.method == 'GET' && segments.length == 1) {
        response.headers.contentType = ContentType.html;
        response.headers.set('Cache-Control', 'no-store');
        response.write(page);
        return await response.close();
      }
      if (request.method == 'PUT' && segments.length == 2 && segments[1] == 'upload') {
        return await _upload(request);
      }
      response.statusCode = HttpStatus.notFound;
      await response.close();
    } catch (_) {
      try {
        await response.close();
      } catch (_) {}
    }
  }

  Future<void> _upload(HttpRequest request) async {
    final response = request.response;
    Future<void> refuse(int status, String name, String reason) async {
      _received.add(ReceivedFile(name, 0, error: reason));
      response.statusCode = status;
      response.write(reason);
      await response.close();
      // Don't read the body: the browser stops sending.
    }

    final raw = request.uri.queryParameters['name'] ?? '';
    final name = sanitizeName(raw);
    if (name == null) return refuse(HttpStatus.badRequest, raw, 'bad name');
    if (!isAccepted(name)) return refuse(HttpStatus.unsupportedMediaType, name, 'not audio');
    if (request.contentLength > maxBytes) return refuse(HttpStatus.requestEntityTooLarge, name, 'too large');

    final temp = File('${_tempDir.path}/transfer_${DateTime.now().microsecondsSinceEpoch}_$name');
    var bytes = 0;
    try {
      final sink = temp.openWrite();
      try {
        await for (final chunk in request) {
          bytes += chunk.length;
          if (bytes > maxBytes) throw const FileSystemException('too large');
          sink.add(chunk);
        }
      } finally {
        await sink.close();
      }
      if (request.contentLength >= 0 && bytes != request.contentLength) {
        throw const FileSystemException('incomplete');
      }
      final error = await import(temp, name);
      _received.add(ReceivedFile(name, bytes, error: error));
      response.statusCode = error == null ? HttpStatus.ok : HttpStatus.internalServerError;
      response.headers.contentType = ContentType.json;
      response.write(jsonEncode({'ok': error == null, 'name': name, if (error != null) 'error': error}));
    } catch (e) {
      _received.add(ReceivedFile(name, bytes, error: '$e'));
      response.statusCode = HttpStatus.internalServerError;
    } finally {
      if (await temp.exists()) await temp.delete();
      await response.close();
    }
  }
}
