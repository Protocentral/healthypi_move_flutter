# Session handoff

**Last updated:** 2026-07-18. **Branch:** `main`, pushed to `origin`
(`Protocentral/healthypi_move_flutter_next` — the private staging repo).

A resume-from-anywhere snapshot: what state the tree is in, what was just done,
and what to pick up next. The durable *why* still lives in
[DECISIONS.md](DECISIONS.md); the sequenced plan in [ROADMAP.md](ROADMAP.md).
This file is the short-lived "where were we" note that those two aren't.

---

## Baselines / tripwires (verify these first on a fresh checkout)

| Check | Expected | Notes |
|---|---|---|
| `flutter analyze` | **185 issues, 0 errors** | Was 434 before the legacy-screen deletion removed ~250 lint infos. **185 is the new tripwire — it should not increase.** All pre-existing lint (`avoid_print`, `withOpacity`, `constant_identifier_names`). |
| `flutter build bundle` | exit 0 | quickest full Dart compile |
| `flutter test` | **8 pass / 1 fail** | The 1 failure is the `widget_test.dart` smoke test — `StateError` in `HealthRepository.loadHome` with no DB in the test env (the shell is the `/` entry). Pre-existing, **not** a regression. (Was a `home.dart` layout overflow before the legacy screens were deleted.) |
| `cd packages/healthypi_healthy_store && dart test` | **30 pass** | pure-Dart protocol suite |
| `flutter test test/smp_lock_test.dart` | 6 pass | SMP arbitration |

Run `flutter pub get` and `(cd packages/healthypi_healthy_store && dart pub get)`
first on a new machine.

## Uncommitted working-tree change

- None of substance — the tree is committed through the legacy-screen deletion.

---

## What this session did (newest first, all pushed to `origin/main`)

| Commit | What |
|---|---|
| *(this session)* | **Delete the legacy UI.** Removed all 19 pre-redesign screens + `home.dart` and the 12 helper files they orphaned; trimmed `main.dart` routes to shell + `/scan` + `/device/bpt-calibration`. `flutter analyze` 434→185. |
| `07458ef` | **HPI_HS `SET_TZ` (cmd 7)** + **retire legacy sync.** `DeviceTimeService` pushes the UTC offset alongside the RTC set. Deleted `background_sync_manager.dart`; HS-only path; `sync_models.dart` split out; plus the accompanying screen redesigns. |
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

## Done since this file was last written

- **Healthy Store sync + RECORDS + SUMMARY are hardware-validated** on a real Move.
- **Legacy custom sync path is gone.** `background_sync_manager.dart` deleted;
  `HealthyStoreSyncManager` is the only sync entry point. Device RTC is stamped via
  `DeviceTimeService` on every sync connect, which now also pushes the UTC offset
  via HPI_HS `SET_TZ` (cmd 7).
- **Legacy UI screens are gone.** All 19 pre-redesign screens (ECG/GSR/HRV FS
  recordings, old home/trends/device/settings + metric children) and the 12 helper
  files they orphaned have been deleted; `main.dart` routes are trimmed to the
  shell, `/scan`, and `/device/bpt-calibration`. No rollback chrome remains.

## Not yet done, roughly in priority order

1. **Phase 7 — publish `healthypi_healthy_store`.** Its hardware gate is now
   lifted. `git subtree split`, swap OpenView 3 onto the shared dep, publish
   `0.1.0`. See ROADMAP Phase 7.
2. **Phase 8 — extract the `healthypi_move` SDK.** Live-stream decoders, the BPT
   calibration state machine, a `FirmwareUpdater` wrapper. See ROADMAP Phase 8.
3. **Optional: a blanket `dart format`** — deliberately skipped so real changes
   weren't buried under whitespace on a hand-copied-back branch. If wanted, do it
   as its own isolated commit.

## Rules that still override convenience

1. **Migrate per *flow*, not per *file*** — each BLE plugin owns its own OS-level
   connection.
2. **`HpiHs.ackDurablyStored()` / `recordsAck()` are destructive** — commit to
   SQLite and persist the cursor first; never ack `hello.head`.
3. **`SYNTH { wipe: true }` destroys data on the *watch*** (not the phone) —
   unsynced real measurements are gone. The confirm dialog says so.
4. **Parse device CBOR defensively** — tolerate and skip, don't throw.
