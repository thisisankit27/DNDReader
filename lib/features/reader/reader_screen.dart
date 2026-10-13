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

/// The single screen: header on top, reading surface below.
class ReaderScreen extends StatefulWidget {
  const ReaderScreen({super.key, this.initialPath, this.pickPdf = pickPdfPath});

  /// A document to open at start-up (command-line argument / "Open With").
  final String? initialPath;

  /// Injected so tests need no native dialog.
  final PdfPicker pickPdf;

  @override
  State<ReaderScreen> createState() => _ReaderScreenState();
}

class _ReaderScreenState extends State<ReaderScreen> {
  String? _path;
  PdfViewerController _controller = PdfViewerController();
  int? _pageNumber;
  int? _pageCount;
  bool _failed = false;
  PdfTextSelection? _selection;
  final SelectionDebugState _debug = SelectionDebugState();

  @override
  void initState() {
    super.initState();
    final initial = widget.initialPath;
    if (initial != null) _path = initial;
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
      _controller = PdfViewerController();
      _pageNumber = null;
      _pageCount = null;
      _failed = false;
      _selection = null;
    });
    _debug.reset();
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
        key: ValueKey(_path),
        path: _path!,
        controller: _controller,
        onPageChanged: (page) => setState(() => _pageNumber = page),
        onViewerReady: (document) =>
            setState(() => _pageCount = document.pages.length),
        onLoadFailed: () => setState(() => _failed = true),
        onTextSelectionChange: (selection) {
          _selection = selection;
          _debug.onSelectionChanged(selection);
        },
      );
    }

    return CallbackShortcuts(
      bindings: <ShortcutActivator, VoidCallback>{
        const SingleActivator(LogicalKeyboardKey.keyO, control: true):
            _openPicker,
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
                  child: SelectionDebugOverlay(state: _debug, child: body),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
