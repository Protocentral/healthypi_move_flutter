// Copyright (c) 2024-2026 ProtoCentral
// SPDX-License-Identifier: MIT

import '../globals.dart';
import 'package:healthypi_healthy_store/healthypi_healthy_store.dart';
import '../utils/database_helper.dart';
import '../utils/device_manager.dart';

/// Whether a metric can be shown, and if not, why. Drives the redesign's
/// honest zero-states (docs/REDESIGN_PLAN.md): the UI never fabricates a value.
enum MetricAvailability {
  /// Real data exists and is shown.
  available,

  /// The metric is supported end-to-end but no rows have synced yet.
  /// UI: a "Sync your watch" placeholder.
  noData,

  /// The metric has no producing code in this build (HRV/stress/EDA and the
  /// derived analytics they need). UI: an explanatory zero-state, e.g. EDA's
  /// "Measure on watch" — never a made-up number.
  unsupported,

  /// The device produces this metric but has no score *yet*: it is still
  /// building the user's personal baseline. UI: "Building your baseline",
  /// **never a zero**.
  ///
  /// This exists because HRV stress is scored against the user's own rolling
  /// RMSSD baseline, which takes ~20 valid 5-minute windows (realistically one
  /// decent night) to establish. Until then the firmware reports
  /// `stress_hrv_v == false`, and a 0 rendered there is a number the user would
  /// believe and that means nothing — it is not "calm". Collapsing this into
  /// [noData] would lose the distinction between "sync your watch" and "your
  /// watch is still learning you".
  baselining,
}

/// A metric's dashboard view: headline value, today's sparkline series, and an
/// optional 30-day baseline. Values are in each metric's stored display unit
/// (temp already divided out of centi-degrees; HR/SpO₂/steps raw).
class MetricTrend {
  const MetricTrend({
    required this.key,
    required this.availability,
    this.latest,
    this.latestAt,
    this.min,
    this.max,
    this.spark = const [],
    this.baseline,
  });

  final String key; // hPi4Global.PREFIX_*
  final MetricAvailability availability;
  final double? latest;
  final DateTime? latestAt;
  final double? min;
  final double? max;

  /// Today's hourly values (chronological) for the mini sparkline/bars.
  final List<double> spark;

  /// 30-day rolling baseline (median of daily averages) in display units, or
  /// null when there aren't enough days yet.
  final double? baseline;

  bool get hasData => availability == MetricAvailability.available;

  /// Signed deviation of [latest] from [baseline], or null if either is absent.
  double? get baselineDelta =>
      (latest != null && baseline != null) ? latest! - baseline! : null;

  static const MetricTrend unsupportedStress =
      MetricTrend(key: 'stress', availability: MetricAvailability.unsupported);
  static const MetricTrend unsupportedEda =
      MetricTrend(key: 'eda', availability: MetricAvailability.unsupported);
}

/// One aggregated point in a trend series (hour or day), in display units.
class TrendPoint {
  const TrendPoint(
      {required this.t, required this.min, required this.max, required this.avg});
  final DateTime t;
  final double min;
  final double max;
  final double avg;
}

/// A named time range for the trend detail's segmented control.
enum TrendRange { day, week, month, sixMonths }

/// Everything a trend-detail screen (1d/3a–3d) needs for one metric: headline
/// stats plus the day/week/month series, all in display units. [availability]
/// tells the screen whether to render charts or an honest zero-state.
class MetricDetail {
  const MetricDetail({
    required this.key,
    required this.availability,
    this.latest,
    this.latestAt,
    this.min,
    this.max,
    this.avg,
    this.baseline,
    this.daily = const [],
    this.weekly = const [],
    this.monthly = const [],
  });

  final String key;
  final MetricAvailability availability;
  final double? latest;
  final DateTime? latestAt;
  final double? min;
  final double? max;
  final double? avg;
  final double? baseline;
  final List<TrendPoint> daily; // today, hourly
  final List<TrendPoint> weekly; // last 7 days
  final List<TrendPoint> monthly; // current month, daily

