// Copyright (c) 2024-2026 ProtoCentral
// SPDX-License-Identifier: MIT

/// Device protocol constants: the HealthyPi Move GATT map, the legacy
/// command opcodes, the research-recording constants, and the trend-type /
/// file-prefix keys.
///
/// This file used to be 554 lines and held three unrelated things: these
/// constants, ~20 TextStyles/Colors, and two widget classes. The styles/colors
/// and widgets (a legacy theme + loading indicator) were retired with the last
/// legacy-themed screens (the 5a/5b/5c device-flow redesign). It now imports no
/// Flutter library at all, which is the point: reading a service UUID should
/// not drag in material.dart.
class hPi4Global {
  static const String UUID_SERV_DIS = "0000180a-0000-1000-8000-00805f9b34fb";
  static const String UUID_SERV_BATT = "0000180f-0000-1000-8000-00805f9b34fb";
  static const String UUID_SERV_HR = "0000180d-0000-1000-8000-00805f9b34fb";
  static const String UUID_SERV_SPO2 = "00001822-0000-1000-8000-00805f9b34fb";

  static const String UUID_SERV_PPG = "cd5c7491-4448-7db8-ae4c-d1da8cba36d0";
  static const String UUID_CHAR_FINGERPPG =
      "cd5ca86f-4448-7db8-ae4c-d1da8cba36d0";
  static const String UUID_CHAR_PPG = "cd5c1525-4448-7db8-ae4c-d1da8cba36d0";

  // The custom cmd/data GATT service (`01bf7492…` + its 0x60-0x76 opcodes) is
  // retired: the firmware moved all control — BPT calibration, log/record
  // fetch, research recording — onto the HPI_HS MCUmgr group (`0x1000`, see
  // package:healthypi_healthy_store). Nothing in the app writes it any more.

  static const String UUID_ECG_SERVICE = "00001122-0000-1000-8000-00805f9b34fb";
  static const String UUID_ECG_CHAR = "00001424-0000-1000-8000-00805f9b34fb";
  static const String UUID_GSR_CHAR = "babe4a4c-7789-11ed-a1eb-0242ac120002";

  static const String UUID_SERV_STREAM_2 =
      "cd5c7491-4448-7db8-ae4c-d1da8cba36d0";
  static const String UUID_STREAM_2 = "01bf1525-970f-8d96-d44d-9023c47faddc";

  static const String UUID_CHAR_HR = "00002a37-0000-1000-8000-00805f9b34fb";
  static const String UUID_SPO2_CHAR = "00002a5e-0000-1000-8000-00805f9b34fb";
  static const String UUID_TEMP_CHAR = "00002a6e-0000-1000-8000-00805f9b34fb";

  static const String UUID_CHAR_ACT = "000000a2-0000-1000-8000-00805f9b34fb";
  static const String UUID_CHAR_BATT = "00002a19-0000-1000-8000-00805f9b34fb";
  static const String UUID_DIS_FW_REVISION =
      "00002a26-0000-1000-8000-00805f9b34fb";
  static const String UUID_SERV_HEALTH_THERM =
      "00001809-0000-1000-8000-00805f9b34fb";

  static const String UUID_SERV_SMP = "8d53dc1d-1db7-4cd3-868b-8a527460aa84";
  static const String UUID_CHAR_SMP = "da2e7828-fbce-4e01-ae9e-261174997c48";

  static const int HPI_TREND_TYPE_HR = 0x01;
  static const int HPI_TREND_TYPE_SPO2 = 0x02;
  static const int HPI_TREND_TYPE_TEMP = 0x03;
  static const int HPI_TREND_TYPE_ACTIVITY = 0x04;
  static const int HPI_TREND_TYPE_ECG = 0x05;

  // Device RTC is set via standard MCUmgr OS datetime (OsMgmt.setDatetime).
  // BPT calibration control (old 0x60/0x61/0x62) is now HPI_HS cmds 8-11, driven
  // from lib/ble/hpi_hs_bpt_transport.dart via the HpiHs client. Log/record fetch
  // (old 0x30-0x55) is now HPI_HS SYNC/RECORDS. All the custom cmd/data opcode
  // constants that lived here were deleted with that service.

