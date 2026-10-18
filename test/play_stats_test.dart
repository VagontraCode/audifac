import 'package:audifac/models/backup.dart';
import 'package:audifac/models/play_stats.dart';
import 'package:audifac/models/song.dart';
import 'package:flutter_test/flutter_test.dart';

Song _song(int id, {String artist = 'A', int albumId = 1, int minutes = 4}) => Song(
      id: id,
      uri: 'content://media/external/audio/media/$id',
      path: '/storage/emulated/0/Music/$id.mp3',
      title: 'Song $id',
      artist: artist,
      artistId: artist.hashCode,
      album: 'Album $albumId',
      albumId: albumId,
      duration: Duration(minutes: minutes),
      dateAdded: DateTime(2024),
    );

/// Plays [songId] for [seconds] of real listening, one tick per second.
PlayEvent? listen(PlayTracker t, int songId, int seconds, {Duration duration = const Duration(minutes: 4), int from = 0}) {
  var finished = t.tick(songId: songId, duration: duration, position: Duration(seconds: from), playing: true);
  for (var s = 1; s <= seconds; s++) {
    // (Not `??=`: that would skip the tick once a listen has finished.)
    final e = t.tick(songId: songId, duration: duration, position: Duration(seconds: from + s), playing: true);
    finished = finished ?? e;
  }
  return finished;
}

void main() {
  group('PlayTracker', () {
    test('counts at half the song', () {
      final t = PlayTracker();
      listen(t, 1, 119);
      expect(t.finish()!.counted, isFalse);
      listen(t, 1, 121);
      final e = t.finish()!;
      expect(e.counted, isTrue);
      expect(e.listenedMs, 121000);
    });

    test('long songs count after 4 minutes', () {
      final t = PlayTracker();
      listen(t, 1, 241, duration: const Duration(minutes: 20));
      expect(t.finish()!.counted, isTrue);
    });

    test('seeking ahead is not listening', () {
      final t = PlayTracker();
      listen(t, 1, 10);
      // Jump to 3:00 and listen 10 s more.
      listen(t, 1, 10, from: 180);
      final e = t.finish()!;
      expect(e.listenedMs, 20000);
      expect(e.counted, isFalse);
    });

    test('paused time does not count', () {
      final t = PlayTracker();
      listen(t, 1, 5);
      t.tick(songId: 1, duration: const Duration(minutes: 4), position: const Duration(seconds: 6), playing: false);
      expect(t.finish()!.listenedMs, 5000);
    });

    test('changing song emits the finished listen', () {
      final t = PlayTracker();
      listen(t, 1, 150);
      final e = listen(t, 2, 3);
      expect(e!.songId, 1);
      expect(e.counted, isTrue);
      expect(t.current!.songId, 2);
    });

    test('repeat-one: back at the start is a new listen', () {
      final t = PlayTracker();
      listen(t, 1, 200);
      final e = listen(t, 1, 3, from: 0);
      expect(e, isNotNull);
      expect(e!.counted, isTrue);
      expect(t.current!.listenedMs, 3000);
    });

    test('blips under a second are not logged', () {
      final t = PlayTracker();
      t.tick(songId: 1, duration: const Duration(minutes: 4), position: Duration.zero, playing: true);
      expect(t.finish(), isNull);
    });
  });

  group('stats', () {
    final now = DateTime(2026, 10, 18, 12);
    final songs = {for (final s in [_song(1), _song(2, artist: 'B', albumId: 2), _song(3)]) s.id: s};
    PlayEvent play(int id, int daysAgo, {bool counted = true, int minutes = 3}) => PlayEvent(
          songId: id,
          at: now.subtract(Duration(days: daysAgo)),
          listenedMs: minutes * 60000,
          counted: counted,
        );
    final log = [
      play(1, 1),
      play(1, 2),
      play(1, 40),
      play(2, 3),
      play(2, 3, counted: false, minutes: 1),
      play(3, 100),
    ];

    test('per-song totals', () {
      final s = songStats(log);
      expect(s[1]!.plays, 3);
      expect(s[1]!.lastPlayed, now.subtract(const Duration(days: 1)));
      expect(s[2]!.plays, 1);
      expect(s[2]!.listened, const Duration(minutes: 4));
    });

    test('summary for the last 30 days', () {
      final sum = StatsSummary.of(log, songs, since: StatsRange.month.since(now));
      expect(sum.plays, 3);
      expect(sum.listened, const Duration(minutes: 10));
      expect(sum.songs.map((r) => r.item.id), [1, 2]);
      expect(sum.artists.first.item, 'A');
      expect(sum.albums.first.item.albumId, 1);
      expect(sum.activeDays, 3);
    });

    test('all time ranks by plays', () {
      final sum = StatsSummary.of(log, songs);
      expect(sum.plays, 5);
      expect(sum.songs.first.plays, 3);
      expect(sum.artists.map((r) => (r.item, r.plays)), [('A', 4), ('B', 1)]);
    });
  });

  test('plays survive a backup round-trip', () {
    final data = BackupData(
      exportedAt: DateTime(2026),
      appVersion: '0.2.0',
      plays: [
        PlaysBackup(song: SongRef.of(_song(1)), events: const [(1000, 120000, true), (5000, 2000, false)]),
      ],
    );
    final back = BackupData.decode(data.encode());
    expect(back.plays.single.song.title, 'Song 1');
    expect(back.plays.single.events, const [(1000, 120000, true), (5000, 2000, false)]);
  });
}
