import 'package:flutter/material.dart';
import 'package:material_symbols_icons/symbols.dart';

import '../theme/hpi_colors.dart';
import '../theme/hpi_text.dart';
import '../ui/charts/hpi_ring_gauge.dart';
import '../ui/components/hpi_components.dart';

/// Stress & EDA (handoff 1e with data / 2b zero-state). The app has no
/// stress-index or EDA producing code yet, so this always renders the honest
/// zero-state: the stress ring shows no value (never a fabricated one), and EDA
/// explains that a spot check is taken on the watch. The layout matches 1e so
/// the populated version drops in unchanged once the data source exists.
class ScrStressEda extends StatelessWidget {
  const ScrStressEda({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: HpiColors.background,
      appBar: AppBar(
        title: const Text('Stress & EDA'),
        actions: const [
          Padding(
            padding: EdgeInsets.only(right: 12),
            child: Icon(Symbols.ios_share, size: 20),
          ),
        ],
      ),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.fromLTRB(16, 16, 16, 28),
          children: [
            _hero(),
            const SizedBox(height: 12),
            _edaEmptyState(context),
            const SizedBox(height: 12),
            _recentSpotChecks(),
          ],
        ),
      ),
    );
  }

  Widget _hero() {
    return HpiCard(
      child: Row(
        children: [
          SizedBox(
            width: 96,
            height: 96,
            child: HpiRingGauge(
              fraction: 0,
              color: HpiColors.stress,
              strokeWidth: 10,
              center: Text('—',
                  style: HpiText.heroNumberSm.copyWith(color: HpiColors.muted)),
            ),
          ),
          const SizedBox(width: 18),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('Continuous · from HRV',
                    style: HpiText.cardTitle.copyWith(color: HpiColors.stress)),
                const SizedBox(height: 4),
                Text('Not yet available', style: HpiText.supporting),
                const SizedBox(height: 10),
                Text(
                  'Stress index runs all day from heart-rate variability. EDA '
                  'adds skin-response detail when you take a spot check.',
                  style: HpiText.body.copyWith(fontSize: 11.5),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _edaEmptyState(BuildContext context) {
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
              child: const Icon(Symbols.water_drop, size: 24, color: HpiColors.eda),
            ),
            const SizedBox(height: 12),
            Text('No EDA spot checks today', style: HpiText.cardTitle),
            const SizedBox(height: 6),
            Text(
              'EDA is a 30-second measurement taken on the watch. Swipe to the '
              'EDA screen and touch the electrodes to record one.',
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

  Widget _recentSpotChecks() {
    return HpiCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const HpiSectionLabel('RECENT SPOT CHECKS'),
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 8),
            child: Text('No spot checks recorded on this device yet.',
                style: HpiText.body.copyWith(fontSize: 12)),
          ),
        ],
      ),
    );
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
