// Copyright (c) 2024-2026 ProtoCentral
// SPDX-License-Identifier: MIT

/// Presentation helpers for raw sensor traces.
///
/// Raw records off the watch are not plottable as-is. Wrist PPG is a large DC
/// pedestal with a pulsatile component well under 1% of it, and the first second
/// of any session is a settling transient an order of magnitude larger than
/// anything that follows. Autoscaling such a trace to its absolute min/max
/// spends the entire axis on the offset and the transient, and draws the actual
/// waveform as a flat line — the "recorded PPG plots as a straight line" report.
///
/// Neither helper here filters or edits samples destructively: [robustRange]
/// only chooses a *viewport*, and [detrend] is an additional derived series that
/// travels alongside the raw one. The raw counts stay the record of truth.
library;

import 'dart:math' as math;

/// A robust y-window for [values]: median ± [k] × MAD, padded by 8% so the
/// extremes aren't flush against the frame.
///
/// **Why MAD and not a percentile clip.** The contaminating feature here is a
/// *contiguous block* — roughly a second of sensor settling — not scattered
/// spikes. In a 25-second record that block is ~4% of the samples, so a 2/98
/// percentile band still lands inside it and the window stays ~20 000 counts
/// wide for a 120-count waveform. Median absolute deviation doesn't care how
/// many samples the excursion spans, only that it is under half of them.
///
/// The window is intersected with the real data extent, so it never opens empty
/// space beyond what was measured. Callers must clamp when mapping: by
/// construction some samples fall outside the band, and an excursion should read
/// as pinned to the edge rather than vanishing off-canvas.
({double lo, double hi}) robustRange(Iterable<double> values, {double k = 4}) {
  final sorted = values.where((v) => v.isFinite).toList()..sort();
  if (sorted.isEmpty) return (lo: -1, hi: 1);

  final dataLo = sorted.first;
  final dataHi = sorted.last;
  double median(List<double> s) => s[s.length ~/ 2];

  final m = median(sorted);
  final mad = median(sorted.map((v) => (v - m).abs()).toList()..sort());

  double lo, hi;
  if (mad > 0) {
    lo = math.max(m - k * mad, dataLo);
    hi = math.min(m + k * mad, dataHi);
  } else {
    // MAD collapses when over half the samples share one value — a flat trace,
    // or a short series. Fall back to the full extent.
    lo = dataLo;
    hi = dataHi;
  }
  if ((hi - lo).abs() < 1e-9) return (lo: lo - 1, hi: hi + 1);

  final pad = (hi - lo) * 0.08;
  return (lo: lo - pad, hi: hi + pad);
}

/// Subtract a centred moving average of [window] samples — a cheap high-pass
/// that removes the DC pedestal and slow baseline wander while leaving the
/// pulsatile shape intact.
///
/// Runs on a prefix sum, so it stays O(n) over a session with tens of thousands
/// of samples. Edges use the shorter window actually available rather than
/// padding, which would fabricate samples that were never measured.
List<double> detrend(List<double> x, {required int window}) {
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
    out[i] = x[i] - (prefix[hi] - prefix[lo]) / (hi - lo);
  }
  return out;
}
