// Copyright (c) 2024-2026 ProtoCentral
// SPDX-License-Identifier: MIT

import 'package:flutter/material.dart';

/// A compact hourly bar chart — the Steps row/tile mini-chart. Rounded-cap
/// vertical bars sized to fill the constraints, heights normalized to the max
/// value. Blank for an empty series (no fabricated bars).
class HpiSparkBars extends StatelessWidget {
  const HpiSparkBars({
    super.key,
    required this.values,
    required this.color,
    this.barWidth = 2.4,
    this.gap = 1.6,
  });

  final List<double> values;
  final Color color;
  final double barWidth;
  final double gap;

  @override
  Widget build(BuildContext context) {
    return SizedBox.expand(
      child: CustomPaint(
        painter: _SparkBarsPainter(
          values: values,
          color: color,
          barWidth: barWidth,
          gap: gap,
        ),
      ),
    );
  }
}

class _SparkBarsPainter extends CustomPainter {
  _SparkBarsPainter({
    required this.values,
    required this.color,
    required this.barWidth,
    required this.gap,
  });

  final List<double> values;
  final Color color;
  final double barWidth;
  final double gap;

  @override
  void paint(Canvas canvas, Size size) {
    if (values.isEmpty) return;
    final maxV = values.reduce((a, b) => a > b ? a : b);
    if (maxV <= 0) return;

    // Fit bars to the available width, shrinking the stroke if needed.
    final n = values.length;
    var w = barWidth;
    var step = w + gap;
    if (step * n > size.width) {
      step = size.width / n;
      w = (step - gap).clamp(0.6, barWidth);
    }
    final paint = Paint()
      ..color = color
      ..strokeWidth = w
      ..strokeCap = StrokeCap.round
      ..style = PaintingStyle.stroke;

    final startX = (size.width - step * n + gap) / 2 + w / 2;
    const minBar = 2.0;
    for (var i = 0; i < n; i++) {
      final h = minBar + (size.height - minBar) * (values[i] / maxV);
      final x = startX + i * step;
      canvas.drawLine(
          Offset(x, size.height), Offset(x, size.height - h), paint);
    }
  }

  @override
  bool shouldRepaint(_SparkBarsPainter old) =>
      old.values != values || old.color != color;
}
