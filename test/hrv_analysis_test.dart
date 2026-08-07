// Copyright (c) 2024-2026 ProtoCentral
// SPDX-License-Identifier: MIT

import 'dart:math' as math;

import 'package:flutter_test/flutter_test.dart';
import 'package:move/utils/hrv_analysis.dart';

/// Synthesise an ECG-like trace from a list of R-R intervals.
///
/// Each beat is a sharp biphasic QRS plus a broad T wave, riding on baseline
/// wander — the three things the detector's bandpass is supposed to separate.
/// The T wave matters: a naive "threshold the raw signal" detector double-counts
/// it, so its presence is part of what the test is checking.
List<double> synthEcg(
  List<double> rrMs, {
  required int sampleRate,
  double amplitude = 1.0,
  double wander = 0.0,
  double noise = 0.0,
  int seed = 7,
}) {
  final total = rrMs.fold<double>(0, (a, b) => a + b) + 1000;
  final n = (total * sampleRate / 1000).round();
  final out = List<double>.filled(n, 0);
  final rnd = math.Random(seed);

  // Baseline wander at 0.3 Hz plus optional white noise.
  for (var i = 0; i < n; i++) {
    final t = i / sampleRate;
    out[i] = wander * math.sin(2 * math.pi * 0.3 * t) +
        (noise == 0 ? 0 : (rnd.nextDouble() - 0.5) * 2 * noise);
  }

  void addBeat(int centre) {
    // QRS: ~40 ms sharp positive spike with small flanking negatives.
    final q = (0.02 * sampleRate).round().clamp(1, n);
    for (var k = -q; k <= q; k++) {
      final idx = centre + k;
      if (idx < 0 || idx >= n) continue;
      final x = k / q;
      out[idx] += amplitude * math.exp(-8 * x * x);
      if (k.abs() > q ~/ 2) out[idx] -= amplitude * 0.25 * math.exp(-4 * x * x);
    }
    // T wave: broad, ~250 ms after R, a third of the amplitude.
    final tOffset = (0.25 * sampleRate).round();
    final tw = (0.08 * sampleRate).round().clamp(1, n);
    for (var k = -tw; k <= tw; k++) {
      final idx = centre + tOffset + k;
      if (idx < 0 || idx >= n) continue;
      final x = k / tw;
      out[idx] += amplitude * 0.33 * math.exp(-3 * x * x);
    }
  }

  var t = 500.0; // first beat at 0.5 s
  addBeat((t * sampleRate / 1000).round());
  for (final rr in rrMs) {
    t += rr;
    addBeat((t * sampleRate / 1000).round());
  }
  return out;
}

