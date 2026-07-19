# Roadmap

Sequenced work for the redesign, with per-item status. For a quick "where were
we" snapshot start with [SESSION_HANDOFF.md](SESSION_HANDOFF.md); rationale for
each choice lives in [DECISIONS.md](DECISIONS.md); the protocol design in
[HEALTH_STORE_SYNC_DESIGN.md](HEALTH_STORE_SYNC_DESIGN.md).

**Status (2026-07-18):** Phases 0–6 are **done and hardware-validated** — the
Healthy Store sync, RECORDS, SUMMARY/trend derivation and the legacy-path
retirement have all been driven on a real Move, and the pre-redesign UI screens
have now been deleted. What remains is Phases 7–8 (publish the package, extract
the SDK); their hardware gate is lifted but the work has not started. This doc
stays until those close out.

**Two rules that govern everything below.**

1. **Migrate per *flow*, not per *file*** (design doc §2.5). A screen that *uses*
   a connection cannot be migrated while the screen that *establishes* it is on a
   different plugin — each plugin holds its own OS-level connection, so the
   migrated screen sees no link at runtime. The flows are: scan/pair, streaming,
   sync, DFU, records.
2. **`ACK` is destructive.** Commit to SQLite, persist the cursor, *then* ack.
   Never ack `hello.head`. Never ack an unpersisted `syncAll()` cursor.

Regression tripwires (current baselines): `flutter analyze` → **0 errors, 121
issues** (was 434; legacy-screen deletion + the 5a/5b/5c redesign off `hpi_legacy_theme`
removed the rest — should not increase). `flutter build bundle` → exit 0.
`flutter test test/smp_lock_test.dart` → 6 pass. `flutter test test/synthetic_banner_test.dart` → 2 pass.
`cd packages/healthypi_healthy_store && dart test` → 30 pass.
`flutter test` as a whole has one failing test — the `widget_test.dart` smoke test,
which pumps the app and hits a `StateError` in `HealthRepository.loadHome` with no
DB in the test env. Pre-existing (the shell was always the `/` entry); **not** a
regression.

---

## Phase 0 — Repo hygiene (do first, cheap) ✅ done

- [x] **Commit the pending changes as a baseline** so the redesign has a clean
      point to diff against when copying back.
- [x] **Untrack committed build artifacts** under `android/build/` and
      `ios/build/`; ignore rules added (`git ls-files android/build ios/build`
      is now empty).
- [x] **Apply the package rename.** Landed as `hpi_health_store` →
      `healthypi_healthy_store` (and `HealthStore*` → `HealthyStore*` on the
      app-facing API); `HpiHs`/`Hs*` wire models deliberately unchanged. Barrel
      file, `pubspec.yaml` name, dep, and imports all updated (commit `76f2caa`).
- [x] Decide `android-deploy.yml`'s `packageName` → `com.protocentral.move`
      (commit `112334f`).

## Phase 1 — Prerequisite refactors ✅ done (one item superseded)

- [x] **Split `lib/globals.dart`** (554→176 lines, now imports no Flutter):
      `lib/theme/hpi_legacy_theme.dart`, `lib/models/trend_models.dart`,
      `lib/widgets/{battery_level_painter,loading_indicator}.dart` (commit
      `47d1e76`).
- [~] **Extract `parseTrendRecords()` out of the database** — *superseded, not
      needed.* The seam this was meant to create for Phase 3 is now the package's
      `HsSample.listFromBytes` decode; trend derivation runs off `hs_samples`, not
      the legacy in-transaction 16-byte parse, which is dead with the legacy path
      gone.
- [x] **Collapse the triplicated firmware-version read** (DIS `0x180A`/`0x2A26`)
      into `lib/utils/device_info_service.dart` (commit `47d1e76`). *(Later removed
      as orphaned when the legacy screens were deleted — see the Phase 8
      device-info note; the SDK will need a DIS read reconstituted.)*
- [x] **Promote `setDeviceTime`** out of `BackgroundSyncManager` into the shared
      `lib/utils/device_time_service.dart`. (Now also pushes the UTC offset via
      HPI_HS `SET_TZ`, cmd 7.)
- [ ] Optional: de-duplicate the log-index protocol re-inlined in
      `scr_{ecg,gsr,hrv}_recordings.dart`. **Deferred** — these legacy screens are
      retired in Phase 4's last item; not worth investing in.

## Phase 2 — Sample-tier sync (design doc Stage 2) ✅ done, hardware-validated

- [x] Schema bumped to **v7** (past the planned v6); `hs_samples`, `hs_types`,
      `hs_sync_state` added additively (plus `hs_records` from Phase 4). `_onUpgrade`
      extended; `health_trends` untouched.
