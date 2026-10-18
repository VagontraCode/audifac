import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../core/theme/app_colors.dart';

/// Small animated equalizer shown next to the song that is playing.
/// Bars settle down when [playing] is false.
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

class _NowPlayingBarsState extends State<NowPlayingBars>
    with SingleTickerProviderStateMixin {
  late final _controller = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 1100),
  );

  static const _bars = 4;
  static const _phases = [0.0, 1.9, 0.8, 2.7];
  // Whole numbers so the wave loops seamlessly when the controller repeats.
  static const _speeds = [1.0, 2.0, 1.0, 3.0];

  @override
  void initState() {
    super.initState();
    if (widget.playing) _controller.repeat();
  }

  @override
  void didUpdateWidget(NowPlayingBars oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.playing && !_controller.isAnimating) {
      _controller.repeat();
    } else if (!widget.playing && _controller.isAnimating) {
      _controller.stop();
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final barWidth = widget.size / (_bars * 1.8);
    final color = widget.color ?? context.palette.ink;
    return SizedBox.square(
      dimension: widget.size,
      child: AnimatedBuilder(
        animation: _controller,
        builder: (context, _) => Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          crossAxisAlignment: CrossAxisAlignment.end,
          children: List.generate(_bars, (i) {
            final t = _controller.value * 2 * math.pi * _speeds[i] + _phases[i];
            final level = widget.playing ? 0.3 + 0.7 * (math.sin(t) + 1) / 2 : 0.25;
            return Container(
              width: barWidth,
              height: widget.size * level,
              decoration: BoxDecoration(
                color: color,
                borderRadius: BorderRadius.circular(barWidth),
              ),
            );
          }),
        ),
      ),
    );
  }
}
