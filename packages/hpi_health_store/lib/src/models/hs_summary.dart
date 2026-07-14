// Copyright (c) 2026 ProtoCentral
// SPDX-License-Identifier: MIT

/// Typed view over the `SUMMARY` response — the device's own at-a-glance
/// baselines, and the one thing a client cannot recompute from the sample tier.
///
/// Keys are **pinned against the firmware** (`hpi_hs_mgmt.c`, `hs_h_summary`):
///
/// ```text
/// day  hr_rest  hr_min  hr_avg  hr_max  spo2_avg  spo2_min
/// temp_dev (x100)  temp_n
/// hrv (SDNN x10)  hrv_base (x10)
/// rmssd (x10)  rmssd_base (x10)  hrv_wins  stress_hrv  stress_hrv_v
/// steps  energy  stress
/// ```
///
/// Note the fixed-point scales differ per field — `temp_dev` is x100, the HRV
/// fields are x10, everything else is raw. The accessors below divide them out;
/// reading [raw] directly means doing that yourself.
///
/// Every read is defensive. The firmware's CBOR shapes have surprised us before
/// (a field that "should" be an int arriving as something else), and a summary
/// that throws would take a dashboard down over a cosmetic field.
///
/// Lives here rather than in the app because it is **protocol**, not
/// presentation: the `stress_hrv_v` rule below is a contract with the firmware,
/// and every client of this package needs it — not just the one app that
/// happened to implement it first.
class HsSummary {
  const HsSummary(this.raw);

  factory HsSummary.fromMap(Map<String, Object?> m) => HsSummary(m);

  /// The response exactly as the device sent it. Unknown keys are preserved:
  /// the registry is additive, and a client that drops what it doesn't
  /// recognise cannot be forward-compatible.
  final Map<String, Object?> raw;

  // --- HRV-derived stress (firmware P3) ---

  /// The HRV-derived stress score (0..100), or **null when the device has no
  /// score yet**.
  ///
  /// `stress_hrv_v == false` means *no score yet*, **not** *zero stress*. The
  /// firmware holds it invalid until roughly 20 valid 5-minute windows have
  /// built the user's personal baseline (about one decent night). A `0` shown
  /// there is a number the user would believe and that means nothing — it reads
  /// as "calm" when the truth is "we don't know you yet".
  ///
  /// This getter refuses to produce one. Callers must render
  /// "building your baseline" instead — see [isBuildingHrvBaseline].
  int? get stressHrv {
    if (_bool('stress_hrv_v') != true) return null;
    return _num('stress_hrv')?.round();
  }

  /// The device reports HRV stress but has no score **yet** — it is still
  /// building the baseline.
  ///
  /// Distinct from a device that never reports it at all (firmware predating
  /// P3), which returns false: that watch is not "still learning you", it never
  /// will. Collapsing the two loses the only difference that matters to the UI.
  bool get isBuildingHrvBaseline =>
      raw.containsKey('stress_hrv_v') && _bool('stress_hrv_v') != true;

  /// Today's mean RMSSD in ms (wire: `rmssd`, ms x10).
  double? get rmssdMs => _scaled('rmssd', 10);

  /// The user's 7-day rolling RMSSD baseline in ms (wire: `rmssd_base`, ms x10).
  double? get rmssdBaselineMs => _scaled('rmssd_base', 10);

  /// How many 5-minute windows back the baseline (wire: `hrv_wins`).
  int? get hrvWindows => _num('hrv_wins')?.round();

  // --- Heart rate ---

  /// Resting HR in bpm (wire: `hr_rest`).
  int? get restingHr => _num('hr_rest')?.round();

  /// Today's HR extremes and mean, in bpm. These come from the true epoch
  /// extremes on the device, so they are exact — unlike a peak recomputed from
  /// the `hr` sample series, which is a mean per minute and under-reports.
  int? get hrMin => _num('hr_min')?.round();
  int? get hrAvg => _num('hr_avg')?.round();
  int? get hrMax => _num('hr_max')?.round();

  // --- Everything else ---

  int? get spo2Avg => _num('spo2_avg')?.round();
  int? get spo2Min => _num('spo2_min')?.round();

  /// Skin-temp deviation from baseline, in °C (wire: `temp_dev`, x100).
  double? get tempDeviationC => _scaled('temp_dev', 100);

  /// Nights of data behind the skin-temp baseline (wire: `temp_n`).
  int? get tempBaselineNights => _num('temp_n')?.round();

  /// SDNN in ms (wire: `hrv`, ms x10) and its baseline (`hrv_base`, ms x10).
  double? get sdnnMs => _scaled('hrv', 10);
  double? get sdnnBaselineMs => _scaled('hrv_base', 10);

  int? get stepsToday => _num('steps')?.round();
  int? get energyTodayKcal => _num('energy')?.round();

  /// The **legacy** stress number: an EDA spot check scored on absolute skin
  /// conductance. Not comparable between people, or even between two sessions on
  /// the same person. Prefer [stressHrv]. (wire: `stress`)
  int? get stressLast => _num('stress')?.round();

  /// Start of the summarised day, UTC seconds (wire: `day`).
  int? get dayStartTs => _num('day')?.round();

  double? _scaled(String key, num scale) {
    final v = _num(key);
    return v == null ? null : v / scale;
  }

  num? _num(String key) {
    final v = raw[key];
    if (v is num) return v;
    if (v is String) return num.tryParse(v);
    return null;
  }

  bool? _bool(String key) {
    final v = raw[key];
    if (v is bool) return v;
    if (v is num) return v != 0; // tolerate 0/1 in place of a CBOR bool
    return null;
  }

  @override
  String toString() => 'HsSummary(${raw.length} keys)';
}
