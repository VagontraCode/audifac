import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../models/soiree.dart';
import '../models/song.dart';
import '../models/song_features.dart';
import 'library_providers.dart';
import 'player_providers.dart';
import 'religious_provider.dart';
import 'soiree_providers.dart';
import 'stats_providers.dart';
import 'user_data_providers.dart';

/// The soirée being planned (and played): its settings and its songs.
class SoireeState {
  const SoireeState({
    this.length = const Duration(hours: 3),
    this.shape = SoireeShape.houseParty,
    EnergyCurve? curve,
    this.sources = const {},
    this.seed = 0,
    this.mustPlay = const {},
    this.excluded = const {},
    this.plan = const [],
    this.building = false,
    this.live = false,
  }) : _curve = curve;

  final Duration length;

  /// The preset the curve came from (null once the owner drags a point).
  final SoireeShape? shape;
  final EnergyCurve? _curve;
  EnergyCurve get curve => _curve ?? (shape ?? SoireeShape.houseParty).curve;

  /// Where the songs come from ([SoireeSources]; none: the whole library).
  final Set<String> sources;
  final int seed;
  final Set<int> mustPlay;

  /// Removed by the owner: not proposed again in this soirée.
  final Set<int> excluded;
  final List<SoireeSlot> plan;
  final bool building;

  /// Playing as a soirée (live controls on).
  final bool live;

  Duration get total => plan.fold(Duration.zero, (sum, s) => sum + s.song.duration);

  SoireeSettings get settings => SoireeSettings(length: length, curve: curve, mustPlay: mustPlay, seed: seed);

  SoireeState copyWith({
    Duration? length,
    SoireeShape? Function()? shape,
    EnergyCurve? curve,
    Set<String>? sources,
    int? seed,
    Set<int>? mustPlay,
    Set<int>? excluded,
    List<SoireeSlot>? plan,
    bool? building,
    bool? live,
  }) =>
      SoireeState(
        length: length ?? this.length,
        shape: shape == null ? this.shape : shape(),
        curve: curve ?? (shape != null ? null : _curve),
        sources: sources ?? this.sources,
        seed: seed ?? this.seed,
        mustPlay: mustPlay ?? this.mustPlay,
        excluded: excluded ?? this.excluded,
        plan: plan ?? this.plan,
        building: building ?? this.building,
        live: live ?? this.live,
      );

  String encode() => jsonEncode({
        'lengthMin': length.inMinutes,
        'shape': shape?.name,
        if (_curve != null) 'curve': _curve.encode(),
        'sources': sources.toList(),
        'seed': seed,
        'mustPlay': mustPlay.toList(),
        'excluded': excluded.toList(),
        'plan': [for (final s in plan) [s.song.id, if (s.locked) 1]],
        'live': live,
      });

  /// [songs] resolves saved song ids (missing songs are dropped).
  static SoireeState decode(String? text, Map<int, Song> songs) {
    if (text == null) return const SoireeState();
    try {
      final j = jsonDecode(text) as Map<String, dynamic>;
      List<int> ints(String k) => [for (final x in (j[k] as List? ?? const [])) (x as num).toInt()];
      return SoireeState(
        length: Duration(minutes: (j['lengthMin'] as num?)?.toInt() ?? 180),
        shape: SoireeShape.values.asNameMap()[j['shape']],
        curve: j['curve'] is String ? EnergyCurve.decode(j['curve'] as String) : null,
        sources: {
          for (final x in (j['sources'] as List? ?? const [])) x as String,
          // Saved by 0.5.0: one playlist at most.
          if ((j['playlistId'] as num?)?.toInt() case final id?) SoireeSources.playlist(id),
        },
        seed: (j['seed'] as num?)?.toInt() ?? 0,
        mustPlay: ints('mustPlay').toSet(),
        excluded: ints('excluded').toSet(),
        plan: [
          for (final e in (j['plan'] as List? ?? const []).cast<List<dynamic>>())
            if (songs[(e.first as num).toInt()] case final song?)
              SoireeSlot(song: song, target: 0, level: 0, locked: e.length > 1),
        ],
        live: j['live'] == true,
      );
    } catch (_) {
      return const SoireeState();
    }
  }
}

