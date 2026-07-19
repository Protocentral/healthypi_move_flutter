// Copyright (c) 2024-2026 ProtoCentral
// SPDX-License-Identifier: MIT

import 'package:flutter/material.dart';
import 'package:material_symbols_icons/symbols.dart';

import '../data/health_repository.dart';
import '../theme/hpi_colors.dart';
import '../theme/hpi_text.dart';
import '../ui/components/hpi_components.dart';

/// Blood-pressure values + trend (handoff 6a/6b) — the screen that *displays*
/// the BPT estimates the watch produces after calibration (5b only calibrates).
///
/// BP is an **`HsClass.event`** metric: sparse spot readings, listed with
/// timestamps, never averaged into a fake per-hour value or drawn as a
/// candlestick. The screen is **gated on calibration state**: 6a when calibrated
/// with ≥1 reading, else the 6b not-calibrated gate.
///
/// **Non-diagnostic by hard requirement** — the watch is not a certified medical
/// device, so this never asserts a clinical BP category. Healthy ranges show
/// only *indirectly* (a shaded reference corridor + faint boundary ticks) with a
/// plain-language explanation and a repeated "not a medical device" disclaimer.
class ScrBloodPressure extends StatefulWidget {
  const ScrBloodPressure({super.key});

  @override
  State<ScrBloodPressure> createState() => _ScrBloodPressureState();
}

class _ScrBloodPressureState extends State<ScrBloodPressure> {
  final _repo = HealthRepository();
  BloodPressureView? _view;
  TrendRange _range = TrendRange.week;

