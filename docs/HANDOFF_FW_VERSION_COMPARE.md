# App Handoff — Firmware update check falsely reports "update available" for `3.0.x+0`

**Status:** Bug, app-side. Firmware is correct; nothing to change on the device.
**Symptom:** After a successful update to a release (2.2.0 → 3.0.1, and again → 3.0.2), the
Firmware Update screen keeps saying an update is available and re-running it **fails**.
**Reported by:** end user, updating 2.2.0 → 3.0.1, then re-tested on 3.0.2.
**Affected build:** current `main` (`5b25e67`).

---

## TL;DR

`FirmwareUpdateService.isUpdateAvailable()` does not strip MCUboot build metadata
(`+0`) before comparing versions. The watch reports its firmware over BLE DIS as
`"3.0.2+0"`; GitHub's release version is `"3.0.2"`. The naive parser turns the
device's patch component `"2+0"` into `0`, so the device looks like `3.0.0`, and
`3.0.2 > 3.0.0` ⇒ "update available" — **forever**, on every equal-version release.

The re-flash then fails because MCUboot refuses to install an image whose version
is **not strictly higher** than what is already running.

The app **already has a correct version parser** (`FirmwareVersion` in
`lib/ble/device_generation.dart`) that strips `+`/`-` suffixes and is used by the
other comparison path (`evaluateFirmwareState`). The fix is to route
`isUpdateAvailable` through it. One function, self-contained.

---

## Root cause

`lib/utils/firmware_update_service.dart:105` — `isUpdateAvailable()`:

```dart
final currentParts = currentClean.split('.').map((p) {
  try { return int.parse(p); } catch (e) { return 0; }   // <-- "2+0" -> exception -> 0
}).toList();
```

Trace with the real inputs — device `"3.0.2+0"`, release `"3.0.2"`:

| step | current (`3.0.2+0`) | latest (`3.0.2`) |
|------|---------------------|------------------|
| `split('.')` | `["3", "0", "2+0"]` | `["3", "0", "2"]` |
| `int.parse` each | `3, 0, ` **`parse("2+0")` throws → `0`** | `3, 0, 2` |
| parts | `[3, 0, 0]` | `[3, 0, 2]` |
| compare @ i=2 | `latest 2 > current 0` → **returns `true`** | |

So the device is misread as `3.0.0`, and every `3.0.x` release looks newer. The
`+0` is **MCUboot's image-header build number** (a fixed 4-tuple
`major.minor.revision.build_num`, `build_num` defaults to `0`), surfaced verbatim
in the DIS firmware-revision string. It is present on **every** release
(`2.2.0+0`, `3.0.1+0`, `3.0.2+0` …) — see `lib/ble/device_generation.dart:75-78`,
which already documents this exact wire format.

### Why the re-flash fails (the second half of the symptom)

When the user taps update again, the app re-sends the same `3.0.2` image. MCUboot
compares image versions and **rejects an equal-or-lower version** — an install of
`3.0.2` over a running `3.0.2` is not "strictly higher", so it aborts. The user
sees the update fail. This is correct device behaviour; the app should never have
offered the update.

### Why only *this* code path is affected

There are **two** version comparators in the app:

| Path | Location | Correct? |
|------|----------|----------|
| `evaluateFirmwareState()` | `lib/ble/firmware_compatibility.dart:79` | ✅ uses `FirmwareVersion.tryParse` — strips `+0` |
| `isUpdateAvailable()` | `lib/utils/firmware_update_service.dart:105` | ❌ naive `split('.')` + `int.parse` |

The DFU screen gates the actual update button on the **buggy** one
(`lib/screens/scr_dfu_new.dart:221`), which is why the bug is user-visible.

---

## The fix

Delegate to the existing, correct `FirmwareVersion`. Drop-in replacement for the
whole method body:

```dart
// add near the other imports at the top of firmware_update_service.dart:
import '../ble/device_generation.dart';   // FirmwareVersion
```

