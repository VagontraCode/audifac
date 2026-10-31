import 'dart:math' as math;

import 'song.dart';
import 'song_features.dart';

/// The shape of an evening: party level (0 calm … 100 everybody dancing)
/// over its length (0 … 1), through a few points joined by straight lines.
class EnergyCurve {
  EnergyCurve(List<(double, double)> points)
      : points = ([...points]..sort((a, b) => a.$1.compareTo(b.$1)))
            .map((p) => (p.$1.clamp(0.0, 1.0), p.$2.clamp(0.0, 100.0)))
            .toList();

  final List<(double, double)> points;

  double at(double t) {
    if (points.isEmpty) return 50;
    if (t <= points.first.$1) return points.first.$2;
    for (var i = 1; i < points.length; i++) {
      final (t1, v1) = points[i];
      if (t <= t1) {
        final (t0, v0) = points[i - 1];
        return t1 == t0 ? v1 : v0 + (v1 - v0) * (t - t0) / (t1 - t0);
      }
    }
    return points.last.$2;
  }

  /// The curve from [from] on moved by [delta] (live "more energy" / "calm
  /// down"), or held at its level at [from] when [delta] is null ("keep it here").
  EnergyCurve reshaped(double from, double? delta) {
    final level = at(from);
    final kept = [for (final p in points) if (p.$1 < from) p];
    if (delta == null) return EnergyCurve([...kept, (from, level), (1.0, level)]);
    return EnergyCurve([
      ...kept,
      (from, level),
      for (final p in points) if (p.$1 > from) (p.$1, p.$2 + delta),
      if (!points.any((p) => p.$1 > from)) (1.0, level + delta),
    ]);
  }

  String encode() => points.map((p) => '${p.$1.toStringAsFixed(3)}:${p.$2.round()}').join(',');

  static EnergyCurve decode(String s) => EnergyCurve([
        for (final part in s.split(','))
          if (part.split(':') case [final t, final v]) (double.tryParse(t) ?? 0, double.tryParse(v) ?? 50),
      ]);
}

enum SoireeShape {
  houseParty,
  dinnerToDance,
  straightToTheFloor,
  withCoolDown,
  windDown;

  EnergyCurve get curve => switch (this) {
        houseParty => EnergyCurve([(0, 35), (0.25, 55), (0.5, 78), (0.8, 92), (1, 88)]),
        dinnerToDance => EnergyCurve([(0, 12), (0.35, 28), (0.55, 60), (0.8, 92), (1, 92)]),
        straightToTheFloor => EnergyCurve([(0, 70), (0.15, 88), (1, 92)]),
        withCoolDown => EnergyCurve([(0, 30), (0.3, 60), (0.6, 92), (0.85, 85), (1, 35)]),
        windDown => EnergyCurve([(0, 85), (0.5, 60), (1, 20)]),
      };
}

/// A song the builder may use.
class SoireeCandidate {
  const SoireeCandidate({required this.song, required this.features, this.taste = 0});

  final Song song;
  final SongFeatures features;

  /// 0 … 1: favourite, played often.
  final double taste;

  /// How much it moves a room: energy and danceability together.
  double get rawLevel => 0.5 * features.energy + 0.5 * features.danceability;
}

/// One song of the evening, with the level the curve asked for there.
class SoireeSlot {
  const SoireeSlot({required this.song, required this.target, required this.level, this.locked = false});

  final Song song;

  /// Where the curve wanted the party (0–100) and where this song sits on
  /// the library's scale (0–100).
  final double target;
  final double level;
  final bool locked;

  SoireeSlot copyWith({bool? locked}) => SoireeSlot(song: song, target: target, level: level, locked: locked ?? this.locked);
}

class SoireeSettings {
  const SoireeSettings({
    required this.length,
    required this.curve,
    this.artistGap = 4,
    this.mustPlay = const {},
    this.seed = 0,
  });

  final Duration length;
  final EnergyCurve curve;

  /// No artist twice within this many songs.
  final int artistGap;

  /// Song ids that must be in.
  final Set<int> mustPlay;

  /// Another seed, another mix ("Regenerate").
  final int seed;
}

/// Builds evenings from [pool]. Levels are ranks within the pool, so the
/// calm part uses the library's calmest songs and the peak its most
/// danceable, whatever the library.
class SoireeBuilder {
  SoireeBuilder(List<SoireeCandidate> pool) : pool = [...pool] {
    final sorted = [...this.pool]..sort((a, b) => a.rawLevel.compareTo(b.rawLevel));
    for (final (i, c) in sorted.indexed) {
      _level[c.song.id] = sorted.length == 1 ? 50 : 100.0 * i / (sorted.length - 1);
    }
    for (final c in this.pool) {
      _byId[c.song.id] = c;
    }
  }