  static const _disclaimer =
      'Cuffless estimate from finger PPG · not a medical device';

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final v = await _repo.loadBloodPressure();
    if (mounted) setState(() => _view = v);
  }

  Future<void> _calibrate() async {
    await Navigator.of(context).pushNamed('/device/bpt-calibration');
    // Returning from calibration may have flipped the calibrated flag / added
    // readings — reload so the gate re-evaluates.
    if (mounted) _load();
  }

  @override
  Widget build(BuildContext context) {
    final view = _view;
    return Scaffold(
      backgroundColor: HpiColors.background,
      appBar: AppBar(
        elevation: 0,
        backgroundColor: HpiColors.background,
        leading: IconButton(
          icon: const Icon(Symbols.arrow_back, color: HpiColors.onSurfaceBright),
          onPressed: () => Navigator.of(context).maybePop(),
        ),
        title: Text('Blood pressure', style: HpiText.appBarTitle),
        centerTitle: false,
        actions: [
          if (view?.showValues ?? false)
            IconButton(
              icon: const Icon(Symbols.ios_share,
                  size: 20, color: HpiColors.onSurfaceBright),
              onPressed: () {},
            ),
        ],
      ),
      body: SafeArea(
        child: view == null
            ? const Center(child: CircularProgressIndicator(color: HpiColors.bpSys))
            : (view.showValues ? _calibrated(view) : _notCalibrated(view)),
      ),
    );
  }

  // --- 6a — calibrated (has readings) ---------------------------------------

  Widget _calibrated(BloodPressureView view) {
    final latest = view.latest!;
    final windowed = view.inRange(_range);
    final stats = _BpStats.from(windowed.isEmpty ? view.readings : windowed);
    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 28),
      children: [
        _hero(latest),
        const SizedBox(height: 14),
        HpiSegmentedControl(
          segments: const ['Day', 'Week', 'Month', '6M'],
          selectedIndex: _range.index,
          onChanged: (i) => setState(() => _range = TrendRange.values[i]),
          accent: HpiColors.bpSys,
        ),
        const SizedBox(height: 14),
        _trendCard(windowed),
        const SizedBox(height: 12),
        _whereThisSitsCard(latest),
        const SizedBox(height: 12),
        _statChips(stats),
        const SizedBox(height: 12),
        _recentReadingsCard(view.readings),
        const SizedBox(height: 12),
        _calibrationFooter(view.calibratedAt),
        const SizedBox(height: 14),
        _disclaimerLine(),
      ],
    );
  }

  Widget _hero(BpReading latest) {
    return HpiCard(
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  crossAxisAlignment: CrossAxisAlignment.baseline,
                  textBaseline: TextBaseline.alphabetic,
                  children: [
                    Text('${latest.systolic}',
                        style: HpiText.heroNumberSm.copyWith(color: HpiColors.bpSys)),
                    Text(' / ',
                        style: HpiText.heroNumberSm.copyWith(color: HpiColors.muted)),
                    Text('${latest.diastolic}',
                        style: HpiText.heroNumberSm.copyWith(color: HpiColors.bpDia)),
                    Text('  mmHg',
                        style: HpiText.body.copyWith(fontSize: 12.5)),
                  ],
                ),
                const SizedBox(height: 8),
                const HpiPill(label: 'TYPICAL RANGE', color: HpiColors.steps),
              ],
            ),
          ),
          const SizedBox(width: 10),
          Text('last reading\n${_absTime(latest.at)}',
              textAlign: TextAlign.right,
              style: HpiText.supporting),
        ],
      ),
    );
  }

  Widget _trendCard(List<BpReading> windowed) {
    return HpiCard(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                  child: Text('SYSTOLIC / DIASTOLIC · ${_rangeLabel()}',
                      style: HpiText.sectionLabel)),
              Text(windowed.isEmpty ? 'no readings' : 'in range',
                  style: HpiText.supporting.copyWith(
                      color: windowed.isEmpty
                          ? HpiColors.muted
                          : HpiColors.steps)),
            ],
          ),
          const SizedBox(height: 12),
          if (windowed.length < 2)
            _sparseNote(windowed.length)
          else
            SizedBox(
              height: 140,
              child: CustomPaint(
                size: const Size(double.infinity, 140),
                painter: _BpTrendPainter(windowed),
              ),
            ),
          const SizedBox(height: 12),
          Row(
            children: [
              _legendDot(HpiColors.bpSys, 'Systolic'),
              const SizedBox(width: 14),
              _legendDot(HpiColors.bpDia, 'Diastolic'),
              const Spacer(),
              Text('shaded = typical corridor',
                  style: HpiText.supporting.copyWith(fontSize: 9.5)),
            ],
          ),
        ],
      ),
    );
  }

  Widget _sparseNote(int n) {
    return Container(
      height: 90,
      alignment: Alignment.center,
      child: Text(
        n == 0
            ? 'No readings in this range.\nTake a reading on the watch.'
            : 'Just one reading in this range —\ntake more to see a trend.',
        textAlign: TextAlign.center,
        style: HpiText.body.copyWith(fontSize: 12),
      ),
    );
  }

  /// The non-clinical classifier: a 4-segment bar with the current reading's
  /// position marked, faint reference ticks, and a plain-language explanation.
  /// It never asserts a medical BP category.
  Widget _whereThisSitsCard(BpReading latest) {
    final idx = _categoryIndex(latest.systolic, latest.diastolic);
    return HpiCard(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const HpiSectionLabel('WHERE THIS SITS'),
          const SizedBox(height: 4),
          SizedBox(
            height: 40,
            child: CustomPaint(
              size: const Size(double.infinity, 40),
              painter: _ClassifierBarPainter(idx),
            ),
          ),
          const SizedBox(height: 8),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              for (var i = 0; i < _catLabels.length; i++)
                Text(_catLabels[i],
                    style: HpiText.supporting.copyWith(
                        fontSize: 9.5,
                        color: i == idx ? _catColors[i] : HpiColors.muted,
                        fontWeight:
                            i == idx ? FontWeight.w800 : FontWeight.w600)),
            ],
          ),
          const SizedBox(height: 12),
          Text(
            'Reference boundaries (≈ under 120/80 at rest), not thresholds the '
            'watch judges you against. General guidance, not a diagnosis — '
            'confirm anything concerning with a validated cuff and a clinician.',
            style: HpiText.body.copyWith(fontSize: 11.5, height: 1.45),
          ),
        ],
      ),
    );
  }

  Widget _statChips(_BpStats s) {
    return Row(
      children: [
        Expanded(
            child: _bpStatChip('7-DAY AVG',
                '${s.avgSys}/${s.avgDia}', HpiColors.onSurface)),
        const SizedBox(width: 10),
        Expanded(
            child: _bpStatChip(
                'HIGHEST', '${s.maxSys}/${s.maxDia}', HpiColors.bpSys)),
        const SizedBox(width: 10),
        Expanded(
            child: _bpStatChip(
                'LOWEST', '${s.minSys}/${s.minDia}', HpiColors.bpDia)),
      ],
    );
  }

  Widget _bpStatChip(String label, String value, Color color) {
    return HpiCard(
      radius: 16,
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 11),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(value,
              style: HpiText.statChip.copyWith(color: color, fontSize: 17)),
          const SizedBox(height: 4),
          Text(label, style: HpiText.sectionLabel.copyWith(fontSize: 9)),
        ],
      ),
    );
  }

  Widget _recentReadingsCard(List<BpReading> readings) {
    final show = readings.take(8).toList();
    return HpiCard(
      padding: const EdgeInsets.fromLTRB(16, 14, 16, 6),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Expanded(child: HpiSectionLabel('RECENT READINGS')),
              Text('spot · on watch', style: HpiText.supporting.copyWith(fontSize: 9.5)),
            ],
          ),
          for (final r in show) _readingRow(r),
          const SizedBox(height: 8),
        ],
      ),
    );
  }

  Widget _readingRow(BpReading r) {
    final idx = _categoryIndex(r.systolic, r.diastolic);
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 9),
      child: Row(
        children: [
          Container(
            width: 8,
            height: 8,
            decoration:
                BoxDecoration(color: _catColors[idx], shape: BoxShape.circle),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(_relTime(r.at), style: HpiText.cardTitle.copyWith(fontSize: 12.5)),
                const SizedBox(height: 2),
                Text('${_catLabels[idx]} · finger PPG',
                    style: HpiText.supporting.copyWith(fontSize: 10)),
              ],
            ),
          ),
          Text('${r.systolic}/${r.diastolic}',
              style: HpiText.valueSm.copyWith(fontSize: 15)),
        ],
      ),
    );
  }

  Widget _calibrationFooter(DateTime? calibratedAt) {
    final ago = calibratedAt == null ? '—' : _relTime(calibratedAt);
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: HpiMetricColors.tint(HpiColors.hr, 0.10),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: HpiMetricColors.tint(HpiColors.hr, 0.22)),
      ),
      child: Row(
        children: [
          const Icon(Symbols.tune, size: 20, color: HpiColors.hr),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('Calibrated $ago',
                    style: HpiText.cardTitle.copyWith(fontSize: 12.5)),
                const SizedBox(height: 2),
                Text('Recalibrate ~monthly for accuracy',
                    style: HpiText.supporting),
              ],
            ),
          ),
          GestureDetector(
            onTap: _calibrate,
            behavior: HitTestBehavior.opaque,
            child: Text('Recalibrate',
                style: HpiText.cardTitle
                    .copyWith(color: HpiColors.hr, fontSize: 12.5)),
          ),
        ],
      ),
    );
  }

  // --- 6b — not calibrated (the gate) ---------------------------------------

  Widget _notCalibrated(BloodPressureView view) {
    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 28),
      children: [
        _gateHero(),
        const SizedBox(height: 14),
        HpiCard(
          padding: const EdgeInsets.all(20),
          child: Column(
            children: [
              HpiIconSquare(
                  icon: Symbols.monitor_heart,
                  color: HpiColors.bpSys,
                  size: 64,
                  iconSize: 34),
              const SizedBox(height: 16),
              Text('Calibrate to enable BP',
                  style: HpiText.screenTitle.copyWith(fontSize: 18),
                  textAlign: TextAlign.center),
              const SizedBox(height: 8),
              Text(
                'The watch estimates blood pressure from finger PPG. It needs '
                '3 reference cuff readings before it can produce a value — a '
                'one-time setup, repeated roughly monthly.',
                style: HpiText.body.copyWith(fontSize: 12.5, height: 1.45),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 18),
              HpiFilledButton(
                label: 'Calibrate now',
                icon: Symbols.play_arrow,
                onPressed: _calibrate,
              ),
            ],
          ),
        ),
        const SizedBox(height: 12),
        HpiGroupedCard(rows: [
          _infoRow(Symbols.timer, 'Duration', '3–5 minutes'),
          _infoRow(Symbols.sensors, 'Readings', '3 points · finger PPG'),
          _infoRow(Symbols.medical_services, "You'll need",
              'Cuff BP monitor + finger sensor'),
        ]),
        const SizedBox(height: 14),
        _disclaimerLine(),
      ],
    );
  }

  Widget _gateHero() {
    return HpiCard(
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.baseline,
              textBaseline: TextBaseline.alphabetic,
              children: [
                Text('--',
                    style: HpiText.heroNumberSm.copyWith(color: HpiColors.disabled)),
                Text(' / ',
                    style: HpiText.heroNumberSm.copyWith(color: HpiColors.disabled)),
                Text('--',
                    style: HpiText.heroNumberSm.copyWith(color: HpiColors.disabled)),
                Text('  mmHg', style: HpiText.body.copyWith(fontSize: 12.5)),
              ],
            ),
          ),
          const HpiPill(label: 'NOT CALIBRATED'),
        ],
      ),
    );
  }

  Widget _infoRow(IconData icon, String label, String value) {
    return HpiListRow(
      icon: icon,
      iconColor: HpiColors.bpSys,
      title: label,
      supporting: value,
      supportingColor: HpiColors.onSurfaceVariant,
      showChevron: false,
    );
  }

  // --- shared ---------------------------------------------------------------

  Widget _legendDot(Color color, String label) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
            width: 8,
            height: 8,
            decoration: BoxDecoration(color: color, shape: BoxShape.circle)),
        const SizedBox(width: 6),
        Text(label, style: HpiText.supporting.copyWith(fontSize: 10)),
      ],
    );
  }

  Widget _disclaimerLine() {
    return Center(
      child: Text(_disclaimer,
          style: HpiText.supporting.copyWith(fontSize: 10), textAlign: TextAlign.center),
    );
  }

  String _rangeLabel() => switch (_range) {
        TrendRange.day => 'LAST 24 H',
        TrendRange.week => 'LAST 7 DAYS',
        TrendRange.month => 'THIS MONTH',
        TrendRange.sixMonths => 'LAST 6 MONTHS',
      };

  String _absTime(DateTime t) {
    final h = t.hour % 12 == 0 ? 12 : t.hour % 12;
    final m = t.minute.toString().padLeft(2, '0');
    final ap = t.hour < 12 ? 'AM' : 'PM';
    return '$h:$m $ap';
  }

  String _relTime(DateTime t) {
    final d = DateTime.now().difference(t);
    if (d.inMinutes < 1) return 'just now';
    if (d.inMinutes < 60) return '${d.inMinutes} m ago';
    if (d.inHours < 24) return '${d.inHours} h ago';
    if (d.inDays < 30) return '${d.inDays} d ago';
    return '${t.year}-${t.month.toString().padLeft(2, '0')}-${t.day.toString().padLeft(2, '0')}';
  }
}

