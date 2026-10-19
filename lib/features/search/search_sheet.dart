import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';

import 'search_panel.dart';
import 'search_session.dart';

/// The search panel as a draggable bottom sheet (phones).
///
/// It overlays the document, which never reflows. It rests at one of [snapFractions] of the available
/// height; dragging the handle moves it, release snaps to the nearest (a fast fling goes the way it was
/// thrown), and dragging below [closeBelow] closes it. The browser inside is the one long-lived one: only the
/// handle is draggable, so the page scrolls normally.
class SearchSheet extends StatefulWidget {
  const SearchSheet({
    super.key,
    required this.session,
    required this.onClose,
    required this.availableHeight,
    required this.fraction,
    required this.onSettled,
  });

  /// Resting heights, as fractions of [availableHeight].
  static const List<double> snapFractions = [0.5, 0.92];

  /// Released below this fraction, the sheet closes.
  static const double closeBelow = 0.3;

  static const double handleHeight = 28;

  final SearchSession session;
  final VoidCallback onClose;

  /// Height the sheet may use (the area below the header).
  final double availableHeight;

  /// The resting fraction currently in effect.
  final double fraction;

  /// Called with the new resting fraction when a drag ends on a snap point.
  final ValueChanged<double> onSettled;

  /// The snap fraction a release at [fraction] with vertical [velocity] (px/s, positive = down) goes to,
  /// or null to close. Pure.
  static double? snapFor(double fraction, double velocity) {
    if (velocity > 900) {
      return fraction > snapFractions.first + 0.05 ? snapFractions.first : null;
    }
    if (velocity < -900) return snapFractions.last;
    if (fraction < closeBelow) return null;
    var best = snapFractions.first;
    for (final f in snapFractions) {
      if ((f - fraction).abs() < (best - fraction).abs()) best = f;
    }
    return best;
  }

  @override
  State<SearchSheet> createState() => _SearchSheetState();
}

class _SearchSheetState extends State<SearchSheet>
    with SingleTickerProviderStateMixin {
  late final AnimationController _settle = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 220),
  );
  late double _fraction = widget.fraction;
  double _from = 0;
  double _to = 0;

  @override
  void initState() {
    super.initState();
    _settle.addListener(() {
      setState(() {
        _fraction =
            _from +
            (_to - _from) * Curves.easeOutCubic.transform(_settle.value);
      });
    });
  }

  @override
  void didUpdateWidget(SearchSheet old) {
    super.didUpdateWidget(old);
    if (old.fraction != widget.fraction && !_settle.isAnimating) {
      _fraction = widget.fraction;
    }
  }

  @override
  void dispose() {
    _settle.dispose();
    super.dispose();
  }

  void _drag(DragUpdateDetails d) {
    _settle.stop();
    setState(() {
      _fraction = (_fraction - d.delta.dy / math.max(1, widget.availableHeight))
          .clamp(0.12, SearchSheet.snapFractions.last);
    });
  }

  void _snapTo(double target) {
    _from = _fraction;
    _to = target;
    // System "remove animations" (MediaQuery.disableAnimations): jump, do not animate.
    _settle.duration = MediaQuery.disableAnimationsOf(context)
        ? Duration.zero
        : const Duration(milliseconds: 220);
    unawaited(
      _settle.forward(from: 0).whenComplete(() {
        if (mounted) widget.onSettled(target);
      }),
    );
  }

  void _release(DragEndDetails d) {
    final target = SearchSheet.snapFor(
      _fraction,
      d.velocity.pixelsPerSecond.dy,
    );
    if (target == null) {
      widget.onClose();
      // Reopening starts from the last resting height, not from where it was closed.
      setState(() => _fraction = widget.fraction);
      return;
    }
    _snapTo(target);
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final height = (widget.availableHeight * _fraction).clamp(
      0.0,
      widget.availableHeight,
    );
    return Align(
      alignment: Alignment.bottomCenter,
      child: SizedBox(
        height: height,
        width: double.infinity,
        child: Material(
          color: theme.colorScheme.surface,
          elevation: 12,
          clipBehavior: Clip.antiAlias,
          borderRadius: const BorderRadius.vertical(top: Radius.circular(16)),
          child: Column(
            children: [
              Semantics(
                label: 'Search results size',
                // A screen reader cannot drag: it gets increase / decrease actions instead.
                onIncrease: () => _snapTo(SearchSheet.snapFractions.last),
                onDecrease: () => _snapTo(SearchSheet.snapFractions.first),
                child: GestureDetector(
                  behavior: HitTestBehavior.opaque,
                  onVerticalDragUpdate: _drag,
                  onVerticalDragEnd: _release,
                  child: SizedBox(
                    height: SearchSheet.handleHeight,
                    width: double.infinity,
                    child: Center(
                      child: Container(
                        width: 36,
                        height: 4,
                        decoration: BoxDecoration(
                          color: theme.colorScheme.outlineVariant,
                          borderRadius: BorderRadius.circular(2),
                        ),
                      ),
                    ),
                  ),
                ),
              ),
              Expanded(
                child: SearchPanel(
                  session: widget.session,
                  onClose: widget.onClose,
                  touch: true,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
