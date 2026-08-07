# Changelog

## 0.2.0

- **Fixed: signal-type codes were off by one.** `hsSignalName` numbered the
  firmware's `enum hpi_hs_signal` from 0, but the enum is **1-based**. Every
  record was reported as the next signal down — an ECG session (1) named
  `BioZ/GSR`, a GSR session (2) named `PPG (wrist)` — and IMU (6) fell off the
  end as `signal 6`. Nothing ever emits 0, so the `ECG` name was unreachable.
  **Anyone on 0.1.0 is mislabelling every record they list**, so this is worth
  taking even though the corrected names are a behaviour change. Covered by
  `test/hs_record_wire_test.dart`.
- Added `HsSignal`, the pinned code table (`ecg` 0x01 … `acc` 0x06). These are a
  wire contract — do not renumber them.
- Added `HpiHs.eraseAll()` (`ERASE`, cmd 12, group v3): delete all health data on
  the watch. Irreversible, requires the firmware's exact `confirm: "ERASE"`
  string, and throws `-EBUSY` if a DFU or capture is in flight. Settings, the
  user profile and BPT calibration survive — it is "delete my data", not a
  factory reset. Callers must reset their own sync cursor: `seq` is not rewound,
  but everything below the new `oldest` is gone.

## 0.1.0

- Initial extraction from the HealthyPi Move app and OpenView 3, which carried
  identical copies of this code.
- `HpiHs` client for MCUmgr group `0x1000`: `HELLO`, `TYPES`, `SYNC`/`syncAll`,
  `SUMMARY`, `RECORDS` (list / get / `downloadRecord` with CRC-32 / ack), `ACK`,
  `SYNTH` (test builds), `SET_TZ` (cmd 7 — push the phone's UTC offset so the
  device renders local wall-clock time without an RTC rewrite on DST), and
  BPT blood-pressure calibration (cmds 8–11: `ENTER` / `POINT` / `STATUS` / `END`).
- Wire models `HsHello`, `HsType`, `HsSample` (+ `HsQuality`), `HsSyncPage`,
  `HsSummary`, `HsRecordHeader`, `HsRecordSamples`, `HsRecordDownload`,
  `HsBptStatus`, and `Crc32` (IEEE, matches Zephyr `crc32_ieee`).
- Pure Dart, no Flutter dependency. Diagnostics go through an injectable
  `HpiHsLog` callback instead of `debugPrint`.
- `HpiHs.ack` is deprecated in favour of `HpiHs.ackDurablyStored`, which names
  its precondition: the call is destructive and the device may drop every sample
  at or below the acked sequence number.
