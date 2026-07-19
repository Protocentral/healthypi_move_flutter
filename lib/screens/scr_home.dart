// Copyright (c) 2024-2026 ProtoCentral
// SPDX-License-Identifier: MIT

import 'dart:async';
import 'package:flutter/material.dart';
import 'package:material_symbols_icons/symbols.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../data/health_repository.dart';
import '../globals.dart';
import '../theme/hpi_colors.dart';
import '../theme/hpi_text.dart';
import '../ui/adaptive/breakpoints.dart';
import '../ui/charts/hpi_ring_gauge.dart';
import '../ui/charts/hpi_spark_bars.dart';
import '../ui/charts/hpi_sparkline.dart';
import '../ui/components/hpi_components.dart';
import '../utils/device_manager.dart';
import '../utils/healthy_store_sync_manager.dart';
import 'scr_stress_eda.dart';
import 'scr_trend_detail.dart';

/// Redesigned Home (handoff 2a list + 1a grid, with the 4a tablet two-pane).
/// Reads [HealthRepository] and renders honest zero-states for metrics with no
/// producing code. Sync is [HealthyStoreSyncManager] only (HPI_HS / mcumgr).
class ScrHome extends StatefulWidget {
  const ScrHome({super.key});

  @override
  State<ScrHome> createState() => _ScrHomeState();
}

enum _Layout { list, grid }

class _ScrHomeState extends State<ScrHome> {
  final _repo = HealthRepository();
  HomeDashboard? _dash;
  BloodPressureView? _bp;
  _Layout _layout = _Layout.list;
  String _selectedMetric = hPi4Global.PREFIX_HR; // tablet right-pane selection

  bool _syncing = false;
  double _syncProgress = 0;
  String _syncMessage = '';
  StreamSubscription? _syncSub;

  static const _layoutPrefKey = 'home_layout_grid';

  @override
  void initState() {
    super.initState();
    _restoreLayout();
    _load();
  }

  @override
  void dispose() {
    _syncSub?.cancel();
    super.dispose();
  }

  Future<void> _restoreLayout() async {
    final prefs = await SharedPreferences.getInstance();
    final grid = prefs.getBool(_layoutPrefKey) ?? false;
    if (mounted) setState(() => _layout = grid ? _Layout.grid : _Layout.list);
  }

