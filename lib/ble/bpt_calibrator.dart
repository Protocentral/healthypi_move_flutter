// Copyright (c) 2024-2026 ProtoCentral
// SPDX-License-Identifier: MIT

import 'dart:async';

import 'package:flutter/foundation.dart';

/// The transport a [BptCalibrator] needs: a command sink plus a live status
/// stream. Deliberately narrow and BLE-agnostic — today an adapter binds it to
/// the custom CMD GATT service, but a future HPI_HS/SMP binding (control
/// commands over MCUmgr group `0x1000`) is a drop-in replacement here, with no
/// change to the state machine below.
///
/// The one thing this seam cannot paper over: SMP has no server push, so the
/// continuous [statusStream] feedback would have to stay on a notify
/// characteristic (or be polled) even if the *control* commands move to SMP.
abstract class BptCalTransport {
  /// Device→app status packets, `[statusCode, progress, …]` per notification.
  Stream<Uint8List> get statusStream;

  /// Send a raw command packet to the device. Ignored when the link is down.
  Future<void> sendCommand(List<int> bytes);

  /// Whether the link is currently up. Commands are dropped (not queued) when
  /// this is false — the same fail-soft behaviour the screen had inline.
  bool get isConnected;
}

/// Phases of a 3-point BPT calibration, in the order the UI walks them.
enum CalibrationState {
  preCalibration,
  readyForInput,
  calibrating,
  pointComplete,
  allComplete,
}

/// One completed reference point: the cuff reading the user entered, stamped
/// when the device reported the point complete.
class CalibrationPoint {
  final int pointNumber;
  final int systolic;
  final int diastolic;
  final bool isComplete;
  final DateTime? timestamp;

  CalibrationPoint({
    required this.pointNumber,
    required this.systolic,
    required this.diastolic,
    this.isComplete = false,
    this.timestamp,
  });
}

/// The BPT finger-cuff calibration state machine, lifted verbatim out of
/// `scr_bpt_calibration.dart` so it can be driven and unit-tested without a
/// widget or a real radio.
///
/// Protocol: three opcodes on the custom CMD service — set-mode `0x60`,
/// start-point `0x61` + `[sys, dia, index]`, end `0x62`. The device streams
/// `[status, progress]` packets while a point is in flight; `status == 2` while
/// [phase] is [CalibrationState.calibrating] completes the current point.
///
/// A [ChangeNotifier] so the screen can `addListener` and rebuild; every state
/// mutation calls [notifyListeners]. `foundation`-only, so it moves into the
/// `healthypi_move` SDK package unchanged when that lands (Phase 8).
class BptCalibrator extends ChangeNotifier {
  BptCalibrator(
    this._transport, {
    this.pointsRequired = 3,
    void Function(String message)? log,
  }) : _log = log;

  final BptCalTransport _transport;

  /// How many reference points a full calibration needs (firmware expects 3).
  final int pointsRequired;

  final void Function(String message)? _log;

  // Wire contract. Kept with the state machine that owns it; a future SMP
  // transport swaps the adapter, not these.
  static const List<int> _cmdSetMode = [0x60];
  static const List<int> _cmdStartPoint = [0x61];
  static const List<int> _cmdEnd = [0x62];

  StreamSubscription<Uint8List>? _sub;

  CalibrationState _phase = CalibrationState.preCalibration;
  int _currentPointIndex = 0;
  final List<CalibrationPoint> _points = [];
  int _statusCode = 0;
  int _progress = 0;
  String _statusMessage = '';
  bool _fingerSignalGood = false;
  bool _pointFailed = false;

  // The reference reading for the in-flight point, stashed on startPoint and
  // attached to the CalibrationPoint when the device reports completion.
  int? _pendingSystolic;
  int? _pendingDiastolic;

  CalibrationState get phase => _phase;
  int get currentPointIndex => _currentPointIndex;
  List<CalibrationPoint> get points => List.unmodifiable(_points);
  int get pointCount => _points.length;
  int get statusCode => _statusCode;
  int get progress => _progress;
  String get statusMessage => _statusMessage;

  /// True once the finger PPG reports good contact (status 1/2); cleared on loss
  /// of contact (0/23/24). Sticky through transient bad packets so the UI's
  /// "ready" cue doesn't thrash.
  bool get fingerSignalGood => _fingerSignalGood;

  /// The last point failed (status 6) — the UI offers a retry that keeps the
  /// points already completed.
  bool get pointFailed => _pointFailed;

