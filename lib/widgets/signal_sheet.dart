import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../core/format.dart';
import '../core/theme/app_colors.dart';
import '../data/dsp_channel.dart';
import '../models/audio_info.dart';
import '../models/eq.dart';
import '../providers/audio_info_providers.dart';
import '../providers/eq_providers.dart';
import '../providers/player_providers.dart';
import '../l10n/l10n.dart';
import '../l10n/labels.dart';

/// Spectrum analyzer, level meters and the signal path: source → decoder →
/// DSP → Android mixer → output device.
class SignalSheet extends ConsumerStatefulWidget {
  const SignalSheet({super.key});

  static Future<void> show(BuildContext context) => showModalBottomSheet<void>(
        context: context,
        useRootNavigator: true,
        isScrollControlled: true,
        builder: (_) => const SignalSheet(),
      );

  @override
  ConsumerState<SignalSheet> createState() => _SignalSheetState();
}

class _SignalSheetState extends ConsumerState<SignalSheet> with SingleTickerProviderStateMixin {
  static const floor = -72.0;

  StreamSubscription<VisualizerFrame>? _sub;
  Timer? _pathTimer;
  late final Ticker _ticker;
  Map<String, dynamic>? _path;

  // Displayed values: rise instantly, fall at a steady rate (like a real meter).
  final _bands = List<double>.filled(32, floor);
  final _peaks = List<double>.filled(32, floor);
  final _peakHold = List<int>.filled(32, 0);
  var _target = List<double>.filled(32, floor);
  var _levels = [floor, floor, floor, floor]; // peakL, peakR, rmsL, rmsR
  var _shownLevels = [floor, floor, floor, floor];
  Duration _last = Duration.zero;

  @override
  void initState() {
    super.initState();
    final channel = ref.read(dspChannelProvider);
    _sub = channel.visualizer.listen((f) {
      _target = f.bands;
      _levels = [f.peakL, f.peakR, f.rmsL, f.rmsR];
    });
    _loadPath();
    _pathTimer = Timer.periodic(const Duration(seconds: 1), (_) => _loadPath());
    _ticker = createTicker(_tick)..start();
  }

  Future<void> _loadPath() async {
    final p = await ref.read(dspChannelProvider).signalPath();
    if (mounted) setState(() => _path = p);
  }

  void _tick(Duration now) {
    final dt = ((now - _last).inMicroseconds / 1e6).clamp(0.0, 0.1);
    _last = now;
    final fall = 40 * dt; // dB per frame
    for (var i = 0; i < _bands.length && i < _target.length; i++) {
      final t = math.max(floor, _target[i]);
      _bands[i] = t > _bands[i] ? t : math.max(t, _bands[i] - fall);
      if (_bands[i] >= _peaks[i]) {
        _peaks[i] = _bands[i];
        _peakHold[i] = 40; // frames
      } else if (_peakHold[i] > 0) {
        _peakHold[i]--;
      } else {
        _peaks[i] = math.max(_bands[i], _peaks[i] - fall * 0.5);
      }
    }
    _shownLevels = [
      for (var i = 0; i < 4; i++)
        math.max(floor, _levels[i]) > _shownLevels[i]
            ? math.max(floor, _levels[i])
            : math.max(math.max(floor, _levels[i]), _shownLevels[i] - fall * 0.6),
    ];
    if (mounted) setState(() {});
  }

