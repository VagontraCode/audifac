import 'dart:async';
import 'dart:io';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:hugeicons/hugeicons.dart';

import '../../core/format.dart';
import '../../core/theme/app_colors.dart';
import '../../models/eq.dart';
import '../../providers/eq_providers.dart';
import '../../providers/library_providers.dart';
import '../../providers/player_providers.dart';
import '../../widgets/eq_curve.dart';
import 'eq_rules_screen.dart';
import 'quick_eq_sheet.dart';
import '../../l10n/l10n.dart';
import '../../l10n/labels.dart';

/// Creates a preset (blank, AutoEQ file, AutoEQ text, or a copy of the
/// current one) and makes it active so it can be edited right away.
Future<EqPreset?> createPreset(BuildContext context, WidgetRef ref, EqPresetKind kind, {bool assign = true}) async {
  final palette = context.palette;
  final choice = await showModalBottomSheet<String>(
    context: context,
    useRootNavigator: true,
    builder: (context) => SafeArea(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          ListTile(
            leading: HugeIcon(icon: HugeIcons.strokeRoundedSlidersHorizontal, color: palette.ink, size: 22),
            title: Text(context.l10n.blankGraphic),
            onTap: () => Navigator.pop(context, 'graphic'),
          ),
          ListTile(
            leading: HugeIcon(icon: HugeIcons.strokeRoundedChartLineData01, color: palette.ink, size: 22),
            title: Text(context.l10n.blankParametric),
            onTap: () => Navigator.pop(context, 'parametric'),
          ),
          ListTile(
            leading: HugeIcon(icon: HugeIcons.strokeRoundedFile01, color: palette.ink, size: 22),
            title: Text(context.l10n.importAutoEqFile),
            onTap: () => Navigator.pop(context, 'file'),
          ),
          ListTile(
            leading: HugeIcon(icon: HugeIcons.strokeRoundedCopy01, color: palette.ink, size: 22),
            title: Text(context.l10n.pasteAutoEq),
            onTap: () => Navigator.pop(context, 'paste'),
          ),
        ],
      ),
    ),
  );
  if (choice == null || !context.mounted) return null;

  final id = EqPresetsNotifier.newId();
  final messenger = ScaffoldMessenger.of(context);
  final l10n = context.l10n;
  EqPreset? preset;
  String suggested = kind == EqPresetKind.device ? l10n.myHeadphones : l10n.mySound;

  switch (choice) {
    case 'graphic':
      preset = EqPreset.flatGraphic(id: id, name: suggested, kind: kind);
    case 'parametric':
      preset = EqPreset(id: id, name: suggested, kind: kind, bands: const [EqBand(frequency: 1000, q: 1)]);
    case 'file':
    case 'paste':
      String? text;
      if (choice == 'file') {
        final doc = await ref.read(mediaLibraryProvider).openTextDocument();
        text = doc?.text;
        if (doc?.name != null) suggested = doc!.name!.replaceAll(RegExp(r'\s*ParametricEQ\s*', caseSensitive: false), '').trim();
      } else {
        text = (await Clipboard.getData(Clipboard.kTextPlain))?.text;
      }
      if (text == null) return null;
      preset = EqPreset.fromAutoEq(text, id: id, name: suggested.isEmpty ? l10n.imported : suggested, kind: kind);
      if (preset == null) {
        messenger.showSnackBar(SnackBar(content: Text(l10n.noAutoEqLines)));
        return null;
      }
  }
  if (preset == null || !context.mounted) return null;

  final name = await askPresetName(context, title: l10n.nameThisPreset, initial: preset.name);
  if (name == null) return null;
  preset = preset.copyWith(name: name);
  await ref.read(eqPresetsProvider.notifier).save(preset);
  if (assign) _activate(ref, preset);
  if (!ref.read(eqSettingsProvider).enabled) ref.read(eqSettingsProvider.notifier).setEnabled(true);
  return preset;
}

void _activate(WidgetRef ref, EqPreset preset) {
  if (preset.kind == EqPresetKind.device) {
    ref.read(eqSettingsProvider.notifier).assignDevice(ref.read(outputDeviceProvider), preset.id);
  } else {
    ref.read(eqQueueOverrideProvider.notifier).set(preset.id);
  }
}

Future<String?> askPresetName(BuildContext context, {required String title, String initial = ''}) {
  final controller = TextEditingController(text: initial);
  return showDialog<String>(
    context: context,
    builder: (context) => AlertDialog(
      title: Text(title),
      content: TextField(
        controller: controller,
        autofocus: true,
        textCapitalization: TextCapitalization.sentences,
        onSubmitted: (v) => Navigator.pop(context, v.trim().isEmpty ? null : v.trim()),
        decoration: InputDecoration(hintText: context.l10n.presetNameHint, fillColor: context.palette.background),
      ),
      actions: [
        TextButton(onPressed: () => Navigator.pop(context), child: Text(context.l10n.cancel)),
        FilledButton(
          onPressed: () => Navigator.pop(context, controller.text.trim().isEmpty ? null : controller.text.trim()),
          child: Text(context.l10n.save),
        ),
      ],
    ),
  );
}