final soireeProvider = NotifierProvider<SoireeNotifier, SoireeState>(SoireeNotifier.new);

class SoireeNotifier extends Notifier<SoireeState> {
  static const key = 'soiree';
  int _generation = 0;

  @override
  SoireeState build() {
    final saved = SoireeState.decode(ref.read(bootstrapProvider).values[key], ref.read(songsByIdProvider));
    // Targets / levels aren't saved: recompute them.
    if (saved.plan.isEmpty) return saved;
    return saved.copyWith(plan: builder().retarget(saved.plan, saved.settings));
  }

  /// Songs in the soirée's sources (all of them for the whole library).
  List<Song> sourceSongs(Set<String> sources) {
    final songs = ref.read(songsProvider);
    if (sources.isEmpty) return songs;
    final favorites = ref.read(favoritesProvider).toSet();
    final playlistSongs = {
      for (final p in ref.read(playlistsProvider))
        if (sources.contains(SoireeSources.playlist(p.id))) ...p.songIds,
    };
    return [
      for (final s in songs)
        if (SoireeSources.contains(sources, s, favorites: favorites, playlistSongs: playlistSongs)) s,
    ];
  }

  /// Songs the soirée can use: analysed, from its sources, not removed, not
  /// religious when that's left out — and the must-plays whatever they are
  /// (added by the owner).
  List<SoireeCandidate> pool([SoireeState? s]) {
    final st = s ?? stateOrNull ?? const SoireeState();
    final features = ref.read(soireeFeaturesProvider);
    final stats = ref.read(songStatsProvider);
    final favorites = ref.read(favoritesProvider).toSet();
    final religious = ref.read(religiousLeftOutProvider);
    SoireeCandidate candidate(Song song, SongFeatures f) => SoireeCandidate(
          song: song,
          features: f,
          taste: tasteOf(favorite: favorites.contains(song.id), plays: stats[song.id]?.plays ?? 0),
        );
    final out = [
      for (final song in sourceSongs(st.sources))
        if (features[song.key] case final f? when SongFeaturesNotifier.worthIt(song) && !noBeat(f))
          if (!st.mustPlay.contains(song.id) && !st.excluded.contains(song.id) && !religious.contains(song.key))
            candidate(song, f),
    ];
    final songs = ref.read(songsByIdProvider);
    for (final id in st.mustPlay) {
      if (songs[id] case final song?) out.add(candidate(song, features[song.key] ?? SoireeBuilder.unknown));
    }
    return out;
  }

  SoireeBuilder builder([SoireeState? s]) => SoireeBuilder(pool(s));

  void _save() => ref.read(databaseProvider).setValue(key, state.encode());

  /// (Re)builds the plan, keeping locked songs where they are. Runs off the
  /// UI thread: a big library takes a moment on a slow phone.
  Future<void> rebuild({bool newSeed = false}) async {
    final generation = ++_generation;
    final next = state.copyWith(seed: newSeed ? state.seed + 1 : null, building: true);
    state = next;
    final locked = {for (final (i, s) in next.plan.indexed) if (s.locked) i: s.song};
    final plan = await compute(_build, (pool(next), next.settings, locked));
    if (generation != _generation) return; // A newer change won.
    state = state.copyWith(plan: plan, building: false);
    _save();
  }

  void setLength(Duration length) {
    state = state.copyWith(length: length);
    rebuild();
  }

  void setShape(SoireeShape shape) {
    state = state.copyWith(shape: () => shape);
    rebuild();
  }

  /// The owner dragged point [index] of the curve to [level].
  void setPoint(int index, double level, {bool done = false}) {
    final points = [...state.curve.points];
    points[index] = (points[index].$1, level.clamp(0, 100));
    state = state.copyWith(shape: () => null, curve: EnergyCurve(points)).copyWith(curve: EnergyCurve(points));
    if (done) rebuild();
  }