void main() {
  group('HrvMetrics', () {
    test('a perfectly regular rhythm has zero variability', () {
      final m = HrvMetrics.fromRr(List.filled(30, 800.0));
      expect(m.meanRrMs, closeTo(800, 0.001));
      expect(m.meanHrBpm, closeTo(75, 0.001));
      expect(m.sdnnMs, closeTo(0, 1e-9));
      expect(m.rmssdMs, closeTo(0, 1e-9));
      expect(m.pnn50, 0);
      expect(m.beats, 31);
    });

    test('RMSSD and SDNN match hand-computed values', () {
      // Alternating 800/840 ms: successive differences are ±40 ms, so RMSSD is
      // exactly 40. SDNN is the sample SD of the values themselves.
      final rr = [for (var i = 0; i < 20; i++) i.isEven ? 800.0 : 840.0];
      final m = HrvMetrics.fromRr(rr);
      expect(m.rmssdMs, closeTo(40, 1e-9));
      expect(m.meanRrMs, closeTo(820, 1e-9));
      // Sample SD of ten 800s and ten 840s.
      expect(m.sdnnMs, closeTo(math.sqrt(20 * 400 / 19), 1e-9));
      // No successive difference exceeds 50 ms.
      expect(m.pnn50, 0);
    });

    test('pNN50 counts successive differences over 50 ms', () {
      final rr = [800.0, 900.0, 800.0, 900.0, 800.0];
      final m = HrvMetrics.fromRr(rr);
      // Every one of the four differences is 100 ms.
      expect(m.pnn50, 1.0);
    });

    test('too few intervals reports empty rather than fabricating zeros', () {
      expect(HrvMetrics.fromRr(const [800.0]).beats, 0);
      expect(HrvMetrics.fromRr(const <double>[]).isReliable, isFalse);
    });

    test('a clean 30-beat series is reliable, a 5-beat one is not', () {
      expect(HrvMetrics.fromRr(List.filled(30, 800.0)).isReliable, isTrue);
      expect(HrvMetrics.fromRr(List.filled(5, 800.0)).isReliable, isFalse);
    });
  });

  group('RrSeries.filtered', () {
    test('drops out-of-range intervals and counts them', () {
      final s = RrSeries.filtered([800, 800, 100, 800, 5000, 800]);
      expect(s.rrMs, [800, 800, 800, 800]);
      expect(s.rejected, 2);
      expect(s.artifactFraction, closeTo(2 / 6, 1e-9));
    });

    test('drops a missed beat (doubled interval) via the jump test', () {
      final s = RrSeries.filtered([800, 800, 1600, 800, 800]);
      expect(s.rrMs, [800, 800, 800, 800]);
      expect(s.rejected, 1);
    });

    test('an artifact does not drag the reference along with it', () {
      // The 1600 is rejected; the following 800s must still be accepted, which
      // only works because the reference stays at the last *accepted* value.
      final s = RrSeries.filtered([800, 1600, 800, 800]);
      expect(s.rrMs, [800, 800, 800]);
    });

    test('tolerates a gradual rate change within the jump limit', () {
      final s = RrSeries.filtered([800, 840, 880, 920, 960]);
      expect(s.rejected, 0);
    });

    test('timesMs is the cumulative tachogram axis', () {
      final s = RrSeries.filtered([800, 800, 800]);
      expect(s.timesMs, [800, 1600, 2400]);
    });
  });

  group('detectRPeaks over synthetic ECG', () {
    test('finds every beat of a clean 60 bpm strip', () {
      const sr = 250;
      final rr = List.filled(29, 1000.0); // 30 beats over 30 s
      final peaks = detectRPeaks(synthEcg(rr, sampleRate: sr), sampleRate: sr);
      expect(peaks.length, 30);
    });

    test('does not double-count T waves', () {
      const sr = 250;
      // Tall T waves are the classic false-positive source.
      final ecg = synthEcg(List.filled(29, 1000.0), sampleRate: sr);
      final peaks = detectRPeaks(ecg, sampleRate: sr);
      // Exactly one detection per beat, never two.
      expect(peaks.length, 30);
      final rr = rrIntervalsMs(peaks, sr);
      for (final v in rr) {
        expect(v, closeTo(1000, 20));
      }
    });

    test('recovers R-R intervals through baseline wander and noise', () {
      const sr = 250;
      final truth = [
        for (var i = 0; i < 40; i++) 800.0 + (i % 5) * 20,
      ];
      final ecg = synthEcg(truth,
          sampleRate: sr, wander: 2.0, noise: 0.05, amplitude: 1.0);
      final result = hrvFromEcg(ecg, sampleRate: sr);

      expect(result.peaks.length, truth.length + 1);
      // Every interval, to within the 4 ms sample period at 250 Hz. Tight on
      // purpose: a detector that finds the right *number* of beats but places
      // each fiducial tens of ms off still counts perfectly while reporting a
      // wholly invented RMSSD, so beat count alone proves nothing.
      final measured = rrIntervalsMs(result.peaks, sr);
      for (var i = 0; i < truth.length; i++) {
        expect(measured[i], closeTo(truth[i], 4));
      }
    });

    test('an inverted lead gives identical intervals', () {
      // Electrode orientation decides whether the dominant deflection is the R
      // spike or the S trough. The fiducial may differ; the intervals must not.
      const sr = 250;
      final truth = [for (var i = 0; i < 30; i++) 800.0 + (i % 4) * 25];
      final upright = synthEcg(truth, sampleRate: sr, wander: 1.0);
      final inverted = [for (final v in upright) -v];

      final a = rrIntervalsMs(detectRPeaks(upright, sampleRate: sr), sr);
      final b = rrIntervalsMs(detectRPeaks(inverted, sampleRate: sr), sr);
      expect(b.length, a.length);
      for (var i = 0; i < a.length; i++) {
        expect(b[i], closeTo(a[i], 4));
      }
    });

    test('ECG-derived RMSSD tracks the RMSSD of the intervals used to build it',
        () {
      const sr = 500;
      final truth = [
        for (var i = 0; i < 60; i++) i.isEven ? 820.0 : 860.0,
      ];
      final ecg = synthEcg(truth, sampleRate: sr, wander: 1.0, noise: 0.02);
      final result = hrvFromEcg(ecg, sampleRate: sr);
      final reference = HrvMetrics.fromRr(truth);

      expect(result.metrics.isReliable, isTrue);
      expect(result.metrics.rmssdMs, closeTo(reference.rmssdMs, 3));
      expect(result.metrics.meanHrBpm, closeTo(reference.meanHrBpm, 0.5));
      expect(result.metrics.sdnnMs, closeTo(reference.sdnnMs, 3));
    });

    test('degenerate inputs return no peaks instead of throwing', () {
      expect(detectRPeaks(const [], sampleRate: 250), isEmpty);
      expect(detectRPeaks(List.filled(100, 0.0), sampleRate: 250), isEmpty);
      expect(detectRPeaks(List.filled(1000, 1.0), sampleRate: 0), isEmpty);
      expect(rrIntervalsMs(const [5], 250), isEmpty);
    });
  });
}