  final List<SoireeCandidate> pool;
  final _level = <int, double>{};
  final _byId = <int, SoireeCandidate>{};

  static const _beamWidth = 6;
  static const _expand = 10;

  double levelOf(Song s) => _level[s.id] ?? 50;

  SoireeCandidate? candidate(Song s) => _byId[s.id];

  /// Tempo distance, with half / double time counting as the same pulse:
  /// |log2| of the ratio (0.1 ≈ 7 %).
  static double tempoDistance(double a, double b) {
    if (a <= 0 || b <= 0) return 0.3;
    final r = (math.log(a / b) / math.ln2).abs();
    return math.min(r, math.min((r - 1).abs(), (r - 2).abs()));
  }

  /// How badly [c] fits at a moment wanting [target], after [previous].
  double cost(SoireeCandidate c, double target, SoireeCandidate? previous, {math.Random? noise}) {
    final level = levelOf(c.song);
    var cost = (level - target).abs() / 100;
    // At the peak, the beat matters more than loudness.
    if (target >= 70) cost += 0.4 * (1 - c.features.danceability / 100);
    if (previous != null) {
      cost += 0.6 * math.min(1, tempoDistance(c.features.bpm, previous.features.bpm) / 0.12);
      cost += 0.3 * (c.features.introEnergy - previous.features.outroEnergy).abs() / 100;
    }
    cost -= 0.25 * c.taste;
    if (noise != null) cost += noise.nextDouble() * 0.06;
    return cost;
  }

  /// The evening: songs until [SoireeSettings.length] is reached. [locked]
  /// keeps songs at their positions (by index).
  List<SoireeSlot> build(SoireeSettings settings, {Map<int, Song> locked = const {}, List<SoireeSlot> keep = const []}) {
    final noise = math.Random(settings.seed);
    final lengthMs = math.max(1, settings.length.inMilliseconds);
    final lockedIds = {for (final s in locked.values) s.id};

    // Beam search over (sequence, elapsed, cost).
    var beam = [
      _Path(
        [for (final s in keep) _byId[s.song.id] ?? SoireeCandidate(song: s.song, features: _blank)],
        keep.fold(0, (sum, s) => sum + s.song.duration.inMilliseconds),
        0,
      ),
    ];
    final finished = <_Path>[];
    var guard = 0;
    while (beam.isNotEmpty && guard++ < 400) {
      final next = <_Path>[];
      for (final path in beam) {
        if (path.elapsed >= lengthMs) {
          finished.add(path);
          continue;
        }
        final index = path.songs.length;
        final previous = path.songs.isEmpty ? null : path.songs.last;
        final forced = locked[index];
        final used = {for (final c in path.songs) c.song.id};
        final recentArtists = {
          for (final c in path.songs.skip(math.max(0, path.songs.length - settings.artistGap + 1))) _artistKey(c.song),
        };
        List<SoireeCandidate> options;
        if (forced != null) {
          options = [_byId[forced.id] ?? SoireeCandidate(song: forced, features: _blank)];
        } else {
          options = [
            for (final c in pool)
              if (!used.contains(c.song.id) && !lockedIds.contains(c.song.id) && !recentArtists.contains(_artistKey(c.song))) c,
          ];
          if (options.isEmpty) {
            // Small pool: allow artists again before giving up.
            options = [for (final c in pool) if (!used.contains(c.song.id) && !lockedIds.contains(c.song.id)) c];
          }
          if (options.isEmpty) {
            finished.add(path);
            continue;
          }
        }
        final scored = [
          for (final c in options)
            () {
              final mid = (path.elapsed + c.song.duration.inMilliseconds / 2) / lengthMs;
              var k = cost(c, settings.curve.at(mid.clamp(0, 1)), previous, noise: noise);
              if (settings.mustPlay.contains(c.song.id)) k -= 0.5;
              return (c, k);
            }(),
        ]..sort((a, b) => a.$2.compareTo(b.$2));
        for (final (c, k) in scored.take(_expand)) {
          next.add(_Path([...path.songs, c], path.elapsed + math.max(1000, c.song.duration.inMilliseconds), path.cost + k));
        }
      }
      next.sort((a, b) => (a.cost / a.songs.length).compareTo(b.cost / b.songs.length));
      beam = next.take(_beamWidth).toList();
    }
    finished.addAll(beam);
    if (finished.isEmpty) return const [];
    finished.sort((a, b) => (a.cost / math.max(1, a.songs.length)).compareTo(b.cost / math.max(1, b.songs.length)));
    var songs = finished.first.songs;

    // Must-play songs still missing take the place that fits them best.
    for (final id in settings.mustPlay) {
      final c = _byId[id];
      if (c == null || songs.any((s) => s.song.id == id)) continue;
      final at = _bestPlace(songs, c, settings, lengthMs, protected: {...locked.keys, for (var i = 0; i < keep.length; i++) i});
      if (at != null) songs = [...songs]..[at] = c;
    }
    return _slots(songs, settings, lengthMs, lockedIndexes: locked.keys.toSet());
  }