class EqualizerScreen extends ConsumerStatefulWidget {
  const EqualizerScreen({super.key});

  static Future<void> open(BuildContext context) => Navigator.of(context, rootNavigator: true).push(
        MaterialPageRoute<void>(builder: (_) => const EqualizerScreen()),
      );

  @override
  ConsumerState<EqualizerScreen> createState() => _EqualizerScreenState();
}

class _EqualizerScreenState extends ConsumerState<EqualizerScreen> {
  EqPresetKind _layer = EqPresetKind.sound;
  int? _selected;

  Timer? _saveTimer;
  EqPreset? _unsaved;
  late final EqDraftNotifier _draft = ref.read(eqDraftProvider.notifier);
  late final EqPresetsNotifier _presets = ref.read(eqPresetsProvider.notifier);
  late final _dsp = ref.read(dspChannelProvider);

  @override
  void dispose() {
    _flush();
    _draft.set(null);
    _dsp.setBypass(false);
    super.dispose();
  }

  void _flush() {
    _saveTimer?.cancel();
    final pending = _unsaved;
    _unsaved = null;
    if (pending != null) _presets.save(pending);
  }

  /// Live edit: heard immediately, saved shortly after.
  void _edit(EqPreset updated) {
    _draft.set(updated);
    _unsaved = updated;
    _saveTimer?.cancel();
    _saveTimer = Timer(const Duration(milliseconds: 400), _flush);
  }

  Future<void> _loadIr(EqDevice output) async {
    final messenger = ScaffoldMessenger.of(context);
    final l10n = context.l10n;
    try {
      final ir = await ref.read(mediaLibraryProvider).importImpulseResponse();
      if (ir == null) return;
      final settings = ref.read(eqSettingsProvider.notifier);
      final old = ref.read(eqSettingsProvider).devices[output.key]?.irPath;
      settings.setImpulseResponse(output, ir.path, ir.name);
      if (!ref.read(eqSettingsProvider).enabled) settings.setEnabled(true);
      _deleteIr(old);
      messenger.showSnackBar(SnackBar(content: Text(l10n.irLoaded(ir.channels, ir.name, ir.seconds.toStringAsFixed(2)))));
    } on PlatformException {
      messenger.showSnackBar(SnackBar(content: Text(l10n.irUnusable)));
    }
  }

  void _removeIr(EqDevice output) {
    final old = ref.read(eqSettingsProvider).devices[output.key]?.irPath;
    ref.read(eqSettingsProvider.notifier).setImpulseResponse(output, null, null);
    _deleteIr(old);
  }

  /// The app's own copy (never the user's original file).
  void _deleteIr(String? path) {
    if (path == null) return;
    File(path).delete().ignore();
  }

  void _setTone(Tone tone) {
    if (!ref.read(eqSettingsProvider).enabled) ref.read(eqSettingsProvider.notifier).setEnabled(true);
    ref.read(eqSettingsProvider.notifier).setTone(tone);
  }

  void _setStereo(Stereo stereo) {
    if (!ref.read(eqSettingsProvider).enabled) ref.read(eqSettingsProvider.notifier).setEnabled(true);
    ref.read(eqSettingsProvider.notifier).setStereo(stereo);
  }

  /// Slider value in dB, to 0.5 dB, snapping to 0 near the middle.
  static double _snapDb(double v) => v.abs() < 0.3 ? 0 : (v * 2).round() / 2;

  void _switchLayer(EqPresetKind layer) {
    if (layer == _layer) return;
    _flush();
    _draft.set(null);
    setState(() {
      _layer = layer;
      _selected = null;
    });
  }

  Future<void> _duplicateAndEdit(EqPreset source) async {
    final name = await askPresetName(context, title: context.l10n.duplicatePreset, initial: context.l10n.myVersion(context.l10n.presetName(source)));
    if (name == null) return;
    final copy = source.duplicate(id: EqPresetsNotifier.newId(), name: name);
    await _presets.save(copy);
    _activate(ref, copy);
  }

  Future<void> _presetMenu(String action, EqPreset preset) async {
    final messenger = ScaffoldMessenger.of(context);
    final l10n = context.l10n;
    switch (action) {
      case 'rename':
        final name = await askPresetName(context, title: l10n.renamePreset, initial: preset.name);
        if (name != null) _edit(preset.copyWith(name: name));
      case 'duplicate':
        await _duplicateAndEdit(preset);
      case 'export':
        await Clipboard.setData(ClipboardData(text: preset.toAutoEq()));
        messenger.showSnackBar(SnackBar(content: Text(l10n.copiedAutoEq)));
      case 'default':
        ref.read(eqSettingsProvider.notifier).setDefaultSound(preset.id);
        messenger.showSnackBar(SnackBar(content: Text(l10n.nowDefault(l10n.presetName(preset)))));
      case 'delete':
        final confirmed = await showDialog<bool>(
          context: context,
          builder: (context) => AlertDialog(
            title: Text(l10n.deletePresetTitle),
            content: Text(l10n.deletePresetBody(preset.name)),
            actions: [
              TextButton(onPressed: () => Navigator.pop(context, false), child: Text(l10n.cancel)),
              FilledButton(
                style: FilledButton.styleFrom(backgroundColor: const Color(0xFFD70015)),
                onPressed: () => Navigator.pop(context, true),
                child: Text(l10n.delete),
              ),
            ],
          ),
        );
        if (confirmed != true) return;
        _flush();
        _draft.set(null);
        await _presets.delete(preset.id);
    }
  }

