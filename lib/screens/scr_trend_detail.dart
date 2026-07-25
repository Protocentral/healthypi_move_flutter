// Copyright (c) 2024-2026 ProtoCentral
// SPDX-License-Identifier: MIT

import 'dart:io';

import 'package:csv/csv.dart';
import 'package:flutter/material.dart';
import 'package:material_symbols_icons/symbols.dart';
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';

import '../data/health_repository.dart';
import '../globals.dart';
import '../theme/hpi_colors.dart';
import '../theme/hpi_text.dart';
import '../ui/charts/hpi_sparkline.dart';
import '../ui/charts/hpi_trend_charts.dart';
import '../ui/components/hpi_components.dart';

/// Per-metric visual identity for the trend screens.
class TrendMetricStyle {
  const TrendMetricStyle(this.icon, this.color, this.title, this.unit);
  final IconData icon;
  final Color color;
  final String title;
  final String unit;

  static TrendMetricStyle of(String key) {
    switch (key) {
      case 'hr':
        return const TrendMetricStyle(
            Symbols.favorite, HpiColors.hr, 'Heart rate', 'bpm');
      case 'spo2':
        return const TrendMetricStyle(
            Symbols.spo2, HpiColors.spo2, 'SpO₂', '%');
      case 'temp':
        return const TrendMetricStyle(
            Symbols.device_thermostat, HpiColors.temp, 'Wrist temp', '°');
      case 'activity':
        return const TrendMetricStyle(
            Symbols.steps, HpiColors.steps, 'Steps', '');
      case 'hrv':
        // RMSSD, in whole ms — the short-window parasympathetic marker the
        // stress score is built on (handoff §6.4).
        return const TrendMetricStyle(
            Symbols.ecg_heart, HpiColors.stress, 'HRV (RMSSD)', 'ms');
      case 'stress':
        // The continuous, HRV-derived 0..100 score, not the EDA spot check.
        return const TrendMetricStyle(
            Symbols.self_improvement, HpiColors.stress, 'Stress', '');
      default:
        return const TrendMetricStyle(
            Symbols.monitoring, HpiColors.hr, 'Trend', '');
    }
  }
}

/// The redesigned trend detail (handoff 1d/3a Heart rate, 3b Steps, 3c SpO₂,
/// 3d Wrist temp), body-only so it embeds in the tablet two-pane (4a) right
/// pane, a compact pushed route ([TrendDetailScreen]), and the Trends hub.
/// Charts render from real `health_trends` data; HR also hosts the continuous
/// HRV (RMSSD) card when samples exist.
class TrendDetailView extends StatefulWidget {
  const TrendDetailView({
    super.key,
    required this.metricKey,
    this.showHeader = true,
  });

  final String metricKey;

  /// Show the inline icon+title+share header (tablet pane / hub). A compact
  /// pushed route sets this false and supplies its own app bar instead.
  final bool showHeader;

  @override
  State<TrendDetailView> createState() => TrendDetailViewState();
}

/// Public so the pushed route ([TrendDetailScreen]) can drive [exportCsv] from
/// its app-bar action — the selected range and loaded detail live here, not in
/// the wrapper.
class TrendDetailViewState extends State<TrendDetailView> {
  MetricDetail? _detail;

  /// HRV rides along on the HR screen (handoff 3a) — it is a second metric, so
  /// it needs its own load rather than being read off [_detail].
  MetricDetail? _hrv;

  TrendRange _range = TrendRange.day;
  bool _exporting = false;
  final _repo = HealthRepository();

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void didUpdateWidget(TrendDetailView old) {
    super.didUpdateWidget(old);
    if (old.metricKey != widget.metricKey) {
      setState(() {
        _detail = null;
        _range = TrendRange.day;
      });
      _load();
    }
  }

  Future<void> _load() async {
    final d = await _repo.loadMetricDetail(widget.metricKey);
    // The HR screen also hosts the HRV card, and HRV is its own metric with its
    // own trend rows — so it needs its own read.
    final hrv = widget.metricKey == 'hr'
        ? await _repo.loadMetricDetail(hPi4Global.PREFIX_HRV)
        : null;
    if (mounted) {
      setState(() {
        _detail = d;
        _hrv = hrv;
      });
    }
  }

  String _fmt(double? v) {
    if (v == null) return '--';
    if (widget.metricKey == 'temp') return v.toStringAsFixed(1);
    return v.round().toString();
  }

