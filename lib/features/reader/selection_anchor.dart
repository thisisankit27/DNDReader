import 'package:flutter/painting.dart';
import 'package:pdfrx/pdfrx.dart';

/// Where the ends of the current text selection are on screen.
///
/// Both rectangles are in the **viewer's local coordinates** (the same space a
/// widget stacked directly over the viewer is positioned in) and describe the
/// first and last selected characters. They are recomputed from the viewer's
/// current transform, so they stay correct under scroll and zoom as long as the
/// caller recomputes when the controller notifies.
class SelectionAnchors {
  const SelectionAnchors({required this.start, required this.end});

  final Rect start;
  final Rect end;

  /// The union of both end characters (for a one-line selection, the whole selection).
  Rect get bounds => start.expandToInclude(end);
}

/// Returns the on-screen anchors of [selection], or null when there is no
/// selection or the viewer is not ready.
///
/// Uses only pdfrx's public API: `textSelectionPointRange` supplies the page
/// text and character index, `PdfPageText.charRects` the glyph box in PDF page
/// coordinates, and the controller converts page → document → viewer-local.
SelectionAnchors? selectionAnchors(
  PdfViewerController controller,
  PdfTextSelection selection,
) {
  if (!controller.isReady || !selection.hasSelectedText) return null;
  final range = selection.textSelectionPointRange;
  if (range == null || !range.start.isValid || !range.end.isValid) return null;

  Rect? toLocal(PdfTextSelectionPoint point) {
    final charRect = point.text.charRects[point.index];
    final documentRect = controller.calcRectForRectInsidePage(
      pageNumber: point.text.pageNumber,
      rect: charRect,
    );
    final topLeft = controller.documentToLocal(documentRect.topLeft);
    final bottomRight = controller.documentToLocal(documentRect.bottomRight);
    return Rect.fromPoints(topLeft, bottomRight);
  }

  final start = toLocal(range.start);
  final end = toLocal(range.end);
  if (start == null || end == null) return null;
  return SelectionAnchors(start: start, end: end);
}
