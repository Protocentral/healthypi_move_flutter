# Roadmap

Sequenced work for the redesign. Rationale for each choice lives in
[DECISIONS.md](DECISIONS.md); the protocol design lives in
[HEALTH_STORE_SYNC_DESIGN.md](HEALTH_STORE_SYNC_DESIGN.md).

**Two rules that govern everything below.**

1. **Migrate per *flow*, not per *file*** (design doc §2.5). A screen that *uses*
   a connection cannot be migrated while the screen that *establishes* it is on a
   different plugin — each plugin holds its own OS-level connection, so the
   migrated screen sees no link at runtime. The flows are: scan/pair, streaming,
   sync, DFU, records.
2. **`ACK` is destructive.** Commit to SQLite, persist the cursor, *then* ack.
   Never ack `hello.head`. Never ack an unpersisted `syncAll()` cursor.

Regression tripwires: `flutter analyze` → **0 errors, 445 issues** (should not
increase). `flutter build bundle` → exit 0. `flutter test test/smp_lock_test.dart`
→ 6 pass. `cd packages/hpi_health_store && dart test` → 12 pass.
`flutter test` as a whole **fails for a pre-existing reason** — see DECISIONS §12.

---

## Phase 0 — Repo hygiene (do first, cheap)

- [ ] **Commit the ~305 pending changes as a baseline** so the redesign has a
      clean point to diff against when copying back. Nothing is committed yet.
- [ ] **Untrack the 78 committed build artifacts** under `android/build/` and
      `ios/build/` (Xcode `XCBuildData/PIFCache`), and add ignore rules.
      `git rm -r --cached android/build ios/build`.
- [ ] **Apply the package rename** `hpi_health_store` → `healthypi_health_store`
      (DECISIONS §9). Touches: package `pubspec.yaml` name, barrel file
      `lib/hpi_health_store.dart` → `lib/healthypi_health_store.dart` and its
      `library` directive, the app's dep + the single `import` in
      `lib/utils/health_store_client.dart`, README, CHANGELOG. Class names stay.
- [ ] Decide `android-deploy.yml`'s `packageName` (currently wrong — DECISIONS §12).

## Phase 1 — Prerequisite refactors (improve the app regardless of packaging)

These delete real duplication, create testable seams, and are prerequisites for
*any* future SDK extraction. None depend on hardware.

- [ ] **Split `lib/globals.dart`.** `hPi4Global` mixes GATT UUIDs and command
      opcodes (lines 111–253) with ~20 `TextStyle`/`Color` constants (255–385),
      and the same file defines `BatteryLevelPainter extends CustomPainter` and
      `LoadingIndicator extends StatelessWidget`. Split into protocol constants,
      an app theme, and `lib/widgets/`. Touches ~30 files. **Do this first** —
      everything else in this phase waits on it.
- [ ] **Extract `parseTrendRecords()` out of the database.** The 16-byte record
      decode is fused *inside* the `db.transaction` loop in
      `database_helper.dart:254-333`, interleaved with `txn.insert`. Factor the
      parse into a pure function returning DTOs; the DB helper then only inserts.
      This is the seam Phase 3 needs.
- [ ] **Collapse the triplicated firmware-version read** (DIS `0x180A`/`0x2A26`),
      currently reimplemented in `BackgroundSyncManager._readFirmwareVersion`,
      `UpdateChecker._readFirmwareVersion`, and inline in `scr_dfu_new.dart`.
- [ ] **Promote `setDeviceTime` (`0x41`)** out of being a private method on
      `BackgroundSyncManager` into a shared device service.
- [ ] Optional: de-duplicate the log-index protocol re-inlined in
      `scr_{ecg,gsr,hrv}_recordings.dart`. Note much of this dies in Phase 4 —
      don't over-invest.

## Phase 2 — Sample-tier sync (design doc Stage 2)

**Start by pinning the wire shapes.** Design doc §10 items are still open: log
the first raw `TYPES`, `SUMMARY` and `RECORDS` response from a real Move and
confirm them before building on the current defensive guesses.

- [ ] Bump `database_helper.dart` to **v6** (currently v5); add `hs_samples`,
      `hs_types`, `hs_sync_state` additively per design doc §5. Extend
      `_onUpgrade`; no destructive change to `health_trends`.
- [ ] Write `HealthStoreSyncManager`, reusing the existing
      `SyncProgress`/`SyncResult`/`progressStream` surface so the home and sync UI
      are unchanged.
- [ ] **Drive the paged `sync()` directly, not `syncAll()`.** Commit each page to
      SQLite and persist the cursor before advancing; ack only the persisted
      cursor. `syncAll()` buffers everything in memory and must never feed an ack.
- [ ] Bracket all SMP work with `ConnectionManager.acquireSmp` / `releaseSmp`
      (DECISIONS §6). Release in a `finally`; never tear down the shared link on a
      failed acquire.