- [x] `HealthyStoreSyncManager` written, reusing the existing
      `SyncProgress`/`SyncResult`/`progressStream` surface so home and sync UI are
      unchanged.
- [x] **Drives the paged `sync()` directly**, committing each page and persisting
      the cursor before advancing; acks only the persisted cursor.
- [x] All SMP work bracketed with `ConnectionManager.acquireSmp` / `releaseSmp`,
      released in a `finally`.
- [x] **Verified on hardware:** full drain, link-kill mid-sync with resume from
      cursor, and re-run as a no-op (`seq` is cursor and dedup key).

## Phase 3 — Trend derivation (Stage 3) ✅ done, hardware-validated

- [x] **Fixed-point units are per-metric** (not `TYPES.scale`) — handled at each
      metric's existing convention (skin temp in centi-degrees ÷100 at read, HR /
      SpO₂ raw).
- [x] **`session_id NOT NULL`** — derived rows use a synthetic id; upsert stays
      idempotent under `UNIQUE(timestamp, trend_type, device_mac)`.
- [x] Aggregates incrementally over touched hours; min/avg/max for `discrete`, sum
      for `cumulative` (per `HsClass`).
- [x] Feature-gated on `HELLO`. **Note:** the legacy fallback this item mentions
      was *removed* in Phase 5 — a HELLO refusal now prompts a firmware update
      rather than delegating to a dead protocol.

## Phase 4 — Records tier (Stage 4) ✅ done, hardware-validated

- [x] Redesigned Recordings library uses HPI_HS `RECORDS` list/get/ack
      (`HealthyStoreRecordsManager` + `ScrRecordings` / `ScrRecordingPreview`).
- [x] Keep `research_sessions` / `research_files` tables (mirrored on download);
      additive `hs_records` index (schema **v7**).
- [x] Download **on demand**, not eagerly on every sync.
- [x] Check `HsRecordDownload.crcOk` before `recordsAck`. Store and mark
      `PARTIAL`-flagged sessions (interrupted, not truncated) — don't discard.
- [x] Retire legacy `scr_{ecg,gsr,hrv}_recordings.dart` + FS pulls. **Done** —
      all 19 pre-redesign screens (recordings, old home/trends/device/settings and
      their metric children) deleted, along with the 12 helper files they
      transitively orphaned; `main.dart` routes trimmed to the shell + `/scan` +
      `/device/bpt-calibration`.

## Phase 5 — SUMMARY, retention, retire the legacy path (Stage 5) ✅ done

- [x] `SUMMARY` dashboard — fetched/cached each sync; drives the P3 continuous-HRV
      and HRV-derived stress card. `HsSummary` renders unknown keys generically.
- [x] Retire `background_sync_manager.dart` — the custom `0x50`/`0x54` cmd/data
      protocol and `/lfs/tr*` pulls are deleted. `HealthyStoreSyncManager` is the
      only sync entry point.

## Phase 6 — Fix the capability gate ✅ done

- [x] `HealthyStoreClient._probeHello()` now distinguishes "group unknown"
      (`rc` → prompt to update) from "transport failed" (timeout → retry). A flaky
      link no longer looks permanently like old firmware (commit `1f3d930`).

## Phase 7 — Publish `healthypi_healthy_store` ⏳ in progress (spun off, private)

Hardware gate satisfied (Phases 2 + 4). The package now lives in its own repo;
the remaining steps are held pending review and the repo going public.

- [x] `git subtree split --prefix=packages/healthypi_healthy_store` into
      **`Protocentral/healthypi_healthy_store`** — created **private**, default
      branch `main`, real 4-commit history preserved. CHANGELOG updated for
      `SYNTH` + `SET_TZ` before the split. The in-tree `packages/` copy is kept as
      the working source (sync forward with another `subtree split`).
- [ ] **Deferred — keep the app on the `path:` dep for now.** The `path:` → `git:`
      swap is blocked while the repo is private: the deploy workflows
      (`android-deploy.yml` / `ios-deploy.yml`, triggered on tag push) do a plain
      `checkout` + `flutter pub get` with no cross-repo token, so a private `git:`
      dep would fail `pub get` at release time. Do the swap once the repo is
      **public** (post-review), or add a CI deploy token if it must stay private.
- [ ] Migrate OpenView 3 off its six duplicate copies to the same dep (separate
      repo, not in this workspace).
- [ ] Publish `0.1.0` under the `protocentral.com` verified publisher (needs the
      repo public + pub.dev verified-publisher login).
- [ ] Fix OpenView's `hs.ack(head)` call (`device_manager_screen.dart:1273`) to
      use `ackDurablyStored` with a persisted cursor (separate repo).

## Phase 8 — `healthypi_move` SDK ⏳ in progress (2 of 4 done)