// --- Non-clinical categorisation (reference boundaries, not a diagnosis) -----

const _catLabels = ['Typical', 'Higher', 'Elevated', 'Very high'];
const _catColors = [HpiColors.steps, HpiColors.hr, HpiColors.temp, HpiColors.error];

/// Map a reading to one of four descriptive bands using reference boundaries
/// (≈120/80, 130, 140/90). Deliberately **not** a clinical classification —
/// labels are plain-language ("Higher", not "Stage 1 hypertension").
int _categoryIndex(int sys, int dia) {
  if (sys >= 140 || dia >= 90) return 3; // Very high
  if (sys >= 130 || dia >= 80) return 2; // Elevated
  if (sys >= 120) return 1; // Higher
  return 0; // Typical
}

/// Windowed min/avg/max for the three stat chips.
class _BpStats {
  const _BpStats({
    required this.avgSys,
    required this.avgDia,
    required this.minSys,
    required this.minDia,
    required this.maxSys,
    required this.maxDia,
  });

  final int avgSys, avgDia, minSys, minDia, maxSys, maxDia;

  factory _BpStats.from(List<BpReading> rs) {
    if (rs.isEmpty) {
      return const _BpStats(
          avgSys: 0, avgDia: 0, minSys: 0, minDia: 0, maxSys: 0, maxDia: 0);
    }
    var sumS = 0, sumD = 0, minS = 999, minD = 999, maxS = 0, maxD = 0;
    for (final r in rs) {
      sumS += r.systolic;
      sumD += r.diastolic;
      minS = r.systolic < minS ? r.systolic : minS;
      minD = r.diastolic < minD ? r.diastolic : minD;
      maxS = r.systolic > maxS ? r.systolic : maxS;
      maxD = r.diastolic > maxD ? r.diastolic : maxD;
    }
    return _BpStats(
      avgSys: (sumS / rs.length).round(),
      avgDia: (sumD / rs.length).round(),
      minSys: minS,
      minDia: minD,
      maxSys: maxS,
      maxDia: maxD,
    );
  }
}

