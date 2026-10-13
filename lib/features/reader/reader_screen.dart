import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:pdfrx/pdfrx.dart';

import '../../dev/dev_harness.dart';
import '../../dev/selection_debug.dart';
import '../../services/pdf_picker.dart';
import 'empty_state.dart';
import 'open_failure.dart';
import 'pdf_view.dart';
import 'reader_header.dart';
import 'selection_action_controller.dart';
import 'selection_anchor.dart';
import 'selection_pill.dart';
import '../../services/search_url.dart';

/// The single screen: header on top, reading surface below.
class ReaderScreen extends StatefulWidget {
  const ReaderScreen({
    super.key,
    this.initialPath,
    this.pickPdf = pickPdfPath,
    this.actionController,
  });

  /// A document to open at start-up (command-line argument / "Open With").
  final String? initialPath;

  /// Injected so tests need no native dialog.
  final PdfPicker pickPdf;

  /// Test seam: lets a widget test drive the "Find meaning" state without a
  /// native PDF viewer. Production code leaves this null.
  @visibleForTesting
  final SelectionActionController? actionController;

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
  int? _pageNumber;
  int? _pageCount;
  bool _failed = false;
  PdfTextSelection? _selection;
  final SelectionDebugState _debug = SelectionDebugState();
  late final SelectionActionController _action =
      widget.actionController ?? SelectionActionController();

  @override
  void initState() {
    super.initState();
    final initial = widget.initialPath;
    if (initial != null) _path = initial;
  }

  @override
  void dispose() {
    if (widget.actionController == null) _action.dispose();
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
    setState(() {
      _path = path;
      _openSerial++;
      _controller = PdfViewerController();
      _pageNumber = null;
      _pageCount = null;
      _failed = false;
      _selection = null;
    });
    _debug.reset();
    _action.reset();
  }

  /// "Find meaning". Until the search panel exists (M4) this hands the built
  /// URL to a transient message; nothing is navigated.
  void _findMeaning() {
    if (!_action.available) return;
    final uri = searchUriFor(_action.query!);
    if (uri == null) return;
    debugPrint('[find-meaning] ${uri.toString()}');
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text('Find meaning: ${_action.query}')));
  }

  /// Esc: hide the action and drop the selection.
  void _dismissSelection() {
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
      body = EmptyState(onOpen: _openPicker);
    } else if (_failed) {
      body = OpenFailure(fileName: _title, onOpenAnother: _openPicker);
    } else {
      body = PdfView(
        key: ValueKey('$_path#$_openSerial'),
        path: _path!,
        controller: _controller,
        onPageChanged: (page) => setState(() => _pageNumber = page),
        onViewerReady: (document) =>
            setState(() => _pageCount = document.pages.length),
        onLoadFailed: () => setState(() => _failed = true),
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
        const SingleActivator(LogicalKeyboardKey.escape): _dismissSelection,
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
              ),
              Expanded(
                child: DevHarness(
                  controller: hasDocument ? _controller : null,
                  openPath: _openPath,
                  selection: () => _selection,
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
