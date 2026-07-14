// Copyright (c) 2024-2026 ProtoCentral
// SPDX-License-Identifier: MIT

import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:material_symbols_icons/symbols.dart';

import '../models/hs_recording.dart';
import '../theme/hpi_colors.dart';
import '../theme/hpi_text.dart';
import '../ui/components/hpi_components.dart';
import '../utils/connection_manager.dart';
import '../utils/device_manager.dart';
import '../utils/healthy_store_records_manager.dart';
import 'scr_recording_preview.dart';

/// Recordings library (handoff 2c). Lists episodic sessions via HPI_HS
/// **RECORDS**, downloads on demand (CRC-verified, then acked), and opens the
/// preview/export screen (2d).
class ScrRecordings extends StatefulWidget {
  const ScrRecordings({super.key});

  @override
  State<ScrRecordings> createState() => _ScrRecordingsState();
}

enum _Filter { all, ppg, gsr, imu }

class _ScrRecordingsState extends State<ScrRecordings> {
  List<HsRecording>? _sessions;
  String? _error;
  bool _busy = false;
  _Filter _filter = _Filter.all;
  int? _downloadingId;
  double _downloadProgress = 0;

  /// In-memory payloads for the current screen session (id → bytes).
  final _payloads = <int, Uint8List>{};

  @override
  void initState() {
    super.initState();
    _refresh();
  }

  Future<T?> _withManager<T>(
      Future<T> Function(HealthyStoreRecordsManager m) action) async {
    final device = await DeviceManager.getPairedDevice();
    if (device == null) {
      if (mounted) setState(() => _error = 'No device paired.');
      return null;
    }
    final manager = HealthyStoreRecordsManager(device.macAddress);
    try {
      return await action(manager);
    } on SmpBusyException catch (e) {
      if (mounted) {
        setState(() => _error =
            'Watch is busy (${e.currentOwner}). Finish sync or firmware update first.');
      }
      return null;
    } catch (e) {
      if (mounted) setState(() => _error = '$e');
      return null;
    } finally {
      await manager.close();
    }
  }

  Future<void> _refresh() async {
    setState(() {
      _busy = true;
      _error = null;
    });
    final list = await _withManager((m) => m.list());
    if (!mounted) return;
    setState(() {
      if (list != null) _sessions = list;
      _busy = false;
    });
  }

  Future<void> _download(HsRecording session) async {
    setState(() {
      _downloadingId = session.id;
      _downloadProgress = 0;
      _error = null;
    });
    final result = await _withManager((m) => m.download(
          session.header,
          onProgress: (done, total) {
            if (!mounted || total <= 0) return;
            setState(() => _downloadProgress = done / total);
          },
        ));
    if (!mounted) return;
    setState(() {
      _downloadingId = null;
      _downloadProgress = 0;
      if (result != null) {
        _payloads[result.recording.id] = Uint8List.fromList(result.data);
        final all = _sessions;
        if (all != null) {
          _sessions = [
            for (final s in all)
              if (s.id == result.recording.id) result.recording else s,
          ];
        }
        if (!result.crcOk) {
          _error =
              'Downloaded recording #${result.recording.id} but CRC failed — '
              'not removed from the watch.';
        }
      }
    });
  }

  Future<void> _open(HsRecording session) async {
    var data = _payloads[session.id];
    if (data == null && session.onPhone) {
      // loadLocal is disk-only; still go through the manager for path helpers.
      final loaded =
          await _withManager<Uint8List?>((m) => m.loadLocal(session));
      data = loaded;
      if (data != null) _payloads[session.id] = data;
    }
    if (data == null || !mounted) return;
    final payload = data;
    Navigator.of(context).push(MaterialPageRoute(
      builder: (_) =>
          ScrRecordingPreview(recording: session, payload: payload),
    ));
  }

  bool _matches(HsRecording s) {
    switch (_filter) {
      case _Filter.all:
        return true;
      case _Filter.ppg:
        return s.kind == HsRecordingKind.ppg;
      case _Filter.gsr:
        return s.kind == HsRecordingKind.gsr;
      case _Filter.imu:
        return s.kind == HsRecordingKind.imu;
    }
  }

  @override
  Widget build(BuildContext context) {
    final all = _sessions;
    final shown = all?.where(_matches).toList() ?? const <HsRecording>[];

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
            else if (_error != null && all == null)
              _errorCard()
            else if (shown.isEmpty)
              _empty()
            else
              HpiGroupedCard(rows: [for (final s in shown) _row(s)]),
            if (_error != null && all != null) ...[
              const SizedBox(height: 12),
              Text(_error!,
                  style: HpiText.supporting.copyWith(color: HpiColors.error)),
            ],
            const SizedBox(height: 14),
            _footer(all),
          ],
        ),
      ),
    );
  }

  Widget _row(HsRecording session) {
    final onPhone = session.onPhone || _payloads.containsKey(session.id);
    final downloading = _downloadingId == session.id;
    final kind = _kindOf(session);

    return HpiListRow(
      icon: kind.icon,
      iconColor: kind.color,
      title:
          '${session.kindLabel} · ${_duration(session.durationSeconds)}'
          '${session.isPartial ? " · partial" : ""}',
      supporting:
          '${_formatWhen(session.startTime)} · ${_size(session.byteLen)}'
          '${session.crcOk == false ? " · CRC fail" : ""}',
      onTap: onPhone ? () => _open(session) : null,
      showChevron: onPhone,
      trailing: downloading
          ? SizedBox(
              width: 22,
              height: 22,
              child: CircularProgressIndicator(
                strokeWidth: 2,
                color: HpiColors.hr,
                value: _downloadProgress > 0 ? _downloadProgress : null,
              ),
            )
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

  Widget _footer(List<HsRecording>? all) {
    if (all == null) return const SizedBox.shrink();
    final pending = all.where((s) => !s.onPhone && !_payloads.containsKey(s.id)).length;
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
                  : 'All listed recordings are on this phone',
              style: HpiText.supporting,
            ),
          ),
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
          Text(
              'Long PPG, GSR and IMU sessions are started on the watch. '
              'ECG spot checks live under Live.',
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

  _Kind _kindOf(HsRecording s) {
    switch (s.kind) {
      case HsRecordingKind.imu:
        return const _Kind(Symbols.rotate_90_degrees_ccw, HpiColors.steps);
      case HsRecordingKind.gsr:
        return const _Kind(Symbols.water_drop, HpiColors.eda);
      case HsRecordingKind.ecg:
        return const _Kind(Symbols.ecg_heart, HpiColors.hr);
      case HsRecordingKind.hrv:
        return const _Kind(Symbols.cardiology, HpiColors.stress);
      case HsRecordingKind.ppg:
      case HsRecordingKind.other:
        return const _Kind(Symbols.spo2, HpiColors.spo2);
    }
  }

  String _duration(int seconds) {
    if (seconds <= 0) return '—';
    final h = seconds ~/ 3600;
    final m = (seconds % 3600) ~/ 60;
    if (h > 0) return '${h}h ${m}m';
    if (m > 0) return '$m min';
    return '${seconds}s';
  }

  String _size(int bytes) {
    if (bytes <= 0) return '—';
    if (bytes >= 1 << 20) return '${(bytes / (1 << 20)).toStringAsFixed(1)} MB';
    return '${(bytes / 1024).toStringAsFixed(0)} kB';
  }

  String _formatWhen(DateTime dt) {
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

class _Kind {
  const _Kind(this.icon, this.color);
  final IconData icon;
  final Color color;
}
