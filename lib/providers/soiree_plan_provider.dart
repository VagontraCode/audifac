import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../models/soiree.dart';
import '../models/song.dart';
import '../models/song_features.dart';
import 'library_providers.dart';
import 'soiree_providers.dart';
import 'stats_providers.dart';
import 'user_data_providers.dart';

/// The soirée being planned (and played): its settings and its songs.
class SoireeState {
  const SoireeState({
    this.length = const Duration(hours: 3),
    this.shape = SoireeShape.houseParty,
    EnergyCurve? curve,
    this.playlistId,
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

  /// Songs from this playlist only (null: the whole library).
  final int? playlistId;
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
    int? Function()? playlistId,
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
        playlistId: playlistId == null ? this.playlistId : playlistId(),
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
        'playlistId': playlistId,
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
        playlistId: (j['playlistId'] as num?)?.toInt(),
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

  /// Songs the soirée can use: analysed, in the chosen playlist, not removed.
  List<SoireeCandidate> pool([SoireeState? s]) {
    final st = s ?? stateOrNull ?? const SoireeState();
    final features = ref.read(soireeFeaturesProvider);
    final stats = ref.read(songStatsProvider);
    final favorites = ref.read(favoritesProvider).toSet();
    final playlist = st.playlistId == null
        ? null
        : ref.read(playlistsProvider).where((p) => p.id == st.playlistId).firstOrNull?.songIds.toSet();
    return [
      for (final song in ref.read(songsProvider))
        if (features[song.key] case final f? when SongFeaturesNotifier.worthIt(song) && !noBeat(f))
          if (!st.excluded.contains(song.id) && (playlist == null || playlist.contains(song.id)))
            SoireeCandidate(
              song: song,
              features: f,
              taste: tasteOf(favorite: favorites.contains(song.id), plays: stats[song.id]?.plays ?? 0),
            ),
    ];
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

  void setPlaylist(int? id) {
    state = state.copyWith(playlistId: () => id);
    rebuild();
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
