// Copyright (c) 2024-2026 ProtoCentral
// SPDX-License-Identifier: MIT

import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:healthypi_healthy_store/healthypi_healthy_store.dart';
import 'package:material_symbols_icons/symbols.dart';
import 'package:share_plus/share_plus.dart';

import '../models/hs_recording.dart';
import '../theme/hpi_colors.dart';
import '../theme/hpi_text.dart';
import '../ui/components/hpi_components.dart';
import '../utils/device_manager.dart';
import '../utils/healthy_store_records_manager.dart';
import '../utils/hrv_analysis.dart';
import '../utils/signal_view.dart';

/// Recording preview + CSV export (handoff 2d) for HPI_HS **RECORDS** payloads.
///
/// Decodes with [HsRecordSamples] (bytes-per-sample inferred from the header).
class ScrRecordingPreview extends StatefulWidget {
  const ScrRecordingPreview({
    super.key,
    required this.recording,
    required this.payload,
  });

  final HsRecording recording;
  final Uint8List payload;

  @override
  State<ScrRecordingPreview> createState() => _ScrRecordingPreviewState();
}

class _ScrRecordingPreviewState extends State<ScrRecordingPreview> {
  bool _exporting = false;
  double _windowStart = 0;
  double _windowWidth = 0.2;
  late HsRecordSamples _samples;

  /// HRV for this record, when it has any: measured off the watch's own R-R
  /// intervals for an HRV record, or off detected R peaks for an ECG record.
  /// Null for signals with no beats in them (PPG/GSR/IMU).
  HrvMetrics? _hrv;

  /// The interval series behind [_hrv] — drives the tachogram.
  RrSeries? _rr;

  @override
  void initState() {
    super.initState();
    _samples = HsRecordSamples.decode(widget.recording.header, widget.payload);
    _computeHrv();
  }

  /// Derive HRV once, at decode time.
  ///
  /// R-peak detection over a multi-minute ECG is O(n) but not free, and this
  /// screen rebuilds on every zoom and pan — running it in `build` would redo
  /// the whole pass on each frame of a drag.
  void _computeHrv() {
    final r = widget.recording;
    if (_samples.data.isEmpty || _samples.data.first.isEmpty) return;
    final channel = _samples.data.first;

    if (r.kind == HsRecordingKind.hrv) {
      // Already intervals in milliseconds — no detection to do.
      final series = RrSeries.filtered(channel);
      _rr = series;
      _hrv = HrvMetrics.from(series);
    } else if (r.kind == HsRecordingKind.ecg && r.sampleRate > 0) {
      final result = hrvFromEcg(channel, sampleRate: r.sampleRate);
      _rr = result.series;
      _hrv = result.metrics;
    }
  }

  bool get _isEcg => widget.recording.kind == HsRecordingKind.ecg;

  /// True for an R-R record: intervals, not a fixed-rate waveform.
  bool get _isRr => widget.recording.isIntervalSeries;

  /// Elapsed time of an R-R record, in seconds.
  ///
  /// The running sum of the intervals — the only honest answer, and why
  /// [HsRecording.durationSeconds] returns 0 for these. Uses the *raw* decoded
  /// values rather than the artifact-filtered series, because a rejected beat
  /// still consumed wall-clock time.
  int get _rrDurationSeconds {
    if (_samples.data.isEmpty || _samples.data.first.isEmpty) return 0;
    final totalMs = _samples.data.first.reduce((a, b) => a + b);
    return (totalMs / 1000).round();
  }

  List<List<double>> get _channels => _samples.data;

  Color get _signalColor {
    switch (widget.recording.kind) {
      case HsRecordingKind.imu:
        return HpiColors.steps;
      case HsRecordingKind.gsr:
        return HpiColors.eda;
      case HsRecordingKind.ecg:
      case HsRecordingKind.hrv:
        return HpiColors.hr;
      case HsRecordingKind.ppg:
      case HsRecordingKind.other:
        return HpiColors.spo2;
    }
  }

