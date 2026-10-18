import 'package:flutter/material.dart';
import 'dart:math' as math;

class AnimatedEqualizer extends StatelessWidget {
  final bool isPlaying;
  final AnimationController controller;

  const AnimatedEqualizer({
    super.key,
    required this.isPlaying,
    required this.controller,
  });

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Row(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.end,
        children: List.generate(25, (index) {
          return AnimatedBuilder(
            animation: controller,
            builder: (context, child) {
              final double animationValue = math.sin(
                (controller.value * 2 * math.pi) + (index * 0.3),
              );

              final double height = isPlaying
                  ? (20 + (animationValue * 15)).abs()
                  : 4.0;

              return Container(
                width: 3,
                height: height,
                margin: EdgeInsets.symmetric(horizontal: 1),
                decoration: BoxDecoration(
                  color: isPlaying
                      ? Colors.black87.withValues(
                          alpha: 0.7 + (animationValue * 0.3).abs(),
                        )
                      : Colors.black26,
                  borderRadius: BorderRadius.circular(1.5),
                ),
              );
            },
          );
        }),
      ),
    );
  }
}
