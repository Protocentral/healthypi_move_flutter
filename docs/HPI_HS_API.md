# HPI_HS — HealthyPi Healthy Store protocol

HPI_HS is the HealthyPi Move's on-device **health store**: an hourly-binned
metric store plus an episodic raw-signal record store, exposed to a companion
app over Bluetooth. This document is the wire contract — the commands, their
request/response shapes, and the packed structures they carry.

The reference client is the pure-Dart package
[`packages/healthypi_healthy_store`](../packages/healthypi_healthy_store) (class
`HpiHs`, plus the `Hs*` models). The app talks to it through one SMP session; see
[HEALTH_STORE_SYNC_DESIGN.md](HEALTH_STORE_SYNC_DESIGN.md) for how the sync loop
is driven and persisted.

---

## 1. Transport

HPI_HS is a **vendor MCUmgr (SMP) group**, id **`0x1000`**. It rides the standard
Nordic SMP GATT service — the same characteristic used for firmware DFU and the
MCUmgr OS/Image/FS groups — so a device speaks HPI_HS iff it exposes SMP.

- **Service** `8D53DC1D-1DB7-4CD3-868B-8A527460AA84`
- **Characteristic** `DA2E7828-FBCE-4E01-AE9E-261174997C48` (write + notify)

Requests are CBOR maps framed in an 8-byte SMP header `(op, flags, len, group,
seq, id)`. Reads use `SMP_OP_READ`, writes use `SMP_OP_WRITE`. Every response
carries an MCUmgr result code `rc` (0 = success); a non-zero `rc` is surfaced as
an exception. Only **one** SMP flow (sync / records / DFU) may be in flight at a
time — they share the single characteristic.

## 2. Commands

Group `0x1000`. CBOR keys are kept short to fit the MTU.

| id | Name | Op | Request | Response |
|----|------|----|---------|----------|
| 0 | `HELLO` | READ | `{}` | `{schema, group, dev, uid, head, oldest, types}` |
| 1 | `TYPES` | READ | `{from}` | `{types:[…], next, total}` — paged registry |
| 2 | `SYNC` | READ | `{since, max}` | `{recs:bstr(n·18), n, next, more}` |
| 3 | `SUMMARY` | READ | `{}` | device-defined key/value map |
| 4 | `RECORDS` | READ | `{op, …}` | list / chunked payload (see §7) |
| 5 | `ACK` | WRITE | `{seq}` | `{rc}` — **destructive**, see §6 |
| 6 | `SYNTH` | WRITE | `{days, wipe}` | `{rc}` — generate synthetic test data |
| 7 | `SET_TZ` | WRITE | `{off}` | `{rc}` — UTC offset in seconds |
| 8 | `BPT_CAL_ENTER` | WRITE | `{}` | `{rc}` |
| 9 | `BPT_CAL_POINT` | WRITE | `{sys, dia, idx}` | `{rc}` |
| 10 | `BPT_CAL_STATUS` | READ | `{}` | `{st, prog, idx, run}` |
| 11 | `BPT_CAL_END` | WRITE | `{}` | `{rc}` |

Two version axes are reported by `HELLO` and gate capabilities independently:
**`schema`** (the sample/registry wire format) and **`group`** (which commands
exist). Bump `group` when the command set grows; bump `schema` when a packed
structure changes.

## 3. HELLO — handshake & capability probe

A successful `HELLO` **is** the proof that a device implements HPI_HS; a
non-zero `rc` means it does not (old firmware → prompt for an update). A
*timeout* is not a verdict — retry it, never treat it as "unsupported".

| Field | Meaning |
|---|---|
| `schema` | sample/registry wire-format version |
| `group` | command-set version |
| `dev` | device model string |
| `uid` | stable per-device id (the store key) |
| `head` | newest sample sequence available |
| `oldest` | oldest sequence still retrievable (0 on old firmware) |
| `types` | number of registry entries |

## 4. TYPES — the self-describing registry

The metric table is **read from the device, never hard-coded** — the device is
authoritative. `TYPES` is paged (`{from}` → `{types, next, total}`); loop
`from := next` until `next == total` or a page is empty. Cache entries by `id`.

