// Copyright (c) 2024-2026 ProtoCentral
// SPDX-License-Identifier: MIT

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// Guards the privacy statement rendered by `ScrSettingsNew._privacyCard`.
///
/// That card tells the user, as a plain assertion, that the app has no
/// analytics and uploads nothing they measure. A claim like that is not a
/// comment — it is the thing a privacy-conscious user decides on, and it stops
/// being true the moment somebody adds a dependency without reading the
/// Settings screen. These tests fail when that happens.
///
/// A failure here is not "delete the test". It means the privacy card must be
/// updated to match what the app now does, or the dependency reconsidered.
void main() {
  final pubspec = File('pubspec.yaml').readAsStringSync();

  /// Files allowed to reach the network, and what for. Both are stated on the
  /// card as the app's only outbound traffic.
  const networkAllowlist = <String>{
    // GitHub: watch firmware release metadata + the binary itself.
    'lib/utils/firmware_update_service.dart',
  };

  group('privacy claims in Settings', () {
    test('no analytics, telemetry or crash-reporting dependency', () {
      // Named rather than pattern-matched: these are the packages that would
      // actually make the "no analytics" line false.
      const banned = [
        'firebase_analytics',
        'firebase_crashlytics',
        'firebase_core',
        'sentry',
        'sentry_flutter',
        'mixpanel_flutter',
        'amplitude_flutter',
        'posthog_flutter',
        'segment_analytics',
        'appsflyer',
        'facebook_app_events',
        'google_analytics',
        'datadog_flutter_plugin',
      ];
      for (final pkg in banned) {
        expect(pubspec.contains('$pkg:'), isFalse,
            reason: '$pkg would make the Settings privacy card\'s '
                '"no analytics" claim false. Update the card or drop the '
                'dependency.');
      }
    });

    test('package:http is imported only where the card says it is', () {
      final offenders = <String>[];
      for (final entity in Directory('lib').listSync(recursive: true)) {
        if (entity is! File || !entity.path.endsWith('.dart')) continue;
        final path = entity.path.replaceAll(r'\', '/');
        if (networkAllowlist.contains(path)) continue;
        final src = entity.readAsStringSync();
        if (src.contains("import 'package:http/") ||
            src.contains('import "package:http/')) {
          offenders.add(path);
        }
      }
      expect(offenders, isEmpty,
          reason: 'New network call site(s) outside the allowlist. The '
              'Settings privacy card claims the app goes online only for '
              'firmware and app-update checks — update it, or route this '
              'through an existing service.');
    });

    test('no raw dart:io HttpClient use in lib/', () {
      // dart:io is imported legitimately for File work, so this looks for the
      // HTTP client specifically rather than the import.
      final offenders = <String>[];
      for (final entity in Directory('lib').listSync(recursive: true)) {
        if (entity is! File || !entity.path.endsWith('.dart')) continue;
        final path = entity.path.replaceAll(r'\', '/');
        if (networkAllowlist.contains(path)) continue;
        if (entity.readAsStringSync().contains('HttpClient(')) {
          offenders.add(path);
        }
      }
      expect(offenders, isEmpty,
          reason: 'Raw HttpClient use bypasses the documented network paths '
              'on the Settings privacy card.');
    });
  });
}
