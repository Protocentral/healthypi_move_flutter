/// A single at-a-glance summary metric (one dashboard card).
class HsSummaryCard {
  const HsSummaryCard({required this.label, required this.value, this.unit});
  final String label;
  final String value;
  final String? unit;
}

/// Typed view over the HPI_HS `SUMMARY` response.
///
/// The exact CBOR keys of `struct hpi_hs_summary` are not fully pinned in the
/// public contract, so this maps a set of **candidate keys** to friendly labels
/// and renders every other key generically — it never assumes a fixed shape.
/// Nested maps (e.g. an `hr` sub-map) are flattened one level.
class HsSummary {
  const HsSummary(this.cards, this.raw);

  final List<HsSummaryCard> cards;
  final Map<String, Object?> raw;

  /// Known keys → (label, unit). Also used to prettify nested `parent.child`.
  static const Map<String, (String, String?)> _labels = {
    'resting_hr': ('Resting HR', 'bpm'),
    'rest_hr': ('Resting HR', 'bpm'),
    'hr_min': ('HR min', 'bpm'),
    'hr_avg': ('HR avg', 'bpm'),
    'hr_mean': ('HR avg', 'bpm'),
    'hr_max': ('HR max', 'bpm'),
    'spo2': ('SpO₂', '%'),
    'spo2_avg': ('SpO₂ (overnight)', '%'),
    'spo2_overnight': ('SpO₂ (overnight)', '%'),
    'skin_temp': ('Skin temp', '°C'),
    'temp_delta': ('Temp Δ', '°C'),
    'temp_dev': ('Temp Δ', '°C'),
    'temp_nights': ('Temp baseline nights', null),
    'hrv': ('HRV', 'ms'),
    'hrv_sdnn': ('HRV SDNN', 'ms'),
    'hrv_rmssd': ('HRV RMSSD', 'ms'),
    'steps': ('Steps', null),
    'energy': ('Active energy', 'kcal'),
    'active_energy': ('Active energy', 'kcal'),
    'stress': ('Stress', null),
    'last_stress': ('Last stress', null),
    // Firmware P3 (continuous HRV + HRV-derived stress).
    'rmssd': ('HRV RMSSD (today)', 'ms'),
    'rmssd_base': ('HRV baseline (7-day)', 'ms'),
    'hrv_wins': ('HRV windows', null),
    'stress_hrv': ('Stress (HRV)', null),
    'stress_hrv_v': ('Stress (HRV) valid', null),
    'dev': ('Device', null),
    'ts': ('Timestamp', null),
    'day': ('Day', null),
  };

  /// The HRV-derived stress score (0..100), or **null when the device has no
  /// score yet**.
  ///
  /// `stress_hrv_v == false` means *no score yet*, not *zero stress* — the
  /// firmware holds it invalid until ~20 valid 5-minute windows (~100 min of
  /// still, on-skin HRV) have built the user's personal baseline. Rendering a 0
  /// there would put a number on screen that the user would believe and that
  /// means nothing. This getter refuses to produce one; callers must show
  /// "building your baseline" instead. Handoff §6: *"the single most important
  /// line in this section"*.
  int? get stressHrv {
    if (_bool('stress_hrv_v') != true) return null;
    return _num('stress_hrv')?.round();
  }

  /// True when the device is still accumulating windows for the HRV baseline —
  /// i.e. HRV stress is supported but has no score *yet*. Distinct from a device
  /// that never reports it at all (old firmware), which returns false.
  bool get isBuildingHrvBaseline =>
      raw.containsKey('stress_hrv_v') && _bool('stress_hrv_v') != true;

  /// Today's mean RMSSD in ms (`rmssd` is sent as ms×10).
  double? get rmssdMs => _scaled('rmssd', 10);

  /// The user's 7-day rolling RMSSD baseline in ms (sent as ms×10).
  double? get rmssdBaselineMs => _scaled('rmssd_base', 10);

  /// How many 5-minute windows back the baseline.
  int? get hrvWindows => _num('hrv_wins')?.round();

  double? _scaled(String key, num scale) {
    final v = _num(key);
    return v == null ? null : v / scale;
  }

  /// Defensive: the firmware's CBOR shapes are not fully pinned, and a field
  /// that "should" be an int has shown up as something else before.
  num? _num(String key) {
    final v = raw[key];
    if (v is num) return v;
    if (v is String) return num.tryParse(v);
    return null;
  }

  bool? _bool(String key) {
    final v = raw[key];
    if (v is bool) return v;
    if (v is num) return v != 0; // some firmwares send 0/1
    return null;
  }

  factory HsSummary.fromMap(Map<String, Object?> m) {
    final cards = <HsSummaryCard>[];

    void add(String key, Object? value) {
      if (value == null) return;
      if (value is Map) {
        // Flatten one level: key.child
        value.forEach((k, v) => add('$key.$k', v));
        return;
      }
      final base = key.contains('.') ? key.split('.').last : key;
      final match = _labels[key] ?? _labels[base];
      final label = match?.$1 ?? _humanize(key);
      final unit = match?.$2;
      cards.add(HsSummaryCard(
        label: label,
        value: _fmt(value),
        unit: unit,
      ));
    }

    m.forEach(add);
    return HsSummary(cards, m);
  }

  static String _fmt(Object? v) {
    if (v is double) {
      return v == v.roundToDouble() ? v.toStringAsFixed(0) : v.toStringAsFixed(2);
    }
    if (v is List) return '[${v.length}]';
    return '$v';
  }

  static String _humanize(String key) {
    final s = key.replaceAll('_', ' ').replaceAll('.', ' · ');
    return s.isEmpty ? key : s[0].toUpperCase() + s.substring(1);
  }
}
