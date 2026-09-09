// Copyright (c) 2024-2026 ProtoCentral
// SPDX-License-Identifier: MIT

/// Build-time feature gates for work that is complete on the app side but
/// waiting on something outside it.
///
/// Flags here are `const`, so a disabled feature is tree-shaken out of release
/// builds rather than merely hidden. Keep them few and short-lived: a flag that
/// outlives its reason becomes a second, undocumented product.
library;

/// Native **HRV R-R interval records** (HPI_HS `RECORDS` signal `0x05`).
///
/// Off because **the firmware does not emit these yet**. The app side is
/// finished and tested — listing, download, CRC, the uint16-ms decode, the
/// tachogram, the per-beat CSV, and the interval-series handling that stops an
/// R-R record being mistaken for a fixed-rate waveform. None of it can be
/// exercised until a watch produces signal `0x05`, and shipping a filter chip
/// that is permanently empty invites a bug report rather than a feature.
///
/// **This does not gate ECG-derived HRV.** The spot-check that detects R peaks
/// in an ECG recording and reports RMSSD/SDNN/pNN50 runs on records the firmware
/// already produces, is live, and is the half of the feature that works today.
/// It is also the reference the native path will eventually be validated
/// against, so it must stay reachable.
///
/// To re-enable when firmware lands: flip this to `true`, then confirm against a
/// real recording that the header's `sampleFormat` is `2` (uint16) and that
/// `nSamples` counts intervals rather than bytes — the decode and every duration
/// shown in the UI depend on both. See `HsRecording.isIntervalSeries`.
const bool kHrvRecordsEnabled = false;

/// Whether the app may ask an **app store** how up to date it is.
///
/// On by default — that is the Play/App Store build. Set false for a build
/// distributed anywhere that has no such listing behind it:
///
/// ```sh
/// flutter build apk --release --dart-define=STORE_UPDATE_CHECKS=false
/// ```
///
/// `upgrader` reads the store's listing to learn the latest version and the
/// `[:mav:]` minimum-version tag. Off a store there is no listing to read, so
/// the check is a network request to Google or Apple that can only ever fail —
/// and on F-Droid, keeping the app current is the store client's job anyway.
/// See [kMinimumAppVersion] and docs/FDROID_RELEASE.md.
///
/// Turning this off costs no enforcement. `Upgrader.blocked()` fires when the
/// *installed* version is below [kMinimumAppVersion], so it only ever reached
/// pre-3.0 binaries already in the field — which by definition were installed
/// from a store, never from F-Droid. A build with this flag off cannot be one
/// of them.
///
/// This gates the runtime call, not the dependency: `upgrader` is still linked
/// in. Removing the package outright would need a separate pubspec, which is
/// not worth a second dependency tree to maintain.
const bool kStoreUpdateChecks =
    bool.fromEnvironment('STORE_UPDATE_CHECKS', defaultValue: true);