  Future<void> _exportCsv() => _export(
        (m) => m.exportCsv(widget.recording, widget.payload),
        'HealthyPi recording',
      );

  /// Export the R-R intervals this screen derived from the ECG — the reference
  /// series for validating the watch's own HRV against a known-good source.
  Future<void> _exportRr() => _export(
        (m) => m.exportEcgRrCsv(widget.recording, widget.payload),
        'HealthyPi ECG-derived R-R intervals',
      );

  Future<void> _export(
    Future<File> Function(HealthyStoreRecordsManager m) build,
    String shareText,
  ) async {
    setState(() => _exporting = true);
    final device = await DeviceManager.getPairedDevice();
    final m = HealthyStoreRecordsManager(device?.macAddress ?? '');
    try {
      final file = await build(m);
      if (!mounted) return;
      await SharePlus.instance
          .share(ShareParams(files: [XFile(file.path)], text: shareText));
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
            content: Text('Export failed: $e'),
            backgroundColor: HpiColors.error));
      }
    } finally {
      if (mounted) setState(() => _exporting = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final s = widget.recording;
    final multi = _channels.length > 1;

    return Scaffold(
      backgroundColor: HpiColors.background,
      appBar: AppBar(
        title: Text('${s.kindLabel} · '
            '${_dur(_isRr ? _rrDurationSeconds : s.durationSeconds)}'),
      ),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 28),
          children: [
            Text(
              // No "Hz" for an interval series — the header's sampleRate is not
              // a rate there, and printing it as one invites the reader to
              // divide by it.
              '${_when(s.startTime)} · '
              '${_isRr ? "${s.beats} beats" : "${s.sampleRate} Hz"} · '
              '${_size(widget.payload.length)}'
              '${s.isPartial ? " · partial" : ""}'
              '${_samples.assumed ? " · format inferred" : ""}',
              style: HpiText.mono.copyWith(fontSize: 10.5),
            ),
            const SizedBox(height: 14),
            if (_channels.isEmpty || _channels.first.isEmpty)
              _noSamples()
            else ...[
              // An R-R record gets the tachogram in the HRV card instead of the
              // waveform pair. The minimap and detail charts draw a fixed-rate
              // trace against an `i / sampleRate` axis, which for intervals is a
              // plausible-looking picture of nothing.
              if (!_isRr) ...[
                _minimapCard(),
                const SizedBox(height: 12),
                _detailCard(multi: multi),
                const SizedBox(height: 12),
                _statsRow(),
                const SizedBox(height: 12),
              ],
              if (_hrv != null) _hrvCard(_hrv!),
              const SizedBox(height: 16),
              HpiFilledButton(
                label: _exporting
                    ? 'Exporting…'
                    : 'Export CSV · ${_size(widget.payload.length)}',
                icon: Symbols.download,
                onPressed: _exporting ? null : _exportCsv,
              ),
              if (_isEcg && _hrv != null) ...[
                const SizedBox(height: 10),
                HpiTonalButton(
                  label: 'Export R-R intervals (HRV)',
                  icon: Symbols.download,
                  onPressed: _exporting ? null : _exportRr,
                ),
              ],
              const SizedBox(height: 10),
              Text(
                _isEcg
                    ? 'Waveform CSV uses a shared t_ms timebase from the '
                        'session start. The R-R export is one row per beat, '
                        'timed from its own R peak.'
                    : (widget.recording.kind == HsRecordingKind.hrv
                        ? 'CSV is one row per beat: interval, instantaneous '
                            'rate, and whether the artifact filter kept it.'
                        : 'CSV uses a shared t_ms timebase from the session '
                            'start.'),
                style: HpiText.supporting,
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _minimapCard() {
    return HpiCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const HpiSectionLabel('FULL SESSION'),
          LayoutBuilder(
            builder: (context, box) {
              final w = box.maxWidth;
              return GestureDetector(
                behavior: HitTestBehavior.opaque,
                onTapDown: (d) => _moveWindow(d.localPosition.dx / w),
                onHorizontalDragUpdate: (d) =>
                    _moveWindow(d.localPosition.dx / w),
                child: SizedBox(
                  height: 52,
                  child: CustomPaint(
                    painter: _MinimapPainter(
                      channel: _channels.first,
                      color: _signalColor,
                      windowStart: _windowStart,
                      windowWidth: _windowWidth,
                    ),
                  ),
                ),
              );
            },
          ),
          const SizedBox(height: 6),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text('0:00', style: HpiText.mono.copyWith(fontSize: 9)),
              Text(_dur(widget.recording.durationSeconds),
                  style: HpiText.mono.copyWith(fontSize: 9)),
            ],
          ),
        ],
      ),
    );
  }

  void _moveWindow(double centerFraction) {
    final half = _windowWidth / 2;
    setState(() => _windowStart =
        (centerFraction - half).clamp(0.0, 1.0 - _windowWidth));
  }

  Widget _detailCard({required bool multi}) {
    return HpiCard(
      waveform: true,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Text(widget.recording.kindLabel.toUpperCase(),
                  style: HpiText.sectionLabel.copyWith(color: _signalColor)),
              const Spacer(),
              if (multi)
                Text(
                  [for (var i = 0; i < _channels.length; i++) 'CH$i'].join('  '),
                  style: HpiText.mono.copyWith(fontSize: 9.5),
                ),
            ],
          ),
          const SizedBox(height: 8),
          SizedBox(
            height: 160,
            child: CustomPaint(
              painter: _DetailPainter(
                channels: _channels,
                colors: multi
                    ? const [HpiColors.hr, HpiColors.spo2, HpiColors.eda]
                    : [_signalColor],
                windowStart: _windowStart,
                windowWidth: _windowWidth,
              ),
            ),
          ),
          const SizedBox(height: 8),
          Row(
            children: [
              _zoomButton(Symbols.zoom_out, () => _zoom(1.6)),
              const SizedBox(width: 8),
              _zoomButton(Symbols.zoom_in, () => _zoom(1 / 1.6)),
              const Spacer(),
              Text(_windowLabel(), style: HpiText.mono.copyWith(fontSize: 9.5)),
            ],
          ),
        ],
      ),
    );
  }

  Widget _zoomButton(IconData icon, VoidCallback onTap) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(999),
      child: Container(
        width: 30,
        height: 30,
        alignment: Alignment.center,
        decoration: const BoxDecoration(
            color: HpiColors.chipBg, shape: BoxShape.circle),
        child: Icon(icon, size: 16, color: HpiColors.onSurfaceBright),
      ),
    );
  }

  void _zoom(double factor) {
    setState(() {
      final center = _windowStart + _windowWidth / 2;
      _windowWidth = (_windowWidth * factor).clamp(0.01, 1.0);
      _windowStart = (center - _windowWidth / 2).clamp(0.0, 1.0 - _windowWidth);
    });
  }

  String _windowLabel() {
    final total = widget.recording.durationSeconds;
    final from = (total * _windowStart).round();
    final to = (total * (_windowStart + _windowWidth)).round();
    return '${_clock(from)} – ${_clock(to)}';
  }

  Widget _statsRow() {
    final ch = _channels.first;
    final peak = ch.fold<double>(0, (a, b) => b.abs() > a ? b.abs() : a);
    final mean = ch.reduce((a, b) => a + b) / ch.length;
    return Row(children: [
      Expanded(
          child: HpiStatChip(
              value: peak.toStringAsFixed(0),
              label: 'Peak',
              valueColor: _signalColor)),
      const SizedBox(width: 10),
      Expanded(
          child: HpiStatChip(value: mean.toStringAsFixed(0), label: 'Mean')),
      const SizedBox(width: 10),
      Expanded(
          child: HpiStatChip(value: '${ch.length}', label: 'Samples')),
    ]);
  }

  /// HRV spot check.
  ///
  /// For an **ECG** record these numbers are derived here, from detected R
  /// peaks — the reference a researcher validates the watch's own HRV against.
  /// For an **HRV** record they are measured over the watch's own R-R
  /// intervals. The card says which, every time: a number is only a validation
  /// if you know which side produced it.
  Widget _hrvCard(HrvMetrics m) {
    final derived = _isEcg;
    final rr = _rr;
    return HpiCard(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Expanded(child: HpiSectionLabel('HRV SPOT CHECK')),
              HpiPill(
                label: derived ? 'FROM ECG' : 'FROM WATCH R-R',
                color: derived ? HpiColors.hr : HpiColors.stress,
              ),
            ],
          ),
          const SizedBox(height: 10),
          if (!m.isReliable)
            // Never render metrics that mean nothing. An RMSSD of 8 ms off six
            // clean beats reads as "very low variability" when it actually
            // means "not measurable" — same trap as the `baselining` state on
            // the stress screen, where a 0 would read as "calm".
            Text(
              m.beats < 20
                  ? 'Only ${m.beats} usable beat${m.beats == 1 ? "" : "s"} — too '
                      'short for a meaningful HRV reading. A spot check wants '
                      '30 s or more of clean signal.'
                  : '${(m.artifactFraction * 100).round()}% of intervals were '
                      'rejected as artifacts — too noisy to report HRV from. '
                      'Re-record with firmer skin contact.',
              style: HpiText.body.copyWith(fontSize: 12, height: 1.4),
            )
          else ...[
            Row(children: [
              Expanded(
                  child: HpiStatChip(
                      value: m.rmssdMs.toStringAsFixed(1),
                      label: 'RMSSD ms',
                      valueColor: HpiColors.stress)),
              const SizedBox(width: 10),
              Expanded(
                  child: HpiStatChip(
                      value: m.sdnnMs.toStringAsFixed(1), label: 'SDNN ms')),
              const SizedBox(width: 10),
              Expanded(
                  child: HpiStatChip(
                      value: m.meanHrBpm.toStringAsFixed(0),
                      label: 'Mean HR',
                      valueColor: HpiColors.hr)),
            ]),
            const SizedBox(height: 10),
            Row(children: [
              Expanded(
                  child: HpiStatChip(
                      value: '${(m.pnn50 * 100).toStringAsFixed(0)}%',
                      label: 'pNN50')),
              const SizedBox(width: 10),
              Expanded(
                  child: HpiStatChip(value: '${m.beats}', label: 'Beats')),
              const SizedBox(width: 10),
              Expanded(
                  child: HpiStatChip(
                      value: '${(m.artifactFraction * 100).toStringAsFixed(0)}%',
                      label: 'Artifacts')),
            ]),
            if (rr != null && rr.rrMs.length > 1) ...[
              const SizedBox(height: 14),
              const HpiSectionLabel('TACHOGRAM · R-R INTERVAL'),
              const SizedBox(height: 6),
              SizedBox(
                height: 88,
                child: CustomPaint(
                  painter: _TachogramPainter(
                      rr.rrMs, derived ? HpiColors.hr : HpiColors.stress),
                ),
              ),
            ],
          ],
          const SizedBox(height: 10),
          Text(
            derived
                ? 'Beats detected from this ECG and measured here on the phone. '
                    'A research reference for checking the watch\'s own HRV — '
                    'not a diagnosis, and no rhythm interpretation.'
                : 'Measured from the R-R intervals the watch recorded. '
                    'Research figures — not a diagnosis.',
            style: HpiText.supporting.copyWith(fontSize: 10),
          ),
        ],
      ),
    );
  }

  Widget _noSamples() {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 56),
      child: Column(
        children: [
          const Icon(Symbols.warning, size: 40, color: HpiColors.disabled),
          const SizedBox(height: 12),
          Text('No samples decoded', style: HpiText.appBarTitle),
          const SizedBox(height: 6),
          Text('This payload had no readable samples for the header shape.',
              textAlign: TextAlign.center,
              style: HpiText.body.copyWith(fontSize: 12)),
        ],
      ),
    );
  }

  String _dur(int seconds) {
    if (seconds <= 0) return '—';
    final h = seconds ~/ 3600;
    final m = (seconds % 3600) ~/ 60;
    return h > 0 ? '${h}h ${m}m' : (m > 0 ? '$m min' : '${seconds}s');
  }

  String _clock(int seconds) =>
      '${seconds ~/ 60}:${(seconds % 60).toString().padLeft(2, '0')}';

  String _size(int bytes) => bytes >= 1 << 20
      ? '${(bytes / (1 << 20)).toStringAsFixed(1)} MB'
      : '${(bytes / 1024).toStringAsFixed(0)} kB';

  String _when(DateTime dt) {
    final months = const [
      'Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun',
      'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'
    ];
    final hour = dt.hour > 12 ? dt.hour - 12 : (dt.hour == 0 ? 12 : dt.hour);
    final amPm = dt.hour >= 12 ? 'PM' : 'AM';
    return '${dt.day} ${months[dt.month - 1]} $hour:'
        '${dt.minute.toString().padLeft(2, '0')} $amPm';
  }
}

