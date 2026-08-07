// Copyright (c) 2024-2026 ProtoCentral
// SPDX-License-Identifier: MIT

/// Pixel-level coverage for where trend marks land horizontally.
///
/// The local-hour bucketing fix corrected the *data* but the charts still drew
/// mark `i` of `n` at `(i + 0.5) / n`, under a hardcoded `12A · 6A · 12P · 6P ·
/// 11P` axis. So one 10 AM reading rendered dead centre (reading as noon), and
/// three small-hours readings spread across the whole day — which is what a
/// beta user reported as "the timezone is still wrong" after the clock was
/// already right.
///
/// These render the painters and inspect the actual pixels, because the bug was
/// invisible to any test of the data alone.
library;

import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:move/ui/charts/hpi_trend_charts.dart';

const _size = Size(480, 120);

/// Renders [chart] and returns the x range, in fractions of the plot width,
/// containing anything the painter drew in [color].
Future<({double lo, double hi})> _markSpan(
  WidgetTester tester,
  Widget chart,
  Color color,
) async {
  final key = GlobalKey();
  await tester.pumpWidget(MaterialApp(
    home: Center(
      child: RepaintBoundary(
        key: key,
        child: SizedBox(width: _size.width, height: _size.height, child: chart),
      ),
    ),
  ));
  await tester.pumpAndSettle();

  final boundary =
      key.currentContext!.findRenderObject()! as RenderRepaintBoundary;
  // Rasterising has to happen on the real clock: under the widget tester's fake
  // async, `toImage` never completes.
  late final ui.Image image;
  late final ByteData data;
  await tester.runAsync(() async {
    image = await boundary.toImage();
    data = (await image.toByteData(format: ui.ImageByteFormat.rawRgba))!;
  });

  // The plot stops kTrendRightGutter short of the widget; positions are
  // fractions of that plot, which is what the painters use.
  final plotW = _size.width - kTrendRightGutter;
  double? lo, hi;
  for (var x = 0; x < image.width; x++) {
    for (var y = 0; y < image.height; y++) {
      final o = (y * image.width + x) * 4;
      final r = data.getUint8(o), g = data.getUint8(o + 1), b = data.getUint8(o + 2);
      // Match the mark colour loosely — it is drawn antialiased and, in the
      // candle chart, over a tinted baseline band.
      final hit = (r - (color.r * 255)).abs() < 40 &&
          (g - (color.g * 255)).abs() < 40 &&
          (b - (color.b * 255)).abs() < 40;
      if (!hit) continue;
      final f = x / plotW;
      lo = (lo == null || f < lo) ? f : lo;
      hi = (hi == null || f > hi) ? f : hi;
    }
  }
  image.dispose();
  expect(lo, isNotNull, reason: 'the painter drew nothing');
  return (lo: lo!, hi: hi!);
}

void main() {
  const mark = Color(0xFFFF9800);

  group('HpiCandleChart', () {
    testWidgets('a lone 10 AM reading sits at 10 AM, not in the middle',
        (tester) async {
      final span = await _markSpan(
        tester,
        HpiCandleChart(
          bins: const [TrendBin(min: 82, max: 94, center: 91)],
          color: mark,
          xAxis: TrendXAxis.localHours([DateTime(2026, 8, 6, 10, 2)]),
        ),
        mark,
      );
      // 10.5/24 = 0.4375. The bug drew it at 0.5.
      final centre = (span.lo + span.hi) / 2;
      expect(centre, closeTo(10.5 / 24, 0.03));
      expect(centre, isNot(closeTo(0.5, 0.02)));
    });

    testWidgets('three small-hours readings stay in the small hours',
        (tester) async {
      final span = await _markSpan(
        tester,
        HpiCandleChart(
          bins: const [
            TrendBin(min: 63, max: 97, center: 86),
            TrendBin(min: 70, max: 90, center: 80),
            TrendBin(min: 75, max: 88, center: 82),
          ],
          color: mark,
          xAxis: TrendXAxis.localHours([
            DateTime(2026, 8, 6, 1),
            DateTime(2026, 8, 6, 2),
            DateTime(2026, 8, 6, 4),
          ]),
        ),
        mark,
      );
      // Everything drawn must fall inside the first fifth of the day. The bug
      // spread these to 1/6, 3/6 and 5/6 of the axis.
      expect(span.hi, lessThan(0.22));
    });

    testWidgets('without an axis it still spreads evenly (Week/Month/6M)',
        (tester) async {
      final span = await _markSpan(
        tester,
        const HpiCandleChart(
          bins: [TrendBin(min: 82, max: 94, center: 91)],
          color: mark,
        ),
        mark,
      );
      expect((span.lo + span.hi) / 2, closeTo(0.5, 0.03));
    });

    testWidgets('marks are hour-wide, not plot-wide, on a sparse day',
        (tester) async {
      final span = await _markSpan(
        tester,
        HpiCandleChart(
          bins: const [
            TrendBin(min: 82, max: 94, center: 91),
            TrendBin(min: 70, max: 90, center: 80),
          ],
          color: mark,
          xAxis: TrendXAxis.localHours(
              [DateTime(2026, 8, 6, 3), DateTime(2026, 8, 6, 20)]),
        ),
        mark,
      );
      // Two readings 17 hours apart must not draw as two half-plot slabs: the
      // stroke width comes from the 24-slot domain, not the sample count.
      expect(span.lo, closeTo(3.5 / 24, 0.05));
      expect(span.hi, closeTo(20.5 / 24, 0.05));
    });
  });

  group('HpiLineChart', () {
    testWidgets('a lone SpO2 spot check sits at its hour', (tester) async {
      // The original report verbatim: one reading taken just after 10:00.
      final span = await _markSpan(
        tester,
        HpiLineChart(
          values: const [97],
          color: mark,
          yRange: const (90, 100),
          xAxis: TrendXAxis.localHours([DateTime(2026, 8, 6, 10, 2)]),
        ),
        mark,
      );
      expect((span.lo + span.hi) / 2, closeTo(10.5 / 24, 0.04));
    });

    testWidgets('a morning series does not stretch across the day',
        (tester) async {
      final span = await _markSpan(
        tester,
        HpiLineChart(
          values: const [96, 97, 95],
          color: mark,
          yRange: const (90, 100),
          xAxis: TrendXAxis.localHours([
            DateTime(2026, 8, 6, 8),
            DateTime(2026, 8, 6, 9),
            DateTime(2026, 8, 6, 10),
          ]),
        ),
        mark,
      );
      expect(span.lo, closeTo(8.5 / 24, 0.04));
      expect(span.hi, closeTo(10.5 / 24, 0.04));
    });
  });

  group('HpiBarChart', () {
    testWidgets('an evening step burst draws in the evening', (tester) async {
      final span = await _markSpan(
        tester,
        HpiBarChart(
          values: const [1200, 800],
          color: mark,
          xAxis: TrendXAxis.localHours(
              [DateTime(2026, 8, 6, 18), DateTime(2026, 8, 6, 19)]),
        ),
        mark,
      );
      expect(span.lo, greaterThan(0.7));
    });
  });
}
