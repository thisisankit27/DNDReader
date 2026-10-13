import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';

import 'pill_placement.dart';
import 'selection_anchor.dart';

/// The floating "Find meaning" action, anchored beside the selection.
///
/// Stack this directly over the viewer (same size and origin). Outside the pill
/// itself it is hit-test transparent, so it never intercepts viewer gestures
/// and never moves focus on its own.
class SelectionPill extends StatelessWidget {
  const SelectionPill({
    super.key,
    required this.anchors,
    required this.repaint,
    required this.onPressed,
    this.onScrollSignal,
  });

  /// Current on-screen anchors, or null when the selection is not on screen.
  final SelectionAnchors? Function() anchors;

  /// Fires when scroll/zoom changes, so the pill follows the selection.
  final Listenable repaint;

  final VoidCallback onPressed;

  /// Mouse-wheel / trackpad signals that land on the pill are handed back here
  /// (the reader passes the viewer's own handler) so the document keeps
  /// scrolling while the cursor happens to rest on the pill.
  final void Function(PointerSignalEvent event)? onScrollSignal;

  /// Test hook and dev-harness handle.
  static final GlobalKey pillKey = GlobalKey(debugLabel: 'selection-pill');

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final viewport = constraints.biggest;
        return ListenableBuilder(
          listenable: repaint,
          builder: (context, _) {
            final a = anchors();
            if (a == null) return const SizedBox.shrink();
            final view = Offset.zero & viewport;
            // Prefer the end of the selection; fall back to its start when only
            // that is on screen; otherwise there is nowhere sensible to put it.
            final anchor = a.end.overlaps(view)
                ? a.end
                : (a.start.overlaps(view) ? a.start : null);
            if (anchor == null) return const SizedBox.shrink();
            return CustomSingleChildLayout(
              delegate: _PillLayoutDelegate(anchor: anchor, avoid: a.bounds),
              child: Listener(
                onPointerSignal: onScrollSignal,
                child: _PillBody(key: pillKey, onPressed: onPressed),
              ),
            );
          },
        );
      },
    );
  }
}

class _PillLayoutDelegate extends SingleChildLayoutDelegate {
  _PillLayoutDelegate({required this.anchor, required this.avoid});

  final Rect anchor;
  final Rect avoid;

  @override
  BoxConstraints getConstraintsForChild(BoxConstraints constraints) =>
      constraints.loosen();

  @override
  Offset getPositionForChild(Size size, Size childSize) {
    return placePill(
      viewport: size,
      pill: childSize,
      anchor: anchor,
      avoid: avoid,
    ).offset;
  }

  @override
  bool shouldRelayout(_PillLayoutDelegate old) =>
      old.anchor != anchor || old.avoid != avoid;
}

class _PillBody extends StatelessWidget {
  const _PillBody({super.key, required this.onPressed});

  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Semantics(
      button: true,
      label: 'Find meaning of the selected text',
      child: Material(
        elevation: 4,
        shadowColor: Colors.black54,
        color: theme.colorScheme.primaryContainer,
        shape: const StadiumBorder(),
        child: InkWell(
          customBorder: const StadiumBorder(),
          onTap: onPressed,
          child: ConstrainedBox(
            constraints: const BoxConstraints(minHeight: 44),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(
                    Icons.search,
                    size: 18,
                    color: theme.colorScheme.onPrimaryContainer,
                  ),
                  const SizedBox(width: 8),
                  Text(
                    'Find meaning',
                    style: theme.textTheme.labelLarge?.copyWith(
                      color: theme.colorScheme.onPrimaryContainer,
                    ),
                  ),
                  const SizedBox(width: 10),
                  Text(
                    'Ctrl+E',
                    style: theme.textTheme.labelSmall?.copyWith(
                      color: theme.colorScheme.onPrimaryContainer.withValues(
                        alpha: 0.7,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
