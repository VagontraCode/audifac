import 'dart:math' as math;

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../core/theme/app_colors.dart';
import '../models/eq.dart';

/// Frequency-response graph (20 Hz – 20 kHz, log scale).
///
/// Shows [background] (e.g. the combined device + sound response) faintly and
/// [bands] boldly. When [onBandChanged] is set, each band has a handle:
/// drag to move frequency / gain, pinch to change Q. Touches that start on a
/// handle are claimed immediately so the page doesn't scroll; elsewhere the
/// page scrolls normally.
class EqCurve extends StatefulWidget {
  const EqCurve({
    super.key,
    required this.bands,
    this.background,
    this.selected,
    this.onSelect,
    this.onBandChanged,
    this.color,
    this.height = 220,
  });

  final List<EqBand> bands;
  final List<EqBand>? background;
  final int? selected;
  final ValueChanged<int>? onSelect;
  final void Function(int index, EqBand band)? onBandChanged;
  final Color? color;
  final double height;

  static const rangeDb = 15.0;

  @override
  State<EqCurve> createState() => _EqCurveState();
}

class _EqCurveState extends State<EqCurve> {
  int? _dragging;
  bool _downOnHandle = false;
  double _startQ = 1;
  double _startGain = 0;
  double _startFreq = 1000;
  Offset _startFocal = Offset.zero;

  static double _x(double f, double width) =>
      width * (math.log(f / EqBand.minFrequency) / math.log(EqBand.maxFrequency / EqBand.minFrequency));

  static double _freqAt(double x, double width) =>
      EqBand.minFrequency * math.pow(EqBand.maxFrequency / EqBand.minFrequency, (x / width).clamp(0.0, 1.0));

  static double _y(double db, double height) => height / 2 - (db / EqCurve.rangeDb) * (height / 2 - 12);

  static double _dbAt(double y, double height) => (height / 2 - y) / (height / 2 - 12) * EqCurve.rangeDb;

  Offset _handle(EqBand b, Size size) {
    final db = b.type.hasGain ? b.gainDb : 0.0;
    return Offset(_x(b.frequency, size.width), _y(db.clamp(-EqCurve.rangeDb, EqCurve.rangeDb), size.height));
  }

  int? _nearest(Offset p, Size size) {
    int? best;
    var bestDist = 36.0;
    for (final (i, b) in widget.bands.indexed) {
      final d = (_handle(b, size) - p).distance;
      if (d < bestDist) {
        best = i;
        bestDist = d;
      }
    }
    return best;
  }

  void _onStart(ScaleStartDetails d, Size size) {
    final i = _nearest(d.localFocalPoint, size) ?? widget.selected;
    if (i == null || i >= widget.bands.length) return;
    _dragging = i;
    final b = widget.bands[i];
    _startQ = b.q;
    _startGain = b.gainDb;
    _startFreq = b.frequency;
    _startFocal = d.localFocalPoint;
    widget.onSelect?.call(i);
    HapticFeedback.selectionClick();
  }

