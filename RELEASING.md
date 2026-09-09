# Releasing

## Version and tag scheme

The version lives in one place — `version:` in [`pubspec.yaml`](pubspec.yaml), as
`X.Y.Z+BUILD`. `X.Y.Z` is the versionName users see; `BUILD` is the Android
versionCode and iOS build number, and must increase on every submitted build.

**Tags are `vX.Y.Z`.** The build number is deliberately *not* in the tag — it lives in
`pubspec.yaml`, and putting it in both is how the history ended up with the same release
tagged four different ways (`3.0.5`, `v3.0.5`, `3.0.5+93`, `v3.0.5+93`).

```
version: 3.0.9+97   in pubspec.yaml   →   tag v3.0.9
```

Tags before 3.0.8 do not follow this and are left alone.

### Why it has to be consistent

Both release workflows trigger on `tags: ['*']` and use `github.ref_name` verbatim as
the GitHub Release name, so **CI accepts any tag shape** — nothing there forces the
issue. What does is F-Droid: its `UpdateCheckMode: Tags` finds new releases by matching
tags against the versionName, and cannot do that reliably against five different
shapes. See [docs/FDROID_RELEASE.md](docs/FDROID_RELEASE.md).

## Cutting a release

1. Bump `version:` in `pubspec.yaml` — both parts.
2. Add release notes to [`CHANGELOG.md`](CHANGELOG.md).
3. Add `fastlane/metadata/android/en-US/changelogs/<versionCode>.txt` — the build
   number, so `3.0.9+97` is `97.txt`. This is what F-Droid and IzzyOnDroid show as the
   "what's new" text; without it a release shows none. Keep it short and user-facing.
4. Commit, then tag `vX.Y.Z` and push the tag. CI builds the AAB and APK, uploads to
   Play and App Store Connect, and attaches the artefacts to a GitHub Release.
5. Verify the GitHub Release has the APKs attached — they are the download path for
   users not on Play, and the source IzzyOnDroid pulls from.

## Minimum supported app version

`kMinimumAppVersion` in [`lib/main.dart`](lib/main.dart) is enforced through the
**store listing**, not the binary: `upgrader` reads the `[:mav: X.Y.Z]` tag from the
Play/App Store description. If you raise it, update the store listings in the same
release or the block will not fire.

This mechanism does not work for installs from outside those stores — see
`docs/FDROID_RELEASE.md`, gap 2.

## Signing

**No signing material lives in this repository.** CI signs from the
`KEYSTORE_BASE64` secret; for a local release build, put the upload keystore
somewhere outside the working tree and point `android/key.properties` at it —
that file is gitignored, along with `*.jks`, `*.keystore` and `keystore.base64`.

The upload keystore itself is kept in the product management folder, not here.
Ask if you need it.

> The upload key was committed to this public repo as `android/akw-newkey` from
> March 2025 until it was removed in September 2026, so **it must be treated as
> public and reset**. Google's App Signing holds the real app signing key, so an
> upload key is resettable from the Play Console without affecting installed
> users — but until it is reset, anyone who cloned the repo has it. Deleting the
> file does not remove it from git history.

## Platform floors

- Android `minSdk 24` — pinned in [`android/app/build.gradle.kts`](android/app/build.gradle.kts).
  Flutter no longer supports API < 24.
- iOS deployment target 13.1, macOS 10.15 — `universal_ble` requirements.

Changing any of these changes who can install the app; say so in the release notes.
