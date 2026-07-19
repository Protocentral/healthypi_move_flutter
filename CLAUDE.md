# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Start here

This is **`healthypi_move_flutter_next`**, the redesign fork of `healthypi_move_flutter`. Work happens here and is copied back when done. `origin` is the private staging repo `Protocentral/healthypi_move_flutter_next` (push here — `git push origin main`); `upstream` points at the production repo (never push there).

Read these before making decisions, in this order:

- **[docs/SESSION_HANDOFF.md](docs/SESSION_HANDOFF.md)** — *start here to resume.* The current tree state, live baselines, what was just done, and the recommended next step. The short-lived "where were we" note.
- **[docs/ROADMAP.md](docs/ROADMAP.md)** — the sequenced work (phases 0–8) with per-item status and what remains.
- **[docs/DECISIONS.md](docs/DECISIONS.md)** — what was decided and *why*, including several non-obvious traps and a list of known-broken things that are **not** regressions.

All three are tracked (this `CLAUDE.md` too, so it travels between machines) — put lasting decisions in DECISIONS, sequenced work in ROADMAP, resume-state in SESSION_HANDOFF, and durable repo guidance here.

Two rules that override convenience:

1. **Migrate per *flow*, not per *file*.** Each BLE plugin holds its own OS-level connection, so a screen that *uses* a link can't move while the screen that *establishes* it hasn't.
2. **`HpiHs.ackDurablyStored()` and `recordsAck()` are destructive.** The device drops the acked data. Commit to SQLite and persist the cursor first — never ack `hello.head`, never ack an unpersisted `syncAll()` cursor.

Before claiming you broke something, check DECISIONS §12: `flutter test` already fails (the `widget_test.dart` smoke test pumps the app and hits a `StateError` in `HealthRepository.loadHome` with no DB in the test env — the shell is the `/` entry), and `flutter analyze` reports pre-existing lint with 0 errors. The count is a tripwire — it should **not increase**. It is currently **121** (was 182 before the device-flow redesign — 5a DFU / 5b BPT-cal / 5c device-scan — moved the last 3 screens off `hpi_legacy_theme`; 434 before the legacy-screen deletion; 445 before that). See the ROADMAP header for the full baseline tripwires.

## Repository layout

A standard Flutter app at the repository root. (It used to live in a `move/` subdirectory; that was flattened, so ignore any lingering `move/`-prefixed paths in older docs.)

