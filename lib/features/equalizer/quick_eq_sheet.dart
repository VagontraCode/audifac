import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:hugeicons/hugeicons.dart';

import '../../core/theme/app_colors.dart';
import '../../models/eq.dart';
import '../../models/eq_rules.dart';
import '../../models/song.dart';
import '../../providers/audio_info_providers.dart';
import '../../providers/eq_providers.dart';
import 'equalizer_screen.dart';
import '../../l10n/l10n.dart';
import '../../l10n/labels.dart';

/// How long a picked sound preset should stick.
enum ApplyScope {
  session('This session'),
  song('This song'),
  album('Album'),
  artist('Artist'),
  genre('Genre'),
  source('Source'),
  everything('All music');

  const ApplyScope(this.label);
  final String label;

  EqScope? get ruleScope => switch (this) {
        song => EqScope.song,
        album => EqScope.album,
        artist => EqScope.artist,
        genre => EqScope.genre,
        source => EqScope.source,
        _ => null,
      };
}

/// Pick a sound preset and how long it applies. Used by the player chip, the
/// song menu, the start-of-listening prompt and the equalizer screen.
class QuickEqSheet extends ConsumerStatefulWidget {
  const QuickEqSheet({super.key, this.song, this.initialScope = ApplyScope.session, this.prompt = false});

  final Song? song;
  final ApplyScope initialScope;

  /// Shown automatically when a new queue starts.
  final bool prompt;

  static Future<void> show(
    BuildContext context, {
    Song? song,
    ApplyScope initialScope = ApplyScope.session,
    bool prompt = false,
  }) =>
      showModalBottomSheet<void>(
        context: context,
        useRootNavigator: true,
        isScrollControlled: true,
        builder: (_) => QuickEqSheet(song: song, initialScope: initialScope, prompt: prompt),
      );

  @override
  ConsumerState<QuickEqSheet> createState() => _QuickEqSheetState();
}

class _QuickEqSheetState extends ConsumerState<QuickEqSheet> {
  late ApplyScope _scope = widget.initialScope;

  void _apply(EqPreset preset) {
    final song = widget.song;
    final genre = song == null ? null : ref.read(songAudioInfoProvider(song)).genre;
    final override = ref.read(eqQueueOverrideProvider.notifier);
    final settings = ref.read(eqSettingsProvider.notifier);
    if (!ref.read(eqSettingsProvider).enabled) settings.setEnabled(true);

    switch (_scope) {
      case ApplyScope.session:
        override.set(preset.id);
      case ApplyScope.everything:
        settings.setDefaultSound(preset.id);
        override.set(null);
      default:
        final scope = _scope.ruleScope!;
        final key = song == null ? null : EqRule.keyFor(scope, song, genre: genre);
        if (song != null && key != null) {
          ref.read(eqRulesProvider.notifier).put(EqRule(
                scope: scope,
                key: key,
                label: EqRule.labelFor(scope, song, genre: genre),
                presetId: preset.id,
              ));
        }
        override.set(null);
    }
    Navigator.of(context).pop();
  }

