import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:hugeicons/hugeicons.dart';

import '../core/format.dart';
import '../l10n/l10n.dart';
import '../models/ab_loop.dart';
import '../providers/player_providers.dart';
import 'spoken_widgets.dart';

/// A–B repeat: first tap marks A, second marks B and starts looping, third
/// stops. The marks are shown on the seek bar.
class AbRepeatChip extends ConsumerWidget {
  const AbRepeatChip({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final loop = ref.watch(abLoopProvider).value ?? AbLoop.off;
    final songId = ref.watch(currentSongIdProvider);
    final l10n = context.l10n;
    final (label, tooltip) = switch (loop) {
      AbLoop(isOff: true) => ('A–B', l10n.abRepeatSetA),
      AbLoop(waitingForB: true) => ('A…', l10n.abRepeatSetB),
      _ => ('A–B', l10n.abRepeatOn(formatDuration(loop.a!), formatDuration(loop.b!))),
    };
    return PlayerChip(
      icon: HugeIcons.strokeRoundedRepeat,
      label: label,
      tooltip: tooltip,
      active: !loop.isOff,
      onTap: songId == null
          ? () {}
          : () {
              HapticFeedback.selectionClick();
              final handler = ref.read(audioHandlerProvider);
              handler.setAbLoop(loop.tap(songId, handler.position));
            },
    );
  }
}
