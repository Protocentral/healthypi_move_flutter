# Decisions log

Architectural decisions and their rationale, newest section last. Each entry
records *why*, not just *what* — the what is visible in the diff, the why is not.

Companion documents: [ROADMAP.md](ROADMAP.md) for sequenced work,
[HEALTH_STORE_SYNC_DESIGN.md](HEALTH_STORE_SYNC_DESIGN.md) for the sync design.

---

## 1. This repo is the redesign fork

`healthypi_move_flutter_next` is a byte-identical duplicate of
`healthypi_move_flutter` taken mid-migration (branch `migrate-to-hs-api`,
base commit `ff105d3` plus ~305 uncommitted changes). Work happens here; it is
copied back when done.

The duplicate was made by copying the working tree **and** `.git`, not by
`git clone` — a clone would have taken only the committed state and silently
dropped the ~305 uncommitted changes that make up most of the recent work.

`origin` was renamed to `upstream` and no `origin` is set, so an accidental
`git push` has no default target and cannot land in the production repo.
`upstream` still points at `Protocentral/healthypi_move_flutter` for copying back.

## 2. Repo layout flattened: `move/` → repository root

The Flutter app lived in a `move/` subdirectory. It is now a standard
root-level Flutter project. Moved with `git mv` (git detected 284 renames, so
history follows the files). The two `.gitignore` files were merged and the
project-specific rules re-anchored.

Everything that referenced the old path was updated: both CI workflows,
`.github/RELEASE.md`, and `.vscode/settings.json` (which had an absolute local
path hardcoded).

**Note:** `package:move/...` imports across `lib/` are the *Dart package name*
(`name: move` in `pubspec.yaml`), not the directory. They are unrelated to this
change and were correctly left alone.

## 3. `mcumgr_dart` consumed from pub.dev, not as a git submodule

Switched from a `packages/mcumgr_dart` submodule to `mcumgr_dart: ^0.1.0`
(hosted). Verified no regression before swapping: the published 0.1.0 tarball
differs from the pinned submodule commit only by license headers, `dart format`
reflows, and a reworded pubspec description. `lib/` has zero API or behavioural
change and `test/` is byte-identical — the submodule HEAD *is* the 0.1.0 release
commit.

Consequence: a fresh clone no longer needs `git submodule update --init`.

## 4. Two latent bugs fixed

- **`BleManager.instance.init()` was never called.** `main()` went straight to
  `runApp`, so `universal_ble` stayed at its verbose default log level. Now
  awaited in `main()`.
- **`intl` was imported by 12 files but was only a transitive dependency.**
  Any dependency bump could have broken the build. Now a direct dependency,
  pinned at `^0.20.2` — the version already resolving, so the lockfile did not
  move.

## 5. Connection ownership: `ConnectionManager` owns the link; SMP sessions ride it

`HealthStoreClient` defaulted to `manageConnection: true`, so it would have
opened a **second OS-level BLE connection** to a device `ConnectionManager`
already held. Every other SMP flow (background sync, records, DFU) already rode
the shared link with `manageConnection: false`.

`HealthStoreClient` now takes `manageConnection` (default `false`), passes it
through to `SmpBleTransport` — which it previously did not, so its `disconnect()`
would have torn down a shared link — and `_assertOwnershipIsCoherent()` makes
both failure modes throw rather than misbehave:

- `manageConnection: true` while `ConnectionManager` holds the same device
  → `StateError` (would open two connections to one peripheral).
- `manageConnection: false` with no link → `StateError` (transport that
  silently cannot write).

## 6. SMP arbitration: one lock, owned by `ConnectionManager`

Sync, records and DFU all speak SMP over **one characteristic** and must never
interleave. A background sync landing mid-DFU would corrupt the image upload.
There was no gate at all (design doc §2.3 called for one).

`ConnectionManager` owns the link, so it owns the mutex:
`acquireSmp(owner) → token`, `releaseSmp(token)`, and a `runSmp` convenience.
`acquireSmp` throws `SmpBusyException` when held. Covered by
[test/smp_lock_test.dart](../test/smp_lock_test.dart) (6 tests).

Three properties that are load-bearing, each learned the hard way:

- **Token-guarded release.** `releaseSmp` ignores a token that is not the
  current one, so a late teardown from a finished flow cannot free the lock a
  *different* flow now holds.
- **Force-release on disconnect and on unexpected link drop.** Otherwise a
  dropped link wedges the lock forever and every later sync/DFU is refused.
- **Acquire *before* the `try` in `BackgroundSyncManager.syncData`.** The
  natural placement — next to the SMP session creation — is wrong: on
  `SmpBusyException` the existing `catch` calls `_safeDisconnect()`, which drops
  the shared BLE link, **killing the DFU that legitimately owns it**. And release
  happens in `finally`, because the `totalSessions == 0` early-return path skips
  `_safeDisconnect()` entirely and would strand the lock permanently.

