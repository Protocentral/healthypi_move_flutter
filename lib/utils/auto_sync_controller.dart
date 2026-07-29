// Copyright (c) 2024-2026 ProtoCentral
// SPDX-License-Identifier: MIT

import 'dart:async';

import 'package:flutter/widgets.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'connection_manager.dart';
import 'device_manager.dart';
import 'firmware_update_checker.dart';
import 'healthy_store_sync_manager.dart';

/// Why an automatic sync did not start. [none] means it should.
enum AutoSyncSkip {
  none,

  /// The user turned auto-sync off in Settings.
  disabled,

  /// No paired watch — nothing to sync with.
  noDevice,

  /// A sync (auto or user-initiated) is already running.
  alreadySyncing,

  /// Another SMP flow holds the wire. Records or, critically, a DFU.
  smpBusy,

  /// The Live screen is streaming. One radio, two modes that must not overlap.
  streaming,

  /// We synced recently enough that another pass would be churn.
  tooSoon,
}

/// When an automatic sync may run. Pure — no plugins, no clock of its own, no
/// BLE — so the guard conditions are unit-testable without a device.
///
/// These are guards, not preferences: three of them ([smpBusy], [streaming],
/// [alreadySyncing]) exist because the app has exactly one radio carrying two
/// logical modes, and an automatic flow is the one flow the user is not
/// watching when it collides with something.
class AutoSyncPolicy {
  const AutoSyncPolicy._();

  /// Floor between automatic syncs. The device aggregates into hourly bins, so
  /// anything much tighter than this re-walks the same rows for no new data
  /// while holding the radio up.
  static const Duration minInterval = Duration(minutes: 15);

  static AutoSyncSkip evaluate({
    required bool enabled,
    required bool hasPairedDevice,
    required bool isSyncing,
    required bool isSmpBusy,
    required bool isStreaming,
    required DateTime? lastAttempt,
    required DateTime now,
    Duration interval = minInterval,
  }) {
    if (!enabled) return AutoSyncSkip.disabled;
    if (!hasPairedDevice) return AutoSyncSkip.noDevice;
    if (isSyncing) return AutoSyncSkip.alreadySyncing;
    if (isSmpBusy) return AutoSyncSkip.smpBusy;
    if (isStreaming) return AutoSyncSkip.streaming;
    if (lastAttempt != null) {
      final since = now.difference(lastAttempt);
      // A negative elapsed time means the clock moved backwards (timezone fix,
      // NTP correction). Treat that as "due" rather than locking auto-sync out
      // until the stored stamp is naturally overtaken.
      if (!since.isNegative && since < interval) return AutoSyncSkip.tooSoon;
    }
    return AutoSyncSkip.none;
  }
}

/// Runs a short, silent sync when the app comes to the foreground.
///
/// This is **foreground** auto-sync, not background sync: it fires on app start
/// and on resume, and does nothing while the app is backgrounded. Real
/// background sync would need iOS BLE state restoration, which `universal_ble`
/// does not expose — a `Timer.periodic` in a suspended app buys nothing but a
/// wakeup that iOS will not honour.
///
/// The sync machinery already supported this: the cursor is persisted per page
/// and a session is resumable, so a short budget that runs out is not lost work
/// — the next resume carries on from where it stopped. What was missing was
/// only a trigger.
///
/// Failures are swallowed. An automatic sync the user did not ask for must not
/// raise a snackbar about a watch that happens to be out of range; the Device
/// screen's "Last synced" line is where that shows up honestly.
class AutoSyncController with WidgetsBindingObserver {
  AutoSyncController._();
  static final AutoSyncController instance = AutoSyncController._();

  /// Settings toggle. Default **on** — the feature is the point — but it is a
  /// user's radio and battery, so it is theirs to switch off.
  static const String enabledPrefKey = 'auto_sync_enabled';

  /// Persisted so the throttle survives a restart. Without it, force-quitting
  /// and reopening would sync on every launch.
  static const String _lastAttemptPrefKey = 'auto_sync_last_attempt';

