# Changelog

## 0.1.0

- Initial extraction from the HealthyPi Move app and OpenView 3, which carried
  identical copies of this code.
- `HpiHs` client for MCUmgr group `0x1000`: `HELLO`, `TYPES`, `SYNC`/`syncAll`,
  `SUMMARY`, `RECORDS` (list / get / `downloadRecord` with CRC-32 / ack), `ACK`,
  `SYNTH` (test builds), and `SET_TZ` (cmd 7 — push the phone's UTC offset so the
  device renders local wall-clock time without an RTC rewrite on DST).
- Wire models `HsType`, `HsSample`, `HsRecordHeader`, `HsRecordSamples`, and
  `Crc32` (IEEE, matches Zephyr `crc32_ieee`).
- Pure Dart, no Flutter dependency. Diagnostics go through an injectable
  `HpiHsLog` callback instead of `debugPrint`.
- `HpiHs.ack` is deprecated in favour of `HpiHs.ackDurablyStored`, which names
  its precondition: the call is destructive and the device may drop every sample
  at or below the acked sequence number.
