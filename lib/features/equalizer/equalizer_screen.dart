import 'dart:async';
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
            title: const Text('Blank 10-band graphic'),
            onTap: () => Navigator.pop(context, 'graphic'),
          ),
          ListTile(
            leading: HugeIcon(icon: HugeIcons.strokeRoundedChartLineData01, color: palette.ink, size: 22),
            title: const Text('Blank parametric'),
            onTap: () => Navigator.pop(context, 'parametric'),
          ),
          ListTile(
            leading: HugeIcon(icon: HugeIcons.strokeRoundedFile01, color: palette.ink, size: 22),
            title: const Text('Import AutoEQ file (ParametricEQ.txt)'),
            onTap: () => Navigator.pop(context, 'file'),
          ),
          ListTile(
            leading: HugeIcon(icon: HugeIcons.strokeRoundedCopy01, color: palette.ink, size: 22),
            title: const Text('Paste AutoEQ / Equalizer APO text'),
            onTap: () => Navigator.pop(context, 'paste'),
          ),
        ],
      ),
    ),
  );
  if (choice == null || !context.mounted) return null;

  final id = EqPresetsNotifier.newId();
  final messenger = ScaffoldMessenger.of(context);
  EqPreset? preset;
  String suggested = kind == EqPresetKind.device ? 'My headphones' : 'My sound';

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
      preset = EqPreset.fromAutoEq(text, id: id, name: suggested.isEmpty ? 'Imported' : suggested, kind: kind);
      if (preset == null) {
        messenger.showSnackBar(const SnackBar(content: Text('No "Filter: ON PK Fc … Hz Gain … dB Q …" lines found')));
        return null;
      }
  }
  if (preset == null || !context.mounted) return null;

  final name = await askPresetName(context, title: 'Name this preset', initial: preset.name);
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
        decoration: InputDecoration(hintText: 'Preset name', fillColor: context.palette.background),
      ),
      actions: [
        TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancel')),
        FilledButton(
          onPressed: () => Navigator.pop(context, controller.text.trim().isEmpty ? null : controller.text.trim()),
          child: const Text('Save'),
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
    final name = await askPresetName(context, title: 'Duplicate preset', initial: '${source.name} (my version)');
    if (name == null) return;
    final copy = source.duplicate(id: EqPresetsNotifier.newId(), name: name);
    await _presets.save(copy);
    _activate(ref, copy);
  }

  Future<void> _presetMenu(String action, EqPreset preset) async {
    final messenger = ScaffoldMessenger.of(context);
    switch (action) {
      case 'rename':
        final name = await askPresetName(context, title: 'Rename preset', initial: preset.name);
        if (name != null) _edit(preset.copyWith(name: name));
      case 'duplicate':
        await _duplicateAndEdit(preset);
      case 'export':
        await Clipboard.setData(ClipboardData(text: preset.toAutoEq()));
        messenger.showSnackBar(const SnackBar(content: Text('Copied as AutoEQ / Equalizer APO text')));
      case 'default':
        ref.read(eqSettingsProvider.notifier).setDefaultSound(preset.id);
        messenger.showSnackBar(SnackBar(content: Text('"${preset.name}" is now the default for all music')));
      case 'delete':
        final confirmed = await showDialog<bool>(
          context: context,
          builder: (context) => AlertDialog(
            title: const Text('Delete preset?'),
            content: Text('"${preset.name}" and any rules using it will be removed.'),
            actions: [
              TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Cancel')),
              FilledButton(
                style: FilledButton.styleFrom(backgroundColor: const Color(0xFFD70015)),
                onPressed: () => Navigator.pop(context, true),
                child: const Text('Delete'),
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
    final combined = [...device.bands, ...sound.preset.bands];
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
        title: const Text('Equalizer', style: TextStyle(fontWeight: FontWeight.w800)),
        leading: IconButton(
          tooltip: 'Back',
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
                'The equalizer is off — you hear the original sound. Turn it on to apply the presets below.',
                style: theme.textTheme.bodyMedium,
              ),
            ),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: Row(
              children: [
                Expanded(
                  child: _LayerCard(
                    title: 'Device · ${output.name}',
                    preset: device.name,
                    reason: 'auto for this output',
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
                    title: 'Sound',
                    preset: sound.preset.name,
                    reason: 'from ${sound.reason.label}',
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
              'Bold: ${_layer == EqPresetKind.device ? 'device correction' : 'sound preset'} · faint: what you hear (both layers)',
              style: theme.textTheme.bodySmall?.copyWith(color: palette.inkMuted),
            ),
          ),
          // A/B
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 14, 20, 0),
            child: _HoldToCompare(onChanged: (held) => _dsp.setBypass(held)),
          ),

          section(editing.kind == EqPresetKind.device ? 'Device correction' : 'Sound preset'),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 20),
            child: Row(
              children: [
                Expanded(
                  child: Text(editing.name, style: theme.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w800)),
                ),
                if (!editing.builtIn)
                  SegmentedButton<bool>(
                    showSelectedIcon: false,
                    style: SegmentedButton.styleFrom(
                      selectedBackgroundColor: palette.ink,
                      selectedForegroundColor: palette.onInk,
                      visualDensity: VisualDensity.compact,
                    ),
                    segments: const [
                      ButtonSegment(value: true, label: Text('Graphic')),
                      ButtonSegment(value: false, label: Text('Parametric')),
                    ],
                    selected: {editing.graphic},
                    onSelectionChanged: (s) => _edit(s.first ? _toGraphic(editing) : editing.copyWith(graphic: false)),
                  ),
                PopupMenuButton<String>(
                  tooltip: 'Preset options',
                  icon: HugeIcon(icon: HugeIcons.strokeRoundedMoreVertical, color: palette.ink, size: 22),
                  onSelected: (a) => _presetMenu(a, editing),
                  itemBuilder: (_) => [
                    if (!editing.builtIn) const PopupMenuItem(value: 'rename', child: Text('Rename')),
                    const PopupMenuItem(value: 'duplicate', child: Text('Duplicate')),
                    const PopupMenuItem(value: 'export', child: Text('Copy as AutoEQ text')),
                    if (editing.kind == EqPresetKind.sound)
                      const PopupMenuItem(value: 'default', child: Text('Use for all music')),
                    if (!editing.builtIn) const PopupMenuItem(value: 'delete', child: Text('Delete')),
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
                  Expanded(child: Text('Built-in presets are read-only.', style: theme.textTheme.bodyMedium)),
                  FilledButton.icon(
                    onPressed: () => _duplicateAndEdit(editing),
                    icon: HugeIcon(icon: HugeIcons.strokeRoundedEdit02, color: palette.onInk, size: 16),
                    label: const Text('Duplicate to edit'),
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

          section('Gain'),
          if (!editing.builtIn)
            _SliderRow(
              label: 'Preamp',
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
            title: const Text('Automatic headroom', style: TextStyle(fontWeight: FontWeight.w600)),
            subtitle: Text(
              'Lowers the volume by the biggest boost so it never distorts · '
              'now ${formatDb(effectivePreamp)}',
            ),
            value: settings.autoPreamp,
            onChanged: ref.read(eqSettingsProvider.notifier).setAutoPreamp,
          ),
          if (clipping)
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 0, 20, 8),
              child: Text(
                'Boosts exceed 0 dB: the limiter will engage. Lower the preamp or turn on automatic headroom.',
                style: theme.textTheme.bodySmall?.copyWith(color: palette.hiRes, fontWeight: FontWeight.w700),
              ),
            ),

          if (editing.kind == EqPresetKind.device && !editing.builtIn) ...[
            section('Output'),
            _SliderRow(
              label: 'Crossfeed',
              value: editing.crossfeed,
              min: 0,
              max: 1,
              display: editing.crossfeed == 0 ? 'Off' : '${(editing.crossfeed * 100).round()} %',
              onChanged: (v) => _edit(editing.copyWith(crossfeed: v < 0.03 ? 0 : v)),
            ),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 20),
              child: Text(
                'Headphones: blends a little of each channel into the other, like speakers in a room.',
                style: theme.textTheme.bodySmall?.copyWith(color: palette.inkMuted),
              ),
            ),
            _SliderRow(
              label: 'Balance',
              value: editing.balance,
              min: -1,
              max: 1,
              display: editing.balance.abs() < 0.02
                  ? 'Centre'
                  : '${(editing.balance.abs() * 100).round()} % ${editing.balance < 0 ? 'L' : 'R'}',
              onChanged: (v) => _edit(editing.copyWith(balance: v.abs() < 0.02 ? 0 : v)),
            ),
            SwitchListTile(
              contentPadding: const EdgeInsets.symmetric(horizontal: 20),
              activeThumbColor: palette.onInk,
              activeTrackColor: palette.ink,
              title: const Text('Mono', style: TextStyle(fontWeight: FontWeight.w600)),
              value: editing.mono,
              onChanged: (v) => _edit(editing.copyWith(mono: v)),
            ),
          ],

          section('Behaviour'),
          SwitchListTile(
            contentPadding: const EdgeInsets.symmetric(horizontal: 20),
            activeThumbColor: palette.onInk,
            activeTrackColor: palette.ink,
            title: const Text('Ask when I start listening', style: TextStyle(fontWeight: FontWeight.w600)),
            subtitle: const Text('Offer your presets when a new queue starts and no rule decides'),
            value: settings.askOnPlay,
            onChanged: ref.read(eqSettingsProvider.notifier).setAskOnPlay,
          ),
          ListTile(
            contentPadding: const EdgeInsets.symmetric(horizontal: 20),
            leading: HugeIcon(icon: HugeIcons.strokeRoundedListView, color: palette.ink, size: 22),
            title: const Text('Rules & devices', style: TextStyle(fontWeight: FontWeight.w600)),
            subtitle: Text('${ref.watch(eqRulesProvider).length} rules · ${settings.devices.length} devices'),
            trailing: HugeIcon(icon: HugeIcons.strokeRoundedArrowRight01, color: palette.inkMuted, size: 20),
            onTap: () => EqRulesScreen.open(context),
          ),
          ListTile(
            contentPadding: const EdgeInsets.symmetric(horizontal: 20),
            leading: HugeIcon(icon: HugeIcons.strokeRoundedAdd01, color: palette.ink, size: 22),
            title: const Text('New preset / import AutoEQ', style: TextStyle(fontWeight: FontWeight.w600)),
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
                    child: const Text('Change', style: TextStyle(fontWeight: FontWeight.w700)),
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
          _held ? 'Original sound (A)' : 'Hold to compare with original',
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
              '${b.type.label} · ${_hz(b.frequency)}',
              style: TextStyle(fontWeight: FontWeight.w700, color: palette.ink),
            ),
            subtitle: Text(
              [
                if (b.type.hasGain) formatDb(b.gainDb),
                'Q ${b.q.toStringAsFixed(2)}',
              ].join(' · '),
            ),
            trailing: IconButton(
              tooltip: 'Remove band',
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
                              label: Text(t.label),
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
                    label: 'Frequency',
                    value: _logPos(b.frequency),
                    min: 0,
                    max: 1,
                    display: _hz(b.frequency),
                    onChanged: (t) => update(i, b.copyWith(frequency: _freqAt(t).roundToDouble())),
                  ),
                  if (b.type.hasGain)
                    _SliderRow(
                      label: 'Gain',
                      value: b.gainDb.clamp(-EqBand.maxGainDb, EqBand.maxGainDb),
                      min: -EqBand.maxGainDb,
                      max: EqBand.maxGainDb,
                      display: formatDb(b.gainDb),
                      onChanged: (v) => update(i, b.copyWith(gainDb: (v * 10).round() / 10)),
                    ),
                  _SliderRow(
                    label: 'Q (width)',
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
                label: Text('Add band (${preset.bands.length}/${EqPreset.maxBands})',
                    style: const TextStyle(fontWeight: FontWeight.w700)),
              ),
            ),
          ),
        Padding(
          padding: const EdgeInsets.fromLTRB(20, 8, 20, 0),
          child: Text(
            'Tip: drag a numbered point on the curve; pinch it to change its width.',
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