  /// Wall-clock cap for an automatic pass. Much shorter than the Device
  /// screen's deliberate 5-minute catch-up: this one runs unattended, and a
  /// backlog it cannot finish is picked up by the next resume.
  static const Duration budget = Duration(seconds: 45);

  bool _started = false;
  Timer? _ticker;

  /// Register the lifecycle hook and run the first check. Idempotent — the
  /// shell is rebuilt by `ScrMainShell.returnToRoot`, so this is called more
  /// than once per process.
  void start() {
    if (_started) return;
    _started = true;
    WidgetsBinding.instance.addObserver(this);
    _startTicker();
    // Deferred to after the first frame so a cold start paints before the
    // radio work begins.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      unawaited(maybeSync('startup'));
      unawaited(FirmwareUpdateChecker.instance.refresh());
    });
  }

  void stop() {
    if (!_started) return;
    _started = false;
    _ticker?.cancel();
    _ticker = null;
    WidgetsBinding.instance.removeObserver(this);
  }

  /// Resume alone would never sync an app that is simply left open — a watch on
  /// the wrist all afternoon behind a foregrounded app would go unsynced until
  /// the user backgrounded it. The tick is throttled by the same policy as
  /// every other trigger, so it costs nothing when a sync just ran.
  void _startTicker() {
    _ticker?.cancel();
    _ticker = Timer.periodic(
        AutoSyncPolicy.minInterval, (_) => unawaited(maybeSync('tick')));
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    // Stop ticking while backgrounded. iOS suspends the app anyway; on Android
    // the timer can survive, and a sync the user cannot see fail — with no
    // foreground service to keep the radio work legitimate — is not something
    // to start on a timer.
    if (state != AppLifecycleState.resumed) {
      _ticker?.cancel();
      _ticker = null;
      return;
    }
    if (_started) _startTicker();
    unawaited(maybeSync('resume'));
    unawaited(FirmwareUpdateChecker.instance.refresh());
  }

  static Future<bool> isEnabled() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getBool(enabledPrefKey) ?? true;
  }

  static Future<void> setEnabled(bool value) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(enabledPrefKey, value);
  }

  /// Sync if every guard in [AutoSyncPolicy] allows it. Returns the reason it
  /// skipped, or [AutoSyncSkip.none] if it ran.
  Future<AutoSyncSkip> maybeSync(String trigger) async {
    final prefs = await SharedPreferences.getInstance();
    final device = await DeviceManager.getPairedDevice();
    final lastMs = prefs.getInt(_lastAttemptPrefKey);
    final conn = ConnectionManager.instance;

    final skip = AutoSyncPolicy.evaluate(
      enabled: prefs.getBool(enabledPrefKey) ?? true,
      hasPairedDevice: device != null,
      isSyncing: HealthyStoreSyncManager.instance.isSyncing,
      isSmpBusy: conn.isSmpBusy,
      isStreaming: conn.isStreaming,
      lastAttempt:
          lastMs == null ? null : DateTime.fromMillisecondsSinceEpoch(lastMs),
      now: DateTime.now(),
    );

    if (skip != AutoSyncSkip.none) {
      debugPrint('[AutoSync] $trigger: skipped (${skip.name})');
      return skip;
    }

    // Stamped *before* the run, not after: a sync that dies mid-way must not
    // become a retry loop across rapid foreground/background flips.
    await prefs.setInt(
        _lastAttemptPrefKey, DateTime.now().millisecondsSinceEpoch);

    debugPrint('[AutoSync] $trigger: starting');
    try {
      final result = await HealthyStoreSyncManager.instance.syncData(
        deviceMacAddress: device!.macAddress,
        onProgress: (_, _) {},
        onStatus: (_) {},
        budget: budget,
      );
      debugPrint('[AutoSync] $trigger: ${result.message}');
    } catch (e) {
      // Out of range, radio off, link dropped — all expected for an unattended
      // pass. The next resume tries again from the persisted cursor.
      debugPrint('[AutoSync] $trigger: failed: $e');
    }
    return AutoSyncSkip.none;
  }
}
