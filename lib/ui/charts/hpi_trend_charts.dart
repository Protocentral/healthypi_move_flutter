// Copyright (c) 2024-2026 ProtoCentral
// SPDX-License-Identifier: MIT

import 'dart:math' as math;
import 'package:flutter/material.dart';
import '../../theme/hpi_colors.dart';

/// Trend-detail charts (handoff screens 1d/3a–3d), all width-parameterized
/// CustomPainters that fill their constraints so the same painter serves the
/// phone plot and the wider tablet pane. Shared conventions: a small plot inset,
/// up to three hairline gridlines with right-side Rubik-style value labels, and
/// metric-colored marks. All render blank for empty input — a no-data metric
/// shows an empty card, never a fabricated chart.

/// One hourly/daily bin for the candlestick: a min–max range with a center mark.
class TrendBin {
  const TrendBin({required this.min, required this.max, required this.center});
  final double min;
  final double max;
  final double center;
}

/// A shaded horizontal band (e.g. the 30-day resting HR baseline).
class TrendBand {
  const TrendBand({required this.lo, required this.hi, required this.color});
  final double lo;
  final double hi;
  final Color color;
}

const double _rightGutter = 30; // space for y labels
const double _padY = 8;

({double lo, double hi}) _fit(double lo, double hi) {
  if (hi - lo < 1e-6) return (lo: lo - 1, hi: hi + 1);
  final pad = (hi - lo) * 0.12;
  return (lo: lo - pad, hi: hi + pad);
}

void _drawGrid(Canvas canvas, Size size, double plotW, double lo, double hi,
    {String Function(double)? label}) {
  final labelPaint = TextPainter(textDirection: TextDirection.ltr);
  final line = Paint()
    ..color = HpiColors.divider
    ..strokeWidth = 1;
  for (var i = 0; i <= 2; i++) {
    final v = lo + (hi - lo) * i / 2;
    final y = _padY + (size.height - 2 * _padY) * (1 - i / 2);
    canvas.drawLine(Offset(0, y), Offset(plotW, y), line);
    if (label != null) {
      labelPaint.text = TextSpan(
          text: label(v),
          style: const TextStyle(
              color: HpiColors.faint,
              fontSize: 9,
              fontFamily: 'JetBrains Mono'));
      labelPaint.layout();
      labelPaint.paint(
          canvas, Offset(plotW + 6, y - labelPaint.height / 2));
    }
  }
}

// ---------------------------------------------------------------------------
// Candlestick — hourly/daily min–max as rounded vertical strokes (HR, generic).
// ---------------------------------------------------------------------------

class HpiCandleChart extends StatelessWidget {
  const HpiCandleChart({
    super.key,
    required this.bins,
    required this.color,
    this.band,
    this.yLabel,
  });

  final List<TrendBin> bins;
  final Color color;
  final TrendBand? band;
  final String Function(double)? yLabel;

  @override
  Widget build(BuildContext context) {
    return SizedBox.expand(
      child: CustomPaint(
          painter: _CandlePainter(bins, color, band, yLabel)),
    );
  }
}

class _CandlePainter extends CustomPainter {
  _CandlePainter(this.bins, this.color, this.band, this.yLabel);
  final List<TrendBin> bins;
  final Color color;
  final TrendBand? band;
  final String Function(double)? yLabel;

  @override
  void paint(Canvas canvas, Size size) {
    if (bins.isEmpty) return;
    final plotW = size.width - _rightGutter;
    var lo = bins.map((b) => b.min).reduce(math.min);
    var hi = bins.map((b) => b.max).reduce(math.max);
    if (band != null) {
      lo = math.min(lo, band!.lo);
      hi = math.max(hi, band!.hi);
    }
    final r = _fit(lo, hi);
    lo = r.lo;
    hi = r.hi;
    double y(double v) =>
        _padY + (size.height - 2 * _padY) * (1 - (v - lo) / (hi - lo));

    if (band != null) {
      final rect = Rect.fromLTRB(0, y(band!.hi), plotW, y(band!.lo));
      canvas.drawRRect(
          RRect.fromRectAndRadius(rect, const Radius.circular(6)),
          Paint()..color = band!.color);
    }
    _drawGrid(canvas, size, plotW, lo, hi, label: yLabel);

    final n = bins.length;
    final stroke = (plotW / n * 0.5).clamp(3.0, 9.0);
    final paint = Paint()
      ..color = color.withValues(alpha: 0.92)
      ..strokeWidth = stroke
      ..strokeCap = StrokeCap.round;
    for (var i = 0; i < n; i++) {
      final x = plotW * (i + 0.5) / n;
      canvas.drawLine(Offset(x, y(bins[i].max)), Offset(x, y(bins[i].min)), paint);
    }
  }

