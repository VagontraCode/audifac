import 'dart:math';

import 'package:audifac/core/audio/queue_logic.dart';
import 'package:audio_service/audio_service.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('repeat cycles off → all → one → off', () {
    var mode = AudioServiceRepeatMode.none;
    final seen = <AudioServiceRepeatMode>[];
    for (var i = 0; i < 3; i++) {
      mode = nextRepeatMode(mode);
      seen.add(mode);
    }
    expect(seen, [
      AudioServiceRepeatMode.all,
      AudioServiceRepeatMode.one,
      AudioServiceRepeatMode.none,
    ]);
  });

  test('repeat mode names round-trip', () {
    for (final mode in [
      AudioServiceRepeatMode.none,
      AudioServiceRepeatMode.all,
      AudioServiceRepeatMode.one,
    ]) {
      expect(repeatModeFromName(repeatModeName(mode)), mode);
    }
    expect(repeatModeFromName('garbage'), AudioServiceRepeatMode.none);
  });

  group('moveItem', () {
    test('moves forward and backward', () {
      expect(moveItem(['a', 'b', 'c', 'd'], 0, 2), ['b', 'c', 'a', 'd']);
      expect(moveItem(['a', 'b', 'c', 'd'], 3, 0), ['d', 'a', 'b', 'c']);
    });

    test('clamps out-of-range targets and leaves the input untouched', () {
      final input = ['a', 'b', 'c'];
      expect(moveItem(input, 0, 99), ['b', 'c', 'a']);
      expect(input, ['a', 'b', 'c']);
    });
  });

  group('upNext', () {
    test('returns what follows the current track in play order', () {
      expect(upNext(playOrder: [0, 1, 2, 3], currentIndex: 1), [2, 3]);
      expect(upNext(playOrder: [2, 0, 3, 1], currentIndex: 0), [3, 1]);
    });

    test('handles the last track and unknown indices', () {
      expect(upNext(playOrder: [0, 1, 2], currentIndex: 2), isEmpty);
      expect(upNext(playOrder: [0, 1], currentIndex: 5), isEmpty);
      expect(upNext(playOrder: [0, 1], currentIndex: null), [0, 1]);
    });
  });

  group('QueueShuffleOrder', () {
    QueueShuffleOrder order(List<int> indices) =>
        QueueShuffleOrder(random: Random(1))..indices.addAll(indices);

    test('shuffle keeps the initial index first and every index once', () {
      final o = order([0, 1, 2, 3, 4, 5])..shuffle(initialIndex: 3);
      expect(o.indices.first, 3);
      expect([...o.indices]..sort(), [0, 1, 2, 3, 4, 5]);
    });

    test('"play next" lands right after the current track in shuffle order', () {
      // Shuffled order 2 → 0 → 3 → 1, currently playing sequence index 0.
      final o = order([2, 0, 3, 1])
        ..placement = InsertPlacement.afterCurrent
        ..currentIndex = 0;
      // Handler inserts the new track at sequence index 1 (after current).
      o.insert(1, 1);
      // Old 1,2,3 shift to 2,3,4; new track 1 plays right after 0.
      expect(o.indices, [3, 0, 1, 4, 2]);
    });

    test('"add to queue" goes to the end of the shuffle order', () {
      final o = order([2, 0, 3, 1])..placement = InsertPlacement.end;
      o.insert(4, 2);
      expect(o.indices, [2, 0, 3, 1, 4, 5]);
    });

    test('removeRange drops and re-indexes', () {
      final o = order([3, 0, 4, 1, 2])..removeRange(1, 3); // remove 1 and 2
      expect(o.indices, [1, 0, 2]);
    });
  });
}
