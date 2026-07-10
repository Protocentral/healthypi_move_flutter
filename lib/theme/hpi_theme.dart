import 'package:flutter/material.dart';
import 'hpi_colors.dart';
import 'hpi_text.dart';

/// The redesign's Material 3 dark theme. Seeds from the amber primary accent as
/// the handoff specifies, then overrides the surface ramp with the exact AMOLED
/// values (fromSeed would otherwise pick tonal surfaces). Flat — no shadows;
/// `HpiMetricColors` rides along as a theme extension.
abstract final class HpiTheme {
  static ThemeData dark() {
    final scheme = ColorScheme.fromSeed(
      seedColor: HpiColors.hr,
      brightness: Brightness.dark,
    ).copyWith(
      surface: HpiColors.background,
      surfaceContainer: HpiColors.surfaceContainer,
      surfaceContainerHighest: HpiColors.surfaceContainer,
      primary: HpiColors.hr,
      onPrimary: HpiColors.onHr,
      onSurface: HpiColors.onSurface,
      onSurfaceVariant: HpiColors.onSurfaceVariant,
      error: HpiColors.error,
      outline: HpiColors.dividerStrong,
    );

    return ThemeData(
      useMaterial3: true,
      brightness: Brightness.dark,
      colorScheme: scheme,
      scaffoldBackgroundColor: HpiColors.background,
      canvasColor: HpiColors.background,
      dividerColor: HpiColors.divider,
      fontFamily: 'Manrope',
      splashFactory: InkRipple.splashFactory,
      // M3 standard easing, no bounces (handoff "Motion").
      pageTransitionsTheme: const PageTransitionsTheme(
        builders: {
          TargetPlatform.android: ZoomPageTransitionsBuilder(),
          TargetPlatform.iOS: CupertinoPageTransitionsBuilder(),
        },
      ),
      appBarTheme: const AppBarTheme(
        backgroundColor: HpiColors.background,
        elevation: 0,
        scrolledUnderElevation: 0,
        centerTitle: false,
        titleTextStyle: HpiText.appBarTitle,
        iconTheme: IconThemeData(color: HpiColors.onSurfaceBright, size: 22),
      ),
      textTheme: _textTheme(),
      extensions: const [HpiMetricColors.dark],
    );
  }

  /// Maps the Material text roles onto the ramp so stray `Text` widgets that
  /// don't use an `HpiText` style still land on-brand. Display/headline roles
  /// use Rubik (numeric); title/body/label use Manrope.
  static TextTheme _textTheme() {
    return const TextTheme(
      displayLarge: HpiText.heroNumber,
      displayMedium: HpiText.heroNumberSm,
      displaySmall: HpiText.cardValue,
      headlineMedium: HpiText.cardValue,
      titleLarge: HpiText.screenTitle,
      titleMedium: HpiText.appBarTitle,
      titleSmall: HpiText.cardTitle,
      bodyMedium: HpiText.body,
      bodySmall: HpiText.supporting,
      labelLarge: HpiText.navLabelActive,
      labelSmall: HpiText.sectionLabel,
    );
  }

  const HpiTheme._();
}
