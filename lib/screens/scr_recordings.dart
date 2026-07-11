import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:material_symbols_icons/symbols.dart';

import '../models/research_recording.dart';
import '../theme/hpi_colors.dart';
import '../theme/hpi_text.dart';
import '../ui/components/hpi_components.dart';
import '../utils/device_manager.dart';
import '../utils/research_recording_manager.dart';
import 'scr_recording_preview.dart';

/// Recordings library (handoff 2c). Long research sessions (PPG · GSR · IMU)
/// held in watch flash: list them over the existing [ResearchRecordingManager]
/// (SMP), download on demand, then open the preview (2d).
///
/// ECG is deliberately absent — it has no long-recording mode on the device; it
/// is only captured as short spot recordings from Live.
class ScrRecordings extends StatefulWidget {
  const ScrRecordings({super.key});

  @override
  State<ScrRecordings> createState() => _ScrRecordingsState();
}

/// Filter chips over the session list.
enum _Filter { all, ppg, gsr, imu }

class _ScrRecordingsState extends State<ScrRecordings> {
  List<ResearchRecording>? _sessions;
  String? _error;
  bool _busy = false;
  _Filter _filter = _Filter.all;

  /// Sessions downloaded this run: timestamp -> per-signal payloads.
  final _downloaded = <int, Map<ResearchSignalType, Uint8List>>{};

  /// Session timestamp currently downloading.
  int? _downloadingTs;

  @override
  void initState() {
    super.initState();
    _refresh();
  }

  /// Run [action] against a live manager, always disposing it so the SMP wire
  /// lock is released even on an early return or throw.
  Future<T?> _withManager<T>(
      Future<T> Function(ResearchRecordingManager m) action) async {
    final device = await DeviceManager.getPairedDevice();
    if (device == null) {
      if (mounted) setState(() => _error = 'No device paired.');
      return null;
    }
    final manager = ResearchRecordingManager(device.macAddress);
    try {
      await manager.initialize();
      return await action(manager);
    } catch (e) {
      if (mounted) setState(() => _error = '$e');
      return null;
    } finally {
      await manager.dispose();
    }
  }

  Future<void> _refresh() async {
    setState(() {
      _busy = true;
      _error = null;
    });
    final list = await _withManager((m) => m.getSessionList());
    if (!mounted) return;
    setState(() {
      if (list != null) _sessions = list;
      _busy = false;
    });
  }

  Future<void> _download(ResearchRecording session) async {
    setState(() => _downloadingTs = session.sessionTimestamp);
    final data = await _withManager((m) => m.downloadSession(session));
    if (!mounted) return;
    setState(() {
      if (data != null) _downloaded[session.sessionTimestamp] = data;
      _downloadingTs = null;
    });
  }

  void _open(ResearchRecording session) {
    final data = _downloaded[session.sessionTimestamp];
    if (data == null) return;
    Navigator.of(context).push(MaterialPageRoute(
      builder: (_) => ScrRecordingPreview(session: session, data: data),
    ));
  }

  bool _matches(ResearchRecording s) {
    final signals = s.signals;
    switch (_filter) {
      case _Filter.all:
        return true;
      case _Filter.ppg:
        return signals.contains(ResearchSignalType.ppgWrist) ||
            signals.contains(ResearchSignalType.ppgFinger);
      case _Filter.gsr:
        return signals.contains(ResearchSignalType.gsr);
      case _Filter.imu:
        return signals.contains(ResearchSignalType.accel) ||
            signals.contains(ResearchSignalType.gyro);
    }
  }

