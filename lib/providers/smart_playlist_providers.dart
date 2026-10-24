import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../models/audio_info.dart';
import '../models/smart_playlist.dart';
import '../models/song.dart';
import 'audio_info_providers.dart';
import 'library_providers.dart';
import 'stats_providers.dart';
import 'user_data_providers.dart';

/// Built-in smart playlists, then the user's.
final smartPlaylistsProvider = NotifierProvider<SmartPlaylistsNotifier, List<SmartPlaylist>>(SmartPlaylistsNotifier.new);

class SmartPlaylistsNotifier extends Notifier<List<SmartPlaylist>> {
  static const key = 'smart_playlists';

  @override
  List<SmartPlaylist> build() =>
      [...SmartPlaylist.builtIns, ...SmartPlaylist.decodeAll(ref.read(bootstrapProvider).values[key])];

  static String newId() => 's_${DateTime.now().microsecondsSinceEpoch}';

  List<SmartPlaylist> get _own => state.where((l) => !l.builtIn).toList();

  void _persist() => ref.read(databaseProvider).setValue(key, SmartPlaylist.encodeAll(_own));

  void save(SmartPlaylist list) {
    if (list.builtIn) return;
    final exists = state.any((l) => l.id == list.id);
    state = exists ? [for (final l in state) l.id == list.id ? list : l] : [...state, list];
    _persist();
  }

  void delete(String id) {
    state = state.where((l) => l.builtIn || l.id != id).toList();
    _persist();
  }

  /// From a backup: lists with a new id are added, known ones replaced.
  int restore(List<SmartPlaylist> lists) {
    for (final l in lists) {
      save(l.copyWith(builtIn: false));
    }
    return lists.length;
  }
}

final smartContextProvider = Provider<SmartContext>((ref) {
  final infos = ref.watch(audioInfoProvider);
  final edits = ref.watch(tagEditsProvider);
  return SmartContext(
    info: (s) {
      final info = infos[s.location] ?? AudioInfo.guess(s);
      return edits[s.key]?.applyInfo(info) ?? info;
    },
    stats: ref.watch(songStatsProvider),
    favorites: ref.watch(favoritesProvider).toSet(),
    now: DateTime.now(),
  );
});

final smartPlaylistProvider = Provider.family<SmartPlaylist?, String>(
  (ref, id) => ref.watch(smartPlaylistsProvider).where((l) => l.id == id).firstOrNull,
);

final smartSongsProvider = Provider.family<List<Song>, String>((ref, id) {
  final list = ref.watch(smartPlaylistProvider(id));
  if (list == null) return const [];
  return list.songsFrom(ref.watch(songsProvider), ref.watch(smartContextProvider));
});