  Future<void> _setLayout(_Layout layout) async {
    setState(() => _layout = layout);
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_layoutPrefKey, layout == _Layout.grid);
  }

  Future<void> _load() async {
    final dash = await _repo.loadHome();
    if (mounted) setState(() => _dash = dash);
    final bp = await _repo.loadBloodPressure();
    if (mounted) setState(() => _bp = bp);
  }

  Future<void> _sync() async {
    if (_syncing) return;
    final device = await DeviceManager.getPairedDevice();
    if (device == null) {
      _snack('No device paired. Pair a device first.', HpiColors.error);
      return;
    }
    setState(() {
      _syncing = true;
      _syncProgress = 0;
      _syncMessage = '';
    });
    _syncSub = HealthyStoreSyncManager.instance.progressStream.listen((p) {
      if (mounted && p.metric == 'all') {
        setState(() {
          _syncProgress = p.progress;
          _syncMessage = p.message ?? '';
        });
      }
    });
    try {
      final result = await HealthyStoreSyncManager.instance.syncData(
        deviceMacAddress: device.macAddress,
        onProgress: (metric, progress) {},
        onStatus: (status) {},
      );
      // Reload either way: a partial sync still stored real samples, and the
      // recent-first pass means the screens have current data even when the
      // history backlog didn't finish.
      await _load();
      if (mounted) {
        _snack(result.message,
            result.success ? HpiColors.steps : HpiColors.error);
      }
    } catch (e) {
      if (mounted) _snack('Sync error: $e', HpiColors.error);
    } finally {
      await _syncSub?.cancel();
      _syncSub = null;
      if (mounted) {
        setState(() {
          _syncing = false;
          _syncProgress = 0;
          _syncMessage = '';
        });
      }
    }
  }

  void _snack(String msg, Color bg) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(msg), backgroundColor: bg));
  }

  // --- Metric presentation config ---------------------------------------

  _MetricStyle _styleFor(String key) {
    switch (key) {
      case 'hr':
        return const _MetricStyle(
            Symbols.favorite, HpiColors.hr, 'Heart rate', 'bpm');
      case 'spo2':
        return const _MetricStyle(Symbols.spo2, HpiColors.spo2, 'SpO₂', '%');
      case 'temp':
        return const _MetricStyle(
            Symbols.device_thermostat, HpiColors.temp, 'Wrist temp', '°');
      case 'activity':
        return const _MetricStyle(Symbols.steps, HpiColors.steps, 'Steps', '');
      case 'stress':
        return const _MetricStyle(
            Symbols.self_improvement, HpiColors.stress, 'Stress', '');
      default:
        return const _MetricStyle(
            Symbols.water_drop, HpiColors.eda, 'EDA · GSR', '');
    }
  }

  MetricTrend _trendFor(String key) {
    final d = _dash!;
    switch (key) {
      case 'hr':
        return d.hr;
      case 'spo2':
        return d.spo2;
      case 'temp':
        return d.temp;
      case 'activity':
        return d.steps;
      case 'stress':
        return d.stress;
      default:
        return d.eda;
    }
  }

  String _fmt(String key, double? v) {
    if (v == null) return '--';
    if (key == 'temp') return v.toStringAsFixed(1);
    return v.round().toString();
  }

  @override
  Widget build(BuildContext context) {
    if (_dash == null) {
      return const Center(
          child: CircularProgressIndicator(color: HpiColors.hr));
    }
    final expanded = Breakpoints.isExpanded(context);
    if (expanded) return _buildTwoPane(context);
    return _buildSinglePane(context);
  }

  // --- Compact (phone) --------------------------------------------------

  Widget _buildSinglePane(BuildContext context) {
    return RefreshIndicator(
      color: HpiColors.hr,
      backgroundColor: HpiColors.surfaceContainer,
      onRefresh: _sync,
      child: ListView(
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
        children: [
          _header(),
          const SizedBox(height: 14),
          _heroHrCard(),
          const SizedBox(height: 12),
          if (_layout == _Layout.list) _signalListCard() else _metricGrid(),
          const SizedBox(height: 12),
          _footer(),
        ],
      ),
    );
  }

  // --- Expanded (tablet 4a) --------------------------------------------

  Widget _buildTwoPane(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        SizedBox(
          width: 432,
          child: ListView(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
            children: [
              _header(),
              const SizedBox(height: 14),
              _heroHrCard(),
              const SizedBox(height: 12),
              _signalListCard(),
            ],
          ),
        ),
        const VerticalDivider(
            width: 1, thickness: 1, color: HpiColors.divider),
        // 4a right pane: the real trend detail, rendered in place (no route).
        Expanded(
          child: TrendDetailView(
            key: ValueKey(_selectedMetric),
            metricKey: _selectedMetric,
          ),
        ),
      ],
    );
  }

  // --- Header -----------------------------------------------------------

  Widget _header() {
    final now = DateTime.now();
    final greeting = now.hour < 12
        ? 'Good morning'
        : (now.hour < 17 ? 'Good afternoon' : 'Good evening');
    final date = '${_weekday(now.weekday)}, ${_month(now.month)} ${now.day}';
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(greeting,
                  style: HpiText.screenTitle.copyWith(fontSize: 19)),
              const SizedBox(height: 2),
              Text(date, style: HpiText.body.copyWith(fontSize: 12)),
            ],
          ),
        ),
        _layoutSwitcher(),
      ],
    );
  }

  Widget _layoutSwitcher() {
    Widget btn(IconData icon, _Layout mode) {
      final active = _layout == mode;
      return GestureDetector(
        onTap: () => _setLayout(mode),
        behavior: HitTestBehavior.opaque,
        child: Container(
          width: 34,
          height: 28,
          alignment: Alignment.center,
          decoration: BoxDecoration(
            color: active
                ? HpiMetricColors.tint(HpiColors.hr, 0.18)
                : Colors.transparent,
            borderRadius: BorderRadius.circular(999),
          ),
          child: Icon(icon,
              size: 17,
              color: active ? HpiColors.hr : HpiColors.onSurfaceVariant),
        ),
      );
    }

    return Container(
      padding: const EdgeInsets.all(3),
      decoration: BoxDecoration(
          color: HpiColors.chipBg, borderRadius: BorderRadius.circular(999)),
      child: Row(mainAxisSize: MainAxisSize.min, children: [
        btn(Symbols.grid_view, _Layout.grid),
        btn(Symbols.view_list, _Layout.list),
      ]),
    );
  }

  // --- Hero HR card -----------------------------------------------------

  Widget _heroHrCard() {
    final hr = _dash!.hr;
    final style = _styleFor('hr');
    return HpiCard(
      onTap: () => _openMetric('hr'),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(Symbols.favorite, size: 17, color: HpiColors.hr),
              const SizedBox(width: 6),
              Text('HEART RATE', style: HpiText.sectionLabel),
              const Spacer(),
              if (hr.baseline != null)
                HpiPill(
                    label: 'RESTING ${hr.baseline!.round()}',
                    color: HpiColors.hr),
            ],
          ),
          const SizedBox(height: 10),
          if (hr.hasData) ...[
            Row(
              crossAxisAlignment: CrossAxisAlignment.baseline,
              textBaseline: TextBaseline.alphabetic,
              children: [
                Text(_fmt('hr', hr.latest), style: HpiText.heroNumber),
                const SizedBox(width: 6),
                Text('bpm', style: HpiText.body.copyWith(fontSize: 14)),
                const Spacer(),
                if (hr.min != null && hr.max != null)
                  Text('range ${hr.min!.round()}–${hr.max!.round()}',
                      style: HpiText.supporting),
              ],
            ),
            // Don't let a big "72 bpm" imply it's current when the newest reading
            // we hold is hours old.
            if (!_isToday(hr) && hr.latestAt != null) ...[
              const SizedBox(height: 2),
              Text('last reading ${_age(hr.latestAt!)}',
                  style: HpiText.supporting.copyWith(color: HpiColors.temp)),
            ],
            const SizedBox(height: 12),
            SizedBox(
              height: 56,
              child: HpiSparkline(
                  values: hr.spark, color: HpiColors.hr, strokeWidth: 2),
            ),
            const SizedBox(height: 6),
            _heroAxis(),
          ] else
            _inlineNoData(style),
        ],
      ),
    );
  }

  Widget _heroAxis() {
    const labels = ['12A', '6A', '12P', '6P', 'NOW'];
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        for (final l in labels)
          Text(l,
              style: HpiText.mono.copyWith(
                  fontSize: 9,
                  color: l == 'NOW' ? HpiColors.hr : HpiColors.faint)),
      ],
    );
  }

  // --- Signal list (2a) -------------------------------------------------

  Widget _signalListCard() {
    return HpiGroupedCard(rows: [
      _signalRow('activity'),
      _signalRow('spo2'),
      _signalRow('temp'),
      _signalRow('stress'),
      _signalRow('eda'),
      _bpRow(),
    ]);
  }

  /// Blood-pressure spot readings — a dedicated event-class screen (6a/6b).
  /// Shows the last reading when calibrated, else the not-calibrated gate.
  Widget _bpRow() {
    final bp = _bp;
    final calibrated = bp?.showValues ?? false;
    final latest = bp?.latest;
    return HpiListRow(
      icon: Symbols.monitor_heart,
      iconColor: HpiColors.bpSys,
      title: 'Blood pressure',
      supporting: calibrated ? 'spot · finger PPG' : 'not calibrated',
      dim: !calibrated,
      onTap: () async {
        await Navigator.of(context).pushNamed('/blood-pressure');
        _load();
      },
      trailing: calibrated
          ? Text('${latest!.systolic}/${latest.diastolic}',
              style: HpiText.statChip.copyWith(color: HpiColors.bpSys))
          : Text('--', style: HpiText.cardValue.copyWith(color: HpiColors.muted)),
    );
  }

  Widget _signalRow(String key) {
    final t = _trendFor(key);
    final s = _styleFor(key);

    // The watch produces this metric but is still learning the user's personal
    // baseline. Say that — never render a 0, which reads as "calm" and is a
    // number the user would believe (handoff §6.2).
    if (t.availability == MetricAvailability.baselining) {
      return HpiListRow(
        icon: s.icon,
        iconColor: s.color,
        title: s.title,
        supporting: 'Building your baseline · wear overnight',
        dim: true,
        onTap: () => Navigator.of(context).push(
            MaterialPageRoute(builder: (_) => const ScrStressEda())),
        trailing:
            Text('—', style: HpiText.cardValue.copyWith(color: HpiColors.muted)),
      );
    }

    // Unsupported metrics → honest zero-state row that opens the explainer.
    if (t.availability == MetricAvailability.unsupported) {
      final measure = key == 'eda';
      return HpiListRow(
        icon: s.icon,
        iconColor: s.color,
        title: s.title,
        supporting: key == 'stress'
            ? 'from HRV · continuous'
            : 'no spot check today',
        dim: true,
        onTap: () => Navigator.of(context).push(
            MaterialPageRoute(builder: (_) => const ScrStressEda())),
        trailing: measure
            ? const HpiPill(label: 'MEASURE ON WATCH', color: HpiColors.eda)
            : Text('—', style: HpiText.cardValue.copyWith(color: HpiColors.muted)),
      );
    }

    final noData = !t.hasData;
    return HpiListRow(
      icon: s.icon,
      iconColor: s.color,
      title: s.title,
      supporting: _rowSupporting(key, t),
      supportingColor: key == 'temp' && t.baselineDelta != null
          ? HpiColors.temp
          : null,
      onTap: () => _openMetric(key),
      trailing: noData
          ? Text('--', style: HpiText.cardValue.copyWith(color: HpiColors.muted))
          : Row(mainAxisSize: MainAxisSize.min, children: [
              SizedBox(
                width: 92,
                height: 30,
                child: key == 'activity'
                    ? HpiSparkBars(values: t.spark, color: s.color)
                    : HpiSparkline(
                        values: t.spark,
                        color: s.color,
                        strokeWidth: 1.8,
                        areaOpacity: 0),
              ),
              const SizedBox(width: 12),
              _rowValue(key, t, s),
            ]),
    );
  }

  Widget _rowValue(String key, MetricTrend t, _MetricStyle s) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.baseline,
      textBaseline: TextBaseline.alphabetic,
      children: [
        Text(_fmt(key, t.latest), style: HpiText.cardValue),
        if (s.unit.isNotEmpty) ...[
          const SizedBox(width: 2),
          Text(s.unit, style: HpiText.mono.copyWith(fontSize: 9.5)),
        ],
      ],
    );
  }

  /// Whether [t]'s newest reading falls on today's date.
  bool _isToday(MetricTrend t) {
    final at = t.latestAt;
    if (at == null) return false;
    final now = DateTime.now();
    return at.year == now.year && at.month == now.month && at.day == now.day;
  }

  /// "2 h ago" / "3 d ago" — used so a card never implies its value is current
  /// when the newest data we hold is older than that.
  String _age(DateTime at) {
    final d = DateTime.now().difference(at);
    if (d.inMinutes < 60) return '${d.inMinutes} m ago';
    if (d.inHours < 24) return '${d.inHours} h ago';
    return '${d.inDays} d ago';
  }

  String? _rowSupporting(String key, MetricTrend t) {
    // Never claim "today" when the reading isn't from today — say how old it is.
    if (!_isToday(t) && t.latestAt != null) return _age(t.latestAt!);

    switch (key) {
      case 'activity':
        return 'today';
      case 'spo2':
        return 'last reading';
      case 'temp':
        final d = t.baselineDelta;
        if (d != null) {
          final sign = d >= 0 ? '+' : '';
          return '$sign${d.toStringAsFixed(1)}° vs baseline';
        }
        return 'last reading';
      default:
        return null;
    }
  }

  // --- Metric grid (1a) -------------------------------------------------

  Widget _metricGrid() {
    final keys = ['activity', 'spo2', 'temp', 'stress'];
    return GridView.count(
      crossAxisCount: 2,
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      mainAxisSpacing: 12,
      crossAxisSpacing: 12,
      childAspectRatio: 1.15,
      children: [for (final k in keys) _metricTile(k)],
    );
  }

  Widget _metricTile(String key) {
    final t = _trendFor(key);
    final s = _styleFor(key);
    // "No score yet" shows the same dash as "not supported" — both must refuse to
    // invent a number — but they say different things in _tileExtra below.
    final unsupported = t.availability == MetricAvailability.unsupported ||
        t.availability == MetricAvailability.baselining;
    return HpiCard(
      onTap: unsupported ? null : () => _openMetric(key),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(children: [
            Icon(s.icon, size: 16, color: s.color),
            const SizedBox(width: 6),
            Text(s.title.toUpperCase(),
                style: HpiText.sectionLabel.copyWith(fontSize: 10)),
          ]),
          const Spacer(),
          if (unsupported)
            Text('—',
                style: HpiText.cardValue.copyWith(color: HpiColors.muted))
          else
            Text(_fmt(key, t.latest),
                style: HpiText.cardValue.copyWith(fontSize: 24)),
          const SizedBox(height: 6),
          SizedBox(height: 26, child: _tileExtra(key, t, s)),
        ],
      ),
    );
  }

  Widget _tileExtra(String key, MetricTrend t, _MetricStyle s) {
    if (t.availability == MetricAvailability.baselining) {
      return Text('building baseline', style: HpiText.supporting);
    }
    if (t.availability == MetricAvailability.unsupported) {
      return Text(key == 'stress' ? 'from HRV' : 'measure on watch',
          style: HpiText.supporting);
    }
    if (!t.hasData) return Text('sync your watch', style: HpiText.supporting);
    switch (key) {
      case 'activity':
        final goal = (t.latest ?? 0) / 10000.0;
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            HpiProgressBar(fraction: goal, color: HpiColors.steps),
            const SizedBox(height: 4),
            Text('goal 10,000', style: HpiText.supporting),
          ],
        );
      default:
        return HpiSparkline(
            values: t.spark, color: s.color, strokeWidth: 1.8, areaOpacity: 0);
    }
  }

  // --- Footer -----------------------------------------------------------

  Widget _footer() {
    final sync = _dash!.lastSync;
    final label = sync == null ? 'Never synced' : 'Synced ${_relativeTime(sync)}';
    // While syncing, show what it's actually doing (and where it's up to) rather
    // than a bare percentage — a long history drain otherwise looks frozen.
    final status = _syncMessage.isNotEmpty
        ? '${(_syncProgress * 100).round()}% · $_syncMessage'
        : 'Syncing… ${(_syncProgress * 100).round()}%';
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 4),
      child: Row(
        children: [
          const Icon(Symbols.watch, size: 15, color: HpiColors.muted),
          const SizedBox(width: 6),
          Expanded(
              child: Text(_syncing ? status : label,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: HpiText.supporting)),
          GestureDetector(
            // A big backlog can't drain in one pass, so the sync must always be
            // interruptible — everything already stored is kept.
            onTap: _syncing
                ? () => HealthyStoreSyncManager.instance.cancel()
                : _sync,
            child: Text(_syncing ? 'Stop' : 'Sync now',
                style: HpiText.cardTitle
                    .copyWith(color: HpiColors.hr, fontSize: 12)),
          ),
        ],
      ),
    );
  }

  // --- nav --------------------------------------------------------------

  void _openMetric(String key) {
    if (Breakpoints.isExpanded(context)) {
      setState(() => _selectedMetric = key);
      return;
    }
    // Compact: push the redesigned trend detail (real-data metrics only).
    if (key == 'hr' || key == 'spo2' || key == 'temp' || key == 'activity') {
      Navigator.of(context).push(MaterialPageRoute(
          builder: (_) => TrendDetailScreen(metricKey: key)));
    }
  }

  Widget _inlineNoData(_MetricStyle s) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 18),
      child: Column(
        children: [
          Icon(s.icon, size: 28, color: HpiColors.disabled),
          const SizedBox(height: 8),
          Text('No ${s.title.toLowerCase()} yet',
              style: HpiText.cardTitle.copyWith(color: HpiColors.onSurfaceVariant)),
          const SizedBox(height: 2),
          Text('Sync your watch to see data', style: HpiText.supporting),
        ],
      ),
    );
  }

  /// Relative age: "just now" / "N m ago" / "N h ago" under 24 h, else a date
  /// (matches the handoff's timestamp rule).
  String _relativeTime(DateTime t) {
    final d = DateTime.now().difference(t);
    if (d.inMinutes < 1) return 'just now';
    if (d.inMinutes < 60) return '${d.inMinutes} m ago';
    if (d.inHours < 24) return '${d.inHours} h ago';
    return '${_month(t.month)} ${t.day}';
  }

  String _weekday(int w) =>
      const ['Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun'][w - 1];
  String _month(int m) => const [
        'Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun',
        'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'
      ][m - 1];
}

class _MetricStyle {
  const _MetricStyle(this.icon, this.color, this.title, this.unit);
  final IconData icon;
  final Color color;
  final String title;
  final String unit;
}