  @override
  Widget build(BuildContext context) {
    final settings = ref.watch(eqSettingsProvider);
    final device = ref.watch(activeDevicePresetProvider);
    final sound = ref.watch(activeSoundProvider);
    final output = ref.watch(outputDeviceProvider);
    final song = ref.watch(currentSongProvider);
    final palette = context.palette;
    final theme = Theme.of(context);

    final editing = _layer == EqPresetKind.device ? device : sound.preset;
    final combined = [...device.bands, ...sound.preset.bands, ...settings.tone.bands];
    final totalPreamp = device.preampDb + sound.preset.preampDb;
    final headroom = -EqMath.maxBoostDb(combined);
    final effectivePreamp = settings.autoPreamp ? math.min(totalPreamp, headroom) : totalPreamp;
    final clipping = !settings.autoPreamp && totalPreamp + EqMath.maxBoostDb(combined) > 0.05;

    Widget section(String text) => Padding(
          padding: const EdgeInsets.fromLTRB(20, 24, 20, 8),
          child: Text(
            text.toUpperCase(),
            style: theme.textTheme.labelSmall?.copyWith(letterSpacing: 1.4, fontWeight: FontWeight.w800, color: palette.inkMuted),
          ),
        );

    return Scaffold(
      appBar: AppBar(
        title: Text(context.l10n.equalizer, style: TextStyle(fontWeight: FontWeight.w800)),
        leading: IconButton(
          tooltip: context.l10n.back,
          onPressed: () => Navigator.of(context).pop(),
          icon: HugeIcon(icon: HugeIcons.strokeRoundedArrowLeft01, color: palette.ink, size: 26),
        ),
        actions: [
          Padding(
            padding: const EdgeInsets.only(right: 12),
            child: Switch(
              value: settings.enabled,
              activeThumbColor: palette.onInk,
              activeTrackColor: palette.ink,
              onChanged: ref.read(eqSettingsProvider.notifier).setEnabled,
            ),
          ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.only(bottom: 32),
        children: [
          if (!settings.enabled)
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 0, 20, 8),
              child: Text(
                context.l10n.eqOffHint,
                style: theme.textTheme.bodyMedium,
              ),
            ),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: Row(
              children: [
                Expanded(
                  child: _LayerCard(
                    title: context.l10n.deviceLayer(context.l10n.deviceName(output)),
                    preset: context.l10n.presetName(device),
                    reason: context.l10n.autoForOutput,
                    icon: switch (output.kind) {
                      'bluetooth' => HugeIcons.strokeRoundedBluetooth,
                      'wired' || 'usb' => HugeIcons.strokeRoundedHeadphones,
                      _ => HugeIcons.strokeRoundedSmartPhone01,
                    },
                    selected: _layer == EqPresetKind.device,
                    onTap: () => _switchLayer(EqPresetKind.device),
                    onChange: () => DevicePresetSheet.show(context),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: _LayerCard(
                    title: context.l10n.sound,
                    preset: context.l10n.presetName(sound.preset),
                    reason: context.l10n.fromReason(context.l10n.eqReason(sound.reason)),
                    icon: HugeIcons.strokeRoundedMusicNote01,
                    selected: _layer == EqPresetKind.sound,
                    onTap: () => _switchLayer(EqPresetKind.sound),
                    onChange: () => QuickEqSheet.show(context, song: song, initialScope: ApplyScope.everything),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 16),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12),
            child: EqCurve(
              bands: editing.bands,
              background: combined,
              selected: _selected,
              onSelect: editing.builtIn || editing.graphic ? null : (i) => setState(() => _selected = i),
              onBandChanged: editing.builtIn
                  ? null
                  : (i, b) => _edit(editing.copyWith(
                        // Graphic bands keep their fixed frequency and width.
                        bands: [...editing.bands]
                          ..[i] = editing.graphic ? b.copyWith(frequency: editing.bands[i].frequency, q: editing.bands[i].q) : b,
                      )),
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 6, 20, 0),
            child: Text(
              _layer == EqPresetKind.device ? context.l10n.curveLegendDevice : context.l10n.curveLegendSound,
              style: theme.textTheme.bodySmall?.copyWith(color: palette.inkMuted),
            ),
          ),
          // A/B
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 14, 20, 0),
            child: _HoldToCompare(onChanged: (held) => _dsp.setBypass(held)),
          ),

          section(editing.kind == EqPresetKind.device ? context.l10n.deviceCorrection : context.l10n.soundPreset),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 20),
            child: Row(
              children: [
                Expanded(
                  child: Text(context.l10n.presetName(editing), style: theme.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w800)),
                ),
                if (!editing.builtIn)
                  SegmentedButton<bool>(
                    showSelectedIcon: false,
                    style: SegmentedButton.styleFrom(
                      selectedBackgroundColor: palette.ink,
                      selectedForegroundColor: palette.onInk,
                      visualDensity: VisualDensity.compact,
                    ),
                    segments: [
                      ButtonSegment(value: true, label: Text(context.l10n.graphic)),
                      ButtonSegment(value: false, label: Text(context.l10n.parametric)),
                    ],
                    selected: {editing.graphic},
                    onSelectionChanged: (s) => _edit(s.first ? _toGraphic(editing) : editing.copyWith(graphic: false)),
                  ),
                PopupMenuButton<String>(
                  tooltip: context.l10n.presetOptions,
                  icon: HugeIcon(icon: HugeIcons.strokeRoundedMoreVertical, color: palette.ink, size: 22),
                  onSelected: (a) => _presetMenu(a, editing),
                  itemBuilder: (_) => [
                    if (!editing.builtIn) PopupMenuItem(value: 'rename', child: Text(context.l10n.rename)),
                    PopupMenuItem(value: 'duplicate', child: Text(context.l10n.duplicate)),
                    PopupMenuItem(value: 'export', child: Text(context.l10n.copyAsAutoEq)),
                    if (editing.kind == EqPresetKind.sound)
                      PopupMenuItem(value: 'default', child: Text(context.l10n.useForAllMusic)),
                    if (!editing.builtIn) PopupMenuItem(value: 'delete', child: Text(context.l10n.delete)),
                  ],
                ),
              ],
            ),
          ),
          if (editing.builtIn)
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 8, 20, 0),
              child: Row(
                children: [
                  Expanded(child: Text(context.l10n.builtInReadOnly, style: theme.textTheme.bodyMedium)),
                  FilledButton.icon(
                    onPressed: () => _duplicateAndEdit(editing),
                    icon: HugeIcon(icon: HugeIcons.strokeRoundedEdit02, color: palette.onInk, size: 16),
                    label: Text(context.l10n.duplicateToEdit),
                  ),
                ],
              ),
            )
          else if (editing.graphic)
            _GraphicEditor(preset: editing, onChanged: _edit)
          else
            _ParametricEditor(
              preset: editing,
              selected: _selected,
              onSelect: (i) => setState(() => _selected = i),
              onChanged: _edit,
            ),

          section(context.l10n.gain),
          if (!editing.builtIn)
            _SliderRow(
              label: context.l10n.preamp,
              value: editing.preampDb,
              min: -24,
              max: 6,
              display: formatDb(editing.preampDb),
              onChanged: (v) => _edit(editing.copyWith(preampDb: (v * 10).round() / 10)),
            ),
          SwitchListTile(
            contentPadding: const EdgeInsets.symmetric(horizontal: 20),
            activeThumbColor: palette.onInk,
            activeTrackColor: palette.ink,
            title: Text(context.l10n.autoHeadroom, style: TextStyle(fontWeight: FontWeight.w600)),
            subtitle: Text(
              context.l10n.autoHeadroomHint(formatDb(effectivePreamp)),
            ),
            value: settings.autoPreamp,
            onChanged: ref.read(eqSettingsProvider.notifier).setAutoPreamp,
          ),
          SwitchListTile(
            contentPadding: const EdgeInsets.symmetric(horizontal: 20),
            activeThumbColor: palette.onInk,
            activeTrackColor: palette.ink,
            title: Text(context.l10n.linearPhase, style: TextStyle(fontWeight: FontWeight.w600)),
            subtitle: Text(context.l10n.linearPhaseHint),
            value: settings.linearPhase,
            onChanged: ref.read(eqSettingsProvider.notifier).setLinearPhase,
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 8, 20, 0),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(context.l10n.compressor, style: TextStyle(fontWeight: FontWeight.w600)),
                const SizedBox(height: 8),
                SizedBox(
                  width: double.infinity,
                  child: SegmentedButton<int>(
                    showSelectedIcon: false,
                    segments: [
                      ButtonSegment(value: 0, label: Text(context.l10n.off)),
                      ButtonSegment(value: 1, label: Text(context.l10n.compressorLight)),
                      ButtonSegment(value: 2, label: Text(context.l10n.compressorMedium)),
                      ButtonSegment(value: 3, label: Text(context.l10n.compressorStrong)),
                    ],
                    selected: {settings.compressor},
                    onSelectionChanged: (s) {
                      final notifier = ref.read(eqSettingsProvider.notifier);
                      if (s.first > 0 && !settings.enabled) notifier.setEnabled(true);
                      notifier.setCompressor(s.first);
                    },
                  ),
                ),
                const SizedBox(height: 4),
                Text(context.l10n.compressorHint, style: theme.textTheme.bodySmall?.copyWith(color: palette.inkMuted)),
              ],
            ),
          ),
          if (clipping)
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 0, 20, 8),
              child: Text(
                context.l10n.boostsExceed,
                style: theme.textTheme.bodySmall?.copyWith(color: palette.hiRes, fontWeight: FontWeight.w700),
              ),
            ),

          if (editing.kind == EqPresetKind.device && !editing.builtIn) ...[
            section(context.l10n.output),
            _SliderRow(
              label: context.l10n.crossfeed,
              value: editing.crossfeed,
              min: 0,
              max: 1,
              display: editing.crossfeed == 0 ? context.l10n.off : '${(editing.crossfeed * 100).round()} %',
              onChanged: (v) => _edit(editing.copyWith(crossfeed: v < 0.03 ? 0 : v)),
            ),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 20),
              child: Text(
                context.l10n.crossfeedHint,
                style: theme.textTheme.bodySmall?.copyWith(color: palette.inkMuted),
              ),
            ),
            _SliderRow(
              label: context.l10n.balance,
              value: editing.balance,
              min: -1,
              max: 1,
              display: editing.balance.abs() < 0.02
                  ? context.l10n.centre
                  : '${(editing.balance.abs() * 100).round()} % ${editing.balance < 0 ? 'L' : 'R'}',
              onChanged: (v) => _edit(editing.copyWith(balance: v.abs() < 0.02 ? 0 : v)),
            ),
            SwitchListTile(
              contentPadding: const EdgeInsets.symmetric(horizontal: 20),
              activeThumbColor: palette.onInk,
              activeTrackColor: palette.ink,
              title: Text(context.l10n.mono, style: TextStyle(fontWeight: FontWeight.w600)),
              value: editing.mono,
              onChanged: (v) => _edit(editing.copyWith(mono: v)),
            ),
          ],

          section(context.l10n.tone),
          _SliderRow(
            label: context.l10n.bass,
            value: settings.tone.bassDb,
            min: -Tone.maxDb,
            max: Tone.maxDb,
            display: formatDb(settings.tone.bassDb),
            onChanged: (v) => _setTone(settings.tone.copyWith(bassDb: _snapDb(v))),
          ),
          _SliderRow(
            label: context.l10n.treble,
            value: settings.tone.trebleDb,
            min: -Tone.maxDb,
            max: Tone.maxDb,
            display: formatDb(settings.tone.trebleDb),
            onChanged: (v) => _setTone(settings.tone.copyWith(trebleDb: _snapDb(v))),
          ),
          _SliderRow(
            label: context.l10n.tilt,
            value: settings.tone.tiltDb,
            min: -Tone.maxTiltDb,
            max: Tone.maxTiltDb,
            display: settings.tone.tiltDb == 0
                ? context.l10n.off
                : '${formatDb(settings.tone.tiltDb)} ${settings.tone.tiltDb > 0 ? context.l10n.brighter : context.l10n.warmer}',
            onChanged: (v) => _setTone(settings.tone.copyWith(tiltDb: _snapDb(v))),
          ),
          SwitchListTile(
            contentPadding: const EdgeInsets.symmetric(horizontal: 20),
            activeThumbColor: palette.onInk,
            activeTrackColor: palette.ink,
            title: Text(context.l10n.loudnessCompensation, style: TextStyle(fontWeight: FontWeight.w600)),
            subtitle: Text(context.l10n.loudnessCompensationHint),
            value: settings.tone.loudness,
            onChanged: (v) => _setTone(settings.tone.copyWith(loudness: v)),
          ),
          if (!settings.tone.isNeutral)
            Align(
              alignment: Alignment.centerRight,
              child: Padding(
                padding: const EdgeInsets.only(right: 12),
                child: TextButton(onPressed: () => _setTone(const Tone()), child: Text(context.l10n.resetTone)),
              ),
            ),

          section(context.l10n.stereoSection),
          _SliderRow(
            label: context.l10n.width,
            value: settings.stereo.width,
            min: 0,
            max: Stereo.maxWidth,
            display: settings.stereo.width == 0 ? context.l10n.mono : '${(settings.stereo.width * 100).round()} %',
            onChanged: (v) => _setStereo(settings.stereo.copyWith(width: (v - 1).abs() < 0.04 ? 1 : (v * 20).round() / 20)),
          ),
          _SliderRow(
            label: context.l10n.channelDelay,
            value: settings.stereo.delayMs,
            min: -10,
            max: 10,
            display: settings.stereo.delayMs == 0
                ? context.l10n.off
                : '${settings.stereo.delayMs > 0 ? 'R' : 'L'} ${settings.stereo.delayMs.abs().toStringAsFixed(1)} ms',
            onChanged: (v) => _setStereo(settings.stereo.copyWith(delayMs: v.abs() < 0.15 ? 0 : (v * 10).round() / 10)),
          ),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 20),
            child: Text(
              context.l10n.channelDelayHint,
              style: theme.textTheme.bodySmall?.copyWith(color: palette.inkMuted),
            ),
          ),
          SwitchListTile(
            contentPadding: const EdgeInsets.symmetric(horizontal: 20),
            activeThumbColor: palette.onInk,
            activeTrackColor: palette.ink,
            title: Text(context.l10n.invertLeft, style: TextStyle(fontWeight: FontWeight.w600)),
            value: settings.stereo.invertLeft,
            onChanged: (v) => _setStereo(settings.stereo.copyWith(invertLeft: v)),
          ),
          SwitchListTile(
            contentPadding: const EdgeInsets.symmetric(horizontal: 20),
            activeThumbColor: palette.onInk,
            activeTrackColor: palette.ink,
            title: Text(context.l10n.invertRight, style: TextStyle(fontWeight: FontWeight.w600)),
            value: settings.stereo.invertRight,
            onChanged: (v) => _setStereo(settings.stereo.copyWith(invertRight: v)),
          ),
          if (!settings.stereo.isNeutral)
            Align(
              alignment: Alignment.centerRight,
              child: Padding(
                padding: const EdgeInsets.only(right: 12),
                child: TextButton(onPressed: () => _setStereo(const Stereo()), child: Text(context.l10n.resetStereo)),
              ),
            ),

          section(context.l10n.convolution),
          Builder(builder: (context) {
            final ir = settings.devices[output.key];
            return ListTile(
              contentPadding: const EdgeInsets.symmetric(horizontal: 20),
              title: Text(context.l10n.impulseResponseFor(output.name), style: TextStyle(fontWeight: FontWeight.w600)),
              subtitle: Text(ir?.irPath == null ? context.l10n.irNone : ir!.irName ?? '—'),
              trailing: ir?.irPath == null
                  ? TextButton(onPressed: () => _loadIr(output), child: Text(context.l10n.loadIr))
                  : TextButton(onPressed: () => _removeIr(output), child: Text(context.l10n.removeIr)),
            );
          }),

          section(context.l10n.behaviour),
          SwitchListTile(
            contentPadding: const EdgeInsets.symmetric(horizontal: 20),
            activeThumbColor: palette.onInk,
            activeTrackColor: palette.ink,
            title: Text(context.l10n.askOnPlay, style: TextStyle(fontWeight: FontWeight.w600)),
            subtitle: Text(context.l10n.askOnPlayHint),
            value: settings.askOnPlay,
            onChanged: ref.read(eqSettingsProvider.notifier).setAskOnPlay,
          ),
          ListTile(
            contentPadding: const EdgeInsets.symmetric(horizontal: 20),
            leading: HugeIcon(icon: HugeIcons.strokeRoundedListView, color: palette.ink, size: 22),
            title: Text(context.l10n.rulesAndDevices, style: TextStyle(fontWeight: FontWeight.w600)),
            subtitle: Text(context.l10n.rulesDevicesCount(settings.devices.length, ref.watch(eqRulesProvider).length)),
            trailing: HugeIcon(icon: HugeIcons.strokeRoundedArrowRight01, color: palette.inkMuted, size: 20),
            onTap: () => EqRulesScreen.open(context),
          ),
          ListTile(
            contentPadding: const EdgeInsets.symmetric(horizontal: 20),
            leading: HugeIcon(icon: HugeIcons.strokeRoundedAdd01, color: palette.ink, size: 22),
            title: Text(context.l10n.newPresetImport, style: TextStyle(fontWeight: FontWeight.w600)),
            onTap: () async {
              _flush();
              _draft.set(null);
              await createPreset(context, ref, _layer);
            },
          ),
        ],
      ),
    );
  }

  /// Parametric → graphic: sample the current response at the 10 centres.
  static EqPreset _toGraphic(EqPreset p) => p.copyWith(
        graphic: true,
        bands: [
          for (final f in EqPreset.graphicFrequencies)
            EqBand(frequency: f, gainDb: EqMath.responseDb(p.bands, f).clamp(-12.0, 12.0), q: EqPreset.graphicQ),
        ],
      );
}