/// Beat-to-beat interval against beat number — the standard HRV view.
///
/// Plotted against **beat index, not elapsed time**: that is what a tachogram
/// is, and it is why the variability is legible. Spacing the points by their own
/// duration would compress exactly the fast beats whose short intervals carry
/// the RMSSD signal.
class _TachogramPainter extends CustomPainter {
  _TachogramPainter(this.rrMs, this.color);

  final List<double> rrMs;
  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    if (rrMs.length < 2) return;

    var lo = rrMs.first, hi = rrMs.first;
    for (final v in rrMs) {
      if (v < lo) lo = v;
      if (v > hi) hi = v;
    }
    // A flat trace must not divide by zero, and a nearly flat one should read as
    // flat rather than being amplified into noise by an autoscale.
    final span = (hi - lo) < 20 ? 20.0 : (hi - lo) * 1.2;
    final mid = (hi + lo) / 2;
    double y(double v) =>
        size.height * (1 - ((v - (mid - span / 2)) / span).clamp(0.0, 1.0));
    double x(int i) => size.width * i / (rrMs.length - 1);

    final grid = Paint()
      ..color = HpiColors.divider
      ..strokeWidth = 1;
    for (var i = 1; i < 3; i++) {
      final gy = size.height * i / 3;
      canvas.drawLine(Offset(0, gy), Offset(size.width, gy), grid);
    }

