# HealthyPi Move — Health Store (HPI_HS) sync architecture

**Status:** design (2026-07-07). Target app: `healthypi_move_flutter/move`.
Companion contract: `HPI_HS_API.md` (firmware repo) — group `0x1000`.
Reference implementation: OpenView 3 (`protocentral_openview3`), which already
ships a proven, hardware-verified HPI_HS client (`lib/smp/`, `lib/mcumgr/hpi_hs.dart`,
`lib/models/hs_*.dart`).

---

## 0. Why this redesign

Today the Move app pulls health data over **two parallel channels**:

1. **Custom cmd/data GATT service** (`UUID_SERVICE_CMD 01bf7492…`): per-metric
   commands — `getSessionCount (0x54)`, `sessionLogIndex (0x50)`,
   `setDeviceTime (0x41)` — with hand-parsed reply packets (`CMD_RSP 0x06`,
   `LOG_IDX 0x05`, `DATA 0x02`). See `background_sync_manager.dart`.
2. **MCUmgr-FS** (`mcumgr_flutter` `FsManager.download`) pulling whole per-session
   files from `/lfs/{trhr,trtemp,trspo2,trsteps}/<sessionId>` (trends) and
   `/lfs/{ecg,gsr,ppgw,ppgf,hrv}` (raw research recordings).

