import 'package:hpi_health_store/hpi_health_store.dart';

import 'connection_manager.dart';
import 'health_store_client.dart';

/// Result of a Health Store capability check.
///
/// [supported] is the answer to "does this device speak HPI_HS?" — it is set by
/// the `HELLO` handshake, which *is* the capability probe (design doc §6). No
/// firmware version string is consulted: if `HELLO` answers, the group is there.
class HsProbeResult {
  const HsProbeResult({
    required this.supported,
    this.schema,
    this.group,
    this.dev,
    this.uid,
    this.head,
    this.typeCount,
    this.types = const {},
    this.summary = const {},
    this.maxWriteLength,
    this.error,
  });

  /// Device implements the HPI_HS group (HELLO answered).
  final bool supported;

  /// HELLO fields.
  final int? schema;
  final int? group;

  /// Model string — always "healthypi-move", identical on every unit.
  final String? dev;

  /// Per-unit device id; the key the local sample store is written under.
  final String? uid;

  final int? head; // newest seq available on device (NEVER ack this)
  final int? typeCount;

  /// The TYPES registry, fetched when supported. Empty on older firmware.
  final Map<int, HsType> types;

  /// Raw SUMMARY map, fetched when supported. Keys are not fully pinned yet, so
  /// this is kept raw for inspection (design doc §10).
  final Map<String, Object?> summary;

  /// Negotiated ATT write length. 20 means the MTU never settled — record and
  /// sample transfers will be unusably slow or fail.
  final int? maxWriteLength;

  final String? error;

  bool get mtuOk => (maxWriteLength ?? 0) > 20;
}

/// Probes a paired device for Health Store support.
///
/// Ownership: rides the [ConnectionManager] link (connecting it first if
/// needed), and [HealthStoreClient] brackets the whole thing with
/// `acquireSmp`/`releaseSmp`, so this can never interleave with a running sync,
/// records pull, or DFU — it throws `SmpBusyException` instead.
///
/// This is read-only. It never acks, so it cannot destroy device data.
class HealthStoreProbe {
  /// Run the capability check against [deviceId].
  ///
  /// Returns `supported: false` (not a throw) when the device simply doesn't
  /// implement HPI_HS — that's an expected answer for older firmware, and the
  /// caller should fall back to the legacy sync path.
  static Future<HsProbeResult> probe(String deviceId, {String? name}) async {
    final conn = ConnectionManager.instance;

    // HealthStoreClient(manageConnection: false) rides the shared link, so it
    // must be up and pointed at this device first.
    if (!conn.isConnected || conn.deviceId != deviceId) {
      await conn.connect(deviceId, name: name);
    }

    final client = HealthStoreClient(deviceId, name: name);
    try {
      await client.connect();

      if (!client.hasHealthStore) {
        return HsProbeResult(
          supported: false,
          maxWriteLength: client.maxWriteLength,
        );
      }

      final hello = client.hello!;
      final hs = client.hs!;

      // Pull the registry and summary too: together with HELLO these are the
      // three responses whose CBOR shapes still need pinning (design doc §10),
      // and they're what the dev console dumps for capture. Both are read-only.
      Map<int, HsType> types = const {};
      Map<String, Object?> summary = const {};
      try {
        types = await hs.types();
      } catch (_) {
        // Tolerate and continue — a registry we can't parse still leaves HELLO
        // a valid capability answer.
      }
      try {
        summary = await hs.summary();
      } catch (_) {}

      return HsProbeResult(
        supported: true,
        schema: hello.schema,
        group: hello.group,
        dev: hello.dev,
        uid: hello.uid,
        head: hello.head,
        typeCount: hello.types,
        types: types,
        summary: summary,
        maxWriteLength: client.maxWriteLength,
      );
    } catch (e) {
      return HsProbeResult(supported: false, error: '$e');
    } finally {
      // Always release the SMP wire, even on an early return or throw.
      await client.disconnect();
    }
  }
}