class _LayerCard extends StatelessWidget {
  const _LayerCard({
    required this.title,
    required this.preset,
    required this.reason,
    required this.icon,
    required this.selected,
    required this.onTap,
    required this.onChange,
  });

  final String title;
  final String preset;
  final String reason;
  final List<List<dynamic>> icon;
  final bool selected;
  final VoidCallback onTap;
  final VoidCallback onChange;

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    final theme = Theme.of(context);
    return AnimatedContainer(
      duration: const Duration(milliseconds: 180),
      decoration: BoxDecoration(
        color: palette.surface,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: selected ? palette.ink : palette.line, width: selected ? 2 : 1),
      ),
      child: InkWell(
        borderRadius: BorderRadius.circular(18),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(14, 12, 6, 12),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  HugeIcon(icon: icon, color: palette.inkMuted, size: 16),
                  const SizedBox(width: 6),
                  Expanded(
                    child: Text(
                      title,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: theme.textTheme.labelMedium?.copyWith(color: palette.inkMuted, fontWeight: FontWeight.w700),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 6),
              Text(preset, maxLines: 1, overflow: TextOverflow.ellipsis,
                  style: theme.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w800)),
              Row(
                children: [
                  Expanded(
                    child: Text(reason, maxLines: 1, overflow: TextOverflow.ellipsis, style: theme.textTheme.bodySmall),
                  ),
                  TextButton(
                    onPressed: onChange,
                    style: TextButton.styleFrom(foregroundColor: palette.ink, visualDensity: VisualDensity.compact),
                    child: Text(context.l10n.change, style: TextStyle(fontWeight: FontWeight.w700)),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _HoldToCompare extends StatefulWidget {
  const _HoldToCompare({required this.onChanged});

  final ValueChanged<bool> onChanged;

  @override
  State<_HoldToCompare> createState() => _HoldToCompareState();
}

class _HoldToCompareState extends State<_HoldToCompare> {
  bool _held = false;

  void _set(bool held) {
    if (held == _held) return;
    HapticFeedback.selectionClick();
    setState(() => _held = held);
    widget.onChanged(held);
  }

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    return Listener(
      onPointerDown: (_) => _set(true),
      onPointerUp: (_) => _set(false),
      onPointerCancel: (_) => _set(false),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 120),
        height: 48,
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: _held ? palette.ink : palette.surface,
          borderRadius: BorderRadius.circular(24),
          border: Border.all(color: _held ? palette.ink : palette.line, width: 1.5),
        ),
        child: Text(
          _held ? context.l10n.originalSound : context.l10n.holdToCompare,
          style: TextStyle(color: _held ? palette.onInk : palette.ink, fontWeight: FontWeight.w700),
        ),
      ),
    );
  }
}

class _GraphicEditor extends StatelessWidget {
  const _GraphicEditor({required this.preset, required this.onChanged});

