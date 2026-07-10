import '../globals.dart';
import '../utils/database_helper.dart';

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
  final MetricTrend stress; // always unsupported in this build
  final MetricTrend eda; // always unsupported in this build
  final DateTime? lastSync;

  bool get anyData =>
      hr.hasData || spo2.hasData || temp.hasData || steps.hasData;
}

/// The single read path the redesigned screens use. Composes the existing
/// derived `health_trends` store (via [DatabaseHelper]) into typed view models,
/// and is the one place that decides data availability. It reads only; the write
/// side (legacy `BackgroundSyncManager` today, `HealthStoreSyncManager` later)
/// is unchanged.
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
    ]);
    return HomeDashboard(
      hr: results[0] as MetricTrend,
      spo2: results[1] as MetricTrend,
      temp: results[2] as MetricTrend,
      steps: results[3] as MetricTrend,
      stress: MetricTrend.unsupportedStress,
      eda: MetricTrend.unsupportedEda,
      lastSync: results[4] as DateTime?,
    );
  }

  /// Build a [MetricTrend] for one supported metric from today's hourly rows
  /// plus a 30-day baseline. [cumulative] metrics (steps) sum today's hourly
  /// values into the headline rather than taking the latest reading.
  Future<MetricTrend> _loadMetric(String key, {bool cumulative = false}) async {
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final hourly = await _db.getHourlyTrends(key, today);

    if (hourly.isEmpty) {
      return MetricTrend(key: key, availability: MetricAvailability.noData);
    }

    final spark = <double>[];
    DateTime? latestAt;
    double? minV, maxV;
    num sumForCumulative = 0;
    num latestReading = 0;

    for (final row in hourly) {
      final avg = _display(key, row['avg_value'] as num);
      final rmin = _display(key, row['min_value'] as num);
      final rmax = _display(key, row['max_value'] as num);
      spark.add(avg);
      minV = (minV == null) ? rmin : (rmin < minV ? rmin : minV);
      maxV = (maxV == null) ? rmax : (rmax > maxV ? rmax : maxV);
      sumForCumulative += rmax; // steps: hourly max, matching getLatestVitals
      latestReading = avg;
      latestAt = DateTime.fromMillisecondsSinceEpoch(
          (row['hour_start'] as int) * 1000,
          isUtc: false);
    }

    final headline =
        cumulative ? sumForCumulative.toDouble() : latestReading.toDouble();

    return MetricTrend(
      key: key,
      availability: MetricAvailability.available,
      latest: headline,
      latestAt: latestAt,
      min: minV,
      max: maxV,
      spark: spark,
      baseline: cumulative ? null : await _baseline(key),
    );
  }

  /// Load the full trend detail for one supported metric. Unsupported metrics
  /// (stress/eda) short-circuit to an unsupported detail so the screen renders a
  /// zero-state. All values are in display units.
  Future<MetricDetail> loadMetricDetail(String key) async {
    if (key == 'stress' || key == 'eda' || key == 'hrv') {
      return MetricDetail(key: key, availability: MetricAvailability.unsupported);
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
