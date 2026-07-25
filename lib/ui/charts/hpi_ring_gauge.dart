// Copyright (c) 2024-2026 ProtoCentral
// SPDX-License-Identifier: MIT

import 'dart:math' as math;
import 'package:flutter/material.dart';
import '../../theme/hpi_colors.dart';

/// A circular arc gauge — the stress/score ring (1a tile, 1e/3a hero). Draws a
/// track ring plus a colored arc for [fraction] (0..1), starting at 12 o'clock
/// clockwise. Optional [center] widget (the score number).
class HpiRingGauge extends StatelessWidget {
  const HpiRingGauge({
    super.key,
    required this.fraction,
    required this.color,
    this.strokeWidth = 5,
    this.center,
  });

  final double fraction;
  final Color color;
  final double strokeWidth;
  final Widget? center;

  @override
  Widget build(BuildContext context) {
    return CustomPaint(
      painter: _RingPainter(
        fraction: fraction.clamp(0, 1),
        color: color,
        strokeWidth: strokeWidth,
      ),
      child: center == null ? null : Center(child: center),
    );
  }
}

class _RingPainter extends CustomPainter {
  _RingPainter({
    required this.fraction,
    required this.color,
    required this.strokeWidth,
  });

  final double fraction;
  final Color color;
  final double strokeWidth;

  @override
  void paint(Canvas canvas, Size size) {
    final rect = Offset.zero & size;
    final center = rect.center;
    final radius = (math.min(size.width, size.height) - strokeWidth) / 2;
    final arcRect = Rect.fromCircle(center: center, radius: radius);

    final track = Paint()
      ..color = HpiColors.dividerStrong
      ..style = PaintingStyle.stroke
      ..strokeWidth = strokeWidth;
    canvas.drawArc(arcRect, 0, 2 * math.pi, false, track);

    if (fraction > 0) {
      final arc = Paint()
        ..color = color
        ..style = PaintingStyle.stroke
        ..strokeWidth = strokeWidth
        ..strokeCap = StrokeCap.round;
      canvas.drawArc(
          arcRect, -math.pi / 2, 2 * math.pi * fraction, false, arc);
    }
  }

  @override
  bool shouldRepaint(_RingPainter old) =>
      old.fraction != fraction ||
      old.color != color ||
      old.strokeWidth != strokeWidth;
}

/// A thin rounded progress bar — the Steps tile "goal" bar (1a). [fraction] 0..1.
class HpiProgressBar extends StatelessWidget {
  const HpiProgressBar({
    super.key,
    required this.fraction,
    required this.color,
    this.height = 6,
  });

  final double fraction;
  final Color color;
  final double height;

  @override
  Widget build(BuildContext context) {
    return ClipRRect(
      borderRadius: BorderRadius.circular(height / 2),
      child: Stack(
        children: [
          Container(height: height, color: HpiColors.dividerStrong),
          FractionallySizedBox(
            widthFactor: fraction.clamp(0, 1),
            child: Container(height: height, color: color),
          ),
        ],
      ),
    );
  }
}
