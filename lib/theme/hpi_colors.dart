import 'package:flutter/material.dart';

/// The redesign's fixed color tokens. Dark is the only theme for v1.
/// Values are final, from the design handoff README ("Design tokens"). Surfaces
/// are a warm-dark AMOLED ramp matched to the watch UI; separation is by surface
/// steps and hairlines, never shadows.
abstract final class HpiColors {
  // Surfaces (warm-dark ramp).
  static const background = Color(0xFF0E1114); // scaffold
  static const surfaceContainer = Color(0xFF161B20); // all cards
  static const navBar = Color(0xFF12161A); // nav bar / rail
  static const waveformBg = Color(0xFF080B0D); // live/preview/log cards

  // Text & icon ramp.
  static const onSurface = Color(0xFFECF0F2); // primary text
  static const onSurfaceBright = Color(0xFFC6CDD1); // icon buttons, 2nd emphasis
  static const onSurfaceVariant = Color(0xFF9AA4A9); // labels, section headers
  static const muted = Color(0xFF6B7478); // captions, units, timestamps
  static const faint = Color(0xFF5B646A); // chart axis labels
  static const disabled = Color(0xFF4A5359); // trailing chevrons

  // Per-metric identity (identical to the watch UI).
  static const hr = Color(0xFFF59E0B); // heart rate / ECG / primary accent
  static const onHr = Color(0xFF1F1300); // text on filled amber
  static const spo2 = Color(0xFF6FB3CC); // SpO₂ / PPG / battery
  static const eda = Color(0xFF2FBDA8); // EDA / GSR
  static const edaDim = Color(0xFF5B8781); // dim EDA (zero-state icon)
  static const edaBarDim = Color(0xFF1E6B60); // dim EDA bars
  static const stress = Color(0xFF8B84F0); // stress / HRV
  static const steps = Color(0xFF2EB865); // steps / activity / success
  static const temp = Color(0xFFF0845C); // wrist temp
  static const error = Color(0xFFF87171); // errors / warnings

  // Hairlines & neutral chips (white at low alpha).
  static const divider = Color(0x0DFFFFFF); // ~.05 list separators
  static const dividerStrong = Color(0x12FFFFFF); // ~.07 borders
  static const chipBg = Color(0x0FFFFFFF); // ~.06 neutral pills
  static const buttonBg = Color(0x12FFFFFF); // ~.07 neutral buttons

  const HpiColors._();
}

/// The six metric identity colors as a [ThemeExtension], so widgets read them
/// from the theme (`Theme.of(context).extension<HpiMetricColors>()!`) rather
/// than importing constants directly. `tint()` yields the ~14% container fill
/// the design uses behind icons, pills, and chart fills.
@immutable
class HpiMetricColors extends ThemeExtension<HpiMetricColors> {
  const HpiMetricColors({
    required this.hr,
    required this.spo2,
    required this.eda,
    required this.stress,
    required this.steps,
    required this.temp,
    required this.onHr,
  });

  final Color hr;
  final Color spo2;
  final Color eda;
  final Color stress;
  final Color steps;
  final Color temp;
  final Color onHr;

  static const dark = HpiMetricColors(
    hr: HpiColors.hr,
    spo2: HpiColors.spo2,
    eda: HpiColors.eda,
    stress: HpiColors.stress,
    steps: HpiColors.steps,
    temp: HpiColors.temp,
    onHr: HpiColors.onHr,
  );

  /// Identity color for a `hPi4Global.PREFIX_*` / metric key, defaulting to the
  /// amber primary accent for unknown keys.
  Color forKey(String key) {
    switch (key) {
      case 'hr':
        return hr;
      case 'spo2':
        return spo2;
      case 'temp':
        return temp;
      case 'activity':
      case 'steps':
        return steps;
      case 'stress':
      case 'hrv':
        return stress;
      case 'eda':
      case 'gsr':
        return eda;
      default:
        return hr;
    }
  }

  /// The metric color as a low-alpha container fill (default ~14%).
  static Color tint(Color c, [double alpha = 0.14]) => c.withValues(alpha: alpha);

  @override
  HpiMetricColors copyWith({
    Color? hr,
    Color? spo2,
    Color? eda,
    Color? stress,
    Color? steps,
    Color? temp,
    Color? onHr,
  }) {
    return HpiMetricColors(
      hr: hr ?? this.hr,
      spo2: spo2 ?? this.spo2,
      eda: eda ?? this.eda,
      stress: stress ?? this.stress,
      steps: steps ?? this.steps,
      temp: temp ?? this.temp,
      onHr: onHr ?? this.onHr,
    );
  }

  @override
  HpiMetricColors lerp(ThemeExtension<HpiMetricColors>? other, double t) {
    if (other is! HpiMetricColors) return this;
    return HpiMetricColors(
      hr: Color.lerp(hr, other.hr, t)!,
      spo2: Color.lerp(spo2, other.spo2, t)!,
      eda: Color.lerp(eda, other.eda, t)!,
      stress: Color.lerp(stress, other.stress, t)!,
      steps: Color.lerp(steps, other.steps, t)!,
      temp: Color.lerp(temp, other.temp, t)!,
      onHr: Color.lerp(onHr, other.onHr, t)!,
    );
  }
}

/// Sugar for `Theme.of(context).extension<HpiMetricColors>()!`.
extension HpiMetricColorsX on BuildContext {
  HpiMetricColors get metric =>
      Theme.of(this).extension<HpiMetricColors>() ?? HpiMetricColors.dark;
}
