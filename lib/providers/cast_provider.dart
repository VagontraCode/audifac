import 'dart:async';

import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../cast/cast_server.dart';
import '../cast/cast_target.dart';
import '../cast/chromecast.dart';
import '../cast/dlna.dart';
import '../models/song.dart';
import 'player_providers.dart';

class CastState {
  const CastState({
    this.discovering = false,
    this.devices = const [],
    this.target,
    this.connecting = false,
    this.status = const CastStatus(),
    this.song,
    this.error,
  });

  final bool discovering;
  final List<CastTarget> devices;

  /// Where audio is going (null: this phone).
  final CastTarget? target;
  final bool connecting;
  final CastStatus status;
  final Song? song;
  final String? error;

  bool get active => target != null;

  CastState copyWith({
    bool? discovering,
    List<CastTarget>? devices,
    CastTarget? Function()? target,
    bool? connecting,
    CastStatus? status,
    Song? Function()? song,
    String? Function()? error,
  }) =>
      CastState(
        discovering: discovering ?? this.discovering,
        devices: devices ?? this.devices,
        target: target == null ? this.target : target(),
        connecting: connecting ?? this.connecting,
        status: status ?? this.status,
        song: song == null ? this.song : song(),
        error: error == null ? this.error : error(),
      );
}

/// MIME type a renderer understands for [song].
String castMime(Song song) {
  final ext = (song.path ?? song.uri).split('.').last.toLowerCase();
  return switch (ext) {
    'mp3' => 'audio/mpeg',
    'flac' => 'audio/flac',
    'm4a' || 'm4b' || 'mp4' || 'aac' => 'audio/mp4',
    'ogg' || 'oga' => 'audio/ogg',
    'opus' => 'audio/ogg',
    'wav' => 'audio/wav',
    'aif' || 'aiff' => 'audio/aiff',
    'wma' => 'audio/x-ms-wma',
    _ => song.mimeType ?? 'audio/mpeg',
  };
}

final castProvider = NotifierProvider<CastNotifier, CastState>(CastNotifier.new);

/// Plays the queue on a TV / speaker instead of the phone: local playback
/// pauses, the renderer fetches each file from the phone, and the queue
/// advances when a song ends there.
class CastNotifier extends Notifier<CastState> {
  static const _net = MethodChannel('audifac/net');

  final _server = CastServer();
  CastSession? _session;
  Timer? _poll;
  bool _sawPlaying = false;
  bool _advancing = false;

  @override
  CastState build() {
    ref.onDispose(() {
      _poll?.cancel();
      _session?.close();
      _server.stop();
    });
    return const CastState();
  }

  Future<void> _multicast(bool on) async {
    try {
      await _net.invokeMethod('multicastLock', on);
    } catch (_) {}
  }

  Future<void> discover() async {
    if (state.discovering) return;
    state = state.copyWith(discovering: true, error: () => null);
    await _multicast(true);
    try {
      final results = await Future.wait([Chromecast.discover(), Dlna.discover()]);
      state = state.copyWith(devices: [...results[0], ...results[1]]);
    } catch (e) {
      state = state.copyWith(error: () => '$e');
    } finally {
      await _multicast(false);
      state = state.copyWith(discovering: false);
    }
  }

  Future<void> connect(CastTarget target) async {
    state = state.copyWith(connecting: true, error: () => null);
    try {
      await _server.start();
      if (_server.host == null) throw const FormatException('Not on Wi-Fi');
      _session = await target.connect();
      state = state.copyWith(target: () => target, connecting: false);
      final handler = ref.read(audioHandlerProvider);
      final position = handler.position;
      await handler.pause();
      await _castCurrent(position);
      _poll = Timer.periodic(const Duration(seconds: 1), (_) => _refresh());
    } catch (e) {
      await _session?.close();
      _session = null;
      state = state.copyWith(connecting: false, target: () => null, error: () => '$e');
    }
  }

  /// Back to the phone, at the position the TV was at (paused).
  Future<void> disconnect() async {
    _poll?.cancel();
    final position = state.status.position;
    await _session?.close();
    _session = null;
    await _server.stop();
    state = state.copyWith(target: () => null, song: () => null, status: const CastStatus());
    final handler = ref.read(audioHandlerProvider);
    final index = handler.currentIndex;
    if (index != null) await handler.moveTo(index, position);
  }

  Future<void> _castCurrent([Duration position = Duration.zero]) async {
    final song = ref.read(currentSongProvider);
    final session = _session;
    if (song == null || session == null) return;
    final path = song.path;
    if (path == null) {
      state = state.copyWith(error: () => 'This file can\'t be shared with the TV');
      return;
    }
    _sawPlaying = false;
    state = state.copyWith(song: () => song, status: const CastStatus(playback: CastPlayback.loading), error: () => null);
    final mime = castMime(song);
    await session.load(CastMedia(
      url: _server.share(path, mime),
      mime: mime,
      title: song.title,
      artist: song.artist,
      album: song.album,
      duration: song.duration,
    ));
    if (position > const Duration(seconds: 2)) await session.seek(position);
  }

  Future<void> _refresh() async {
    final session = _session;
    if (session == null) return;
    try {
      final s = await session.status();
      state = state.copyWith(status: s);
      if (s.playback == CastPlayback.playing) _sawPlaying = true;
      // Ended on the TV (and it had really started): next song.
      if (_sawPlaying && (s.playback == CastPlayback.finished || s.playback == CastPlayback.idle)) {
        await next();
      }
    } catch (_) {
      // A missed poll is fine; the next one will tell.
    }
  }

  Future<void> togglePlay() async {
    if (state.status.playback == CastPlayback.playing) {
      await _session?.pause();
    } else {
      await _session?.play();
    }
    await _refresh();
  }

  Future<void> seek(Duration position) async {
    await _session?.seek(position);
    await _refresh();
  }

  Future<void> setVolume(double v) async => _session?.setVolume(v);

  Future<void> _go(int step) async {
    if (_advancing) return;
    _advancing = true;
    try {
      final handler = ref.read(audioHandlerProvider);
      final order = handler.playOrder;
      final at = order.indexOf(handler.currentIndex ?? -1);
      final target = at + step;
      if (at < 0 || target < 0 || target >= order.length) {
        // End of the queue.
        if (step > 0) state = state.copyWith(status: const CastStatus(playback: CastPlayback.idle));
        _sawPlaying = false;
        return;
      }
      await handler.moveTo(order[target]);
      // Let the current-song provider catch up with the handler.
      await Future<void>.delayed(const Duration(milliseconds: 150));
      await _castCurrent();
    } finally {
      _advancing = false;
    }
  }

  Future<void> next() => _go(1);

  /// Restarts the song if more than 3 s in, like the phone does.
  Future<void> previous() async {
    if (state.status.position > const Duration(seconds: 3)) return seek(Duration.zero);
    return _go(-1);
  }
}
