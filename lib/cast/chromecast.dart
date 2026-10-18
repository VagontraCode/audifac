import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:multicast_dns/multicast_dns.dart';

import 'cast_target.dart';

/// Google Cast devices (Chromecast, Nest / Google speakers, Cast-enabled TVs):
/// mDNS discovery, then the Cast V2 protocol (TLS, protobuf frames, JSON
/// payloads) talking to the Default Media Receiver.
class Chromecast {
  static const service = '_googlecast._tcp.local';

  static Future<List<ChromecastTarget>> discover({Duration timeout = const Duration(seconds: 4)}) async {
    // Android can't bind with reusePort; reuseAddress is enough there.
    final client = MDnsClient(
      rawDatagramSocketFactory: (dynamic host, int port, {bool reuseAddress = true, bool reusePort = true, int ttl = 1}) =>
          RawDatagramSocket.bind(host, port, reuseAddress: true, reusePort: false, ttl: ttl),
    );
    final found = <String, ChromecastTarget>{};
    try {
      await client.start();
      await for (final ptr in client.lookup<PtrResourceRecord>(ResourceRecordQuery.serverPointer(service), timeout: timeout)) {
        String? friendly;
        await for (final txt in client.lookup<TxtResourceRecord>(ResourceRecordQuery.text(ptr.domainName), timeout: const Duration(seconds: 2))) {
          for (final entry in txt.text.split('\n')) {
            if (entry.startsWith('fn=')) friendly = entry.substring(3);
          }
        }
        await for (final srv in client.lookup<SrvResourceRecord>(ResourceRecordQuery.service(ptr.domainName), timeout: const Duration(seconds: 2))) {
          await for (final ip in client.lookup<IPAddressResourceRecord>(ResourceRecordQuery.addressIPv4(srv.target), timeout: const Duration(seconds: 2))) {
            final name = friendly ?? ptr.domainName.split('.').first;
            found[ptr.domainName] = ChromecastTarget(id: ptr.domainName, name: name, host: ip.address.address, port: srv.port);
            break;
          }
        }
      }
    } catch (_) {
      // No network / multicast blocked: nothing found.
    } finally {
      client.stop();
    }
    return found.values.toList();
  }
}

/// Encodes / decodes the Cast `CastMessage` protobuf (6 fields, so by hand).
class CastFrame {
  const CastFrame({required this.source, required this.destination, required this.namespace, required this.payload});

  final String source;
  final String destination;
  final String namespace;
  final String payload;

  static void _varint(BytesBuilder b, int v) {
    while (v >= 0x80) {
      b.addByte((v & 0x7F) | 0x80);
      v >>= 7;
    }
    b.addByte(v);
  }

  static void _string(BytesBuilder b, int field, String s) {
    final bytes = utf8.encode(s);
    b.addByte(field << 3 | 2);
    _varint(b, bytes.length);
    b.add(bytes);
  }

  /// Length-prefixed message, ready for the socket.
  Uint8List encode() {
    final m = BytesBuilder();
    m.addByte(1 << 3 | 0); // protocol_version = CASTV2_1_0
    _varint(m, 0);
    _string(m, 2, source);
    _string(m, 3, destination);
    _string(m, 4, namespace);
    m.addByte(5 << 3 | 0); // payload_type = STRING
    _varint(m, 0);
    _string(m, 6, payload);
    final body = m.takeBytes();
    final out = Uint8List(4 + body.length);
    ByteData.view(out.buffer).setUint32(0, body.length);
    out.setRange(4, out.length, body);
    return out;
  }

  /// One message body (without the length prefix); null if malformed.
  static CastFrame? decode(Uint8List body) {
    var i = 0;
    int varint() {
      var shift = 0, v = 0;
      while (true) {
        final byte = body[i++];
        v |= (byte & 0x7F) << shift;
        if (byte < 0x80) return v;
        shift += 7;
      }
    }

    final strings = <int, String>{};
    try {
      while (i < body.length) {
        final key = varint();
        final field = key >> 3, wire = key & 7;
        if (wire == 0) {
          varint();
        } else if (wire == 2) {
          final len = varint();
          strings[field] = utf8.decode(body.sublist(i, i + len), allowMalformed: true);
          i += len;
        } else {
          return null; // Binary payloads etc. aren't used here.
        }
      }
    } catch (_) {
      return null;
    }
    return CastFrame(source: strings[2] ?? '', destination: strings[3] ?? '', namespace: strings[4] ?? '', payload: strings[6] ?? '');
  }
}

