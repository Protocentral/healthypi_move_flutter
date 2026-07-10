import 'package:flutter/material.dart';
import '../../theme/hpi_colors.dart';
import '../../theme/hpi_text.dart';
import 'breakpoints.dart';

/// A top-level navigation destination (Home / Trends / Live / Device).
class HpiDestination {
  const HpiDestination({required this.icon, required this.label});
  final IconData icon;
  final String label;
}

/// The app shell that swaps `NavigationBar` (compact) for `NavigationRail`
/// (expanded, ≥840 dp) per the handoff's adaptive spec. Custom-drawn rather
/// than themed M3 widgets so the active amber-tint pill, hairlines, and rail
/// chrome (watch avatar top, battery bottom) match the design exactly.
class HpiAdaptiveScaffold extends StatelessWidget {
  const HpiAdaptiveScaffold({
    super.key,
    required this.destinations,
    required this.selectedIndex,
    required this.onDestinationSelected,
    required this.body,
    this.railLeading,
    this.railTrailing,
  });

  final List<HpiDestination> destinations;
  final int selectedIndex;
  final ValueChanged<int> onDestinationSelected;
  final Widget body;

  /// Rail-only: round watch avatar pinned to the top.
  final Widget? railLeading;

  /// Rail-only: battery status pinned to the bottom.
  final Widget? railTrailing;

  @override
  Widget build(BuildContext context) {
    final expanded = Breakpoints.isExpanded(context);
    if (expanded) {
      return Scaffold(
        backgroundColor: HpiColors.background,
        body: Row(
          children: [
            _HpiNavRail(
              destinations: destinations,
              selectedIndex: selectedIndex,
              onSelected: onDestinationSelected,
              leading: railLeading,
              trailing: railTrailing,
            ),
            Expanded(child: SafeArea(left: false, child: body)),
          ],
        ),
      );
    }
    return Scaffold(
      backgroundColor: HpiColors.background,
      body: SafeArea(bottom: false, child: body),
      bottomNavigationBar: _HpiNavBar(
        destinations: destinations,
        selectedIndex: selectedIndex,
        onSelected: onDestinationSelected,
      ),
    );
  }
}

class _HpiNavBar extends StatelessWidget {
  const _HpiNavBar({
    required this.destinations,
    required this.selectedIndex,
    required this.onSelected,
  });

  final List<HpiDestination> destinations;
  final int selectedIndex;
  final ValueChanged<int> onSelected;

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: const BoxDecoration(
        color: HpiColors.navBar,
        border: Border(top: BorderSide(color: HpiColors.dividerStrong)),
      ),
      child: SafeArea(
        top: false,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceAround,
            children: [
              for (var i = 0; i < destinations.length; i++)
                _NavItem(
                  dest: destinations[i],
                  selected: i == selectedIndex,
                  onTap: () => onSelected(i),
                ),
            ],
          ),
        ),
      ),
    );
  }
}

class _NavItem extends StatelessWidget {
  const _NavItem(
      {required this.dest, required this.selected, required this.onTap});

  final HpiDestination dest;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(999),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 4),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 56,
              height: 30,
              alignment: Alignment.center,
              decoration: BoxDecoration(
                color: selected
                    ? HpiMetricColors.tint(HpiColors.hr, 0.18)
                    : Colors.transparent,
                borderRadius: BorderRadius.circular(999),
              ),
              child: Icon(dest.icon,
                  size: 22,
                  color:
                      selected ? HpiColors.hr : HpiColors.onSurfaceVariant),
            ),
            const SizedBox(height: 4),
            Text(dest.label,
                style: selected
                    ? HpiText.navLabelActive
                    : HpiText.navLabelInactive),
          ],
        ),
      ),
    );
  }
}

class _HpiNavRail extends StatelessWidget {
  const _HpiNavRail({
    required this.destinations,
    required this.selectedIndex,
    required this.onSelected,
    this.leading,
    this.trailing,
  });

  final List<HpiDestination> destinations;
  final int selectedIndex;
  final ValueChanged<int> onSelected;
  final Widget? leading;
  final Widget? trailing;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 84,
      decoration: const BoxDecoration(
        color: HpiColors.navBar,
        border: Border(right: BorderSide(color: HpiColors.dividerStrong)),
      ),
      child: SafeArea(
        right: false,
        child: Column(
          children: [
            const SizedBox(height: 12),
            if (leading != null) ...[leading!, const SizedBox(height: 20)],
            for (var i = 0; i < destinations.length; i++)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 6),
                child: _RailItem(
                  dest: destinations[i],
                  selected: i == selectedIndex,
                  onTap: () => onSelected(i),
                ),
              ),
            const Spacer(),
            if (trailing != null) ...[trailing!, const SizedBox(height: 16)],
          ],
        ),
      ),
    );
  }
}

class _RailItem extends StatelessWidget {
  const _RailItem(
      {required this.dest, required this.selected, required this.onTap});

  final HpiDestination dest;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(999),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 52,
            height: 30,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: selected
                  ? HpiMetricColors.tint(HpiColors.hr, 0.18)
                  : Colors.transparent,
              borderRadius: BorderRadius.circular(999),
            ),
            child: Icon(dest.icon,
                size: 22,
                color: selected ? HpiColors.hr : HpiColors.onSurfaceVariant),
          ),
          const SizedBox(height: 4),
          Text(dest.label,
              style: (selected
                      ? HpiText.navLabelActive
                      : HpiText.navLabelInactive)
                  .copyWith(fontSize: 10.5)),
        ],
      ),
    );
  }
}