  /// Songs from [sources] only (none: the whole library). Their songs are
  /// analysed first.
  void setSources(Set<String> sources) {
    state = state.copyWith(sources: sources);
    ref.read(songFeaturesProvider.notifier).prioritise({for (final s in sourceSongs(sources)) s.key});
    rebuild();
  }

  /// A new soirée from [sources] (a folder's or a playlist's menu): the
  /// owner's locks, additions and removals start over; one playing stops
  /// being live (its music plays on).
  void startFrom(Set<String> sources) {
    state = state.copyWith(plan: const [], mustPlay: const {}, excluded: const {}, live: false);
    setSources(sources);
  }

  /// "Leave out religious music" switched.
  void setReligious(bool on) {
    ref.read(religiousFilterProvider.notifier).setOn(on);
    rebuild();
  }

  /// [index] is religious: out of soirées from now on, the best fit takes
  /// its place.
  void markReligious(int index) {
    ref.read(religiousFilterProvider.notifier).setLeftOut(state.plan[index].song, true);
    remove(index);
  }

  void toggleLock(int index) {
    final plan = [...state.plan];
    plan[index] = plan[index].copyWith(locked: !plan[index].locked);
    state = state.copyWith(plan: plan);
    _save();
  }

  /// Removed: never proposed again in this soirée; the best fit takes its place.
  void remove(int index) {
    final song = state.plan[index].song;
    final next = state.copyWith(excluded: {...state.excluded, song.id}, mustPlay: {...state.mustPlay}..remove(song.id));
    final b = builder(next);
    final alts = b.alternatives(next.plan, index, next.settings, count: 1);
    final plan = [...next.plan];
    if (alts.isEmpty) {
      plan.removeAt(index);
    } else {
      plan[index] = SoireeSlot(song: alts.first.song, target: plan[index].target, level: b.levelOf(alts.first.song));
    }
    state = next.copyWith(plan: b.retarget(plan, next.settings));
    _save();
  }

  void swap(int index, Song song) {
    final plan = [...state.plan];
    plan[index] = SoireeSlot(song: song, target: plan[index].target, level: 0, locked: plan[index].locked);
    state = state.copyWith(plan: builder().retarget(plan, state.settings));
    _save();
  }

  /// [to] counts after removing [from] (onReorderItem).
  void move(int from, int to) {
    final plan = [...state.plan];
    final slot = plan.removeAt(from);
    plan.insert(to, slot);
    state = state.copyWith(plan: builder().retarget(plan, state.settings));
    _save();
  }

  /// Added by the owner: a must-play, slotted where it fits.
  void add(Song song) {
    if (state.plan.any((s) => s.song.id == song.id)) return;
    final b = builder();
    final plan = [...state.plan]..insert(b.placeFor(state.plan, song), SoireeSlot(song: song, target: 0, level: 0));
    state = state.copyWith(
      plan: b.retarget(plan, state.settings),
      mustPlay: {...state.mustPlay, song.id},
      excluded: {...state.excluded}..remove(song.id),
    );
    _save();
  }

  List<SoireeCandidate> alternatives(int index) => builder().alternatives(state.plan, index, state.settings);

  /// Live: [songs] join the soirée from slot [from] on — right there in
  /// their order ([next]), or spread: each takes the upcoming slot whose
  /// moment fits it best (that auto-picked song drops out), or is slotted in
  /// where it fits once none is left. They become must-plays, so reading the
  /// room keeps them. Songs already played stay out; already planned ones
  /// stay where they are (or move up for [next]). Returns the plan from
  /// [from] on.
  List<SoireeSlot> addLive(int from, List<Song> songs, {required bool next}) {
    final st = state;
    final played = {for (final s in st.plan.take(from)) s.song.id};
    final adding = [
      for (final s in {for (final s in songs) s.id: s}.values)
        if (!played.contains(s.id)) s,
    ];
    final ids = {for (final s in adding) s.id};
    final upd = st.copyWith(mustPlay: {...st.mustPlay, ...ids}, excluded: {...st.excluded}..removeAll(ids));
    final b = builder(upd);
    var plan = [...st.plan];
    if (next) {
      plan = [
        ...plan.take(from),
        for (final s in adding) SoireeSlot(song: s, target: 0, level: 0),
        ...plan.skip(from).where((s) => !ids.contains(s.song.id)),
      ];
    } else {
      final planned = {for (final s in plan) s.song.id};
      final added = <int>{};
      for (final song in adding) {
        if (planned.contains(song.id)) continue;
        final at = b.replaceFor(plan, song, from: from, keep: upd.mustPlay, avoid: added);
        final slot = SoireeSlot(song: song, target: 0, level: 0);
        if (at == null) {
          plan.insert(b.placeFor(plan, song, from: from), slot);
        } else {
          plan[at] = slot;
        }
        added.add(song.id);
        // The next song's choice needs this one's moment.
        plan = b.retarget(plan, upd.settings);
      }
    }
    state = upd.copyWith(plan: b.retarget(plan, upd.settings));
    _save();
    return state.plan.skip(from).toList();
  }

