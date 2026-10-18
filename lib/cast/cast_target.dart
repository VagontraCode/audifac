import 'dart:async';

enum CastKind { chromecast, dlna }

/// What a renderer is doing.
enum CastPlayback { idle, loading, playing, paused, finished }

class CastStatus {
  const CastStatus({this.playback = CastPlayback.idle, this.position = Duration.zero, this.duration, this.volume});

  final CastPlayback playback;
  final Duration position;
  final Duration? duration;

  /// 0–1, when the device reports it.
  final double? volume;
}

/// A song as sent to a renderer.
class CastMedia {
  const CastMedia({required this.url, required this.mime, required this.title, this.artist, this.album, this.duration});

  final String url;
  final String mime;
  final String title;
  final String? artist;
  final String? album;
  final Duration? duration;
}

/// A connection to one TV / speaker.
abstract class CastSession {
  Future<void> load(CastMedia media);
  Future<void> play();
  Future<void> pause();
  Future<void> seek(Duration position);
  Future<void> setVolume(double volume);

  /// Current state (polled by the controller about once a second).
  Future<CastStatus> status();
  Future<void> close();
}

/// A TV / speaker found on the network.
abstract class CastTarget {
  String get id;
  String get name;
  CastKind get kind;

  Future<CastSession> connect();
}