  final EqPreset preset;
  final ValueChanged<EqPreset> onChanged;

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    final style = Theme.of(context).textTheme.labelSmall?.copyWith(color: palette.inkMuted, fontWeight: FontWeight.w700);
    return Padding(
      padding: const EdgeInsets.fromLTRB(8, 12, 8, 0),
      child: Row(
        children: [
          for (final (i, b) in preset.bands.indexed)
            Expanded(
              child: Column(
                children: [
                  Text(formatDb(b.gainDb, unit: false), style: style),
                  SizedBox(
                    height: 170,
                    child: RotatedBox(
                      quarterTurns: 3,
                      child: SliderTheme(
                        data: SliderTheme.of(context).copyWith(
                          trackHeight: 3,
                          thumbShape: const RoundSliderThumbShape(enabledThumbRadius: 7),
                        ),
                        child: Slider(
                          // Only the knob drags, so scrolling the page over
                          // the sliders doesn't change them by accident.
                          allowedInteraction: SliderInteraction.slideThumb,
                          min: -12,
                          max: 12,
                          value: b.gainDb.clamp(-12.0, 12.0),
                          onChanged: (v) => onChanged(preset.copyWith(
                            bands: [...preset.bands]..[i] = b.copyWith(gainDb: (v * 2).round() / 2),
                          )),
                        ),
                      ),
                    ),
                  ),
                  Text(_short(b.frequency), style: style),
                ],
              ),
            ),
        ],
      ),
    );
  }

