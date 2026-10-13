import 'package:flutter/material.dart';
import 'package:pdfrx/pdfrx.dart';

/// The reading surface: a PDFium-rendered, continuously scrolling document.
///
/// Text selection is enabled and pdfrx's own automatic context menu is
/// suppressed; the app renders its own "Find meaning" action (M3).
class PdfView extends StatelessWidget {
  const PdfView({
    super.key,
    required this.documentRef,
    required this.controller,
    this.onPageChanged,
    this.onViewerReady,
    this.onLoadFailed,
    this.onTextSelectionChange,
    this.onDocumentTap,
    this.initialPage,
  });

  /// Held by the owner for the lifetime of one open document. Creating a new
  /// ref on every build (what `PdfViewer.file` does) stranded the first load
  /// when a rebuild arrived while it was in flight.
  final PdfDocumentRef documentRef;
  final PdfViewerController controller;
  final ValueChanged<int?>? onPageChanged;
  final void Function(PdfDocument document)? onViewerReady;
  final VoidCallback? onLoadFailed;
  final PdfViewerTextSelectionChangeCallback? onTextSelectionChange;

  /// A plain tap on the document (not a drag/selection).
  final VoidCallback? onDocumentTap;

  /// Page to show first (restoring the last position).
  final int? initialPage;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return PdfViewer(
      documentRef,
      controller: controller,
      initialPageNumber: initialPage ?? 1,
      params: PdfViewerParams(
        margin: 12,
        backgroundColor: Colors.transparent,
        textSelectionParams: PdfTextSelectionParams(
          enabled: true,
          showContextMenuAutomatically: false,
          onTextSelectionChange: onTextSelectionChange,
        ),
        onGeneralTap: (context, controller, details) {
          if (details.type == PdfViewerGeneralTapType.tap) {
            onDocumentTap?.call();
          }
          return false; // never swallow the tap: selection handling continues
        },
        onPageChanged: onPageChanged,
        onViewerReady: (document, _) => onViewerReady?.call(document),
        onDocumentLoadFinished: (ref, succeeded) {
          if (!succeeded) onLoadFailed?.call();
        },
        loadingBannerBuilder: (context, downloaded, total) =>
            Center(child: CircularProgressIndicator(color: scheme.primary)),
        // A document that fails to open is reported through onLoadFailed and
        // rendered by the reader screen; never show raw error text here.
        errorBannerBuilder: (context, error, stackTrace, ref) =>
            const SizedBox.shrink(),
      ),
    );
  }
}
