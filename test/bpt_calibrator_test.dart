// Copyright (c) 2024-2026 ProtoCentral
// SPDX-License-Identifier: MIT

import 'dart:async';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:move/ble/bpt_calibrator.dart';

/// In-memory transport: records the command packets the calibrator emits and
/// lets a test push device status packets back. No radio, no widget.
class FakeBptTransport implements BptCalTransport {
  final _status = StreamController<Uint8List>.broadcast();
  final List<List<int>> sent = [];
  bool connected = true;

  @override
  Stream<Uint8List> get statusStream => _status.stream;

  @override
  Future<void> sendCommand(List<int> bytes) async => sent.add(List.of(bytes));

  @override
  bool get isConnected => connected;

  /// Push a device status packet and let the calibrator's listener run.
  Future<void> emit(List<int> bytes) async {
    _status.add(Uint8List.fromList(bytes));
    await Future<void>.delayed(Duration.zero);
  }

  Future<void> dispose() => _status.close();
}

void main() {
  late FakeBptTransport tx;
  late BptCalibrator cal;

  setUp(() {
    tx = FakeBptTransport();
    cal = BptCalibrator(tx);
  });

  tearDown(() async {
    cal.dispose();
    await tx.dispose();
  });

  test('enterCalibrationMode sends 0x60 and subscribes', () async {
    await cal.enterCalibrationMode();
    expect(tx.sent, [
      [0x60]
    ]);
    expect(cal.phase, CalibrationState.preCalibration);
  });

  test('startPoint emits [0x61, sys, dia, index] and enters calibrating',
      () async {
    await cal.enterCalibrationMode();
    cal.beginInput();
    expect(cal.phase, CalibrationState.readyForInput);

    await cal.startPoint(systolic: 120, diastolic: 80);
    expect(cal.phase, CalibrationState.calibrating);
    expect(tx.sent.last, [0x61, 120, 80, 0]);
  });

  test('a status-2 packet completes the point with the entered reading',
      () async {
    await cal.enterCalibrationMode();
    cal.beginInput();
    await cal.startPoint(systolic: 118, diastolic: 76);

    await tx.emit([1, 40]); // good contact mid-point
    expect(cal.fingerSignalGood, isTrue);
    expect(cal.phase, CalibrationState.calibrating);

    await tx.emit([2, 100]); // point complete
    expect(cal.phase, CalibrationState.pointComplete);
    expect(cal.points, hasLength(1));
    expect(cal.points.single.systolic, 118);
    expect(cal.points.single.diastolic, 76);
    expect(cal.points.single.pointNumber, 1);
  });

  test('three points walk to allComplete, indices advancing', () async {
    await cal.enterCalibrationMode();
    cal.beginInput();

    for (var i = 0; i < 3; i++) {
      expect(cal.currentPointIndex, i);
      await cal.startPoint(systolic: 120 + i, diastolic: 80 + i);
      expect(tx.sent.last, [0x61, 120 + i, 80 + i, i]);
      await tx.emit([2, 100]);

      if (i < 2) {
        expect(cal.phase, CalibrationState.pointComplete);
        cal.advanceToNextPoint();
        expect(cal.phase, CalibrationState.readyForInput);
      } else {
        expect(cal.phase, CalibrationState.allComplete);
      }
    }
    expect(cal.points, hasLength(3));
  });

  test('status 6 flags failure; retry returns to input keeping prior points',
      () async {
    await cal.enterCalibrationMode();
    cal.beginInput();

    // First point succeeds.
    await cal.startPoint(systolic: 120, diastolic: 80);
    await tx.emit([2, 100]);
    cal.advanceToNextPoint();

    // Second point fails.
    await cal.startPoint(systolic: 130, diastolic: 85);
    await tx.emit([6, 0]);
    expect(cal.pointFailed, isTrue);

    cal.retryPoint();
    expect(cal.phase, CalibrationState.readyForInput);
    expect(cal.pointFailed, isFalse);
    expect(cal.points, hasLength(1)); // the completed first point is kept
    expect(cal.currentPointIndex, 1); // still on point 2
  });

  test('good-contact flag is sticky through weak packets, cleared on loss',
      () async {
    await cal.enterCalibrationMode();
    await tx.emit([1, 0]);
    expect(cal.fingerSignalGood, isTrue);
    await tx.emit([4, 0]); // motion — not a contact-loss code
    expect(cal.fingerSignalGood, isTrue);
    await tx.emit([23, 0]); // no contact
    expect(cal.fingerSignalGood, isFalse);
  });

  test('commands are dropped (not thrown) when the link is down', () async {
    tx.connected = false;
    await cal.enterCalibrationMode();
    expect(tx.sent, isEmpty); // 0x60 dropped, no throw
  });

  test('a short status packet is ignored', () async {
    await cal.enterCalibrationMode();
    await tx.emit([1]); // < 2 bytes
    expect(cal.statusCode, 0); // unchanged
  });
}
