import 'album.dart';
import 'song.dart';

class Artist {
  final int id;
  final String name;
  final List<Song> songs;
  final List<Album> albums;

  const Artist({
    required this.id,
    required this.name,
    required this.songs,
    required this.albums,
  });

  Song get coverSong => songs.first;
}
