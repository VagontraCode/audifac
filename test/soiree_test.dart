import 'dart:math' as math;

import 'package:audifac/models/soiree.dart';
import 'package:audifac/models/song.dart';
import 'package:audifac/models/song_features.dart';
import 'package:audifac/providers/soiree_plan_provider.dart';
import 'package:flutter_test/flutter_test.dart';

Song _song(int id, String artist) => Song(
      id: id,
      uri: 'content://media/external/audio/media/$id',
      path: '/storage/emulated/0/Music/$id.mp3',
      title: 'Song $id',
      artist: artist,
      artistId: artist.hashCode,
      album: 'A',
      albumId: id,
      duration: const Duration(minutes: 4),
      dateAdded: DateTime(2024),
    );

/// 80 songs: levels from calm to wild, tempos around afro / coupé-décalé, 20 artists.
List<SoireeCandidate> _pool() {
  final r = math.Random(3);
  return [
    for (var i = 0; i < 80; i++)
      SoireeCandidate(
        song: _song(i, 'Artist ${i % 20}'),
        features: SongFeatures(
          bpm: const [95.0, 104.0, 110.0, 116.0, 124.0, 132.0, 138.0][r.nextInt(7)],
          confidence: 0.5,
          groove: 30 + r.nextInt(70),
          bassPunch: 30 + r.nextInt(70),
          energy: (i * 100 / 80).round(),
          danceability: (10 + i * 85 / 80 + r.nextInt(10)).round().clamp(0, 100),
          excerptEnergy: [(i * 100 / 80).round(), (i * 100 / 80).round(), (i * 100 / 80).round()],
          sizeBytes: 0,
          modifiedMs: 0,
        ),
        taste: i % 9 == 0 ? 1 : 0,
      ),
  ];
}