  static String _short(double f) => f >= 1000 ? '${(f / 1000).round()}k' : '${f.round()}';
}

class _ParametricEditor extends StatelessWidget {
  const _ParametricEditor({
    required this.preset,
    required this.selected,
    required this.onSelect,
    required this.onChanged,
  });

  final EqPreset preset;
  final int? selected;
  final ValueChanged<int?> onSelect;
  final ValueChanged<EqPreset> onChanged;

  static double _logPos(double f) => math.log(f / EqBand.minFrequency) / math.log(EqBand.maxFrequency / EqBand.minFrequency);
  static double _freqAt(double t) => EqBand.minFrequency * math.pow(EqBand.maxFrequency / EqBand.minFrequency, t);

  static String _hz(double f) => f >= 1000 ? '${(f / 1000).toStringAsFixed(f >= 10000 ? 1 : 2)} kHz' : '${f.round()} Hz';

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    final theme = Theme.of(context);

    void update(int i, EqBand b) => onChanged(preset.copyWith(bands: [...preset.bands]..[i] = b));

    return Column(
      children: [
        for (final (i, b) in preset.bands.indexed) ...[
          ListTile(
            contentPadding: const EdgeInsets.only(left: 20, right: 8),
            selected: i == selected,
            selectedTileColor: palette.surface,
            onTap: () => onSelect(i == selected ? null : i),
            leading: CircleAvatar(
              radius: 13,
              backgroundColor: i == selected ? palette.ink : palette.line,
              child: Text('${i + 1}',
                  style: TextStyle(color: i == selected ? palette.onInk : palette.ink, fontSize: 12, fontWeight: FontWeight.w800)),
            ),
            title: Text(
              '${context.l10n.filterType(b.type)} · ${_hz(b.frequency)}',
              style: TextStyle(fontWeight: FontWeight.w700, color: palette.ink),
            ),
            subtitle: Text(
              [
                if (b.type.hasGain) formatDb(b.gainDb),
                'Q ${b.q.toStringAsFixed(2)}',
              ].join(' · '),
            ),
            trailing: IconButton(
              tooltip: context.l10n.removeBand,
              onPressed: () {
                onSelect(null);
                onChanged(preset.copyWith(bands: [...preset.bands]..removeAt(i)));
              },
              icon: HugeIcon(icon: HugeIcons.strokeRoundedDelete02, color: palette.inkMuted, size: 20),
            ),
          ),
          if (i == selected)
            Container(
              color: palette.surface,
              padding: const EdgeInsets.only(bottom: 8),
              child: Column(
                children: [
                  SizedBox(
                    height: 44,
                    child: ListView(
                      scrollDirection: Axis.horizontal,
                      padding: const EdgeInsets.symmetric(horizontal: 16),
                      children: [
                        for (final t in EqFilterType.values)
                          Padding(
                            padding: const EdgeInsets.symmetric(horizontal: 4),
                            child: ChoiceChip(
                              label: Text(context.l10n.filterType(t)),
                              selected: b.type == t,
                              showCheckmark: false,
                              selectedColor: palette.ink,
                              labelStyle: TextStyle(color: b.type == t ? palette.onInk : palette.ink, fontWeight: FontWeight.w700),
                              onSelected: (_) => update(i, b.copyWith(type: t)),
                            ),
                          ),
                      ],
                    ),
                  ),
                  _SliderRow(
                    label: context.l10n.frequency,
                    value: _logPos(b.frequency),
                    min: 0,
                    max: 1,
                    display: _hz(b.frequency),
                    onChanged: (t) => update(i, b.copyWith(frequency: _freqAt(t).roundToDouble())),
                  ),
                  if (b.type.hasGain)
                    _SliderRow(
                      label: context.l10n.gain,
                      value: b.gainDb.clamp(-EqBand.maxGainDb, EqBand.maxGainDb),
                      min: -EqBand.maxGainDb,
                      max: EqBand.maxGainDb,
                      display: formatDb(b.gainDb),
                      onChanged: (v) => update(i, b.copyWith(gainDb: (v * 10).round() / 10)),
                    ),
                  _SliderRow(
                    label: context.l10n.qWidth,
                    // Log scale 0.1 … 20.
                    value: math.log(b.q / 0.1) / math.log(200),
                    min: 0,
                    max: 1,
                    display: b.q.toStringAsFixed(2),
                    onChanged: (t) => update(i, b.copyWith(q: (0.1 * math.pow(200, t) * 100).round() / 100)),
                  ),
                ],
              ),
            ),
        ],
        if (preset.bands.length < EqPreset.maxBands)
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 8, 20, 0),
            child: Align(
              alignment: Alignment.centerLeft,
              child: OutlinedButton.icon(
                style: OutlinedButton.styleFrom(foregroundColor: palette.ink, side: BorderSide(color: palette.line, width: 1.5)),
                onPressed: () {
                  onChanged(preset.copyWith(bands: [...preset.bands, const EqBand(frequency: 1000, q: 1)]));
                  onSelect(preset.bands.length);
                },
                icon: HugeIcon(icon: HugeIcons.strokeRoundedAdd01, color: palette.ink, size: 18),
                label: Text(context.l10n.addBand(preset.bands.length, EqPreset.maxBands),
                    style: const TextStyle(fontWeight: FontWeight.w700)),
              ),
            ),
          ),
        Padding(
          padding: const EdgeInsets.fromLTRB(20, 8, 20, 0),
          child: Text(
            context.l10n.curveTip,
            style: theme.textTheme.bodySmall?.copyWith(color: palette.inkMuted),
          ),
        ),
      ],
    );
  }
}

class _SliderRow extends StatelessWidget {
  const _SliderRow({
    required this.label,
    required this.value,
    required this.min,
    required this.max,
    required this.display,
    required this.onChanged,
  });

  final String label;
  final double value;
  final double min;
  final double max;
  final String display;
  final ValueChanged<double> onChanged;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 20),
      child: Row(
        children: [
          SizedBox(width: 84, child: Text(label, style: theme.textTheme.bodyMedium)),
          Expanded(
            child: Slider(
              allowedInteraction: SliderInteraction.slideThumb,
              min: min,
              max: max,
              value: value.clamp(min, max),
              onChanged: onChanged,
            ),
          ),
          SizedBox(
            width: 76,
            child: Text(
              display,
              textAlign: TextAlign.right,
              style: theme.textTheme.bodyMedium?.copyWith(
                color: context.palette.ink,
                fontWeight: FontWeight.w700,
                fontFeatures: const [FontFeature.tabularFigures()],
              ),
            ),
          ),
        ],
      ),
    );
  }
}
