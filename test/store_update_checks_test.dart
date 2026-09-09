// Copyright (c) 2024-2026 ProtoCentral
// SPDX-License-Identifier: MIT

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import 'package:move/feature_flags.dart';

/// Guards the store-less build variant.
///
/// `--dart-define=STORE_UPDATE_CHECKS=false` is what makes an F-Droid build
/// legitimate: off a store there is no listing for `upgrader` to read, so the
/// check is a request to Google or Apple that can only fail, and F-Droid's own
/// client is what keeps the app current. See docs/FDROID_RELEASE.md.
///
/// The flag only works if `upgrader` stays confined to the one file that
/// honours it. A second call site added anywhere else would reach a store from
/// a build that has none — silently, because nothing else would fail.
///
/// A failure here is not "delete the test". It means the new usage must be put
/// behind [kStoreUpdateChecks] too.
void main() {
  group('store update checks', () {
    test('defaults to on, so store builds are unaffected', () {
      // No --dart-define under `flutter test`, so this is the default path.
      expect(kStoreUpdateChecks, isTrue);
    });

    test('package:upgrader is imported only by main.dart', () {
      const allowed = 'lib/main.dart';
      final offenders = <String>[];

      for (final entity in Directory('lib').listSync(recursive: true)) {
        if (entity is! File || !entity.path.endsWith('.dart')) continue;
        final path = entity.path.replaceAll(r'\', '/');
        if (path == allowed) continue;
        if (entity.readAsStringSync().contains("package:upgrader/")) {
          offenders.add(path);
        }
      }

      expect(offenders, isEmpty,
          reason: 'upgrader reaches an app store. Every use must sit behind '
              'kStoreUpdateChecks, which only $allowed does. Found in: '
              '${offenders.join(', ')}');
    });

    test('main.dart constructs Upgrader only when the flag is on', () {
      final main = File('lib/main.dart').readAsStringSync();

      // Construction, not just display: Upgrader queries the store listing when
      // it is created, so a hidden alert would still make the request.
      expect(
        main.contains(
            'kStoreUpdateChecks ? Upgrader(minAppVersion: kMinimumAppVersion) : null'),
        isTrue,
        reason: 'The Upgrader must be built conditionally. Constructing it and '
            'then hiding the alert still hits the store on launch.',
      );
    });
  });
}