## 7. Health Store protocol extracted to `packages/healthypi_healthy_store`

OpenView 3 and this app carried **six byte-identical copies** of the HPI_HS
protocol code with no shared source. They had not drifted yet, but nothing
prevented it: the first defensive-CBOR-parsing fix in one would not reach the
other.

Extracted `hpi_hs.dart`, `hs_type.dart`, `hs_sample.dart`, `hs_record.dart` and
`crc32.dart` into a pure-Dart package (`git mv`, so history follows). Its only
runtime dependency is `mcumgr_dart`; `dart analyze` passes under
`lints/recommended` and `dart test` runs without a Flutter SDK, which is the
mechanical proof the Flutter dependency is gone.

Deliberately excluded:

- **`hs_summary.dart` stays app-side.** `HsSummaryCard {label, value, unit}` is a
  dashboard card and its label map hardcodes UI strings (`SpO₂`, `Temp Δ`, `°C`).
  It is presentation. The raw map is already exposed by `HpiHs.summary()`.
- **`smp_ble_transport.dart` stays app-side** — it is the one BLE-coupled file
  and belongs with a future `healthypi_move` package, not a pure protocol one.
- **SMP framing, CBOR, sequence matching, OS/Image/FS groups** already live in
  `mcumgr_dart`. Not reimplemented.

`debugPrint` became an injectable `HpiHsLog` callback, matching the `log:`
parameter `mcumgr_dart`'s `SmpClient` already exposes.

## 8. `ack` renamed to `ackDurablyStored`

`HpiHs.ack(seq)` is **contractually destructive**: the device may drop every
sample at or below the acked sequence number, with no error if you never stored
them. The name implied a harmless acknowledgement.

`ackDurablyStored(seq)` is now the primary name, documented with its
precondition. `ack` remains as a `@Deprecated` alias so OpenView keeps compiling
and gets a warning pointing at the fix, rather than a hard break.

This is not hypothetical: OpenView calls `hs.ack(head)` — acking the `head`
cursor straight from `HELLO` rather than a durably-stored one — at
`device_manager_screen.dart:1273`.

**Update (firmware, 2026-07-11).** On current firmware `hpi_hs_ack()` is a
**no-op** — it does *not* free flash. Retention is **size-based only** (H4, as
designed). Two consequences, and they point in opposite directions:

- **Don't depend on `ACK` reclaiming space.** It won't. Flash is reclaimed by
  size-based retention regardless of what the app acks.
- **Keep the commit-before-ack discipline anyway.** The API contract still says
  an ack may drop data, and a future firmware could start honouring it. The
  ordering costs nothing, so `HealthStoreSyncManager` still only acks a cursor
  already committed to SQLite. Getting this wrong is unrecoverable; getting it
  needlessly right is free.

## 9. Package naming (applied)

Rename `hpi_health_store` → **`healthypi_healthy_store`** (landed in commit
`76f2caa`; the earlier draft name in this section was `healthypi_health_store`).

`mcumgr_dart` is published under the verified publisher `protocentral.com`, so
the brand is already carried by the publisher badge and a `protocentral_` prefix
would be redundant. `HPI` is internal shorthand that appears nowhere a customer
has seen; a customer searches pub.dev for "healthypi". The `healthypi_` prefix is
also the right generality — `HPI_HS` is device-family-scoped, not Move-specific.

Rejected: `protocentral_health_store` (redundant with the publisher badge),
`healthypi_move` (promises a full device SDK — reserve it, see §11),
`health_store` (unbranded, ambiguous next to HealthKit / Health Connect),
`hpi_health_store` (jargon). All were available on pub.dev.

Class names (`HpiHs`, `HsSample`, `HsType`) stay — they mirror the firmware's
`HPI_HS` contract and churning them would break OpenView for no gain.

## 10. Publishing is deferred, extraction is not

Extraction captures the entire real benefit — deduplicating OpenView and Move —
at zero contract cost. Publishing to pub.dev is a separate, deferrable decision:

- The `TYPES`, `SUMMARY` and `RECORDS` wire shapes are **not pinned** (design doc
  §10). `HsRecordHeader.fromMap` accepts *candidate* key names. Publishing freezes
  those guesses into other people's code; pinning them later is a breaking change.
- **No app has ever executed `HpiHs` in this repo.** It compiles and is dead code.
  Publishing a client your own flagship app does not run is how you ship a broken
  package.

Publish after Roadmap phases 2 and 4 exercise the sample and records tiers
against real hardware. Until then the package is a `path:` dependency; consumed
by OpenView via a `git:` dependency once pushed to its own repo.

