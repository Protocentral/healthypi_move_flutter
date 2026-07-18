// Copyright (c) 2024-2026 ProtoCentral
// SPDX-License-Identifier: MIT

import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:material_symbols_icons/symbols.dart';

import '../data/health_repository.dart';
import '../theme/hpi_colors.dart';
import '../theme/hpi_text.dart';
import '../ui/charts/hpi_ring_gauge.dart';
import '../ui/charts/hpi_sparkline.dart';
import '../ui/components/hpi_components.dart';

/// Stress & EDA (handoff 1e with data / 2b zero-state).
///
/// Continuous stress comes from the watch SUMMARY (`stress_hrv` / baselining);
/// the sparkline is the derived continuous `stress` trend. EDA spot checks are
/// the MANUAL-bit `stress_eda` samples — never fabricated.
class ScrStressEda extends StatefulWidget {
  const ScrStressEda({super.key});

  @override
  State<ScrStressEda> createState() => _ScrStressEdaState();
}

class _ScrStressEdaState extends State<ScrStressEda> {
  final _repo = HealthRepository();
  StressEdaView? _view;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final v = await _repo.loadStressEda();
    if (mounted) setState(() => _view = v);
  }

  @override
  Widget build(BuildContext context) {
    final v = _view;
    return Scaffold(
      backgroundColor: HpiColors.background,
      appBar: AppBar(
        title: const Text('Stress & EDA'),
      ),
      body: SafeArea(
        child: v == null
            ? const Center(
                child: CircularProgressIndicator(color: HpiColors.stress))
            : RefreshIndicator(
                color: HpiColors.stress,
                onRefresh: _load,
                child: ListView(
                  physics: const AlwaysScrollableScrollPhysics(),
                  padding: const EdgeInsets.fromLTRB(16, 16, 16, 28),
                  children: [
                    _hero(v),
                    const SizedBox(height: 12),
                    if (v.hrv.hasData && v.hrv.daily.isNotEmpty) ...[
                      _todaySpark(v),
                      const SizedBox(height: 12),
                    ],
                    _edaSection(context, v),
                    const SizedBox(height: 12),
                    _recentSpotChecks(v),
                  ],
                ),
              ),
      ),
    );
  }

  Widget _hero(StressEdaView v) {
    final s = v.stress;
    final available = s.availability == MetricAvailability.available;
    final baselining = s.availability == MetricAvailability.baselining;
    final score = s.latest;
    final fraction = available && score != null
        ? (score.clamp(0, 100) / 100.0)
        : 0.0;

    String title;
    String supporting;
    if (available && score != null) {
      title = _stressLabel(score);
      supporting = s.latestAt != null
          ? 'Updated ${_relative(s.latestAt!)}'
          : 'From continuous HRV';
    } else if (baselining) {
      title = 'Building baseline';
      supporting = v.hrvWindows != null
          ? '${v.hrvWindows} HRV windows so far · wear overnight'
          : 'Wear overnight so the watch can learn your normal HRV';
    } else if (s.availability == MetricAvailability.noData) {
      title = 'No stress score yet';
      supporting = 'Sync your watch after wearing it for a while';
    } else {
      title = 'Not yet available';
      supporting = 'Needs firmware with continuous HRV (P3+)';
    }

    return HpiCard(
      child: Row(
        children: [
          SizedBox(
            width: 96,
            height: 96,
            child: HpiRingGauge(
              fraction: fraction,
              color: available ? HpiColors.stress : HpiColors.muted,
              strokeWidth: 10,
              center: Text(
                available && score != null ? score.round().toString() : '—',
                style: HpiText.heroNumberSm.copyWith(
                  color: available ? HpiColors.stress : HpiColors.muted,
                  fontSize: 28,
                ),
              ),
            ),
          ),
          const SizedBox(width: 18),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('Continuous · from HRV',
                    style:
                        HpiText.cardTitle.copyWith(color: HpiColors.stress)),
                const SizedBox(height: 4),
                Text(title, style: HpiText.supporting),
                const SizedBox(height: 10),
                Text(
                  supporting,
                  style: HpiText.body.copyWith(fontSize: 11.5),
                ),
                if (v.rmssdBaselineMs != null) ...[
                  const SizedBox(height: 8),
                  Text(
                    'Your RMSSD baseline · ${v.rmssdBaselineMs!.round()} ms',
                    style: HpiText.mono.copyWith(
                        fontSize: 10.5, color: HpiColors.muted),
                  ),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _todaySpark(StressEdaView v) {
    final values = [for (final p in v.hrv.daily) p.avg];
    return HpiCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const HpiSectionLabel('TODAY · CONTINUOUS STRESS'),
          const SizedBox(height: 8),
          SizedBox(
            height: 48,
            child: HpiSparkline(
              values: values,
              color: HpiColors.stress,
              strokeWidth: 1.8,
            ),
          ),
          const SizedBox(height: 8),
          Row(
            children: [
              _stat('MIN', v.hrv.min),
              _stat('AVG', v.hrv.avg),
              _stat('MAX', v.hrv.max),
            ],
          ),
        ],
      ),
    );
  }

  Widget _stat(String label, double? value) {
    return Expanded(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(label, style: HpiText.sectionLabel.copyWith(fontSize: 8.5)),
          const SizedBox(height: 2),
          Text(value == null ? '—' : value.round().toString(),
              style: HpiText.mono.copyWith(fontSize: 12)),
        ],
      ),
    );
  }

  Widget _edaSection(BuildContext context, StressEdaView v) {
    final hasSpots = v.spotChecks.isNotEmpty;
    if (hasSpots) {
      return const SizedBox.shrink(); // list below is enough
    }
    return _DashedBorder(
      color: HpiMetricColors.tint(HpiColors.eda, 0.35),
      radius: 20,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 24),
        child: Column(
          children: [
            Container(
              width: 48,
              height: 48,
              decoration: BoxDecoration(
                color: HpiMetricColors.tint(HpiColors.eda, 0.13),
                shape: BoxShape.circle,
              ),
              child: const Icon(Symbols.water_drop,
                  size: 24, color: HpiColors.eda),
            ),
            const SizedBox(height: 12),
            Text('No EDA spot checks yet', style: HpiText.cardTitle),
            const SizedBox(height: 6),
            Text(
              'EDA is a 30-second measurement taken on the watch. Swipe to the '
              'EDA screen and touch the electrodes to record one — it syncs '
              'here automatically.',
              textAlign: TextAlign.center,
              style: HpiText.body.copyWith(fontSize: 11.5),
            ),
            const SizedBox(height: 16),
            HpiTonalButton(
              label: 'How to measure',
              icon: Symbols.help,
              color: HpiColors.eda,
              onPressed: () => _showHowTo(context),
            ),
          ],
        ),
      ),
    );
  }

  Widget _recentSpotChecks(StressEdaView v) {
    final fmt = DateFormat('EEE · HH:mm');
    return HpiCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const HpiSectionLabel('RECENT EDA SPOT CHECKS'),
          if (v.spotChecks.isEmpty)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 8),
              child: Text(
                'No spot checks recorded on this device yet.',
                style: HpiText.body.copyWith(fontSize: 12),
              ),
            )
          else
            for (var i = 0; i < v.spotChecks.length; i++) ...[
              if (i > 0)
                const Divider(height: 1, color: HpiColors.divider),
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 10),
                child: Row(
                  children: [
                    Container(
                      width: 34,
                      height: 34,
                      decoration: BoxDecoration(
                        color: HpiMetricColors.tint(HpiColors.eda, 0.13),
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: const Icon(Symbols.water_drop,
                          size: 18, color: HpiColors.eda),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text('EDA stress index', style: HpiText.cardTitle),
                          Text(fmt.format(v.spotChecks[i].at),
                              style: HpiText.supporting),
                        ],
                      ),
                    ),
                    Text(
                      v.spotChecks[i].score.round().toString(),
                      style: HpiText.cardValue.copyWith(color: HpiColors.eda),
                    ),
                  ],
                ),
              ),
            ],
        ],
      ),
    );
  }

  String _stressLabel(double score) {
    if (score < 30) return 'Relaxed';
    if (score < 50) return 'Normal';
    if (score < 70) return 'Elevated';
    return 'High strain';
  }

  String _relative(DateTime t) {
    final d = DateTime.now().difference(t);
    if (d.inMinutes < 60) return '${d.inMinutes} m ago';
    if (d.inHours < 24) return '${d.inHours} h ago';
    return '${d.inDays} d ago';
  }

  void _showHowTo(BuildContext context) {
    showModalBottomSheet<void>(
      context: context,
      backgroundColor: HpiColors.surfaceContainer,
      showDragHandle: true,
      builder: (_) => Padding(
        padding: const EdgeInsets.fromLTRB(24, 4, 24, 32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Measure EDA on your watch', style: HpiText.appBarTitle),
            const SizedBox(height: 12),
            Text(
              '1. On the watch, swipe to the EDA screen.\n'
              '2. Rest two fingers on the electrode band.\n'
              '3. Hold still for the 30-second countdown.\n'
              'The reading syncs to the app automatically.',
              style: HpiText.body.copyWith(fontSize: 13, height: 1.6),
            ),
          ],
        ),
      ),
    );
  }
}

/// A dashed rounded-rect border wrapping a card-shaped child (the EDA empty
/// state). Kept local — the only dashed border in the redesign so far.
class _DashedBorder extends StatelessWidget {
  const _DashedBorder(
      {required this.child, required this.color, this.radius = 20});
  final Widget child;
  final Color color;
  final double radius;

  @override
  Widget build(BuildContext context) {
    return CustomPaint(
      painter: _DashedBorderPainter(color, radius),
      child: child,
    );
  }
}

class _DashedBorderPainter extends CustomPainter {
  _DashedBorderPainter(this.color, this.radius);
  final Color color;
  final double radius;

  @override
  void paint(Canvas canvas, Size size) {
    final rrect = RRect.fromRectAndRadius(
        Offset.zero & size, Radius.circular(radius));
    final path = Path()..addRRect(rrect);
    final dashed = Path();
    for (final metric in path.computeMetrics()) {
      double dist = 0;
      while (dist < metric.length) {
        dashed.addPath(metric.extractPath(dist, dist + 5), Offset.zero);
        dist += 10;
      }
    }
    canvas.drawPath(
      dashed,
      Paint()
        ..color = color
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.4,
    );
  }

  @override
  bool shouldRepaint(_DashedBorderPainter old) => old.color != color;
}