Each entry (`HsType`):

| Field | Meaning |
|---|---|
| `id` | metric type id — matches the `type` byte in a sample |
| `key` | short name, e.g. `hr`, `spo2`, `bp_sys`, `hrv_rmssd` |
| `unit` | display unit, e.g. `bpm`, `%` |
| `scale` | fixed-point divisor: real value = `sample.value / scale` |
| `class` | statistical class (`D`/`C`/`E`, see below) |
| `derived` | whether the device computed it from other signals |
| `hk` / `hc` | optional HealthKit / Health Connect mapping hints |

**Statistical class** (`HsClass`) drives how a client aggregates a metric:

- **`D` discrete** — avg / min / max over a bin (HR, SpO₂, temp, HRV).
- **`C` cumulative** — a running counter; per-bin value is a sum (steps, energy).
- **`E` event** — sparse, timestamped spot readings; **list them, never average
  into a per-hour value** (BP estimates, ECG-derived HR).

## 5. SYNC — the sample stream

`SYNC {since, max}` returns a page of packed samples newer than the `since`
cursor: `{recs: bstr(n · 18 bytes), n, next, more}`. `max` is clamped device-side
(~40 samples/batch). Drive it cursor-first: request `since = lastStoredSeq`,
commit the page, persist `next`, then advance — never buffer the whole history in
memory. `more` is `n > 0 && next < head`, so it is safe to loop on and never true
on an empty page.

### Sample wire format (`HsSample`, 18 bytes, little-endian)

`struct.unpack('<IqBBi', rec)`:

| Offset | Field | Type | Meaning |
|---|---|---|---|
| 0 | `seq` | uint32 | monotonic per-device sequence — the sync cursor |
| 4 | `ts_utc` | int64 | seconds since Unix epoch (UTC) |
| 12 | `type` | uint8 | metric type id → look up in TYPES |
| 13 | `quality` | uint8 | quality/context bitmask (below) |
| 14 | `value` | int32 | fixed-point; real = `value / type.scale` |

### Quality bitmask (`HsQuality`)

| Bit | Flag | Meaning |
|---|---|---|
| 0 | `valid` | timestamp valid (RTC synced) and value in range |
| 1 | `onSkin` | sensor reports skin contact |
| 2 | `lowMotion` | IMU below the motion threshold |
| 3 | `highConf` | algorithm confidence high |
| 4 | `duringSleep` | captured in a sleep window |
| 5 | `manual` | user-initiated spot check |
| 6 | `synthetic` | **fabricated test data — never render as a measurement** |

**Synthetic samples** (bit 6) are generated on-device (`CONFIG_HPI_HS_SYNTH`) so
long-baseline features can be tested without a week of wear. They land in the same
store, interleaved with real readings. Storing them is fine; a client must
**exclude them from every chart, summary, and export**, or fabricated data would
be silently mistaken for a measurement.

## 6. ACK — retention, and why it is destructive

`ACK {seq}` tells the device the client has durably stored everything up to
`seq`. It is **contractually destructive**: the device *may* drop every sample at
or below `seq`, with no error if you never stored them.

**Only ack a cursor you have already committed to local storage** — never
`hello.head`, never an in-memory cursor. Getting this wrong is unrecoverable;
getting it needlessly right is free.

On current firmware `ACK` is a **no-op** — flash is reclaimed by size-based
retention regardless. But the contract still permits dropping, and a future
firmware could honour it, so the commit-before-ack discipline is kept anyway.

## 7. RECORDS — episodic raw-signal sessions

Long raw-signal captures (ECG / PPG / GSR / IMU sessions) are stored separately
and pulled on demand. `RECORDS` is an `op`-multiplexed command:

- **list** → an array of `HsRecordHeader`.
- **get** → chunked payload (`{data: bstr, eof}`), reassembled client-side and
  CRC-checked against the header before use.
- **ack** → drop a session after a verified on-phone copy.

### Record header (`HsRecordHeader`)