    final path = Path()..moveTo(x(0), y(rrMs.first));
    for (var i = 1; i < rrMs.length; i++) {
      path.lineTo(x(i), y(rrMs[i]));
    }
    canvas.drawPath(
      path,
      Paint()
        ..color = color
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.6
        ..strokeJoin = StrokeJoin.round,
    );

    // Dots only when they won't merge into a smear.
    if (rrMs.length <= 120) {
      final dot = Paint()..color = color;
      for (var i = 0; i < rrMs.length; i++) {
        canvas.drawCircle(Offset(x(i), y(rrMs[i])), 2, dot);
      }
    }

    final label = TextPainter(
      text: TextSpan(
        text: '${lo.round()}–${hi.round()} ms',
        style: const TextStyle(
            fontFamily: 'Rubik', fontSize: 9, color: HpiColors.faint),
      ),
      textDirection: TextDirection.ltr,
    )..layout();
    label.paint(canvas, Offset(size.width - label.width, 0));
  }

  @override
  bool shouldRepaint(_TachogramPainter old) =>
      old.rrMs != rrMs || old.color != color;
}

class _MinimapPainter extends CustomPainter {
  _MinimapPainter({
    required this.channel,
    required this.color,
    required this.windowStart,
    required this.windowWidth,
  });

  final List<double> channel;
  final Color color;
  final double windowStart;
  final double windowWidth;

