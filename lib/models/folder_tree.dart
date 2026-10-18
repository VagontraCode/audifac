import 'song.dart';

/// A folder that holds audio somewhere below it.
class FolderEntry {
  const FolderEntry({required this.path, required this.name, required this.songCount, required this.folderCount});

  final String path;
  final String name;

  /// Songs in this folder and all below it.
  final int songCount;

  /// Direct subfolders with audio.
  final int folderCount;
}

/// The library as a folder tree, from each storage volume down. Only folders
/// on the way to audio files appear.
class FolderTree {
  FolderTree._(this._direct, this._children, this._counts, this.roots);

  /// `/storage/emulated/0`, `/storage/1A2B-3C4D`, or `/` for anything else.
  static String volumeOf(String path) {
    final m = RegExp(r'^/storage/(emulated/\d+|[0-9A-Fa-f]{4}-[0-9A-Fa-f]{4})').firstMatch(path);
    return m?.group(0) ?? '/';
  }

  static String volumeName(String root) => switch (root) {
        '/' => 'Device',
        _ when root.startsWith('/storage/emulated/') => 'Internal storage',
        _ => 'SD card',
      };

  factory FolderTree.of(Iterable<Song> songs) {
    final direct = <String, List<Song>>{};
    for (final s in songs) {
      final folder = s.folder;
      if (folder == null || folder.isEmpty) continue;
      direct.putIfAbsent(folder, () => []).add(s);
    }
    final children = <String, Set<String>>{};
    final counts = <String, int>{};
    final roots = <String>{};
    direct.forEach((folder, list) {
      final root = volumeOf(folder);
      roots.add(root);
      var path = folder;
      counts[path] = (counts[path] ?? 0) + list.length;
      // Walk up to the volume root, linking each folder to its parent.
      while (path != root && path.length > root.length) {
        final cut = path.lastIndexOf('/');
        final parent = cut <= 0 ? '/' : path.substring(0, cut);
        final top = parent.length < root.length ? root : parent;
        children.putIfAbsent(top, () => {}).add(path);
        counts[top] = (counts[top] ?? 0) + list.length;
        path = top;
      }
    });
    for (final list in direct.values) {
      list.sort((a, b) => a.title.toLowerCase().compareTo(b.title.toLowerCase()));
    }
    return FolderTree._(direct, children, counts, roots.toList()..sort());
  }

  final Map<String, List<Song>> _direct;
  final Map<String, Set<String>> _children;
  final Map<String, int> _counts;

  /// Storage volumes with audio.
  final List<String> roots;

  String nameOf(String path) =>
      roots.contains(path) ? volumeName(path) : path.substring(path.lastIndexOf('/') + 1);

  FolderEntry entry(String path) => FolderEntry(
        path: path,
        name: nameOf(path),
        songCount: _counts[path] ?? 0,
        folderCount: _children[path]?.length ?? 0,
      );

  /// Subfolders, by name. A chain of folders holding nothing but one
  /// subfolder (Android/media/com.app/…) is skipped through to where audio is.
  List<FolderEntry> foldersIn(String path) {
    final kids = [
      for (final k in _children[path] ?? const <String>{})
        () {
          final c = _collapse(k);
          final e = entry(c);
          // Collapsed: name the whole hop, e.g. "Media/WhatsApp Audio".
          final name = c == k ? e.name : c.substring(path == '/' ? 1 : path.length + 1);
          return FolderEntry(path: c, name: name, songCount: e.songCount, folderCount: e.folderCount);
        }(),
    ]..sort((a, b) => a.name.toLowerCase().compareTo(b.name.toLowerCase()));
    return kids;
  }

  String _collapse(String path) {
    var p = path;
    while ((_direct[p]?.isEmpty ?? true) && (_children[p]?.length ?? 0) == 1) {
      p = _children[p]!.first;
    }
    return p;
  }

  /// Songs directly in [path].
  List<Song> songsIn(String path) => _direct[path] ?? const [];

  /// Songs in [path] and below, folder by folder.
  List<Song> allUnder(String path) {
    final out = <Song>[...songsIn(path)];
    for (final f in foldersIn(path)) {
      out.addAll(allUnder(f.path));
    }
    return out;
  }
}
