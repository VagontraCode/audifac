import 'dart:math';

import 'package:audifac/core/audio/queue_logic.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  // Sequence: album A = 0,1,2 · album B = 3,4 · album C = 5,6,7,8.
  const albums = ['A', 'A', 'A', 'B', 'B', 'C', 'C', 'C', 'C'];

  QueueShuffleOrder order(int seed) {
    final o = QueueShuffleOrder(random: Random(seed))..albumOf = (i) => albums[i];
    o.insert(0, albums.length);
    return o;
  }

  List<List<int>> runs(List<int> indices) {
    final out = <List<int>>[];
    for (final i in indices) {
      if (out.isNotEmpty && albums[out.last.last] == albums[i]) {
        out.last.add(i);
      } else {
        out.add([i]);
      }
    }
    return out;
  }

  test('albums stay whole and in order; album order varies', () {
    final seen = <String>{};
    for (var seed = 0; seed < 20; seed++) {
      final o = order(seed)..shuffle();
      expect(o.indices.toSet(), {for (var i = 0; i < albums.length; i++) i});
      final r = runs(o.indices);
      expect(r.length, 3, reason: 'each album is one block');
      for (final block in r) {
        expect(block, [...block]..sort());
      }
      seen.add(r.map((b) => albums[b.first]).join());
    }
    expect(seen.length, greaterThan(1));
  });

  test('starting mid-album: that track first, the album\'s earlier tracks at its end', () {
    final o = order(3)..shuffle(initialIndex: 6);
    expect(o.indices.take(4), [6, 7, 8, 5]);
  });

  test('without albums it is a plain song shuffle', () {
    final o = QueueShuffleOrder(random: Random(1))..insert(0, 9);
    o.shuffle(initialIndex: 4);
    expect(o.indices.first, 4);
    expect(o.indices.toSet().length, 9);
  });
}