  @override
  bool shouldRepaint(_CandlePainter old) => old.bins != bins || old.color != color;
}

// ---------------------------------------------------------------------------
// Bars — hourly/daily totals with an optional dashed goal line (steps).
// ---------------------------------------------------------------------------

class HpiBarChart extends StatelessWidget {
  const HpiBarChart({
    super.key,
    required this.values,
    required this.color,
    this.goal,
    this.goalLabel,
  });

  final List<double> values;
  final Color color;
  final double? goal;
  final String? goalLabel;

  @override
  Widget build(BuildContext context) {
    return SizedBox.expand(
      child: CustomPaint(
          painter: _BarPainter(values, color, goal, goalLabel)),
    );
  }
}

class _BarPainter extends CustomPainter {
  _BarPainter(this.values, this.color, this.goal, this.goalLabel);
  final List<double> values;
  final Color color;
  final double? goal;
  final String? goalLabel;

  @override
  void paint(Canvas canvas, Size size) {
    if (values.isEmpty) return;
    final plotW = size.width - _rightGutter;
    var hi = values.reduce(math.max);
    if (goal != null) hi = math.max(hi, goal!);
    if (hi <= 0) return;
    hi *= 1.1;
    double y(double v) => _padY + (size.height - 2 * _padY) * (1 - v / hi);

    final n = values.length;
    final stroke = (plotW / n * 0.55).clamp(3.0, 22.0);
    final paint = Paint()
      ..color = color.withValues(alpha: 0.9)
      ..strokeWidth = stroke
      ..strokeCap = StrokeCap.round;
    final base = size.height - _padY;
    for (var i = 0; i < n; i++) {
      if (values[i] <= 0) continue;
      final x = plotW * (i + 0.5) / n;
      canvas.drawLine(Offset(x, base), Offset(x, y(values[i])), paint);
    }

    if (goal != null) {
      final gy = y(goal!);
      final dash = Paint()
        ..color = color.withValues(alpha: 0.6)
        ..strokeWidth = 1.2;
      for (double x = 0; x < plotW; x += 7) {
        canvas.drawLine(Offset(x, gy), Offset(x + 3, gy), dash);
      }
      if (goalLabel != null) {
        final tp = TextPainter(
            textDirection: TextDirection.ltr,
            text: TextSpan(
                text: goalLabel,
                style: TextStyle(
                    color: color.withValues(alpha: 0.8),
                    fontSize: 9,
                    fontFamily: 'JetBrains Mono')))
          ..layout();
        tp.paint(canvas, Offset(plotW + 4, gy - tp.height / 2));
      }
    }
  }

  @override
  bool shouldRepaint(_BarPainter old) => old.values != values || old.color != color;
}

// ---------------------------------------------------------------------------
// Line — a curve with gridlines, an optional baseline, and event dots
// (SpO₂ night curve with sub-95 dips; temp nightly line).
// ---------------------------------------------------------------------------

class HpiLineChart extends StatelessWidget {
  const HpiLineChart({
    super.key,
    required this.values,
    required this.color,
    this.baseline,
    this.eventIndices = const [],
    this.eventColor,
    this.yLabel,
    this.yRange,
  });

  final List<double> values;
  final Color color;
  final double? baseline;
  final List<int> eventIndices;
  final Color? eventColor;
  final String Function(double)? yLabel;
  final (double, double)? yRange;

  @override
  Widget build(BuildContext context) {
    return SizedBox.expand(
      child: CustomPaint(
        painter: _LinePainter(
            values, color, baseline, eventIndices, eventColor, yLabel, yRange),
      ),
    );
  }
}