  bool get hasData => availability == MetricAvailability.available;

  List<TrendPoint> series(TrendRange r) {
    switch (r) {
      case TrendRange.day:
        return daily;
      case TrendRange.week:
        return weekly;
      case TrendRange.month:
      case TrendRange.sixMonths:
        return monthly; // 30-day retention caps the real window at ~a month
    }
  }
}

/// Everything the home dashboard (2a / 1a) needs, in one aggregate so the screen
/// makes a single call. Metrics with no producing code are reported as
/// [MetricAvailability.unsupported] rather than omitted, so the layout is stable.
class HomeDashboard {
  const HomeDashboard({
    required this.hr,
    required this.spo2,
    required this.temp,
    required this.steps,
    required this.stress,
    required this.eda,
    this.lastSync,
  });

  final MetricTrend hr;
  final MetricTrend spo2;
  final MetricTrend temp;
  final MetricTrend steps;
  final MetricTrend stress; // HRV-derived continuous score from SUMMARY
  final MetricTrend eda; // manual EDA spot-check stress (or unsupported)
  final DateTime? lastSync;

  bool get anyData =>
      hr.hasData ||
      spo2.hasData ||
      temp.hasData ||
      steps.hasData ||
      stress.hasData;
}

/// One manual EDA / GSR spot check, derived from the MANUAL-bit `stress`
/// samples (`PREFIX_STRESS_EDA`).
class EdaSpotCheck {
  const EdaSpotCheck({required this.at, required this.score});
  final DateTime at;
  final double score;
}

/// Everything the Stress & EDA screen needs in one load.
class StressEdaView {
  const StressEdaView({
    required this.stress,
    required this.hrv,
    required this.spotChecks,
    this.rmssdBaselineMs,
    this.hrvWindows,
  });

  /// Continuous HRV-derived stress (SUMMARY headline + trend samples).
  final MetricTrend stress;

  /// Today's continuous stress series for a sparkline (may be empty).
  final MetricDetail hrv;

  /// Recent manual EDA spot checks (stress_eda), newest first.
  final List<EdaSpotCheck> spotChecks;

  /// User's 7-day RMSSD baseline in ms, when known.
  final double? rmssdBaselineMs;

  /// How many 5-min windows back the stress baseline.
  final int? hrvWindows;
}

/// One blood-pressure spot reading — a paired systolic/diastolic estimate the
/// watch produced from finger PPG after calibration. An `HsClass.event`: a
/// discrete timestamped reading, never averaged into a per-hour value.
class BpReading {
  const BpReading({
    required this.at,
    required this.systolic,
    required this.diastolic,
    this.quality,
  });

  final DateTime at;
  final int systolic;
  final int diastolic;

  /// Firmware quality byte for the reading, when present (contact/confidence).
  final int? quality;
}

/// Everything the Blood-pressure screen (6a/6b) needs in one load. BP is gated
/// on calibration state: 6a renders only when [isCalibrated] **and** there is
/// at least one reading; otherwise the screen shows the 6b not-calibrated gate.
/// It never fabricates a value — no readings means no numbers.
class BloodPressureView {
  const BloodPressureView({this.calibratedAt, this.readings = const []});

  /// When BPT calibration last completed (persisted on 5b's completion), or null
  /// if the watch has never been calibrated on this phone.
  final DateTime? calibratedAt;

  /// Spot readings, newest first.
  final List<BpReading> readings;

  bool get isCalibrated => calibratedAt != null;
  bool get hasReadings => readings.isNotEmpty;

  /// True → render 6a; false → render 6b.
  bool get showValues => isCalibrated && hasReadings;

  BpReading? get latest => readings.isEmpty ? null : readings.first;

  /// Readings within [range] of now (for the segmented chart window).
  List<BpReading> inRange(TrendRange range) {
    final cutoff = switch (range) {
      TrendRange.day => const Duration(days: 1),
      TrendRange.week => const Duration(days: 7),
      TrendRange.month => const Duration(days: 31),
      TrendRange.sixMonths => const Duration(days: 183),
    };
    final since = DateTime.now().subtract(cutoff);
    return readings.where((r) => r.at.isAfter(since)).toList();
  }
}