Problems this creates: two protocols to maintain, per-metric bespoke packet
parsing, whole-file re-pulls (today's session re-downloaded every sync), a fragile
`FsManager.kill()` disconnect dance, device-local-time timestamps with a packed
tz-offset, and a hard-coded metric list on the client.

**HPI_HS collapses all of this into one self-describing SMP group (`0x1000`):**

- **Sample tier** (`SYNC`) — a single cursor-based, incremental stream of packed
  18-byte samples (`seq, ts_utc, type, quality, value`) for *every* metric, with a
  self-describing **`TYPES`** registry. Replaces channel #1 entirely and the
  `/lfs/tr*` trend files.
- **Records tier** (`RECORDS`) — episodic raw-signal sessions (ECG/GSR/PPG/HRV/IMU)
  listed + fetched in CRC-verified chunks. Replaces the `/lfs/{ecg,…}` file pull.
- **`SUMMARY`** — at-a-glance baselines. **`ACK`** — retention hint. **`HELLO`** —
  handshake + schema/version + `head` cursor.

Net: **one protocol, cursor-based incremental sync, UTC timestamps, phone as the
system of record** — all over **one BLE plugin (`universal_ble`) and one SMP
client**, retiring both the custom cmd/data channel and `mcumgr_flutter`.

---

## 1. Principles

- **Phone is the system of record.** Store **raw samples** durably; derive trends,
  baselines, and HealthKit/Health Connect exports from them. The device keeps only
  a rolling window and drops what we `ACK`.
- **Idempotent + resumable.** `seq` is the cursor and the dedup key. A dropped link
  mid-sync costs nothing — resume from the last persisted cursor.
- **Self-describing.** Never hard-code the metric table; read `TYPES` and cache by
  `id`. Adding a device metric must not require an app release.
- **Feature-detected, not version-gated.** Presence of a working `HELLO` decides the
  HPI_HS path; fall back / prompt-to-update otherwise.
- **Defensive parsing.** The firmware CBOR shapes are not fully pinned; every field
  read tolerates a type/shape surprise (learned the hard way — see OpenView's
  `HsType.fromMap` after `TYPES failed: type int`).

---

## 2. Communication stack

```
┌───────────────────────────── Move app ─────────────────────────────┐
│  HealthStoreSyncManager  (rewrite of background_sync_manager)       │
│      │ HELLO/TYPES/SYNC/SUMMARY/ACK/RECORDS                          │
│  HpiHs (group 0x1000 facade)      ◄── port verbatim from OpenView   │
│      │ send(op,group,id,payload) → SmpMessage                       │
│  SmpClient  (seq alloc, response match, fragment reassembly)        │
│      │ write(frame) / notifications                                 │
│  SmpBleTransport  (universal_ble)  ◄── reuse OpenView's verbatim    │
│      │ write-without-response + notify on the SMP characteristic    │
└──────────────────────── BLE: SMP GATT service ─────────────────────┘
   Service 8d53dc1d-1db7-4cd3-868b-8a527460aa84  (already in globals as UUID_SERV_SMP)
   Char    da2e7828-fbce-4e01-ae9e-261174997c48  (UUID_CHAR_SMP) — write+notify
```

### 2.0 BLE plugin: migrate FBP → `universal_ble` (do first)

The Move app is on **`flutter_blue_plus` 2.x**, whose license **requires a paid
commercial license for any for-profit use** (ProtoCentral qualifies), forbids
relicensing, and pings build-time telemetry — incompatible with shipping as genuine
open source. OpenView already **migrated to `universal_ble`** (BSD-3, maintained, all
platforms) and hardware-verified it. **Do the same here** so both apps share one BLE
layer and the exact same SMP transport.

Scope of the migration (FBP is used in `ble_controller.dart`,
`background_sync_manager.dart`, `scr_device_scan.dart`, the streaming screens, and
DFU):
- Replace FBP scan/connect/notify/write with `universal_ble` (static/singleton API
  keyed by `deviceId`; hold the resolved service/char UUID strings). OpenView's
  `BleService` + `DeveloperBleController` are ready idioms.
- **Retire `mcumgr_flutter`.** Because we're porting OpenView's SMP core — which
  includes `img_mgmt.dart` (image list / SHA-256 chunked upload / test / confirm) —
  **DFU also moves onto the same `universal_ble` SMP transport**, so the app ends on
  **one** BLE plugin and **one** SMP client for health sync *and* firmware. (OpenView
  deliberately rejected `mcumgr_flutter` for being native-mobile-only; here it's
  simply redundant once the SMP core is in.)
- universal_ble needs **iOS deployment target ≥ 13.1** (bump `ios/Podfile` + Runner),
  macOS ≥ 10.15, Android `minSdk 21`.

### 2.1 Why a hand-rolled SMP client (not `mcumgr_flutter`)

`mcumgr_flutter` exposes stock managers (`FsManager`, `ImageManager`, …) but **no
generic custom-group transaction API**, so it can't speak group `0x1000`. The
proven path (OpenView) is a small, transport-agnostic, pure-Dart SMP core over the
SMP characteristic. **Port it as-is; the `universal_ble` transport comes over from
OpenView unchanged (§2.0).**

Files to port from OpenView (pure Dart, no edits needed):
- `lib/smp/smp_message.dart` — 8-byte header + CBOR; `rc` (v1) **and** `err` (v2);
  `errorLabel` (named MCUmgr codes).
- `lib/smp/smp_client.dart` — seq allocation, response matching, **notification
  reassembly** (buffer until `8 + len`), timeouts.
- `lib/smp/smp_transport.dart` — the abstract seam.
- `lib/mcumgr/hpi_hs.dart` — the `0x1000` facade (HELLO/TYPES/SYNC/`syncAll`/
  SUMMARY/ACK/RECORDS list+get+`downloadRecord` w/ CRC-32).
- `lib/models/hs_type.dart`, `hs_sample.dart`, `hs_summary.dart`, `hs_record.dart`,
  `lib/utils/crc32.dart`.

Because the Move app moves to `universal_ble` (§2.0), `SmpBleTransport` is **reused
verbatim from OpenView** (`lib/smp/smp_ble_transport.dart`) — connect, gate on the
SMP service, subscribe, write-without-response, MTU-settle. No new transport code.

Add deps: `universal_ble`, `cbor`, `crypto` (all as in OpenView). Remove
`flutter_blue_plus` and `mcumgr_flutter`. `fl_chart` is already present for the
record charts.

### 2.2 MTU (critical — from OpenView hardware experience)

On iOS/macOS the ATT MTU settles **just after** connect, so read during connect it's
the 23-byte default (`maxWriteLength` 20) and uploads/large frames break. **Poll
`requestMtu` for a few seconds post-connect** and re-read before any `RECORDS`/upload
work; size chunks off the live `maxWriteLength`. Verified to settle 20 → 244 B on a
Move. If it stays 20, it's a firmware cap (`CONFIG_BT_L2CAP_TX_MTU`). For sync
(request/response) throughput is bounded by the BLE connection interval, so request a
high connection priority on Android.

### 2.3 One SMP client for sync *and* DFU

After §2.0 there is no `mcumgr_flutter` — health sync and firmware both go through the
single `SmpClient` on the SMP characteristic. They still must not overlap on the wire,
so gate all SMP work (sync, records, DFU) behind one **"SMP busy"** flag. DFU uses the
ported `img_mgmt.dart` (SHA-256, device-driven offset chunking sized off the live
`maxWriteLength`, test → `os reset` → confirm) — see OpenView's Firmware tab.

### 2.4 Recommended BLE architecture changes (beyond the plugin swap)

The current app has **no BLE abstraction** — 24 files call `FlutterBluePlus` /
`BluetoothDevice` directly, each connecting/disconnecting the same device and managing
its own stream subscriptions. That scatter is *why* the migration touches so many files
and why the disconnect sequences are fragile. While we're in here, adopt the structure
OpenView already uses (and which the shared SMP package reinforces):

1. **A single `BleService` facade (the only file that imports `universal_ble`).**
   Scan (with the HealthyPi name filter) + system/bonded devices, connect/disconnect
   **by `deviceId`**, per-characteristic notify streams + write, adapter state, MTU.
   Screens depend on the facade, never the plugin → the plugin stays swappable and the
   next screen migrations become "use the facade" instead of 19 bespoke rewrites.
   (Mirror OpenView `lib/transport/ble_service.dart` + `TransportService`.)

2. **One connection owner (`ConnectionManager`).** A single object owns the active link
   to the paired device; screens *acquire/release* it rather than each calling
   `BluetoothDevice.fromId(mac).connect()` independently. This removes the current
   per-screen connect/disconnect races and the `FsManager.kill()` + delay dance.
   (Mirror OpenView `ConnectionController`.)

3. **Model the two GATT "modes" explicitly on that one connection:**
   - **Streaming** — live ECG/PPG/HR/SpO₂ over the custom streaming characteristics
     (`UUID_STREAM_*`, HR/SpO₂/temp chars) for live-view screens.
   - **SMP** — HPI_HS sync + DFU via `HealthStoreClient` over the SMP characteristic.
   Same physical connection; the connection owner arbitrates so the two never overlap
   on the wire. The legacy **custom cmd/data channel is retired** (its session/log-index
   commands are replaced by SMP `SYNC`); only the live-streaming chars remain.

4. **`deviceId` (String) is the canonical device handle everywhere** — no
   `BluetoothDevice` objects passed between screens (universal_ble forces this; it's
   also cleaner). The paired MAC already *is* this string.

5. **Centralize BLE/connection state in one `provider`/`bloc`** (the connection owner as
   a `ChangeNotifier`), replacing the per-screen `setState` stream subscriptions. The
   trend/live screens `watch` it.

6. **Share the abstraction with OpenView.** Both apps end on the same `BleService` +
   the `mcumgr_dart` SMP package, so fixes/gotchas (MTU-settle, reconnect, defensive
   CBOR) live in one place.

**Sequencing:** introduce the `BleService` facade + `ConnectionManager` **before** the
bulk screen migrations (Stages 2–4) so each screen migrates onto the facade. The scan
screen (Stage 1, already done on raw universal_ble) can be refactored onto the facade
when it lands — low priority since it works.

---

## 3. Sample-tier sync (the workhorse)

### 3.1 Flow

```
connect → settle MTU
HELLO {}                       → {schema, group, dev, head, types}
  ├─ check schema == expected (else prompt update / read-only)
  └─ persist dev serial
TYPES {from:0}                 → cache registry by id (only if schema/types changed)
cursor = stored_cursor(dev)    (0 = full history the device still retains)
loop:
  SYNC {since: cursor, max: 256} → {recs:<N*18 bytes>, n, next, more}
    ├─ decode 18-byte records  (HsSample.listFromBytes)
    ├─ UPSERT into hs_samples  (PK seq → idempotent; dedup free)
    └─ cursor = next; persist cursor
  until !more
ACK {acked: cursor}            → device may drop retained ≤ cursor
SUMMARY {}                     → refresh at-a-glance baselines (optional)
aggregate hs_samples → health_trends (hourly/daily) for the existing trend screens
```

`seq` is monotonic per device and is both the **resume cursor** and the **dedup
key**, so the whole loop is safe to interrupt and re-run.

### 3.2 Sample decoding

18-byte packed little-endian record, `struct.unpack('<IqBBi')`:
`seq u32 @0 · ts_utc i64 @4 · type u8 @12 · quality u8 @13 · value i32 @14`.
Real value = `value / type.scale` from the cached `TYPES` entry. `ts_utc` is **UTC
seconds** (the redesign drops the old device-local-time + packed-tz-offset scheme —
store UTC, convert only for display). Quality flags gate analysis (`VALID`,
`ON_SKIN`, `LOW_MOTION`, `HIGH_CONF`, `DURING_SLEEP`, `MANUAL`).

---

## 4. Records-tier sync (raw signals)

For episodic ECG/GSR/PPG/HRV/IMU sessions:

```
RECORDS {op:list, since:<lastRecordId>} → [{id,start_ts,signal,fmt,ch,sr,n,len,crc32,flags}, …]
for each new record:
  downloadRecord(header):                       (OpenView HpiHs.downloadRecord)
     loop RECORDS {op:get, id, off, len:chunk} → {off,data,eof}  until eof
     reassemble payload; CRC-32 verify vs header.crc32
  persist raw payload (research_files / app docs dir) + header (research_sessions)
  RECORDS {op:ack, id}                          → device may drop the session
```

- **CRC-32** is IEEE/zlib (matches Zephyr `crc32_ieee`) — `utils/crc32.dart`.
- **PARTIAL**-flagged sessions are usable (interrupted, not truncated) — store and
  mark, don't discard.
- Records can be large; download **on demand** (when the user opens a recording) or
  opportunistically in the background with a size budget — not eagerly on every sync.
- This retires `research_recording_manager` + the `/lfs/{ecg,gsr,ppgw,ppgf,hrv}`
  `FsManager` pulls; keep `research_sessions`/`research_files` tables (schema below).

---

## 5. Local data model (system of record)

Keep `sqflite`. Add a **raw sample store** as the source of truth; keep
`health_trends` as a **derived** table so existing trend screens
(`TrendsDataManager`, `scr_hr`/`scr_spo2`/…) keep working unchanged.

```sql
-- NEW: raw samples (system of record)
CREATE TABLE hs_samples (
  device   TEXT NOT NULL,          -- HELLO dev serial (not MAC — stable across OS)
  seq      INTEGER NOT NULL,       -- device-monotonic; cursor + dedup key
  ts_utc   INTEGER NOT NULL,       -- UTC seconds
  type     INTEGER NOT NULL,       -- TYPES id
  quality  INTEGER NOT NULL,
  value    INTEGER NOT NULL,       -- fixed-point; real = value/scale
  PRIMARY KEY (device, seq)
);
CREATE INDEX idx_hs_type_ts ON hs_samples(device, type, ts_utc);

-- NEW: cached self-describing registry (from TYPES)
CREATE TABLE hs_types (
  device TEXT, id INTEGER, key TEXT, unit TEXT, scale INTEGER,
  class TEXT, derived INTEGER, hk TEXT, hc TEXT,
  PRIMARY KEY (device, id)
);

-- NEW: per-device sync state
CREATE TABLE hs_sync_state (
  device TEXT PRIMARY KEY,
  cursor INTEGER,          -- highest seq durably stored (= last ACK target)
  head   INTEGER,          -- last HELLO head
  schema INTEGER,
  last_sync_utc INTEGER,
  last_record_id INTEGER   -- RECORDS list cursor
);

-- REUSE (derived cache, unchanged shape): hourly/daily aggregates the trend UI reads
--   health_trends(trend_type, session_id, timestamp, value_avg/min/max, device_mac, …)
-- REUSE: research_sessions / research_files for the records tier
```

**Type id → `trend_type` mapping** for the derived aggregation: map by the `TYPES`
`key` (e.g. `hr`→`hr`, `spo2`→`spo2`, `skin_temp`→`temp`, `steps`→`activity`) so the
existing `health_trends`/`TrendsDataManager` continue to work. Aggregation = group
`hs_samples` by `type` and hour/day → min/avg/max (discrete) or sum (cumulative,
per the `class` field). Run it incrementally after each sync for the touched hours.

Migration: additive tables + a `_version` bump in `database_helper.dart`. No
destructive change to `health_trends`; on first HPI_HS sync the raw store simply
starts filling and back-populates trends going forward.

---

## 6. Firmware feature-detection & coexistence

```
after connect:
  try HELLO → HPI_HS present → use this design (new path)
  catch (rc / timeout / group unknown) →
     fw too old for HPI_HS → keep the legacy dual-channel sync, prompt to update
```

- No hard version string check needed — `HELLO` *is* the capability probe (mirrors
  OpenView's `_probeHealthStore`). Keep the existing `>= 1.9.0` gate only as a floor.
- Keep the legacy `background_sync_manager` path available during the transition;
  select at runtime on the `HELLO` result. Retire it once fleet firmware ships HPI_HS.
- `setDeviceTime` still runs on connect (device RTC), but timestamps now come back as
  UTC in samples, so the app no longer needs to reason about device-local time.

---

## 7. Background sync & connection lifecycle

- Rewrite `background_sync_manager.dart` as `HealthStoreSyncManager` with the §3/§4
  flow. There is no `FsManager` at all (DFU moved to the ported `img_mgmt`), which
  removes the brittle `FsManager.kill()` + 1.5 s delay disconnect sequence entirely.
- Reuse the existing `SyncProgress`/`SyncResult`/`progressStream` surface so the
  home/sync UI is unchanged.
- Connection: `universal_ble` connect → own the SMP characteristic for the sync →
  clean disconnect at the end. Auto-reconnect + resume-from-cursor on an
  unexpected drop (OpenView's `SmpController` reconnect logic is a ready pattern).
- Keep the current bonded-device / background-fetch triggers.

---

## 8. HealthKit / Health Connect bridge (optional, later)

`TYPES` carries `hk` (HealthKit type) and `hc` (Health Connect record) hints per
metric. A bridge maps each stored sample via its type's hint (e.g. `spo2` % → HK
`oxygenSaturation` as a 0..1 fraction). This is purely a read over `hs_samples` +
`hs_types`; it needs no protocol work and can ship after the core sync is solid.

---

## 9. Phased plan

0. **BLE migration (§2.0).** Move scan/connect/notify/write from `flutter_blue_plus`
   to `universal_ble`; bump iOS target to 13.1; remove `flutter_blue_plus` and
   `mcumgr_flutter`. Keep the app building against the legacy sync throughout.
1. **SMP core up.** Port OpenView `smp/` + `hpi_hs.dart` + `img_mgmt.dart` + models +
   `crc32`; reuse `smp_ble_transport.dart` verbatim; add `cbor`/`crypto`. Smoke test:
   `HELLO` + `echo`-style round-trip against a Move → prove transport + framing +
   CBOR + reassembly. (OpenView verified this end-to-end.) Move DFU onto `img_mgmt`.
2. **Sample sync.** `hs_samples`/`hs_types`/`hs_sync_state` tables; SYNC loop +
   cursor persistence + ACK; TYPES cache. Verify a full drain + resume.
3. **Trend derivation.** Aggregate `hs_samples` → `health_trends`; confirm the
   existing trend screens render from HPI_HS-sourced data. Feature-detect + keep
   legacy path as fallback.
4. **Records tier.** RECORDS list/download/CRC/ack; wire into
   `scr_{ecg,gsr,hrv}_recordings`; retire the `/lfs/{ecg,…}` FS pull.
5. **SUMMARY dashboard** + retention polish + background-sync integration.
6. **(Optional) HK/HC bridge.**

Each phase is independently shippable behind the `HELLO` feature gate.

---

## 10. Open items to confirm against real Move responses

The wire shapes below are handled defensively but should be pinned from live captures
(log the first raw `TYPES`/`SUMMARY`/`RECORDS` response, as OpenView does):

- `TYPES` value encodings (`class` may be an int code, `derived` may be `0/1`).
- `SUMMARY` exact CBOR keys (→ dashboard card labels).
- `RECORDS` header key names and the raw **sample encoding per signal** (bytes/sample
  is inferred from `len/(n·ch)`; confirm int16 vs int32 vs float per signal type).
- `HELLO` `head`/cursor semantics and the device retention window.
- Whether the device advertises the SMP service (for scan filtering) or must be
  matched by name + verified post-connect (OpenView assumes the latter).

---

## 10a. Follow-up: publish the SMP core as a pub.dev package (decided)

Once this BLE migration is complete, extract the generic SMP/MCUmgr core (currently
copied into both OpenView and Move) into a **pure-Dart pub.dev package**
(`mcumgr_dart`) + a `mcumgr_universal_ble` transport companion; keep `hpi_hs`/`hs_*`
out (app/vendor-specific). Both apps then depend on the package instead of carrying
copies. Fills a real gap — `mcumgr_flutter` is native mobile-only. Do it **after** the
migration stabilizes.

## 11. Reference

- HPI_HS contract: `HPI_HS_API.md` (firmware repo).
- Proven client: OpenView 3 `protocentral_openview3` —
  `lib/smp/`, `lib/mcumgr/hpi_hs.dart`, `lib/models/hs_*.dart`, `lib/utils/crc32.dart`,
  `lib/controllers/smp_controller.dart` (scan/connect/reconnect/MTU-settle patterns).
- Current Move sync being replaced: `lib/utils/background_sync_manager.dart`,
  `database_helper.dart`, `globals.dart` (`UUID_SERV_SMP`/`UUID_CHAR_SMP` already
  present).