  void setLive(bool live) {
    state = state.copyWith(live: live);
    _save();
  }

  /// Live: from slot [from] on, the evening follows the reshaped curve
  /// ([delta] up / down, null = hold the current level). Songs before stay.
  Future<List<SoireeSlot>> reshape(int from, double? delta) async {
    final st = state;
    if (from >= st.plan.length) return const [];
    final elapsed = st.plan.take(from).fold(Duration.zero, (sum, s) => sum + s.song.duration);
    final at = elapsed.inMilliseconds / st.length.inMilliseconds;
    final curve = st.curve.reshaped(at.clamp(0, 1), delta);
    final next = st.copyWith(shape: () => null, curve: curve).copyWith(curve: curve);
    final kept = st.plan.take(from).toList();
    final plan = await compute(_buildFrom, (pool(next), next.settings, kept));
    state = next.copyWith(plan: plan);
    _save();
    return plan.skip(from).toList();
  }
}

List<SoireeSlot> _build((List<SoireeCandidate>, SoireeSettings, Map<int, Song>) a) =>
    SoireeBuilder(a.$1).build(a.$2, locked: a.$3);

List<SoireeSlot> _buildFrom((List<SoireeCandidate>, SoireeSettings, List<SoireeSlot>) a) =>
    SoireeBuilder(a.$1).build(a.$2, keep: a.$3);

/// Where the soirée is: the index of the song playing in the plan, or null
/// when what plays isn't the soirée.
final soireeNowProvider = Provider<int?>((ref) {
  final s = ref.watch(soireeProvider);
  if (!s.live) return null;
  final id = ref.watch(currentSongIdProvider);
  if (id == null) return null;
  final i = s.plan.indexWhere((slot) => slot.song.id == id);
  return i < 0 ? null : i;
});

/// Learn from soirées (Settings switch, on by default).
final soireeLearnProvider = NotifierProvider<SoireeLearnNotifier, bool>(SoireeLearnNotifier.new);

class SoireeLearnNotifier extends Notifier<bool> {
  static const key = 'soiree_learn';

  @override
  bool build() => ref.read(bootstrapProvider).values[key] != '0';

  void set(bool on) {
    state = on;
    ref.read(databaseProvider).setValue(key, on ? '1' : '0');
  }
}

/// While a soirée plays, each finished listen nudges what the song is worth
/// on a dance floor (see [soireeLesson]). Watched by the app shell.
final soireeLearningProvider = Provider<void>((ref) {
  ref.listen(playLogProvider, (previous, next) {
    if (previous == null || next.length <= previous.length || next.length - previous.length > 3) return;
    if (!ref.read(soireeLearnProvider)) return;
    final s = ref.read(soireeProvider);
    if (!s.live) return;
    for (final e in next.sublist(previous.length)) {
      final slot = s.plan.where((x) => x.song.id == e.songId).firstOrNull;
      if (slot == null) continue;
      final delta = soireeLesson(listenedMs: e.listenedMs, duration: slot.song.duration, target: slot.target);
      if (delta != 0) ref.read(featureOverridesProvider.notifier).update(slot.song, (o) => o.copyWith(learned: o.learned + delta));
    }
  });
});
