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

## Automatic sync is foreground-only, and defers to both radio modes

[`AutoSyncController`](../lib/utils/auto_sync_controller.dart) syncs on app start,
on resume, and on a tick while the app is open — never while backgrounded. That is
not a shortcut: real background sync needs iOS BLE state restoration, which
`universal_ble` does not expose, and a `Timer.periodic` in a suspended app buys a
wakeup iOS will not honour. The ticker is cancelled when the app is paused.

The guards live in `AutoSyncPolicy`, pure and unit-tested, because an automatic
flow is the one flow nobody is watching when it collides with something:

- **`isSmpBusy`** — the SMP lock above would throw anyway, but skipping earlier
  keeps a "skipped (smpBusy)" line in the log instead of an exception during a DFU.
- **`isStreaming`** — *the lock does not cover this.* It arbitrates SMP against
  SMP; streaming is the other logical mode on the same radio, and the two must not
  overlap on the wire. `ConnectionManager.isStreaming` is published by the Live
  screen from its subscription set (not toggled per call, so a double unsubscribe
  cannot leave it stuck on).
- **A persisted throttle** — the stamp is written *before* the run, so a sync that
  dies mid-way cannot become a retry loop across rapid foreground flips, and the
  interval survives a force-quit.

A sync is resumable from a persisted cursor, so the short 45 s budget running out
is not lost work — the next trigger carries on.

## Firmware updates: checked proactively, gated on app compatibility

The version check runs from the same lifecycle hook, through
[`FirmwareUpdateChecker`](../lib/utils/firmware_update_checker.dart), so an
available update reaches the Device screen instead of only whoever thinks to open
the DFU screen. **It never touches the radio**: the current version is the DIS
revision cached on the paired device by whatever last held a link (sync does this
on every session), and the latest comes from a 6-hour release cache — the GitHub
releases API is unauthenticated and rate-limited to 60 requests/hour *per IP*, so
a startup check must not fetch fresh each time. Connecting just to check would
burn battery and contend for the SMP lock against a sync or an in-flight DFU.

Firmware and app ship on independent schedules, so a firmware release can need
protocol support only a newer app has. A release declares that in its notes:

    [Minimum app version: 3.1.0]      or      [:mav: 3.1.0]

mirroring the store-listing convention `upgrader` already reads for the app
itself. **Absence means compatible** — the entire back catalogue is untagged, and
treating absence as "unknown, block it" would kill the update path for all of it.
When the tag does exceed the running build, `ScrDFUNew` shows *update the app
first* with no install button: MCUboot here is overwrite-only with no auto-revert,
so installing anyway would strand the user on a watch this app cannot talk to.
The gate sits *after* the pending-radio branch, because a half-finished two-stage
migration must always be allowed to finish.

`FirmwareUpdateState` has five values for the same reason `MetricAvailability` has
four. `unknown` is not `upToDate` — we have not checked, or could not read a
version, and nagging on a guess is a support ticket. `updateRequired` (pre-3.0
firmware, which cannot answer HPI_HS at all) is not `updateAvailable`.

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