  @override
  void paint(Canvas canvas, Size size) {
    if (channel.isEmpty) return;
    final cols = size.width.floor().clamp(1, 4096);
    final per = (channel.length / cols).ceil().clamp(1, channel.length);
    final r = robustRange(channel);
    final lo = r.lo, hi = r.hi;
    double y(double v) =>
        size.height * (1 - (v - lo) / (hi - lo)).clamp(0.0, 1.0);

    final path = Path();
    final tops = <Offset>[];
    final bottoms = <Offset>[];
    for (var c = 0; c < cols; c++) {
      final start = c * per;
      if (start >= channel.length) break;
      final end = (start + per).clamp(0, channel.length);
      var mn = double.infinity, mx = -double.infinity;
      for (var i = start; i < end; i++) {
        final v = channel[i];
        if (v < mn) mn = v;
        if (v > mx) mx = v;
      }
      final x = size.width * c / cols;
      tops.add(Offset(x, y(mx)));
      bottoms.add(Offset(x, y(mn)));
    }
    if (tops.isEmpty) return;
    path.addPolygon([...tops, ...bottoms.reversed], true);
    canvas.drawPath(path, Paint()..color = color.withValues(alpha: 0.30));

    final rect = Rect.fromLTWH(
      size.width * windowStart,
      0,
      size.width * windowWidth,
      size.height,
    );
    canvas.drawRRect(
      RRect.fromRectAndRadius(rect, const Radius.circular(6)),
      Paint()..color = HpiColors.hr.withValues(alpha: 0.12),
    );
    canvas.drawRRect(
      RRect.fromRectAndRadius(rect, const Radius.circular(6)),
      Paint()
        ..color = HpiColors.hr
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.4,
    );
  }

