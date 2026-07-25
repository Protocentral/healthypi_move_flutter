// Copyright (c) 2024-2026 ProtoCentral
// SPDX-License-Identifier: MIT

import 'package:flutter_test/flutter_test.dart';
import 'package:move/ble/device_info.dart';

/// In-memory DIS: maps characteristic short-UUID → bytes (or an error). A
/// missing key returns null (characteristic absent); an entry in [errors]
/// throws (GATT read failure). No radio.
class FakeDisTransport implements DisTransport {
  FakeDisTransport(this.values, {this.errors = const {}});

  final Map<String, List<int>> values; // char → raw bytes
  final Set<String> errors; // chars whose read throws
  final List<String> reads = []; // chars actually requested

  @override
  Future<List<int>?> readCharacteristic(
      String service, String characteristic) async {
    reads.add(characteristic);
    if (errors.contains(characteristic)) {
      throw StateError('read $characteristic failed');
    }
    return values[characteristic];
  }
}

List<int> _ascii(String s) => s.codeUnits;

void main() {
  group('readFirmwareVersion', () {
    test('returns the trimmed DIS 0x2A26 string', () async {
      final tx = FakeDisTransport({'2a26': _ascii(' 2.1.0 \n')});
      final reader = DeviceInfoReader(tx);
      expect(await reader.readFirmwareVersion(), '2.1.0');
      expect(tx.reads, ['2a26']);
    });

    test('null when the characteristic is absent', () async {
      final reader = DeviceInfoReader(FakeDisTransport({}));
      expect(await reader.readFirmwareVersion(), isNull);
    });

    test('null (not a throw) when the read errors', () async {
      final reader =
          DeviceInfoReader(FakeDisTransport({}, errors: {'2a26'}));
      expect(await reader.readFirmwareVersion(), isNull);
    });

    test('empty bytes read as null, not an empty string', () async {
      final reader = DeviceInfoReader(FakeDisTransport({'2a26': const []}));
      expect(await reader.readFirmwareVersion(), isNull);
    });
  });

  group('readAll', () {
    test('populates every reported field and tolerates the rest', () async {
      final tx = FakeDisTransport(
        {
          '2a29': _ascii('ProtoCentral'),
          '2a24': _ascii('HealthyPi Move'),
          '2a26': _ascii('2.1.0'),
          '2a28': _ascii('zephyr-3.5'),
        },
        errors: {'2a25'}, // serial read flakes
        // hardware rev (2a27) simply absent
      );
      final info = await DeviceInfoReader(tx).readAll();

      expect(info.manufacturer, 'ProtoCentral');
      expect(info.model, 'HealthyPi Move');
      expect(info.firmwareRevision, '2.1.0');
      expect(info.softwareRevision, 'zephyr-3.5');
      expect(info.serialNumber, isNull); // errored → tolerated
      expect(info.hardwareRevision, isNull); // absent → tolerated
      expect(info.isEmpty, isFalse);
    });

    test('isEmpty when the device reports nothing', () async {
      final info = await DeviceInfoReader(FakeDisTransport({})).readAll();
      expect(info.isEmpty, isTrue);
    });
  });

  group('isAtLeast', () {
    test('compares major.minor', () {
      expect(DeviceInfoReader.isAtLeast('2.1.0', major: 2, minor: 0), isTrue);
      expect(DeviceInfoReader.isAtLeast('2.1.0', major: 2, minor: 1), isTrue);
      expect(DeviceInfoReader.isAtLeast('2.1.0', major: 2, minor: 2), isFalse);
      expect(DeviceInfoReader.isAtLeast('3.0.0', major: 2, minor: 9), isTrue);
      expect(DeviceInfoReader.isAtLeast('1.9.9', major: 2, minor: 0), isFalse);
    });

    test('tolerates a leading v and a -suffix on the minor', () {
      expect(DeviceInfoReader.isAtLeast('v2.1-rc1', major: 2, minor: 1), isTrue);
    });

    test('unknown/unparseable returns onUnknown (default permit)', () {
      expect(DeviceInfoReader.isAtLeast(null, major: 2, minor: 0), isTrue);
      expect(DeviceInfoReader.isAtLeast('unknown', major: 2, minor: 0), isTrue);
      expect(DeviceInfoReader.isAtLeast('garbage', major: 2, minor: 0), isTrue);
      expect(
        DeviceInfoReader.isAtLeast(null, major: 2, minor: 0, onUnknown: false),
        isFalse,
      );
    });
  });
}
