import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../models/playback_memory.dart';
import 'player_providers.dart';
import 'user_data_providers.dart';

/// Speed and volume matching mode remembered per album / artist.
final playbackMemoryProvider = NotifierProvider<PlaybackMemoryNotifier, PlaybackMemories>(PlaybackMemoryNotifier.new);

class PlaybackMemoryNotifier extends Notifier<PlaybackMemories> {
  static const key = 'playback_memory';

  @override
  PlaybackMemories build() => PlaybackMemories.decode(ref.read(bootstrapProvider).values[key]);

  void setAlbum(int albumId, PlaybackMemory memory) => _save(state.withAlbum(albumId, memory));

  void setArtist(String artist, PlaybackMemory memory) => _save(state.withArtist(artist, memory));

  void _save(PlaybackMemories next) {
    state = next;
    ref.read(databaseProvider).setValue(key, next.encode());
  }
}

/// What applies to the song playing now.
final currentPlaybackMemoryProvider = Provider<PlaybackMemory>((ref) {
  final song = ref.watch(currentSongProvider);
  return song == null ? const PlaybackMemory() : ref.watch(playbackMemoryProvider).forSong(song);
});
