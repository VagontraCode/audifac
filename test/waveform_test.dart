import 'dart:typed_data';

import 'package:audifac/widgets/waveform_painter.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('pool keeps the loudest level of each group', () {
    final levels = Uint8List.fromList([0, 255, 51, 102, 0, 0, 204, 0]);
    expect(WaveformPainter.pool(levels, 4), [1.0, 0.4, 0.0, 0.8]);
    expect(WaveformPainter.pool(levels, 8).length, 8);
    // More bars than levels: each bar still reads one level.
    expect(WaveformPainter.pool(Uint8List.fromList([255, 0]), 4), [1.0, 1.0, 0.0, 0.0]);
    expect(WaveformPainter.pool(Uint8List(0), 4), isEmpty);
  });
}
