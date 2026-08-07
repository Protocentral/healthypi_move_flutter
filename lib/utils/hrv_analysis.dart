// Copyright (c) 2024-2026 ProtoCentral
// SPDX-License-Identifier: MIT

/// Heart-rate-variability analysis over R-R interval series.
///
/// Two sources feed this, and keeping them in one module is the point:
///
///  - **Native R-R records** — HPI_HS `RECORDS` signal `0x05`, uint16 ms
///    straight off the watch's own beat detector.
///  - **ECG-derived R-R** — [detectRPeaks] run over an ECG record (signal
///    `0x01`), which is the *reference* a researcher validates the watch
///    against. Same metrics, same artifact rules, so the two numbers are
///    genuinely comparable rather than comparable-looking.
///
/// Pure Dart, no Flutter, no BLE — every function here is a deterministic
/// transform over a sample list, which is what makes the spot-check testable.
///
/// **This is a research/validation tool, not a diagnostic.** Nothing here
/// classifies a rhythm or flags an arrhythmia; artifact handling deliberately
/// *discards* implausible beats rather than interpreting them.
library;

import 'dart:math' as math;

import 'signal_view.dart';

/// Physiological bounds for a usable R-R interval, in milliseconds
/// (300 ms = 200 bpm, 2000 ms = 30 bpm). Anything outside is a detector miss or
/// a double-count, not a heartbeat.
const double kMinRrMs = 300;
const double kMaxRrMs = 2000;

/// An R-R interval series with its artifact bookkeeping.
///
/// [rrMs] holds only the intervals that survived filtering. [rejected] is kept
/// because it is the quality signal for a spot check: RMSSD computed after
/// throwing away a third of the beats is not the same claim as RMSSD over a
/// clean trace, and the UI must be able to say so.
class RrSeries {
  const RrSeries({required this.rrMs, this.rejected = 0});

  /// Successive beat-to-beat intervals in milliseconds, in time order.
  final List<double> rrMs;

  /// Intervals dropped as physiologically implausible.
  final int rejected;

  int get beats => rrMs.isEmpty ? 0 : rrMs.length + 1;

  /// Fraction of candidate intervals discarded (0–1). Above ~0.05 the derived
  /// metrics should be treated as indicative only.
  double get artifactFraction {
    final total = rrMs.length + rejected;
    return total == 0 ? 0 : rejected / total;
  }

  /// Cumulative time of each interval's end, in milliseconds from the first
  /// detected beat — the x-axis of a tachogram.
  List<double> get timesMs {
    final out = <double>[];
    var t = 0.0;
    for (final rr in rrMs) {
      t += rr;
      out.add(t);
    }
    return out;
  }

  /// Drop implausible intervals.
  ///
  /// Two rules, both standard: an absolute physiological window, and a relative
  /// jump test against the last *accepted* interval (a missed beat doubles the
  /// interval, a double-count halves it — both show up as a large step, not as
  /// an out-of-range value). Comparing against the last accepted interval rather
  /// than the previous raw one stops a single artifact from dragging the
  /// reference along with it.
  factory RrSeries.filtered(Iterable<double> raw, {double maxJump = 0.2}) {
    final kept = <double>[];
    var rejected = 0;
    double? reference;
    for (final rr in raw) {
      if (!rr.isFinite || rr < kMinRrMs || rr > kMaxRrMs) {
        rejected++;
        continue;
      }
      if (reference != null && (rr - reference).abs() / reference > maxJump) {
        rejected++;
        continue;
      }
      kept.add(rr);
      reference = rr;
    }
    return RrSeries(rrMs: kept, rejected: rejected);
  }
}

/// Time-domain HRV metrics over an [RrSeries].
///
/// Time-domain only, on purpose: frequency-domain measures (LF/HF) need an
/// evenly resampled series and a much longer window than a spot check provides,
/// and reporting them off a 30-second strip would be a number with no meaning
/// behind it.
class HrvMetrics {
  const HrvMetrics({
    required this.beats,
    required this.meanRrMs,
    required this.meanHrBpm,
    required this.sdnnMs,
    required this.rmssdMs,
    required this.pnn50,
    required this.artifactFraction,
    required this.durationMs,
  });

  /// Beats behind the intervals used.
  final int beats;

  /// Mean R-R interval (ms).
  final double meanRrMs;

  /// Mean heart rate (bpm) derived from [meanRrMs].
  final double meanHrBpm;

