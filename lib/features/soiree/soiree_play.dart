import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../providers/player_providers.dart';
import '../../providers/soiree_plan_provider.dart';

/// Plays the planned soirée as the queue (live controls on).
Future<void> playSoiree(BuildContext context, WidgetRef ref) async {
  final s = ref.read(soireeProvider);
  if (s.plan.isEmpty) return;
  ref.read(soireeProvider.notifier).setLive(true);
  await ref.read(audioHandlerProvider).playSongs([for (final slot in s.plan) slot.song]);
}
