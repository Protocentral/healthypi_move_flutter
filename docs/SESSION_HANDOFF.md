# Session handoff

**Last updated:** 2026-07-14. **Branch:** `main`, pushed to `origin`
(`Protocentral/healthypi_move_flutter_next` — the private staging repo).

A resume-from-anywhere snapshot: what state the tree is in, what was just done,
and what to pick up next. The durable *why* still lives in
[DECISIONS.md](DECISIONS.md); the sequenced plan in [ROADMAP.md](ROADMAP.md).
This file is the short-lived "where were we" note that those two aren't.

---

## Baselines / tripwires (verify these first on a fresh checkout)

| Check | Expected | Notes |
|---|---|---|
| `flutter analyze` | **434 issues, 0 errors** | Was 445 at session start. **434 is the new tripwire — it should not increase.** All 434 are pre-existing lint (`avoid_print`, `withOpacity`, `constant_identifier_names`). |
| `flutter build bundle` | exit 0 | quickest full Dart compile |
| `flutter test` | **9 pass / 1 fail** | The 1 failure is the pre-existing `widget_test.dart` layout overflow (DECISIONS §12) — **not** a regression. |
| `cd packages/healthypi_healthy_store && dart test` | **30 pass** | pure-Dart protocol suite |
| `flutter test test/smp_lock_test.dart` | 6 pass | SMP arbitration |

Run `flutter pub get` and `(cd packages/healthypi_healthy_store && dart pub get)`
first on a new machine.

## Uncommitted working-tree change

- `lib/screens/scr_bpt_calibration.dart` — a **one-line trailing-whitespace**
  edit that predates this session. Trivial; left uncommitted. Not part of any
  task.

---

## What this session did (newest first, all pushed to `origin/main`)

| Commit | What |
|---|---|
| *(uncommitted)* | **Retire legacy sync.** Delete `background_sync_manager.dart`. HS-only path; auto `DeviceTimeService.setDeviceTime` on every sync connect; wire `ScrStressEda` + EDA spot checks; BPT finger-sensor flow (live PPG before cuff entry, retry on fail). |
| `47d1e76` | **Phase 1 refactors.** Split `globals.dart` (554→176 lines, now imports no Flutter): `lib/theme/hpi_legacy_theme.dart` (legacy TextStyles/Colors), `lib/models/trend_models.dart`, `lib/widgets/{battery_level_painter,loading_indicator}.dart`. Collapsed the triplicated DIS `0x180A/0x2A26` firmware-version read into `lib/utils/device_info_service.dart`. |
| `112334f` | **Hygiene.** MIT SPDX headers on all 85 files that lacked them (`*.g.dart` skipped). Fixed `android-deploy.yml` `packageName` → `com.protocentral.move`. Removed real dead code. |
| `76f2caa` | **Rename** `hpi_health_store` → `healthypi_healthy_store`, `HealthStore*` → `HealthyStore*` (app-facing only). `HpiHs`/`Hs*` wire models deliberately unchanged (firmware `HPI_HS` contract, shared with OpenView 3). |
| `387ff55` | **Moved `HsSummary` into the package** with keys pinned to firmware. Deleted the dead `HsSummaryCard` presentation. |
| `1f3d930` | **Phase 6.** `HELLO` timeout vs refusal now distinguished — a flaky link no longer looks like old firmware forever. `HealthyStoreClient.helloRc`, `HsProbeResult.reachable`. |
| `ce51701` | **RECORDS pinned to firmware** (`hpi_hs_mgmt.c`). Fixed 4 wire bugs: missing `ns` key, `from` vs `since` (index not id), no paging, inverted PARTIAL/COMPLETE. `decode` now trusts `fmt`. 10 new tests. |
| `7c5caad` | **HRV now renders** on the HR detail screen (was a hardcoded zero-state that never read the trend). |
| `8dfc10f` | **SYNTH button** on the Developer screen (`HpiHs.synth()`, HPI_HS cmd 6). Destructive `wipe` confirm; rc=8 = release build, rc=10 = busy. |
| `f43d4c4` | **One Developer screen** — absorbed the BLE console; added a LOCAL STORE diagnostics section. |
| `3357cc2` | **P3: continuous HRV + HRV-derived stress.** SUMMARY fetched/cached each sync; `MetricAvailability.baselining` ("building your baseline", never 0); the two `stress` metrics split by the MANUAL bit. |

Earlier in the same thread: `d0deb0f` synthetic-data banner, plus the
legacy-home nav fix and the initial RECORDS commit.

---

## Architecture deltas since the docs were written

These are **true now** and may contradict older prose in DECISIONS/ROADMAP:

- **`origin` exists.** It is the private staging repo
  `Protocentral/healthypi_move_flutter_next`. Push to `origin main`. (Older
  CLAUDE.md text says "no origin remote" — stale. `upstream` is production.)
- **Sample sync, trend derivation, RECORDS, and SUMMARY are all live** and
  wired through `HealthyStoreSyncManager` / `HealthyStoreRecordsManager` on the
  redesigned screens. ROADMAP still describes Phases 2–5 as unbuilt in places —
  the data-layer and read-path work is done; what remains is device validation.
- **Package is `healthypi_healthy_store`** (path dep). API classes are
  `HealthyStore*`; wire models stay `HpiHs`/`Hs*`.
- **`HsSummary` is a package model** with firmware-pinned keys and typed
  accessors (`stressHrv`, `rmssdMs`, …). The `*_valid` flags other than
  `stress_hrv_v` are **not on the wire** — don't rely on them.
- **Firmware handoff is at P3** (see `docs/FIRMWARE_HANDOFF_HS2.md`): §6 continuous
  HRV. Note that doc's P3 type-id table contradicts its own §3 registry — the app
  binds on TYPES **key strings**, never numeric ids, so it is immune; the doc
  should be reconciled on the firmware side.

---

## Not yet done, roughly in priority order

1. **Nothing has been driven on real hardware this session.** The highest-value
   next step is a bench Move (ideally a `CONFIG_HPI_HS_SYNTH=y` build): press
   **Developer → Generate synthetic data**, then sync, and verify end-to-end —
   HRV chart on the HR screen, the stress card leaving `baselining`, RECORDS
   list/download/CSV, and the LOCAL STORE diagnostics. The synthetic path exists
   specifically so this needs no week-long wear.
2. **Legacy custom sync path is gone.** `background_sync_manager.dart` has been
   deleted; `HealthyStoreSyncManager` is the only sync entry point. Device RTC is
   stamped via `DeviceTimeService` on every sync connect. Legacy *UI* screens
   (ECG/GSR/HRV FS recordings, old home) still exist as rollback chrome only —
   they no longer drive the old protocol.
3. **Phase 7 — publish `healthypi_healthy_store`.** Gated on hardware-validated
   SYNC + RECORDS (now pinned to firmware, but unproven on a device). `git subtree
   split`, swap OpenView 3 onto the shared dep, publish `0.1.0`.
4. **Optional: a blanket `dart format`** — deliberately skipped this session so
   real changes weren't buried under whitespace on a hand-copied-back branch. If
   wanted, do it as its own isolated commit.

## Rules that still override convenience

1. **Migrate per *flow*, not per *file*** — each BLE plugin owns its own OS-level
   connection.
2. **`HpiHs.ackDurablyStored()` / `recordsAck()` are destructive** — commit to
   SQLite and persist the cursor first; never ack `hello.head`.
3. **`SYNTH { wipe: true }` destroys data on the *watch*** (not the phone) —
   unsynced real measurements are gone. The confirm dialog says so.
4. **Parse device CBOR defensively** — tolerate and skip, don't throw.
