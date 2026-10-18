import 'dart:convert';

/// The playback queue as it was when the app last ran, so it can be restored.
class SavedSession {
  final List<int> songIds;
  final int index;
  final Duration position;
  final bool shuffle;

  /// One of `none`, `all`, `one`.
  final String repeat;

  const SavedSession({
    required this.songIds,
    required this.index,
    required this.position,
    this.shuffle = false,
    this.repeat = 'none',
  });

  String encode() => jsonEncode({
        'songIds': songIds,
        'index': index,
        'positionMs': position.inMilliseconds,
        'shuffle': shuffle,
        'repeat': repeat,
      });

  /// Returns null for missing or corrupt data.
  static SavedSession? decode(String? raw) {
    if (raw == null || raw.isEmpty) return null;
    try {
      final map = jsonDecode(raw) as Map<String, dynamic>;
      final ids = (map['songIds'] as List).map((e) => (e as num).toInt()).toList();
      if (ids.isEmpty) return null;
      return SavedSession(
        songIds: ids,
        index: ((map['index'] as num?)?.toInt() ?? 0).clamp(0, ids.length - 1),
        position: Duration(milliseconds: (map['positionMs'] as num?)?.toInt() ?? 0),
        shuffle: map['shuffle'] as bool? ?? false,
        repeat: map['repeat'] as String? ?? 'none',
      );
    } catch (_) {
      return null;
    }
  }

  /// Keeps only songs that still exist in the library, and moves [index] so it
  /// still points at the same song (or the closest following one).
  SavedSession? retainWhere(bool Function(int id) exists) {
    final kept = <int>[];
    var newIndex = 0;
    for (var i = 0; i < songIds.length; i++) {
      if (i == index) newIndex = kept.length;
      if (exists(songIds[i])) kept.add(songIds[i]);
    }
    if (kept.isEmpty) return null;
    final currentSurvived = exists(songIds[index]);
    return SavedSession(
      songIds: kept,
      index: newIndex.clamp(0, kept.length - 1),
      position: currentSurvived ? position : Duration.zero,
      shuffle: shuffle,
      repeat: repeat,
    );
  }
}
