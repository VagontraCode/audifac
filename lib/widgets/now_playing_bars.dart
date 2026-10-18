import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../core/theme/app_colors.dart';

/// Small animated equalizer shown next to the song that is playing.
/// Bars settle down when [playing] is false.
///
/// Battery: the bars move at [_BarsClock.fps] frames per second from one
/// shared clock, instead of one frame per display refresh (60–120 Hz) — that
/// kept the raster thread at ~75 % of a core for as long as music played
/// with a list on screen. The clock stops when nothing animated is visible:
/// paused, app in the background, or the list covered by another screen.
class NowPlayingBars extends StatefulWidget {
  const NowPlayingBars({
    super.key,
    required this.playing,
    this.color,
    this.size = 16,
  });

  final bool playing;
  /// Defaults to the palette's ink color.
  final Color? color;
  final double size;

  @override
  State<NowPlayingBars> createState() => _NowPlayingBarsState();
}

class _NowPlayingBarsState extends State<NowPlayingBars> {
  bool _tickersEnabled = true;
  bool _subscribed = false;

  bool get _animating => widget.playing && _tickersEnabled;

  void _sync() {
    if (_animating && !_subscribed) {
      _BarsClock.instance.addUser();
      _subscribed = true;
    } else if (!_animating && _subscribed) {
      _BarsClock.instance.removeUser();
      _subscribed = false;
    }
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    // False while this widget's route is covered (offstage) — e.g. the
    // library under the full-screen player.
    _tickersEnabled = TickerMode.valuesOf(context).enabled;
    _sync();
  }

  @override
  void didUpdateWidget(NowPlayingBars oldWidget) {
    super.didUpdateWidget(oldWidget);
    _sync();
  }

  @override
  void dispose() {
    if (_subscribed) _BarsClock.instance.removeUser();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return RepaintBoundary(
      child: CustomPaint(
        size: Size.square(widget.size),
        painter: _BarsPainter(
          color: widget.color ?? context.palette.ink,
          clock: _animating ? _BarsClock.instance : null,
        ),
      ),
    );
  }
}

class _BarsPainter extends CustomPainter {
  _BarsPainter({required this.color, required this.clock}) : super(repaint: clock);

  final Color color;
  /// Null when still.
  final _BarsClock? clock;

  static const _bars = 4;
  static const _phases = [0.0, 1.9, 0.8, 2.7];
  // Whole numbers so the wave loops seamlessly.
  static const _speeds = [1.0, 2.0, 1.0, 3.0];

  @override
  void paint(Canvas canvas, Size size) {
    final barWidth = size.width / (_bars * 1.8);
    final gap = (size.width - barWidth * _bars) / (_bars - 1);
    final paint = Paint()..color = color;
    final radius = Radius.circular(barWidth);
    final c = clock;
    for (var i = 0; i < _bars; i++) {
      final level = c == null
          ? 0.25
          : 0.3 + 0.7 * (math.sin(c.phase * 2 * math.pi * _speeds[i] + _phases[i]) + 1) / 2;
      final h = size.height * level;
      final x = i * (barWidth + gap);
      canvas.drawRRect(RRect.fromLTRBR(x, size.height - h, x + barWidth, size.height, radius), paint);
    }
  }

  @override
  bool shouldRepaint(_BarsPainter old) => old.color != color || old.clock != clock;
}

/// One low-rate clock for every [NowPlayingBars] on screen; runs only while
/// one of them animates and the app is in the foreground.
class _BarsClock extends ChangeNotifier {
  _BarsClock._();

  static final instance = _BarsClock._();

  static const fps = 12;
  static const _cycle = Duration(milliseconds: 1100);

  final _watch = Stopwatch();
  Timer? _timer;
  AppLifecycleListener? _lifecycle;
  bool _foreground = true;
  int _users = 0;

  /// Position in the 1.1 s animation cycle, 0…1.
  double get phase => (_watch.elapsedMicroseconds % _cycle.inMicroseconds) / _cycle.inMicroseconds;

  void addUser() {
    _users++;
    _lifecycle ??= AppLifecycleListener(onStateChange: (state) {
      _foreground = state == AppLifecycleState.resumed;
      _update();
    });
    _update();
  }

  void removeUser() {
    _users--;
    _update();
  }

  void _update() {
    final run = _users > 0 && _foreground;
    if (run && _timer == null) {
      _watch.start();
      _timer = Timer.periodic(const Duration(microseconds: 1000000 ~/ fps), (_) => notifyListeners());
    } else if (!run && _timer != null) {
      _timer!.cancel();
      _timer = null;
      _watch.stop();
    }
  }
}