```dart
/// Check if [latestVersion] is strictly newer than [currentVersion].
///
/// Both strings are parsed with [FirmwareVersion], which strips MCUboot build
/// metadata and pre-release suffixes (`"3.0.2+0"`, `"v3.0.2"`, `"3.0.2-rc1"` all
/// compare as `3.0.2`). The `+0` is the MCUboot image build number and is
/// present on every device's DIS string — comparing it literally makes every
/// equal-version release look like an upgrade. See the note in
/// device_generation.dart on the `3.0.2+0` wire format.
static bool isUpdateAvailable(String currentVersion, String latestVersion) {
  final current = FirmwareVersion.tryParse(currentVersion);
  final latest = FirmwareVersion.tryParse(latestVersion);

  // Unparseable input tells us nothing — do not nag on nothing.
  if (current == null || latest == null) {
    print('[FirmwareUpdateService] Unparseable version '
        '(current: "$currentVersion", latest: "$latestVersion") — treating as up to date');
    return false;
  }

  final available = latest > current;   // strictly newer only; equal ⇒ false
  print('[FirmwareUpdateService] $current vs $latest -> '
      '${available ? "update available" : "up to date"}');
  return available;
}
```

`FirmwareVersion` already defines `>`, `<`, `>=`, `==`, and `compareTo`
(`lib/ble/device_generation.dart:114-126`), so no new comparison logic is needed.
This also makes `isUpdateAvailable` and `evaluateFirmwareState` agree, which they
currently don't.

> Note: `FirmwareVersion` currently exposes `<`, `>=`, but not a `>` operator.
> Either add `bool operator >(FirmwareVersion o) => compareTo(o) > 0;` next to the
> others in `device_generation.dart`, or write the comparison as
> `latest.compareTo(current) > 0`. Prefer adding the operator — it reads better and
> `<`/`>=` are already there asymmetrically.

---

## Test cases

Add to the version-comparison tests (there is existing coverage for
`FirmwareVersion` / `evaluateFirmwareState`; mirror it for `isUpdateAvailable`):

| current (device) | latest (release) | expected `isUpdateAvailable` | why |
|------------------|------------------|------------------------------|-----|
| `3.0.2+0` | `3.0.2` | **false** | the reported bug — equal after stripping `+0` |
| `3.0.1+0` | `3.0.2` | true | real upgrade |
| `3.0.2+0` | `3.0.1` | false | device ahead of release (dev build) |
| `2.2.0+0` | `3.0.1` | true | the original 2.2.0→3.0.1 upgrade still works |
| `v3.0.2` | `3.0.2` | false | `v` prefix tolerated |
| `3.0.2-rc1` | `3.0.2` | false | pre-release suffix stripped |
| `Unknown` | `3.0.2` | false | unparseable ⇒ no nag |

---

## Scope / non-goals

- **Firmware needs no change.** `3.0.2` is a clean, strictly-higher release; the
  `+0` is normal MCUboot metadata, not a firmware defect. (The earlier
  duplicate/renamed `3.0.1` tag was a separate, already-resolved packaging issue —
  the `3.0.2` bump fixed the device/manifest collision. This handoff is only about
  the app misreading the version string.)
- Don't try to strip `+0` at the display layer or in the DIS read — fix it at the
  one comparison that's wrong. The parser that already handles it is the pattern to
  follow.
- After the fix, verify on a device running `3.0.2`: the Firmware Update screen
  should show **up to date**, and no update should be offered until a `3.0.3`+
  release is published.

## Files

- `lib/utils/firmware_update_service.dart` — **fix here** (`isUpdateAvailable`, line 105)
- `lib/ble/device_generation.dart` — `FirmwareVersion` (reuse; maybe add `operator >`)
- `lib/ble/firmware_compatibility.dart` — the already-correct sibling path, for reference
- `lib/screens/scr_dfu_new.dart:221` — the caller that gates the update button