class ChromecastTarget implements CastTarget {
  ChromecastTarget({required this.id, required this.name, required this.host, this.port = 8009});

  @override
  final String id;
  @override
  final String name;
  final String host;
  final int port;

  @override
  CastKind get kind => CastKind.chromecast;

  @override
  Future<CastSession> connect() async {
    final socket = await SecureSocket.connect(host, port, onBadCertificate: (_) => true, timeout: const Duration(seconds: 6));
    final session = ChromecastSession._(socket);
    await session._start();
    return session;
  }
}

class ChromecastSession implements CastSession {
  ChromecastSession._(this._socket);

  static const _connection = 'urn:x-cast:com.google.cast.tp.connection';
  static const _heartbeat = 'urn:x-cast:com.google.cast.tp.heartbeat';
  static const _receiver = 'urn:x-cast:com.google.cast.receiver';
  static const _media = 'urn:x-cast:com.google.cast.media';
  static const _defaultReceiver = 'CC1AD845';

  final SecureSocket _socket;
  final _buffer = BytesBuilder();
  final _waiting = <int, Completer<Map<String, dynamic>>>{};
  Timer? _ping;
  var _requestId = 1;
  String? _transportId;
  String? _appSessionId;
  int? _mediaSessionId;
  Map<String, dynamic>? _lastMedia;
  double? _volume;

  Future<void> _start() async {
    _socket.listen(_onData, onError: (_) => _fail(), onDone: _fail);
    _send('receiver-0', _connection, {'type': 'CONNECT'});
    _ping = Timer.periodic(const Duration(seconds: 5), (_) => _send('receiver-0', _heartbeat, {'type': 'PING'}));
    final status = await _request('receiver-0', _receiver, {'type': 'LAUNCH', 'appId': _defaultReceiver});
    final apps = ((status['status'] as Map?)?['applications'] as List?)?.cast<Map>() ?? const [];
    final app = apps.where((a) => a['appId'] == _defaultReceiver).firstOrNull;
    if (app == null) throw const SocketException('The device did not start the media receiver');
    _transportId = app['transportId'] as String;
    _appSessionId = app['sessionId'] as String?;
    _send(_transportId!, _connection, {'type': 'CONNECT'});
  }

  void _fail() {
    for (final c in _waiting.values) {
      if (!c.isCompleted) c.completeError(const SocketException('Cast connection closed'));
    }
    _waiting.clear();
    _ping?.cancel();
  }

  void _send(String destination, String namespace, Map<String, Object?> payload) {
    final frame = CastFrame(source: 'sender-0', destination: destination, namespace: namespace, payload: jsonEncode(payload));
    _socket.add(frame.encode());
  }

  Future<Map<String, dynamic>> _request(String destination, String namespace, Map<String, Object?> payload) {
    final id = _requestId++;
    final completer = Completer<Map<String, dynamic>>();
    _waiting[id] = completer;
    _send(destination, namespace, {...payload, 'requestId': id});
    return completer.future.timeout(const Duration(seconds: 10), onTimeout: () {
      _waiting.remove(id);
      throw TimeoutException('No answer from the Cast device');
    });
  }

  void _onData(Uint8List data) {
    _buffer.add(data);
    var bytes = _buffer.takeBytes();
    while (bytes.length >= 4) {
      final len = ByteData.view(bytes.buffer, bytes.offsetInBytes).getUint32(0);
      if (bytes.length < 4 + len) break;
      final frame = CastFrame.decode(Uint8List.sublistView(bytes, 4, 4 + len));
      bytes = Uint8List.sublistView(bytes, 4 + len);
      if (frame != null) _onFrame(frame);
    }
    _buffer.add(bytes);
  }

