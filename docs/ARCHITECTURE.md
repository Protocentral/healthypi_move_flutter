# Architecture & design decisions

Why the HealthyPi Move companion app is built the way it is. Each entry records
the *why* — the *what* is visible in the code. For the device protocol see
[HPI_HS_API.md](HPI_HS_API.md); for the sync loop, [HEALTH_STORE_SYNC_DESIGN.md](HEALTH_STORE_SYNC_DESIGN.md).

---

## One BLE plugin, one SMP client

The app runs on a single BSD-licensed BLE plugin (`universal_ble`, all platforms)
and a single SMP/MCUmgr client (`mcumgr_dart`). There are two logical modes over
**one** physical link:

1. **Streaming** — live ECG/PPG/HR/SpO₂/temp over the custom GATT characteristics.
2. **SMP** — health-store sync, firmware DFU, and filesystem pulls over the Nordic
   SMP characteristic.

They must never overlap on the wire, which drives the two decisions below.

## Connection ownership: `ConnectionManager` owns the link

A single `ConnectionManager` singleton owns *the* live connection to the paired
device. Screens acquire and release it; they never call `connect` themselves.
This exists specifically to kill the per-screen connect/disconnect races that a
per-screen ownership model produces.

An SMP session *rides* that link (`SmpBleTransport(manageConnection: false)`); if
it managed its own connection it would either open a **second** OS-level
connection to a device the manager already holds, or its `disconnect()` would
tear down the shared link. Both failure modes are asserted against rather than
left to misbehave.

## SMP arbitration: one lock, owned by the connection

Sync, records, and DFU all speak SMP over **one characteristic** and must never
interleave — a background sync landing mid-DFU would corrupt the image upload. The
`ConnectionManager` owns the link, so it owns the mutex: `acquireSmp(owner)` →
token, `releaseSmp(token)`, throwing `SmpBusyException` when held.

Three load-bearing properties, each learned the hard way:

- **Token-guarded release** — releasing ignores a stale token, so a late teardown
  from a finished flow cannot free the lock a *different* flow now holds.
- **Force-release on disconnect / unexpected drop** — otherwise a dropped link
  wedges the lock and every later sync/DFU is refused.
- **Acquire before the flow's `try`, release in `finally`** — otherwise an
  early-return or an error path can strand the lock, or a busy-exception handler
  can tear down the link a legitimately-running flow owns.

## The health-store protocol is a pure-Dart package

The HPI_HS protocol (the `HpiHs` client, the `Hs*` wire models, `Crc32`) lives in
[`packages/healthypi_healthy_store`](../packages/healthypi_healthy_store) — pure
Dart, no Flutter, its own test suite. It is shared with other ProtoCentral tools
(e.g. OpenView 3) that previously carried byte-identical copies with no shared
source, so a fix in one never reached the others.

The boundary is deliberate. Protocol framing, CBOR, sequence matching, and the
OS/Image/FS MCUmgr groups already live in `mcumgr_dart` and are not
reimplemented. The one BLE-coupled file, `smp_ble_transport.dart`, stays in the
app — it belongs with a future device SDK, not a transport-agnostic protocol
package. Diagnostics are an injectable callback so the package never depends on
Flutter's logger.

## `ACK` is destructive — commit before you ack

`HpiHs.ackDurablyStored(seq)` (and `recordsAck(id)`) tell the device the client
holds everything up to that point; the device *may* then drop it. So the sync
manager acks **only** a cursor already committed to local storage — never
`hello.head`, never an unpersisted cursor. The method is named for its
precondition precisely because the harmless-sounding alternative (`ack`) invited
the unrecoverable mistake. See [HPI_HS_API.md](HPI_HS_API.md) §6.

## Honest data, never a fabricated value

The UI never invents a number. Three distinct states are kept apart because
collapsing any two would put a misleading value on screen:

- **Real data** — shown.
- **Supported but no data yet** — a "sync your watch" placeholder.
- **Supported, still learning you** — e.g. HRV stress is scored against the user's
  own rolling baseline, which takes ~a night to establish; until then the device
  reports the score as invalid and the UI says "building your baseline", **never a
  zero** (a 0 there reads as "calm" and means nothing).

Synthetic firmware test samples are stored but **excluded from every chart,
summary, and export**. Blood-pressure estimates follow the same honesty rule and
a regulatory one — see below.

## Blood pressure is a relative wellness trend, not a measurement

The watch estimates BP from finger PPG after a cuff-baseline set-up. The line that
makes BP a *regulated medical device* is **clinical classification**, not the
presence of numbers (the FDA's 2025 WHOOP warning → 2026 closeout). So the BP
screen:

- shows an estimated mmHg **range**, not a single cuff-style value (a single
  number overstates PPG precision) — derived on-phone from the algorithm's value ±
  a confidence-based half-width;
- compares today to the user's **own usual** on a **continuous** gradient — no
  Normal/Elevated/Stage buckets, no diagnostic threshold lines, no "healthy
  corridor";
- uses **relative** language ("higher *for you*") and a wellness disclaimer.

Calibration control rides HPI_HS (group `0x1000`, cmds 8–11) behind a
transport-agnostic `BptCalibrator` state machine, so the wire binding is an
adapter, not the screen. Because SMP cannot push, the continuous contact/progress
feedback is **polled** (`BPT_CAL_STATUS`), not streamed.

## Data layer: raw samples in, derived trends out

Synced samples land in a raw `hs_samples` store (keyed by the device's HPI_HS
`uid`). A derivation step aggregates them into `health_trends` (hourly/daily
min/avg/max per metric, plus 30-day baselines) — the stable read seam the trend
screens consume, so the UI is insulated from the sync internals. Event-class
metrics (BP estimates) are sparse and read directly, never aggregated into fake
hourly bins.

`health_trends` is a **derived cache**: a version stamp on the derivation logic
lets a changed derivation replay over the already-stored raw samples on the next
sync, rather than silently serving stale rows.
