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

  @override
  void initState() {
    super.initState();
    _samples = HsRecordSamples.decode(widget.recording.header, widget.payload);
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

  Future<void> _exportCsv() async {
    setState(() => _exporting = true);
    final device = await DeviceManager.getPairedDevice();
    final m = HealthyStoreRecordsManager(device?.macAddress ?? '');
    try {
      final file = await m.exportCsv(widget.recording, widget.payload);
      if (!mounted) return;
      await SharePlus.instance.share(
          ShareParams(files: [XFile(file.path)], text: 'HealthyPi recording'));
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
        title: Text('${s.kindLabel} · ${_dur(s.durationSeconds)}'),
      ),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 28),
          children: [
            Text(
              '${_when(s.startTime)} · ${s.sampleRate} Hz · '
              '${_size(widget.payload.length)}'
              '${s.isPartial ? " · partial" : ""}'
              '${_samples.assumed ? " · format inferred" : ""}',
              style: HpiText.mono.copyWith(fontSize: 10.5),
            ),
            const SizedBox(height: 14),
            if (_channels.isEmpty || _channels.first.isEmpty)
              _noSamples()
            else ...[
              _minimapCard(),
              const SizedBox(height: 12),
              _detailCard(multi: multi),
              const SizedBox(height: 12),
              _statsRow(),
              const SizedBox(height: 16),
              HpiFilledButton(
                label: _exporting
                    ? 'Exporting…'
                    : 'Export CSV · ${_size(widget.payload.length)}',
                icon: Symbols.download,
                onPressed: _exporting ? null : _exportCsv,
              ),
              const SizedBox(height: 10),
              Text(
                'CSV uses a shared t_ms timebase from the session start.',
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
    var lo = double.infinity, hi = -double.infinity;
    for (final v in channel) {
      if (v < lo) lo = v;
      if (v > hi) hi = v;
    }
    if ((hi - lo).abs() < 1e-9) {
      lo -= 1;
      hi += 1;
    }
    double y(double v) => size.height * (1 - (v - lo) / (hi - lo));

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

    var lo = double.infinity, hi = -double.infinity;
    for (final ch in channels) {
      for (var i = from; i < to && i < ch.length; i++) {
        if (ch[i] < lo) lo = ch[i];
        if (ch[i] > hi) hi = ch[i];
      }
    }
    if (!lo.isFinite || !hi.isFinite || (hi - lo).abs() < 1e-9) {
      lo -= 1;
      hi += 1;
    }
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