Device emits `{id, sig, fmt, ch, rate, ns, len, crc, flags, ts}`:

| Field | Meaning |
|---|---|
| `id` | session id |
| `ts` | start timestamp (UTC seconds) |
| `sig` | signal type — `enum hpi_hs_signal`, **1-based**, see below |
| `fmt` | sample encoding (`enum hpi_hs_sfmt`) — pins bytes-per-sample |
| `ch` | channel count |
| `rate` | sample rate (Hz) |
| `ns` | sample count |
| `len` | payload byte length |
| `crc` | CRC-32 of the payload (0 = none) |
| `flags` | bit 0 `COMPLETE`; a **PARTIAL** session is usable, not truncated — store and mark it, don't discard; a `COMPRESSED` payload must not be decoded as raw samples |

Verify `crc` before trusting a decoded payload, and store `PARTIAL` sessions
flagged rather than dropping them.

### Signal codes (`sig`)

Pinned against `enum hpi_hs_signal` in the firmware's `hpi_hs_types.h`. **The
enum starts at 1** — `0` is not a signal.

| `sig` | Signal | Source |
|---|---|---|
| `0x01` | ECG | MAX30001, int32 raw |
| `0x02` | BioZ / GSR | MAX30001, int32 raw |
| `0x03` | PPG wrist | MAX32664C, multi-LED |
| `0x04` | PPG finger | MAX32664D, multi-LED |
| `0x05` | HRV R-R | uint16 ms |
| `0x06` | IMU accel | int16 x/y/z |

A 0-based reading of this table shifts every code by one and is silent about
it: ECG sessions list as GSR, GSR as PPG, IMU disappears, and the ECG bucket
can never be filled because nothing emits `0`. Regression-tested in
`packages/healthypi_healthy_store/test/hs_record_wire_test.dart`.

## 8. SUMMARY

`SUMMARY` returns a device-defined key/value map of things the phone cannot
derive itself — the device's own rolling baselines and, on P3+ firmware, an
HRV-derived stress score with a validity flag. It is one cheap round-trip;
refresh it each session, and never let its failure fail the sync (the samples are
the system of record). Clients must render unknown keys generically and treat a
`stress_hrv_v == false` as "still building baseline", **never a zero**.

## 9. SET_TZ

`SET_TZ {off}` carries the phone's current UTC offset in seconds
(`DateTime.now().timeZoneOffset.inSeconds` — already DST-aware). The device
stores the offset separately from its RTC, so a DST change costs only a re-send,
never an RTC rewrite. Send it on every connect / time sync.

## 10. BPT calibration (cmds 8–11)

Blood-pressure calibration control lives in this group (it moved off a retired
custom cmd/data GATT service). The three control commands are a clean SMP fit;
the continuous contact/progress **feedback** cannot be pushed by SMP, so the
client **polls `BPT_CAL_STATUS`** (~6 Hz) while a point runs.

- `BPT_CAL_ENTER {}` — enter calibration mode.
- `BPT_CAL_POINT {sys, dia, idx}` — begin point `idx` (0-based) with the cuff
  reference `sys`/`dia` (mmHg, one byte each). Firmware rejects an out-of-range or
  out-of-order index with a non-zero `rc`.
- `BPT_CAL_STATUS {}` → `{st, prog, idx, run}` — current status code, progress
  0–100, point index, and whether a measurement is in flight. The two terminal
  codes for a running point are `st == 2` (complete) and `st == 6` (failed).
- `BPT_CAL_END {}` — exit calibration mode.

A full calibration is **3 points**. Status codes (finger-PPG contract): `0`
no signal, `1` good contact, `2` point complete, `3/16/19` weak PPG, `4` motion,
`6` failed, `23/24` no contact. Clients tolerate unknown codes (render generically)
and never treat them as terminal.

## 11. Defensive parsing

Some `TYPES` / `SUMMARY` / record-header shapes are pinned to firmware, but a
field that "should" be an int has appeared as another type across builds. Clients
**tolerate and skip** malformed entries rather than throwing — one bad row must
never sink a whole page.
