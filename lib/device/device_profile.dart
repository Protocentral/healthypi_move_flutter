// Copyright (c) 2024-2026 ProtoCentral
// SPDX-License-Identifier: MIT

/// Which HealthyPi product is paired, and what that product can physically do.
///
/// This file imports no Flutter library and reaches no I/O — same discipline as
/// [hPi4Global] in `lib/globals.dart`, and for the same reason: deciding whether
/// a device has a blood-pressure sensor should not drag in `material.dart`, and
/// it must be unit-testable with no radio.
///
/// ## What belongs here, and what does not
///
/// A [DeviceProfile] carries **product facts** — the things no wire response can
/// tell us. It is deliberately *not* a capability cache. Three other sources
/// answer three other questions, and conflating them is the mistake this seam
/// exists to prevent:
///
/// | Question | Answered by |
/// |---|---|
/// | What does a metric id *mean*? | the `TYPES` registry, read from the device |
/// | Can this product *measure* it? | **here** |
/// | Does `RECORDS`/`SUMMARY` work right now? | `DeviceCapabilities` (`ENOTSUP`) |
///
/// **`TYPES` is not a capability list.** The Ultralight registry is at Move NEXT
/// parity *on purpose* — its `hpi_hs_types.h` is a frozen contract that
/// advertises `bp_sys`, `bp_dia`, `eda_scl` and every other id on hardware with
/// no producer for any of them, so that one client can read both products. Read
/// the registry for a type's unit, scale and class; never for whether the band
/// in the user's hand has electrodes.
library;

import '../globals.dart';

/// The products this app serves.
enum DeviceModel {
  /// HealthyPi Move — the screened watch. nRF5340, MAX30001 (ECG/BioZ),
  /// MAX32664C/D (wrist + finger PPG), BPT calibration.
  moveNext,

  /// HealthyPi Move Ultralight — the screenless band. STM32U595 + nRF54L15,
  /// AS7058 wrist PPG, BMI323 IMU, AS6221 temp. No ECG electrodes, no finger
  /// sensor, no blood pressure.
  moveUltralight,

  /// A device whose `HELLO.dev` string this build does not recognise.
  ///
  /// Treated conservatively — see [DeviceProfile.unknown]. It still syncs, and
  /// syncs *correctly*, because the sample stream and the type registry are
  /// self-describing. It just gets no product-specific surface.
  unknown,
}

/// Extra Home/Trends row keys that are not `hPi4Global.PREFIX_*` metrics.
///
/// Blood pressure is a screen rather than a single metric — two correlated
/// types (`bp_sys`/`bp_dia`) plus a calibration flow — so it is addressed by its
/// own row key.
const String kSignalBloodPressure = 'bp';

/// EDA / GSR. `hPi4Global` has `PREFIX_STRESS_EDA` for the *derived* spot-check
/// score; this key is the raw electrodermal row on Home.
const String kSignalEda = 'eda';

/// What a paired product is, and what it can physically measure.
class DeviceProfile {
  const DeviceProfile({
    required this.model,
    required this.productName,
    required this.deviceNoun,
    required this.hasBloodPressure,
    required this.hasEcg,
    required this.hasGsrEda,
    required this.hasFingerSensor,
    required this.homeSignals,
    required this.gridSignals,
  });

  final DeviceModel model;

  /// Full product name, for the Home footer, the Device hero, and scan rows.
  final String productName;

  /// The word for this device in a sentence: `watch` or `band`.
  ///
  /// Interpolated into shared copy so the app does not tell an Ultralight owner
  /// to "measure on watch" — an instruction they cannot follow on a device with
  /// no screen and no buttons. See docs/internal/ULTRALIGHT_SHARED_APP_UX.md §5.
  final String deviceNoun;

  /// Finger-PPG blood-pressure estimation and its 3-point calibration
  /// (HPI_HS cmds 8–11).
  ///
  /// When false the BP row, the `/blood-pressure` route and `ScrBptCalibration`
  /// are **absent**, not disabled. BP is the app's one regulated surface — an
  /// estimated range on a continuous gradient, never clinical categories — and a
  /// permanently dim BP affordance on hardware with no BP sensor implies a
  /// measurement that cannot be made.
  final bool hasBloodPressure;

  /// ECG electrodes (MAX30001). Gates the ECG live signal, ECG spot checks, and
  /// the ECG-derived HRV analysis.
  final bool hasEcg;

  /// GSR / electrodermal electrodes. Gates the EDA row and the 30-second EDA
  /// spot check — *not* the HRV-derived continuous stress score, which needs
  /// only PPG and exists on both products.
  final bool hasGsrEda;

  /// A finger-contact sensor (MAX32664D) for guided spot checks.
  final bool hasFingerSensor;

  /// Home's signal rows, in display order.
  ///
  /// Composing the row set here is what keeps `if (isUltralight)` out of the
  /// row builders: a metric this product cannot measure is not a dim row, it is
  /// not a row. [MetricAvailability] keeps its existing meaning for the rows
  /// that do exist.
  final List<String> homeSignals;

  /// Home's 2×2 grid tiles, in display order. A subset of [homeSignals]:
  /// the grid has no room for rows that need a supporting sentence.
  final List<String> gridSignals;

  /// True when the product has any live-streaming surface at all.
  bool get hasLiveStream => model != DeviceModel.unknown;

  // --- The profiles -------------------------------------------------------