  // Research Recording Signal Mask Bits
  static const int SIGNAL_PPG_WRIST = 0x01;   // Bit 0: PPG Wrist (IR, Red, Green @ 25 Hz)
  static const int SIGNAL_PPG_FINGER = 0x02; // Bit 1: PPG Finger (IR, Red @ 25 Hz)
  static const int SIGNAL_ACCEL = 0x04;      // Bit 2: IMU Accelerometer (X, Y, Z @ 100 Hz)
  static const int SIGNAL_GYRO = 0x08;       // Bit 3: IMU Gyroscope (X, Y, Z @ 100 Hz)
  static const int SIGNAL_GSR = 0x10;        // Bit 4: GSR (@ 32 Hz)

  // Research Recording States
  static const int REC_STATE_IDLE = 0;
  static const int REC_STATE_ARMED = 1;
  static const int REC_STATE_RECORDING = 2;
  static const int REC_STATE_FINALIZING = 3;
  static const int REC_STATE_ERROR = 4;

  // Research Recording Response Types
  static const int CES_CMDIF_TYPE_REC_SESSION = 0x05; // Session list entry

  // Research Recording File Format
  static const int REC_FILE_MAGIC = 0x48504952; // "HPIR" in little-endian
  static const int REC_FILE_HEADER_SIZE = 32;

  // Research Recording Signal Types (in file header)
  static const int REC_SIGNAL_TYPE_PPG_WRIST = 0;
  static const int REC_SIGNAL_TYPE_PPG_FINGER = 1;
  static const int REC_SIGNAL_TYPE_ACCEL = 2;
  static const int REC_SIGNAL_TYPE_GYRO = 3;
  static const int REC_SIGNAL_TYPE_GSR = 4;

  // Research Recording Sample Sizes (bytes per sample)
  static const int REC_SAMPLE_SIZE_PPG_WRIST = 12;  // 3 x uint32
  static const int REC_SAMPLE_SIZE_PPG_FINGER = 8; // 2 x uint32
  static const int REC_SAMPLE_SIZE_ACCEL = 6;      // 3 x int16
  static const int REC_SAMPLE_SIZE_GYRO = 6;       // 3 x int16
  static const int REC_SAMPLE_SIZE_GSR = 4;        // 1 x int32

  // Research Recording Sample Rates (Hz)
  static const int REC_SAMPLE_RATE_PPG = 25;
  static const int REC_SAMPLE_RATE_ACCEL = 100;
  static const int REC_SAMPLE_RATE_GYRO = 100;
  static const int REC_SAMPLE_RATE_GSR = 32;

  // Research Recording File Paths on Device
  static const String DEVICE_DIR_RESEARCH = 'rec';

  // Device filesystem paths for SMP downloads (LittleFS structure)
  static const String DEVICE_DIR_HR = 'trhr';
  static const String DEVICE_DIR_TEMP = 'trtemp';
  static const String DEVICE_DIR_SPO2 = 'trspo2';
  static const String DEVICE_DIR_ACTIVITY = 'trsteps';
  
  // File prefixes for local CSV storage
  static const String PREFIX_HR = 'hr';
  static const String PREFIX_TEMP = 'temp';
  static const String PREFIX_SPO2 = 'spo2';
  static const String PREFIX_ACTIVITY = 'activity';

  /// Continuous HRV (RMSSD), stored in whole milliseconds. Firmware P3 emits a
  /// 5-minute-window RMSSD from gated wrist R-R intervals.
  static const String PREFIX_HRV = 'hrv';

  /// Continuous, HRV-derived stress (0..100), scored against the user's own
  /// rolling RMSSD baseline.
  static const String PREFIX_STRESS = 'stress';

  /// The *other* stress number: the manual 30-second EDA spot check, scored on
  /// absolute skin conductance. Both arrive as the same HPI_HS `stress` type and
  /// are told apart only by the MANUAL quality bit — they are kept in separate
  /// trends on purpose, because they are two different scales and plotting them
  /// on one axis would silently mix them (firmware handoff §6.3).
  static const String PREFIX_STRESS_EDA = 'stress_eda';

  static String hpi4AppVersion = "";
  static String hpi4AppBuildNumber = "";
}