/// The single read path the redesigned screens use. Composes the existing
/// derived `health_trends` store (via [DatabaseHelper]) into typed view models,
/// and is the one place that decides data availability. It reads only; the write
/// side (`HealthyStoreSyncManager`, which derives `health_trends` from the raw
/// `hs_samples` store) is unchanged.
class HealthRepository {
  HealthRepository({DatabaseHelper? db})
      : _db = db ?? DatabaseHelper.instance;

  final DatabaseHelper _db;

  /// Metrics stored in centi-units — divided by 100 for display, matching
  /// scr_skin_temp.dart. HR/SpO₂/steps are stored raw.
  static const Set<String> _centiMetrics = {hPi4Global.PREFIX_TEMP};

  double _display(String key, num stored) =>
      _centiMetrics.contains(key) ? stored / 100.0 : stored.toDouble();

  Future<HomeDashboard> loadHome() async {
    final results = await Future.wait([
      _loadMetric(hPi4Global.PREFIX_HR),
      _loadMetric(hPi4Global.PREFIX_SPO2),
      _loadMetric(hPi4Global.PREFIX_TEMP),
      _loadMetric(hPi4Global.PREFIX_ACTIVITY, cumulative: true),
      _db.getLastSyncTime(),
      _loadHrvStress(),
      _loadEdaSpotMetric(),
    ]);
    return HomeDashboard(
      hr: results[0] as MetricTrend,
      spo2: results[1] as MetricTrend,
      temp: results[2] as MetricTrend,
      steps: results[3] as MetricTrend,
      stress: results[5] as MetricTrend,
      eda: results[6] as MetricTrend,
      lastSync: results[4] as DateTime?,
    );
  }

  /// Full Stress & EDA screen payload: SUMMARY stress + continuous series +
  /// recent manual EDA spot checks.
  Future<StressEdaView> loadStressEda() async {
    final results = await Future.wait([
      _loadHrvStress(),
      loadMetricDetail(hPi4Global.PREFIX_STRESS),
      _loadEdaSpotChecks(limit: 12),
      _db.latestHsSummary(),
    ]);
    final stress = results[0] as MetricTrend;
    final detail = results[1] as MetricDetail;
    final spots = results[2] as List<EdaSpotCheck>;
    final raw = results[3] as Map<String, Object?>?;
    final summary = raw == null ? null : HsSummary.fromMap(raw);
    return StressEdaView(
      stress: stress,
      hrv: detail,
      spotChecks: spots,
      rmssdBaselineMs: summary?.rmssdBaselineMs ?? stress.baseline,
      hrvWindows: summary?.hrvWindows,
    );
  }

  /// `app_metadata` key holding the last BPT-calibration completion time. Set by
  /// the calibration screen (5b) on success; read here to gate the BP screen.
  static const String bpCalibratedAtKey = 'bp_calibrated_at';

  /// Full Blood-pressure screen payload (6a/6b): calibration state + the recent
  /// event-class BP spot readings. Returns an un-calibrated view (→ 6b) when the
  /// watch has never calibrated or no readings have synced — never a fake value.
  Future<BloodPressureView> loadBloodPressure() async {
    final calAt = await _db.getMetadata<DateTime>(bpCalibratedAtKey);
    final device = (await DeviceManager.getPairedDevice())?.macAddress;
    final rows =
        device == null ? const <Map<String, Object?>>[] : await _db.getBpReadings(device);
    final readings = rows
        .map((r) => BpReading(
              // ts_utc is epoch seconds UTC; show in local time like other cards.
              at: DateTime.fromMillisecondsSinceEpoch((r['ts'] as int) * 1000,
                      isUtc: true)
                  .toLocal(),
              systolic: (r['sys'] as num).round(),
              diastolic: (r['dia'] as num).round(),
              quality: (r['quality'] as num?)?.toInt(),
            ))
        .toList();
    return BloodPressureView(calibratedAt: calAt, readings: readings);
  }

