// Copyright (c) 2026 ProtoCentral
// SPDX-License-Identifier: MIT

/// A pure-Dart client for the **ProtoCentral Health Store** (`HPI_HS`), the
/// vendor MCUmgr group (`0x1000`) exposed by HealthyPi Move firmware.
///
/// It lets you read a device's health data — without touching firmware — over
/// any SMP transport (BLE, serial, TCP). Bring your own
/// [`SmpTransport`](https://pub.dev/documentation/mcumgr_dart/latest/) from
/// `package:mcumgr_dart`; this package adds only the Health Store group and its
/// wire models.
///
/// The protocol has two tiers:
///
/// - **Samples** (`SYNC`) — one cursor-based, incremental, resumable stream of
///   packed 18-byte records covering every metric, described at runtime by the
///   self-describing `TYPES` registry. Never hard-code the metric table.
/// - **Records** (`RECORDS`) — episodic raw-signal sessions (ECG, GSR, PPG,
///   HRV, IMU), listed and fetched in CRC-32-verified chunks.
///
/// Plus `HELLO` (handshake + capability probe), `SUMMARY` (baselines) and `ACK`
/// (retention hint — **destructive**, see [HpiHs.ackDurablyStored]).
///
/// ```dart
/// final hs = HpiHs(SmpClient(myTransport));
/// final hello = await hs.hello();          // capability probe
/// final types = await hs.types();          // cache by id
/// var cursor = loadCursor(hello.dev);      // 0 = everything retained
/// while (true) {
///   final page = await hs.sync(since: cursor, max: 256);
///   await persist(page.samples);           // commit BEFORE acking
///   cursor = page.next;
///   await saveCursor(hello.dev, cursor);
///   if (!page.more) break;
/// }
/// await hs.ackDurablyStored(cursor);       // device may now drop <= cursor
/// ```
///
/// `seq` is both the resume cursor and the dedup key, so the loop is safe to
/// interrupt and re-run.
library;

export 'src/crc32.dart';
export 'src/hpi_hs.dart';
export 'src/models/hs_record.dart';
export 'src/models/hs_sample.dart';
export 'src/models/hs_type.dart';
