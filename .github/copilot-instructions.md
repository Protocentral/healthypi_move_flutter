# HealthyPi Move Flutter App - AI Coding Agent Instructions

## Project Overview
Flutter mobile app (iOS/Android) for HealthyPi Move wearable health device. Syncs health metrics (HR, SpO2, temperature, activity) via BLE using a **hybrid protocol approach**: custom commands for discovery + SMP (Simple Management Protocol) for file transfer.

## Architecture

### Core Structure
- **Entry Point**: `move/lib/main.dart` - MaterialApp with `UpgradeAlert` wrapper
- **Main Navigation**: `move/lib/home.dart` - Bottom nav with 3 tabs (Home, Device, Settings)
- **Working Directory**: All app code is in `move/` subdirectory, NOT the repo root

### Key Screens (`move/lib/screens/`)
- `scr_scan.dart` - BLE device scanning with auto-reconnect to paired devices
- `scrSync.dart` - **Hybrid data synchronization** (custom commands + SMP file transfer)
- `scr_dfu.dart` - Firmware update via MCU Manager protocol
- `scr_device_mgmt.dart` - Device management and data reset
- `scr_hr.dart`, `scr_spo2.dart`, `scr_skin_temp.dart`, `scr_activity.dart` - Metric visualization
- `csvData.dart` - Generic CSV data manager with `CsvDataManager<T>` class
- `fileTransfer.dart` - Example SMP file operations with MCU Manager

### Data Flow (Hybrid Protocol)

#### 1. **BLE Communication** - Custom Commands for Discovery
Uses `flutter_blue_plus` with custom UUIDs in `globals.dart`:
- Command service: `UUID_SERVICE_CMD`, characteristic: `UUID_CHAR_CMD`
- Data service: `UUID_CHAR_CMD_DATA` for metadata responses
- Standard characteristics: `UUID_CHAR_HR`, `UUID_CHAR_ACT`, `UUID_CHAR_BATT`

#### 2. **Sync Process** (`scrSync.dart`) - Hybrid Approach
**Discovery Phase (Custom Protocol)**:
1. Send `getSessionCount` command for each metric type (HR/Temp/SpO2/Activity)
2. Receive count responses via `CES_CMDIF_TYPE_CMD_RSP` packets
3. Send `sessionLogIndex` command to get file metadata
4. Parse `CES_CMDIF_TYPE_LOG_IDX` responses containing:
   - **logFileID** (Unix timestamp): File identifier
   - **sessionLength** (bytes): File size for progress tracking
   - **trendType**: Metric identifier

**Download Phase (SMP Protocol via MCU Manager)**:
1. Initialize `FsManager` with device ID
2. Construct device file path: `/lfs/<metric>_<timestamp>.bin` (binary files)
3. Call `fsManager.download(deviceFilePath)` for SMP file transfer
4. Read downloaded binary file from app directory
5. Parse binary data (16 bytes per record) into CSV format
6. Save CSV to app documents directory
7. Clean up temporary binary file

**Key Differences from Old Approach**:
- ❌ OLD: Custom BLE packets (`CES_CMDIF_TYPE_DATA`) with manual chunking via BLE notifications
- ✅ NEW: SMP file transfer downloads complete binary files, then parse locally
- **Note**: Device stores binary format, not CSV - app must still parse binary-to-CSV

#### 3. **Storage**
- **CSV files**: App documents directory via `path_provider`
  - Naming: `hr_<timestamp>.csv`, `temp_<timestamp>.csv`, etc.
  - Format: Already CSV from device (no conversion needed)
- **SharedPreferences**: Last sync time, latest vital values, device pairing MAC address
- **Key pattern**: `latestHR`, `lastUpdatedHR`, `lastSynced`, `fetchStatus`

#### 4. **Data Visualization**
- Syncfusion Charts (`syncfusion_flutter_charts`)
- Trend classes in `globals.dart`: `HourlyTrend`, `WeeklyTrend`, `MonthlyTrend`, `ActivityDailyTrend`, etc.
- `CsvDataManager` reads/filters CSV data by timestamp ranges

## Critical Patterns

### Hybrid Protocol Structure
```dart
// Discovery: Custom BLE commands (kept for compatibility)
List<int> cmd = [];
cmd.addAll(hPi4Global.getSessionCount);
cmd.addAll(hPi4Global.HrTrend);
await commandCharacteristic.write(cmd, withoutResponse: true);

// Download: SMP via MCU Manager
final fsManager = mcumgr.FsManager(deviceId);
await fsManager.download("/lfs/hr_1633024800.csv");
```

### Device File Paths (SMP/LittleFS)
- Pattern: `/lfs/<metric>_<timestamp>.bin` (binary format)
- Examples:
  - `/lfs/hr_1633024800.bin`
  - `/lfs/temp_1633024800.bin`
  - `/lfs/spo2_1633024800.bin`
  - `/lfs/activity_1633024800.bin`
