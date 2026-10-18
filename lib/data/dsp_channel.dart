import 'dart:async';

import 'package:flutter/services.dart';

import '../models/eq.dart';

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

  /// A/B: hear the unprocessed signal while true.
  Future<void> setBypass(bool bypass) async {
    try {
      await _channel.invokeMethod('setBypass', bypass);
    } on MissingPluginException {
      // Tests / non-Android.
    }
  }
}
