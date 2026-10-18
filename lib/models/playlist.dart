class Playlist {
  final int id;
  final String name;

  /// MediaStore song ids, in playlist order.
  final List<int> songIds;
  final DateTime createdAt;

  const Playlist({
    required this.id,
    required this.name,
    required this.songIds,
    required this.createdAt,
  });

  Playlist copyWith({String? name, List<int>? songIds}) => Playlist(
        id: id,
        name: name ?? this.name,
        songIds: songIds ?? this.songIds,
        createdAt: createdAt,
      );
}