/// The dual connected-dot series (systolic rose / diastolic blue) over a
/// shaded typical corridor (120↔80) with dashed reference guides. Event-class:
/// dots joined by lines, never bars/candles.
class _BpTrendPainter extends CustomPainter {
  _BpTrendPainter(this.readings);

  /// Newest-first from the repo; drawn oldest→newest left→right.
  final List<BpReading> readings;

  static const double _min = 60, _max = 140; // mmHg y-range

  @override
  void paint(Canvas canvas, Size size) {
    const leftPad = 6.0, rightLabel = 30.0, topPad = 6.0, botPad = 18.0;
    final plotW = size.width - leftPad - rightLabel;
    final plotH = size.height - topPad - botPad;
    double y(num v) => topPad + (_max - v) / (_max - _min) * plotH;

    // Shaded typical corridor between 120 and 80.
    canvas.drawRect(
      Rect.fromLTRB(leftPad, y(120), leftPad + plotW, y(80)),
      Paint()..color = const Color(0x0BFFFFFF),
    );

    // Dashed reference guides at 120 (rose) and 80 (blue), + right labels.
    _dashedLine(canvas, leftPad, leftPad + plotW, y(120),
        HpiColors.bpSys.withValues(alpha: 0.5));
    _dashedLine(canvas, leftPad, leftPad + plotW, y(80),
        HpiColors.bpDia.withValues(alpha: 0.5));
    for (final v in [140, 120, 80, 60]) {
      final tp = TextPainter(
        text: TextSpan(
            text: '$v',
            style: const TextStyle(
                fontFamily: 'Rubik', fontSize: 9, color: HpiColors.faint)),
        textDirection: TextDirection.ltr,
      )..layout();
      tp.paint(canvas, Offset(leftPad + plotW + 6, y(v) - tp.height / 2));
    }

    final ordered = readings.reversed.toList(); // oldest → newest
    final n = ordered.length;
    double x(int i) => n == 1 ? leftPad + plotW / 2 : leftPad + i / (n - 1) * plotW;

    void series(int Function(BpReading) sel, Color color) {
      final line = Paint()
        ..color = color
        ..strokeWidth = 2.2
        ..style = PaintingStyle.stroke
        ..strokeCap = StrokeCap.round
        ..strokeJoin = StrokeJoin.round;
      final path = Path();
      for (var i = 0; i < n; i++) {
        final p = Offset(x(i), y(sel(ordered[i]).clamp(_min, _max)));
        if (i == 0) {
          path.moveTo(p.dx, p.dy);
        } else {
          path.lineTo(p.dx, p.dy);
        }
      }
      canvas.drawPath(path, line);
      final dot = Paint()..color = color;
      for (var i = 0; i < n; i++) {
        canvas.drawCircle(
            Offset(x(i), y(sel(ordered[i]).clamp(_min, _max))), 3.5, dot);
      }
    }

    series((r) => r.diastolic, HpiColors.bpDia);
    series((r) => r.systolic, HpiColors.bpSys);
  }