  /// Latest manual EDA spot-check metric for the home / trends cards.
  Future<MetricTrend> _loadEdaSpotMetric() async {
    final latest =
        await _db.getLatestHourlyTrend(hPi4Global.PREFIX_STRESS_EDA, withinDays: 30);
    if (latest == null) {
      // EDA remains a manual action — no samples means "measure on watch",
      // not "unsupported firmware". Use noData once we know HPI_HS works;
      // fall back to unsupported only when we have never synced anything.
      final lastSync = await _db.getLastSyncTime();
      if (lastSync == null) return MetricTrend.unsupportedEda;
      return const MetricTrend(
          key: 'eda', availability: MetricAvailability.noData);
    }
    final score = (latest['avg_value'] as num).toDouble();
    final at = DateTime.fromMillisecondsSinceEpoch(
        (latest['hour_start'] as int) * 1000,
        isUtc: false);
    return MetricTrend(
      key: 'eda',
      availability: MetricAvailability.available,
      latest: score,
      latestAt: at,
    );
  }

  Future<List<EdaSpotCheck>> _loadEdaSpotChecks({int limit = 12}) async {
    // Walk recent days of derived hourly stress_eda rows and flatten to
    // individual spot-check-like points (one per hour that has a reading).
    final now = DateTime.now();
    final checks = <EdaSpotCheck>[];
    for (var back = 0; back < 14 && checks.length < limit; back++) {
      final day = DateTime(now.year, now.month, now.day)
          .subtract(Duration(days: back));
      final hourly =
          await _db.getHourlyTrends(hPi4Global.PREFIX_STRESS_EDA, day);
      for (final row in hourly.reversed) {
        checks.add(EdaSpotCheck(
          at: DateTime.fromMillisecondsSinceEpoch(
              (row['hour_start'] as int) * 1000,
              isUtc: false),
          score: (row['avg_value'] as num).toDouble(),
        ));
        if (checks.length >= limit) break;
      }
    }
    return checks;
  }

  /// Stress, read from the device's own `SUMMARY` rather than derived here.
  ///
  /// Prefer the continuous HRV score over the legacy EDA one: it needs no user
  /// action (the EDA spot check needs 30 deliberate seconds), and it is scored
  /// against the user's *own* rolling RMSSD baseline rather than an absolute
  /// skin-conductance scale, which is not comparable between people or even
  /// between two sessions on one person. Handoff §6.
  ///
  /// The three outcomes are deliberately distinct, and collapsing any two of
  /// them would put a misleading number on screen:
  ///  - a score            → [MetricAvailability.available]
  ///  - `stress_hrv_v` false → [MetricAvailability.baselining] ("still learning
  ///    you"), **never 0**
  ///  - key absent entirely  → [MetricAvailability.unsupported] (pre-P3 firmware)
  Future<MetricTrend> _loadHrvStress() async {
    final raw = await _db.latestHsSummary();
    if (raw == null) return MetricTrend.unsupportedStress;

    final summary = HsSummary.fromMap(raw);
    final score = summary.stressHrv;
    if (score != null) {
      return MetricTrend(
        key: hPi4Global.PREFIX_STRESS,
        availability: MetricAvailability.available,
        latest: score.toDouble(),
        baseline: summary.rmssdBaselineMs,
      );
    }
    if (summary.isBuildingHrvBaseline) {
      return const MetricTrend(
        key: hPi4Global.PREFIX_STRESS,
        availability: MetricAvailability.baselining,
      );
    }
    return MetricTrend.unsupportedStress;
  }