The SMP/MCUmgr core is the published [`mcumgr_dart`](https://pub.dev/packages/mcumgr_dart) package from pub.dev (source: `Protocentral/mcumgr_dart`). It used to be a git submodule under `packages/`; it is now an ordinary hosted dependency, so no submodule init is needed. Its own test suite lives in that repo, not here.

## Commands

```bash
flutter pub get
flutter run                       # attach a real device; the app is useless in a simulator (needs BLE)
flutter analyze                   # ~121 pre-existing lint infos/warnings, 0 errors
flutter test                      # see caveat below
flutter build bundle              # quickest full-app Dart compile, no platform SDK needed

# Codegen (manifest.g.dart via json_serializable)
dart run build_runner build --delete-conflicting-outputs
```

Release builds mirror CI ([.github/workflows/](.github/workflows/), Flutter 3.35.4):

```bash
flutter build appbundle --release --no-shrink   # Android → Play internal track
flutter build apk --release --no-shrink
flutter build ipa --release --export-method app-store
```

**`flutter test` currently fails**, and did before any recent changes: the single smoke test in [test/widget_test.dart](test/widget_test.dart) pumps `HealthyPiApp`, whose `/` route is the redesigned `ScrMainShell`; `ScrHome.initState` calls `HealthRepository.loadHome`, which throws a `StateError` with no database in the test env. It is an environment/wiring failure, not a logic failure in your change. (Before the legacy screens were deleted this surfaced instead as a `home.dart` layout overflow — same "smoke test is red for a pre-existing reason" caveat.) Don't treat a red `flutter test` as evidence your change broke something — confirm against `git stash` first.

Version/build number live in [pubspec.yaml](pubspec.yaml) (`version: 2.1.0+87`). App id is `com.protocentral.move`. iOS deployment target is pinned to 13.1 and Android `minSdk` 21 — both are `universal_ble` requirements; don't lower them.

## Architecture

A companion app for the HealthyPi Move wearable. Everything of consequence is BLE plumbing plus a local SQLite store; there is no backend.

### The BLE stack (read [docs/HEALTH_STORE_SYNC_DESIGN.md](docs/HEALTH_STORE_SYNC_DESIGN.md) before touching any of this)

The app recently migrated off `flutter_blue_plus` + `mcumgr_flutter` onto a single BSD-licensed plugin (`universal_ble`) and a single SMP client. That migration is the dominant fact about this codebase. Layers, bottom-up:

- **[lib/utils/ble_manager.dart](lib/utils/ble_manager.dart)** — the facade over `universal_ble`. Almost the only file that imports the plugin (exceptions: `smp_ble_transport.dart`, self-contained; and `scr_device_scan.dart`, which predates the facade). New code goes through the facade.
- **[lib/utils/connection_manager.dart](lib/utils/connection_manager.dart)** — a `ChangeNotifier` singleton that owns *the* live connection to the paired device. Screens acquire/release it; they must never call `BleManager.connect` themselves. This exists specifically to kill the per-screen connect/disconnect races that plagued the old code.
- **[lib/smp/smp_ble_transport.dart](lib/smp/smp_ble_transport.dart)** — SMP framing over the Nordic SMP GATT characteristic. The only BLE-coupled piece of the SMP stack.
- **`package:mcumgr_dart`** — pure-Dart `SmpClient` + the stock `OsMgmt`/`ImgMgmt`/`FsMgmt` groups. Transport-agnostic; also used by ProtoCentral's OpenView 3.
- **`package:healthypi_healthy_store`** ([packages/healthypi_healthy_store/](packages/healthypi_healthy_store/)) — the ProtoCentral **Healthy Store**, a vendor MCUmgr group (`0x1000`) with `HELLO`/`TYPES`/`SYNC`/`SUMMARY`/`RECORDS`/`ACK`, plus the `Hs*` wire models and `Crc32`. Pure Dart, path dep for now, shared with OpenView 3. `mcumgr_flutter` was rejected because it has no generic custom-group API and can't speak `0x1000`.
- **[lib/utils/healthy_store_client.dart](lib/utils/healthy_store_client.dart)** (`HealthyStoreClient`) — one SMP session bundling the group facades; `HELLO` doubles as the capability probe.

Protocol code belongs in `packages/healthypi_healthy_store` (pure Dart, no Flutter, own `dart test` suite); presentation stays in the app. `HsSummary` (the typed SUMMARY decoder) now lives **in the package** — it grew protocol semantics (the `stress_hrv_v` rule, fixed-point scales) and its keys are pinned to firmware; the app-side card prettifier it replaced was dead code and was deleted. `HpiHs.ackDurablyStored(seq)` and `recordsAck(id)` are **destructive**: the device drops the acked data. Ack only what you have already committed to SQLite — never `hello.head`, never an unpersisted `syncAll()` cursor. (`HpiHs.ack` is the deprecated alias for the same thing.)

### Two connection paths, one radio

There is **one physical BLE link** but two logical modes, and they must never overlap on the wire:

1. **Streaming** — live ECG/PPG/HR/SpO₂/temp over the custom GATT characteristics, via `ConnectionManager`.
2. **SMP** — health sync, DFU, filesystem pulls, over the SMP characteristic.

`ConnectionManager` owns the link. An SMP session rides it via `SmpBleTransport(id, manageConnection: false)` — otherwise its `disconnect()` tears down the shared connection. `manageConnection: true` is only for a standalone session on a device the `ConnectionManager` is *not* connected to; `HealthyStoreClient` asserts both directions of this.

**Every SMP flow must bracket its session with `ConnectionManager.acquireSmp(owner)` / `releaseSmp(token)`** (or `runSmp`). Sync, records, and DFU share one characteristic; a background sync landing mid-DFU would interleave frames and corrupt the image upload. `acquireSmp` throws `SmpBusyException` when the wire is held. Two rules the existing call sites encode: release in a `finally` (early-return paths otherwise strand the lock forever), and never run a teardown that drops the shared link when you failed to get the lock — you'd disconnect the flow that legitimately owns it. The lock is force-released on disconnect and on an unexpected link drop. Covered by [test/smp_lock_test.dart](test/smp_lock_test.dart).

### Migration state (in flux)

**The Healthy Store path is the only sync path.** `HealthyStoreSyncManager` drives cursor-based `SYNC` into `hs_samples`, derives `health_trends`, fetches/caches `SUMMARY`, and `HealthyStoreRecordsManager` does `RECORDS` list/download/CRC/ack. The legacy custom `0x50`/`0x54` + `/lfs/tr*` path (`background_sync_manager.dart`) has been **removed**. Device RTC is stamped via `DeviceTimeService` on every sync connect. The `hs_*` tables exist (schema v7). **What is NOT done: full device validation on a production fleet** — see ROADMAP.

**When migrating a flow, migrate the whole flow at once.** A screen that *uses* a connection cannot be migrated while the screen that *establishes* it is on a different plugin — each plugin holds its own OS-level connection, so the migrated screen sees no link at runtime. The flows are: scan/pair, streaming, sync, DFU, records.

### Data layer

[lib/utils/database_helper.dart](lib/utils/database_helper.dart) — sqflite, schema **version 5**, tables `health_trends` (hourly/daily aggregates the trend UI reads), `synced_sessions` (dedup), `research_sessions`/`research_files`, `app_metadata`. Bump the version and extend `_onUpgrade` additively; the design doc's plan treats `health_trends` as a *derived* cache once raw `hs_samples` land.

[lib/data/health_repository.dart](lib/data/health_repository.dart) is the read path the redesigned trend screens use, so `health_trends` is the seam that keeps the UI stable across the sync rewrite. (The old `trends_data_manager.dart` was deleted with the legacy screens.)

### Everything else

- [lib/globals.dart](lib/globals.dart) — all GATT UUIDs, legacy command opcodes, research-recording constants, and the app's `TextStyle`s, in one `hPi4Global` class.
- [lib/utils/device_manager.dart](lib/utils/device_manager.dart) — paired-device persistence in `SharedPreferences`, with migration from a legacy MAC-in-a-file format. **`deviceId` (a String — CoreBluetooth UUID on Apple, MAC on Android) is the canonical device handle everywhere.** Never pass plugin device objects between screens.
- [lib/utils/firmware_update_service.dart](lib/utils/firmware_update_service.dart) — pulls releases from the `Protocentral/healthypi-move-fw` GitHub repo; DFU itself runs through `ImgMgmt` in [lib/screens/scr_dfu_new.dart](lib/screens/scr_dfu_new.dart).
- Routing is a flat `routes` map in [lib/main.dart](lib/main.dart); screens are `lib/screens/scr_*.dart`.

## Hardware gotchas that are easy to reintroduce

- **Call `discoverServices` after connect, always.** CoreBluetooth and Android GATT only expose characteristics afterwards; skip it and `connect()` succeeds while every notify/write silently fails.
- **The ATT MTU settles *after* connect on iOS/macOS.** Read immediately, you get the 23-byte default (`maxWriteLength` 20) and every DFU/record transfer breaks. Poll `refreshMtu()` for a few seconds — see `HealthyStoreClient._settleMtu`. It settles 20 → 244 B on a real Move; if it stays at 20 that's a firmware cap.
- **On iOS, a stored `deviceId` must be rediscovered by a scan before `connect()` resolves it.** That's what `BleManager.connectResolved` is for; use it, not `connect`.
- **Subscribe to `connectionStream` only after a successful connect**, or macOS replays a `disconnected` event at you.
- **Parse device CBOR defensively.** The firmware's `TYPES`/`SUMMARY`/`RECORDS` wire shapes are not fully pinned (design doc §10); a field that "should" be an int has shown up as something else. Tolerate and skip, don't throw.