  /// Export the **selected range** as CSV and hand it to the share sheet.
  ///
  /// The share icon was decoration for a while — a bare `Icon` with no handler
  /// on either the inline header or the pushed route's app bar. Exporting the
  /// selected range (rather than everything) keeps the file matching what the
  /// user is looking at.
  Future<void> exportCsv() => _export();

  /// True while an export is in flight, so a host app bar can disable its action.
  bool get isExporting => _exporting;

  Future<void> _export() async {
    final d = _detail;
    if (d == null || _exporting) return;
    final series = d.series(_range);
    if (series.isEmpty) {
      _toast('Nothing to export in this range.');
      return;
    }

    setState(() => _exporting = true);
    try {
      final style = TrendMetricStyle.of(widget.metricKey);
      final bucket = _range == TrendRange.day
          ? 'hour'
          : (_range == TrendRange.sixMonths ? 'week' : 'day');
      final rows = <List<dynamic>>[
        ['bucket_start_local', 'bucket', 'metric', 'unit', 'min', 'avg', 'max'],
        for (final p in series)
          [
            p.t.toIso8601String(),
            bucket,
            widget.metricKey,
            style.unit,
            p.min,
            p.avg,
            p.max,
          ],
      ];

      final dir = await getApplicationDocumentsDirectory();
      final stamp = DateTime.now()
          .toIso8601String()
          .replaceAll(RegExp(r'[:.]'), '-')
          .substring(0, 19);
      final file = File(
          '${dir.path}/healthypi_${widget.metricKey}_${_range.name}_$stamp.csv');
      await file.writeAsString(const ListToCsvConverter().convert(rows));
      if (!mounted) return;
      await SharePlus.instance.share(ShareParams(
        files: [XFile(file.path)],
        text: '${style.title} · ${_rangeLabel()}',
      ));
    } catch (e) {
      _toast('Export failed: $e');
    } finally {
      if (mounted) setState(() => _exporting = false);
    }
  }

  String _rangeLabel() => switch (_range) {
        TrendRange.day => 'today',
        TrendRange.week => 'last 7 days',
        TrendRange.month => 'last 30 days',
        TrendRange.sixMonths => 'last 6 months',
      };

  void _toast(String msg) {
    if (!mounted) return;
    ScaffoldMessenger.of(context)
        .showSnackBar(SnackBar(content: Text(msg)));
  }