  /// Enter calibration mode (`0x60`) and begin listening for finger-signal
  /// status. Idempotent: the subscription is created once — re-subscribing
  /// mid-session drops the first status packets and makes the sensor look dead.
  Future<void> enterCalibrationMode() async {
    _sub ??= _transport.statusStream.listen(
      _onStatus,
      onError: (Object e) => _log?.call('BPT status stream error: $e'),
    );
    await _send(_cmdSetMode);
  }

  /// preCalibration → readyForInput (user tapped "Begin calibration").
  void beginInput() {
    _phase = CalibrationState.readyForInput;
    notifyListeners();
  }

  /// Start the current point: sends `[sys, dia, index]` and moves to
  /// calibrating. The reading is stashed and attached to the point when the
  /// device reports completion.
  Future<void> startPoint({
    required int systolic,
    required int diastolic,
  }) async {
    _pendingSystolic = systolic;
    _pendingDiastolic = diastolic;
    _phase = CalibrationState.calibrating;
    _progress = 0;
    _pointFailed = false;
    _statusMessage = _fingerSignalGood
        ? 'Hold still — measuring finger PPG…'
        : 'Seat the finger sensor, then hold still…';
    notifyListeners();
    await _send([
      ..._cmdStartPoint,
      systolic & 0xFF,
      diastolic & 0xFF,
      _currentPointIndex & 0xFF,
    ]);
  }

  /// Retry the current point after a failure, keeping earlier points.
  void retryPoint() {
    _pointFailed = false;
    _progress = 0;
    _statusMessage = '';
    _phase = CalibrationState.readyForInput;
    notifyListeners();
  }

  /// Advance to the next point after a completion
  /// (pointComplete → readyForInput).
  void advanceToNextPoint() {
    _currentPointIndex++;
    _phase = CalibrationState.readyForInput;
    notifyListeners();
  }

  /// End calibration mode on the device (`0x62`). Leaves local phase as-is —
  /// callers navigate away or reset the screen themselves.
  Future<void> endCalibration() async {
    await _send(_cmdEnd);
  }

  void _onStatus(Uint8List value) {
    if (value.length < 2) return;
    final code = value[0];
    final prog = value[1];
    _log?.call('BPT status=$code progress=$prog');

    _statusCode = code;
    _progress = prog;
    _statusMessage = statusMessageFor(code);

    // Status 1/2 = good contact; keep the flag until contact is lost (0/23/24)
    // so a brief blip doesn't thrash the UI.
    if (code == 1 || code == 2) {
      _fingerSignalGood = true;
    } else if (code == 0 || code == 23 || code == 24) {
      _fingerSignalGood = false;
    }
    if (code == 6) _pointFailed = true;

    if (code == 2 && _phase == CalibrationState.calibrating) {
      _pointFailed = false;
      _completePoint();
    }
    notifyListeners();
  }

  void _completePoint() {
    _points.add(CalibrationPoint(
      pointNumber: _currentPointIndex + 1,
      systolic: _pendingSystolic ?? 0,
      diastolic: _pendingDiastolic ?? 0,
      isComplete: true,
      timestamp: DateTime.now(),
    ));
    _phase = _points.length >= pointsRequired
        ? CalibrationState.allComplete
        : CalibrationState.pointComplete;
  }

  Future<void> _send(List<int> bytes) async {
    if (!_transport.isConnected) {
      _log?.call('BPT: link down, skipping command $bytes');
      return;
    }
    try {
      await _transport.sendCommand(bytes);
    } catch (e) {
      _log?.call('BPT: error sending command $bytes: $e');
    }
  }

  @override
  void dispose() {
    _sub?.cancel();
    _sub = null;
    super.dispose();
  }

  /// Human-readable meaning of a device status code. Protocol semantics, so it
  /// lives with the state machine rather than the screen; colour mapping stays
  /// in the UI (it's Flutter-specific).
  static String statusMessageFor(int code) {
    switch (code) {
      case 0:
        return 'No PPG signal — seat the finger sensor firmly';
      case 1:
        return 'Good finger signal — ready to calibrate';
      case 2:
        return 'Calibration point complete';
      case 4:
        return 'Too much motion — rest your hand and stay still';
      case 6:
        return 'Calibration failed — check finger contact and retry';
      case 3:
      case 16:
      case 19:
        return 'Weak PPG — try a warmer finger, firmer contact, less pressure';
      case 23:
      case 24:
        return 'No finger contact — slide the sensor fully onto the fingertip';
      default:
        return code == 0 ? '' : 'Sensor status $code';
    }
  }
}
