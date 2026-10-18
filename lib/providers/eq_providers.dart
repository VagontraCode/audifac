import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../data/dsp_channel.dart';
import '../models/eq.dart';
import '../models/eq_rules.dart';
import '../models/song.dart';
import 'audio_info_providers.dart';
import 'player_providers.dart';
import 'user_data_providers.dart';

final dspChannelProvider = Provider<DspChannel>((ref) => DspChannel());

// --- Settings ------------------------------------------------------------------

final eqSettingsProvider = NotifierProvider<EqSettingsNotifier, EqSettings>(EqSettingsNotifier.new);

class EqSettingsNotifier extends Notifier<EqSettings> {
  static const _key = 'eq';

  @override
  EqSettings build() => EqSettings.decode(ref.read(bootstrapProvider).values[_key]);

  void _set(EqSettings next) {
    state = next;
    ref.read(databaseProvider).setValue(_key, next.encode());
  }

  void setEnabled(bool enabled) => _set(state.copyWith(enabled: enabled));
  void setDefaultSound(String presetId) => _set(state.copyWith(defaultSoundId: presetId));
  void setAskOnPlay(bool ask) => _set(state.copyWith(askOnPlay: ask));
  void setAutoPreamp(bool auto) => _set(state.copyWith(autoPreamp: auto));

  /// Correction preset to use whenever [device] is the output.
  void assignDevice(EqDevice device, String presetId) =>
      _set(state.copyWith(devices: {...state.devices, device.key: device.copyWith(presetId: presetId)}));

  /// Remembers a newly seen output (with no correction yet).
  void remember(EqDevice device) {
    if (state.devices.containsKey(device.key)) return;
    _set(state.copyWith(devices: {...state.devices, device.key: device}));
  }

  /// Restore from a backup: flags & default from [restored], devices merged
  /// (restored assignments win).
  void restore(EqSettings restored) => _set(restored.copyWith(devices: {...state.devices, ...restored.devices}));

  void forgetDevice(String key) => _set(state.copyWith(devices: {...state.devices}..remove(key)));

  /// After a preset is deleted, fall back to defaults wherever it was used.
  void presetDeleted(String id) {
    _set(state.copyWith(
      defaultSoundId: state.defaultSoundId == id ? BuiltInPresets.soundFlat.id : null,
      devices: {
        for (final d in state.devices.values)
          d.key: d.presetId == id ? d.copyWith(presetId: BuiltInPresets.deviceNone.id) : d,
      },
    ));
  }
}

// --- Presets & rules -------------------------------------------------------------

final eqPresetsProvider = NotifierProvider<EqPresetsNotifier, List<EqPreset>>(EqPresetsNotifier.new);

class EqPresetsNotifier extends Notifier<List<EqPreset>> {
  @override
  List<EqPreset> build() => [...BuiltInPresets.all, ...ref.read(bootstrapProvider).eqPresets];

  static String newId() => 'u_${DateTime.now().microsecondsSinceEpoch}';

  EqPreset? byId(String id) => state.where((p) => p.id == id).firstOrNull;

  Future<void> save(EqPreset preset) async {
    if (preset.builtIn) return;
    final exists = state.any((p) => p.id == preset.id);
    state = exists ? [for (final p in state) p.id == preset.id ? preset : p] : [...state, preset];
    await ref.read(databaseProvider).putEqPreset(preset);
  }

  Future<void> delete(String id) async {
    final preset = byId(id);
    if (preset == null || preset.builtIn) return;
    state = state.where((p) => p.id != id).toList();
    ref.read(eqSettingsProvider.notifier).presetDeleted(id);
    ref.read(eqRulesProvider.notifier).presetDeleted(id);
    if (ref.read(eqQueueOverrideProvider) == id) ref.read(eqQueueOverrideProvider.notifier).set(null);
    await ref.read(databaseProvider).deleteEqPreset(id);
  }
}

final eqPresetProvider = Provider.family<EqPreset?, String>(
  (ref, id) => ref.watch(eqPresetsProvider).where((p) => p.id == id).firstOrNull,
);

final eqRulesProvider = NotifierProvider<EqRulesNotifier, List<EqRule>>(EqRulesNotifier.new);

class EqRulesNotifier extends Notifier<List<EqRule>> {
  @override
  List<EqRule> build() => ref.read(bootstrapProvider).eqRules;

  Future<void> put(EqRule rule) async {
    state = [
      for (final r in state)
        if (!(r.scope == rule.scope && r.key == rule.key)) r,
      rule,
    ];
    await ref.read(databaseProvider).putEqRule(rule);
  }

  Future<void> remove(EqScope scope, String key) async {
    state = state.where((r) => !(r.scope == scope && r.key == key)).toList();
    await ref.read(databaseProvider).deleteEqRule(scope, key);
  }

  void presetDeleted(String id) => state = state.where((r) => r.presetId != id).toList();
}

// --- Live state ------------------------------------------------------------------

