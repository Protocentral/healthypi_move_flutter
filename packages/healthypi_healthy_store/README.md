# healthypi_healthy_store

Pure-Dart client for the **ProtoCentral Healthy Store** (`HPI_HS`) — the vendor
MCUmgr group `0x1000` implemented by [HealthyPi Move](https://github.com/Protocentral/healthypi-move-fw)
firmware.

It reads health data off a Move **without touching firmware**, and has no Flutter
dependency — use it from a Flutter app, a CLI tool, a desktop research script, or
server-side ingest.

## API surface

| Method | What it's for |
| --- | --- |
| `hello()` | Handshake — schema/group version, device model + uid, `head` cursor. Doubles as the capability probe. |
| `types()` | The self-describing metric registry. Cache by `id`; never hard-code the table. |
| `sync()` / `syncAll()` | Cursor-based, resumable stream of packed 18-byte samples across every metric. |
| `summary()` | Device-computed baselines as a typed `HsSummary` (raw map still available via `.raw`). |
| `recordsList()` / `downloadRecord()` / `recordsAck()` | Episodic raw-signal sessions (ECG/GSR/PPG/HRV/IMU), CRC-32 verified. |
| `ackDurablyStored()` | Retention hint. **Destructive** — see the warning below. |
| `setTimezone()` | Push the phone's UTC offset so the device renders local wall-clock time without an RTC rewrite on DST. |
| `bptCalEnter()` / `bptCalPoint()` / `bptCalStatus()` / `bptCalEnd()` | Blood-pressure calibration control (cmds 8–11). |
| `synth()` | Generate on-device synthetic samples for testing (dev firmware only). |

## Transport

This package speaks SMP but does not own a link. It builds on
[`mcumgr_dart`](https://pub.dev/packages/mcumgr_dart), which defines the
`SmpTransport` abstraction and the SMP framing / CBOR / sequence-matching layer.
Supply any transport — BLE, serial, TCP.

```dart
import 'package:healthypi_healthy_store/healthypi_healthy_store.dart';
import 'package:mcumgr_dart/mcumgr_dart.dart';

final client = SmpClient(myTransport);   // your SmpTransport
final hs = HpiHs(client, log: print);    // log is optional

// A successful HELLO *is* the capability probe: a device that answers with an
// unknown-group error has no Healthy Store (feature-detect, don't version-gate).
try {
  final hello = await hs.hello();
  // ... device implements HPI_HS
} on SmpException {
  // firmware predates the Healthy Store
}
```

## Incremental sync

`seq` is monotonic per device and is **both the resume cursor and the dedup key**,
so an interrupted sync costs nothing — resume from the last persisted cursor.

```dart
final hello = await hs.hello();
final types = await hs.types();               // cache by id
var cursor = loadCursor(hello.uid);           // 0 = all retained history

while (true) {
  final page = await hs.sync(since: cursor, max: 256);
  for (final s in page.samples) {
    final t = types[s.type];                  // real value = s.real(t)
    await persist(s, t);
  }
  cursor = page.next;
  await saveCursor(hello.uid, cursor);        // persist BEFORE acking
  if (!page.more) break;
}

await hs.ackDurablyStored(cursor);
```

Key the cursor by `hello.uid` (the stable per-device id), not `hello.dev` (the
device model string). Samples carry UTC seconds (`tsUtc`), a fixed-point `value`
(real units are `value / type.scale`, or `sample.real(type)`), and a `quality`
bitmask (`HsQuality`) that gates analysis — including a `synthetic` bit that
marks fabricated test data, which must never be rendered as a measurement.

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

The parsers tolerate cross-firmware variation rather than throwing: `TYPES`,
`SUMMARY`, and record headers accept candidate key names and skip malformed
entries (reported through the `log` callback) so one bad row never sinks a page.
Record-header keys are pinned against current firmware; `summary()` returns a
typed `HsSummary` while still exposing the raw map via `.raw`.

## Status

`0.1.0`. The sample and records tiers are hardware-verified against a HealthyPi
Move; record-header keys are pinned. Some `TYPES`/`SUMMARY` fields may still firm
up before `1.0.0`, which is why the parsers stay defensive.

## License

MIT. See [LICENSE](LICENSE).
