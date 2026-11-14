import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:hugeicons/hugeicons.dart';

import '../../core/theme/app_colors.dart';
import '../../l10n/l10n.dart';
import '../../models/abx.dart';
import '../../providers/eq_providers.dart';
import '../../providers/player_providers.dart';

enum _Hear { a, b, x }

/// Blind ABX test of the equalizer: can you really tell your sound (B) from
/// the original (A)? Levels are matched so loudness doesn't give it away.
class AbxScreen extends ConsumerStatefulWidget {
  const AbxScreen({super.key});

  static Future<void> open(BuildContext context) =>
      Navigator.of(context).push(MaterialPageRoute<void>(builder: (_) => const AbxScreen()));

  @override
  ConsumerState<AbxScreen> createState() => _AbxScreenState();
}

class _AbxScreenState extends ConsumerState<AbxScreen> {
  var _test = AbxTest();
  var _hear = _Hear.x;
  late final _dsp = ref.read(dspChannelProvider);
  late final _handler = ref.read(audioHandlerProvider);
  late final double _volumeBefore = _handler.volume;

  @override
  void initState() {
    super.initState();
    _volumeBefore; // Remember it before the test changes it.
    WidgetsBinding.instance.addPostFrameCallback((_) => _apply());
  }

  @override
  void dispose() {
    _dsp.setBypass(false);
    _handler.setVolume(_volumeBefore);
    super.dispose();
  }

  /// Plays what's selected: B = your sound, A = the original, level-matched.
  void _apply() {
    if (!mounted) return;
    final isB = _hear == _Hear.b || (_hear == _Hear.x && _test.xIsB);
    final volumes = levelMatchedVolumes(ref.read(eqLevelDbProvider));
    _dsp.setBypass(!isB);
    _handler.setVolume((isB ? volumes.b : volumes.a) * _volumeBefore);
  }

  void _listen(_Hear hear) {
    HapticFeedback.selectionClick();
    setState(() => _hear = hear);
    _apply();
  }

  void _answer(bool saysB) {
    HapticFeedback.lightImpact();
    setState(() {
      _test.answer(saysB: saysB);
      _hear = _Hear.x; // Next trial: start on the new X.
    });
    _apply();
  }

  void _restart() {
    setState(() {
      _test = AbxTest();
      _hear = _Hear.x;
    });
    _apply();
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final palette = context.palette;
    final theme = Theme.of(context);
    final eqOn = ref.watch(eqSettingsProvider.select((s) => s.enabled));
    final playing = ref.watch(isPlayingProvider);
    // Re-match if the sound changes during the test.
    ref.listen(eqLevelDbProvider, (_, _) => _apply());

    Widget listenButton(_Hear hear, String label) {
      final selected = _hear == hear;
      return Expanded(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 4),
          child: SizedBox(
            height: 72,
            child: selected
                ? FilledButton(onPressed: () => _listen(hear), child: Text(label, style: const TextStyle(fontSize: 26, fontWeight: FontWeight.w800)))
                : OutlinedButton(onPressed: () => _listen(hear), child: Text(label, style: const TextStyle(fontSize: 26, fontWeight: FontWeight.w800))),
          ),
        ),
      );
    }

    final body = !eqOn
        ? Center(child: Text(l10n.abxNeedsEq, textAlign: TextAlign.center, style: theme.textTheme.bodyLarge))
        : _test.finished
            ? _Result(test: _test, onRestart: _restart)
            : Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Text(l10n.abxHowTo, style: theme.textTheme.bodyMedium),
                  const SizedBox(height: 8),
                  Text(l10n.abxLevelNote, style: theme.textTheme.bodySmall?.copyWith(color: palette.inkMuted)),
                  const SizedBox(height: 28),
                  Text(
                    l10n.abxTrial(_test.done + 1, _test.trials),
                    textAlign: TextAlign.center,
                    style: theme.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w800),
                  ),
                  const SizedBox(height: 12),
                  LinearProgressIndicator(
                    value: _test.done / _test.trials,
                    minHeight: 4,
                    borderRadius: BorderRadius.circular(2),
                    color: palette.ink,
                    // Light track: round 1 must look empty, not complete.
                    backgroundColor: palette.line,
                  ),
                  const SizedBox(height: 24),
                  Text(l10n.abxListen, style: theme.textTheme.labelLarge?.copyWith(color: palette.inkMuted)),
                  const SizedBox(height: 8),
                  Row(children: [listenButton(_Hear.a, 'A'), listenButton(_Hear.x, 'X'), listenButton(_Hear.b, 'B')]),
                  const SizedBox(height: 6),
                  Row(
                    children: [
                      Expanded(child: Text(l10n.abxAIsOriginal, textAlign: TextAlign.center, style: theme.textTheme.bodySmall)),
                      const Expanded(child: SizedBox()),
                      Expanded(child: Text(l10n.abxBIsYourSound, textAlign: TextAlign.center, style: theme.textTheme.bodySmall)),
                    ],
                  ),
                  const SizedBox(height: 28),
                  Text(l10n.abxQuestion, style: theme.textTheme.labelLarge?.copyWith(color: palette.inkMuted)),
                  const SizedBox(height: 8),
                  Row(
                    children: [
                      Expanded(child: OutlinedButton(onPressed: () => _answer(false), child: Text(l10n.abxXIsA))),
                      const SizedBox(width: 12),
                      Expanded(child: OutlinedButton(onPressed: () => _answer(true), child: Text(l10n.abxXIsB))),
                    ],
                  ),
                  const Spacer(),
                  if (!playing)
                    FilledButton.icon(
                      onPressed: _handler.play,
                      icon: HugeIcon(icon: HugeIcons.strokeRoundedPlay, color: palette.onInk, size: 20),
                      label: Text(l10n.abxPlayMusic),
                    ),
                ],
              );

    return Scaffold(
      appBar: AppBar(title: Text(l10n.abxTitle)),
      body: SafeArea(child: Padding(padding: const EdgeInsets.fromLTRB(20, 8, 20, 20), child: body)),
    );
  }
}

class _Result extends StatelessWidget {
  const _Result({required this.test, required this.onRestart});

  final AbxTest test;
  final VoidCallback onRestart;

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final theme = Theme.of(context);
    final palette = context.palette;
    final percent = (test.pValue * 100).toStringAsFixed(test.pValue < 0.01 ? 2 : 1);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const SizedBox(height: 24),
        Text(
          '${test.correct} / ${test.trials}',
          textAlign: TextAlign.center,
          style: theme.textTheme.displayMedium?.copyWith(fontWeight: FontWeight.w800),
        ),
        const SizedBox(height: 8),
        Text(
          test.heard ? l10n.abxHeard : l10n.abxNotHeard,
          textAlign: TextAlign.center,
          style: theme.textTheme.titleMedium?.copyWith(
            fontWeight: FontWeight.w800,
            color: test.heard ? palette.lossless : palette.ink,
          ),
        ),
        const SizedBox(height: 12),
        Text(l10n.abxLuck(percent), textAlign: TextAlign.center, style: theme.textTheme.bodyMedium),
        const SizedBox(height: 32),
        FilledButton(onPressed: onRestart, child: Text(l10n.abxAgain)),
      ],
    );
  }
}