Both preconditions — Phase 5 deleting the legacy protocol (DECISIONS §11) and
hardware validation — are **met**. The durable surface is: transport +
connection + SMP lock, live streaming, DFU, device info, re-exported Health Store.
BPT is extracted (below); the rest is pending.

- [ ] Write the live-stream decoders and sample models. Partly done: the inline
      `setState` decode is now a `LiveSignal` enum with a `decode()` method in
      `lib/screens/scr_live.dart` (the old `scr_live_stream.dart` was deleted) —
      what remains is promoting it + sample models into the SDK. Needs hardware
      validation: sample rates and scaling for the live characteristics are written
      down nowhere.
- [x] Extract the BPT calibration state machine (`0x60`–`0x62`) into
      `lib/ble/bpt_calibrator.dart` — a transport-agnostic `ChangeNotifier`
      (`foundation`-only, SDK-ready) behind a `BptCalTransport` seam. The screen
      is now just its view; a `_ConnCmdBptTransport` adapter binds the custom CMD
      GATT service. Unit-tested (`test/bpt_calibrator_test.dart`, 8 tests) with a
      fake transport — impossible while the logic was welded into the widget.
      **Open, firmware-coordinated:** moving the *control* commands into the HPI_HS
      MCUmgr group (0x1000) for consistency is a later adapter swap — SMP has no
      server push, so the continuous contact/progress feedback would stay on a
      notify characteristic (or be polled) regardless. See DECISIONS (BPT/HPI_HS).
- [x] Wrap `ImgMgmt` into a `FirmwareUpdater` (`lib/ble/firmware_updater.dart`) —
      a transport-agnostic `ChangeNotifier` (`foundation`-only, SDK-ready) behind a
      `FirmwareUploadTransport` seam. It owns the multi-image upload→confirm walk,
      progress (per-image + `overallProgress`), and cooperative cancel (won't
      `confirm` an image once cancel is requested, so the device never swaps to a
      half-committed update). `scr_dfu_new.dart` is now just its view; an
      `_ImgMgmtUploadTransport` adapter binds the seam to `mcumgr_dart`'s `ImgMgmt`
      over the live SMP session. Unit-tested (`test/firmware_updater_test.dart`, 8
      tests) with a fake transport. **Stays in the SDK, not `mcumgr_dart`:** the
      raw wire (`upload`/`confirm`/chunking/SHA) is already in `mcumgr_dart` (pure
      Dart, shared with OpenView 3); a `ChangeNotifier` progress model is Flutter/
      presentation layer and would force Flutter into that pure-Dart package.
      Manifest→`FirmwareImage` mapping and the `dart:io` file read stay in the
      screen (the updater takes a lazy byte loader, so it never touches the FS).
- [ ] Ships as a Flutter package (`universal_ble` forces it) — one package, no
      `_ble` companion.
- [x] **Device-info gap closed:** reconstituted as `lib/ble/device_info.dart` — a
      pure-Dart `DeviceInfoReader` behind a `DisTransport` seam, widened from the
      deleted service's firmware-revision-only read to the full standard DIS set
      (manufacturer/model/serial/hw/fw/sw), each field tolerated on failure. The
      `isAtLeast` version-gate policy carried over verbatim. A `BleDisTransport`
      adapter (`lib/utils/ble_dis_transport.dart`) binds the seam to `BleManager`;
      `scr_dfu_new.dart`'s inline `180a/2a26` read now goes through it. 9 tests
      (`test/device_info_test.dart`). **Needs a device only to confirm the exact
      DIS strings the firmware reports** — structure + policy are validated here.

---

## Reference: verified facts worth not rediscovering

- `database_helper.dart` schema is at **v7**; `health_trends` has
  `UNIQUE(timestamp, trend_type, device_mac)` and `session_id INTEGER NOT NULL`.
  Raw `hs_samples` / `hs_types` / `hs_sync_state` / `hs_records` all exist.
- `lib/data/health_repository.dart` is the read path the redesigned trend screens
  use, so `health_trends` is the seam that keeps the UI stable across the sync
  rewrite. (`trends_data_manager.dart` was deleted with the legacy screens.)
- `healthypi_healthy_store` is a pure-Dart, no-Flutter path dependency, all MIT or
  BSD-3.
- `HpiHs` is **live** — it drives sample sync, RECORDS, SUMMARY, `SYNTH` and
  `SET_TZ` on the redesigned screens. (It was dead/ported code earlier in the
  redesign.)
- `background_sync_manager.dart` is **deleted**; the only lightly-Flutter-coupled
  (`foundation`-only) files left are `ble_manager`, `connection_manager`,
  `healthy_store_client`, and `smp_ble_transport`.
