# Publishing to F-Droid and other non-Google stores

Tracking issue: [#45 "F-Droid version?"](https://github.com/Protocentral/healthypi_move_flutter/issues/45),
open since 2026-06-30. This document is the working plan for answering it.

The short version: nothing here is a hard blocker. The app is MIT, has no Firebase,
no Play Services and no analytics SDK, and a Flutter app of this shape is buildable
on F-Droid's infrastructure. What stands between the current `main` and an accepted
merge request is a handful of concrete items, listed under [Gap audit](#gap-audit).

---

## What F-Droid actually requires

F-Droid is not a store you upload a binary to. **You submit source metadata; their
buildserver compiles the app from a tagged commit in this repository and signs the
result with F-Droid's key.** That single fact drives most of the requirements below.

### Licensing and dependencies

- The app must be FLOSS under an OSI/FSF-recognised licence. **MIT — satisfied.**
- No proprietary tracking, advertising or analytics. Google Play Services, Firebase
  and Crashlytics are named and forbidden. **None present — satisfied.**
- Every dependency must build from source or come from an approved source. F-Droid's
  allowlist covers Maven Central, Google Maven, JitPack, OSS Sonatype/JFrog, Clojars,
  PyPI, npm, Rust, Go and Debian main. Prebuilt binaries from anywhere else are not
  accepted.
- The whole toolchain must be FLOSS. No Oracle JDK, no proprietary build tools.

### Build

- The build runs in a clean Debian VM with no network access beyond dependency
  fetching, and must be reproducible from the tagged commit.
- Flutter is handled either as a **git submodule** (conventionally `.flutter`) or as
  an **srclib** (`flutter@stable`) — you pick one, not both. F-Droid ships a
  [Flutter build template](https://gitlab.com/fdroid/fdroiddata/-/blob/master/templates/build-flutter.yml)
  that pins the Flutter version, runs `flutter config --no-analytics`, deletes the
  non-Android platform directories, builds with `--split-per-abi`, and then deletes
  the Flutter SDK and pub-cache so the scanner does not trip over cached Dart tooling.
- `Builds:` must name an explicit `output:` path (`build/app/outputs/flutter-apk/…`)
  or the build fails.

### Metadata

- A metadata file `metadata/com.protocentral.move.yml` in a fork of
  [fdroiddata](https://gitlab.com/fdroid/fdroiddata), submitted as a merge request
  from a branch named after the app ID.
- Descriptions, icon and screenshots come from **`fastlane/metadata/android/en-US/`
  in this repository** — scaffolded on this branch, see [fastlane/](../fastlane/).
- Every release commit must carry a **tag matching the versionName**, so
  `UpdateCheckMode: Tags` can find new releases automatically.

### Grounds for rejection

Beyond licence problems: duplicate application IDs, third-party IP infringement,
undisclosed anti-features, failing to rebuild from source, and — relevant here —
**downloading executable files without explicit opt-in user consent**.

Sources: [Inclusion Policy](https://f-droid.org/docs/Inclusion_Policy/),
[Quick Start Guide](https://f-droid.org/en/docs/Submitting_to_F-Droid_Quick_Start_Guide/),
[Build Metadata Reference](https://f-droid.org/en/docs/Build_Metadata_Reference/).

---

## Gap audit

Findings against `main` at `c58ff7a` (3.0.8+96). Ordered by how much thought each needs.

### 1. Firmware download — disclosure, not a licensing fix

[`firmware_update_service.dart`](../lib/utils/firmware_update_service.dart) downloads
watch firmware images from the `Protocentral/healthypi-move-fw` GitHub releases, and
[`scr_dfu_new.dart`](../lib/screens/scr_dfu_new.dart) flashes them.

**The firmware repo's licensing is in good order** — better than this one's. It is MIT
(© 2019-2025 ProtoCentral) with a full REUSE-style breakdown: per-file
`SPDX-License-Identifier` headers, licence texts in `LICENSES/`, a component-by-component
`THIRD_PARTY.md`, and a `LICENSE.md` splitting hardware (CERN-OHL-P v2), software (MIT)
and documentation (CC BY-SA 4.0). Nothing needs adding there.

What remains is narrower and cannot be fixed by licensing, because it is upstream:

- **Four files are `LicenseRef-Nordic-5-Clause`**, which the firmware's own `LICENSE`
  correctly flags as **not OSI-approved** — redistribution is permitted only for use
  with Nordic Semiconductor devices. Three are required (`Kconfig.sysbuild`, the nPM1300
  fuel-gauge model, the ipc_radio and MCUboot configs). The fourth,
  `app/linker_arm_extxip.ld`, is marked unused and safe to delete.
- The **net-core image** the v3 DFU path uploads is the nRF5340's BLE controller, which
  comes from the nRF Connect SDK as a Nordic-licensed binary.

So the *app* is fully FLOSS, but a binary it can fetch is not. Worth stating clearly in
the merge request: the image is never executed on Android, it is flashed to separate
hardware, the download is user-initiated, and the genuinely proprietary parts of the
system — the Analog Devices MAX32664C/D `.msbl` sensor-hub images — are **not**
distributed by either repo (verified: `lib/` contains no `.msbl` handling at all).

**Action:** disclose in the merge request and accept an anti-feature label
(`NonFreeDep` or similar) if the reviewers want one. Do not wait for them to find it.

One thing that *is* worth changing:
[`firmware_update_checker.dart`](../lib/utils/firmware_update_checker.dart) polls the
GitHub releases API automatically at start and resume behind a 6-hour cache. It is a
modest, unauthenticated request and it never connects to the watch — but it is an
automatic network call the user did not ask for, which reviewers do ask about. Put it
behind a settings toggle.

### 2. `upgrader` queries the Play Store at runtime

[`lib/main.dart`](../lib/main.dart) uses `Upgrader(minAppVersion: kMinimumAppVersion)`
with `Upgrader.blocked`, which reads the **store listing** to decide whether to force
an update. On an F-Droid install this is wrong twice over: it makes a runtime request
to Google's servers, and the mandatory v3 cut-off silently stops working because
there is no Play listing behind it.

That gate is not cosmetic — per [ARCHITECTURE.md](ARCHITECTURE.md) a pre-3.0 app and a
v3 watch cannot talk to each other at all, so the block is what stops a user landing in
a broken pairing.

**Action:** compile `upgrader` out of the F-Droid build (a Dart define or a product
flavour) and replace the gate with something local — the app already learns the watch's
firmware version from `HELLO`, so it can refuse to proceed on a protocol mismatch
without asking any store anything.

### 3. Bundled fonts ship without licences

`assets/fonts/` contains JetBrainsMono, Manrope, Rubik and Saira — four TTFs, ~1.2 MB,
with **no accompanying licence file**. All four are SIL Open Font License 1.1 upstream,
which is FLOSS and fine, but OFL requires the licence text to be distributed with the
font, and F-Droid checks asset provenance.

**Action:** add each font's `OFL.txt` under `assets/fonts/` and note the origin.

### 4. Release tags are inconsistent

Current tags: `3.0.8+96`, `v3.0.5`, `v3.0.5+93`, `3.0.5+93`, `3.0.5`, `2.1.0+87`,
`2.0.0+71`, `v1.4.5+67`. Five different shapes, including the same release tagged four
ways. `UpdateCheckMode: Tags` cannot work reliably against this, and the `+buildcode`
suffix does not match `versionName`.

**Action:** settle on one scheme (`v3.0.9` is the conventional choice, with the build
number left to `pubspec.yaml`) and use it from the next release forward. Old tags can
stay; F-Droid only needs to find new ones.

### 5. Build environment details

- `ndkVersion = "28.2.13676358"` is pinned in
  [`android/app/build.gradle.kts`](../android/app/build.gradle.kts). The buildserver
  must have that exact NDK or the build fails — verify before submitting, and drop the
  pin if nothing actually requires it.
- CI uses Flutter **3.44.0**; the F-Droid metadata must pin the same version.
- `minSdk`/`targetSdk` are inherited from the Flutter toolchain rather than pinned.
  The documented Android 5.0 (API 21) floor therefore moves whenever Flutter's default
  moves. Pin them explicitly if the floor is a real commitment.
- `healthypi_healthy_store` is a **git** dependency (`ref: v0.2.0`). It is source, not
  a prebuilt, so it should be acceptable — but flag it in the merge request, and never
  submit a commit carrying a `dependency_overrides:` path entry — those exist on some
  feature branches to build against a local checkout, and would make the build
  unreproducible for anyone else.

### 6. Signature divergence — tell users about this

F-Droid signs with its own key, so the F-Droid APK and the Play APK have **different
signatures and cannot replace each other**. A user on the Play build who wants to move
to F-Droid must uninstall first, which **wipes the local SQLite database and every
stored reading**. There is no backend, so nothing comes back.

**Action:** make sure a data export exists in the migration path, and say so plainly in
the store description and release notes. Alternatively, [reproducible builds](https://f-droid.gitlab.io/jekyll-fdroid/docs/Reproducible_Builds/)
let F-Droid ship *your* signed APK instead — more work up front, no uninstall for users.

---

## fdroiddata metadata

The build recipe lives at [`docs/fdroid/com.protocentral.move.yml`](fdroid/com.protocentral.move.yml).
That file is not read from this repository — it is the working copy of what goes to
`metadata/com.protocentral.move.yml` in a fdroiddata fork — but it is versioned here so
the recipe travels with the code it builds.

**It carries no comments, deliberately.** fdroiddata's CI runs `fdroid rewritemeta` and
fails the pipeline on any diff, and rewriting strips every comment and reorders keys —
which is why the upstream template says, in capitals, to remove all comments before
submitting. The file is kept byte-identical to `fdroid rewritemeta` output; everything
that would have been a comment is in this section instead. After editing it, run:

```sh
fdroid rewritemeta com.protocentral.move   # must produce no diff
fdroid lint com.protocentral.move          # must be silent
```

### Departures from the upstream Flutter template

- The Flutter version is scraped from `.github/workflows/android-deploy.yml`, not the
  template's `release.yml`, which this repo does not have. The Android workflow's
  `flutter-version: '3.44.0'` is single-quoted, which is the form the template's regex
  expects; the iOS workflow uses double quotes, so it must not be pointed at that one.
- **No `scanignore`.** The template's `.flutter/bin/cache` entry belongs to the
  *submodule* method, where Flutter is checked out to `.flutter` inside the app. This
  recipe uses *srclibs*, so Flutter lives in `build/srclib/flutter` and is reached
  through `$$flutter$$` — that path never exists, and `fdroid` treats a `scanignore`
  glob matching nothing as a hard error, not a warning. `scandelete` keeps `.pub-cache`,
  which does exist because the build points `PUB_CACHE` into the tree so the scanner can
  see the Dart packages.
- The `/upstream/path` relocation dance is omitted. It exists to make the build path
  match upstream's for reproducible builds, which is gap 6's optional follow-up, not a
  requirement for acceptance.

### versionCodes are not ours to choose

`flutter build apk --split-per-abi` stamps each APK with `abiCode * 1000 + the pubspec
build number`, so 3.0.8+96 really produced **1096 / 2096 / 4096** — note x86_64 is 4,
not 3. F-Droid's versionCodes must match what the APK actually carries, so
`VercodeOperation` reproduces that arithmetic rather than the template's illustrative
`%c * 10 + n`, which would have published codes no APK has.

### Verification status

**`fdroid build` passes end to end**, on `fdroidserver` 2.4.5 against a real Android SDK
36 / JDK 17 / AGP 8.11.1 toolchain:

```
Successfully built version 3.0.8 of com.protocentral.move from 5e7aa72
1 build succeeded
```

It produces `unsigned/com.protocentral.move_2096.apk` — versionCode 2096 exactly as
declared, arm64-v8a, unsigned (F-Droid signs at publish), `minSdkVersion 24`,
`targetSdkVersion 36`. `flutter pub get --enforce-lockfile` passes against the committed
`pubspec.lock`. No NDK is pulled in, confirming A2's removal of the `ndkVersion` pin.

That run was on macOS, not the Debian buildserver, so it proves the **recipe** rather
than the production environment — two of the failures along the way were host quirks
rather than metadata bugs. The authoritative run is fdroiddata's own CI.

### What running it actually caught

Five errors, none visible in a file that parsed cleanly: the `VercodeOperation`
arithmetic; the `scanignore` path; a `Changelog` URL needing `/HEAD` rather than
`/main`; the comment stripping above; and a **committed upload keystore**
(`android/akw-newkey`, public for ~18 months) that F-Droid's scanner refused to build
around. The last one mattered more than the listing.

## Plan

Three phases. Phase A is self-contained repo hygiene that is worth doing whether or not
F-Droid ever happens. Phase B ships to IzzyOnDroid, which answers issue #45 in days
rather than weeks. Phase C is the F-Droid merge request.

### Phase A — repo hygiene (no release needed) — **done**

All four landed in one commit. `flutter analyze` 0 errors, `flutter test` 162 pass with
only the documented `widget_test.dart` sqflite harness failure. A2 turned up a real
discrepancy: the app had been shipping `minSdk 24` while the docs, the changelog and the
store copy all claimed API 21 — corrected rather than papered over.

**A1. Font licences — done.** Copy the pattern the firmware repo already uses. Add
`assets/fonts/OFL.txt` (SIL OFL 1.1 covers JetBrains Mono, Manrope, Rubik and Saira —
one shared text is fine, the licence requires the text travel with the fonts) and a
top-level `THIRD_PARTY.md` itemising them plus `material_symbols_icons` (Apache-2.0,
© Google). Half a day. Closes gap 3.

**A2. Pin the Android SDK floors — done.** Replace `minSdk = flutter.minSdkVersion` /
`targetSdk = flutter.targetSdkVersion` in
[`android/app/build.gradle.kts`](../android/app/build.gradle.kts) with literals — `21`
and the current target — so the documented Android 5.0 floor stops moving whenever the
Flutter toolchain's default moves. Also confirm whether `ndkVersion = "28.2.13676358"`
is actually needed; if nothing requires it, drop the pin rather than make F-Droid's
buildserver match it. An hour, plus a build to verify. Closes most of gap 5.

**A3. Make the firmware update check opt-in — done.** Add a settings toggle gating
`FirmwareUpdateChecker.refresh()` so the automatic GitHub poll only happens if the user
wants it. Manual "check now" from the Device tab stays regardless. Half a day. Closes
the loose end in gap 1.

**A4. Adopt one tag scheme — done.** `vX.Y.Z` from the next release, build number left to
`pubspec.yaml`. Both release workflows trigger on `tags: ['*']`, so **nothing in CI
breaks** — this is purely a convention change. Old tags stay; F-Droid only needs to
find new ones. Write it down in the README or a `RELEASING.md`. An hour. Closes gap 4.

### Phase B — IzzyOnDroid — **skipped**

Dropped on request: going straight to F-Droid. Kept below for the record, since it
remains the fallback if the F-Droid merge request stalls. B1's screenshots are still
needed — F-Droid reads the same `fastlane/` tree.

**B1. Screenshots.** Capture 4-6 from a release build on a real paired device, no real
personal health data, into
`fastlane/metadata/android/en-US/images/phoneScreenshots/`. This is the only piece of
fastlane metadata not already scaffolded on this branch.

**B2. Verify the release APK is acceptable.** Signed with the release key (it is, via
`KEYSTORE_BASE64` in CI), and neither `debuggable` nor `testOnly`. Confirm against the
published 3.0.8+96 artefact rather than assuming.

**B3. Submit.** Open the inclusion request with the source URL and the release APK
location. No buildserver work, and because *you* keep signing, **no signature change
and no uninstall for existing users**.

**B4. Reply to issue #45** — Obtainium works today with the existing GitHub releases,
IzzyOnDroid is in progress, F-Droid main is the longer track. That closes the loop with
the two people who asked, one of whom only wanted a non-Play install route at all.

### Phase C — F-Droid main

**C1. Decouple from the Play listing — done.** `kStoreUpdateChecks` in
[`lib/feature_flags.dart`](../lib/feature_flags.dart) is
`bool.fromEnvironment('STORE_UPDATE_CHECKS', defaultValue: true)`; the F-Droid build
sets it false. [`lib/main.dart`](../lib/main.dart) then skips *constructing* the
`Upgrader` rather than merely hiding the alert — it queries the store listing on
creation, so a hidden alert would still make the request.

**No local replacement gate was needed, contrary to the plan as first written.**
`Upgrader.blocked()` fires when the *installed* version is below
`kMinimumAppVersion`, so it only ever reached pre-3.0 binaries already in the field —
and those were installed from a store. F-Droid has never shipped this app, so no
F-Droid build can be one of them. Disabling the check costs no enforcement. Protocol
mismatch against a newer watch is separately handled by the `HELLO` probe, which
already distinguishes a verdict (`supported: false, reachable: true`) from a timeout.

Covered by [`test/store_update_checks_test.dart`](../test/store_update_checks_test.dart),
which fails if `upgrader` is imported anywhere but `main.dart` or if the construction
stops being conditional — a second call site would otherwise reach a store from a build
that has none, silently. Closes gap 2.

**C2. Prove the build — local build proven; `fdroid build` still to run.** Fork [fdroiddata](https://gitlab.com/fdroid/fdroiddata),
finish the YAML above against a real `vX.Y.Z` tag, run `fdroid lint` and `fdroid build`
locally or via their GitLab CI. Expect iteration here — the Flutter SDK pin, the NDK,
and the `healthypi_healthy_store` git dependency are each a plausible first failure.

**C3. Submit the merge request**, disclosing the DFU flow up front per gap 1.

**C4. Document the migration.** Whichever way it lands, F-Droid signs with its own key,
so switching from the Play build means uninstall — and with no backend, that **wipes
every stored reading**. Make sure CSV export is reachable and say so in the release
notes and store description. Revisit
[reproducible builds](https://f-droid.gitlab.io/jekyll-fdroid/docs/Reproducible_Builds/)
later if the uninstall proves to be a real obstacle; it lets F-Droid ship your signed
APK instead. Closes gap 6.

### What is not on the critical path

Gap 1 needs no licensing work — the firmware repo is already in order. Phases A and B
together are roughly a week and require no architectural change; C1 is the only item
that touches app logic.

---

## Other non-Google distribution

Ranked by effort-to-value for this app.

### IzzyOnDroid — do this first

A third-party F-Droid-compatible repository that accepts **prebuilt APKs from GitHub
releases**. It does not rebuild from source, so there is no buildserver work at all,
and because you keep signing the APK there is **no signature change and no uninstall**
for existing users.

Requirements: FLOSS licence, publicly accessible source, no proprietary components,
APK signed with a release key and not marked debuggable or testOnly, and fastlane
metadata — the same `fastlane/metadata/android/en-US/` tree scaffolded here. This repo
already meets nearly all of it.

Realistically this is a few days of work versus weeks for F-Droid main, and IzzyOnDroid
is a common stepping stone: get listed there, then pursue F-Droid main.
[Inclusion policy](https://izzyondroid.org/docs/general/AppInclusionPolicy/) ·
[Get started](https://izzyondroid.org/quickstart/)

### Obtainium — nothing to do

Installs and updates apps directly from GitHub releases. It needs no submission and no
cooperation: it already works today, since 3.0.8+96 APKs are published. Worth naming in
the README and in the reply to issue #45 as the zero-effort answer for the users asking.

### Accrescent

A security-focused store built around signing-key pinning, signed repo metadata and
unattended updates. Still alpha as of 2026 and deliberately small. Its requirements are
stricter than F-Droid's in some respects (app bundles, modern target SDK). Reasonable to
revisit once F-Droid or IzzyOnDroid is done; not a starting point.

### Amazon Appstore / Samsung Galaxy Store / Huawei AppGallery

Commercial, non-Google, and each wants its own developer account, review process and
release pipeline. Samsung is the interesting one for a wearable-adjacent product given
its device base. All three are business decisions rather than open-source ones, and none
of them address what issue #45 is asking for.

### Aurora Store, APKPure, APKMirror — not distribution

Aurora is an alternative *client* for Google Play, not a separate store; the reporter in
issue #45 hit exactly this when it demanded a Play login. APKPure and APKMirror are
mirrors that republish APKs without the publisher's involvement, which is why they lag.
Listing on any of these is not something to pursue — they are symptoms of the gap, not
solutions to it.
