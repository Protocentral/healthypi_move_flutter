# healthypi_healthy_store

Pure-Dart client for the **ProtoCentral Healthy Store** (`HPI_HS`) — the vendor
MCUmgr group `0x1000` implemented by [HealthyPi Move](https://github.com/Protocentral/healthypi-move-fw)
firmware.

It lets you read health data off a Move **without touching firmware**. No Flutter
dependency: use it from a Flutter app, a CLI tool, a desktop research script, or
server-side ingest.

## What it gives you

| Command | What it's for |
| --- | --- |
| `hello()` | Handshake, schema/group version, device serial, `head` cursor. Doubles as the capability probe. |
| `types()` | The self-describing metric registry. Cache by `id`; never hard-code the table. |
| `sync()` / `syncAll()` | Cursor-based, resumable stream of packed 18-byte samples for every metric. |
| `summary()` | At-a-glance baselines, returned as the raw CBOR map. |
| `recordsList()` / `downloadRecord()` | Episodic raw-signal sessions (ECG/GSR/PPG/HRV/IMU), CRC-32 verified. |
| `ackDurablyStored()` / `recordsAck()` | Retention hints. **Destructive** — read the warning below. |

## Transport

This package speaks SMP but does not own a link. It builds on
[`mcumgr_dart`](https://pub.dev/packages/mcumgr_dart), which defines the
`SmpTransport` abstraction and the SMP framing/CBOR/sequence-matching layer.
Supply any transport — BLE, serial, TCP.

```dart
import 'package:healthypi_healthy_store/healthypi_healthy_store.dart';
import 'package:mcumgr_dart/mcumgr_dart.dart';

final client = SmpClient(myTransport);   // your SmpTransport
final hs = HpiHs(client, log: print);    // log is optional

final hello = await hs.hello();
if (hello.group != 1) { /* firmware predates this client */ }
```

A `HELLO` that fails with an unknown-group error means the firmware has no Health
Store; feature-detect on that rather than version-gating.

## Incremental sync

`seq` is monotonic per device and is **both the resume cursor and the dedup key**,
so an interrupted sync costs nothing — resume from the last persisted cursor.

```dart
final types = await hs.types();               // cache by id
var cursor = loadCursor(hello.dev);           // 0 = all retained history

while (true) {
  final page = await hs.sync(since: cursor, max: 256);
  for (final s in page.samples) {
    final t = types[s.type];                  // real value = s.real(t)
    await persist(s, t);
  }
  cursor = page.next;
  await saveCursor(hello.dev, cursor);        // persist BEFORE acking
  if (!page.more) break;
}

await hs.ackDurablyStored(cursor);
```

Samples carry UTC seconds (`tsUtc`), a fixed-point `value` (real units are
`value / type.scale`, or `sample.real(type)`), and a `quality` bitmask
(`HsQuality`) that gates analysis.

## ⚠️ `ackDurablyStored` and `recordsAck` are destructive

They tell the device it may **drop** data — everything at or below the acked
`seq`, or the acked record. There is no undo, and no error if you ack data you
never stored.

- Ack only after the data is committed to durable storage.
- Never ack `hello.head`. Never ack a cursor from an in-memory `syncAll()` that
  hasn't been persisted.
- For records, check `HsRecordDownload.crcOk` before acking.

`syncAll()` is a convenience that buffers every page in memory. It's fine for
exploration and small backlogs; for a real sync loop, page with `sync()` and
commit as you go.

## Defensive parsing

The firmware's `TYPES`, `SUMMARY` and `RECORDS` CBOR shapes are not fully pinned.
`HsType.fromMap` and `HsRecordHeader.fromMap` accept several candidate key names
and tolerate type surprises rather than throwing; unparseable `TYPES` entries are
skipped and reported through the `log` callback. `summary()` deliberately returns
the raw map — presentation is the caller's business.

## Status

`0.1.0`. The sample tier is hardware-verified against a HealthyPi Move. The
`RECORDS` and `SUMMARY` wire shapes are handled defensively but not yet pinned
from live captures; expect their key names to firm up before `1.0.0`.

## License

MIT. See [LICENSE](LICENSE).
