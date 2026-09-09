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

### 1. Firmware download — the one that needs a policy decision

[`firmware_update_service.dart`](../lib/utils/firmware_update_service.dart) downloads
watch firmware images from the `Protocentral/healthypi-move-fw` GitHub releases, and
[`scr_dfu_new.dart`](../lib/screens/scr_dfu_new.dart) flashes them. Two distinct issues:

- **`healthypi-move-fw` is public but carries no licence file at all.** Unlicensed
  means all rights reserved, so as things stand the app fetches a non-free binary.
  Adding a licence to that repo is the cheap fix and is worth doing regardless.
- F-Droid's "downloads executables without opt-in consent" rule exists for apps that
  pull code they then *run on the phone*. Here the binary is flashed to a separate
  device and never executed on Android, and the download is user-initiated (Device
  tab → update). That is a good argument, but it is an argument to *make*, not to
  assume. Expect to disclose it, and possibly to carry an anti-feature label such as
  `NonFreeAssets` if the firmware stays unlicensed.

**Action:** licence the firmware repo, then raise the DFU flow explicitly in the merge
request rather than waiting for a reviewer to find it.

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
  submit a commit carrying a `dependency_overrides:` path entry (currently present on
  `feature/ultralight-support`, absent on `main`).

### 6. Signature divergence — tell users about this

F-Droid signs with its own key, so the F-Droid APK and the Play APK have **different
signatures and cannot replace each other**. A user on the Play build who wants to move
to F-Droid must uninstall first, which **wipes the local SQLite database and every
stored reading**. There is no backend, so nothing comes back.

**Action:** make sure a data export exists in the migration path, and say so plainly in
the store description and release notes. Alternatively, [reproducible builds](https://f-droid.gitlab.io/jekyll-fdroid/docs/Reproducible_Builds/)
let F-Droid ship *your* signed APK instead — more work up front, no uninstall for users.

---

## Draft fdroiddata metadata

Starting point for `metadata/com.protocentral.move.yml`, to be validated with
`fdroid lint` and `fdroid build` before opening the merge request. Not yet verified
against a real build.

```yaml
Categories:
  - Science & Education
License: MIT
AuthorName: ProtoCentral Electronics
WebSite: https://www.protocentral.com
SourceCode: https://github.com/Protocentral/healthypi_move_flutter
IssueTracker: https://github.com/Protocentral/healthypi_move_flutter/issues
Changelog: https://github.com/Protocentral/healthypi_move_flutter/blob/main/CHANGELOG.md

RepoType: git
Repo: https://github.com/Protocentral/healthypi_move_flutter.git

Builds:
  - versionName: 3.0.9
    versionCode: 97
    commit: v3.0.9
    subdir: .
    sudo:
      - apt-get update
      - apt-get install -y clang cmake ninja-build pkg-config
    srclibs:
      - flutter@3.44.0
    output: build/app/outputs/flutter-apk/app-arm64-v8a-release.apk
    prebuild:
      - rm -rf ios linux macos web windows
    build:
      - $$flutter$$/bin/flutter config --no-analytics
      - $$flutter$$/bin/flutter pub get
      - $$flutter$$/bin/flutter build apk --release --no-shrink --split-per-abi
    ndk: 28.2.13676358

AutoUpdateMode: Version
UpdateCheckMode: Tags
CurrentVersion: 3.0.9
CurrentVersionCode: 97
```

## Suggested order of work

1. Add a licence to `Protocentral/healthypi-move-fw`. Unblocks the only real question.
2. Add `OFL.txt` for the four bundled fonts.
3. Add the F-Droid build flavour that drops `upgrader`, with a local firmware-version
   gate in its place.
4. Adopt the `vX.Y.Z` tag scheme at the next release, and add a
   `fastlane/…/changelogs/<versionCode>.txt` per release from then on.
5. Add release screenshots under `fastlane/metadata/android/en-US/images/phoneScreenshots/`.
6. Fork fdroiddata, finish the YAML above, run `fdroid lint` and `fdroid build`, submit.
7. **In parallel — submit to IzzyOnDroid** (see below). It is far less work and it
   answers the actual complaint in issue #45 much sooner.

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
