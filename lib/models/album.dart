import 'song.dart';

class Album {
  final int id;
  final String title;
  final String artist;
  final List<Song> songs;

  const Album({
    required this.id,
    required this.title,
    required this.artist,
    required this.songs,
  });

  /// Song whose embedded artwork represents the album.
  Song get coverSong => songs.first;

  Duration get totalDuration =>
      songs.fold(Duration.zero, (sum, s) => sum + s.duration);
}
