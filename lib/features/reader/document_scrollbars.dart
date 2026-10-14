import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:pdfrx/pdfrx.dart';

/// Vertical and horizontal scrollbars for the document.
///
/// Both are driven by the viewer's own position, so they follow wheel, drag,
/// keyboard and contents navigation alike. They sit in the visible part of the
/// reading area: [leftInset] / [rightInset] are the widths of the contents and
/// search panels overlaying the document, so a bar is never hidden under one.
///
/// A bar is only shown on an axis that actually scrolls.
class DocumentScrollbars extends StatelessWidget {
  const DocumentScrollbars({
    super.key,
    required this.controller,
    this.leftInset = 0,
    this.rightInset = 0,
  });

  /// Thickness of a bar, including its track.
  static const double thickness = 12;

  static const double _minThumb = 36;

  final PdfViewerController controller;

  /// Width of a panel overlaying the left edge of the document.
  final double leftInset;

  /// Width of a panel overlaying the right edge of the document.
  final double rightInset;

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: controller,
      builder: (context, _) {
        if (!controller.isReady) return const SizedBox.shrink();
        final Size view;
        final Size doc;
        final Rect visible;
        try {
          view = controller.viewSize;
          doc = controller.documentSize;
          visible = controller.visibleRect;
        } catch (_) {
          return const SizedBox.shrink(); // layout not ready yet
        }
        final zoom = controller.currentZoom;

        // The viewer's scrollable extent: the document plus the insets the
        // panels cover (see `PdfView.contentInsets`). An axis whose content
        // fits the viewport does not scroll.
        final scrollsX =
            (doc.width + leftInset + rightInset) * zoom > view.width + 0.5;
        final scrollsY = doc.height * zoom > view.height + 0.5;
        if (!scrollsX && !scrollsY) return const SizedBox.shrink();

        return Stack(
          children: [
            if (scrollsY)
              Positioned(
                top: 0,
                bottom: scrollsX ? thickness : 0,
                right: rightInset,
                width: thickness,
                child: _Bar(
                  key: const ValueKey('scrollbar-vertical'),
                  vertical: true,
                  min: 0,
                  max: doc.height - visible.height,
                  value: visible.top,
                  extent: visible.height,
                  total: doc.height,
                  onChanged: (v) => _scrollTo(y: v),
                ),
              ),
            if (scrollsX)
              Positioned(
                left: leftInset,
                right: rightInset + (scrollsY ? thickness : 0),
                bottom: 0,
                height: thickness,
                child: _Bar(
                  key: const ValueKey('scrollbar-horizontal'),
                  vertical: false,
                  min: -leftInset,
                  max: doc.width + rightInset - visible.width,
                  value: visible.left,
                  extent: visible.width,
                  total: doc.width + leftInset + rightInset,
                  onChanged: (v) => _scrollTo(x: v),
                ),
              ),
          ],
        );
      },
    );
  }

  /// Moves the visible area's top-left corner to [x] / [y] (document units).
  void _scrollTo({double? x, double? y}) {
    if (!controller.isReady) return;
    final m = controller.value.clone();
    if (x != null) m.x = -x;
    if (y != null) m.y = -y;
    controller.value = m;
  }
}

class _Bar extends StatefulWidget {
  const _Bar({
    super.key,
    required this.vertical,
    required this.min,
    required this.max,
    required this.value,
    required this.extent,
    required this.total,
    required this.onChanged,
  });

  final bool vertical;

  /// Scrollable range of the visible area's leading edge, and its current value.
  final double min;
  final double max;
  final double value;

  /// Visible length and total content length, in the same units.
  final double extent;
  final double total;
  final ValueChanged<double> onChanged;

  @override
  State<_Bar> createState() => _BarState();
}

class _BarState extends State<_Bar> {
  bool _hover = false;
  bool _dragging = false;

  // Geometry of the last build, for the drag handlers.
  double _trackLength = 1;
  double _thumbLength = 1;

  double get _range => math.max(widget.max - widget.min, 0);

  double _thumbOffset() {
    if (_range <= 0) return 0;
    final f = ((widget.value - widget.min) / _range).clamp(0.0, 1.0);
    return f * (_trackLength - _thumbLength);
  }

  /// The content position that puts the thumb's leading edge at [offset].
  double _valueAt(double offset) {
    final free = _trackLength - _thumbLength;
    if (free <= 0) return widget.min;
    return widget.min + (offset / free).clamp(0.0, 1.0) * _range;
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return LayoutBuilder(
      builder: (context, constraints) {
        _trackLength = widget.vertical
            ? constraints.maxHeight
            : constraints.maxWidth;
        final fraction = (widget.extent / math.max(widget.total, 1)).clamp(
          0.0,
          1.0,
        );
        _thumbLength = math.min(
          _trackLength,
          math.max(DocumentScrollbars._minThumb, _trackLength * fraction),
        );
        final offset = _thumbOffset();
        final active = _hover || _dragging;

        final thumb = AnimatedContainer(
          duration: const Duration(milliseconds: 120),
          margin: const EdgeInsets.all(2),
          decoration: BoxDecoration(
            color: scheme.onSurfaceVariant.withAlpha(active ? 230 : 170),
            borderRadius: BorderRadius.circular(DocumentScrollbars.thickness),
          ),
        );

        return MouseRegion(
          onEnter: (_) => setState(() => _hover = true),
          onExit: (_) => setState(() => _hover = false),
          child: GestureDetector(
            behavior: HitTestBehavior.opaque,
            // A click on the track pages by one viewport towards the click.
            onTapDown: (d) {
              final p = widget.vertical
                  ? d.localPosition.dy
                  : d.localPosition.dx;
              if (p >= offset && p <= offset + _thumbLength) return;
              final step = widget.extent * 0.9;
              final target = p < offset
                  ? widget.value - step
                  : widget.value + step;
              widget.onChanged(
                target.clamp(widget.min, math.max(widget.min, widget.max)),
              );
            },
            onPanStart: (_) => setState(() => _dragging = true),
            onPanEnd: (_) => setState(() => _dragging = false),
            onPanCancel: () => setState(() => _dragging = false),
            onPanUpdate: (d) {
              final delta = widget.vertical ? d.delta.dy : d.delta.dx;
              widget.onChanged(_valueAt(_thumbOffset() + delta));
            },
            child: Container(
              // Opaque, so the bar reads against both the page and the backdrop.
              color: scheme.surfaceContainerHigh,
              child: Stack(
                children: [
                  Positioned(
                    left: widget.vertical ? 0 : offset,
                    top: widget.vertical ? offset : 0,
                    width: widget.vertical ? null : _thumbLength,
                    height: widget.vertical ? _thumbLength : null,
                    right: widget.vertical ? 0 : null,
                    bottom: widget.vertical ? null : 0,
                    child: thumb,
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }
}
