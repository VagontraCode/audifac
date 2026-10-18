import 'song.dart';

/// One listen of one song: how long it was actually heard and whether that
/// was enough to count as a play.
class PlayEvent {
  const PlayEvent({required this.songId, required this.at, required this.listenedMs, required this.counted});

  final int songId;

  /// When the listen started.
  final DateTime at;
  final int listenedMs;
  final bool counted;

  Map<String, Object?> toRow() => {
        'song_id': songId,
        'played_at': at.millisecondsSinceEpoch,
        'listened_ms': listenedMs,
        'counted': counted ? 1 : 0,
      };

  factory PlayEvent.fromRow(Map<String, Object?> r) => PlayEvent(
        songId: r['song_id'] as int,
        at: DateTime.fromMillisecondsSinceEpoch(r['played_at'] as int),
        listenedMs: r['listened_ms'] as int,
        counted: r['counted'] == 1,
      );
}

/// Turns playback ticks into [PlayEvent]s. A play counts once half the song
/// (or 4 minutes of it) has really been heard — seeking doesn't count.
class PlayTracker {
  PlayTracker({DateTime Function()? clock}) : _clock = clock ?? DateTime.now;

  static const countAfter = Duration(minutes: 4);

  /// Gaps bigger than this between ticks are seeks or stalls, not listening.
  static const maxTick = Duration(seconds: 3);

  final DateTime Function() _clock;

  int? _songId;
  Duration _songDuration = Duration.zero;
  DateTime? _startedAt;
  int _listenedMs = 0;
  bool _counted = false;
  Duration? _lastPosition;

  bool _reached() {
    final half = _songDuration.inMilliseconds ~/ 2;
    final needed = half > 0 && half < countAfter.inMilliseconds ? half : countAfter.inMilliseconds;
    return _listenedMs >= needed;
  }

  /// Reports the player's state. Returns the finished listen when the song changed.
  PlayEvent? tick({required int? songId, required Duration duration, required Duration position, required bool playing}) {
    PlayEvent? finished;
    if (songId != _songId) {
      finished = finish();
      _songId = songId;
      _songDuration = duration;
      _startedAt = songId == null ? null : _clock();
      _lastPosition = position;
      return finished;
    }
    if (duration > Duration.zero) _songDuration = duration;
    final last = _lastPosition;
    _lastPosition = position;
    if (!playing || last == null || songId == null) return null;
    final delta = position - last;
    // Back at the start of the same song (repeat one, "play again"): a new listen.
    if (delta < -maxTick && position < const Duration(seconds: 5) && _listenedMs > 0) {
      final finished = finish();
      _songId = songId;
      _startedAt = _clock();
      _lastPosition = position;
      return finished;
    }
    if (delta > Duration.zero && delta <= maxTick) {
      _listenedMs += delta.inMilliseconds;
      if (!_counted && _reached()) _counted = true;
    }
    return null;
  }

  /// The listen in progress so far (saved periodically in case the app is killed).
  PlayEvent? get current {
    final id = _songId;
    final at = _startedAt;
    if (id == null || at == null || _listenedMs < 1000) return null;
    return PlayEvent(songId: id, at: at, listenedMs: _listenedMs, counted: _counted);
  }

  /// Ends the current listen (song change, queue end, app closing).
  PlayEvent? finish() {
    final event = current;
    _songId = null;
    _startedAt = null;
    _listenedMs = 0;
    _counted = false;
    _lastPosition = null;
    return event;
  }
}

/// Per-song totals.
class SongStats {
  const SongStats({this.plays = 0, this.listened = Duration.zero, this.lastPlayed});

  final int plays;
  final Duration listened;
  final DateTime? lastPlayed;

  SongStats add(PlayEvent e) => SongStats(
        plays: plays + (e.counted ? 1 : 0),
        listened: listened + Duration(milliseconds: e.listenedMs),
        lastPlayed: e.counted && (lastPlayed == null || e.at.isAfter(lastPlayed!)) ? e.at : lastPlayed,
      );
}

Map<int, SongStats> songStats(Iterable<PlayEvent> events, {DateTime? since}) {
  final result = <int, SongStats>{};
  for (final e in events) {
    if (since != null && e.at.isBefore(since)) continue;
    result[e.songId] = (result[e.songId] ?? const SongStats()).add(e);
  }
  return result;
}

enum StatsRange {
  week('7 days', Duration(days: 7)),
  month('30 days', Duration(days: 30)),
  year('Year', Duration(days: 365)),
  all('All time', null);

  const StatsRange(this.label, this.length);
  final String label;
  final Duration? length;

  DateTime? since(DateTime now) => length == null ? null : now.subtract(length!);
}

/// A ranked row: a song, an artist or an album with its totals.
class Ranked<T> {
  const Ranked(this.item, this.plays, this.listened);

  final T item;
  final int plays;
  final Duration listened;
}

/// Everything the Stats screen shows for one range.
class StatsSummary {
  const StatsSummary({
    required this.plays,
    required this.listened,
    required this.songs,
    required this.artists,
    required this.albums,
    required this.activeDays,
  });

  final int plays;
  final Duration listened;
  final List<Ranked<Song>> songs;
  final List<Ranked<String>> artists;

  /// Album title with its cover song.
  final List<Ranked<Song>> albums;

  /// Distinct days with any listening.
  final int activeDays;

  static StatsSummary of(Iterable<PlayEvent> events, Map<int, Song> byId, {DateTime? since}) {
    final perSong = songStats(events, since: since);
    var plays = 0;
    var listened = Duration.zero;
    final artists = <String, (int, Duration)>{};
    final albums = <int, (Song, int, Duration)>{};
    final songs = <Ranked<Song>>[];
    perSong.forEach((id, s) {
      plays += s.plays;
      listened += s.listened;
      final song = byId[id];
      if (song == null) return;
      songs.add(Ranked(song, s.plays, s.listened));
      final a = artists[song.artist] ?? (0, Duration.zero);
      artists[song.artist] = (a.$1 + s.plays, a.$2 + s.listened);
      final b = albums[song.albumId] ?? (song, 0, Duration.zero);
      albums[song.albumId] = (b.$1, b.$2 + s.plays, b.$3 + s.listened);
    });
    int byPlays(Ranked<Object> a, Ranked<Object> b) {
      final c = b.plays.compareTo(a.plays);
      return c != 0 ? c : b.listened.compareTo(a.listened);
    }

    final days = <int>{};
    for (final e in events) {
      if (since != null && e.at.isBefore(since)) continue;
      days.add(DateTime(e.at.year, e.at.month, e.at.day).millisecondsSinceEpoch);
    }
    return StatsSummary(
      plays: plays,
      listened: listened,
      songs: songs.where((r) => r.plays > 0).toList()..sort(byPlays),
      artists: [
        for (final e in artists.entries)
          if (e.value.$1 > 0) Ranked(e.key, e.value.$1, e.value.$2),
      ]..sort(byPlays),
      albums: [
        for (final v in albums.values)
          if (v.$2 > 0) Ranked(v.$1, v.$2, v.$3),
      ]..sort(byPlays),
      activeDays: days.length,
    );
  }
}
