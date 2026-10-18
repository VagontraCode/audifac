import 'dart:async';

import 'package:audio_service/audio_service.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'player_providers.dart';

enum SleepMode { off, minutes, endOfTrack, endOfQueue }

class SleepTimerState {
  const SleepTimerState({this.mode = SleepMode.off, this.endsAt, this.remaining});

  final SleepMode mode;

  /// Minutes mode: when playback stops.
  final DateTime? endsAt;

  /// Time left (minutes mode, or the last track in end-of-track/queue modes).
  final Duration? remaining;

  bool get active => mode != SleepMode.off;
}

/// Volume for [remaining] time left in a [fade]: 1 → 0 on a squared curve
/// (sounds even, unlike a linear ramp that seems to drop at the very end).
double sleepFadeVolume(Duration remaining, Duration fade) {
  if (remaining >= fade) return 1;
  if (remaining <= Duration.zero) return 0;
  final t = remaining.inMilliseconds / fade.inMilliseconds;
  return t * t;
}

final sleepTimerProvider = NotifierProvider<SleepTimerNotifier, SleepTimerState>(SleepTimerNotifier.new);

class SleepTimerNotifier extends Notifier<SleepTimerState> {
  static const minutesFade = Duration(seconds: 30);
  static const trackFade = Duration(seconds: 8);

  Timer? _ticker;
  int? _armedIndex;
  bool _faded = false;

  @override
  SleepTimerState build() {
    ref.onDispose(() => _ticker?.cancel());
    return const SleepTimerState();
  }

  void start(Duration length) => _begin(SleepTimerState(mode: SleepMode.minutes, endsAt: DateTime.now().add(length)));

  void startEndOfTrack() => _begin(const SleepTimerState(mode: SleepMode.endOfTrack));

  void startEndOfQueue() => _begin(const SleepTimerState(mode: SleepMode.endOfQueue));

  /// Minutes mode: push the end back.
  void extend(Duration by) {
    final ends = state.endsAt;
    if (state.mode != SleepMode.minutes || ends == null) return;
    state = SleepTimerState(mode: SleepMode.minutes, endsAt: ends.add(by), remaining: state.remaining);
    _tick();
  }

  void cancel() {
    _ticker?.cancel();
    _ticker = null;
    state = const SleepTimerState();
    _restoreVolume();
  }

  void _begin(SleepTimerState next) {
    _ticker?.cancel();
    _armedIndex = ref.read(audioHandlerProvider).currentIndex;
    _lastWasArmed = false;
    state = next;
    _restoreVolume();
    _ticker = Timer.periodic(const Duration(milliseconds: 250), (_) => _tick());
    _tick();
  }

  void _restoreVolume() {
    if (_faded) ref.read(audioHandlerProvider).setVolume(1);
    _faded = false;
  }

  void _setVolume(double v) {
    _faded = v < 1;
    ref.read(audioHandlerProvider).setVolume(v);
  }

  Future<void> _finish() async {
    final handler = ref.read(audioHandlerProvider);
    _ticker?.cancel();
    _ticker = null;
    state = const SleepTimerState();
    await handler.pause();
    _restoreVolume();
  }

  void _tick() {
    final handler = ref.read(audioHandlerProvider);
    switch (state.mode) {
      case SleepMode.off:
        return;
      case SleepMode.minutes:
        final remaining = state.endsAt!.difference(DateTime.now());
        state = SleepTimerState(mode: state.mode, endsAt: state.endsAt, remaining: remaining);
        if (remaining <= Duration.zero) {
          _finish();
        } else if (ref.read(isPlayingProvider)) {
          _setVolume(sleepFadeVolume(remaining, minutesFade));
        }
      case SleepMode.endOfTrack || SleepMode.endOfQueue:
        final index = handler.currentIndex;
        final order = handler.playOrder;
        final repeatOne = ref.read(playbackStateProvider).value?.repeatMode == AudioServiceRepeatMode.one;
        // End of queue: only the last track in play order counts.
        final armed = state.mode == SleepMode.endOfTrack || (order.isNotEmpty && index == order.last) || repeatOne;
        if (index != _armedIndex) {
          if (_lastWasArmed) {
            // The armed track just ended: stop at the start of the next one.
            handler.seek(Duration.zero);
            _finish();
            return;
          }
          _armedIndex = index;
        }
        _lastWasArmed = armed;
        final duration = handler.duration;
        if (!armed || duration == null) {
          state = SleepTimerState(mode: state.mode);
          return;
        }
        final remaining = duration - handler.position;
        state = SleepTimerState(mode: state.mode, remaining: remaining);
        // Repeat-one never changes track; the queue's last song just stops.
        if ((repeatOne || !ref.read(isPlayingProvider)) && remaining <= const Duration(milliseconds: 300)) {
          _finish();
        } else if (ref.read(isPlayingProvider)) {
          _setVolume(sleepFadeVolume(remaining, trackFade));
        }
    }
  }

  bool _lastWasArmed = false;
}