  /// Build a [MetricTrend] for one supported metric from today's hourly rows
  /// plus a 30-day baseline. [cumulative] metrics (steps) sum today's hourly
  /// values into the headline rather than taking the latest reading.
  Future<MetricTrend> _loadMetric(String key, {bool cumulative = false}) async {
    if (cumulative) return _loadCumulative(key);

    // A rolling 24-hour window, not a calendar day. "Today" goes blank at 00:05,
    // and on a device whose newest data predates midnight it shows nothing at all
    // even though there is plenty of recent data to draw.
    final recent = await _db.getRecentHourlyTrends(key, hours: 24);

    // The headline is the last reading we have, even if it's older than the
    // window — better to show "98% · 6 h ago" than an empty card.
    final latestRow = await _db.getLatestHourlyTrend(key, withinDays: 7);
    if (recent.isEmpty && latestRow == null) {
      return MetricTrend(key: key, availability: MetricAvailability.noData);
    }

    final spark = <double>[];
    double? minV, maxV;
    for (final row in recent) {
      final avg = _display(key, row['avg_value'] as num);
      final rmin = _display(key, row['min_value'] as num);
      final rmax = _display(key, row['max_value'] as num);
      spark.add(avg);
      minV = (minV == null || rmin < minV) ? rmin : minV;
      maxV = (maxV == null || rmax > maxV) ? rmax : maxV;
    }

    double? latest;
    DateTime? latestAt;
    if (latestRow != null) {
      latest = _display(key, latestRow['avg_value'] as num);
      latestAt = DateTime.fromMillisecondsSinceEpoch(
          (latestRow['hour_start'] as int) * 1000,
          isUtc: false);
      // Window empty but a recent reading exists: still show min/max from it.
      minV ??= _display(key, latestRow['min_value'] as num);
      maxV ??= _display(key, latestRow['max_value'] as num);
    }

    return MetricTrend(
      key: key,
      availability: MetricAvailability.available,
      latest: latest,
      latestAt: latestAt,
      min: minV,
      max: maxV,
      spark: spark,
      baseline: await _baseline(key),
    );
  }

  /// Cumulative metrics (steps) headline the **day's total**, so they need a
  /// calendar day rather than a rolling window.
  ///
  /// If today has no data yet, fall back to the most recent day that does. A
  /// bare "0 steps" would be a claim we can't support — it reads as "you walked
  /// nowhere", when the truth is "we have nothing for today".
  Future<MetricTrend> _loadCumulative(String key) async {
    final now = DateTime.now();
    final midnight = DateTime(now.year, now.month, now.day);

    List<Map<String, dynamic>> hourly = const [];
    DateTime day = midnight;
    for (var back = 0; back <= 7; back++) {
      day = midnight.subtract(Duration(days: back));
      hourly = await _db.getHourlyTrends(key, day);
      if (hourly.isNotEmpty) break;
    }
    if (hourly.isEmpty) {
      return MetricTrend(key: key, availability: MetricAvailability.noData);
    }

    // Derived rows hold each hour's INCREMENT (deriveTrends differences the
    // device's running counter), so the day's total is their sum.
    final spark = <double>[];
    num total = 0;
    DateTime? latestAt;
    for (final row in hourly) {
      final v = _display(key, row['max_value'] as num);
      spark.add(v);
      total += v;
      latestAt = DateTime.fromMillisecondsSinceEpoch(
          (row['hour_start'] as int) * 1000,
          isUtc: false);
    }

    return MetricTrend(
      key: key,
      availability: MetricAvailability.available,
      latest: total.toDouble(),
      latestAt: latestAt,
      min: null,
      max: null,
      spark: spark,
      baseline: null,
    );
  }