  @override
  Widget build(BuildContext context) {
    final style = TrendMetricStyle.of(widget.metricKey);
    final d = _detail;
    if (d == null) {
      return const Center(
          child: CircularProgressIndicator(color: HpiColors.hr));
    }

    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 28),
      children: [
        if (widget.showHeader) _header(style),
        if (!d.hasData)
          _noData(d, style)
        else ...[
          HpiSegmentedControl(
            segments: const ['Day', 'Week', 'Month', '6M'],
            selectedIndex: _range.index,
            accent: style.color,
            onChanged: (i) => setState(() => _range = TrendRange.values[i]),
          ),
          const SizedBox(height: 16),
          _hero(d, style),
          const SizedBox(height: 16),
          _mainChartCard(d, style),
          const SizedBox(height: 12),
          _statChips(d, style),
          const SizedBox(height: 12),
          ..._secondary(d, style),
        ],
      ],
    );
  }

  Widget _header(TrendMetricStyle style) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 14),
      child: Row(
        children: [
          Icon(style.icon, size: 22, color: style.color),
          const SizedBox(width: 8),
          Text(style.title, style: HpiText.appBarTitle),
          const Spacer(),
          IconButton(
            icon: _exporting
                ? const SizedBox(
                    width: 16,
                    height: 16,
                    child: CircularProgressIndicator(strokeWidth: 2))
                : const Icon(Symbols.ios_share,
                    size: 20, color: HpiColors.onSurfaceBright),
            tooltip: 'Export CSV',
            onPressed: _exporting ? null : _export,
          ),
        ],
      ),
    );
  }

  Widget _hero(MetricDetail d, TrendMetricStyle style) {
    final updated = d.latestAt == null
        ? ''
        : ' · updated ${_relative(d.latestAt!)}';
    return Row(
      crossAxisAlignment: CrossAxisAlignment.baseline,
      textBaseline: TextBaseline.alphabetic,
      children: [
        Text(_fmt(d.latest),
            style: HpiText.heroNumberSm.copyWith(color: style.color)),
        const SizedBox(width: 6),
        if (style.unit.isNotEmpty)
          Text(widget.metricKey == 'activity' ? 'steps' : style.unit,
              style: HpiText.body.copyWith(fontSize: 14)),
        const Spacer(),
        Flexible(
          child: Text(
            '${_dayLabel(DateTime.now())}$updated',
            textAlign: TextAlign.right,
            style: HpiText.supporting.copyWith(fontSize: 11),
          ),
        ),
      ],
    );
  }

  Widget _mainChartCard(MetricDetail d, TrendMetricStyle style) {
    final series = d.series(_range);
    if (series.isEmpty) {
      return HpiCard(
        child: SizedBox(
          height: 150,
          child: Center(
              child: Text('No data in this range',
                  style: HpiText.supporting)),
        ),
      );
    }
    return HpiCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          HpiSectionLabel(_mainChartTitle()),
          SizedBox(height: 150, child: _chartFor(d, style, series)),
          const SizedBox(height: 8),
          _xAxis(series),
        ],
      ),
    );
  }

  String _mainChartTitle() {
    final scope = _range == TrendRange.day ? 'TODAY' : 'RECENT';
    switch (widget.metricKey) {
      case 'activity':
        return _range == TrendRange.day ? 'TODAY · STEPS PER HOUR' : 'STEPS PER DAY';
      case 'spo2':
        return _range == TrendRange.day ? 'TODAY · SpO₂' : 'SpO₂ TREND';
      case 'temp':
        return '$scope · WRIST TEMP';
      default:
        return _range == TrendRange.day ? 'TODAY · HOURLY MIN–MAX' : 'MIN–MAX';
    }
  }

  Widget _chartFor(MetricDetail d, TrendMetricStyle style, List<TrendPoint> s) {
    switch (widget.metricKey) {
      case 'activity':
        return HpiBarChart(
          values: s.map((p) => p.max).toList(),
          color: style.color,
          goal: _range == TrendRange.day ? null : 10000,
          goalLabel: _range == TrendRange.day ? null : '10k',
        );
      case 'spo2':
        final vals = s.map((p) => p.avg).toList();
        final dips = <int>[];
        for (var i = 0; i < s.length; i++) {
          if (s[i].min < 95) dips.add(i);
        }
        return HpiLineChart(
          values: vals,
          color: style.color,
          baseline: d.baseline,
          eventIndices: dips,
          yRange: const (90, 100),
          yLabel: (v) => v.round().toString(),
        );
      case 'temp':
        return HpiLineChart(
          values: s.map((p) => p.avg).toList(),
          color: style.color,
          baseline: d.baseline,
          yLabel: (v) => v.toStringAsFixed(1),
        );
      default: // hr — candlestick
        return HpiCandleChart(
          bins: s
              .map((p) => TrendBin(min: p.min, max: p.max, center: p.avg))
              .toList(),
          color: style.color,
          band: (d.baseline != null)
              ? TrendBand(
                  lo: d.baseline! - 3,
                  hi: d.baseline! + 3,
                  color: HpiMetricColors.tint(HpiColors.spo2, 0.14))
              : null,
          yLabel: (v) => v.round().toString(),
        );
    }
  }

  Widget _statChips(MetricDetail d, TrendMetricStyle style) {
    final chips = <Widget>[];
    void add(String v, String l, {Color? c}) => chips.add(Expanded(
        child: HpiStatChip(value: v, label: l, valueColor: c)));

    // Stats for the *selected* range. These used to read d.min/avg/max, which
    // are today-only — so they never moved when you changed range, and showed
    // "--" whenever today was empty even with a full chart next to them.
    final s = d.statsFor(_range);
    final hasRange = s.avg != null;
    final avg = hasRange ? s.avg : d.avg;
    final min = hasRange ? s.min : d.min;
    final max = hasRange ? s.max : d.max;

    if (widget.metricKey == 'activity') {
      add(_fmt(max), _range == TrendRange.day ? 'Peak hr' : 'Best day',
          c: style.color);
      add(_fmt(avg), _range == TrendRange.day ? 'Avg' : 'Avg/day');
      if (d.baseline != null) add(_fmt(d.baseline), 'Daily avg');
    } else {
      if (d.baseline != null) add(_fmt(d.baseline), 'Baseline', c: HpiColors.spo2);
      add(_fmt(avg), 'Avg');
      add(_fmt(min), 'Min');
      add(_fmt(max), 'Max', c: style.color);
    }
    final row = <Widget>[];
    for (var i = 0; i < chips.length; i++) {
      if (i > 0) row.add(const SizedBox(width: 10));
      row.add(chips[i]);
    }
    return Row(children: row);
  }

  List<Widget> _secondary(MetricDetail d, TrendMetricStyle style) {
    switch (widget.metricKey) {
      case 'hr':
        return [_baselineDeviationCard(d, style), const SizedBox(height: 12), _hrvCard()];
      case 'temp':
        return [_baselineDeviationCard(d, style)];
      default:
        return [];
    }
  }

  /// Daily average minus the 30-day baseline, as above/below lollipops.
  Widget _baselineDeviationCard(MetricDetail d, TrendMetricStyle style) {
    if (d.baseline == null || d.weekly.isEmpty) return const SizedBox.shrink();
    final dev = d.weekly.map((p) => p.avg - d.baseline!).toList();
    final title = widget.metricKey == 'temp'
        ? 'NIGHTLY DEVIATION VS BASELINE'
        : 'DAILY AVG VS 30-DAY BASELINE';
    return HpiCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          HpiSectionLabel(title),
          SizedBox(
            height: 76,
            child: HpiLollipopChart(
              deviations: dev,
              aboveColor: widget.metricKey == 'temp' ? HpiColors.temp : HpiColors.hr,
              belowColor: HpiColors.spo2,
            ),
          ),
          const SizedBox(height: 6),
          _weekAxis(d.weekly),
        ],
      ),
    );
  }

  /// HRV on the HR screen (handoff 3a).
  ///
  /// Real data since firmware P3: continuous RMSSD from gated wrist R-R
  /// intervals, in 5-minute windows, whole ms. This used to be a hardcoded
  /// zero-state that said "no producing code" — it kept saying that after the
  /// producer arrived, which is why HRV synced but appeared nowhere.
  ///
  /// Falls back to the zero-state only when there genuinely is no HRV: a watch
  /// on pre-P3 firmware, or one that has not synced any window yet.
  Widget _hrvCard() {
    final h = _hrv;
    final supported = h != null &&
        h.availability == MetricAvailability.available;

    // "Supported but nothing today" is a real, common state — HRV only accrues
    // from still, on-skin, high-confidence beats, so a restless day can produce
    // none. Rendering the usual layout with "--" in every slot would look like a
    // bug; say what actually happened instead.
    final hasToday = supported && h.daily.isNotEmpty;

    return HpiCard(
      highlightColor: HpiMetricColors.tint(HpiColors.stress, 0.25),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(children: [
            const Icon(Symbols.ecg_heart, size: 18, color: HpiColors.stress),
            const SizedBox(width: 6),
            Text('HRV · TODAY', style: HpiText.sectionLabel),
            const Spacer(),
            HpiPill(
                label: hasToday
                    ? 'RMSSD'
                    : (supported ? 'NONE TODAY' : 'NOT YET AVAILABLE'),
                color: HpiColors.stress),
          ]),
          const SizedBox(height: 12),
          if (!supported)
            Text(
              'HRV (RMSSD) is computed on the watch from gated beat-to-beat '
              'intervals in 5-minute windows. It appears here once your watch '
              'reports them — no estimate is shown in the meantime.',
              style: HpiText.body.copyWith(fontSize: 12),
            )
          else if (!hasToday)
            Text(
              'No HRV windows today yet. A window only counts when the watch is '
              'on-skin and still with confident beat detection, so an active day '
              'can produce none.',
              style: HpiText.body.copyWith(fontSize: 12),
            )
          else ...[
            Row(
              crossAxisAlignment: CrossAxisAlignment.baseline,
              textBaseline: TextBaseline.alphabetic,
              children: [
                Text(h.latest?.round().toString() ?? '--',
                    style: HpiText.cardValue.copyWith(
                        fontSize: 30, color: HpiColors.stress)),
                const SizedBox(width: 3),
                Text('ms', style: HpiText.mono.copyWith(fontSize: 11)),
                const SizedBox(width: 14),
                Expanded(
                  child: SizedBox(
                    height: 34,
                    child: HpiSparkline(
                      values: [for (final p in h.daily) p.avg],
                      color: HpiColors.stress,
                      strokeWidth: 1.8,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 10),
            // Low RMSSD is the signal that matters (suppressed HRV), so min is
            // as interesting as max here — show the range, not just an average.
            Row(children: [
              _hrvStat('MIN', h.min),
              _hrvStat('AVG', h.avg),
              _hrvStat('MAX', h.max),
              _hrvStat('BASELINE', h.baseline),
            ]),
          ],
        ],
      ),
    );
  }

  Widget _hrvStat(String label, double? v) {
    return Expanded(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(label, style: HpiText.sectionLabel.copyWith(fontSize: 8.5)),
          const SizedBox(height: 2),
          Text(v == null ? '--' : '${v.round()} ms',
              style: HpiText.mono.copyWith(fontSize: 11.5)),
        ],
      ),
    );
  }

  Widget _noData(MetricDetail d, TrendMetricStyle style) {
    final unsupported = d.availability == MetricAvailability.unsupported;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 48),
      child: Column(
        children: [
          Icon(style.icon, size: 44, color: HpiColors.disabled),
          const SizedBox(height: 14),
          Text(unsupported ? 'Not yet available' : 'No ${style.title.toLowerCase()} yet',
              style: HpiText.appBarTitle),
          const SizedBox(height: 6),
          Text(
            unsupported
                ? 'This metric has no data source in the app yet.'
                : 'Sync your watch to populate this trend.',
            textAlign: TextAlign.center,
            style: HpiText.body.copyWith(fontSize: 12),
          ),
        ],
      ),
    );
  }

  // --- axis labels ---

  /// Axis ticks for the selected range.
  ///
  /// Every non-day range used to print weekday names, so Month and 6M both read
  /// "Tue … Fri" — indistinguishable from Week, and meaningless once the window
  /// is longer than seven days. Each range now labels in its own units: hours,
  /// weekdays, dates, months.
  Widget _xAxis(List<TrendPoint> s) {
    String tick(DateTime t) => switch (_range) {
          TrendRange.day => _hourShort(t),
          TrendRange.week => _weekdayShort(t),
          TrendRange.month => '${_monthShort(t.month)} ${t.day}',
          TrendRange.sixMonths => _monthShort(t.month),
        };

    final List<String> labels;
    if (_range == TrendRange.day) {
      labels = ['12A', '6A', '12P', '6P', '11P'];
    } else if (s.isEmpty) {
      labels = const [];
    } else if (s.length == 1) {
      labels = [tick(s.first.t)];
    } else {
      labels = [
        tick(s.first.t),
        if (s.length > 2) tick(s[s.length ~/ 2].t),
        tick(s.last.t),
      ];
    }
    return Row(
      mainAxisAlignment: labels.length == 1
          ? MainAxisAlignment.center
          : MainAxisAlignment.spaceBetween,
      children: [
        for (final l in labels)
          Text(l, style: HpiText.mono.copyWith(fontSize: 9, color: HpiColors.faint)),
      ],
    );
  }

  Widget _weekAxis(List<TrendPoint> s) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        for (final p in s)
          Text(_weekdayShort(p.t),
              style: HpiText.mono.copyWith(fontSize: 9, color: HpiColors.faint)),
      ],
    );
  }

  String _relative(DateTime t) {
    final diff = DateTime.now().difference(t);
    if (diff.inMinutes < 1) return 'just now';
    if (diff.inMinutes < 60) return '${diff.inMinutes} m ago';
    if (diff.inHours < 24) return '${diff.inHours} h ago';
    return _dayLabel(t);
  }

  String _dayLabel(DateTime t) =>
      '${_weekdayShort(t)}, ${_monthShort(t.month)} ${t.day}';
  String _weekdayShort(DateTime t) =>
      const ['Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun'][t.weekday - 1];
  String _hourShort(DateTime t) {
    final h = t.hour % 12 == 0 ? 12 : t.hour % 12;
    return '$h${t.hour < 12 ? 'A' : 'P'}';
  }
  String _monthShort(int m) => const [
        'Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun',
        'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'
      ][m - 1];
}

/// Compact pushed route wrapping [TrendDetailView] with an app bar (back +
/// share), used when the layout isn't wide enough for the two-pane detail.
class TrendDetailScreen extends StatefulWidget {
  const TrendDetailScreen({super.key, required this.metricKey});
  final String metricKey;

  @override
  State<TrendDetailScreen> createState() => _TrendDetailScreenState();
}

class _TrendDetailScreenState extends State<TrendDetailScreen> {
  /// Drives the app-bar share action, which would otherwise have no way to
  /// reach the selected range — this action was a decorative `Icon` before.
  final _viewKey = GlobalKey<TrendDetailViewState>();

  @override
  Widget build(BuildContext context) {
    final style = TrendMetricStyle.of(widget.metricKey);
    return Scaffold(
      backgroundColor: HpiColors.background,
      appBar: AppBar(
        title: Text(style.title),
        actions: [
          IconButton(
            icon: const Icon(Symbols.ios_share, size: 20),
            tooltip: 'Export CSV',
            onPressed: () => _viewKey.currentState?.exportCsv(),
          ),
        ],
      ),
      body: SafeArea(
        child: TrendDetailView(
          key: _viewKey,
          metricKey: widget.metricKey,
          showHeader: false,
        ),
      ),
    );
  }
}