  /// Standard deviation of R-R intervals (ms) — overall variability.
  final double sdnnMs;

  /// Root mean square of successive differences (ms) — short-term,
  /// parasympathetically mediated variability. The metric the watch's own
  /// stress score is built on, so it is the one a spot check is validating.
  final double rmssdMs;

  /// Proportion (0–1) of successive differences over 50 ms.
  final double pnn50;

  /// Fraction of candidate intervals discarded as artifacts (0–1).
  final double artifactFraction;

  /// Total span covered by the accepted intervals (ms).
  final double durationMs;

  /// True when there are too few clean beats for the numbers to mean anything.
  ///
  /// Reported rather than silently returning zeros: an RMSSD of 0 reads as
  /// "perfectly regular", which is the opposite of "we couldn't measure it".
  bool get isReliable => beats >= 20 && artifactFraction <= 0.2;

  static const HrvMetrics empty = HrvMetrics(
    beats: 0,
    meanRrMs: 0,
    meanHrBpm: 0,
    sdnnMs: 0,
    rmssdMs: 0,
    pnn50: 0,
    artifactFraction: 0,
    durationMs: 0,
  );

  factory HrvMetrics.from(RrSeries series) {
    final rr = series.rrMs;
    if (rr.length < 2) {
      return HrvMetrics.empty;
    }

    final mean = rr.reduce((a, b) => a + b) / rr.length;

    var sqSum = 0.0;
    for (final v in rr) {
      sqSum += (v - mean) * (v - mean);
    }
    // Sample standard deviation (n-1): the intervals are a sample of the
    // underlying rhythm, not the whole population of beats.
    final sdnn = math.sqrt(sqSum / (rr.length - 1));

    var diffSq = 0.0;
    var over50 = 0;
    for (var i = 1; i < rr.length; i++) {
      final d = rr[i] - rr[i - 1];
      diffSq += d * d;
      if (d.abs() > 50) over50++;
    }
    final n = rr.length - 1;
    final rmssd = math.sqrt(diffSq / n);

    return HrvMetrics(
      beats: series.beats,
      meanRrMs: mean,
      meanHrBpm: 60000 / mean,
      sdnnMs: sdnn,
      rmssdMs: rmssd,
      pnn50: over50 / n,
      artifactFraction: series.artifactFraction,
      durationMs: rr.reduce((a, b) => a + b),
    );
  }

  /// Convenience: filter then measure.
  factory HrvMetrics.fromRr(Iterable<double> rawRrMs) =>
      HrvMetrics.from(RrSeries.filtered(rawRrMs));
}

