import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:pdfrx/pdfrx.dart';

import '../../dev/dev_harness.dart';
import '../../dev/selection_debug.dart';
import '../../services/document_access.dart';
import '../../services/pdf_picker.dart';
import '../../services/window_service.dart';
import 'document_scrollbars.dart';
import 'empty_state.dart';
import 'open_failure.dart';
import 'outline_panel.dart';
import 'pdf_view.dart';
import 'reader_header.dart';
import 'reader_menu.dart';
import '../../build_info.dart';
import '../../services/settings_service.dart';
import 'selection_action_controller.dart';
import 'selection_anchor.dart';
import 'selection_pill.dart';
import '../search/embedded_browser_info.dart';
import '../search/search_panel.dart';
import '../search/search_presentation.dart';
import '../search/search_sheet.dart';
import '../search/search_session.dart';
import '../../services/path_names.dart';
import '../../services/search_url.dart';

/// The single screen: header on top, reading surface below.
class ReaderScreen extends StatefulWidget {
  const ReaderScreen({
    super.key,
    this.initialPath,
    this.pickPdf = pickPdfPath,
    this.actionController,
    this.searchSession,
    this.settings,
    this.documents,
    this.searchPresentation = SearchPresentation.sidePanel,
  });

  /// A document to open at start-up (command-line argument / "Open With").
  final String? initialPath;

  /// Injected so tests need no native dialog.
  final PdfPicker pickPdf;

  /// Test seam: lets a widget test drive the "Find meaning" state without a
  /// native PDF viewer. Production code leaves this null.
  @visibleForTesting
  final SelectionActionController? actionController;

  /// Test seam for the search session (a fake web view). Null in production.
  @visibleForTesting
  final SearchSession? searchSession;

  /// Persisted preferences; an in-memory service when null (tests).
  final SettingsService? settings;

  /// Where documents come from where they are not plain files (Android); null on desktop.
  final DocumentAccess? documents;

  /// Side panel (desktop) or, on phone-width windows, a bottom sheet (Android).
  final SearchPresentation searchPresentation;

  @override
  State<ReaderScreen> createState() => _ReaderScreenState();
}

class _ReaderScreenState extends State<ReaderScreen> {
  String? _path;

  /// Bumped on every open. The viewer is keyed on it, so opening the same file
  /// again builds a fresh viewer for the fresh controller (reusing the old
  /// viewer state left the new controller detached: zoom and page indicator dead).
  int _openSerial = 0;
  PdfViewerController _controller = PdfViewerController();

  /// One ref per opened document, created when the document is opened.
  PdfDocumentRef? _documentRef;
  int? _pageNumber;
  int? _pageCount;
  bool _failed = false;

  /// The document outline; null until loaded.
  List<PdfOutlineNode>? _outline;
  bool _outlineVisible = false;
  PdfTextSelection? _selection;
  final SelectionDebugState _debug = SelectionDebugState();
  late final SelectionActionController _action =
      widget.actionController ?? SelectionActionController();
  late final SearchSession _search = widget.searchSession ?? SearchSession();
  late final SettingsService _settings =
      widget.settings ?? SettingsService.inMemory();

  final WindowService _window = WindowService();

  /// True while the right-click menu is showing; the pill steps aside for it.
  final ValueNotifier<bool> _contextMenuOpen = ValueNotifier(false);

  /// The reader's own focus. The embedded browser takes primary focus when it
  /// is clicked and, while it holds it, the native layer hands it every key.
  /// Closing the panel or finishing an edit returns focus here.
  final FocusNode _readerFocus = FocusNode(debugLabel: 'reader');

  StreamSubscription<DocumentEvent>? _documentsSub;

  /// Resting height of the search sheet, as a fraction of the reading area.
  double _sheetFraction = SearchSheet.snapFractions.first;
  int? _initialPage;
  Timer? _persistTimer;
  double? _persistedZoom;

  @override
  void initState() {
    super.initState();
    _search.addListener(_onSearchChanged);
    _window.addListener(_onWindowChanged);
    final initial = widget.initialPath;
    if (initial != null) {
      _path = initial;
    } else {
      // Reopen where the last run left off, if that document still exists.
      final last = _settings.settings.lastDocument;
      if (last != null && File(last).existsSync()) {
        _path = last;
        _initialPage = _settings.settings.lastPage;
      } else if (last != null) {
        _settings.clearLastPosition();
      }
    }
    if (_path != null) {
      _documentRef = PdfDocumentRefFile(_path!);
      _trackDocument(_path!);
    }
    _controller.addListener(_onViewerTransform);
    _documentsSub = widget.documents?.incoming.listen(_onIncomingDocument);
  }