  /// Load the full trend detail for one metric. All values are in display units.
  ///
  /// `stress` and `hrv` are derived into `health_trends` from the sample stream
  /// (continuous HRV RMSSD, and the non-MANUAL `stress` samples). For stress,
  /// when the derived series is empty we still honour SUMMARY baselining so the
  /// detail screen never shows a fake 0 while the watch is learning the user.
  ///
  /// EDA (`eda`) maps to the manual `stress_eda` trend (MANUAL-bit spot checks).
  Future<MetricDetail> loadMetricDetail(String key) async {
    if (key == 'eda') {
      // Reuse the stress_eda derived rows under the UI key "eda".
      final detail =
          await loadMetricDetail(hPi4Global.PREFIX_STRESS_EDA);
      if (detail.availability == MetricAvailability.noData) {
        final lastSync = await _db.getLastSyncTime();
        if (lastSync == null) {
          return const MetricDetail(
              key: 'eda', availability: MetricAvailability.unsupported);
        }
      }
      return MetricDetail(
        key: 'eda',
        availability: detail.availability,
        latest: detail.latest,
        latestAt: detail.latestAt,
        min: detail.min,
        max: detail.max,
        avg: detail.avg,
        baseline: detail.baseline,
        daily: detail.daily,
        weekly: detail.weekly,
        monthly: detail.monthly,
      );
    }
    if (key == hPi4Global.PREFIX_STRESS_EDA) {
      // Fall through to the generic loader with the real trend key.
    }
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final results = await Future.wait([
      _db.getHourlyTrends(key, today),
      _db.getWeeklyTrends(key, now.subtract(const Duration(days: 6))),
      _db.getMonthlyTrends(key, now.year, now.month),
    ]);

    List<TrendPoint> map(List<Map<String, dynamic>> rows, String tsCol) => rows
        .map((r) => TrendPoint(
              t: DateTime.fromMillisecondsSinceEpoch(
                  (r[tsCol] as int) * 1000,
                  isUtc: false),
              min: _display(key, r['min_value'] as num),
              max: _display(key, r['max_value'] as num),
              avg: _display(key, r['avg_value'] as num),
            ))
        .toList();

    final daily = map(results[0], 'hour_start');
    final weekly = map(results[1], 'day_start');
    final monthly = map(results[2], 'day_start');

    if (daily.isEmpty && weekly.isEmpty && monthly.isEmpty) {
      // Stress: prefer SUMMARY baselining over a blank "no data" when the
      // watch is still learning the user's RMSSD baseline.
      if (key == hPi4Global.PREFIX_STRESS) {
        final headline = await _loadHrvStress();
        if (headline.availability == MetricAvailability.baselining) {
          return const MetricDetail(
              key: hPi4Global.PREFIX_STRESS,
              availability: MetricAvailability.baselining);
        }
        if (headline.availability == MetricAvailability.available &&
            headline.latest != null) {
          return MetricDetail(
            key: hPi4Global.PREFIX_STRESS,
            availability: MetricAvailability.available,
            latest: headline.latest,
            baseline: headline.baseline,
          );
        }
        if (headline.availability == MetricAvailability.unsupported) {
          return const MetricDetail(
              key: hPi4Global.PREFIX_STRESS,
              availability: MetricAvailability.unsupported);
        }
      }
      return MetricDetail(key: key, availability: MetricAvailability.noData);
    }

    final cumulative = key == hPi4Global.PREFIX_ACTIVITY;
    double? minV, maxV, avgV, latest;
    DateTime? latestAt;
    if (daily.isNotEmpty) {
      minV = daily.map((p) => p.min).reduce((a, b) => a < b ? a : b);
      maxV = daily.map((p) => p.max).reduce((a, b) => a > b ? a : b);
      avgV = daily.map((p) => p.avg).reduce((a, b) => a + b) / daily.length;
      latest = cumulative
          ? daily.map((p) => p.max).reduce((a, b) => a + b)
          : daily.last.avg;
      latestAt = daily.last.t;
    }

    return MetricDetail(
      key: key,
      availability: MetricAvailability.available,
      latest: latest,
      latestAt: latestAt,
      min: minV,
      max: maxV,
      avg: avgV,
      baseline: cumulative ? null : await _baseline(key),
      daily: daily,
      weekly: weekly,
      monthly: monthly,
    );
  }

  /// 30-day rolling baseline: the median of daily averages. Null until at least
  /// a week of days exist, so the UI can hide "vs baseline" affordances honestly
  /// rather than compare against one noisy day.
  Future<double?> _baseline(String key) async {
    final daily = await _db.getDailyAveragesSince(key, days: 30);
    if (daily.length < 7) return null;
    final avgs = daily
        .map((r) => _display(key, r['avg'] as num))
        .toList()
      ..sort();
    return avgs[avgs.length ~/ 2];
  }
}