  static const DeviceProfile moveNext = DeviceProfile(
    model: DeviceModel.moveNext,
    productName: 'HealthyPi Move',
    deviceNoun: 'watch',
    hasBloodPressure: true,
    hasEcg: true,
    hasGsrEda: true,
    hasFingerSensor: true,
    homeSignals: [
      hPi4Global.PREFIX_ACTIVITY,
      hPi4Global.PREFIX_SPO2,
      hPi4Global.PREFIX_TEMP,
      hPi4Global.PREFIX_STRESS,
      kSignalEda,
      kSignalBloodPressure,
    ],
    gridSignals: [
      hPi4Global.PREFIX_ACTIVITY,
      hPi4Global.PREFIX_SPO2,
      hPi4Global.PREFIX_TEMP,
      hPi4Global.PREFIX_STRESS,
    ],
  );

  /// The screenless band.
  ///
  /// No BP, no ECG, no GSR — the Nerve board carries an AS7058 PPG AFE, a
  /// BMI323 IMU and an AS6221 temperature sensor, and nothing else reaches skin
  /// through an electrode. Stress stays: it is HRV-derived from wrist PPG.
  static const DeviceProfile moveUltralight = DeviceProfile(
    model: DeviceModel.moveUltralight,
    productName: 'HealthyPi Move Ultralight',
    deviceNoun: 'band',
    hasBloodPressure: false,
    hasEcg: false,
    hasGsrEda: false,
    hasFingerSensor: false,
    homeSignals: [
      hPi4Global.PREFIX_ACTIVITY,
      hPi4Global.PREFIX_SPO2,
      hPi4Global.PREFIX_TEMP,
      hPi4Global.PREFIX_STRESS,
    ],
    gridSignals: [
      hPi4Global.PREFIX_ACTIVITY,
      hPi4Global.PREFIX_SPO2,
      hPi4Global.PREFIX_TEMP,
      hPi4Global.PREFIX_STRESS,
    ],
  );

  /// A device this build has never heard of.
  ///
  /// The **intersection**, deliberately — the same posture as
  /// `DeviceGeneration.unknown` in `lib/ble/device_generation.dart`. Health data
  /// still syncs and still charts correctly, because the sample stream and the
  /// registry describe themselves. What it does not get is any surface that
  /// depends on knowing the hardware: no BP, no ECG, no EDA, and (in
  /// `DfuTopology`, later) no firmware update, because pushing an image at a
  /// bootloader we cannot identify is unrecoverable.
  static const DeviceProfile unknown = DeviceProfile(
    model: DeviceModel.unknown,
    productName: 'HealthyPi device',
    deviceNoun: 'device',
    hasBloodPressure: false,
    hasEcg: false,
    hasGsrEda: false,
    hasFingerSensor: false,
    homeSignals: [
      hPi4Global.PREFIX_ACTIVITY,
      hPi4Global.PREFIX_SPO2,
      hPi4Global.PREFIX_TEMP,
      hPi4Global.PREFIX_STRESS,
    ],
    gridSignals: [
      hPi4Global.PREFIX_ACTIVITY,
      hPi4Global.PREFIX_SPO2,
      hPi4Global.PREFIX_TEMP,
      hPi4Global.PREFIX_STRESS,
    ],
  );

  // --- Resolution ---------------------------------------------------------

  /// The `HELLO.dev` model string each product reports.
  ///
  /// Pinned against the firmware: `app/src/health/hpi_hs_mgmt.c` in
  /// `healthypi-move-fw` emits `healthypi-move`, and
  /// `apps/app_ultralight_stm32/src/health/hpi_hs_mgmt.c` in `move_ultralight`
  /// emits `healthypi-move-ultralight`.
  static const String devMoveNext = 'healthypi-move';
  static const String devUltralight = 'healthypi-move-ultralight';

  /// Resolve a profile from the `HELLO.dev` model string — the authoritative
  /// source, because it comes from the device's own firmware over SMP.
  ///
  /// Matching is case-insensitive and trims surrounding whitespace, but is
  /// otherwise exact: a *prefix* match would classify `healthypi-move-ultralight`
  /// as a Move, which would put a blood-pressure screen on a band. Order the
  /// checks so that can never depend on which is tested first.
  static DeviceProfile forHelloDev(String? dev) {
    final d = dev?.trim().toLowerCase();
    if (d == null || d.isEmpty) return unknown;
    return switch (d) {
      devMoveNext => moveNext,
      devUltralight => moveUltralight,
      _ => unknown,
    };
  }

  /// Resolve from the value persisted on `DeviceInfo.model`.
  ///
  /// `null` — every pairing made before this field existed — resolves to
  /// [moveNext], **not** [unknown]. An app update must not change what a current
  /// user sees before their next sync, and every fielded device today is a Move.
  /// The value is corrected from `HELLO.dev` on the next sync.
  static DeviceProfile forStoredModel(String? stored) {
    if (stored == null || stored.trim().isEmpty) return moveNext;
    return forHelloDev(stored);
  }

  /// A best-effort guess from a BLE advertised name, for the scan list only.
  ///
  /// **Never use this for a capability decision.** An advertised name is
  /// user-settable and carries no authority; it exists here so a scan row can be
  /// labelled before any SMP session exists. Capabilities come from
  /// [forHelloDev], after `HELLO`.
  static DeviceProfile forAdvertisedName(String? name) {
    final n = name?.trim().toLowerCase();
    if (n == null || n.isEmpty) return unknown;
    // Firmware builds this as "MoveUL XXYYZZ" from the hardware id.
    if (n.startsWith('moveul') || n.contains('ultralight')) {
      return moveUltralight;
    }
    if (n.contains('healthypi move') || n.contains('healthypi-move')) {
      return moveNext;
    }
    return unknown;
  }

  /// The stored form of this profile, for `DeviceInfo.model`.
  String? get storedModel => switch (model) {
        DeviceModel.moveNext => devMoveNext,
        DeviceModel.moveUltralight => devUltralight,
        DeviceModel.unknown => null,
      };

  @override
  String toString() => 'DeviceProfile($productName)';
}
