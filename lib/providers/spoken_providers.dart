import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../models/song.dart';
import '../models/spoken.dart';
import 'library_providers.dart';
import 'playback_memory_provider.dart';
import 'player_providers.dart';
import 'user_data_providers.dart';

/// Speed for audiobooks & podcasts (music always plays at 1×).
final spokenSpeedProvider = NotifierProvider<SpokenSpeedNotifier, double>(SpokenSpeedNotifier.new);

class SpokenSpeedNotifier extends Notifier<double> {
  static const key = 'spoken_speed';
  static const choices = [0.75, 1.0, 1.25, 1.5, 1.75, 2.0, 2.5, 3.0];

  @override
  double build() => (double.tryParse(ref.read(bootstrapProvider).values[key] ?? '') ?? 1.0).clamp(0.5, 3.0).toDouble();

  void set(double speed) {
    state = (speed * 20).round() / 20; // 0.05 steps
    ref.read(databaseProvider).setValue(key, '$state');
  }
}

/// Is the current item an audiobook / podcast / long recording?
final currentIsLongFormProvider = Provider<bool>((ref) {
  final song = ref.watch(currentSongProvider);
  return song != null && isLongForm(song);
});

/// The speed the current item plays at: remembered for its album / artist,
/// else the spoken-word speed for audiobooks & podcasts, else 1×.
final effectiveSpeedProvider = Provider<double>((ref) {
  final remembered = ref.watch(currentPlaybackMemoryProvider).speed;
  if (remembered != null) return remembered;
  return ref.watch(currentIsLongFormProvider) ? ref.watch(spokenSpeedProvider) : 1.0;
});

final chaptersProvider = FutureProvider.family<List<Chapter>, Song>((ref, song) async {
  if (!mayHaveChapters(song)) return const [];
  final raw = await ref.read(mediaLibraryProvider).readChapters(song);
  final chapters = [for (final c in raw) Chapter(Duration(milliseconds: c.startMs), c.title)];
  // A single "chapter" covering everything isn't worth showing.
  return chapters.length < 2 ? const [] : chapters;
});

String _resumeKey(Song song) => 'resume:${song.location}';

/// Applies the spoken-word speed and resumes long recordings where they were
/// left. Watched once by the app shell.
final spokenControllerProvider = Provider<void>((ref) {
  final handler = ref.read(audioHandlerProvider);
  final db = ref.read(databaseProvider);
  Timer? saver;
  Song? current;

  /// [announce]: tell "Continue listening" (not for the 5 s saves while
  /// playing, which would rebuild Home all the time).
  Future<void> savePosition({bool announce = false}) async {
    final song = current;
    if (song == null || !isLongForm(song)) return;
    final position = handler.position;
    final finished = song.duration > Duration.zero && position > song.duration - const Duration(seconds: 30);
    if (finished) {
      await db.deleteValue(_resumeKey(song));
    } else if (position > const Duration(seconds: 10)) {
      await db.setValue(_resumeKey(song), encodeResumeSpot(position, DateTime.now()));
    } else {
      return;
    }
    if (announce) ref.read(resumeRevisionProvider.notifier).bump();
  }

  Future<void> onSong(Song? song, {bool restarted = false}) async {
    // A new queue starting on the same book (tapped again) resumes too.
    if (!restarted && song?.location == current?.location) return;
    // (No save for the one we're leaving: the position already belongs to
    // the new song. The 5 s saver and the save on pause have it.)
    current = song;
    if (song == null) return;
    if (!isLongForm(song)) return;
    final saved = decodeResumeSpot(await db.getValue(_resumeKey(song)));
    final point = resumePoint(saved?.position, song.duration);
    // Only jump when the song is starting from the top (not a restored session
    // or a seek the user just made).
    if (point != null && handler.position < const Duration(seconds: 5)) await handler.seek(point);
  }

  ref.listen(currentSongProvider, (_, song) => onSong(song), fireImmediately: true);
  final starts = handler.queueStarts.listen((song) => onSong(song, restarted: true));
  // Speed follows the song: remembered for its album / artist, the spoken
  // speed for books and podcasts, else 1×.
  ref.listen(effectiveSpeedProvider, (_, speed) {
    if (handler.speed != speed) handler.setSpeed(speed);
  }, fireImmediately: true);
  ref.listen(isPlayingProvider, (_, playing) {
    saver?.cancel();
    if (playing) {
      saver = Timer.periodic(const Duration(seconds: 5), (_) => savePosition());
    } else {
      savePosition(announce: true);
    }
  });
  ref.onDispose(() {
    saver?.cancel();
    starts.cancel();
  });
});

/// Bumped when a resume spot is saved on pause / finished: "Continue
/// listening" reloads.
final resumeRevisionProvider = NotifierProvider<ResumeRevision, int>(ResumeRevision.new);

class ResumeRevision extends Notifier<int> {
  @override
  int build() => 0;

  void bump() => state++;
}

/// A recording left part-way, for Home → Continue listening.
typedef InProgress = ({Song song, Duration position, double progress});

/// Audiobooks and podcasts started but not finished, most recent first.
final continueListeningProvider = FutureProvider<List<InProgress>>((ref) async {
  ref.watch(resumeRevisionProvider);
  final songs = ref.watch(songsProvider);
  final spots = await ref.read(databaseProvider).valuesWithPrefix('resume:');
  if (spots.isEmpty) return const [];
  final byLocation = {for (final s in songs) if (!s.isCueTrack) s.location: s};
  final found = <(InProgress, DateTime?)>[];
  for (final MapEntry(:key, :value) in spots.entries) {
    final song = byLocation[key.substring('resume:'.length)];
    final spot = decodeResumeSpot(value);
    if (song == null || spot == null || !isLongForm(song)) continue;
    if (resumePoint(spot.position, song.duration) == null) continue;
    final length = song.duration.inMilliseconds;
    final progress = length <= 0 ? 0.0 : (spot.position.inMilliseconds / length).clamp(0.0, 1.0);
    found.add(((song: song, position: spot.position, progress: progress), spot.savedAt));
  }
  // Newest first; spots from older versions (no date) last.
  found.sort((a, b) => (b.$2?.millisecondsSinceEpoch ?? 0).compareTo(a.$2?.millisecondsSinceEpoch ?? 0));
  return [for (final f in found.take(10)) f.$1];
});

/// Database keys of bookmarks: this prefix + [Song.location].
const bookmarksKeyPrefix = 'bookmarks:';

/// Bookmarks of one recording (by [Song.location]).
final bookmarksProvider =
    AsyncNotifierProvider.family<BookmarksNotifier, List<Bookmark>, String>(BookmarksNotifier.new);

class BookmarksNotifier extends AsyncNotifier<List<Bookmark>> {
  BookmarksNotifier(this.location);

  final String location;

  String get _key => '$bookmarksKeyPrefix$location';

  @override
  Future<List<Bookmark>> build() async => Bookmark.decodeAll(await ref.read(databaseProvider).getValue(_key));

  Future<void> add(Bookmark bookmark) =>
      _save([...?state.value, bookmark]..sort((a, b) => a.position.compareTo(b.position)));

  Future<void> remove(Bookmark bookmark) => _save([...?state.value]..remove(bookmark));

  Future<void> _save(List<Bookmark> bookmarks) async {
    state = AsyncData(bookmarks);
    final db = ref.read(databaseProvider);
    if (bookmarks.isEmpty) {
      await db.deleteValue(_key);
    } else {
      await db.setValue(_key, Bookmark.encodeAll(bookmarks));
    }
  }
}
