import 'dart:async';

import 'package:flutter/services.dart';

import '../models/eq.dart';
import '../models/loudness.dart';

/// Talks to the native DSP (`DspChannel.kt`): applies settings and reports the
/// current audio output.
class DspChannel {
  DspChannel() {
    _channel.setMethodCallHandler((call) async {
      if (call.method == 'outputChanged' && call.arguments is Map) {
        _outputs.add(EqDevice.fromNative(call.arguments as Map));
      }
    });
  }

  static const _channel = MethodChannel('audifac/dsp');
  final _outputs = StreamController<EqDevice>.broadcast();

  /// Fires when headphones / Bluetooth / USB audio connect or disconnect.
  Stream<EqDevice> get outputChanges => _outputs.stream;

  Future<EqDevice> currentOutput() async {
    try {
      final raw = await _channel.invokeMapMethod<String, dynamic>('outputDevice');
      return raw == null ? _speaker : EqDevice.fromNative(raw);
    } on MissingPluginException {
      return _speaker;
    }
  }

  static final _speaker = EqDevice.fromNative(const {'key': 'speaker', 'kind': 'speaker', 'name': 'Phone speaker'});

  Future<void> setConfig(Map<String, Object> config) async {
    try {
      await _channel.invokeMethod('setConfig', config);
    } on MissingPluginException {
      // Tests / non-Android.
    }
  }

  Future<void> setVolumeMatching(Map<String, Object> settings) => _invoke('setVolumeMatching', settings);

  /// Per-file gains by native key; [replace] drops files not in [gains].
  Future<void> setGains(Map<String, Gains> gains, {bool replace = true}) => _invoke('setGains', {
        'gains': {
          for (final e in gains.entries)
            e.key: {
              'trackGainDb': e.value.trackGainDb,
              'trackPeak': e.value.trackPeak,
              'albumGainDb': e.value.albumGainDb,
              'albumPeak': e.value.albumPeak,
            },
        },
        'replace': replace,
      });

  /// What the DSP sink is doing and where audio goes (see `SignalPath.kt`).
  Future<Map<String, dynamic>?> signalPath() async {
    try {
      return await _channel.invokeMapMethod<String, dynamic>('signalPath');
    } on MissingPluginException {
      return null;
    }
  }

  static const _visualizer = EventChannel('audifac/visualizer');

  /// ~30 frames / s of spectrum bands and levels (dBFS) while listened to.
  Stream<VisualizerFrame> get visualizer => _visualizer.receiveBroadcastStream().map((e) {
        final m = e as Map;
        double d(String k) => (m[k] as num).toDouble();
        return VisualizerFrame(
          bands: [for (final b in m['bands'] as List) (b as num).toDouble()],
          peakL: d('peakL'),
          peakR: d('peakR'),
          rmsL: d('rmsL'),
          rmsR: d('rmsR'),
        );
      });

  /// Crossfade length (0 = off) and the album of each queued file (no
  /// crossfade between tracks of one album).
  /// Bit-perfect USB output when nothing needs processing; false when the
  /// phone can't (Android < 14).
  Future<bool> setBitPerfect(bool on) async {
    try {
      return await _channel.invokeMethod<bool>('setBitPerfect', on) ?? false;
    } on MissingPluginException {
      return false;
    }
  }

  Future<void> setCrossfade(int seconds, Map<String, int> albums) =>
      _invoke('setCrossfade', {'seconds': seconds, 'albums': albums});

  /// Tags or an R128 measurement for each location (slow for untagged files:
  /// they are decoded).
  Future<List<Map<dynamic, dynamic>>> analyseLoudness(List<String> locations) async {
    try {
      final raw = await _channel.invokeListMethod<Map<dynamic, dynamic>>('analyseLoudness', {'locations': locations});
      return raw ?? const [];
    } on MissingPluginException {
      return const [];
    }
  }

  Future<void> _invoke(String method, Object arguments) async {
    try {
      await _channel.invokeMethod(method, arguments);
    } on MissingPluginException {
      // Tests / non-Android.
    }
  }

  /// A/B: hear the unprocessed signal while true.
  Future<void> setBypass(bool bypass) async {
    try {
      await _channel.invokeMethod('setBypass', bypass);
    } on MissingPluginException {
      // Tests / non-Android.
    }
  }
}

/// One visualizer frame: 32 log-spaced bands (30 Hz – 20 kHz) and per-channel
/// peak / RMS, all in dBFS.
class VisualizerFrame {
  const VisualizerFrame({required this.bands, required this.peakL, required this.peakR, required this.rmsL, required this.rmsR});

  final List<double> bands;
  final double peakL;
  final double peakR;
  final double rmsL;
  final double rmsR;
}
