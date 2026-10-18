import 'package:audifac/models/folder_tree.dart';
import 'package:audifac/models/song.dart';
import 'package:flutter_test/flutter_test.dart';

var _id = 0;
Song _at(String path) => Song(
      id: ++_id,
      uri: 'content://media/external/audio/media/$_id',
      path: path,
      title: path.split('/').last,
      artist: 'a',
      artistId: 1,
      album: 'b',
      albumId: 1,
      duration: const Duration(minutes: 3),
      dateAdded: DateTime(2024),
    );

void main() {
  final tree = FolderTree.of([
    _at('/storage/emulated/0/Music/Jazz/a.flac'),
    _at('/storage/emulated/0/Music/Jazz/b.flac'),
    _at('/storage/emulated/0/Music/Rock/c.mp3'),
    _at('/storage/emulated/0/Music/d.mp3'),
    _at('/storage/emulated/0/Android/media/com.whatsapp/WhatsApp/Media/WhatsApp Audio/e.opus'),
    _at('/storage/1A2B-3C4D/Albums/f.flac'),
  ]);

  test('volumes', () {
    expect(tree.roots, ['/storage/1A2B-3C4D', '/storage/emulated/0']);
    expect(tree.nameOf('/storage/emulated/0'), 'Internal storage');
    expect(tree.nameOf('/storage/1A2B-3C4D'), 'SD card');
    expect(tree.entry('/storage/emulated/0').songCount, 5);
  });

  test('children, counts, collapsed chains', () {
    final top = tree.foldersIn('/storage/emulated/0');
    expect([for (final f in top) f.name], ['Android/media/com.whatsapp/WhatsApp/Media/WhatsApp Audio', 'Music']);
    expect(top.first.path, '/storage/emulated/0/Android/media/com.whatsapp/WhatsApp/Media/WhatsApp Audio');
    final music = top.last;
    expect(music.songCount, 4);
    expect(music.folderCount, 2);
    expect([for (final f in tree.foldersIn(music.path)) f.name], ['Jazz', 'Rock']);
    expect([for (final s in tree.songsIn(music.path)) s.title], ['d.mp3']);
  });

  test('everything below, folder by folder', () {
    expect([for (final s in tree.allUnder('/storage/emulated/0/Music')) s.title], ['d.mp3', 'a.flac', 'b.flac', 'c.mp3']);
    expect(tree.allUnder('/nowhere'), isEmpty);
  });
}
