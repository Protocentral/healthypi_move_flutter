// Copyright (c) 2024-2026 ProtoCentral
// SPDX-License-Identifier: MIT

import 'package:flutter/material.dart';
import '../../theme/hpi_colors.dart';
import '../../theme/hpi_text.dart';

/// Shared M3 components for the redesign, built to the handoff's "Shared
/// components" spec. Flat surfaces, hairline separation, full-radius pills.

/// The standard card: `#161B20`, radius 20, no shadow. [highlighted] and
/// [waveform] cover the two bordered exceptions (found-device / dev-log cards).
class HpiCard extends StatelessWidget {
  const HpiCard({
    super.key,
    required this.child,
    this.padding = const EdgeInsets.all(15),
    this.radius = 20,
    this.highlightColor,
    this.waveform = false,
    this.onTap,
  });

  final Widget child;
  final EdgeInsetsGeometry padding;
  final double radius;

  /// If set, draws a 1px border in this color (highlighted / found-device card).
  final Color? highlightColor;

  /// Near-black waveform/log surface with a faint hairline border.
  final bool waveform;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final border = waveform
        ? Border.all(color: HpiColors.dividerStrong, width: 1)
        : (highlightColor != null
            ? Border.all(color: highlightColor!, width: 1)
            : null);
    final shape = RoundedRectangleBorder(
      borderRadius: BorderRadius.circular(radius),
      side: border?.top ?? BorderSide.none,
    );
    return Material(
      color: waveform ? HpiColors.waveformBg : HpiColors.surfaceContainer,
      shape: shape,
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        child: Padding(padding: padding, child: child),
      ),
    );
  }
}

/// A metric-tinted rounded icon square (list-row leading, stat headers).
class HpiIconSquare extends StatelessWidget {
  const HpiIconSquare({
    super.key,
    required this.icon,
    required this.color,
    this.size = 36,
    this.iconSize = 19,
    this.dim = false,
  });

  final IconData icon;
  final Color color;
  final double size;
  final double iconSize;

  /// Zero-state look: desaturated tint + muted glyph (e.g. EDA no-data row).
  final bool dim;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        color: HpiMetricColors.tint(color, dim ? 0.07 : 0.14),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Icon(icon,
          size: iconSize, color: dim ? HpiColors.edaDim : color),
    );
  }
}

/// One row of a grouped list card (shared anatomy). [trailing] is any value /
/// chip; a chevron is appended when [onTap] is set unless [showChevron] is false.
class HpiListRow extends StatelessWidget {
  const HpiListRow({
    super.key,
    required this.icon,
    required this.iconColor,
    required this.title,
    this.supporting,
    this.supportingColor,
    this.trailing,
    this.onTap,
    this.dim = false,
    this.showChevron = true,
  });

  final IconData icon;
  final Color iconColor;
  final String title;
  final String? supporting;
  final Color? supportingColor;
  final Widget? trailing;
  final VoidCallback? onTap;
  final bool dim;
  final bool showChevron;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
        child: Row(
          children: [
            HpiIconSquare(icon: icon, color: iconColor, dim: dim),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(title,
                      style: HpiText.cardTitle.copyWith(
                          color: dim
                              ? HpiColors.onSurfaceVariant
                              : HpiColors.onSurface)),
                  if (supporting != null) ...[
                    const SizedBox(height: 2),
                    Text(supporting!,
                        style: HpiText.supporting
                            .copyWith(color: supportingColor)),
                  ],
                ],
              ),
            ),
            if (trailing != null) ...[
              const SizedBox(width: 10),
              trailing!,
            ],
            if (onTap != null && showChevron) ...[
              const SizedBox(width: 4),
              const Icon(Icons.chevron_right,
                  size: 17, color: HpiColors.disabled),
            ],
          ],
        ),
      ),
    );
  }
}

/// Wraps rows into one card, separated by `~.05` hairlines.
class HpiGroupedCard extends StatelessWidget {
  const HpiGroupedCard({super.key, required this.rows});

  final List<Widget> rows;

  @override
  Widget build(BuildContext context) {
    final children = <Widget>[];
    for (var i = 0; i < rows.length; i++) {
      if (i > 0) {
        children.add(const Divider(
            height: 1, thickness: 1, color: HpiColors.divider, indent: 14));
      }
      children.add(rows[i]);
    }
    return HpiCard(
      padding: EdgeInsets.zero,
      child: Column(mainAxisSize: MainAxisSize.min, children: children),
    );
  }
}

/// Full-width segmented control (Day/Week/Month/6M, filter chips). [accent]
/// lets steps use green, etc. — defaults to amber.
class HpiSegmentedControl extends StatelessWidget {
  const HpiSegmentedControl({
    super.key,
    required this.segments,
    required this.selectedIndex,
    required this.onChanged,
    this.accent = HpiColors.hr,
  });

