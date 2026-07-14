// Copyright (c) 2024-2026 ProtoCentral
// SPDX-License-Identifier: MIT

import 'package:flutter/material.dart';

/// The pre-redesign TextStyles and Colors, still referenced by the legacy
/// screens that remain in the tree for rollback (home.dart, scr_trends.dart,
/// the ECG/GSR/HRV recording screens, BPT).
///
/// These are **not** the redesign's theme — that is `lib/theme/hpi_theme.dart`
/// plus HpiColors/HpiText. Nothing new should reach for these; they exist so
/// the legacy screens keep compiling until Phase 5 deletes them, and they die
/// with those screens.
///
/// They used to live inside `hPi4Global` next to the GATT UUIDs, which meant
/// every file that wanted a service UUID also pulled in Flutter's material
/// library.
class HpiLegacyTheme {
  static const TextStyle eventStyle = TextStyle(
    fontSize: 30,
    fontWeight: FontWeight.bold,
    color: Colors.white,
  );
  static const TextStyle cardTextStyle = TextStyle(
    fontSize: 16,
    fontWeight: FontWeight.bold,
    color: Colors.white,
  );
  static const TextStyle cardValueTextStyle = TextStyle(
    fontSize: 30,
    fontWeight: FontWeight.bold,
    color: Colors.white,
  );

  static const TextStyle movecardTextStyle = TextStyle(
    fontSize: 16,
    color: Colors.white,
  );
  static const TextStyle movecardValueTextStyle = TextStyle(
    fontSize: 28,
    fontWeight: FontWeight.bold,
    color: Colors.white,
  );

  static const TextStyle moveValueTextStyle = TextStyle(
    fontSize: 18,
    fontWeight: FontWeight.bold,
    color: Colors.white,
  );

  static const TextStyle moveValueGreenTextStyle = TextStyle(
    fontSize: 34,
    fontWeight: FontWeight.bold,
    color: Colors.green,
  );

  static const TextStyle moveValueOrangeTextStyle = TextStyle(
    fontSize: 34,
    fontWeight: FontWeight.bold,
    color: Colors.orange,
  );

  static const TextStyle moveValueBlueTextStyle = TextStyle(
    fontSize: 34,
    fontWeight: FontWeight.bold,
    color: Colors.blue,
  );

  static const TextStyle movecardSubValueTextStyle = TextStyle(
    fontSize: 12,
    color: Colors.white,
  );

  static const TextStyle movecardSubValueGreenTextStyle = TextStyle(
    fontSize: 12,
    color: Colors.green,
  );

  static const TextStyle movecardSubValueOrangeTextStyle = TextStyle(
    fontSize: 12,
    color: Colors.orange,
  );

  static const TextStyle movecardSubValueBlueTextStyle = TextStyle(
    fontSize: 12,
    color: Colors.blue,
  );

  static const TextStyle movecardSubValue1TextStyle = TextStyle(
    fontSize: 12,
    color: Colors.white,
  );

  static const TextStyle movecardSubValueRedTextStyle = TextStyle(
    fontSize: 14,
    color: Colors.orange,
  );

  static const TextStyle movecardSubValue2TextStyle = TextStyle(
    fontSize: 14,
    fontWeight: FontWeight.bold,
    color: Colors.white,
  );

  static const TextStyle subValueWhiteTextStyle = TextStyle(
    fontSize: 12,
    color: Colors.white,
  );

  static const TextStyle cardBlackTextStyle = TextStyle(
    fontSize: 20,
    color: Colors.black,
  );

  static const TextStyle cardWhiteTextStyle = TextStyle(
    fontSize: 20,
    color: Colors.white,
  );

  static const TextStyle eventsWhite = TextStyle(
    fontSize: 14,
    fontWeight: FontWeight.bold,
    color: Colors.white,
  );

  //static const Color hpi4Color = Color(0xFFFFD551);

  static const Color hpi4Color = Color(0xFFFF6D00);

  static const Color hpi4AppBarColor = Colors.black;

  static const Color hpi4AppBarIconsColor = Colors.white;

  static const Color oldHpi4Color = Color(0xFF125871);

  static const TextStyle scrHeadStyle = TextStyle(
    fontSize: 24,
    color: Colors.white,
    letterSpacing: 1,
  );

  static const TextStyle HeadStyle = TextStyle(
    fontSize: 24,
    color: Colors.black,
    letterSpacing: 0.5,
  );

  static Color appBarColor = Colors.black38;
  static Color appBackgroundColor = Colors.black;

}
