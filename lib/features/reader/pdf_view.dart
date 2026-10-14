import 'dart:io' show Platform;

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
    this.contentInsets = EdgeInsets.zero,
    this.contextMenuOpen,
    this.onFindMeaning,
  });

  /// Mouse-wheel scroll multiplier, per platform, aiming at ~100 px per notch
  /// (close to a browser).
  ///
  /// The embedders differ: the Linux one reports about 53 px per notch, so
  /// pdfrx's default of 0.2 gave ~10 px, which read as painfully slow; 2.0 gives
  /// ~105. The Windows embedder reports `lines-per-notch × 100/3` px — 100 px at
  /// the default of 3 lines, and it follows the user's system setting
  /// (`flutter_window.cc`, `UpdateScrollOffsetMultiplier`) — so 1.0 gives ~100.
  static double wheelScrollFactorFor({required bool windows}) =>
      windows ? 1.0 : 2.0;

  static final double wheelScrollFactor = wheelScrollFactorFor(
    windows: Platform.isWindows,
  );

  /// Pixels moved per arrow-key press.
  static const double arrowKeyStep = 60;

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

  /// Space on the left/right covered by overlay panels (contents, search).
  /// Added as scrollable room so everything under a panel can be panned clear
  /// of it; the document is not resized.
  final EdgeInsets contentInsets;

  /// Set to true while the right-click menu is on screen, so the owner can
  /// move anything of its own that would sit on top of it (the action pill).
  final ValueNotifier<bool>? contextMenuOpen;

  /// Offered in the right-click menu whenever text is selected (not only once
  /// the pill has appeared, which waits for the selection to settle).
  final VoidCallback? onFindMeaning;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return PdfViewer(
      documentRef,
      controller: controller,
      initialPageNumber: initialPage ?? 1,
      params: PdfViewerParams(
        margin: 12,
        boundaryMargin: contentInsets == EdgeInsets.zero ? null : contentInsets,
        scrollByMouseWheel: wheelScrollFactor,
        scrollByArrowKey: arrowKeyStep,
        backgroundColor: Colors.transparent,
        textSelectionParams: PdfTextSelectionParams(
          enabled: true,
          showContextMenuAutomatically: false,
          onTextSelectionChange: onTextSelectionChange,
        ),
        buildContextMenu: _buildContextMenu,
        onGeneralTap: (context, controller, details) {
          switch (details.type) {
            case PdfViewerGeneralTapType.tap:
              onDocumentTap?.call();
            case PdfViewerGeneralTapType.doubleTap:
              // pdfrx leaves double-click unhandled (only touch long-press
              // selects a word); a reader expects it to select the word.
              if (details.tapOn != PdfViewerPart.background) {
                controller.textSelectionDelegate.selectWord(
                  details.documentPosition,
                );
                return true;
              }
            case _:
              break;
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

  Widget? _buildContextMenu(
    BuildContext context,
    PdfViewerContextMenuBuilderParams params,
  ) {
    final delegate = params.textSelectionDelegate;
    final entries = <_MenuEntry>[
      if (params.isTextSelectionEnabled &&
          delegate.isCopyAllowed &&
          delegate.hasSelectedText)
        _MenuEntry('Copy', 'Ctrl+C', () {
          delegate.copyTextSelection();
          params.dismissContextMenu();
        }),
      if (delegate.hasSelectedText && onFindMeaning != null)
        _MenuEntry('Find meaning', 'Ctrl+E', () {
          params.dismissContextMenu();
          onFindMeaning?.call();
        }),
      if (params.isTextSelectionEnabled && !delegate.isSelectingAllText)
        _MenuEntry('Select all', 'Ctrl+A', () {
          delegate.selectAllText();
          params.dismissContextMenu();
        }),
    ];
    if (entries.isEmpty) return null;
    return _MenuPresence(
      open: contextMenuOpen,
      child: _ContextMenu(entries: entries),
    );
  }
}

class _MenuEntry {
  const _MenuEntry(this.label, this.hint, this.onPressed);

  final String label;
  final String hint;
  final VoidCallback onPressed;
}

/// The right-click menu: a plain card. pdfrx places it at the click and keeps
/// it inside the viewer (it measures the widget), so this only draws it. Drawn
/// here, not by pdfrx's adaptive toolbar, so it is legible in both themes.
class _ContextMenu extends StatelessWidget {
  const _ContextMenu({required this.entries});

  static const double _width = 220;
  static const double _rowHeight = 40;

  final List<_MenuEntry> entries;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return SizedBox(
      width: _width,
      child: Material(
        key: const ValueKey('context-menu'),
        color: theme.colorScheme.surfaceContainerHigh,
        elevation: 6,
        borderRadius: BorderRadius.circular(8),
        clipBehavior: Clip.antiAlias,
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 4),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              for (final e in entries)
                InkWell(
                  onTap: e.onPressed,
                  child: SizedBox(
                    height: _rowHeight,
                    child: Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 16),
                      child: Row(
                        children: [
                          Expanded(
                            child: Text(
                              e.label,
                              style: theme.textTheme.bodyMedium,
                            ),
                          ),
                          Text(
                            e.hint,
                            style: theme.textTheme.labelSmall?.copyWith(
                              color: theme.colorScheme.onSurfaceVariant,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Reports, through [open], that its child (the context menu) is on screen.
class _MenuPresence extends StatefulWidget {
  const _MenuPresence({required this.open, required this.child});

  final ValueNotifier<bool>? open;
  final Widget child;

  @override
  State<_MenuPresence> createState() => _MenuPresenceState();
}

class _MenuPresenceState extends State<_MenuPresence> {
  ValueNotifier<bool>? _open;

  @override
  void initState() {
    super.initState();
    _open = widget.open;
    // Not during build: listeners rebuild.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _open?.value = true;
    });
  }

  @override
  void dispose() {
    final open = _open;
    if (open != null) {
      // The tree is locked while disposing; notify afterwards.
      WidgetsBinding.instance.addPostFrameCallback((_) => open.value = false);
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => widget.child;
}
