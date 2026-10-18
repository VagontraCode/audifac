import 'dart:math';

import 'package:audio_service/audio_service.dart';
import 'package:just_audio/just_audio.dart' show ShuffleOrder;

/// Pure queue helpers, kept free of the audio engine so they can be tested.

/// Repeat button cycle: off → all → one → off.
AudioServiceRepeatMode nextRepeatMode(AudioServiceRepeatMode mode) => switch (mode) {
      AudioServiceRepeatMode.none => AudioServiceRepeatMode.all,
      AudioServiceRepeatMode.all || AudioServiceRepeatMode.group => AudioServiceRepeatMode.one,
      AudioServiceRepeatMode.one => AudioServiceRepeatMode.none,
    };

String repeatModeName(AudioServiceRepeatMode mode) => switch (mode) {
      AudioServiceRepeatMode.none => 'none',
      AudioServiceRepeatMode.one => 'one',
      AudioServiceRepeatMode.all || AudioServiceRepeatMode.group => 'all',
    };

AudioServiceRepeatMode repeatModeFromName(String name) => switch (name) {
      'one' => AudioServiceRepeatMode.one,
      'all' => AudioServiceRepeatMode.all,
      _ => AudioServiceRepeatMode.none,
    };

/// Returns a copy of [items] with the element at [from] moved to [to]
/// (`to` already expressed as a post-removal index).
List<T> moveItem<T>(List<T> items, int from, int to) {
  final copy = [...items];
  final item = copy.removeAt(from);
  copy.insert(to.clamp(0, copy.length), item);
  return copy;
}

/// Sequence indices that will play after [currentIndex], following
/// [playOrder] (the shuffle order when shuffling, else 0..n-1).
List<int> upNext({required List<int> playOrder, required int? currentIndex}) {
  if (currentIndex == null) return playOrder;
  final position = playOrder.indexOf(currentIndex);
  if (position < 0) return const [];
  return playOrder.sublist(position + 1);
}

enum InsertPlacement { afterCurrent, end }

/// Shuffle order that respects "Play next" / "Add to queue" while shuffling.
///
/// just_audio's default order drops inserted tracks at random positions; this
/// one places them right after the current track or at the end of the order,
/// depending on [placement] (set by the handler before each insert).
class QueueShuffleOrder extends ShuffleOrder {
  QueueShuffleOrder({Random? random}) : _random = random ?? Random();

  final Random _random;

  @override
  final indices = <int>[];

  /// Sequence index of the track playing when the next insert happens.
  int? currentIndex;
  InsertPlacement placement = InsertPlacement.end;

  @override
  void shuffle({int? initialIndex}) {
    if (indices.length <= 1) return;
    indices.shuffle(_random);
    if (initialIndex == null) return;
    final swapPos = indices.indexOf(initialIndex);
    if (swapPos < 0) return;
    indices[swapPos] = indices[0];
    indices[0] = initialIndex;
  }

  @override
  void insert(int index, int count) {
    for (var i = 0; i < indices.length; i++) {
      if (indices[i] >= index) indices[i] += count;
    }
    final added = List.generate(count, (i) => index + i);

    var insertAt = indices.length;
    if (placement == InsertPlacement.afterCurrent && currentIndex != null) {
      // currentIndex refers to the pre-insert sequence; shift it the same way.
      final current = currentIndex! >= index ? currentIndex! + count : currentIndex!;
      final pos = indices.indexOf(current);
      if (pos >= 0) insertAt = pos + 1;
    }
    indices.insertAll(insertAt, added);
  }

  @override
  void removeRange(int start, int end) {
    final count = end - start;
    indices.removeWhere((i) => i >= start && i < end);
    for (var i = 0; i < indices.length; i++) {
      if (indices[i] >= end) indices[i] -= count;
    }
  }

  @override
  void clear() => indices.clear();
}
