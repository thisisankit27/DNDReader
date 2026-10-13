import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:pdfrx/pdfrx.dart';

/// Directory for `selection.json`; shared with the frame-capture flag.
const String _outDir = String.fromEnvironment('DNDREADER_CAPTURE_DIR');

/// Turns the §5.1.1 gate readout on. Debug builds only.
const String _flag = String.fromEnvironment('DNDREADER_DEBUG_SELECTION');

bool get selectionDebugEnabled => !kReleaseMode && _flag.isNotEmpty;

/// Gate 1/2 instrumentation (plan §5.1.1): records what pdfrx actually reports
/// for a selection, and whether the selection survives our own widget.
///
/// This is a crude readout, not product UI: it is inert unless
/// `--dart-define=DNDREADER_DEBUG_SELECTION=1` is given to a non-release build.
class SelectionDebugState extends ChangeNotifier {
  PdfTextSelection? _selection;
  int changeCount = 0;
  bool hasSelection = false;
  String text = '';
  List<String> ranges = const [];
  String pointRange = '';
  int pillTaps = 0;
  bool? selectionAfterLastPillTap;
  bool? selectionWhilePillShown;
  Timer? _debounce;

  PdfTextSelection? get selection => _selection;

  void onSelectionChanged(PdfTextSelection selection) {
    if (!selectionDebugEnabled) return;
    _selection = selection;
    changeCount++;
    _debounce?.cancel();
    _debounce = Timer(const Duration(milliseconds: 80), refresh);
  }

  /// A new document was opened: forget everything about the old one.
  void reset() {
    _debounce?.cancel();
    _selection = null;
    hasSelection = false;
    text = '';
    ranges = const [];
    pointRange = '';
    selectionAfterLastPillTap = null;
    selectionWhilePillShown = null;
    notifyListeners();
  }

  Future<void> refresh() async {
    final s = _selection;
    if (s == null) return;
    hasSelection = s.hasSelectedText;
    text = hasSelection ? await s.getSelectedText() : '';
    final rs = hasSelection
        ? await s.getSelectedTextRanges()
        : const <PdfPageTextRange>[];
    ranges = [for (final r in rs) 'p${r.pageNumber}[${r.start},${r.end})'];
    final pr = s.textSelectionPointRange;
    pointRange = pr == null
        ? ''
        : 'p${pr.start.text.pageNumber}#${pr.start.index} → p${pr.end.text.pageNumber}#${pr.end.index}';
    notifyListeners();
    _write();
  }

  /// Called after the test pill has been tapped.
  void pillTapped() {
    pillTaps++;
    Timer(const Duration(milliseconds: 500), () {
      selectionAfterLastPillTap = _selection?.hasSelectedText;
      notifyListeners();
      _write();
    });
  }

  void pillShown() {
    Timer(const Duration(milliseconds: 500), () {
      selectionWhilePillShown = _selection?.hasSelectedText;
      notifyListeners();
      _write();
    });
  }

  Map<String, Object?> toJson() => {
    'changeCount': changeCount,
    'hasSelection': hasSelection,
    'text': text,
    'textCodeUnits': text.codeUnits.length,
    'textEscaped': json.encode(text),
    'ranges': ranges,
    'pointRange': pointRange,
    'pillTaps': pillTaps,
    'selectionWhilePillShown': selectionWhilePillShown,
    'selectionAfterLastPillTap': selectionAfterLastPillTap,
  };

  void _write() {
    if (_outDir.isEmpty) return;
    try {
      File(
        '$_outDir/selection.json',
      ).writeAsStringSync(const JsonEncoder.withIndent('  ').convert(toJson()));
    } catch (_) {}
  }
}

/// Wraps the reading surface with the readout and a plain test pill.
class SelectionDebugOverlay extends StatefulWidget {
  const SelectionDebugOverlay({
    super.key,
    required this.state,
    required this.child,
  });

  final SelectionDebugState state;
  final Widget child;

  @override
  State<SelectionDebugOverlay> createState() => _SelectionDebugOverlayState();

  /// Key of the test pill, so the dev harness can find and click it.
  static final GlobalKey pillKey = GlobalKey(debugLabel: 'debug-test-pill');
}

class _SelectionDebugOverlayState extends State<SelectionDebugOverlay> {
  bool _pillWasVisible = false;

  @override
  Widget build(BuildContext context) {
    if (!selectionDebugEnabled) return widget.child;
    return ListenableBuilder(
      listenable: widget.state,
      builder: (context, _) {
        final s = widget.state;
        if (s.hasSelection && !_pillWasVisible) {
          _pillWasVisible = true;
          s.pillShown();
        } else if (!s.hasSelection) {
          _pillWasVisible = false;
        }
        final mono = Theme.of(context).textTheme.bodySmall?.copyWith(
          fontFamily: 'monospace',
          color: Colors.white,
          fontSize: 11,
        );
        return Stack(
          children: [
            Positioned.fill(child: widget.child),
            if (s.hasSelection)
              Positioned(
                top: 8,
                right: 24,
                child: FilledButton(
                  key: SelectionDebugOverlay.pillKey,
                  onPressed: s.pillTapped,
                  child: const Text('Find meaning (test pill)'),
                ),
              ),
            Positioned(
              left: 8,
              right: 8,
              bottom: 8,
              child: IgnorePointer(
                child: Container(
                  padding: const EdgeInsets.all(8),
                  color: Colors.black87,
                  child: Text(
                    'changes=${s.changeCount} has=${s.hasSelection} ranges=${s.ranges} '
                    'point=${s.pointRange}\n'
                    'text=${json.encode(s.text.length > 220 ? '${s.text.substring(0, 220)}…' : s.text)}\n'
                    'pillShown→still selected=${s.selectionWhilePillShown}  pillTaps=${s.pillTaps} '
                    'after tap still selected=${s.selectionAfterLastPillTap}',
                    style: mono,
                    maxLines: 6,
                  ),
                ),
              ),
            ),
          ],
        );
      },
    );
  }
}