void main() {
  final pool = _pool();
  final builder = SoireeBuilder(pool);
  final twoHours = SoireeSettings(length: const Duration(hours: 2), curve: SoireeShape.dinnerToDance.curve);

  test('fills the evening once, following the curve from calm to the floor', () {
    final plan = builder.build(twoHours);
    final total = plan.fold(Duration.zero, (sum, s) => sum + s.song.duration);
    expect(total >= const Duration(hours: 2) && total < const Duration(hours: 2, minutes: 4), isTrue, reason: '$total');
    expect(plan.map((s) => s.song.id).toSet().length, plan.length);
    double mean(Iterable<SoireeSlot> s) => s.map((x) => x.level).reduce((a, b) => a + b) / s.length;
    final third = plan.length ~/ 3;
    expect(mean(plan.take(third)), lessThan(40));
    expect(mean(plan.skip(2 * third)), greaterThan(70));
    // Each song close to what the curve wanted.
    final err = plan.map((s) => (s.level - s.target).abs()).reduce((a, b) => a + b) / plan.length;
    expect(err, lessThan(15));
  });

  test('no artist twice within the gap; smoother tempos than chance', () {
    final plan = builder.build(twoHours);
    for (var i = 0; i < plan.length; i++) {
      for (var j = i + 1; j < math.min(plan.length, i + twoHours.artistGap); j++) {
        expect(plan[i].song.artist == plan[j].song.artist, isFalse, reason: 'slots $i and $j');
      }
    }
    double jumps(List<Song> songs) {
      var sum = 0.0;
      for (var i = 1; i < songs.length; i++) {
        sum += SoireeBuilder.tempoDistance(builder.candidate(songs[i])!.features.bpm, builder.candidate(songs[i - 1])!.features.bpm);
      }
      return sum / (songs.length - 1);
    }

    final shuffled = [for (final s in plan) s.song]..shuffle(math.Random(1));
    expect(jumps([for (final s in plan) s.song]), lessThan(jumps(shuffled)));
  });

  test('locked songs stay where they are; must-play songs get in', () {
    final first = builder.build(twoHours);
    final lockedSong = first[5].song;
    final quiet = pool.first.song; // the calmest: not chosen for a dance floor
    final again = builder.build(
      SoireeSettings(length: twoHours.length, curve: twoHours.curve, seed: 7, mustPlay: {pool.last.song.id}),
      locked: {5: lockedSong},
    );
    expect(again[5].song, lockedSong);
    expect(again[5].locked, isTrue);
    expect(again.where((s) => s.song.id == pool.last.song.id), hasLength(1));
    expect(again.where((s) => s.song == lockedSong), hasLength(1));
    expect(quiet.id, isNot(lockedSong.id));
  });

  test('another seed gives another mix', () {
    final a = builder.build(twoHours).map((s) => s.song.id).toList();
    final b = builder.build(SoireeSettings(length: twoHours.length, curve: twoHours.curve, seed: 42)).map((s) => s.song.id).toList();
    expect(a, isNot(b));
  });

  test('swap alternatives fit the moment and are not already in', () {
    final plan = builder.build(twoHours);
    final peak = plan.length - 2;
    final alts = builder.alternatives(plan, peak, twoHours);
    expect(alts, hasLength(5));
    expect(alts.any((c) => plan.any((s) => s.song.id == c.song.id)), isFalse);
    for (final c in alts) {
      expect((builder.levelOf(c.song) - plan[peak].target).abs(), lessThan(35));
    }
    expect(builder.placeFor(plan, pool.last.song), greaterThan(plan.length ~/ 2));
    expect(builder.placeFor(plan, pool.first.song), lessThan(plan.length ~/ 3));
  });

  test('half / double tempo is the same pulse', () {
    expect(SoireeBuilder.tempoDistance(120, 60), closeTo(0, 1e-9));
    expect(SoireeBuilder.tempoDistance(110, 110), 0);
    expect(SoireeBuilder.tempoDistance(132, 110), greaterThan(0.2));
  });

  test('curves: interpolation, live reshaping, encode', () {
    final c = EnergyCurve([(0, 20), (0.5, 60), (1, 100)]);
    expect(c.at(0.25), 40);
    expect(c.at(2), 100);
    final more = c.reshaped(0.5, 15);
    expect(more.at(0.25), 40); // the past is unchanged
    expect(more.at(1), 100); // clamped at 100
    expect(c.reshaped(0.5, -20).at(1), 80);
    final hold = c.reshaped(0.5, null);
    expect(hold.at(0.9), 60);
    expect(EnergyCurve.decode(c.encode()).at(0.75), 80);
  });

  test('a small pool still makes a list (artists may repeat)', () {
    final small = SoireeBuilder(pool.take(6).toList());
    final plan = small.build(SoireeSettings(length: const Duration(hours: 1), curve: SoireeShape.houseParty.curve));
    expect(plan, hasLength(6)); // ran out of songs: no repeats
  });

  test('live: rebuilding from the middle keeps what played and never repeats it', () {
    final plan = builder.build(twoHours);
    final played = plan.take(10).toList();
    final hotter = twoHours.curve.reshaped(0.33, 15);
    final again = builder.build(SoireeSettings(length: twoHours.length, curve: hotter), keep: played);
    expect(again.take(10).map((s) => s.song.id), played.map((s) => s.song.id));
    expect(again.map((s) => s.song.id).toSet().length, again.length);
    double mean(Iterable<SoireeSlot> s) => s.map((x) => x.level).reduce((a, b) => a + b) / s.length;
    final calmer = builder.build(SoireeSettings(length: twoHours.length, curve: twoHours.curve.reshaped(0.33, -25)), keep: played);
    expect(mean(again.skip(10)), greaterThan(mean(calmer.skip(10))));
  });

  test('lessons: skipped early is less danceable, played through at the peak more', () {
    const four = Duration(minutes: 4);
    expect(soireeLesson(listenedMs: 20000, duration: four, target: 80), -8);
    expect(soireeLesson(listenedMs: 230000, duration: four, target: 80), 4);
    expect(soireeLesson(listenedMs: 230000, duration: four, target: 40), 0); // calm part: no lesson
    expect(soireeLesson(listenedMs: 150000, duration: four, target: 80), 0); // most of it: neutral
    expect(soireeLesson(listenedMs: 20000, duration: const Duration(seconds: 45), target: 80), 0); // short song, last 30 s
  });

  test('live: an added song takes the upcoming slot whose moment fits it, never a kept one', () {
    final plan = builder.build(twoHours);
    final wild = pool.last.song; // the most danceable
    final at = builder.replaceFor(plan, wild, from: 5)!;
    expect(at, greaterThanOrEqualTo(5));
    final best = [for (var i = 5; i < plan.length; i++) (plan[i].target - builder.levelOf(wild)).abs()].reduce(math.min);
    expect((plan[at].target - builder.levelOf(wild)).abs(), best);
    // Locked and must-play slots are kept.
    final locked = [for (final (i, s) in plan.indexed) i == at ? s.copyWith(locked: true) : s];
    expect(builder.replaceFor(locked, wild, from: 5), isNot(at));
    expect(builder.replaceFor(plan, wild, from: 5, keep: {plan[at].song.id}), isNot(at));
    // Nothing left to replace.
    expect(builder.replaceFor(plan, wild, from: plan.length), isNull);
  });

  test("live: an album's songs are spread, not side by side", () {
    final plan = builder.build(twoHours);
    final song = pool.last.song;
    final first = builder.replaceFor(plan, song, from: 0)!;
    final placed = [...plan]..[first] = SoireeSlot(song: song, target: plan[first].target, level: builder.levelOf(song));
    final next = builder.replaceFor(placed, pool[pool.length - 2].song, from: 0, keep: {song.id}, avoid: {song.id});
    expect((next! - first).abs(), greaterThan(1));
  });

  test('sources: favourites, playlists and folders with their subfolders', () {
    Song at(int id, String folder) => Song(
          id: id,
          uri: 'content://x/$id',
          path: '$folder/$id.mp3',
          title: 'S$id',
          artist: 'A',
          artistId: 0,
          album: 'B',
          albumId: 0,
          duration: const Duration(minutes: 3),
          dateAdded: DateTime(2024),
        );
    final party = at(1, '/storage/emulated/0/Music/Party');
    final deeper = at(2, '/storage/emulated/0/Music/Party/2024');
    final lookalike = at(3, '/storage/emulated/0/Music/Party Old');
    final other = at(4, '/storage/emulated/0/Download');
    final folder = {SoireeSources.folder('/storage/emulated/0/Music/Party')};
    expect([party, deeper, lookalike, other].where((s) => SoireeSources.contains(folder, s)), [party, deeper]);
    expect(SoireeSources.contains(const {}, other), isTrue); // whole library
    final mixed = {...folder, SoireeSources.favorites, SoireeSources.playlist(7)};
    expect(SoireeSources.contains(mixed, other, favorites: {4}), isTrue);
    expect(SoireeSources.contains(mixed, lookalike, playlistSongs: {3}), isTrue);
    expect(SoireeSources.contains(mixed, other), isFalse);
    expect(SoireeSources.playlistIdOf(SoireeSources.playlist(7)), 7);
    expect(SoireeSources.folderOf(SoireeSources.folder('/a/b')), '/a/b');
  });

  test('a soirée saved by 0.5.0 keeps its playlist as its source', () {
    final s = SoireeState.decode('{"lengthMin":120,"playlistId":7,"plan":[]}', const {});
    expect(s.sources, {SoireeSources.playlist(7)});
    final again = SoireeState.decode(s.copyWith(sources: {SoireeSources.favorites, SoireeSources.folder('/x')}).encode(), const {});
    expect(again.sources, {SoireeSources.favorites, SoireeSources.folder('/x')});
  });
}