/// Where audio is going right now (speaker, wired, Bluetooth / USB device).
final outputDeviceProvider = NotifierProvider<OutputDeviceNotifier, EqDevice>(OutputDeviceNotifier.new);

class OutputDeviceNotifier extends Notifier<EqDevice> {
  @override
  EqDevice build() {
    final channel = ref.read(dspChannelProvider);
    final sub = channel.outputChanges.listen(_set);
    ref.onDispose(sub.cancel);
    channel.currentOutput().then(_set);
    return EqDevice.fromNative(const {'key': 'speaker', 'kind': 'speaker', 'name': 'Phone speaker'});
  }

  void _set(EqDevice device) {
    state = device;
    ref.read(eqSettingsProvider.notifier).remember(device);
  }
}

/// Preset chosen for the current listening session (cleared on a new queue).
final eqQueueOverrideProvider = NotifierProvider<EqQueueOverrideNotifier, String?>(EqQueueOverrideNotifier.new);

class EqQueueOverrideNotifier extends Notifier<String?> {
  @override
  String? build() => null;

  void set(String? presetId) => state = presetId;
}

/// The preset being edited, heard live in place of its layer.
final eqDraftProvider = NotifierProvider<EqDraftNotifier, EqPreset?>(EqDraftNotifier.new);

class EqDraftNotifier extends Notifier<EqPreset?> {
  @override
  EqPreset? build() => null;

  void set(EqPreset? preset) => state = preset;
}

/// Device-correction layer for the current output.
final activeDevicePresetProvider = Provider<EqPreset>((ref) {
  final draft = ref.watch(eqDraftProvider);
  final output = ref.watch(outputDeviceProvider);
  final settings = ref.watch(eqSettingsProvider);
  final id = settings.devices[output.key]?.presetId ?? BuiltInPresets.deviceNone.id;
  if (draft != null && draft.kind == EqPresetKind.device && draft.id == id) return draft;
  return ref.watch(eqPresetProvider(id)) ?? BuiltInPresets.deviceNone;
});

/// Sound-preset layer for the current song, and why it was chosen.
final activeSoundProvider = Provider<({EqPreset preset, EqReason reason})>((ref) {
  final presets = ref.watch(eqPresetsProvider);
  bool isValid(String id) => presets.any((p) => p.id == id && p.kind == EqPresetKind.sound);
  final song = ref.watch(currentSongProvider);
  final genre = song == null ? null : ref.watch(songAudioInfoProvider(song)).genre;
  final settings = ref.watch(eqSettingsProvider);
  final resolved = resolveSoundPreset(
    song: song,
    genre: genre,
    rules: ref.watch(eqRulesProvider),
    queueOverride: ref.watch(eqQueueOverrideProvider),
    defaultPresetId: isValid(settings.defaultSoundId) ? settings.defaultSoundId : BuiltInPresets.soundFlat.id,
    isValid: isValid,
  );
  final preset = presets.firstWhere((p) => p.id == resolved.presetId, orElse: () => BuiltInPresets.soundFlat);
  final draft = ref.watch(eqDraftProvider);
  if (draft != null && draft.kind == EqPresetKind.sound && draft.id == preset.id) {
    return (preset: draft, reason: resolved.reason);
  }
  return (preset: preset, reason: resolved.reason);
});

/// Pushes the combined settings to the native DSP whenever they change.
final dspSyncProvider = Provider<void>((ref) {
  final settings = ref.watch(eqSettingsProvider);
  final config = combineForNative(
    enabled: settings.enabled,
    device: ref.watch(activeDevicePresetProvider),
    sound: ref.watch(activeSoundProvider).preset,
    autoPreamp: settings.autoPreamp,
  );
  ref.read(dspChannelProvider).setConfig(config);
});

/// Song for which to offer a preset choice (a new queue started and no rule
/// decides). The shell shows the picker and clears it.
final eqPromptProvider = NotifierProvider<EqPromptNotifier, Song?>(EqPromptNotifier.new);

class EqPromptNotifier extends Notifier<Song?> {
  @override
  Song? build() {
    final sub = ref.read(audioHandlerProvider).queueStarts.listen(_onQueueStart);
    ref.onDispose(sub.cancel);
    return null;
  }

  void _onQueueStart(Song song) {
    ref.read(eqQueueOverrideProvider.notifier).set(null);
    final settings = ref.read(eqSettingsProvider);
    if (!settings.enabled || !settings.askOnPlay) return;
    final presets = ref.read(eqPresetsProvider);
    final hasOwnSound = presets.any((p) => !p.builtIn && p.kind == EqPresetKind.sound);
    if (!hasOwnSound) return;
    final genre = ref.read(songAudioInfoProvider(song)).genre;
    final rule = matchingRule(
      song: song,
      genre: genre,
      rules: ref.read(eqRulesProvider),
      isValid: (id) => presets.any((p) => p.id == id),
    );
    if (rule == null) state = song;
  }

  void clear() => state = null;
}