  /// [count] songs not in [plan] that would fit at [index] (swap).
  List<SoireeCandidate> alternatives(List<SoireeSlot> plan, int index, SoireeSettings settings, {int count = 5}) {
    final used = {for (final s in plan) s.song.id};
    final previous = index > 0 ? _byId[plan[index - 1].song.id] : null;
    final target = plan[index].target;
    final scored = [
      for (final c in pool)
        if (!used.contains(c.song.id)) (c, cost(c, target, previous)),
    ]..sort((a, b) => a.$2.compareTo(b.$2));
    return [for (final (c, _) in scored.take(count)) c];
  }

  /// Where an added [song] fits best in [plan] (an index to insert at).
  int placeFor(List<SoireeSlot> plan, Song song) {
    final level = levelOf(song);
    var best = plan.length;
    var bestCost = double.infinity;
    for (var i = 0; i < plan.length; i++) {
      final k = (plan[i].target - level).abs();
      if (k < bestCost) {
        bestCost = k;
        best = i;
      }
    }
    return best;
  }

  /// Rebuilds the slots' targets / levels after the owner reorders or adds.
  List<SoireeSlot> retarget(List<SoireeSlot> plan, SoireeSettings settings) {
    final lengthMs = math.max(1, settings.length.inMilliseconds);
    final songs = [for (final s in plan) _byId[s.song.id] ?? SoireeCandidate(song: s.song, features: _blank)];
    final lockedIndexes = {for (final (i, s) in plan.indexed) if (s.locked) i};
    return _slots(songs, settings, lengthMs, lockedIndexes: lockedIndexes);
  }

  int? _bestPlace(List<SoireeCandidate> songs, SoireeCandidate c, SoireeSettings settings, int lengthMs, {required Set<int> protected}) {
    var elapsed = 0;
    int? best;
    var bestCost = double.infinity;
    for (var i = 0; i < songs.length; i++) {
      final mid = (elapsed + songs[i].song.duration.inMilliseconds / 2) / lengthMs;
      elapsed += songs[i].song.duration.inMilliseconds;
      if (protected.contains(i) || settings.mustPlay.contains(songs[i].song.id)) continue;
      final k = (levelOf(c.song) - settings.curve.at(mid.clamp(0, 1))).abs();
      if (k < bestCost) {
        bestCost = k;
        best = i;
      }
    }
    return best;
  }

  List<SoireeSlot> _slots(List<SoireeCandidate> songs, SoireeSettings settings, int lengthMs, {Set<int> lockedIndexes = const {}}) {
    var elapsed = 0;
    return [
      for (final (i, c) in songs.indexed)
        () {
          final mid = (elapsed + c.song.duration.inMilliseconds / 2) / lengthMs;
          elapsed += c.song.duration.inMilliseconds;
          return SoireeSlot(
            song: c.song,
            target: settings.curve.at(mid.clamp(0, 1)),
            level: levelOf(c.song),
            locked: lockedIndexes.contains(i),
          );
        }(),
    ];
  }

  static String _artistKey(Song s) => s.artist.trim().toLowerCase();

  static const _blank = SongFeatures(
    bpm: 0,
    confidence: 0,
    groove: 50,
    bassPunch: 50,
    energy: 50,
    danceability: 50,
    sizeBytes: 0,
    modifiedMs: 0,
  );
}

class _Path {
  _Path(this.songs, this.elapsed, this.cost);

  final List<SoireeCandidate> songs;
  final int elapsed;
  final double cost;
}

/// 0…1 from favourites and plays.
double tasteOf({required bool favorite, required int plays}) => math.min(1, (favorite ? 0.6 : 0) + 0.4 * math.min(1, plays / 10));
