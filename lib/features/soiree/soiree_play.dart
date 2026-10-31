import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../l10n/l10n.dart';
import '../../providers/player_providers.dart';
import '../../providers/soiree_plan_provider.dart';
import '../../providers/user_data_providers.dart';

/// Crossfade a soirée suggests: the floor shouldn't stop between songs.
const soireeCrossfadeSeconds = 6;

/// Plays the planned soirée in order (live controls on). Offers a crossfade
/// first when it's off.
Future<void> playSoiree(BuildContext context, WidgetRef ref) async {
  final s = ref.read(soireeProvider);
  if (s.plan.isEmpty) return;
  if (ref.read(settingsProvider).crossfadeSeconds == 0) {
    final on = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(context.l10n.soireeCrossfadeTitle),
        content: Text(context.l10n.soireeCrossfadeBody(soireeCrossfadeSeconds)),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: Text(context.l10n.keepItOff)),
          FilledButton(onPressed: () => Navigator.pop(context, true), child: Text(context.l10n.turnOnCrossfade(soireeCrossfadeSeconds))),
        ],
      ),
    );
    if (on == null) return; // Dismissed: not now.
    if (on) ref.read(settingsProvider.notifier).setCrossfade(soireeCrossfadeSeconds);
  }
  ref.read(soireeProvider.notifier).setLive(true);
  // In the planned order: no shuffle, whatever the album settings.
  await ref.read(audioHandlerProvider).playSongs([for (final slot in s.plan) slot.song], shuffle: false);
}