  @override
  void dispose() {
    _ticker.dispose();
    _sub?.cancel();
    _pathTimer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final palette = context.palette;
    final song = ref.watch(currentSongProvider);
    final info = song == null ? null : ref.watch(songAudioInfoProvider(song));
    final eqOn = ref.watch(eqSettingsProvider.select((s) => s.enabled));
    final sound = ref.watch(activeSoundProvider).preset;
    final device = ref.watch(activeDevicePresetProvider);
    final muted = theme.textTheme.bodySmall?.copyWith(color: palette.inkMuted);

    return ConstrainedBox(
      constraints: BoxConstraints(maxHeight: MediaQuery.sizeOf(context).height * 0.9),
      child: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(24, 0, 24, 16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(context.l10n.signal, style: theme.textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w800)),
              const SizedBox(height: 16),
              SizedBox(
                height: 150,
                width: double.infinity,
                child: CustomPaint(
                  painter: _SpectrumPainter(
                    bands: _bands,
                    peaks: _peaks,
                    floor: floor,
                    color: palette.ink,
                    peakColor: palette.hiRes,
                    grid: palette.line,
                  ),
                ),
              ),
              Padding(
                padding: const EdgeInsets.only(top: 4),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [for (final f in ['30', '100', '500', '2k', '8k', '20k']) Text(f, style: muted)],
                ),
              ),
              const SizedBox(height: 18),
              _Meter(label: 'L', peak: _shownLevels[0], rms: _shownLevels[2], floor: floor),
              const SizedBox(height: 8),
              _Meter(label: 'R', peak: _shownLevels[1], rms: _shownLevels[3], floor: floor),
              const SizedBox(height: 4),
              Text(context.l10n.meterLegend, style: muted),
              const SizedBox(height: 22),
              Text(context.l10n.signalPath, style: theme.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w800)),
              const SizedBox(height: 8),
              ..._steps(info, eqOn, sound, device),
            ],
          ),
        ),
      ),
    );
  }

  List<Widget> _steps(AudioInfo? info, bool eqOn, EqPreset sound, EqPreset device) {
    final l10n = context.l10n;
    final p = _path;
    final out = (p?['output'] as Map?)?.cast<String, dynamic>();
    final rate = (p?['sampleRate'] as num?)?.toInt() ?? 0;
    final bits = (p?['bits'] as num?)?.toInt();
    final mixer = (out?['mixerRate'] as num?)?.toInt();
    final gain = (p?['gainDb'] as num?)?.toDouble() ?? 0;
    final crossfade = (p?['crossfade'] as num?)?.toDouble() ?? 0;
    final processing = p?['processing'] == true;
    final bitPerfect = p?['bitPerfect'] == true;
    final resampledTo = (p?['resampledTo'] as num?)?.toInt() ?? 0;
    // The rate that reaches Android's mixer.
    final reaching = resampledTo > 0 ? resampledTo : rate;
    final outputRate = (p?['outputRate'] as num?)?.toInt() ?? 0;
    final output16 = p?['output16'] == true;
    final levelFrames = (p?['levelFrames'] as num?)?.toInt() ?? 0;
    final peakDb = (p?['peakDb'] as num?)?.toDouble() ?? -100;
    final limitedPct = ((p?['limitedFraction'] as num?)?.toDouble() ?? 0) * 100;
    final clipped = (p?['clippedFrames'] as num?)?.toInt() ?? 0;
    final loudnessDb = (p?['loudnessBassDb'] as num?)?.toDouble() ?? 0;
    final convolution = p?['convolution'] as String? ?? '';
    final linearPhase = p?['linearPhase'] == true;
    final compressor = (p?['compressor'] as num?)?.toInt() ?? 0;
    String khz(int hz) => '${AudioInfo.formatSampleRate(hz)} kHz';

    final dspParts = [
      if (eqOn) 'EQ: ${l10n.presetName(sound)}${device.id == BuiltInPresets.deviceNone.id ? '' : ' + ${l10n.presetName(device)}'}${linearPhase ? ' (${l10n.linearPhaseShort})' : ''}',
      if (gain.abs() >= 0.05) l10n.volumeDb(formatDb(gain)),
      if (crossfade > 0) l10n.crossfadeSeconds(crossfade.round()),
      if (loudnessDb >= 0.1) l10n.loudnessBass(formatDb(loudnessDb)),
      if (convolution.isNotEmpty) l10n.convolutionWith(convolution),
      if (compressor > 0) l10n.compressorIs([l10n.compressorLight, l10n.compressorMedium, l10n.compressorStrong][compressor - 1]),
    ];
    final rates = [for (final r in (out?['deviceRates'] as List? ?? const [])) (r as num).toInt()];

    return [
      _Step(
        title: l10n.fieldSource,
        value: info == null
            ? '—'
            : [
                info.codec,
                if (info.bitDepth != null) '${info.bitDepth}-bit',
                if (info.sampleRate != null) khz(info.sampleRate!),
                if (info.kbpsOrNull != null && !info.quality.isLossless) '${info.kbpsOrNull} kbps',
              ].join(' · '),
      ),
      _Step(
        title: l10n.decoded,
        value: rate == 0 ? l10n.notThroughDsp : 'PCM ${bits ?? '?'}-bit · ${khz(rate)} · ${p?['channels']} ch',
      ),
      _Step(
        title: 'audifac DSP',
        value: !processing
            ? l10n.bitTransparent
            : l10n.dspProcessing(dspParts.isEmpty ? l10n.processing : dspParts.join(' · ')),
        good: !processing,
      ),
      if (resampledTo > 0)
        _Step(
          title: l10n.hqResampler,
          value: l10n.resampledByAudifac(khz(rate), khz(resampledTo)),
          good: true,
        ),
      if (levelFrames > 0)
        _Step(
          title: l10n.levels,
          value: [
            l10n.peakDbfs(peakDb.toStringAsFixed(1)),
            if (limitedPct >= 0.01)
              l10n.limiterShare(limitedPct < 1 ? limitedPct.toStringAsFixed(2) : limitedPct.toStringAsFixed(1))
            else if (clipped > 0)
              l10n.clippedCount(clipped)
            else
              l10n.noClipping,
          ].join(' · '),
          good: limitedPct < 0.01 && clipped == 0,
        ),
      if (outputRate > 0 && !bitPerfect)
        _Step(
          title: l10n.toAndroid,
          value: '${output16 ? l10n.pcm16Dithered : l10n.float32} · ${khz(outputRate)}',
        ),
      _Step(
        title: l10n.androidMixer,
        value: bitPerfect
            ? l10n.bitPerfectOn
            : mixer == null || reaching == 0
            ? '—'
            : mixer == reaching
                ? l10n.noResampling(khz(mixer))
                : l10n.resampled(khz(reaching), khz(mixer)),
        good: bitPerfect || (mixer != null && mixer == reaching),
      ),
      _Step(
        title: l10n.output,
        value: [
          out?['name'] as String? ?? l10n.phoneSpeaker,
          if (rates.isNotEmpty) l10n.accepts(rates.map(khz).join(', ')),
        ].join(' · '),
        last: true,
      ),
    ];
  }
}

