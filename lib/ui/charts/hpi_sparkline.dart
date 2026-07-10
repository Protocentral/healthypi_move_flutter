import 'package:flutter/material.dart';

/// A minimal line sparkline with an optional soft area fill — the hero HR
/// 24-hour trace and the metric-row mini charts. Width-parameterized: it fills
/// its constraints, so the same widget serves the 92×30 row spark and the wide
/// hero card. Values are plotted in order; the y-range auto-fits with padding.
///
/// Renders nothing (blank) for fewer than two points, so a no-data metric shows
/// an empty card rather than a fabricated line.
class HpiSparkline extends StatelessWidget {
  const HpiSparkline({
    super.key,
    required this.values,
    required this.color,
    this.strokeWidth = 2,
    this.areaOpacity = 0.12,
    this.min,
    this.max,
  });

  final List<double> values;
  final Color color;
  final double strokeWidth;

  /// Area fill alpha under the line; 0 disables the fill (plain line spark).
  final double areaOpacity;

  /// Optional fixed y-bounds; when null the range auto-fits to the data.
  final double? min;
  final double? max;

  @override
  Widget build(BuildContext context) {
    return SizedBox.expand(
      child: CustomPaint(
        painter: _SparklinePainter(
          values: values,
          color: color,
          strokeWidth: strokeWidth,
          areaOpacity: areaOpacity,
          fixedMin: min,
          fixedMax: max,
        ),
      ),
    );
  }
}

class _SparklinePainter extends CustomPainter {
  _SparklinePainter({
    required this.values,
    required this.color,
    required this.strokeWidth,
    required this.areaOpacity,
    this.fixedMin,
    this.fixedMax,
  });

  final List<double> values;
  final Color color;
  final double strokeWidth;
  final double areaOpacity;
  final double? fixedMin;
  final double? fixedMax;

  @override
  void paint(Canvas canvas, Size size) {
    if (values.length < 2) return;

    var lo = fixedMin ?? values.reduce((a, b) => a < b ? a : b);
    var hi = fixedMax ?? values.reduce((a, b) => a > b ? a : b);
    if (hi - lo < 1e-6) {
      // Flat series — center it so the line doesn't clip to an edge.
      lo -= 1;
      hi += 1;
    }
    const padY = 3.0;
    final plotH = size.height - padY * 2;
    double x(int i) => size.width * i / (values.length - 1);
    double y(double v) => padY + plotH * (1 - (v - lo) / (hi - lo));

    final path = Path()..moveTo(x(0), y(values[0]));
    for (var i = 1; i < values.length; i++) {
      path.lineTo(x(i), y(values[i]));
    }

    if (areaOpacity > 0) {
      final fill = Path.from(path)
        ..lineTo(size.width, size.height)
        ..lineTo(0, size.height)
        ..close();
      canvas.drawPath(
          fill, Paint()..color = color.withValues(alpha: areaOpacity));
    }

    canvas.drawPath(
      path,
      Paint()
        ..color = color
        ..style = PaintingStyle.stroke
        ..strokeWidth = strokeWidth
        ..strokeJoin = StrokeJoin.round
        ..strokeCap = StrokeCap.round,
    );
  }

  @override
  bool shouldRepaint(_SparklinePainter old) =>
      old.values != values ||
      old.color != color ||
      old.strokeWidth != strokeWidth ||
      old.areaOpacity != areaOpacity;
}
