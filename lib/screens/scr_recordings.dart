// Copyright (c) 2024-2026 ProtoCentral
// SPDX-License-Identifier: MIT

import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:material_symbols_icons/symbols.dart';

import '../feature_flags.dart';
import '../models/hs_recording.dart';
import '../theme/hpi_colors.dart';
import '../theme/hpi_text.dart';
import '../ui/components/hpi_components.dart';
import '../utils/connection_manager.dart';
import '../utils/device_manager.dart';
import '../utils/healthy_store_records_manager.dart';
import '../utils/healthy_store_sync_manager.dart';
import 'scr_recording_preview.dart';

/// Recordings library (handoff 2c). Lists episodic sessions via HPI_HS
/// **RECORDS**, downloads on demand (CRC-verified, then acked), and opens the
/// preview/export screen (2d).
class ScrRecordings extends StatefulWidget {
  const ScrRecordings({super.key});

  @override
  State<ScrRecordings> createState() => _ScrRecordingsState();
}

/// A library filter chip.
///
/// Each case carries its own [label], and the control is built from
/// [_visibleFilters] rather than from `_Filter.values` with a parallel list of
/// strings. That coupling ("order must match the labels") could not survive a
/// conditionally-hidden chip: hiding one shifts every later index, so the
/// segmented control would report GSR and select IMU.
enum _Filter {
  all('All'),
  ecg('ECG'),
  hrv('HRV'),
  ppg('PPG'),
  gsr('GSR'),
  imu('IMU');

  const _Filter(this.label);
  final String label;

  /// Chips actually shown. HRV is hidden while [kHrvRecordsEnabled] is off —
  /// the firmware emits no such records, so the chip would always be empty.
  static List<_Filter> get visible => [
        for (final f in _Filter.values)
          if (f != _Filter.hrv || kHrvRecordsEnabled) f,
      ];
}

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
    HealthyStoreSyncManager.dataRevision.addListener(_onStoreChanged);
    _refresh();
  }

  @override
  void dispose() {
    HealthyStoreSyncManager.dataRevision.removeListener(_onStoreChanged);
    super.dispose();
  }

  /// The local store was wiped (or re-synced) underneath us.
  ///
  /// [_payloads] and the `onPhone` flags on [_sessions] are both caches of state
  /// that no longer exists, so a stale screen would keep offering "open" on a
  /// payload whose file has just been unlinked. Drop the cache and re-list.
  void _onStoreChanged() {
    if (!mounted) return;
    _payloads.clear();
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

  /// Delete the phone's copy of a recording, after confirming.
  ///
  /// The dialog distinguishes the two outcomes rather than promising one:
  /// RECORDS has no erase op, so a session the watch still holds comes back on
  /// the next refresh as `ON WATCH`. Saying "deleted" flatly would look like a
  /// bug the first time a row reappeared.
  Future<void> _delete(HsRecording session) async {
    final stillOnWatch = !session.acked;
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: HpiColors.surfaceContainer,
        title: const Text('Delete this recording?'),
        content: Text(
          'The ${session.kindLabel} recording from '
          '${_formatWhen(session.startTime)} will be removed from this phone, '
          'along with any CSV exported from it.\n\n'
          '${stillOnWatch ? "The watch still has this session, so it will "
              "reappear here as ON WATCH until the watch reclaims the space." : "The watch has already released this session, so this deletes it "
              "for good."}',
          style: HpiText.body.copyWith(fontSize: 12.5, height: 1.4),
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('Cancel')),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Delete',
                style: TextStyle(color: HpiColors.error)),
          ),
        ],
      ),
    );
    if (ok != true || !mounted) return;

    setState(() {
      _busy = true;
      _error = null;
    });
    // Deliberately not routed through _withManager: deleting is a local-store
    // operation and must work with the watch out of range, but _withManager's
    // `finally` closes a manager whose `list()`/`download()` would have opened
    // an SMP session. Constructing one directly touches no BLE.
    final device = await DeviceManager.getPairedDevice();
    try {
      await HealthyStoreRecordsManager(device?.macAddress ?? '')
          .deleteLocal(session);
      _payloads.remove(session.id);
    } catch (e) {
      if (mounted) setState(() => _error = 'Could not delete: $e');
    }
    if (!mounted) return;

    // Reconcile in memory rather than re-listing. A full refresh would spend an
    // SMP session to learn something the watch's inventory did not change, and
    // would fail outright with the watch out of range — leaving the screen still
    // showing the row that was just deleted.
    setState(() {
      _busy = false;
      final all = _sessions;
      if (all == null) return;
      _sessions = [
        for (final s in all)
          if (s.id != session.id)
            s
          // Still on the watch: the row survives, demoted to ON WATCH and
          // re-downloadable. Rebuilt rather than copyWith'd so a stale CRC-fail
          // verdict from the deleted payload doesn't outlive it.
          else if (stillOnWatch)
            HsRecording(header: s.header),
      ];
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
      case _Filter.ecg:
        return s.kind == HsRecordingKind.ecg;
      case _Filter.hrv:
        return s.kind == HsRecordingKind.hrv;
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
    // Also drop HRV rows outright while the feature is gated. The chip is
    // hidden, but a bench build could still emit signal 0x05 — and a row that
    // downloads into a preview whose HRV analysis is switched off is a worse
    // outcome than not listing it.
    final shown = all
            ?.where(_matches)
            .where((s) => kHrvRecordsEnabled || s.kind != HsRecordingKind.hrv)
            .toList() ??
        const <HsRecording>[];

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
              segments: [for (final f in _Filter.visible) f.label],
              selectedIndex: _Filter.visible.indexOf(_filter).clamp(0, 99),
              onChanged: (i) =>
                  setState(() => _filter = _Filter.visible[i]),
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
          // An interval series has no fixed-rate duration to quote from the
          // header; beat count is what it can honestly report before download.
          '${session.kindLabel} · '
          '${session.isIntervalSeries ? "${session.beats} beats" : _duration(session.durationSeconds)}'
          '${session.isPartial ? " · partial" : ""}',
      supporting:
          '${_formatWhen(session.startTime)} · ${_size(session.byteLen)}'
          '${session.crcOk == false ? " · CRC fail" : ""}',
      onTap: onPhone ? () => _open(session) : null,
      // The delete button occupies the trailing slot, so the chevron would
      // crowd it; the row is still tappable to open.
      showChevron: false,
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
              ? Row(mainAxisSize: MainAxisSize.min, children: [
                  const HpiPill(label: 'ON PHONE', color: HpiColors.steps),
                  IconButton(
                    tooltip: 'Delete from phone',
                    visualDensity: VisualDensity.compact,
                    icon: const Icon(Symbols.delete,
                        size: 19, color: HpiColors.error),
                    onPressed: _busy ? null : () => _delete(session),
                  ),
                ])
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
              '${kHrvRecordsEnabled ? "ECG, HRV, PPG" : "ECG, PPG"}, GSR and '
              'IMU sessions are all started on the watch, then downloaded here '
              'on demand.',
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
