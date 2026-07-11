import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:material_symbols_icons/symbols.dart';
import 'package:share_plus/share_plus.dart';

import '../models/research_recording.dart';
import '../theme/hpi_colors.dart';
import '../theme/hpi_text.dart';
import '../ui/components/hpi_components.dart';
import '../utils/device_manager.dart';
import '../utils/research_recording_manager.dart';

/// Recording preview + CSV export (handoff 2d).
///
/// Renders a downloaded session: a full-session minimap with a draggable zoom
/// window, the windowed detail waveform (IMU shows AX/AY/AZ overlaid), session
/// stats, and CSV export via the existing [ResearchRecordingManager]. All series
/// come from the decoded payload — nothing here is synthesized.
class ScrRecordingPreview extends StatefulWidget {
  const ScrRecordingPreview({
    super.key,
    required this.session,
    required this.data,
  });

  final ResearchRecording session;
  final Map<ResearchSignalType, Uint8List> data;

  @override
  State<ScrRecordingPreview> createState() => _ScrRecordingPreviewState();
}

class _ScrRecordingPreviewState extends State<ScrRecordingPreview> {
  late ResearchSignalType _signal;
  bool _exporting = false;

  /// Zoom window over the session, as fractions of the whole [0..1].
  double _windowStart = 0;
  double _windowWidth = 0.2;

  /// Decoded channels for the selected signal (1 channel, or 3 for IMU axes).
  List<List<double>> _channels = const [];

  @override
  void initState() {
    super.initState();
    _signal = widget.data.keys.first;
    _decode();
  }

  void _decode() {
    final bytes = widget.data[_signal];
    if (bytes == null) {
      setState(() => _channels = const []);
      return;
    }
    // Parsing needs a manager instance, but decoding is pure — no BLE work is
    // done here, so this never touches the SMP wire lock.
    final m = ResearchRecordingManager('');
    List<List<double>> channels;
    switch (_signal) {
      case ResearchSignalType.accel:
        final s = m.parseAccelSamples(bytes);
        channels = [
          s.map((e) => e.x.toDouble()).toList(),
          s.map((e) => e.y.toDouble()).toList(),
          s.map((e) => e.z.toDouble()).toList(),
        ];
      case ResearchSignalType.gyro:
        final s = m.parseGyroSamples(bytes);
        channels = [
          s.map((e) => e.x.toDouble()).toList(),
          s.map((e) => e.y.toDouble()).toList(),
          s.map((e) => e.z.toDouble()).toList(),
        ];
      case ResearchSignalType.gsr:
        final s = m.parseGsrSamples(bytes);
        channels = [s.map((e) => e.value.toDouble()).toList()];
      case ResearchSignalType.ppgWrist:
        final s = m.parsePpgWristSamples(bytes);
        channels = [s.map((e) => e.ir.toDouble()).toList()];
      case ResearchSignalType.ppgFinger:
        final s = m.parsePpgFingerSamples(bytes);
        channels = [s.map((e) => e.ir.toDouble()).toList()];
    }
    setState(() => _channels = channels);
  }

  Future<void> _exportCsv() async {
    final bytes = widget.data[_signal];
    if (bytes == null) return;
    setState(() => _exporting = true);
    final device = await DeviceManager.getPairedDevice();
    final m = ResearchRecordingManager(device?.macAddress ?? '');
    try {
      final file = await m.exportToCsv(widget.session, _signal, bytes);
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

  Color get _signalColor => switch (_signal) {
        ResearchSignalType.accel || ResearchSignalType.gyro => HpiColors.steps,
        ResearchSignalType.gsr => HpiColors.eda,
        _ => HpiColors.spo2,
      };

  @override
  Widget build(BuildContext context) {
    final s = widget.session;
    final signals = widget.data.keys.toList();

    return Scaffold(
      backgroundColor: HpiColors.background,
      appBar: AppBar(
        title: Text('${_signal.shortName} · ${_dur(s.durationSeconds)}'),
      ),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 28),
          children: [
            Text(
              '${s.formattedDateTime} · ${_signal.sampleRateHz} Hz · '
              '${_size(s.totalSizeBytes)}',
              style: HpiText.mono.copyWith(fontSize: 10.5),
            ),
            const SizedBox(height: 14),
            if (signals.length > 1) ...[
              HpiSegmentedControl(
                segments: [for (final x in signals) x.shortName],
                selectedIndex: signals.indexOf(_signal),
                accent: _signalColor,
                onChanged: (i) {
                  setState(() => _signal = signals[i]);
                  _decode();
                },
              ),
              const SizedBox(height: 14),
            ],
            if (_channels.isEmpty || _channels.first.isEmpty)
              _noSamples()
            else ...[
              _minimapCard(),
              const SizedBox(height: 12),
              _detailCard(),
              const SizedBox(height: 12),
              _statsRow(),
              const SizedBox(height: 16),
              HpiFilledButton(
                label: _exporting
                    ? 'Exporting…'
                    : 'Export CSV · ${_size(widget.data[_signal]!.length)}',
                icon: Symbols.download,
                onPressed: _exporting ? null : _exportCsv,
              ),
              const SizedBox(height: 10),
              Text(
                'CSV shares the t_ms timebase — align it column-wise with other '
                'signals from this session for correlation.',
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
              Text(_dur(widget.session.durationSeconds),
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

  Widget _detailCard() {
    final imu = _signal == ResearchSignalType.accel ||
        _signal == ResearchSignalType.gyro;
    return HpiCard(
      waveform: true,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Text(_signal.shortName.toUpperCase(),
                  style: HpiText.sectionLabel.copyWith(color: _signalColor)),
              const Spacer(),
              if (imu)
                Text('AX  AY  AZ',
                    style: HpiText.mono.copyWith(fontSize: 9.5)),
            ],
          ),
          const SizedBox(height: 8),
          SizedBox(
            height: 160,
            child: CustomPaint(
              painter: _DetailPainter(
                channels: _channels,
                colors: imu
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
    final total = widget.session.durationSeconds;
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
          child: HpiStatChip(
              value: '${ch.length}', label: 'Samples')),
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
          Text('This signal downloaded with no readable samples.',
              textAlign: TextAlign.center,
              style: HpiText.body.copyWith(fontSize: 12)),
        ],
      ),
    );
  }

  String _dur(int seconds) {
    final h = seconds ~/ 3600;
    final m = (seconds % 3600) ~/ 60;
    return h > 0 ? '${h}h ${m}m' : '$m min';
  }

  String _clock(int seconds) =>
      '${seconds ~/ 60}:${(seconds % 60).toString().padLeft(2, '0')}';

  String _size(int bytes) => bytes >= 1 << 20
      ? '${(bytes / (1 << 20)).toStringAsFixed(1)} MB'
      : '${(bytes / 1024).toStringAsFixed(0)} kB';
}

/// Full-session amplitude envelope with the zoom-window rect drawn over it.
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
    // Bucket the session into one column per pixel and fill min..max.
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

/// The windowed detail waveform. Draws every channel overlaid on a shared scale
/// so IMU axes stay comparable.
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

    // Shared scale across channels within the window.
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
      // Never draw more segments than pixels — long windows would otherwise
      // build a path with tens of thousands of points.
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