  @override
  Widget build(BuildContext context) {
    final presets = ref.watch(eqPresetsProvider).where((p) => p.kind == EqPresetKind.sound).toList();
    final mine = presets.where((p) => !p.builtIn).toList();
    final builtIn = presets.where((p) => p.builtIn).toList();
    final active = ref.watch(activeSoundProvider);
    final enabled = ref.watch(eqSettingsProvider.select((s) => s.enabled));
    final song = widget.song;
    final genre = song == null ? null : ref.watch(songAudioInfoProvider(song)).genre;
    final theme = Theme.of(context);
    final palette = context.palette;

    final scopes = [
      ApplyScope.session,
      if (song != null) ...[
        ApplyScope.song,
        ApplyScope.album,
        if (song.artist != Song.unknownArtist) ApplyScope.artist,
        if (genre != null && genre.isNotEmpty) ApplyScope.genre,
        ApplyScope.source,
      ],
      ApplyScope.everything,
    ];
    if (!scopes.contains(_scope)) _scope = ApplyScope.session;

    String scopeHint(ApplyScope s) => switch (s) {
          ApplyScope.album => song?.album ?? '',
          ApplyScope.artist => song?.artist ?? '',
          ApplyScope.genre => genre ?? '',
          ApplyScope.song => song?.title ?? '',
          _ => '',
        };

    Widget tile(EqPreset p) {
      final isActive = enabled && p.id == active.preset.id;
      return ListTile(
        contentPadding: const EdgeInsets.symmetric(horizontal: 24),
        leading: SizedBox(
          width: 56,
          height: 28,
          child: CustomPaint(painter: _MiniCurve(p.bands, isActive ? palette.ink : palette.inkMuted)),
        ),
        title: Text(context.l10n.presetName(p), style: TextStyle(fontWeight: isActive ? FontWeight.w800 : FontWeight.w600)),
        trailing: isActive ? HugeIcon(icon: HugeIcons.strokeRoundedTick02, color: palette.ink, size: 20) : null,
        onTap: () => _apply(p),
      );
    }

    return ConstrainedBox(
      constraints: BoxConstraints(maxHeight: MediaQuery.sizeOf(context).height * 0.85),
      child: SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(24, 0, 12, 4),
              child: Row(
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          widget.prompt ? context.l10n.chooseSound : context.l10n.soundPreset,
                          style: theme.textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w800),
                        ),
                        if (song != null)
                          Text(
                            '${song.title} · ${song.artist}',
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: theme.textTheme.bodyMedium,
                          ),
                      ],
                    ),
                  ),
                  IconButton(
                    tooltip: context.l10n.openEqualizer,
                    onPressed: () {
                      Navigator.of(context).pop();
                      EqualizerScreen.open(context);
                    },
                    icon: HugeIcon(icon: HugeIcons.strokeRoundedSettings02, color: palette.ink, size: 22),
                  ),
                ],
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(24, 10, 24, 4),
              child: Text(context.l10n.applyTo, style: theme.textTheme.labelLarge?.copyWith(fontWeight: FontWeight.w700)),
            ),
            SizedBox(
              height: 44,
              child: ListView(
                scrollDirection: Axis.horizontal,
                padding: const EdgeInsets.symmetric(horizontal: 20),
                children: [
                  for (final s in scopes)
                    Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 4),
                      child: ChoiceChip(
                        label: Text(applyScopeLabel(context.l10n, s)),
                        selected: _scope == s,
                        showCheckmark: false,
                        selectedColor: palette.ink,
                        labelStyle: TextStyle(
                          color: _scope == s ? palette.onInk : palette.ink,
                          fontWeight: FontWeight.w700,
                        ),
                        backgroundColor: palette.surface,
                        side: BorderSide(color: palette.line),
                        onSelected: (_) => setState(() => _scope = s),
                      ),
                    ),
                ],
              ),
            ),
            if (scopeHint(_scope).isNotEmpty)
              Padding(
                padding: const EdgeInsets.fromLTRB(24, 2, 24, 0),
                child: Text(
                  context.l10n.everyTimePlays(scopeHint(_scope)),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: theme.textTheme.bodySmall?.copyWith(color: palette.inkMuted),
                ),
              ),
            const SizedBox(height: 8),
            Flexible(
              child: ListView(
                shrinkWrap: true,
                padding: const EdgeInsets.only(bottom: 12),
                children: [
                  if (mine.isNotEmpty) ...[
                    _Header(context.l10n.yourPresets),
                    for (final p in mine) tile(p),
                  ],
                  _Header(context.l10n.builtIn),
                  for (final p in builtIn) tile(p),
                ],
              ),
            ),
            if (widget.prompt)
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
                child: TextButton(
                  onPressed: () {
                    ref.read(eqSettingsProvider.notifier).setAskOnPlay(false);
                    Navigator.of(context).pop();
                  },
                  child: Text("Don't ask when I start playing", style: TextStyle(color: palette.inkMuted)),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

class _Header extends StatelessWidget {
  const _Header(this.text);

  final String text;

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.fromLTRB(24, 12, 24, 4),
        child: Text(
          text.toUpperCase(),
          style: Theme.of(context).textTheme.labelSmall?.copyWith(
                letterSpacing: 1.4,
                fontWeight: FontWeight.w800,
                color: context.palette.inkMuted,
              ),
        ),
      );
}