- **After download**: Binary files are parsed into CSV format locally

### MCU Manager Error Handling
```dart
String _getMcuMgrErrorMessage(String errorString) {
  if (errorString.contains('McuMgrErrorException')) {
    // Parse error code and group
    // Group 8 = File system errors (2=not found, 7=permission denied, etc.)
    // Return user-friendly message
  }
}
```

### Device Pairing Persistence
- MAC address stored in `paired_device_mac.txt` (see `scr_scan.dart`)
- Auto-connect attempted on scan screen init via `_tryAutoConnectToPairedDevice()`

### Firmware Updates
- Uses `mcumgr_flutter` for Nordic nRF5 DFU protocol
- Manifest-based updates with `manifest.dart` (JSON serializable)
- Check version via BLE characteristic before showing update card
- **Minimum version for sync: 1.7.0** (SMP file system support required)

### State Management
- Mostly StatefulWidget with setState()
- No Provider/Bloc in main app flow (despite dependencies)
- StreamSubscriptions for BLE state (connection, scanning, characteristics)
- FsManager for SMP file operations

## Development Workflows

### Building
```bash
cd move
flutter pub get
flutter build apk --release  # Android
flutter build ios --release  # iOS
```

### Running
```bash
cd move
flutter run
# Or for specific device:
flutter devices
flutter run -d <device-id>
```

### Key Dependencies
- `flutter_blue_plus: ^2.0.0` - BLE communication
- `mcumgr_flutter: ^0.6.1` - **Nordic SMP protocol (file transfer + DFU)**
- `syncfusion_flutter_charts: ^31.1.20` - Chart widgets
- `shared_preferences: ^2.0.18` - Persistent key-value storage
- `path_provider: ^2.0.11` - File system paths

### Android Build Configuration
- Signing: Uses `key.properties` (load keystoreProperties from root)
- NDK version locked to `27.0.12077973`
- Namespace: `com.protocentral.move`
- minSdk from flutter, compileOptions Java 11

## Common Gotchas

1. **Always work in `move/` directory** - pubspec.yaml is at `move/pubspec.yaml`, not root
2. **BLE Permissions**: Android needs location permissions for BLE scanning (handled in AndroidManifest)
3. **CSV Timestamp Format**: Unix epoch in seconds (multiply by 1000 for DateTime conversion)
4. **SharedPreferences Keys**: Multiple keys per metric (latest value, last updated time, sync status)
5. **Stream Cleanup**: Always cancel StreamSubscriptions in dispose() to prevent memory leaks
6. **Device Connection State**: Check `_connectionState` before BLE operations
7. **iOS Build Height**: Bottom nav has special height calculation for iOS (see `bottomBarHeight()`)
8. **SMP File Paths**: Must use `/lfs/` prefix for LittleFS file system on device
9. **Firmware Version**: Minimum 1.7.0 required for SMP file system support
10. **Import Conflicts**: `mcumgr_flutter` and `flutter` both export `Image` - use `as mcumgr` prefix

## Sync Protocol Details

### Why Hybrid Approach?
- **Discovery remains custom** because firmware already implements these commands and they work reliably
- **File transfer via SMP** provides:
  - Standardized protocol with better error handling
  - No manual chunking/packet assembly
  - Direct file system access
  - Simpler codebase (no binary parsing)
  - Future compatibility with Nordic ecosystem

### File Existence Optimization
```dart
bool isToday = _isToday(header);  // Check if timestamp is today
if (!isToday && fileExists) {
  skip download  // Avoid re-downloading old data
}
// Always download today's file (may have new data)
```

## Color Scheme
- Primary: `hPi4Global.hpi4Color` (purple theme)
- AppBar: `hPi4Global.hpi4AppBarColor`
- Background: `hPi4Global.appBackgroundColor`
- Accent: `hPi4Global.oldHpi4Color`

## Testing
- Basic widget test exists but is not actively used
- No unit tests for BLE logic or data processing
- Manual testing with physical HealthyPi Move device required
- Firmware version 1.7.0+ required for SMP testing

## File Organization
- `lib/screens/` - UI screens and main logic
- `lib/widgets/` - Reusable widgets (tiles for scan results, services, characteristics)
- `lib/utils/` - Utilities (size config, snackbar, manifest parsing)
- `lib/globals.dart` - Constants, UUIDs, trend classes, hPi4Global static class
- `lib/fileTransfer.dart` - Example/reference for SMP file operations

## Version Management
- Version in `pubspec.yaml`: `version: 1.3.5+62` (semantic version + build number)
- Package info loaded dynamically: `hPi4Global.hpi4AppVersion` set from `PackageInfo.fromPlatform()`
- Firmware compatibility: Check for version ≥1.7.0 before syncing
