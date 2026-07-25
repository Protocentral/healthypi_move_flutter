// Copyright (c) 2024-2026 ProtoCentral
// SPDX-License-Identifier: MIT

import 'dart:math' as math;

import 'package:flutter_test/flutter_test.dart';
import 'package:move/utils/signal_view.dart';

/// A wrist-PPG session shaped like the one from the beta report: a large DC
/// pedestal, a pulsatile component well under 1% of it, and a settling
/// transient in the first second that dwarfs everything after it.
///
/// Peak 32767 / mean ~11463 came off a real 25 Hz, 632-sample record.
List<double> ppgSession({
  int n = 632,
  double dc = 11463,
  double ac = 60,
  double rateHz = 25,
}) {
  return [
    for (var i = 0; i < n; i++)
      if (i < rateHz) // ~1 s of sensor settling, clipping at int16 max
        32767.0 - (32767.0 - dc) * (i / rateHz)
      else
        dc + ac * math.sin(2 * math.pi * 1.2 * i / rateHz),
  ];
}

void main() {
  group('robustRange', () {
    test('ignores the settling transient that flattens a raw PPG plot', () {
      final s = ppgSession();
      final r = robustRange(s);

      // Absolute min/max would span ~21k, against a 120-unit waveform: the
      // pulse gets 0.5% of the axis and reads as a straight line. That is the
      // bug. The robust window must be a small multiple of the AC amplitude.
      final fullSpan = s.reduce(math.max) - s.reduce(math.min);
      final span = r.hi - r.lo;
      expect(fullSpan, greaterThan(20000),
          reason: 'the raw trace really does span the transient');
      expect(span, lessThan(1000),
          reason: 'the viewport must follow the waveform, not the transient');

      // And it must actually contain the waveform, not crop past it.
      expect(r.lo, lessThan(11463 - 50));
      expect(r.hi, greaterThan(11463 + 50));
    });

    test('a flat trace still gets a non-degenerate window', () {
      final r = robustRange(List<double>.filled(100, 42));
      expect(r.hi, greaterThan(r.lo), reason: 'never divide by a zero span');
      expect(r.lo, lessThanOrEqualTo(42));
      expect(r.hi, greaterThanOrEqualTo(42));
    });

    test('empty and non-finite input do not produce NaN bounds', () {
      final empty = robustRange(const []);
      expect(empty.hi, greaterThan(empty.lo));

      final nan = robustRange([double.nan, double.infinity, 5, 6, 7]);
      expect(nan.lo.isFinite, isTrue);
      expect(nan.hi.isFinite, isTrue);
    });

    test('a single sample is a window, not a crash', () {
      final r = robustRange(const [7.0]);
      expect(r.hi, greaterThan(r.lo));
    });
  });

  group('detrend', () {
    test('removes the DC pedestal and leaves the pulse', () {
      final s = ppgSession();
      final d = detrend(s, window: 25);

      // Steady-state region only — the first second is the transient.
      final steady = d.sublist(50);
      final mean = steady.reduce((a, b) => a + b) / steady.length;
      expect(mean.abs(), lessThan(5),
          reason: 'the 11463-count pedestal must be gone');

      final amplitude = steady.reduce(math.max) - steady.reduce(math.min);
      expect(amplitude, greaterThan(40),
          reason: 'the pulsatile component must survive, not be filtered out');
    });

    test('preserves length and handles the edges without inventing samples', () {
      final s = ppgSession(n: 40);
      expect(detrend(s, window: 25), hasLength(40));
      expect(detrend(const [], window: 25), isEmpty);
      expect(detrend(const [5.0], window: 25), [0.0]);
    });

    test('a window wider than the series does not go out of bounds', () {
      final d = detrend([1, 2, 3, 4], window: 1000);
      expect(d, hasLength(4));
      expect(d.every((v) => v.isFinite), isTrue);
    });
  });
}
