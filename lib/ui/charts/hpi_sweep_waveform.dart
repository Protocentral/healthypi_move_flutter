import 'package:flutter/material.dart';
import '../../theme/hpi_colors.dart';

/// A monitor-style sweeping waveform (handoff 1f live ECG, 4b dual-signal).
///
/// Holds a fixed-length ring of samples. New samples are written at the head,
/// and a short gap ahead of the head is blanked — so the trace redraws in place
/// like a bedside monitor rather than scrolling. Feed it with [SweepBuffer],
/// which owns the ring and the head index.
class SweepBuffer extends ChangeNotifier {
  SweepBuffer({this.capacity = 512, this.gap = 16})
      : _samples = List<double?>.filled(capacity, null);

  final int capacity;

  /// Blanked samples ahead of the write head (the erase gap).
  final int gap;

  final List<double?> _samples;
  int _head = 0;

  List<double?> get samples => _samples;
  int get head => _head;

  /// Append one sample at the head and blank the erase gap ahead of it.
  void add(double v) {
    _samples[_head] = v;
    for (var i = 1; i <= gap; i++) {
      _samples[(_head + i) % capacity] = null;
    }
    _head = (_head + 1) % capacity;
  }

  void addAll(Iterable<double> values) {
    for (final v in values) {
      add(v);
    }
    notifyListeners();
  }

  void clear() {
    for (var i = 0; i < capacity; i++) {
      _samples[i] = null;
    }
    _head = 0;
    notifyListeners();
  }

  /// Auto-scaled bounds over the populated samples, with a floor so a flat or
  /// empty trace doesn't blow up the scale.
  (double, double) bounds() {
    double? lo, hi;
    for (final s in _samples) {
      if (s == null) continue;
      lo = (lo == null || s < lo) ? s : lo;
      hi = (hi == null || s > hi) ? s : hi;
    }
    if (lo == null || hi == null || (hi - lo).abs() < 1e-6) {
      return (-1, 1);
    }
    final pad = (hi - lo) * 0.15;
    return (lo - pad, hi + pad);
  }
}

/// Renders a [SweepBuffer] with a faint metric-tinted grid and an amber write
/// head. Blank (erase-gap) samples break the path, so no line is drawn across
/// the gap.
class HpiSweepWaveform extends StatelessWidget {
  const HpiSweepWaveform({
    super.key,
    required this.buffer,
    required this.color,
    this.strokeWidth = 2.2,
    this.showGrid = true,
  });

  final SweepBuffer buffer;
  final Color color;
  final double strokeWidth;
  final bool showGrid;

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: buffer,
      builder: (context, child) => SizedBox.expand(
        child: CustomPaint(
          painter: _SweepPainter(
            buffer: buffer,
            color: color,
            strokeWidth: strokeWidth,
            showGrid: showGrid,
          ),
        ),
      ),
    );
  }
}

class _SweepPainter extends CustomPainter {
  _SweepPainter({
    required this.buffer,
    required this.color,
    required this.strokeWidth,
    required this.showGrid,
  });

  final SweepBuffer buffer;
  final Color color;
  final double strokeWidth;
  final bool showGrid;

  @override
  void paint(Canvas canvas, Size size) {
    if (showGrid) {
      final grid = Paint()
        ..color = color.withValues(alpha: 0.08)
        ..strokeWidth = 1;
      const cell = 17.0;
      for (double x = 0; x < size.width; x += cell) {
        canvas.drawLine(Offset(x, 0), Offset(x, size.height), grid);
      }
      for (double y = 0; y < size.height; y += cell) {
        canvas.drawLine(Offset(0, y), Offset(size.width, y), grid);
      }
    }

    final n = buffer.capacity;
    final (lo, hi) = buffer.bounds();
    double x(int i) => size.width * i / (n - 1);
    double y(double v) =>
        size.height * (1 - (v - lo) / (hi - lo)).clamp(0.0, 1.0);

    final trace = Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeWidth = strokeWidth
      ..strokeJoin = StrokeJoin.round
      ..strokeCap = StrokeCap.round;

    // Draw contiguous runs; a null (erased) sample ends the current run.
    Path? path;
    for (var i = 0; i < n; i++) {
      final s = buffer.samples[i];
      if (s == null) {
        if (path != null) {
          canvas.drawPath(path, trace);
          path = null;
        }
        continue;
      }
      if (path == null) {
        path = Path()..moveTo(x(i), y(s));
      } else {
        path.lineTo(x(i), y(s));
      }
    }
    if (path != null) canvas.drawPath(path, trace);

    // Write head.
    final hx = x(buffer.head);
    canvas.drawLine(
      Offset(hx, 0),
      Offset(hx, size.height),
      Paint()
        ..color = HpiColors.hr.withValues(alpha: 0.55)
        ..strokeWidth = 1.6,
    );
  }

  @override
  bool shouldRepaint(_SweepPainter old) => true; // driven by the buffer
}
