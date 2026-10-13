import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:pdfrx/pdfrx.dart';

import '../../dev/dev_harness.dart';
import '../../dev/selection_debug.dart';
import '../../services/pdf_picker.dart';
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
import '../search/search_panel.dart';
import '../search/search_session.dart';
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

  int? _initialPage;
  Timer? _persistTimer;
  double? _persistedZoom;

  @override
  void initState() {
    super.initState();
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
  }

  void _trackDocument(String path) {
    _settings.addRecent(path);
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

  void _fitPage() {
    if (!_controller.isReady) return;
    final matrix = _controller.calcMatrixForFit(pageNumber: _pageNumber ?? 1);
    if (matrix != null) _controller.goTo(matrix);
  }

  @override
  void dispose() {
    _persistTimer?.cancel();
    _controller.removeListener(_onViewerTransform);
    if (widget.actionController == null) _action.dispose();
    if (widget.searchSession == null) _search.dispose();
    super.dispose();
  }

  String get _title {
    final path = _path;
    if (path == null) return 'DNDReader';
    return path.split(Platform.pathSeparator).last;
  }

  String? get _pageLabel {
    final count = _pageCount;
    if (_path == null || _failed || count == null) return null;
    return '${_pageNumber ?? 1} / $count';
  }

  Future<void> _openPicker() async {
    final picked = await widget.pickPdf();
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

  void _showAbout() {
    showAboutDialog(
      context: context,
      applicationName: 'DNDReader',
      applicationVersion: kAppVersion,
      applicationLegalese:
          'Search results are shown by Google in an embedded browser.\n'
          'Embedded browser: $kBundledChromium',
    );
  }

  /// Esc: close the search panel if it is open; otherwise hide the action and
  /// drop the selection.
  void _escape() {
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

  @override
  Widget build(BuildContext context) {
    final hasDocument = _path != null && !_failed;

    final Widget body;
    if (_path == null) {
      body = EmptyState(
        onOpen: _openPicker,
        recents: _settings.settings.recents
            .where((p) => File(p).existsSync())
            .toList(growable: false),
        onOpenRecent: _openPath,
      );
    } else if (_failed) {
      body = OpenFailure(fileName: _title, onOpenAnother: _openPicker);
    } else {
      body = PdfView(
        key: ValueKey('$_path#$_openSerial'),
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

    return CallbackShortcuts(
      bindings: <ShortcutActivator, VoidCallback>{
        const SingleActivator(LogicalKeyboardKey.keyO, control: true):
            _openPicker,
        const SingleActivator(LogicalKeyboardKey.keyE, control: true):
            _findMeaning,
        const SingleActivator(LogicalKeyboardKey.keyT, control: true):
            _toggleOutline,
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
        child: Scaffold(
          body: Column(
            children: [
              ReaderHeader(
                title: _title,
                pageLabel: _pageLabel,
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
                    child: Stack(
                      children: [
                        Positioned.fill(child: body),
                        if (hasDocument)
                          Positioned.fill(
                            child: ListenableBuilder(
                              listenable: _action,
                              builder: (context, _) {
                                if (!_action.available) {
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
                                  onScrollSignal:
                                      _controller.handlePointerSignalEvent,
                                );
                              },
                            ),
                          ),
                        // Contents overlay the left edge, like the search panel
                        // on the right: the document never reflows.
                        if (hasDocument && _outlineVisible)
                          Positioned.fill(
                            child: LayoutBuilder(
                              builder: (context, constraints) => Align(
                                alignment: Alignment.centerLeft,
                                child: SizedBox(
                                  width: OutlinePanel.width.clamp(
                                    0.0,
                                    constraints.maxWidth * 0.8,
                                  ),
                                  child: OutlinePanel(
                                    outline: _outline,
                                    currentPage: _pageNumber,
                                    onSelect: _goToOutlineDest,
                                    onClose: _toggleOutline,
                                  ),
                                ),
                              ),
                            ),
                          ),
                        // The search panel overlays the right edge: the document
                        // never reflows and never loses its scroll position.
                        Positioned.fill(
                          child: ListenableBuilder(
                            listenable: _search,
                            builder: (context, _) {
                              // No browser exists until the first search.
                              if (_search.webView == null && !_search.visible) {
                                return const SizedBox.shrink();
                              }
                              return LayoutBuilder(
                                builder: (context, constraints) {
                                  final width = SearchPanel.widthFor(
                                    constraints.maxWidth,
                                  );
                                  return Align(
                                    alignment: Alignment.centerRight,
                                    child: SizedBox(
                                      width: width,
                                      // Offstage keeps the browser laid out (and
                                      // alive) while the panel is closed.
                                      child: Offstage(
                                        offstage: !_search.visible,
                                        child: SearchPanel(
                                          session: _search,
                                          onClose: _search.close,
                                        ),
                                      ),
                                    ),
                                  );
                                },
                              );
                            },
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