  final List<String> segments;
  final int selectedIndex;
  final ValueChanged<int> onChanged;
  final Color accent;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(3),
      decoration: BoxDecoration(
        color: HpiColors.chipBg,
        borderRadius: BorderRadius.circular(999),
      ),
      child: Row(
        children: [
          for (var i = 0; i < segments.length; i++)
            Expanded(
              child: GestureDetector(
                onTap: () => onChanged(i),
                behavior: HitTestBehavior.opaque,
                child: AnimatedContainer(
                  duration: const Duration(milliseconds: 150),
                  curve: const Cubic(0.2, 0, 0, 1),
                  height: 32,
                  alignment: Alignment.center,
                  decoration: BoxDecoration(
                    color: i == selectedIndex
                        ? HpiMetricColors.tint(accent, 0.2)
                        : Colors.transparent,
                    borderRadius: BorderRadius.circular(999),
                  ),
                  child: Text(
                    segments[i],
                    style: TextStyle(
                      fontFamily: 'Manrope',
                      fontSize: 12,
                      fontWeight: i == selectedIndex
                          ? FontWeight.w800
                          : FontWeight.w700,
                      color: i == selectedIndex
                          ? accent
                          : HpiColors.onSurfaceVariant,
                    ),
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }
}

/// A pill: neutral by default, or a metric-tinted chip when [color] is given.
class HpiPill extends StatelessWidget {
  const HpiPill({
    super.key,
    required this.label,
    this.color,
    this.icon,
    this.filled = false,
  });

  final String label;
  final Color? color;
  final IconData? icon;

  /// Solid metric background with on-metric text (e.g. the amber "Pair" button).
  final bool filled;

  @override
  Widget build(BuildContext context) {
    final c = color ?? HpiColors.onSurfaceVariant;
    final bg = filled
        ? c
        : (color != null ? HpiMetricColors.tint(c, 0.16) : HpiColors.chipBg);
    final fg = filled ? HpiColors.onHr : (color ?? HpiColors.onSurfaceBright);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
      decoration:
          BoxDecoration(color: bg, borderRadius: BorderRadius.circular(999)),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (icon != null) ...[
            Icon(icon, size: 13, color: fg),
            const SizedBox(width: 4),
          ],
          Text(label,
              style: TextStyle(
                  fontFamily: 'Manrope',
                  fontSize: 11,
                  fontWeight: FontWeight.w800,
                  letterSpacing: 0.3,
                  color: fg)),
        ],
      ),
    );
  }
}

/// Mini stat card: a Rubik value over a wide-tracked uppercase label.
class HpiStatChip extends StatelessWidget {
  const HpiStatChip({
    super.key,
    required this.value,
    required this.label,
    this.unit,
    this.valueColor,
  });

  final String value;
  final String label;
  final String? unit;
  final Color? valueColor;

  @override
  Widget build(BuildContext context) {
    return HpiCard(
      radius: 16,
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 11),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.baseline,
            textBaseline: TextBaseline.alphabetic,
            children: [
              Text(value,
                  style: HpiText.statChip.copyWith(color: valueColor)),
              if (unit != null) ...[
                const SizedBox(width: 3),
                Text(unit!, style: HpiText.mono.copyWith(fontSize: 9.5)),
              ],
            ],
          ),
          const SizedBox(height: 4),
          Text(label.toUpperCase(),
              style: HpiText.sectionLabel.copyWith(fontSize: 9)),
        ],
      ),
    );
  }
}

/// Section header — uppercased, wide tracking.
class HpiSectionLabel extends StatelessWidget {
  const HpiSectionLabel(this.text, {super.key, this.trailing});

  final String text;
  final Widget? trailing;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(2, 0, 2, 8),
      child: Row(
        children: [
          Expanded(
              child: Text(text.toUpperCase(), style: HpiText.sectionLabel)),
          if (trailing != null) trailing!,
        ],
      ),
    );
  }
}

/// Filled primary button (height 52, radius 26, amber).
class HpiFilledButton extends StatelessWidget {
  const HpiFilledButton({
    super.key,
    required this.label,
    this.icon,
    this.onPressed,
    this.color = HpiColors.hr,
  });

  final String label;
  final IconData? icon;
  final VoidCallback? onPressed;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 52,
      child: Material(
        color: color,
        borderRadius: BorderRadius.circular(26),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: onPressed,
          child: Center(
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                if (icon != null) ...[
                  Icon(icon, size: 19, color: HpiColors.onHr),
                  const SizedBox(width: 8),
                ],
                Text(label,
                    style: const TextStyle(
                        fontFamily: 'Manrope',
                        fontSize: 14,
                        fontWeight: FontWeight.w800,
                        color: HpiColors.onHr)),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// Tonal button — metric-tinted background, metric-colored text.
class HpiTonalButton extends StatelessWidget {
  const HpiTonalButton({
    super.key,
    required this.label,
    this.icon,
    this.onPressed,
    this.color = HpiColors.hr,
  });

  final String label;
  final IconData? icon;
  final VoidCallback? onPressed;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 40,
      child: Material(
        color: HpiMetricColors.tint(color, 0.16),
        borderRadius: BorderRadius.circular(999),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: onPressed,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: Center(
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  if (icon != null) ...[
                    Icon(icon, size: 17, color: color),
                    const SizedBox(width: 6),
                  ],
                  Text(label,
                      style: TextStyle(
                          fontFamily: 'Manrope',
                          fontSize: 12,
                          fontWeight: FontWeight.w800,
                          color: color)),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
