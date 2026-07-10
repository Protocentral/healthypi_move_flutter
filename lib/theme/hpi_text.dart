import 'package:flutter/material.dart';
import 'hpi_colors.dart';

/// The redesign's type ramp, from the handoff README ("Typography"). Four
/// bundled families (declared in pubspec):
///  - **Rubik** (w500) — every numeral/value.
///  - **Manrope** (w400–800) — all UI text.
///  - **JetBrains Mono** — developer surfaces (MACs, UUIDs, logs, file meta).
///  - **Saira** (w700) — the "PROTOCENTRAL" wordmark on onboarding only.
///
/// Styles carry sensible default colors from the ramp; callers `.copyWith` a
/// metric color where a value or label is tinted (e.g. an amber hero number).
abstract final class HpiText {
  static const _rubik = 'Rubik';
  static const _manrope = 'Manrope';
  static const _mono = 'JetBrains Mono';
  static const _saira = 'Saira';

  // --- Rubik: numerals & values ---
  static const heroNumber = TextStyle(
    fontFamily: _rubik,
    fontWeight: FontWeight.w500,
    fontSize: 42,
    height: 1.0,
    letterSpacing: -1,
    color: HpiColors.onSurface,
  );

  static const heroNumberSm = TextStyle(
    fontFamily: _rubik,
    fontWeight: FontWeight.w500,
    fontSize: 34,
    height: 1.0,
    letterSpacing: -0.5,
    color: HpiColors.onSurface,
  );

  static const cardValue = TextStyle(
    fontFamily: _rubik,
    fontWeight: FontWeight.w500,
    fontSize: 24,
    height: 1.05,
    color: HpiColors.onSurface,
  );

  static const statChip = TextStyle(
    fontFamily: _rubik,
    fontWeight: FontWeight.w500,
    fontSize: 18,
    color: HpiColors.onSurface,
  );

  static const valueSm = TextStyle(
    fontFamily: _rubik,
    fontWeight: FontWeight.w500,
    fontSize: 13,
    color: HpiColors.onSurface,
  );

  // --- Manrope: UI text ---
  static const screenTitle = TextStyle(
    fontFamily: _manrope,
    fontWeight: FontWeight.w800,
    fontSize: 22,
    letterSpacing: -0.3,
    color: HpiColors.onSurface,
  );

  static const appBarTitle = TextStyle(
    fontFamily: _manrope,
    fontWeight: FontWeight.w800,
    fontSize: 18,
    color: HpiColors.onSurface,
  );

  static const cardTitle = TextStyle(
    fontFamily: _manrope,
    fontWeight: FontWeight.w800,
    fontSize: 13.5,
    color: HpiColors.onSurface,
  );

  static const body = TextStyle(
    fontFamily: _manrope,
    fontWeight: FontWeight.w600,
    fontSize: 12.5,
    color: HpiColors.onSurfaceVariant,
  );

  static const supporting = TextStyle(
    fontFamily: _manrope,
    fontWeight: FontWeight.w600,
    fontSize: 10.5,
    color: HpiColors.muted,
  );

  /// Section headers — uppercase, wide tracking. Apply to already-uppercased text.
  static const sectionLabel = TextStyle(
    fontFamily: _manrope,
    fontWeight: FontWeight.w800,
    fontSize: 10.5,
    letterSpacing: 1.2,
    color: HpiColors.muted,
  );

  static const navLabelActive = TextStyle(
    fontFamily: _manrope,
    fontWeight: FontWeight.w800,
    fontSize: 11,
    color: HpiColors.onSurface,
  );

  static const navLabelInactive = TextStyle(
    fontFamily: _manrope,
    fontWeight: FontWeight.w600,
    fontSize: 11,
    color: HpiColors.onSurfaceVariant,
  );

  // --- JetBrains Mono: developer surfaces ---
  static const mono = TextStyle(
    fontFamily: _mono,
    fontWeight: FontWeight.w400,
    fontSize: 10.5,
    color: HpiColors.muted,
  );

  static const monoLog = TextStyle(
    fontFamily: _mono,
    fontWeight: FontWeight.w400,
    fontSize: 10,
    height: 1.9,
    color: HpiColors.muted,
  );

  // --- Saira: brand wordmark (onboarding only) ---
  static const wordmark = TextStyle(
    fontFamily: _saira,
    fontWeight: FontWeight.w700,
    fontSize: 12,
    letterSpacing: 2.5,
    color: HpiColors.muted,
  );

  const HpiText._();
}