/// R-peak detection over a raw ECG channel, returning **sample indices**.
///
/// A compact Pan–Tompkins: bandpass → derivative → square → moving-window
/// integration → adaptive threshold, then a search back into the filtered trace
/// to place the peak on the true R deflection rather than on the integrator's
/// delayed lump.
///
/// The adaptive threshold (rather than a fixed fraction of the maximum) is what
/// makes this usable on a real wrist recording, where amplitude drifts with
/// contact pressure across a single 30-second strip.
List<int> detectRPeaks(List<double> ecg, {required int sampleRate}) {
  if (sampleRate <= 0 || ecg.length < sampleRate) return const [];

  // Bandpass ≈ 5–15 Hz, the band where QRS energy dominates P/T waves, baseline
  // wander and mains hum. Built from two moving averages rather than an IIR
  // design so it stays allocation-cheap and phase-symmetric (centred windows
  // introduce no lag, so detected indices need no delay compensation).
  final highPassed = detrend(ecg, window: (sampleRate ~/ 5).clamp(3, ecg.length));
  final band = _movingAverage(highPassed, (sampleRate ~/ 25).clamp(2, 15));

  // Derivative (slope) then square: emphasises the steep QRS upstroke and makes
  // everything positive.
  final n = band.length;
  final squared = List<double>.filled(n, 0);
  for (var i = 2; i < n - 2; i++) {
    final d = (2 * band[i + 1] + band[i + 2] - band[i - 2] - 2 * band[i - 1]) / 8;
    squared[i] = d * d;
  }

  // Moving-window integration over ~150 ms — about one QRS width, so each
  // complex becomes a single lump instead of several slope peaks.
  final win = (0.15 * sampleRate).round().clamp(3, n);
  final integrated = _movingAverage(squared, win);

  // Initialise the running peak/noise estimates from the first two seconds.
  final learn = math.min(2 * sampleRate, n);
  var spki = 0.0;
  var sum = 0.0;
  for (var i = 0; i < learn; i++) {
    spki = math.max(spki, integrated[i]);
    sum += integrated[i];
  }
  var npki = sum / learn;
  spki = math.max(spki * 0.25, npki * 2);
  double threshold() => npki + 0.25 * (spki - npki);

  // 250 ms refractory: no two beats can be closer, so a fragmented QRS cannot
  // register twice.
  final refractory = (0.25 * sampleRate).round().clamp(1, n);

  // Half-width of the search for the true R peak around an integrator lump.
  //
  // **Symmetric**, not the backward-only window of textbook Pan–Tompkins: that
  // window compensates for a *causal* integrator's group delay, and the moving
  // averages here are centred, so there is nothing to undo. It still has to be
  // generous — squaring spreads energy across the whole QRS, so the lump's own
  // maximum sits a few tens of milliseconds off the R spike.
  final searchHalf = (0.10 * sampleRate).round().clamp(1, n);

  // Lock the fiducial to one polarity for the whole record.
  //
  // Which deflection is largest depends on electrode orientation, so this picks
  // whichever the record actually shows and then stays with it. Refining on
  // `abs()` instead would let the R spike win on one beat and the S trough on
  // the next; the fiducial would hop by a QRS width and inject ~40 ms of pure
  // fiction into that beat's interval — an error the size of the RMSSD being
  // measured.
  var maxPos = 0.0, maxNeg = 0.0;
  for (final v in highPassed) {
    if (v > maxPos) maxPos = v;
    if (-v > maxNeg) maxNeg = -v;
  }
  final polarity = maxPos >= maxNeg ? 1.0 : -1.0;

  final peaks = <int>[];
  var i = 1;
  var lastPeak = -refractory;
  while (i < n - 1) {
    final v = integrated[i];
    // Local maximum of the integrated signal.
    if (v > integrated[i - 1] && v >= integrated[i + 1]) {
      if (v > threshold() && i - lastPeak >= refractory) {
        // Refine onto the true R deflection in the window that produced this
        // lump. Searched on the *high-passed* trace, not the band-passed one:
        // the extra smoothing that helps the energy detector also blunts and
        // shifts the spike it is trying to locate.
        final from = math.max(0, i - searchHalf);
        final to = math.min(n - 1, i + searchHalf);
        var best = from;
        var bestAmp = polarity * highPassed[from];
        for (var j = from; j <= to; j++) {
          final a = polarity * highPassed[j];
          if (a > bestAmp) {
            bestAmp = a;
            best = j;
          }
        }
        if (peaks.isEmpty || best - peaks.last >= refractory) {
          peaks.add(best);
          lastPeak = i;
        }
        spki = 0.125 * v + 0.875 * spki;
      } else {
        npki = 0.125 * v + 0.875 * npki;
      }
    }
    i++;
  }
  return peaks;
}

/// R-R intervals (ms) from detected peak indices at [sampleRate].
List<double> rrIntervalsMs(List<int> peaks, int sampleRate) {
  if (sampleRate <= 0 || peaks.length < 2) return const [];
  return [
    for (var i = 1; i < peaks.length; i++)
      (peaks[i] - peaks[i - 1]) * 1000 / sampleRate,
  ];
}

/// One-call ECG → HRV spot check: detect, interval, filter, measure.
({HrvMetrics metrics, RrSeries series, List<int> peaks}) hrvFromEcg(
  List<double> ecg, {
  required int sampleRate,
}) {
  final peaks = detectRPeaks(ecg, sampleRate: sampleRate);
  final series = RrSeries.filtered(rrIntervalsMs(peaks, sampleRate));
  return (metrics: HrvMetrics.from(series), series: series, peaks: peaks);
}

/// Centred moving average of [window] samples. Edges use the shorter window
/// actually available rather than padded values, matching [detrend].
List<double> _movingAverage(List<double> x, int window) {
  final n = x.length;
  if (n == 0) return const [];
  final half = (window ~/ 2).clamp(1, n);

  final prefix = List<double>.filled(n + 1, 0);
  for (var i = 0; i < n; i++) {
    prefix[i + 1] = prefix[i] + x[i];
  }

  final out = List<double>.filled(n, 0);
  for (var i = 0; i < n; i++) {
    final lo = (i - half).clamp(0, n);
    final hi = (i + half + 1).clamp(0, n);
    out[i] = (prefix[hi] - prefix[lo]) / (hi - lo);
  }
  return out;
}
