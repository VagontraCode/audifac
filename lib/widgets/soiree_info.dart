import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../core/theme/app_colors.dart';
import '../l10n/l10n.dart';
import '../models/song.dart';
import '../models/song_features.dart';
import '../providers/soiree_providers.dart';

/// Song info → Soirée: tempo, energy, danceability, groove, and the owner's
/// corrections (tap tempo, more / less danceable).
class SoireeInfoSection extends ConsumerWidget {
  const SoireeInfoSection({super.key, required this.song});

  final Song song;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = context.l10n;
    final theme = Theme.of(context);
    final palette = context.palette;
    final f = ref.watch(soireeFeaturesProvider.select((m) => m[song.key]));
    final measured = ref.watch(songFeaturesProvider.select((m) => m[song.key]));
    final o = ref.watch(featureOverridesProvider.select((m) => m[song.key])) ?? const FeatureOverride();
    final notifier = ref.read(featureOverridesProvider.notifier);
    final enabled = ref.watch(rhythmEnabledProvider);

    Widget row(String label, String value) => Padding(
          padding: const EdgeInsets.symmetric(vertical: 5),
          child: Row(
            children: [
              SizedBox(width: 112, child: Text(label, style: theme.textTheme.bodyMedium)),
              Expanded(
                child: Text(value, style: theme.textTheme.bodyMedium?.copyWith(color: palette.ink, fontWeight: FontWeight.w600)),
              ),
            ],
          ),
        );

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.only(top: 22, bottom: 6),
          child: Text(
            l10n.soireeSection.toUpperCase(),
            style: theme.textTheme.labelSmall?.copyWith(letterSpacing: 1.4, fontWeight: FontWeight.w800, color: palette.inkMuted),
          ),
        ),
        if (f == null)
          Text(
            measured?.failed ?? false ? l10n.soireeCantAnalyse : (enabled ? l10n.soireeNotYet : l10n.soireeAnalysisOff),
            style: theme.textTheme.bodySmall?.copyWith(color: palette.inkMuted),
          )
        else ...[
          row(l10n.tempo, '${f.bpm.round()} BPM${o.bpm != null ? ' · ${l10n.setByYou}' : ''}'),
          row(l10n.danceability, [
            '${f.danceability} / 100',
            if (o.nudge != 0) l10n.setByYou,
            if (o.learned != 0) l10n.learnedAtSoirees,
          ].join(' · ')),
          row(l10n.energy, '${f.energy} / 100'),
          row(l10n.groove, '${f.groove} / 100'),
          const SizedBox(height: 6),
          Wrap(
            spacing: 8,
            runSpacing: 4,
            children: [
              OutlinedButton(
                onPressed: () async {
                  final bpm = await TapTempoDialog.show(context, f.bpm);
                  if (bpm != null) notifier.update(song, (x) => x.copyWith(bpm: () => bpm));
                },
                child: Text(l10n.tapTempo),
              ),
              OutlinedButton(
                onPressed: () => notifier.update(song, (x) => x.copyWith(nudge: x.nudge - 15)),
                child: Text(l10n.lessDanceable),
              ),
              OutlinedButton(
                onPressed: () => notifier.update(song, (x) => x.copyWith(nudge: x.nudge + 15)),
                child: Text(l10n.moreDanceable),
              ),
              if (!o.isEmpty)
                TextButton(
                  onPressed: () => notifier.update(song, (x) => x.copyWith(bpm: () => null, nudge: 0, learned: 0)),
                  child: Text(l10n.resetMeasured),
                ),
            ],
          ),
        ],
      ],
    );
  }
}

/// Tap along with the beat; ×½ / ×2 fix a half / double-time reading.
class TapTempoDialog extends StatefulWidget {
  const TapTempoDialog({super.key, required this.initial});

  final double initial;

  static Future<double?> show(BuildContext context, double initial) =>
      showDialog<double>(context: context, builder: (_) => TapTempoDialog(initial: initial));

  @override
  State<TapTempoDialog> createState() => _TapTempoDialogState();
}

class _TapTempoDialogState extends State<TapTempoDialog> {
  final _taps = <int>[];
  late double _bpm = widget.initial;

  void _tap() {
    HapticFeedback.lightImpact();
    _taps.add(DateTime.now().millisecondsSinceEpoch);
    final t = tapTempo(_taps);
    if (t != null) setState(() => _bpm = t);
  }

  void _scale(double k) => setState(() => _bpm = (_bpm * k).clamp(40, 240).toDouble());

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final palette = context.palette;
    return AlertDialog(
      title: Text(l10n.tapTempo),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(l10n.tapTempoHint, style: Theme.of(context).textTheme.bodySmall?.copyWith(color: palette.inkMuted)),
          const SizedBox(height: 16),
          Text('${_bpm.round()} BPM', style: Theme.of(context).textTheme.headlineMedium?.copyWith(fontWeight: FontWeight.w800)),
          const SizedBox(height: 16),
          SizedBox.square(
            dimension: 120,
            child: FilledButton(
              style: FilledButton.styleFrom(shape: const CircleBorder()),
              onPressed: _tap,
              child: Text(l10n.tap, style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w800)),
            ),
          ),
          const SizedBox(height: 12),
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              TextButton(onPressed: () => _scale(0.5), child: const Text('×½')),
              TextButton(onPressed: () => _scale(2), child: const Text('×2')),
            ],
          ),
        ],
      ),
      actions: [
        TextButton(onPressed: () => Navigator.pop(context), child: Text(l10n.cancel)),
        FilledButton(onPressed: () => Navigator.pop(context, _bpm), child: Text(l10n.save)),
      ],
    );
  }
}