  @override
  bool shouldRepaint(_MinimapPainter old) =>
      old.channel != channel ||
      old.windowStart != windowStart ||
      old.windowWidth != windowWidth;
}

class _DetailPainter extends CustomPainter {
  _DetailPainter({
    required this.channels,
    required this.colors,
    required this.windowStart,
    required this.windowWidth,
  });

  final List<List<double>> channels;
  final List<Color> colors;
  final double windowStart;
  final double windowWidth;

  @override
  void paint(Canvas canvas, Size size) {
    if (channels.isEmpty || channels.first.isEmpty) return;

    final grid = Paint()
      ..color = HpiColors.divider
      ..strokeWidth = 1;
    for (var i = 1; i < 4; i++) {
      final y = size.height * i / 4;
      canvas.drawLine(Offset(0, y), Offset(size.width, y), grid);
    }

    final n = channels.first.length;
    final from = (n * windowStart).floor().clamp(0, n - 1);
    final to = (n * (windowStart + windowWidth)).ceil().clamp(from + 1, n);

    // Robust over the *visible window* only, so zooming into a quiet stretch
    // rescales to it instead of staying pinned to a transient off-screen.
    final r = robustRange([
      for (final ch in channels)
        for (var i = from; i < to && i < ch.length; i++) ch[i],
    ]);
    final lo = r.lo, hi = r.hi;
    final span = to - from;
    double y(double v) =>
        size.height * (1 - (v - lo) / (hi - lo)).clamp(0.0, 1.0);

    for (var c = 0; c < channels.length; c++) {
      final ch = channels[c];
      final path = Path();
      var started = false;
      final step = (span / size.width).ceil().clamp(1, span);
      for (var i = from; i < to && i < ch.length; i += step) {
        final x = size.width * (i - from) / span;
        if (!started) {
          path.moveTo(x, y(ch[i]));
          started = true;
        } else {
          path.lineTo(x, y(ch[i]));
        }
      }
      canvas.drawPath(
        path,
        Paint()
          ..color = colors[c % colors.length]
          ..style = PaintingStyle.stroke
          ..strokeWidth = 1.8
          ..strokeJoin = StrokeJoin.round,
      );
    }
  }

  @override
  bool shouldRepaint(_DetailPainter old) =>
      old.channels != channels ||
      old.windowStart != windowStart ||
      old.windowWidth != windowWidth;
}
