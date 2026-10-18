import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../core/format.dart';
import '../core/theme/app_colors.dart';
import '../providers/player_providers.dart';

/// Seek slider with elapsed / remaining time. While dragging, the thumb grows,
/// the track thickens, and the player only seeks on release.
class SeekBar extends ConsumerStatefulWidget {
  const SeekBar({super.key, required this.duration, this.color});

  final Duration? duration;

  /// Active track / thumb color (defaults to the palette's ink).
  final Color? color;

  @override
  ConsumerState<SeekBar> createState() => _SeekBarState();
}

class _SeekBarState extends ConsumerState<SeekBar> {
  double? _dragValue;

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    final color = widget.color ?? palette.ink;
    final position = ref.watch(positionProvider).value ?? Duration.zero;
    final total = widget.duration ?? Duration.zero;
    final max = total.inMilliseconds.toDouble();
    final dragging = _dragValue != null;
    final value = (_dragValue ?? position.inMilliseconds.toDouble()).clamp(0.0, max);
    final shown = Duration(milliseconds: value.round());
    final style = Theme.of(context).textTheme.bodySmall?.copyWith(
          color: dragging ? color : palette.inkMuted,
          fontWeight: dragging ? FontWeight.w700 : FontWeight.w400,
          fontFeatures: const [FontFeature.tabularFigures()],
        );

    return Column(
      children: [
        TweenAnimationBuilder<double>(
          tween: Tween(end: dragging ? 1 : 0),
          duration: const Duration(milliseconds: 180),
          curve: Curves.easeOut,
          builder: (context, t, child) => SliderTheme(
            data: SliderTheme.of(context).copyWith(
              trackHeight: 4 + 4 * t,
              activeTrackColor: color,
              thumbColor: color,
              inactiveTrackColor: palette.ink.withValues(alpha: 0.12),
              overlayColor: color.withValues(alpha: 0.12),
              thumbShape: RoundSliderThumbShape(enabledThumbRadius: 6 + 3 * t),
              overlayShape: const RoundSliderOverlayShape(overlayRadius: 18),
              padding: EdgeInsets.zero,
            ),
            child: child!,
          ),
          child: Slider(
            min: 0,
            max: max <= 0 ? 1 : max,
            value: max <= 0 ? 0 : value,
            onChangeStart: max <= 0 ? null : (v) => setState(() => _dragValue = v),
            onChanged: max <= 0 ? null : (v) => setState(() => _dragValue = v),
            onChangeEnd: (v) {
              ref.read(audioHandlerProvider).seek(Duration(milliseconds: v.round()));
              setState(() => _dragValue = null);
            },
          ),
        ),
        const SizedBox(height: 10),
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text(formatDuration(shown), style: style),
            Text('-${formatDuration(total - shown)}', style: style),
          ],
        ),
      ],
    );
  }
}
