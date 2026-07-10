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
