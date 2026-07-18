# Session handoff

**Last updated:** 2026-07-19. **Branch:** `main`, pushed to `origin`
(`Protocentral/healthypi_move_flutter_next` — the private staging repo).

A resume-from-anywhere snapshot: what state the tree is in, what was just done,
and what to pick up next. The durable *why* lives in [DECISIONS.md](DECISIONS.md);
the sequenced plan + per-phase status in [ROADMAP.md](ROADMAP.md).

---

## Baselines / tripwires (verify first on a fresh checkout)

| Check | Expected | Notes |
|---|---|---|
| `flutter analyze` | **182 issues, 0 errors** | Was 434 before the legacy-screen deletion. **182 is the tripwire — should not increase.** All pre-existing lint (`avoid_print`, `withOpacity`, `constant_identifier_names`). |
| `flutter build bundle` | exit 0 | quickest full Dart compile |
| `flutter test` | **16 pass / 1 fail** | The 1 failure is the `widget_test.dart` smoke test — `StateError` in `HealthRepository.loadHome` with no DB in the test env (the shell is the `/` entry). Pre-existing, **not** a regression. |
| `cd packages/healthypi_healthy_store && dart test` | **30 pass** | pure-Dart protocol suite |
| `flutter test test/smp_lock_test.dart` | 6 pass | SMP arbitration |
| `flutter test test/bpt_calibrator_test.dart` | 8 pass | BPT state machine (new) |

Run `flutter pub get` and `(cd packages/healthypi_healthy_store && dart pub get)`
first on a new machine.

## Working-tree state

Clean at handoff — everything below is committed and pushed to `origin/main`.

---

## What this session did (newest first, all on `origin/main`)

| Commit | What |
|---|---|
| `6fe823f` | **Phase 7 status** — record the spin-off + defer the `path:`→`git:` dep swap. |
| `f03a9d5` | **BPT-over-HPI_HS firmware handoff** (`docs/FIRMWARE_HANDOFF_BPT_HS.md`); retire `FIRMWARE_HANDOFF_HS2.md`. |
| `9dfe7cb` | **Package CHANGELOG** — note `SYNTH` + `SET_TZ` (cmd 7) in 0.1.0. |
| `4f71a80` | Remove `SESSION_HANDOFF` + `HS_SYNC_FIRMWARE_BUG`, fix dangling refs. *(This file was later recreated.)* |
| `3e76c3c` | **Phase 8: BPT calibration state machine extracted** behind a `BptCalTransport` seam (`lib/ble/bpt_calibrator.dart`, 8 tests). |
| `80abe5c` | **Delete the 19 legacy pre-redesign screens** + 12 orphaned helpers; trim `main.dart` routes. analyze 434→185. |
| `07458ef` | **HPI_HS `SET_TZ` (cmd 7)** + finish Phase 5 legacy-sync removal (`background_sync_manager.dart` deleted). |

## Big rocks: where Phase 7 & 8 stand

**Phase 7 — publish `healthypi_healthy_store`** (in progress):
- ✅ Spun off to **`Protocentral/healthypi_healthy_store`** — **private**, `main`,
  real history preserved. The in-tree `packages/` copy is kept as the working
  source (sync forward with another `git subtree split`).
- ⏸️ **Dep swap deferred.** App stays on the `path:` dep. A private `git:` dep
  would break `pub get` in the tag-triggered deploy workflows (no cross-repo
  token). Do the swap once the repo is **public** (post-review), or add a CI token.
- ⛔ Publish `0.1.0` and the OpenView 3 migration (+ its `hs.ack(head)` fix) are
  blocked on the repo going public / pub.dev auth / a separate repo.

**Phase 8 — `healthypi_move` SDK** (in progress, 1 brick done):
- ✅ **BPT calibration** extracted (`lib/ble/bpt_calibrator.dart`) — the pattern
  for the rest. Firmware-facing move-to-HPI_HS spec in
  `docs/FIRMWARE_HANDOFF_BPT_HS.md` (DECISIONS §13).
- ⏳ **`FirmwareUpdater`** — wrap `ImgMgmt` + `manifest.dart` into one class. Pure
  refactor, **no hardware dependency** — the best next brick, doable + testable here.
- ⏳ **Live-stream decoders** — promote `LiveSignal.decode` (now in
  `lib/screens/scr_live.dart`, not the deleted `scr_live_stream.dart`) + sample
  models into the SDK. **Blocked:** live-characteristic sample rates / scaling are
  documented nowhere — needs a hardware pass.
- ⏳ **Ship the package** — Flutter package (universal_ble forces it), moves the
  durable surface in (transport + connection + SMP lock, streaming, DFU, device
  info, re-exported Health Store). Gated on the two items above.
- ⚠️ **Device-info gap:** `device_info_service.dart` was deleted as orphaned in the
  legacy cleanup; the SDK's "device info" surface needs a DIS read reconstituted.

## Recommended next step

`FirmwareUpdater` (Phase 8) — the only remaining pending item that is pure refactor
with no hardware dependency, so it can be finished and unit-tested here exactly
like the BPT extraction.

## Heads-up: external doc deletions

Three tracked docs were deleted from the working tree by something outside the
assistant's actions across recent sessions (`SESSION_HANDOFF.md`,
`HS_SYNC_FIRMWARE_BUG.md`, `FIRMWARE_HANDOFF_HS2.md`) — all handled cleanly at the
user's direction. If an IDE/sync process is removing files unprompted, worth a
glance so it doesn't catch something meant to be kept.

## Rules that override convenience

1. **Migrate per *flow*, not per *file*** — each BLE plugin owns its own OS-level
   connection.
2. **`HpiHs.ackDurablyStored()` / `recordsAck()` are destructive** — commit to
   SQLite and persist the cursor first; never ack `hello.head`.
3. **`SYNTH { wipe: true }` destroys data on the *watch*** — unsynced real
   measurements are gone.
4. **Parse device CBOR defensively** — tolerate and skip, don't throw.
5. **Bracket every SMP flow** with `ConnectionManager.acquireSmp` / `releaseSmp`
   (release in a `finally`).
