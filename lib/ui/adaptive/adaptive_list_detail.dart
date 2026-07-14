// Copyright (c) 2024-2026 ProtoCentral
// SPDX-License-Identifier: MIT

import 'package:flutter/material.dart';
import '../../theme/hpi_colors.dart';
import 'breakpoints.dart';

/// List-detail pattern used by Home (4a), Trends hub, Recordings, and the dev
/// console. On expanded widths (≥840 dp) the list and detail sit side-by-side
/// and selecting an item swaps the detail **in place**; on compact widths only
/// the list shows and selecting **pushes** the detail as a route.
///
/// [T] is the selectable item. [listBuilder] renders the left pane and receives
/// the current selection (to highlight it) plus an `onSelect` callback.
/// [detailBuilder] renders the detail for a selected item. [emptyDetail] shows
/// when nothing is selected on a two-pane layout.
class AdaptiveListDetail<T> extends StatefulWidget {
  const AdaptiveListDetail({
    super.key,
    required this.listBuilder,
    required this.detailBuilder,
    this.initialSelection,
    this.listPaneWidth = 432,
    this.emptyDetail,
    this.detailTitle,
  });

  final Widget Function(
      BuildContext context, T? selected, ValueChanged<T> onSelect) listBuilder;
  final Widget Function(BuildContext context, T selected) detailBuilder;
  final T? initialSelection;
  final double listPaneWidth;
  final Widget? emptyDetail;

  /// Title for the pushed detail route on compact (ignored when two-pane).
  final String Function(T selected)? detailTitle;

  @override
  State<AdaptiveListDetail<T>> createState() => _AdaptiveListDetailState<T>();
}

class _AdaptiveListDetailState<T> extends State<AdaptiveListDetail<T>> {
  T? _selected;

  @override
  void initState() {
    super.initState();
    _selected = widget.initialSelection;
  }

  void _onSelect(BuildContext context, T item, bool expanded) {
    if (expanded) {
      setState(() => _selected = item);
    } else {
      Navigator.of(context).push(MaterialPageRoute(
        builder: (ctx) => Scaffold(
          backgroundColor: HpiColors.background,
          appBar: widget.detailTitle == null
              ? null
              : AppBar(title: Text(widget.detailTitle!(item))),
          body: SafeArea(child: widget.detailBuilder(ctx, item)),
        ),
      ));
    }
  }

  @override
  Widget build(BuildContext context) {
    final expanded = Breakpoints.isExpanded(context);
    if (!expanded) {
      return widget.listBuilder(
          context, null, (item) => _onSelect(context, item, false));
    }

    // Keep a valid selection so the detail pane is never blank when items exist.
    final selected = _selected;
    return Row(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        SizedBox(
          width: widget.listPaneWidth,
          child: widget.listBuilder(
              context, selected, (item) => _onSelect(context, item, true)),
        ),
        const VerticalDivider(
            width: 1, thickness: 1, color: HpiColors.divider),
        Expanded(
          child: selected == null
              ? (widget.emptyDetail ?? const SizedBox.shrink())
              : widget.detailBuilder(context, selected),
        ),
      ],
    );
  }
}
