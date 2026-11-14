import 'package:audifac/models/signal_path.dart';
import 'package:flutter_test/flutter_test.dart';

List<SignalLoss> losses({
  bool? lossless = true,
  int? bits = 16,
  bool bitPerfect = false,
  int reaching = 48000,
  int? mixer = 48000,
  bool output16 = false,
  double limited = 0,
  int clipped = 0,
  String? kind = 'wired',
}) => signalLosses(
  sourceLossless: lossless,
  sourceBits: bits,
  bitPerfect: bitPerfect,
  reachingRate: reaching,
  mixerRate: mixer,
  output16: output16,
  limitedFraction: limited,
  clippedFrames: clipped,
  outputKind: kind,
);

void main() {
  test('a clean path', () => expect(losses(), isEmpty));

  test('each loss, in signal order', () {
    expect(
      losses(lossless: false, bits: 24, output16: true, limited: 0.01, reaching: 44100, kind: 'bluetooth'),
      [SignalLoss.lossySource, SignalLoss.limiting, SignalLoss.reducedTo16Bit, SignalLoss.androidResampling, SignalLoss.bluetooth],
    );
  });

  test('bit-perfect USB skips the mixer and the 16-bit step', () {
    expect(losses(bitPerfect: true, reaching: 96000, mixer: 48000, bits: 24, output16: true, kind: 'usb'), isEmpty);
  });

  test('16-bit output of a 16-bit file loses nothing; unknown details are no loss', () {
    expect(losses(output16: true), isEmpty);
    expect(losses(lossless: null, mixer: null), isEmpty);
  });
}
