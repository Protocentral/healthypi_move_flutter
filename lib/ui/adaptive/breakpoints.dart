import 'package:flutter/widgets.dart';

/// M3 window-size classes for the adaptive layout (docs/REDESIGN_PLAN.md).
/// The handoff switches nav and single→two-pane at **≥840 dp**; below that is the
/// compact phone layout. [compactMax] is kept for any future medium-band tuning.
enum WindowSize { compact, medium, expanded }

abstract final class Breakpoints {
  static const double compactMax = 600;

  /// At/above this width: NavigationRail replaces NavigationBar, and list-detail
  /// screens become two-pane instead of pushing a route.
  static const double expandedMin = 840;

  static WindowSize of(BuildContext context) =>
      fromWidth(MediaQuery.sizeOf(context).width);

  static WindowSize fromWidth(double width) {
    if (width >= expandedMin) return WindowSize.expanded;
    if (width >= compactMax) return WindowSize.medium;
    return WindowSize.compact;
  }

  /// Whether to use the expanded (rail + two-pane) layout.
  static bool isExpanded(BuildContext context) =>
      MediaQuery.sizeOf(context).width >= expandedMin;

  const Breakpoints._();
}
