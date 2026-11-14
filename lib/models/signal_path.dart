/// Where sound quality changes between the file and your ears (Signal sheet
/// → verdict). EQ and other processing the user chose are not losses.
enum SignalLoss {
  /// The file itself is lossy (MP3, AAC…).
  lossySource,

  /// Android's mixer runs at another rate and resamples.
  androidResampling,

  /// Hi-res audio reduced to 16-bit for an output that takes no more.
  reducedTo16Bit,

  /// The limiter is catching peaks (EQ / gain too hot) or samples clip.
  limiting,

  /// Bluetooth re-encodes for the radio link.
  bluetooth,
}

/// The losses on the current path, in signal order.
List<SignalLoss> signalLosses({
  required bool? sourceLossless,
  required int? sourceBits,
  required bool bitPerfect,
  required int reachingRate,
  required int? mixerRate,
  required bool output16,
  required double limitedFraction,
  required int clippedFrames,
  required String? outputKind,
}) => [
  if (sourceLossless == false) SignalLoss.lossySource,
  if (limitedFraction >= 0.0001 || clippedFrames > 0) SignalLoss.limiting,
  if (!bitPerfect && output16 && (sourceBits ?? 16) > 16) SignalLoss.reducedTo16Bit,
  if (!bitPerfect && mixerRate != null && reachingRate > 0 && mixerRate != reachingRate) SignalLoss.androidResampling,
  if (outputKind == 'bluetooth') SignalLoss.bluetooth,
];
