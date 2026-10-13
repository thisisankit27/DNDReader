import 'package:flutter/material.dart';
import 'package:pdfrx/pdfrx.dart';

/// The reading surface: a PDFium-rendered, continuously scrolling document.
///
/// Text selection is enabled and pdfrx's own automatic context menu is
/// suppressed; the app renders its own "Find meaning" action (M3).
class PdfView extends StatelessWidget {
  const PdfView({
    super.key,
    required this.path,
    required this.controller,
    this.onPageChanged,
    this.onViewerReady,
    this.onLoadFailed,
    this.onTextSelectionChange,
  });

  final String path;
  final PdfViewerController controller;
  final ValueChanged<int?>? onPageChanged;
  final void Function(PdfDocument document)? onViewerReady;
  final VoidCallback? onLoadFailed;
  final PdfViewerTextSelectionChangeCallback? onTextSelectionChange;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return PdfViewer.file(
      path,
      controller: controller,
      params: PdfViewerParams(
        margin: 12,
        backgroundColor: Colors.transparent,
        textSelectionParams: PdfTextSelectionParams(
          enabled: true,
          showContextMenuAutomatically: false,
          onTextSelectionChange: onTextSelectionChange,
        ),
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