class _Step extends StatelessWidget {
  const _Step({required this.title, required this.value, this.good, this.last = false});

  final String title;
  final String value;
  final bool? good;
  final bool last;

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    final theme = Theme.of(context);
    final dot = good == true ? palette.lossless : palette.ink;
    return IntrinsicHeight(
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          SizedBox(
            width: 20,
            child: Column(
              children: [
                const SizedBox(height: 4),
                Container(width: 10, height: 10, decoration: BoxDecoration(color: dot, shape: BoxShape.circle)),
                if (!last) Expanded(child: Container(width: 2, color: palette.line)),
              ],
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Padding(
              padding: const EdgeInsets.only(bottom: 14),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(title, style: theme.textTheme.labelMedium?.copyWith(color: palette.inkMuted, fontWeight: FontWeight.w700)),
                  Text(value, style: theme.textTheme.bodyMedium?.copyWith(fontWeight: FontWeight.w600)),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _Meter extends StatelessWidget {
  const _Meter({required this.label, required this.peak, required this.rms, required this.floor});

  final String label;
  final double peak;
  final double rms;
  final double floor;

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    double frac(double db) => ((db - floor) / -floor).clamp(0.0, 1.0);
    return Row(
      children: [
        SizedBox(width: 16, child: Text(label, style: const TextStyle(fontWeight: FontWeight.w800))),
        Expanded(
          child: SizedBox(
            height: 10,
            child: LayoutBuilder(
              builder: (context, c) => Stack(
                children: [
                  Container(decoration: BoxDecoration(color: palette.line, borderRadius: BorderRadius.circular(5))),
                  Container(
                    width: c.maxWidth * frac(rms),
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(5),
                      gradient: LinearGradient(colors: [palette.lossless, palette.hiRes, const Color(0xFFD70015)]),
                    ),
                  ),
                  Positioned(
                    left: (c.maxWidth * frac(peak) - 2).clamp(0, c.maxWidth - 2),
                    top: 0,
                    bottom: 0,
                    child: Container(width: 2, color: peak > -0.5 ? const Color(0xFFD70015) : palette.ink),
                  ),
                ],
              ),
            ),
          ),
        ),
        SizedBox(
          width: 56,
          child: Text(
            peak <= floor ? '−∞' : peak.toStringAsFixed(1),
            textAlign: TextAlign.right,
            style: const TextStyle(fontFeatures: [FontFeature.tabularFigures()], fontWeight: FontWeight.w600),
          ),
        ),
      ],
    );
  }
}

class _SpectrumPainter extends CustomPainter {
  _SpectrumPainter({
    required this.bands,
    required this.peaks,
    required this.floor,
    required this.color,
    required this.peakColor,
    required this.grid,
  });

  final List<double> bands;
  final List<double> peaks;
  final double floor;
  final Color color;
  final Color peakColor;
  final Color grid;

  @override
  void paint(Canvas canvas, Size size) {
    final gridPaint = Paint()
      ..color = grid
      ..strokeWidth = 1;
    for (final db in [-12.0, -24.0, -36.0, -48.0, -60.0]) {
      final y = size.height * (db / floor);
      canvas.drawLine(Offset(0, y), Offset(size.width, y), gridPaint);
    }
    final n = bands.length;
    final slot = size.width / n;
    final w = slot * 0.7;
    final bar = Paint()..color = color;
    final peak = Paint()..color = peakColor;
    for (var i = 0; i < n; i++) {
      final x = i * slot + (slot - w) / 2;
      final h = size.height * ((bands[i] - floor) / -floor).clamp(0.0, 1.0);
      canvas.drawRRect(
        RRect.fromRectAndRadius(Rect.fromLTWH(x, size.height - h, w, h), const Radius.circular(2)),
        bar,
      );
      final py = size.height * (1 - ((peaks[i] - floor) / -floor).clamp(0.0, 1.0));
      canvas.drawRect(Rect.fromLTWH(x, math.min(py, size.height - 2), w, 2), peak);
    }
  }

  @override
  bool shouldRepaint(_SpectrumPainter old) => true;
}
