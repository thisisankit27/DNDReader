import 'dart:math' as math;
import 'dart:ui';

/// Where the "Find meaning" pill goes, in the viewer's local coordinates.
class PillPlacement {
  const PillPlacement({
    required this.offset,
    required this.above,
    required this.overlapsAnchor,
  });

  /// Top-left of the pill.
  final Offset offset;

  /// True when the pill was flipped above the selection.
  final bool above;

  /// True only in the degenerate case where neither side had room and the pill
  /// was clamped on top of the selection.
  final bool overlapsAnchor;
}

/// Places a [pill]-sized widget next to a selection.
///
/// - Preferred: directly below [anchor] (the last selected character), centred
///   on it, [gap] away.
/// - If there is no room below, flipped above [avoid] (the selection's top).
/// - Always clamped horizontally and vertically inside [viewport] by [margin].
/// - Never overlaps the selection unless neither side fits (then it is clamped
///   inside the viewport and [PillPlacement.overlapsAnchor] says so).
PillPlacement placePill({
  required Size viewport,
  required Size pill,
  required Rect anchor,
  Rect? avoid,
  double gap = 8,
  double margin = 8,
}) {
  final maxX = math.max(margin, viewport.width - pill.width - margin);
  final x = (anchor.center.dx - pill.width / 2).clamp(margin, maxX).toDouble();

  final below = anchor.bottom + gap;
  if (below + pill.height <= viewport.height - margin) {
    return PillPlacement(
      offset: Offset(x, below),
      above: false,
      overlapsAnchor: false,
    );
  }

  final selectionTop = (avoid ?? anchor).top;
  final above = selectionTop - gap - pill.height;
  if (above >= margin) {
    return PillPlacement(
      offset: Offset(x, above),
      above: true,
      overlapsAnchor: false,
    );
  }

  final maxY = math.max(margin, viewport.height - pill.height - margin);
  final y = below.clamp(margin, maxY).toDouble();
  final pillRect = Rect.fromLTWH(x, y, pill.width, pill.height);
  return PillPlacement(
    offset: Offset(x, y),
    above: false,
    overlapsAnchor: pillRect.overlaps(avoid ?? anchor),
  );
}
