// Copyright (c) 2024-2026 ProtoCentral
// SPDX-License-Identifier: MIT

import '../ble/device_info.dart';
import 'ble_manager.dart';

/// Binds the SDK-ready [DisTransport] seam to the app's `universal_ble` facade
/// for one device. The only piece that touches both [DeviceInfoReader] and the
/// plugin — it lives at the app/SDK boundary, never inside the pure-Dart reader.
///
/// A read is skipped (returns `null`) when the link is down, so a
/// [DeviceInfoReader] over a disconnected device degrades to "nothing reported"
/// instead of surfacing a GATT error.
class BleDisTransport implements DisTransport {
  BleDisTransport(this.deviceId);

  /// Canonical device handle (CoreBluetooth UUID on Apple, MAC on Android).
  final String deviceId;

  @override
  Future<List<int>?> readCharacteristic(
      String service, String characteristic) async {
    if (!await BleManager.instance.isConnected(deviceId)) return null;
    return BleManager.instance.read(deviceId, service, characteristic);
  }
}