class _LinePainter extends CustomPainter {
  _LinePainter(this.values, this.color, this.baseline, this.events,
      this.eventColor, this.yLabel, this.yRange);
  final List<double> values;
  final Color color;
  final double? baseline;
  final List<int> events;
  final Color? eventColor;
  final String Function(double)? yLabel;
  final (double, double)? yRange;

  @override
  void paint(Canvas canvas, Size size) {
    if (values.length < 2) return;
    final plotW = size.width - _rightGutter;
    double lo, hi;
    if (yRange != null) {
      lo = yRange!.$1;
      hi = yRange!.$2;
    } else {
      final r = _fit(values.reduce(math.min), values.reduce(math.max));
      lo = r.lo;
      hi = r.hi;
    }
    double x(int i) => plotW * i / (values.length - 1);
    double y(double v) =>
        _padY + (size.height - 2 * _padY) * (1 - (v - lo) / (hi - lo));

    _drawGrid(canvas, size, plotW, lo, hi, label: yLabel);

    if (baseline != null) {
      final by = y(baseline!);
      final dash = Paint()
        ..color = color.withValues(alpha: 0.5)
        ..strokeWidth = 1;
      for (double px = 0; px < plotW; px += 8) {
        canvas.drawLine(Offset(px, by), Offset(px + 4, by), dash);
      }
    }

    final path = Path()..moveTo(x(0), y(values[0]));
    for (var i = 1; i < values.length; i++) {
      path.lineTo(x(i), y(values[i]));
    }
    final fill = Path.from(path)
      ..lineTo(x(values.length - 1), size.height)
      ..lineTo(0, size.height)
      ..close();
    canvas.drawPath(fill, Paint()..color = color.withValues(alpha: 0.12));
    canvas.drawPath(
        path,
        Paint()
          ..color = color
          ..style = PaintingStyle.stroke
          ..strokeWidth = 2.2
          ..strokeJoin = StrokeJoin.round);

    final ec = eventColor ?? HpiColors.error;
    for (final i in events) {
      if (i < 0 || i >= values.length) continue;
      canvas.drawCircle(Offset(x(i), y(values[i])), 3.5, Paint()..color = ec);
    }
  }

  @override
  bool shouldRepaint(_LinePainter old) => old.values != values || old.color != color;
}

// ---------------------------------------------------------------------------
// Lollipops — daily deviation above/below a baseline midline (temp, HR-vs-base).
// Positive lobes use [aboveColor], negative use [belowColor].
// ---------------------------------------------------------------------------

class HpiLollipopChart extends StatelessWidget {
  const HpiLollipopChart({
    super.key,
    required this.deviations,
    required this.aboveColor,
    required this.belowColor,
  });

  final List<double> deviations; // signed, around 0
  final Color aboveColor;
  final Color belowColor;

  @override
  Widget build(BuildContext context) {
    return SizedBox.expand(
      child: CustomPaint(
          painter: _LollipopPainter(deviations, aboveColor, belowColor)),
    );
  }
}

class _LollipopPainter extends CustomPainter {
  _LollipopPainter(this.dev, this.above, this.below);
  final List<double> dev;
  final Color above;
  final Color below;

  @override
  void paint(Canvas canvas, Size size) {
    if (dev.isEmpty) return;
    final maxAbs = dev.map((d) => d.abs()).reduce(math.max);
    final span = maxAbs < 1e-6 ? 1.0 : maxAbs * 1.2;
    final mid = size.height / 2;
    final half = size.height / 2 - _padY;

    final dash = Paint()
      ..color = HpiColors.dividerStrong
      ..strokeWidth = 1;
    for (double x = 0; x < size.width; x += 8) {
      canvas.drawLine(Offset(x, mid), Offset(x + 4, mid), dash);
    }

    final n = dev.length;
    final stroke = (size.width / n * 0.45).clamp(4.0, 10.0);
    for (var i = 0; i < n; i++) {
      final x = size.width * (i + 0.5) / n;
      final len = half * (dev[i].abs() / span);
      final up = dev[i] >= 0;
      final paint = Paint()
        ..color = up ? above : below
        ..strokeWidth = stroke
        ..strokeCap = StrokeCap.round;
      canvas.drawLine(
          Offset(x, mid), Offset(x, up ? mid - len : mid + len), paint);
    }
  }

  @override
  bool shouldRepaint(_LollipopPainter old) => old.dev != dev;
}
