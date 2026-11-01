import 'dart:convert';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../models/religious.dart';
import '../models/song.dart';
import 'audio_info_providers.dart';
import 'library_providers.dart';
import 'user_data_providers.dart';

/// Soirée → "Leave out religious music": the switch and the owner's
/// corrections, kept across soirées.
final religiousFilterProvider = NotifierProvider<ReligiousFilterNotifier, ReligiousFilter>(ReligiousFilterNotifier.new);

class ReligiousFilterNotifier extends Notifier<ReligiousFilter> {
  static const key = 'soiree_religious';

  @override
  ReligiousFilter build() {
    final text = ref.read(bootstrapProvider).values[key];
    if (text == null) return const ReligiousFilter();
    try {
      return ReligiousFilter.fromJson(jsonDecode(text) as Map<String, dynamic>);
    } catch (_) {
      return const ReligiousFilter();
    }
  }

  void _set(ReligiousFilter f) {
    state = f;
    ref.read(databaseProvider).setValue(key, jsonEncode(f.toJson()));
  }

  void setOn(bool on) => _set(state.copyWith(on: on));

  /// [song] stays out of soirées ([out]) or is kept in: a match is kept, a
  /// song marked by the owner is unmarked, any other song is marked.
  void setLeftOut(Song song, bool out) {
    final matched = ref.read(religiousSongsProvider)[song.key];
    final keep = {...state.keep}..remove(song.key);
    final marked = {...state.marked};
    if (out) {
      if (matched == null) marked.add(song.key);
    } else {
      marked.remove(song.key);
      if (matched != null && matched.reason != ReligiousReason.marked) keep.add(song.key);
    }
    _set(state.copyWith(keep: keep, marked: marked));
  }
}

/// Songs that look religious, by [Song.key] (kept ones included: the check
/// list shows them).
final religiousSongsProvider = Provider<Map<String, ReligiousMatch>>((ref) {
  final songs = ref.watch(songsProvider);
  final infos = ref.watch(audioInfoProvider);
  final edits = ref.watch(tagEditsProvider);
  final marked = ref.watch(religiousFilterProvider.select((f) => f.marked));
  return religiousSongs(songs, genreOf: (s) => edits[s.key]?.genre ?? infos[s.location]?.genre, marked: marked);
});

/// Song keys a soirée leaves out (empty when the switch is off).
final religiousLeftOutProvider = Provider<Set<String>>((ref) {
  final filter = ref.watch(religiousFilterProvider);
  if (!filter.on) return const {};
  return {for (final k in ref.watch(religiousSongsProvider).keys) if (!filter.keep.contains(k)) k};
});