  void _onUpdate(ScaleUpdateDetails d, Size size) {
    final i = _dragging;
    if (i == null || i >= widget.bands.length) return;
    final b = widget.bands[i];
    if (d.pointerCount >= 2) {
      // Pinch: spread fingers = wider band = lower Q.
      widget.onBandChanged!(i, b.copyWith(q: _startQ / d.scale));
      return;
    }
    final delta = d.localFocalPoint - _startFocal;
    widget.onBandChanged!(
      i,
      b.copyWith(
        frequency: _freqAt(_x(_startFreq, size.width) + delta.dx, size.width),
        gainDb: b.type.hasGain ? _dbAt(_y(_startGain, size.height) + delta.dy, size.height) : null,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    final color = widget.color ?? palette.ink;
    final editable = widget.onBandChanged != null;

    return LayoutBuilder(
      builder: (context, constraints) {
        final size = Size(constraints.maxWidth, widget.height);
        return RawGestureDetector(
          gestures: {
            if (editable)
              _HandleScaleRecognizer: GestureRecognizerFactoryWithHandlers<_HandleScaleRecognizer>(
                () => _HandleScaleRecognizer(() => _downOnHandle),
                (r) => r
                  ..onStart = ((d) => _onStart(d, size))
                  ..onUpdate = ((d) => _onUpdate(d, size))
                  ..onEnd = ((_) => _dragging = null),
              ),
          },
          child: Listener(
            // The inner Listener sees the pointer before the recognizer does:
            // decide here whether this touch grabs a handle.
            onPointerDown: (e) {
              final i = editable ? _nearest(e.localPosition, size) : null;
              _downOnHandle = i != null;
              if (i != null) widget.onSelect?.call(i);
            },
            child: CustomPaint(
              size: size,
              painter: _CurvePainter(
                bands: widget.bands,
                background: widget.background,
                selected: widget.selected,
                editable: editable,
                color: color,
                grid: palette.line,
                label: palette.inkMuted,
                handleFill: palette.surface,
              ),
            ),
          ),
        );
      },
    );
  }
}

/// Scale recognizer that wins the gesture arena at once when the touch
/// started on a handle (so the surrounding list can't steal the drag).
class _HandleScaleRecognizer extends ScaleGestureRecognizer {
  _HandleScaleRecognizer(this._onHandle);

  final bool Function() _onHandle;

  @override
  void addAllowedPointer(PointerDownEvent event) {
    super.addAllowedPointer(event);
    if (_onHandle()) resolve(GestureDisposition.accepted);
  }
}

class _CurvePainter extends CustomPainter {
  _CurvePainter({
    required this.bands,
    required this.background,
    required this.selected,
    required this.editable,
    required this.color,
    required this.grid,
    required this.label,
    required this.handleFill,
  });

  final List<EqBand> bands;
  final List<EqBand>? background;
  final int? selected;
  final bool editable;
  final Color color;
  final Color grid;
  final Color label;
  final Color handleFill;

  static const _gridFreqs = [50.0, 100.0, 200.0, 500.0, 1000.0, 2000.0, 5000.0, 10000.0];
  static String _freqLabel(double f) => f >= 1000 ? '${(f / 1000).round()}k' : '${f.round()}';

  @override
  void paint(Canvas canvas, Size size) {
    final gridPaint = Paint()
      ..color = grid
      ..strokeWidth = 1;
    final textStyle = TextStyle(color: label, fontSize: 10, fontWeight: FontWeight.w600);

    for (final f in _gridFreqs) {
      final x = _EqCurveState._x(f, size.width);
      canvas.drawLine(Offset(x, 0), Offset(x, size.height), gridPaint);
      _text(canvas, _freqLabel(f), Offset(x + 3, size.height - 14), textStyle);
    }
    for (final db in [-12.0, -6.0, 0.0, 6.0, 12.0]) {
      final y = _EqCurveState._y(db, size.height);
      canvas.drawLine(
        Offset(0, y),
        Offset(size.width, y),
        db == 0 ? (Paint()
          ..color = label.withValues(alpha: 0.5)
          ..strokeWidth = 1.2) : gridPaint,
      );
      if (db != 0) _text(canvas, '${db > 0 ? '+' : ''}${db.round()}', Offset(4, y - 13), textStyle);
    }

    final points = EqMath.logFrequencies(size.width.clamp(60, 400).round());
    Path pathFor(List<EqBand> bs) {
      final path = Path();
      for (final (i, f) in points.indexed) {
        final db = EqMath.responseDb(bs, f).clamp(-EqCurve.rangeDb * 1.6, EqCurve.rangeDb * 1.6);
        final p = Offset(_EqCurveState._x(f, size.width), _EqCurveState._y(db, size.height));
        i == 0 ? path.moveTo(p.dx, p.dy) : path.lineTo(p.dx, p.dy);
      }
      return path;
    }

    final bg = background;
    if (bg != null && bg.isNotEmpty) {
      canvas.drawPath(
        pathFor(bg),
        Paint()
          ..color = color.withValues(alpha: 0.28)
          ..style = PaintingStyle.stroke
          ..strokeWidth = 2
          ..strokeCap = StrokeCap.round,
      );
    }

    final main = pathFor(bands);
    final zeroY = _EqCurveState._y(0, size.height);
    final fill = Path.from(main)
      ..lineTo(size.width, zeroY)
      ..lineTo(0, zeroY)
      ..close();
    canvas.drawPath(fill, Paint()..color = color.withValues(alpha: 0.10));
    canvas.drawPath(
      main,
      Paint()
        ..color = color
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2.6
        ..strokeCap = StrokeCap.round
        ..strokeJoin = StrokeJoin.round,
    );

    if (!editable) return;
    for (final (i, b) in bands.indexed) {
      final db = b.type.hasGain ? b.gainDb : 0.0;
      final c = Offset(
        _EqCurveState._x(b.frequency, size.width),
        _EqCurveState._y(db.clamp(-EqCurve.rangeDb, EqCurve.rangeDb), size.height),
      );
      final isSelected = i == selected;
      canvas.drawCircle(c, isSelected ? 11 : 8, Paint()..color = isSelected ? color : handleFill);
      canvas.drawCircle(
        c,
        isSelected ? 11 : 8,
        Paint()
          ..color = color
          ..style = PaintingStyle.stroke
          ..strokeWidth = 2,
      );
      _text(
        canvas,
        '${i + 1}',
        c - const Offset(3.5, 6.5),
        TextStyle(color: isSelected ? handleFill : color, fontSize: 9, fontWeight: FontWeight.w800),
      );
    }
  }

  void _text(Canvas canvas, String text, Offset at, TextStyle style) {
    final tp = TextPainter(text: TextSpan(text: text, style: style), textDirection: TextDirection.ltr)..layout();
    tp.paint(canvas, at);
  }

  @override
  bool shouldRepaint(_CurvePainter old) =>
      old.bands != bands || old.background != background || old.selected != selected || old.color != color;
}