## 11. A fuller `healthypi_move` SDK is deferred, and the ordering matters

Extraction difficulty and long-term value are **inversely correlated** here:

- Most of what is easy to extract today — the legacy trend-log protocol
  (`0x50`/`0x54`), the 16-byte trend record decode, the `/lfs/{ecg,…}` FS pulls —
  is **scheduled for deletion** by design doc §3/§4, replaced by HPI_HS `SYNC` and
  `RECORDS`. Publishing it means shipping an API you intend to delete.
- The most valuable surface — **live streaming** — has no extractable code at all.
  Byte decoding happens inline in `_onValue()` in a `StatefulWidget` state class
  (`scr_live_stream.dart:113-154`), a raw `asInt32List()` switched on a `String`,
  feeding `setState` and `fl_chart` directly. There is no sample model. BPT
  calibration (`0x60`–`0x62`) is likewise entirely inline in its widget.

So: finish the HPI_HS migration first, let the legacy code be *deleted* rather
than extracted, then package what remains — connection management, live streaming,
DFU, device info, Health Store. That surface will be roughly a third the size.

When it happens it is **one** package (`healthypi_move`), not a separate
`_ble` companion: `universal_ble` is a Flutter plugin, so any package shipping
streaming is a Flutter package. That is precisely why `healthypi_health_store`
stays separate and pure — server-side and CLI consumers never pay for a Bluetooth
stack.

## 12. Known-broken things that are *not* regressions

Verified pre-existing; do not attribute them to recent work.

- **`flutter test` fails.** `test/widget_test.dart` pumps `HealthyPiApp`; its `/`
  route is `ScrMainShell`, whose `ScrHome.initState` calls
  `HealthRepository.loadHome`, which throws a `StateError` with no DB in the test
  env. An environment/wiring failure, not a logic failure. (Before the legacy
  screens were deleted this surfaced as a `home.dart` layout overflow instead.)
  `test/smp_lock_test.dart`, `synthetic_banner_test.dart` and
  `bpt_calibrator_test.dart` pass.
- **`flutter analyze`: 445 issues, 0 errors.** All pre-existing lint
  (`avoid_print`, `withOpacity` deprecation). Use the count as a regression
  tripwire: it should not increase.
- **`android-deploy.yml` publishes to the wrong app id.** `packageName` is
  `com.protocentral.healthypi_move`; the real `applicationId` is
  `com.protocentral.move` (`android/app/build.gradle.kts`, the manifest, and the
  Play Store listing all agree). Left unfixed — it is a release-pipeline decision.
- **78 tracked files under `android/build/` and `ios/build/`** (Xcode
  `XCBuildData/PIFCache` output) are committed and should not be. They are also a
  copy hazard: a naive `--exclude build/` drops them.
- **`HealthStoreClient._probeHello()` swallows every exception identically.** A
  connection timeout and an unsupported-group `rc` both silently disable the
  Health Store, so a flaky link is indistinguishable from old firmware and the app
  quietly falls back to the legacy path forever. See Roadmap phase 6.
  *(Resolved — timeout vs refusal now distinguished; kept here for history.)*

## 13. BPT calibration: extracted behind a transport seam; HPI_HS move deferred

The BPT finger-cuff calibration logic (custom CMD GATT: set-mode `0x60`,
start-point `0x61`+`[sys,dia,index]`, end `0x62`, plus streamed `[status,
progress]` feedback) is now a transport-agnostic `BptCalibrator`
(`lib/ble/bpt_calibrator.dart`) behind a `BptCalTransport` interface, unit-tested
with a fake transport. This is the first `healthypi_move` SDK brick (Roadmap
Phase 8) and stays app-side only until the SDK package lands.

**Why not move the commands into the HPI_HS MCUmgr group (0x1000) now**, for
consistency with sync/records/summary: BPT is two things on the wire — *control*
(the three opcodes, request/response, a clean SMP fit) and *feedback* (continuous
contact-quality + progress, a server push). **SMP/mcumgr has no server push**, so
even a full move leaves the feedback on a notify characteristic or forces the app
to poll a status read during a point. So the move is a *later, firmware-coordinated*
change (new cmd ids + handlers in `hpi_hs_mgmt.c`, capability-gating old firmware),
and possibly belongs in a sibling `0x1001` device-control group rather than
overloading the health *store*. The transport seam means that move is an adapter
swap, not a rewrite of the screen or the state machine. The firmware-facing spec
for the move — proposed command set, the push constraint, capability gating — is
[FIRMWARE_HANDOFF_BPT_HS.md](FIRMWARE_HANDOFF_BPT_HS.md).