  void _dashedLine(Canvas canvas, double x0, double x1, double y, Color color) {
    final paint = Paint()
      ..color = color
      ..strokeWidth = 1;
    const dash = 4.0, gap = 4.0;
    for (var x = x0; x < x1; x += dash + gap) {
      canvas.drawLine(
          Offset(x, y), Offset((x + dash).clamp(x0, x1), y), paint);
    }
  }

  @override
  bool shouldRepaint(_BpTrendPainter old) => old.readings != readings;
}

/// The 4-segment "where this sits" bar with a marker triangle over the active
/// segment and faint reference boundary ticks (120/80 · 130 · 140/90).
class _ClassifierBarPainter extends CustomPainter {
  _ClassifierBarPainter(this.activeIndex);
  final int activeIndex;

  @override
  void paint(Canvas canvas, Size size) {
    const barH = 8.0;
    final barTop = 10.0;
    final segW = size.width / 4;
    for (var i = 0; i < 4; i++) {
      final r = Rect.fromLTWH(i * segW + 1, barTop, segW - 2, barH);
      final rr = RRect.fromRectAndCorners(
        r,
        topLeft: Radius.circular(i == 0 ? 4 : 0),
        bottomLeft: Radius.circular(i == 0 ? 4 : 0),
        topRight: Radius.circular(i == 3 ? 4 : 0),
        bottomRight: Radius.circular(i == 3 ? 4 : 0),
      );
      canvas.drawRRect(
        rr,
        Paint()
          ..color = i == activeIndex
              ? _catColors[i]
              : _catColors[i].withValues(alpha: 0.28),
      );
    }

    // Marker triangle over the active segment's centre.
    final mx = activeIndex * segW + segW / 2;
    final tri = Path()
      ..moveTo(mx, barTop - 2)
      ..lineTo(mx - 5, barTop - 9)
      ..lineTo(mx + 5, barTop - 9)
      ..close();
    canvas.drawPath(tri, Paint()..color = HpiColors.onSurface);

    // Faint boundary ticks under the bar at the 3 segment joins.
    const ticks = ['120/80', '130', '140/90'];
    for (var i = 1; i < 4; i++) {
      final tx = i * segW;
      canvas.drawLine(
        Offset(tx, barTop + barH),
        Offset(tx, barTop + barH + 4),
        Paint()..color = HpiColors.faint,
      );
      final tp = TextPainter(
        text: TextSpan(
            text: ticks[i - 1],
            style: const TextStyle(
                fontFamily: 'JetBrains Mono',
                fontSize: 8,
                color: HpiColors.faint)),
        textDirection: TextDirection.ltr,
      )..layout();
      tp.paint(canvas, Offset(tx - tp.width / 2, barTop + barH + 6));
    }
  }

  @override
  bool shouldRepaint(_ClassifierBarPainter old) =>
      old.activeIndex != activeIndex;
}
