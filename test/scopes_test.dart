import 'dart:typed_data';

import 'package:audifac/widgets/scopes.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('spectrogram colours run from near black to pale yellow', () {
    final p = SpectrogramBuffer.palette;
    expect(p.length, 256 * 3);
    expect([p[0], p[1], p[2]], [0, 0, 4]);
    expect([p[765], p[766], p[767]], [0xFC, 0xFD, 0xBF]);
    // Brightness grows overall.
    int sum(int i) => p[i * 3] + p[i * 3 + 1] + p[i * 3 + 2];
    expect(sum(64) < sum(192), isTrue);
  });

  test('the scope trail keeps the newest frames', () {
    final t = ScopeTrail(length: 2);
    for (var i = 0; i < 3; i++) {
      t.add(Float32List.fromList([i.toDouble(), 0]));
    }
    t.add(Float32List(0));
    expect(t.frames.map((f) => f[0]), [1, 2]);
  });
}