- [ ] Verify: full drain, then kill the link mid-sync and confirm resume from
      cursor. `seq` is both cursor and dedup key, so re-running must be a no-op.

## Phase 3 — Trend derivation (Stage 3)

Aggregate `hs_samples` → `health_trends` so `TrendsDataManager` and the trend
screens keep working unchanged. **Two verified traps:**

- [ ] **Fixed-point units are per-metric and are *not* `TYPES.scale`.**
      `health_trends.value_*` are `INTEGER`. Skin temp is stored in
      centi-degrees and `scr_skin_temp.dart:350-352` divides by 100 at read time;
      HR and SpO₂ are stored raw. Convert into each metric's existing convention
      or the charts silently go wrong by 100×.
- [ ] **`session_id` is `NOT NULL`** and there is a
      `UNIQUE(timestamp, trend_type, device_mac)` — good for idempotent upsert,
      but derived rows need a synthetic `session_id` (legacy code uses `0`).
- [ ] Aggregate incrementally over touched hours only. Group by `type` and
      hour/day → min/avg/max for `discrete`, sum for `cumulative` (per `HsClass`).
- [ ] Feature-gate on `HELLO`; keep the legacy path as fallback.

## Phase 4 — Records tier (Stage 4)

- [ ] Move `scr_{ecg,gsr,hrv}_recordings.dart` and `research_recording_manager`
      off the `/lfs/{ecg,…}` `FsMgmt` pulls onto `RECORDS` list/get/ack.
- [ ] Keep `research_sessions` / `research_files` tables as-is.
- [ ] Download **on demand**, not eagerly on every sync.
- [ ] Check `HsRecordDownload.crcOk` before `recordsAck`. Store and mark
      `PARTIAL`-flagged sessions (interrupted, not truncated) — don't discard.

## Phase 5 — SUMMARY, retention, retire the legacy path (Stage 5)

- [ ] `SUMMARY` dashboard. `HsSummary` already renders unknown keys generically,
      so this is mostly UI.
- [ ] Retire `background_sync_manager.dart` once fleet firmware ships HPI_HS.
      This deletes the custom `0x50`/`0x54` cmd/data protocol and the `/lfs/tr*`
      pulls.

## Phase 6 — Fix the capability gate

- [ ] `HealthStoreClient._probeHello()` swallows every exception identically.
      Distinguish "group unknown" (`rc` → legacy path, prompt to update) from
      "transport failed" (timeout → retry). Today a flaky link permanently looks
      like old firmware.

## Phase 7 — Publish `healthypi_health_store`

Gated on Phases 2 and 4 (wire shapes validated against hardware).

- [ ] `git subtree split --prefix=packages/healthypi_health_store` into
      `Protocentral/healthypi_health_store`.
- [ ] Swap the app's `path:` dep for a `git:` dep; migrate OpenView 3 off its six
      duplicate copies to the same dep (one-line pubspec change + delete copies).
- [ ] Publish `0.1.0` under the `protocentral.com` verified publisher.
- [ ] Fix OpenView's `hs.ack(head)` call (`device_manager_screen.dart:1273`) to
      use `ackDurablyStored` with a persisted cursor.

## Phase 8 — `healthypi_move` SDK

Only after Phase 5 deletes the legacy protocol (DECISIONS §11). The durable
surface is: transport + connection + SMP lock, live streaming, DFU, device info,
re-exported Health Store.

- [ ] Write the live-stream decoders and sample models that **do not exist today**
      (`scr_live_stream.dart:113-154` decodes inline in `setState`). Needs hardware
      validation: sample rates and scaling for the live characteristics are written
      down nowhere.
- [ ] Extract the BPT calibration state machine (`0x60`–`0x62`), currently inline
      in `scr_bpt_calibration.dart:344-449`.
- [ ] Wrap `ImgMgmt` + manifest into a `FirmwareUpdater`; the DFU protocol core is
      already outside the widget.
- [ ] Ships as a Flutter package (`universal_ble` forces it) — one package, no
      `_ble` companion.

---

## Reference: verified facts worth not rediscovering

- `database_helper.dart` schema is at **v5**; `health_trends` has
  `UNIQUE(timestamp, trend_type, device_mac)` and `session_id INTEGER NOT NULL`.
- `trends_data_manager.dart` is the **only** read path the trend screens use, so
  `health_trends` is the seam that keeps the UI stable across the sync rewrite.
- `hpi_health_store` runtime closure is 9 packages, all MIT or BSD-3, no Flutter.
- `HpiHs` is **dead code** in this app today — ported, compiling, never executed.
- 33 of 47 files under `lib/` import Flutter; only 5 are *lightly* coupled
  (`foundation` only): `ble_manager`, `connection_manager`,
  `background_sync_manager`, `health_store_client`, `smp_ble_transport`.