/// Tiny response preview next to a preset name.
class _MiniCurve extends CustomPainter {
  _MiniCurve(this.bands, this.color);

  final List<EqBand> bands;
  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    final path = Path();
    final freqs = EqMath.logFrequencies(40);
    for (final (i, f) in freqs.indexed) {
      final db = EqMath.responseDb(bands, f).clamp(-12.0, 12.0);
      final p = Offset(size.width * i / (freqs.length - 1), size.height / 2 - db / 12 * (size.height / 2));
      i == 0 ? path.moveTo(p.dx, p.dy) : path.lineTo(p.dx, p.dy);
    }
    canvas.drawPath(
      path,
      Paint()
        ..color = color
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2
        ..strokeCap = StrokeCap.round,
    );
  }

  @override
  bool shouldRepaint(_MiniCurve old) => old.bands != bands || old.color != color;
}

/// Pick a device-correction preset for the current output.
class DevicePresetSheet extends ConsumerWidget {
  const DevicePresetSheet({super.key});

  static Future<void> show(BuildContext context) => showModalBottomSheet<void>(
        context: context,
        useRootNavigator: true,
        isScrollControlled: true,
        builder: (_) => const DevicePresetSheet(),
      );

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final presets = ref.watch(eqPresetsProvider).where((p) => p.kind == EqPresetKind.device).toList();
    final output = ref.watch(outputDeviceProvider);
    final active = ref.watch(activeDevicePresetProvider);
    final palette = context.palette;
    final theme = Theme.of(context);

    return ConstrainedBox(
      constraints: BoxConstraints(maxHeight: MediaQuery.sizeOf(context).height * 0.8),
      child: SafeArea(
        child: ListView(
          shrinkWrap: true,
          padding: const EdgeInsets.only(bottom: 12),
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(24, 0, 24, 4),
              child: Text(context.l10n.correctionFor(context.l10n.deviceName(output)),
                  style: theme.textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w800)),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(24, 0, 24, 8),
              child: Text(
                context.l10n.correctionHint,
                style: theme.textTheme.bodyMedium,
              ),
            ),
            for (final p in presets)
              ListTile(
                contentPadding: const EdgeInsets.symmetric(horizontal: 24),
                leading: SizedBox(
                  width: 56,
                  height: 28,
                  child: CustomPaint(painter: _MiniCurve(p.bands, p.id == active.id ? palette.ink : palette.inkMuted)),
                ),
                title: Text(context.l10n.presetName(p), style: TextStyle(fontWeight: p.id == active.id ? FontWeight.w800 : FontWeight.w600)),
                trailing: p.id == active.id ? HugeIcon(icon: HugeIcons.strokeRoundedTick02, color: palette.ink, size: 20) : null,
                onTap: () {
                  ref.read(eqSettingsProvider.notifier).assignDevice(output, p.id);
                  Navigator.of(context).pop();
                },
              ),
            ListTile(
              contentPadding: const EdgeInsets.symmetric(horizontal: 24),
              leading: HugeIcon(icon: HugeIcons.strokeRoundedAdd01, color: palette.ink, size: 22),
              title: Text(context.l10n.newCorrection, style: TextStyle(fontWeight: FontWeight.w700)),
              onTap: () async {
                Navigator.of(context).pop();
                await createPreset(context, ref, EqPresetKind.device, assign: true);
              },
            ),
          ],
        ),
      ),
    );
  }
}

String applyScopeLabel(AppLocalizations l10n, ApplyScope s) => switch (s) {
      ApplyScope.session => l10n.thisSession,
      ApplyScope.song => l10n.thisSong,
      ApplyScope.album => l10n.fieldAlbum,
      ApplyScope.artist => l10n.fieldArtist,
      ApplyScope.genre => l10n.fieldGenre,
      ApplyScope.source => l10n.fieldSource,
      ApplyScope.everything => l10n.allMusic,
    };
