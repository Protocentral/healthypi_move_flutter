// Copyright (c) 2024-2026 ProtoCentral
// SPDX-License-Identifier: MIT

import 'package:flutter/material.dart';
import 'package:material_symbols_icons/symbols.dart';

import '../data/health_repository.dart';
import '../theme/hpi_colors.dart';
import '../theme/hpi_text.dart';
import '../ui/components/hpi_components.dart';

/// Blood pressure — **relative wellness trend, not a measurement** (handoff
/// 6a/6b). The display counterpart to the 5b baseline set-up.
///
/// **Regulatory framing is the whole design (WHOOP/FDA, Jul 2025 → Jun 2026).**
/// The line that makes BP a regulated medical device is *clinical classification*,
/// not the presence of numbers. So this screen:
///  - shows an estimated mmHg **range**, never a single cuff-style value;
///  - compares today to the user's **own usual** on a **continuous** gradient —
///    no Normal/Elevated/Stage buckets, no diagnostic threshold lines, no shaded
///    "healthy corridor";
///  - uses **relative** language ("higher *for you*", never "high blood pressure")
///    and strong wellness disclaimers.
///
/// Gated on baseline state: 6a when a baseline + ≥1 estimate exist, else 6b. It
/// never fabricates a value.
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
      'Wellness estimate from finger PPG · shown as a range, not a cuff '
      'measurement · not for diagnosis — talk to a clinician about any concerns';

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final v = await _repo.loadBloodPressure();
    if (mounted) setState(() => _view = v);
  }

  Future<void> _setUp() async {
    await Navigator.of(context).pushNamed('/device/bpt-calibration');
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
            : (view.showValues ? _setUpView(view) : _gate(view)),
      ),
    );
  }

  // --- 6a — set up (has estimates) ------------------------------------------

  Widget _setUpView(BloodPressureView view) {
    final latest = view.latest!;
    final windowed = view.inRange(_range);
    final source = windowed.isEmpty ? view.readings : windowed;
    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 28),
      children: [
        _hero(view, latest),
        const SizedBox(height: 14),
        HpiSegmentedControl(
          segments: const ['Day', 'Week', 'Month', '6M'],
          selectedIndex: _range.index,
          onChanged: (i) => setState(() => _range = TrendRange.values[i]),
          accent: HpiColors.bpSys,
        ),
        const SizedBox(height: 14),
        _rangeChartCard(view, windowed),
        const SizedBox(height: 12),
        _vsUsualCard(view),
        const SizedBox(height: 12),
        _statChips(view, source),
        const SizedBox(height: 12),
        _recentEstimatesCard(view),
        const SizedBox(height: 12),
        _baselineFooter(view.baselineSetAt),
        const SizedBox(height: 14),
        _disclaimerLine(),
      ],
    );
  }

  Widget _hero(BloodPressureView view, BpReading latest) {
    final rel = _relOf(view.deviation(latest));
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
                    Text(_fmtRange(latest.sysRange),
                        style:
                            HpiText.heroNumberSm.copyWith(color: HpiColors.bpSys, fontSize: 28)),
                    Text(' / ',
                        style: HpiText.heroNumberSm
                            .copyWith(color: HpiColors.muted, fontSize: 28)),
                    Text(_fmtRange(latest.diaRange),
                        style:
                            HpiText.heroNumberSm.copyWith(color: HpiColors.bpDia, fontSize: 28)),
                    Text('  mmHg est.', style: HpiText.body.copyWith(fontSize: 11.5)),
                  ],
                ),
                const SizedBox(height: 8),
                HpiPill(label: rel.pill, color: rel.color),
              ],
            ),
          ),
          const SizedBox(width: 10),
          Text('estimated\n${_relDayTime(latest.at)}',
              textAlign: TextAlign.right, style: HpiText.supporting),
        ],
      ),
    );
  }

  /// Estimated-range chart: plain numeric mmHg axis, a faint neutral "your
  /// usual" band, and two connected-dot series. **No clinical target guides, no
  /// shaded healthy corridor** — that is the exact thing that crosses the line.
  Widget _rangeChartCard(BloodPressureView view, List<BpReading> windowed) {
    return HpiCard(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const HpiSectionLabel('ESTIMATED RANGE · LAST 7 DAYS'),
          const SizedBox(height: 10),
          if (windowed.length < 2)
            _sparseNote(windowed.length)
          else
            SizedBox(
              height: 150,
              child: CustomPaint(
                size: const Size(double.infinity, 150),
                painter: _BpRangePainter(
                  windowed,
                  usualSys: view.usualSys,
                  usualDia: view.usualDia,
                ),
              ),
            ),
          const SizedBox(height: 10),
          Row(
            children: [
              _legendDot(HpiColors.bpSys, 'Systolic'),
              const SizedBox(width: 12),
              _legendDot(HpiColors.bpDia, 'Diastolic'),
              const SizedBox(width: 12),
              _legendDot(HpiColors.faint, 'Your usual'),
            ],
          ),
          const SizedBox(height: 8),
          Text(
            'Daily estimate from finger PPG, shown as a range — not a cuff reading.',
            style: HpiText.supporting.copyWith(fontSize: 10),
          ),
        ],
      ),
    );
  }

  /// The continuous "vs your usual" gradient — the WHOOP-style relative scale.
  /// A single gradient with a marker where today sits; end labels only. **No
  /// discrete segments, no category names, no mmHg ticks.**
  Widget _vsUsualCard(BloodPressureView view) {
    final pos = view.todayVsUsual;
    return HpiCard(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const HpiSectionLabel('TODAY vs YOUR USUAL'),
          const SizedBox(height: 12),
          LayoutBuilder(builder: (context, c) {
            final w = c.maxWidth;
            return SizedBox(
              height: 22,
              child: Stack(
                clipBehavior: Clip.none,
                children: [
                  Container(
                    height: 10,
                    margin: const EdgeInsets.only(top: 8),
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(5),
                      gradient: const LinearGradient(colors: [
                        HpiColors.steps, // lower for you
                        Color(0xFF8FC93A),
                        Color(0xFFF5C24B),
                        HpiColors.temp,
                        HpiColors.error, // higher for you
                      ]),
                    ),
                  ),
                  // Marker where today sits on the personal scale.
                  Positioned(
                    left: (pos * w - 6).clamp(0.0, w - 12),
                    top: 0,
                    child: Container(
                      width: 12,
                      height: 22,
                      decoration: BoxDecoration(
                        color: HpiColors.onSurface,
                        borderRadius: BorderRadius.circular(3),
                        border: Border.all(color: HpiColors.background, width: 2),
                      ),
                    ),
                  ),
                ],
              ),
            );
          }),
          const SizedBox(height: 8),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text('Lower for you', style: HpiText.supporting.copyWith(fontSize: 10)),
              Text('Higher for you', style: HpiText.supporting.copyWith(fontSize: 10)),
            ],
          ),
          const SizedBox(height: 10),
          Text(
            'A continuous, personal scale of how today compares with your own '
            'usual — a wellness estimate, not a clinical category or diagnosis.',
            style: HpiText.body.copyWith(fontSize: 11.5, height: 1.45),
          ),
        ],
      ),
    );
  }

  Widget _statChips(BloodPressureView view, List<BpReading> source) {
    final s = _BpStats.from(view, source);
    return Row(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Expanded(
            child: _statChip(
                '7-DAY EST. AVG', s.avgLabel, HpiColors.onSurface)),
        const SizedBox(width: 10),
        Expanded(
            child: _statChip(
                'HIGHEST FOR YOU', s.highestWhen, HpiColors.bpSys)),
        const SizedBox(width: 10),
        Expanded(
            child: _statChip(
                'DAY-TO-DAY SWING', s.swingLabel, HpiColors.bpDia)),
      ],
    );
  }

  Widget _statChip(String label, String value, Color color) {
    return HpiCard(
      radius: 16,
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 11),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(value,
              style: HpiText.statChip.copyWith(color: color, fontSize: 16)),
          const SizedBox(height: 4),
          Text(label, style: HpiText.sectionLabel.copyWith(fontSize: 8.5)),
        ],
      ),
    );
  }

  Widget _recentEstimatesCard(BloodPressureView view) {
    final show = view.readings.take(8).toList();
    return HpiCard(
      padding: const EdgeInsets.fromLTRB(16, 14, 16, 6),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Expanded(child: HpiSectionLabel('RECENT ESTIMATES')),
              Text('spot · on watch',
                  style: HpiText.supporting.copyWith(fontSize: 9.5)),
            ],
          ),
          for (final r in show) _estimateRow(view, r),
          const SizedBox(height: 8),
        ],
      ),
    );
  }

  Widget _estimateRow(BloodPressureView view, BpReading r) {
    final rel = _relOf(view.deviation(r));
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 9),
      child: Row(
        children: [
          Container(
            width: 8,
            height: 8,
            decoration: BoxDecoration(color: rel.color, shape: BoxShape.circle),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(_relDayTime(r.at),
                    style: HpiText.cardTitle.copyWith(fontSize: 12.5)),
                const SizedBox(height: 2),
                Text('${rel.label} · finger PPG',
                    style: HpiText.supporting.copyWith(fontSize: 10)),
              ],
            ),
          ),
          Text('${_fmtRange(r.sysRange)}/${_fmtRange(r.diaRange)}',
              style: HpiText.valueSm.copyWith(fontSize: 13.5)),
        ],
      ),
    );
  }

  Widget _baselineFooter(DateTime? baselineSetAt) {
    final title = baselineSetAt == null
        ? 'Baseline set on this watch'
        : 'Baseline set ${_relTime(baselineSetAt)}';
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
                Text(title, style: HpiText.cardTitle.copyWith(fontSize: 12.5)),
                const SizedBox(height: 2),
                Text('Refresh with a cuff ~monthly to keep it accurate',
                    style: HpiText.supporting),
              ],
            ),
          ),
          GestureDetector(
            onTap: _setUp,
            behavior: HitTestBehavior.opaque,
            child: Text('Refresh',
                style: HpiText.cardTitle
                    .copyWith(color: HpiColors.hr, fontSize: 12.5)),
          ),
        ],
      ),
    );
  }

  // --- 6b — not set up (the gate) -------------------------------------------

  Widget _gate(BloodPressureView view) {
    // Second sub-state: this phone recorded a baseline but no estimate synced yet.
    final awaiting = view.hasBaseline;
    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 28),
      children: [
        _gateHero(awaiting ? 'NO ESTIMATES YET' : 'NOT SET'),
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
              Text(awaiting ? 'Waiting for an estimate' : 'Set up blood-pressure trends',
                  style: HpiText.screenTitle.copyWith(fontSize: 18),
                  textAlign: TextAlign.center),
              const SizedBox(height: 8),
              Text(
                awaiting
                    ? 'Your baseline is set. Take a reading on the watch, then '
                        'sync — your estimated range will appear here.'
                    : 'Setting up teaches the watch your personal baseline. After '
                        'that it shows a daily estimated range and how today '
                        'compares with your own usual — a wellness estimate, not a '
                        'cuff measurement. Refresh roughly monthly.',
                style: HpiText.body.copyWith(fontSize: 12.5, height: 1.45),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 18),
              HpiFilledButton(
                label: awaiting ? 'Refresh baseline' : 'Set up now',
                icon: awaiting ? Symbols.tune : Symbols.play_arrow,
                onPressed: _setUp,
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

  Widget _gateHero(String pillLabel) {
    return HpiCard(
      child: Row(
        children: [
          HpiIconSquare(
              icon: Symbols.show_chart,
              color: HpiColors.onSurfaceVariant,
              size: 44,
              iconSize: 22,
              dim: true),
          const SizedBox(width: 14),
          Expanded(
            child: Text('Not set up yet',
                style: HpiText.cardTitle.copyWith(fontSize: 15)),
          ),
          HpiPill(label: pillLabel),
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

  Widget _sparseNote(int n) {
    return Container(
      height: 96,
      alignment: Alignment.center,
      child: Text(
        n == 0
            ? 'No estimates in this range.\nTake a reading on the watch.'
            : 'Just one estimate in this range —\ntake more to see a trend.',
        textAlign: TextAlign.center,
        style: HpiText.body.copyWith(fontSize: 12),
      ),
    );
  }

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
          style: HpiText.supporting.copyWith(fontSize: 10),
          textAlign: TextAlign.center),
    );
  }

  String _fmtRange(List<int> r) => '${r[0]}–${r[1]}';

  String _relDayTime(DateTime t) {
    final now = DateTime.now();
    final ap = t.hour < 12 ? 'AM' : 'PM';
    final sameDay = t.year == now.year && t.month == now.month && t.day == now.day;
    if (sameDay) {
      final h = t.hour % 12 == 0 ? 12 : t.hour % 12;
      return '$h:${t.minute.toString().padLeft(2, '0')} $ap';
    }
    const days = ['Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun'];
    return '${days[t.weekday - 1]} $ap';
  }

  String _relTime(DateTime t) {
    final d = DateTime.now().difference(t);
    if (d.inMinutes < 60) return '${d.inMinutes} m ago';
    if (d.inHours < 24) return '${d.inHours} h ago';
    if (d.inDays < 30) return '${d.inDays} d ago';
    return '${t.year}-${t.month.toString().padLeft(2, '0')}-${t.day.toString().padLeft(2, '0')}';
  }
}

// --- Relative (personal) status — never a clinical category ------------------

/// A reading's position relative to the user's *own* usual. Deliberately only
/// three soft, personal buckets with "for you" language — this is not a clinical
/// classification (no Normal/Elevated/Stage), which is the WHOOP/FDA line.
enum _Rel {
  lower('Lower for you', 'LOWER FOR YOU', HpiColors.bpDia),
  typical('Typical for you', 'TYPICAL FOR YOU', HpiColors.steps),
  higher('Higher for you', 'HIGHER FOR YOU', HpiColors.temp);

  const _Rel(this.label, this.pill, this.color);
  final String label;
  final String pill;
  final Color color;
}

/// ±5 mmHg vs your usual is "typical for you"; beyond that, lower/higher. A
/// personal comparison, not a diagnostic threshold.
_Rel _relOf(double deviation) {
  if (deviation <= -5) return _Rel.lower;
  if (deviation >= 5) return _Rel.higher;
  return _Rel.typical;
}

/// The three stat chips, all framed relatively.
class _BpStats {
  const _BpStats({
    required this.avgLabel,
    required this.highestWhen,
    required this.swingLabel,
  });

  final String avgLabel; // "120/78" — a plain average, no verdict
  final String highestWhen; // "Tue AM" — when, not a scary number
  final String swingLabel; // Small / Moderate / Large — qualitative, personal

  factory _BpStats.from(BloodPressureView view, List<BpReading> source) {
    if (source.isEmpty) {
      return const _BpStats(avgLabel: '—', highestWhen: '—', swingLabel: '—');
    }
    var sumS = 0, sumD = 0;
    BpReading highest = source.first;
    double bestDev = view.deviation(highest);
    for (final r in source) {
      sumS += r.sysRaw;
      sumD += r.diaRaw;
      final dev = view.deviation(r);
      if (dev > bestDev) {
        bestDev = dev;
        highest = r;
      }
    }
    final avgS = (sumS / source.length).round();
    final avgD = (sumD / source.length).round();

    // Day-to-day swing: qualitative spread of the raw systolic values. Kept
    // fuzzy on purpose — a number here would invite a clinical reading.
    final sys = source.map((r) => r.sysRaw).toList()..sort();
    final spread = sys.last - sys.first;
    final swing = spread < 8 ? 'Small' : (spread < 16 ? 'Moderate' : 'Large');

    return _BpStats(
      avgLabel: '$avgS/$avgD',
      highestWhen: _dayAmPm(highest.at),
      swingLabel: swing,
    );
  }

  static String _dayAmPm(DateTime t) {
    const days = ['Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun'];
    return '${days[t.weekday - 1]} ${t.hour < 12 ? 'AM' : 'PM'}';
  }
}

/// The estimated-range chart: two connected-dot series (systolic rose /
/// diastolic blue) over a **faint neutral "your usual" band**. Plain numeric
/// mmHg axis. **No clinical target guides, no shaded healthy corridor, no
/// threshold lines** — that framing is what crosses the regulatory line.
class _BpRangePainter extends CustomPainter {
  _BpRangePainter(this.readings, {required this.usualSys, required this.usualDia});

  final List<BpReading> readings; // newest-first
  final int usualSys;
  final int usualDia;

  static const double _min = 60, _max = 140;

  @override
  void paint(Canvas canvas, Size size) {
    const leftPad = 6.0, rightLabel = 30.0, topPad = 6.0, botPad = 18.0;
    final plotW = size.width - leftPad - rightLabel;
    final plotH = size.height - topPad - botPad;
    double y(num v) => topPad + (_max - v.clamp(_min, _max)) / (_max - _min) * plotH;

    // Faint neutral "your usual" bands (±3 mmHg) — personal reference, NOT a
    // clinical target. No dashes, no labels that imply a threshold.
    final band = Paint()..color = const Color(0x0BFFFFFF);
    canvas.drawRect(
        Rect.fromLTRB(leftPad, y(usualSys + 3), leftPad + plotW, y(usualSys - 3)),
        band);
    canvas.drawRect(
        Rect.fromLTRB(leftPad, y(usualDia + 3), leftPad + plotW, y(usualDia - 3)),
        band);

    // Plain numeric axis — a scale is fine; there are no target guide-lines.
    for (final v in [140, 120, 100, 80, 60]) {
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
        final p = Offset(x(i), y(sel(ordered[i])));
        i == 0 ? path.moveTo(p.dx, p.dy) : path.lineTo(p.dx, p.dy);
      }
      canvas.drawPath(path, line);
      final dot = Paint()..color = color;
      for (var i = 0; i < n; i++) {
        canvas.drawCircle(Offset(x(i), y(sel(ordered[i]))), 3.5, dot);
      }
    }

    series((r) => r.diaRaw, HpiColors.bpDia);
    series((r) => r.sysRaw, HpiColors.bpSys);
  }

  @override
  bool shouldRepaint(_BpRangePainter old) =>
      old.readings != readings ||
      old.usualSys != usualSys ||
      old.usualDia != usualDia;
}
