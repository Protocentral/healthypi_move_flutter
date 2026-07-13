import 'package:flutter/material.dart';
import 'package:material_symbols_icons/symbols.dart';

import '../data/health_repository.dart';
import '../theme/hpi_colors.dart';
import '../theme/hpi_text.dart';
import '../ui/adaptive/breakpoints.dart';
import '../ui/components/hpi_components.dart';
import 'scr_stress_eda.dart';
import 'scr_trend_detail.dart';

/// The Trends tab (handoff): a hub listing every metric that opens its trend
/// detail. Compact pushes [TrendDetailScreen]; expanded is a list-detail
/// two-pane with [TrendDetailView] on the right. Reuses the Home signal-row
/// anatomy and the same honest zero-states.
class ScrTrendsHub extends StatefulWidget {
  const ScrTrendsHub({super.key});

  @override
  State<ScrTrendsHub> createState() => _ScrTrendsHubState();
}

class _ScrTrendsHubState extends State<ScrTrendsHub> {
  final _repo = HealthRepository();
  HomeDashboard? _dash;
  String _selected = 'hr';

  static const _real = ['hr', 'spo2', 'temp', 'activity'];

  @override
  void initState() {
    super.initState();
    _repo.loadHome().then((d) {
      if (mounted) setState(() => _dash = d);
    });
  }

  MetricTrend _trend(String key) {
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

  void _open(String key) {
    if (Breakpoints.isExpanded(context)) {
      setState(() => _selected = key);
    } else {
      Navigator.of(context).push(MaterialPageRoute(
          builder: (_) => TrendDetailScreen(metricKey: key)));
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_dash == null) {
      return const Center(child: CircularProgressIndicator(color: HpiColors.hr));
    }
    final expanded = Breakpoints.isExpanded(context);
    final list = _listPane(expanded);
    if (!expanded) return list;
    return Row(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        SizedBox(width: 380, child: list),
        const VerticalDivider(width: 1, thickness: 1, color: HpiColors.divider),
        Expanded(
          child: TrendDetailView(
              key: ValueKey(_selected), metricKey: _selected),
        ),
      ],
    );
  }

  Widget _listPane(bool expanded) {
    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
      children: [
        Padding(
          padding: const EdgeInsets.only(bottom: 14, left: 2),
          child: Text('Trends', style: HpiText.screenTitle),
        ),
        HpiGroupedCard(
            rows: [for (final k in _real) _row(k, expanded)]),
        const SizedBox(height: 12),
        // Stress is real once the watch has an HRV baseline (firmware P3), so
        // the header can't keep claiming the whole section is unavailable.
        HpiSectionLabel(_trend('stress').hasData
            ? 'DERIVED'
            : 'DERIVED · NOT YET AVAILABLE'),
        HpiGroupedCard(rows: [_row('stress', expanded), _row('eda', expanded)]),
      ],
    );
  }

  Widget _row(String key, bool expanded) {
    final t = _trend(key);
    final style = TrendMetricStyle.of(key);
    final baselining = t.availability == MetricAvailability.baselining;
    final unsupported =
        t.availability == MetricAvailability.unsupported || baselining;
    final title = unsupported
        ? (key == 'stress' ? 'Stress' : 'EDA · GSR')
        : style.title;

    if (unsupported) {
      return HpiListRow(
        icon: key == 'stress' ? Symbols.self_improvement : Symbols.water_drop,
        iconColor: key == 'stress' ? HpiColors.stress : HpiColors.eda,
        title: title,
        supporting: baselining
            // Supported, measuring, just no score yet — not the same thing as
            // "we can't do this" (handoff §6.2).
            ? 'Building your baseline · wear overnight'
            : (key == 'stress'
                ? 'from HRV · continuous'
                : 'spot check on watch'),
        dim: true,
        onTap: () => Navigator.of(context).push(
            MaterialPageRoute(builder: (_) => const ScrStressEda())),
        trailing: Text('—',
            style: HpiText.cardValue.copyWith(color: HpiColors.muted)),
      );
    }

    final selected = expanded && _selected == key;
    return Container(
      color: selected ? HpiMetricColors.tint(HpiColors.hr, 0.08) : null,
      child: HpiListRow(
        icon: style.icon,
        iconColor: style.color,
        title: title,
        supporting: t.hasData ? _relative(t.latestAt) : 'sync your watch',
        onTap: () => _open(key),
        trailing: t.hasData
            ? Text(_fmt(key, t.latest),
                style: HpiText.cardValue.copyWith(color: style.color))
            : Text('--',
                style: HpiText.cardValue.copyWith(color: HpiColors.muted)),
      ),
    );
  }

  String _fmt(String key, double? v) {
    if (v == null) return '--';
    if (key == 'temp') return v.toStringAsFixed(1);
    return v.round().toString();
  }

  String _relative(DateTime? t) {
    if (t == null) return 'no recent reading';
    final d = DateTime.now().difference(t);
    if (d.inMinutes < 60) return 'updated ${d.inMinutes} m ago';
    if (d.inHours < 24) return 'updated ${d.inHours} h ago';
    return 'updated ${d.inDays} d ago';
  }
}