  /// A document that arrived while running (a second intent), or one that failed to import.
  void _onIncomingDocument(DocumentEvent event) {
    if (!mounted) return;
    final path = event.path;
    if (path != null) {
      _openPath(path);
    } else {
      _showNotice(event.error ?? 'Couldn’t open that file.');
    }
  }

  void _showNotice(String message) {
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(message)));
  }

  void _trackDocument(String path) {
    _settings.addRecent(path);
    // Stored copies nothing refers to any more are removed (Android only).
    final last = _settings.settings.lastDocument;
    unawaited(
      widget.documents?.prune([..._settings.settings.recents, path, ?last]) ??
          Future<void>.value(),
    );
  }

  /// Debounced persistence of page and zoom.
  void _onViewerTransform() {
    _persistTimer?.cancel();
    _persistTimer = Timer(const Duration(milliseconds: 600), _persistPosition);
  }

  void _persistPosition() {
    final path = _path;
    if (path == null || _failed || !_controller.isReady) return;
    final page = _controller.pageNumber;
    if (page != null) _settings.setLastPosition(path, page);
    final zoom = _controller.currentZoom;
    if (_persistedZoom == null || (zoom - _persistedZoom!).abs() > 0.001) {
      _persistedZoom = zoom;
      _settings.setZoom(zoom);
    }
  }

  void _applySavedZoom() {
    final zoom = _settings.settings.zoom;
    if (zoom == null || !_controller.isReady) return;
    _persistedZoom = zoom;
    _controller.setZoom(
      _controller.centerPosition,
      zoom,
      duration: Duration.zero,
    );
  }

  bool _searchWasVisible = false;

  void _onSearchChanged() {
    final visible = _search.visible;
    if (_searchWasVisible && !visible) {
      // The native webview may still hold OS focus while hidden.
      unawaited(_search.webView?.releaseFocus() ?? Future<void>.value());
      _focusReader();
    }
    _searchWasVisible = visible;
  }

  void _onWindowChanged() {
    if (mounted) setState(() {});
  }

  /// Takes primary focus back from the embedded browser (or the page field).
  void _focusReader() {
    if (mounted && !_readerFocus.hasFocus) _readerFocus.requestFocus();
  }

  /// The page field is done (Enter, Esc, or a tap elsewhere): put keyboard
  /// focus back on the document.
  ///
  /// [_focusReader] is not enough here. The field sits under [_readerFocus], so
  /// while it is focused `_readerFocus.hasFocus` is true and that call does
  /// nothing; the field's own `unfocus()` then hands primary focus to the route's
  /// focus scope, which is *above* the shortcuts, so Ctrl+R/E/T and the arrow
  /// keys went nowhere until the document was clicked. Focusing the viewer's own
  /// node is what a click on the document does.
  void _onPageEditDone() {
    if (!mounted) return;
    if (_path != null && !_failed && _controller.isReady) {
      _controller.requestFocus();
    } else {
      _readerFocus.requestFocus();
    }
  }

  void _goToPage(int page) {
    if (!_controller.isReady) return;
    _controller.goToPage(pageNumber: page);
  }

  /// Turns every page a quarter turn. The viewer re-lays itself out when the
  /// document's pages change; rotation is a view setting, never written to the
  /// file, and a document opened again starts upright.
  void _rotate({bool clockwise = true}) {
    if (!_controller.isReady || _failed) return;
    final document = _controller.document;
    document.pages = [
      for (final page in document.pages)
        clockwise ? page.rotatedCW90() : page.rotatedCCW90(),
    ];
    // The old zoom was chosen for the old orientation; refit once the viewer
    // has laid the turned pages out.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _fitPage();
    });
  }

  void _fitPage() {
    if (!_controller.isReady) return;
    final matrix = _controller.calcMatrixForFit(pageNumber: _pageNumber ?? 1);
    if (matrix != null) _controller.goTo(matrix);
  }

  @override
  void dispose() {
    _search.removeListener(_onSearchChanged);
    _window.removeListener(_onWindowChanged);
    _window.dispose();
    _contextMenuOpen.dispose();
    _readerFocus.dispose();
    _persistTimer?.cancel();
    unawaited(_documentsSub?.cancel());
    _controller.removeListener(_onViewerTransform);
    if (widget.actionController == null) _action.dispose();
    if (widget.searchSession == null) _search.dispose();
    super.dispose();
  }

  String get _title {
    final path = _path;
    if (path == null) return 'DNDReader';
    return baseName(path);
  }

  /// Page count of the open document; null when nothing is open.
  int? get _headerPageCount => _path == null || _failed ? null : _pageCount;

  Future<void> _openPicker() async {
    final String? picked;
    try {
      picked = await (widget.documents?.pick ?? widget.pickPdf)();
    } on DocumentImportException catch (e) {
      if (mounted) _showNotice(e.message);
      return;
    }
    if (picked == null || !mounted) return;
    _openPath(picked);
  }

  void _openPath(String path) {
    _controller.removeListener(_onViewerTransform);
    setState(() {
      _path = path;
      _documentRef = PdfDocumentRefFile(path);
      _initialPage = null;
      _openSerial++;
      _controller = PdfViewerController()..addListener(_onViewerTransform);
      _pageNumber = null;
      _pageCount = null;
      _outline = null;
      _outlineVisible = false;
      _failed = false;
      _selection = null;
    });
    _debug.reset();
    _action.reset();
    _search.close();
    _trackDocument(path);
    _settings.setLastPosition(path, 1);
  }

  /// "Find meaning": builds the search URL for the held query and opens the panel.
  void _findMeaning() {
    if (!_action.available) return;
    final query = _action.query!;
    final uri = searchUriFor(query);
    if (uri == null) return;
    _search.search(uri, query);
  }

  /// "Find meaning" from the right-click menu: reads the selection as it is
  /// now, so it works even before the pill's debounce has settled.
  Future<void> _findMeaningNow() async {
    final query = await _action.resolveQueryNow();
    if (query == null || !mounted) return;
    final uri = searchUriFor(query);
    if (uri != null) unawaited(_search.search(uri, query));
  }

  void _zoomIn() {
    if (_controller.isReady) _controller.zoomUp();
  }

  void _zoomOut() {
    if (_controller.isReady) _controller.zoomDown();
  }

  void _toggleOutline() {
    if (_path == null || _failed) return;
    setState(() => _outlineVisible = !_outlineVisible);
  }

  Future<void> _loadOutline(PdfDocument document) async {
    List<PdfOutlineNode> outline;
    try {
      outline = await document.loadOutline();
    } catch (_) {
      outline = const [];
    }
    if (!mounted || _controller.document != document) return;
    setState(() => _outline = outline);
  }

  void _goToOutlineDest(PdfDest dest) {
    if (_controller.isReady) _controller.goToDest(dest);
  }

  Future<void> _showAbout() async {
    // Resolved first: on Windows the Runtime's version is asked of the Runtime.
    final browser = await embeddedBrowserDescription();
    if (!mounted) return;
    showAboutDialog(
      context: context,
      applicationName: 'DNDReader',
      applicationVersion: kAppVersion,
      applicationLegalese:
          'Search results are shown by Google in an embedded browser.\n'
          '$browser',
    );
  }

  /// Esc: leave full screen if in it; otherwise close the search panel, then
  /// the contents, then hide the action and drop the selection.
  void _escape() {
    if (_window.fullscreen) {
      _window.setFullscreen(false);
      return;
    }
    if (_search.visible) {
      _search.close();
      return;
    }
    if (_outlineVisible) {
      setState(() => _outlineVisible = false);
      return;
    }
    _action.dismiss();
    if (_controller.isReady) {
      _controller.textSelectionDelegate.clearTextSelection();
    }
  }

  /// Panel insets last handed to the viewer (see [_syncInsets]).
  EdgeInsets _appliedInsets = EdgeInsets.zero;

  /// pdfrx applies a changed boundary margin only on its next interaction, so
  /// a panel opening would leave the page under it. Re-applying the current
  /// position makes the viewer re-clamp now: the page centres in the space the
  /// panels leave free, and is scrollable if it is wider than that.
  void _syncInsets(EdgeInsets insets) {
    if (insets == _appliedInsets) return;
    _appliedInsets = insets;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || _path == null || !_controller.isReady) return;
      _controller.value = _controller.value.clone();
    });
  }

  @override
  Widget build(BuildContext context) {
    final hasDocument = _path != null && !_failed;

    Widget bodyFor(EdgeInsets insets) {
      if (_path == null) {
        return EmptyState(
          onOpen: _openPicker,
          recents: _settings.settings.recents
              .where((p) => File(p).existsSync())
              .toList(growable: false),
          onOpenRecent: _openPath,
        );
      } else if (_failed) {
        return OpenFailure(fileName: _title, onOpenAnother: _openPicker);
      } else {
        return PdfView(
          key: ValueKey('$_path#$_openSerial'),
          contentInsets: insets,
          contextMenuOpen: _contextMenuOpen,
          onFindMeaning: () => unawaited(_findMeaningNow()),
          documentRef: _documentRef!,
          controller: _controller,
          onPageChanged: (page) => setState(() => _pageNumber = page),
          initialPage: _initialPage,
          onViewerReady: (document) {
            setState(() {
              _pageCount = document.pages.length;
              // The restored page is shown before any page-change event.
              _pageNumber ??= _initialPage;
            });
            _applySavedZoom();
            unawaited(_loadOutline(document));
          },
          onLoadFailed: () => setState(() => _failed = true),
          onDocumentTap: _search.close,
          onTextSelectionChange: (selection) {
            _selection = selection;
            _debug.onSelectionChanged(selection);
            _action.onSelectionChanged(selection);
          },
        );
      }
    }

    return CallbackShortcuts(
      bindings: <ShortcutActivator, VoidCallback>{
        const SingleActivator(LogicalKeyboardKey.keyO, control: true):
            _openPicker,
        const SingleActivator(LogicalKeyboardKey.keyE, control: true):
            _findMeaning,
        const SingleActivator(LogicalKeyboardKey.keyT, control: true):
            _toggleOutline,
        const SingleActivator(LogicalKeyboardKey.keyR, control: true): _rotate,
        const SingleActivator(
          LogicalKeyboardKey.keyR,
          control: true,
          shift: true,
        ): () =>
            _rotate(clockwise: false),
        const SingleActivator(LogicalKeyboardKey.f11): _window.toggleFullscreen,
        const SingleActivator(LogicalKeyboardKey.escape): _escape,
        const SingleActivator(LogicalKeyboardKey.equal, control: true): _zoomIn,
        const SingleActivator(
          LogicalKeyboardKey.equal,
          control: true,
          shift: true,
        ): _zoomIn,
        const SingleActivator(LogicalKeyboardKey.numpadAdd, control: true):
            _zoomIn,
        const SingleActivator(LogicalKeyboardKey.minus, control: true):
            _zoomOut,
        const SingleActivator(LogicalKeyboardKey.numpadSubtract, control: true):
            _zoomOut,
        const SingleActivator(LogicalKeyboardKey.digit0, control: true):
            _fitPage,
      },
      child: Focus(
        autofocus: true,
        focusNode: _readerFocus,
        child: Scaffold(
          body: Column(
            children: [
              // Keeps the header clear of a status bar / cutout the system draws over the app
              // (edge-to-edge on Android). Zero on desktop, where nothing is drawn over the window.
              SizedBox(height: MediaQuery.paddingOf(context).top),
              if (widget.documents != null)
                ValueListenableBuilder<bool>(
                  valueListenable: widget.documents!.importing,
                  builder: (context, importing, _) => SizedBox(
                    height: 2,
                    child: importing ? const LinearProgressIndicator() : null,
                  ),
                ),
              ReaderHeader(
                title: _title,
                pageNumber: _pageNumber,
                pageCount: _headerPageCount,
                onGoToPage: _goToPage,
                onPageEditDone: _onPageEditDone,
                onRotate: hasDocument && _controller.isReady ? _rotate : null,
                fullscreen: _window.fullscreen,
                onToggleFullscreen: _window.toggleFullscreen,
                onOpen: _openPicker,
                onZoomIn: hasDocument && _controller.isReady
                    ? _controller.zoomUp
                    : null,
                onZoomOut: hasDocument && _controller.isReady
                    ? _controller.zoomDown
                    : null,
                onToggleContents: _toggleOutline,
                contentsOpen: _outlineVisible,
                menu: ListenableBuilder(
                  listenable: _settings,
                  builder: (context, _) => ReaderMenu(
                    themeMode: _settings.settings.themeMode,
                    onThemeMode: _settings.setThemeMode,
                    selectionHighlight: _settings.settings.selectionHighlight,
                    onSelectionHighlight: _settings.setSelectionHighlight,
                    recents: _settings.settings.recents,
                    onOpenRecent: _openPath,
                    onShowShortcuts: () => showShortcutsDialog(context),
                    onShowAbout: _showAbout,
                  ),
                ),
              ),
              Expanded(
                child: DevHarness(
                  controller: hasDocument ? _controller : null,
                  openPath: _openPath,
                  selection: () => _selection,
                  search: _search,
                  child: SelectionDebugOverlay(
                    state: _debug,
                    // The panels overlay the document (it never reflows), so
                    // their widths are tracked here: they become scrollable
                    // room for the viewer and an inset for the scrollbars.
                    child: ListenableBuilder(
                      listenable: _search,
                      builder: (context, _) => LayoutBuilder(
                        builder: (context, constraints) {
                          final maxWidth = constraints.maxWidth;
                          final leftInset = hasDocument && _outlineVisible
                              ? OutlinePanel.width.clamp(0.0, maxWidth * 0.8)
                              : 0.0;
                          final sheet = widget.searchPresentation.usesSheet(
                            maxWidth,
                          );
                          final rightInset = _search.visible && !sheet
                              ? SearchPanel.widthFor(maxWidth)
                              : 0.0;
                          // The sheet covers the bottom of the page; its height becomes scrollable
                          // room so the selected text can be panned clear of it.
                          final bottomInset = _search.visible && sheet
                              ? constraints.maxHeight * _sheetFraction
                              : 0.0;
                          final insets = EdgeInsets.only(
                            left: leftInset,
                            right: rightInset,
                            bottom: bottomInset,
                          );
                          _syncInsets(insets);
                          return Stack(
                            children: [
                              Positioned.fill(child: bodyFor(insets)),
                              if (hasDocument)
                                Positioned.fill(
                                  child: ListenableBuilder(
                                    listenable: Listenable.merge([
                                      _action,
                                      _contextMenuOpen,
                                    ]),
                                    builder: (context, _) {
                                      if (!_action.available ||
                                          _contextMenuOpen.value) {
                                        return const SizedBox.shrink();
                                      }
                                      return SelectionPill(
                                        repaint: _controller,
                                        anchors: () {
                                          final selection = _action.selection;
                                          if (selection == null) return null;
                                          return selectionAnchors(
                                            _controller,
                                            selection,
                                          );
                                        },
                                        onPressed: _findMeaning,
                                        onScrollSignal: _controller
                                            .handlePointerSignalEvent,
                                      );
                                    },
                                  ),
                                ),
                              if (hasDocument)
                                Positioned.fill(
                                  child: DocumentScrollbars(
                                    controller: _controller,
                                    leftInset: leftInset,
                                    rightInset: rightInset,
                                  ),
                                ),
                              // Contents overlay the left edge, like the search
                              // panel on the right.
                              if (hasDocument && _outlineVisible)
                                Positioned(
                                  left: 0,
                                  top: 0,
                                  bottom: 0,
                                  width: leftInset,
                                  child: OutlinePanel(
                                    outline: _outline,
                                    currentPage: _pageNumber,
                                    onSelect: _goToOutlineDest,
                                    onClose: _toggleOutline,
                                  ),
                                ),
                              // Phone-width windows: a draggable bottom sheet instead.
                              if (sheet &&
                                  (_search.webView != null || _search.visible))
                                Positioned.fill(
                                  child: Offstage(
                                    offstage: !_search.visible,
                                    child: ExcludeFocus(
                                      excluding: !_search.visible,
                                      child: SearchSheet(
                                        session: _search,
                                        onClose: _search.close,
                                        availableHeight: constraints.maxHeight,
                                        fraction: _sheetFraction,
                                        onSettled: (fraction) => setState(
                                          () => _sheetFraction = fraction,
                                        ),
                                      ),
                                    ),
                                  ),
                                ),
                              // No browser exists until the first search.
                              if (!sheet &&
                                  (_search.webView != null || _search.visible))
                                Positioned(
                                  right: 0,
                                  top: 0,
                                  bottom: 0,
                                  width: SearchPanel.widthFor(maxWidth),
                                  // Offstage keeps the browser laid out (and
                                  // alive) while the panel is closed.
                                  child: Offstage(
                                    offstage: !_search.visible,
                                    // A hidden browser must not keep keyboard
                                    // focus (it would swallow every key).
                                    child: ExcludeFocus(
                                      excluding: !_search.visible,
                                      child: SearchPanel(
                                        session: _search,
                                        onClose: _search.close,
                                      ),
                                    ),
                                  ),
                                ),
                            ],
                          );
                        },
                      ),
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