  void _onFrame(CastFrame f) {
    Map<String, dynamic> json;
    try {
      json = jsonDecode(f.payload) as Map<String, dynamic>;
    } catch (_) {
      return;
    }
    if (f.namespace == _heartbeat && json['type'] == 'PING') {
      _send(f.source, _heartbeat, {'type': 'PONG'});
      return;
    }
    if (json['type'] == 'MEDIA_STATUS') {
      final list = (json['status'] as List?)?.cast<Map<String, dynamic>>() ?? const [];
      if (list.isNotEmpty) {
        _lastMedia = list.first;
        _mediaSessionId = (list.first['mediaSessionId'] as num?)?.toInt() ?? _mediaSessionId;
      }
    }
    if (json['type'] == 'RECEIVER_STATUS') {
      _volume = (((json['status'] as Map?)?['volume'] as Map?)?['level'] as num?)?.toDouble() ?? _volume;
    }
    final id = (json['requestId'] as num?)?.toInt();
    if (id != null) _waiting.remove(id)?.complete(json);
  }

  Future<void> _mediaCommand(String type, [Map<String, Object?> extra = const {}]) async {
    final session = _mediaSessionId;
    if (session == null || _transportId == null) return;
    await _request(_transportId!, _media, {'type': type, 'mediaSessionId': session, ...extra});
  }

  @override
  Future<void> load(CastMedia m) async {
    final answer = await _request(_transportId!, _media, {
      'type': 'LOAD',
      'autoplay': true,
      'currentTime': 0,
      'media': {
        'contentId': m.url,
        'contentType': m.mime,
        'streamType': 'BUFFERED',
        'metadata': {
          'metadataType': 3, // MusicTrackMediaMetadata
          'title': m.title,
          'artist': ?m.artist,
          'albumName': ?m.album,
        },
        if (m.duration != null) 'duration': m.duration!.inMilliseconds / 1000,
      },
    });
    if (answer['type'] == 'LOAD_FAILED' || answer['type'] == 'INVALID_REQUEST') {
      throw SocketException('The Cast device could not play this file (${answer['type']})');
    }
  }

  @override
  Future<void> play() => _mediaCommand('PLAY');

  @override
  Future<void> pause() => _mediaCommand('PAUSE');

  @override
  Future<void> seek(Duration position) => _mediaCommand('SEEK', {'currentTime': position.inMilliseconds / 1000});

  @override
  Future<void> setVolume(double volume) async {
    _volume = volume;
    await _request('receiver-0', _receiver, {
      'type': 'SET_VOLUME',
      'volume': {'level': volume.clamp(0, 1)},
    });
  }

  @override
  Future<CastStatus> status() async {
    if (_transportId == null) return const CastStatus();
    final answer = await _request(_transportId!, _media, {'type': 'GET_STATUS'});
    final list = (answer['status'] as List?)?.cast<Map<String, dynamic>>() ?? const [];
    final s = list.isEmpty ? _lastMedia : list.first;
    if (s == null) return CastStatus(playback: CastPlayback.idle, volume: _volume);
    final state = s['playerState'] as String?;
    final duration = ((s['media'] as Map?)?['duration'] as num?)?.toDouble();
    return CastStatus(
      playback: switch (state) {
        'PLAYING' => CastPlayback.playing,
        'PAUSED' => CastPlayback.paused,
        'BUFFERING' => CastPlayback.loading,
        'IDLE' when s['idleReason'] == 'FINISHED' => CastPlayback.finished,
        _ => CastPlayback.idle,
      },
      position: Duration(milliseconds: (((s['currentTime'] as num?) ?? 0) * 1000).round()),
      duration: duration == null ? null : Duration(milliseconds: (duration * 1000).round()),
      volume: _volume,
    );
  }

  @override
  Future<void> close() async {
    try {
      if (_appSessionId != null) _send('receiver-0', _receiver, {'type': 'STOP', 'sessionId': _appSessionId, 'requestId': _requestId++});
      if (_transportId != null) _send(_transportId!, _connection, {'type': 'CLOSE'});
      await _socket.flush();
    } catch (_) {}
    _ping?.cancel();
    await _socket.close();
  }
}