  @override
  Widget build(BuildContext context) {
    final all = _sessions;
    final shown = all?.where(_matches).toList() ?? const <ResearchRecording>[];

    return Scaffold(
      backgroundColor: HpiColors.background,
      appBar: AppBar(
        title: const Text('Recordings'),
        actions: [
          IconButton(
            icon: const Icon(Symbols.refresh, size: 20),
            onPressed: _busy ? null : _refresh,
          ),
        ],
      ),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 28),
          children: [
            HpiSegmentedControl(
              segments: const ['All', 'PPG', 'GSR', 'IMU'],
              selectedIndex: _filter.index,
              onChanged: (i) => setState(() => _filter = _Filter.values[i]),
            ),
            const SizedBox(height: 16),
            if (_busy && all == null)
              const Padding(
                padding: EdgeInsets.symmetric(vertical: 60),
                child: Center(
                    child: CircularProgressIndicator(color: HpiColors.hr)),
              )
            else if (_error != null)
              _errorCard()
            else if (shown.isEmpty)
              _empty()
            else
              HpiGroupedCard(rows: [for (final s in shown) _row(s)]),
            const SizedBox(height: 14),
            _footer(all),
          ],
        ),
      ),
    );
  }

  Widget _row(ResearchRecording session) {
    final onPhone = _downloaded.containsKey(session.sessionTimestamp);
    final downloading = _downloadingTs == session.sessionTimestamp;
    final kind = _kindOf(session);

    return HpiListRow(
      icon: kind.icon,
      iconColor: kind.color,
      title: '${kind.label} · ${_duration(session.durationSeconds)}',
      supporting: '${session.formattedDateTime} · ${_size(session.totalSizeBytes)}',
      onTap: onPhone ? () => _open(session) : null,
      showChevron: onPhone,
      trailing: downloading
          ? const SizedBox(
              width: 18,
              height: 18,
              child: CircularProgressIndicator(
                  strokeWidth: 2, color: HpiColors.hr))
          : onPhone
              ? const HpiPill(label: 'ON PHONE', color: HpiColors.steps)
              : GestureDetector(
                  onTap: () => _download(session),
                  child: Row(mainAxisSize: MainAxisSize.min, children: const [
                    HpiPill(label: 'ON WATCH'),
                    SizedBox(width: 8),
                    Icon(Symbols.download, size: 19, color: HpiColors.hr),
                  ]),
                ),
    );
  }

  Widget _footer(List<ResearchRecording>? all) {
    if (all == null) return const SizedBox.shrink();
    final pending = all.length - _downloaded.length;
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 4),
      child: Row(
        children: [
          const Icon(Symbols.database, size: 15, color: HpiColors.muted),
          const SizedBox(width: 6),
          Expanded(
            child: Text(
              pending > 0
                  ? '$pending recording${pending == 1 ? "" : "s"} not yet downloaded'
                  : 'All recordings downloaded',
              style: HpiText.supporting,
            ),
          ),
          Text('ECG = 30 s spot recordings, see Live',
              style: HpiText.supporting.copyWith(fontSize: 10)),
        ],
      ),
    );
  }

  Widget _empty() {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 56),
      child: Column(
        children: [
          const Icon(Symbols.receipt_long, size: 44, color: HpiColors.disabled),
          const SizedBox(height: 12),
          Text('No recordings', style: HpiText.appBarTitle),
          const SizedBox(height: 6),
          Text('Long PPG, GSR and IMU sessions are started on the watch.',
              textAlign: TextAlign.center,
              style: HpiText.body.copyWith(fontSize: 12)),
        ],
      ),
    );
  }

  Widget _errorCard() {
    return HpiCard(
      child: Column(
        children: [
          const Icon(Symbols.warning, size: 32, color: HpiColors.error),
          const SizedBox(height: 10),
          Text("Couldn't read recordings", style: HpiText.cardTitle),
          const SizedBox(height: 6),
          Text(_error!,
              textAlign: TextAlign.center,
              style: HpiText.supporting.copyWith(color: HpiColors.error)),
          const SizedBox(height: 14),
          HpiTonalButton(
              label: 'Retry', icon: Symbols.refresh, onPressed: _refresh),
        ],
      ),
    );
  }

  _Kind _kindOf(ResearchRecording s) {
    final signals = s.signals;
    if (signals.contains(ResearchSignalType.accel) ||
        signals.contains(ResearchSignalType.gyro)) {
      return const _Kind('IMU', Symbols.rotate_90_degrees_ccw, HpiColors.steps);
    }
    if (signals.contains(ResearchSignalType.gsr)) {
      return const _Kind('GSR', Symbols.water_drop, HpiColors.eda);
    }
    return const _Kind('PPG', Symbols.spo2, HpiColors.spo2);
  }

  String _duration(int seconds) {
    final h = seconds ~/ 3600;
    final m = (seconds % 3600) ~/ 60;
    if (h > 0) return '${h}h ${m}m';
    return '$m min';
  }

  String _size(int bytes) {
    if (bytes >= 1 << 20) return '${(bytes / (1 << 20)).toStringAsFixed(1)} MB';
    return '${(bytes / 1024).toStringAsFixed(0)} kB';
  }
}

class _Kind {
  const _Kind(this.label, this.icon, this.color);
  final String label;
  final IconData icon;
  final Color color;
}
