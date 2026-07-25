// Copyright (c) 2024-2026 ProtoCentral
// SPDX-License-Identifier: MIT

import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:healthypi_healthy_store/healthypi_healthy_store.dart';

import 'bpt_calibrator.dart';

/// Binds [BptCalTransport] to the **HPI_HS MCUmgr group** (`0x1000`) — the path
/// the firmware moved BPT onto when the custom cmd/data GATT service was retired.
/// Replaces the old `_ConnCmdBptTransport`; the [BptCalibrator] state machine is
/// unchanged, exactly as the transport seam was designed for
/// (`docs/FIRMWARE_HANDOFF_BPT_HS.md` §10).
///
/// Two halves, per that handoff:
///  - **Control** — the calibrator's opcode bytes are mapped onto HPI_HS writes
///    (`0x60`→`BPT_CAL_ENTER`, `0x61,sys,dia,idx`→`BPT_CAL_POINT`,
///    `0x62`→`BPT_CAL_END`). The calibrator still speaks the legacy byte format;
///    only this adapter knows they are now SMP commands.
///  - **Feedback** — SMP has no server push, so [statusStream] is fed by a poll
///    loop over `BPT_CAL_STATUS` (~6 Hz) that re-emits the same 2-byte
///    `[status, progress]` packets the calibrator already consumes.
///
/// The `HpiHs` client rides an SMP session that holds the SMP wire lock for the
/// whole calibration (opened by the screen via `HealthyStoreClient`), so a
/// background sync/DFU cannot interleave frames.
class HpiHsBptTransport implements BptCalTransport {
  HpiHsBptTransport(
    this._hs, {
    required bool Function() isConnected,
    Duration pollInterval = const Duration(milliseconds: 150),
    void Function(String message)? log,
  })  : _isConnected = isConnected,
        _pollInterval = pollInterval,
        _log = log;

  final HpiHs _hs;
  final bool Function() _isConnected;
  final Duration _pollInterval;
  final void Function(String message)? _log;

  // Legacy opcodes the calibrator still emits (kept as the seam's wire format).
  static const int _opEnter = 0x60;
  static const int _opPoint = 0x61;
  static const int _opEnd = 0x62;

  StreamController<Uint8List>? _controller;
  Timer? _poll;

  /// Guards against overlapping polls — one status read is in flight at a time
  /// (the SmpClient serialises anyway, but this keeps the timer from queuing a
  /// backlog if the link stalls).
  bool _polling = false;

  @override
  Stream<Uint8List> get statusStream {
    _controller ??= StreamController<Uint8List>.broadcast(
      onListen: _startPolling,
      onCancel: _stopPolling,
    );
    return _controller!.stream;
  }

  void _startPolling() => _poll ??= Timer.periodic(_pollInterval, (_) => _pollOnce());

  void _stopPolling() {
    _poll?.cancel();
    _poll = null;
  }

  Future<void> _pollOnce() async {
    if (_polling || !_isConnected()) return;
    _polling = true;
    try {
      final s = await _hs.bptCalStatus();
      _controller?.add(Uint8List.fromList([s.status & 0xFF, s.progress & 0xFF]));
    } catch (e) {
      // Best-effort feedback: a dropped poll must not tear the flow down.
      _log?.call('BPT: status poll failed: $e');
    } finally {
      _polling = false;
    }
  }

  @override
  Future<void> sendCommand(List<int> bytes) async {
    if (bytes.isEmpty) return;
    switch (bytes[0]) {
      case _opEnter:
        await _hs.bptCalEnter();
        break;
      case _opPoint:
        if (bytes.length >= 4) {
          await _hs.bptCalPoint(sys: bytes[1], dia: bytes[2], idx: bytes[3]);
        } else {
          _log?.call('BPT: short start-point packet $bytes');
        }
        break;
      case _opEnd:
        await _hs.bptCalEnd();
        break;
      default:
        _log?.call('BPT: unknown opcode ${bytes[0]}');
    }
  }

  @override
  bool get isConnected => _isConnected();

  /// Stop polling and close the feedback stream. Call when the calibration
  /// session ends (the screen also tears down the SMP session that owns [_hs]).
  Future<void> dispose() async {
    _stopPolling();
    await _controller?.close();
    _controller = null;
  }
}
