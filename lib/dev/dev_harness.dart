// ignore_for_file: deprecated_member_use
import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math' as math;

import 'package:flutter/foundation.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:pdfrx/pdfrx.dart';

import '../features/reader/selection_anchor.dart';
import '../features/reader/selection_pill.dart';
import 'selection_debug.dart';

/// Path of a one-line command file polled by [DevHarness]. Empty disables it.
/// Debug builds only; inert in release builds.
const String _commandFile = String.fromEnvironment('DNDREADER_DEV_HARNESS');

/// Spike-grade development driver for the §5.1.1 gates: it injects pointer
/// events *inside Flutter* (OS-level input does not reach this app under
/// XWayland on the dev machine) and dumps what pdfrx reports.
///
/// It never touches a webview and is not part of the product.
class DevHarness extends StatefulWidget {
  const DevHarness({
    super.key,
    required this.controller,
    required this.openPath,
    required this.selection,
    required this.child,
  });

  final PdfViewerController? controller;
  final void Function(String path) openPath;
  final PdfTextSelection? Function() selection;
  final Widget child;

  static bool get enabled => !kReleaseMode && _commandFile.isNotEmpty;

  @override
  State<DevHarness> createState() => _DevHarnessState();
}

class _DevHarnessState extends State<DevHarness> {
  Timer? _timer;
  bool _busy = false;
  bool _pointerAdded = false;
  int _pointerId = 100;

  @override
  void initState() {
    super.initState();
    if (DevHarness.enabled) {
      _timer = Timer.periodic(
        const Duration(milliseconds: 400),
        (_) => _poll(),
      );
    }
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  void _log(String line) {
    debugPrint('[harness] $line');
    try {
      File('$_commandFile.out')
          .writeAsStringSync('$line\n', mode: FileMode.append);
    } catch (_) {}
  }

  Future<void> _poll() async {
    if (_busy) return;
    final file = File(_commandFile);
    if (!file.existsSync()) return;
    final line = file.readAsStringSync().trim();
    file.deleteSync();
    if (line.isEmpty) return;
    _busy = true;
    try {
      await _run(line);
    } catch (e, st) {
      _log('ERROR $line -> $e\n$st');
    } finally {
      _busy = false;
    }
  }

  PdfViewerController _need() {
    final c = widget.controller;
    if (c == null || !c.isReady) throw StateError('no document ready');
    return c;
  }

  // ---- pointer injection (in-Flutter) -------------------------------------

  void _inject(PointerEvent Function(int viewId) make) {
    final viewId = View.of(context).viewId;
    GestureBinding.instance.handlePointerEvent(make(viewId));
  }

  void _ensurePointer(Offset p) {
    if (_pointerAdded) return;
    _pointerAdded = true;
    _inject(
      (v) => PointerAddedEvent(
        position: p,
        kind: PointerDeviceKind.mouse,
        device: 7,
        viewId: v,
      ),
    );
  }

  Future<void> _hover(Offset p) async {
    _ensurePointer(p);
    _inject(
      (v) => PointerHoverEvent(
        position: p,
        kind: PointerDeviceKind.mouse,
        device: 7,
        viewId: v,
      ),
    );
    await Future<void>.delayed(const Duration(milliseconds: 30));
  }

  Future<void> _click(Offset p) async {
    await _hover(p);
    final id = ++_pointerId;
    _inject(
      (v) => PointerDownEvent(
        position: p,
        kind: PointerDeviceKind.mouse,
        device: 7,
        pointer: id,
        buttons: kPrimaryButton,
        viewId: v,
      ),
    );
    await Future<void>.delayed(const Duration(milliseconds: 60));
    _inject(
      (v) => PointerUpEvent(
        position: p,
        kind: PointerDeviceKind.mouse,
        device: 7,
        pointer: id,
        viewId: v,
      ),
    );
    await Future<void>.delayed(const Duration(milliseconds: 80));
  }

  Future<void> _drag(Offset a, Offset b, {int steps = 12}) async {
    await _hover(a);
    final id = ++_pointerId;
    _inject(
      (v) => PointerDownEvent(
        position: a,
        kind: PointerDeviceKind.mouse,
        device: 7,
        pointer: id,
        buttons: kPrimaryButton,
        viewId: v,
      ),
    );
    await Future<void>.delayed(const Duration(milliseconds: 40));
    var prev = a;
    for (var i = 1; i <= steps; i++) {
      final p = Offset.lerp(a, b, i / steps)!;
      _inject(
        (v) => PointerMoveEvent(
          position: p,
          delta: p - prev,
          kind: PointerDeviceKind.mouse,
          device: 7,
          pointer: id,
          buttons: kPrimaryButton,
          viewId: v,
        ),
      );
      prev = p;
      await Future<void>.delayed(const Duration(milliseconds: 16));
    }
    _inject(
      (v) => PointerUpEvent(
        position: b,
        kind: PointerDeviceKind.mouse,
        device: 7,
        pointer: id,
        viewId: v,
      ),
    );
    await Future<void>.delayed(const Duration(milliseconds: 120));
  }

  Future<void> _scroll(Offset p, double dy) async {
    await _hover(p);
    _inject(
      (v) => PointerScrollEvent(
        position: p,
        scrollDelta: Offset(0, dy),
        kind: PointerDeviceKind.mouse,
        device: 7,
        viewId: v,
      ),
    );
    await Future<void>.delayed(const Duration(milliseconds: 250));
  }

  // ---- document geometry --------------------------------------------------

  /// Global (window logical px) rect of character [i] on [page]. Uses the
  /// viewer's own public conversion — this is what gate 3 relies on.
  Future<Rect> _charGlobalRect(int page, int i) async {
    final c = _need();
    final text = await c.document.pages[page - 1].loadStructuredText();
    if (i < 0 || i >= text.charRects.length) {
      throw RangeError(
        'char $i outside page $page (${text.charRects.length} chars)',
      );
    }
    final docRect = c.calcRectForRectInsidePage(
      pageNumber: page,
      rect: text.charRects[i],
    );
    final tl = c.documentToGlobal(docRect.topLeft)!;
    final br = c.documentToGlobal(docRect.bottomRight)!;
    return Rect.fromPoints(tl, br);
  }

  // ---- commands -------------------------------------------------------------

  Future<void> _run(String line) async {
    final a = line.split(RegExp(r'\s+'));
    _log('> $line');
    switch (a[0]) {
      case 'open':
        widget.openPath(a.sublist(1).join(' '));
        await Future<void>.delayed(const Duration(milliseconds: 1500));
      case 'goto':
        await _need().goToPage(pageNumber: int.parse(a[1]));
        await Future<void>.delayed(const Duration(milliseconds: 600));
      case 'zoom':
        final c = _need();
        if (a[1] == 'in') {
          await c.zoomUp();
        } else if (a[1] == 'out') {
          await c.zoomDown();
        } else {
          await c.setZoom(c.centerPosition, double.parse(a[1]));
        }
        await Future<void>.delayed(const Duration(milliseconds: 500));
      case 'click':
        await _click(Offset(double.parse(a[1]), double.parse(a[2])));
      case 'drag':
        await _drag(
          Offset(double.parse(a[1]), double.parse(a[2])),
          Offset(double.parse(a[3]), double.parse(a[4])),
        );
      case 'scroll':
        await _scroll(
          Offset(double.parse(a[1]), double.parse(a[2])),
          double.parse(a[3]),
        );
      case 'dragchars': // dragchars <page> <i0> <i1>  — real pointer drag between two characters
        final page = int.parse(a[1]);
        await _need().goToPage(pageNumber: page);
        await Future<void>.delayed(const Duration(milliseconds: 500));
        final r0 = await _charGlobalRect(page, int.parse(a[2]));
        final r1 = await _charGlobalRect(page, int.parse(a[3]));
        _log('  from ${r0.center} to ${r1.center}');
        await _drag(
          Offset(r0.left + 1, r0.center.dy),
          Offset(r1.right - 1, r1.center.dy),
        );
      case 'clickchar': // clickchar <page> <i> — double-click selects a word in pdfrx
        final r = await _charGlobalRect(int.parse(a[1]), int.parse(a[2]));
        await _click(r.center);
        await Future<void>.delayed(const Duration(milliseconds: 60));
        await _click(r.center);
      case 'selrange': // selrange <page> <i0> <i1>  — programmatic, no pointer
        final c = _need();
        final text = await c.document.pages[int.parse(a[1]) - 1]
            .loadStructuredText();
        await c.textSelectionDelegate.setTextSelectionPointRange(
          PdfTextSelectionRange.fromPoints(
            PdfTextSelectionPoint(text, int.parse(a[2])),
            PdfTextSelectionPoint(text, int.parse(a[3])),
          ),
        );
      case 'selall':
        await _need().textSelectionDelegate.selectAllText();
      case 'clear':
        await _need().textSelectionDelegate.clearTextSelection();
      case 'clickpill':
        final ctx =
            SelectionPill.pillKey.currentContext ??
            SelectionDebugOverlay.pillKey.currentContext;
        final box = ctx?.findRenderObject() as RenderBox?;
        if (box == null) throw StateError('pill not visible');
        await _click(box.localToGlobal(box.size.center(Offset.zero)));
      case 'pagetext': // pagetext <page> [maxChars] — raw vs structured text for gate 1
        final page = _need().document.pages[int.parse(a[1]) - 1];
        final max = a.length > 2 ? int.parse(a[2]) : 700;
        final raw = await page.loadText();
        final st = await page.loadStructuredText();
        String cut(String s) => s.length > max ? s.substring(0, max) : s;
        _log(
          '  raw.len=${raw?.fullText.length} structured.len=${st.fullText.length} '
          'charRects=${st.charRects.length} fragments=${st.fragments.length}',
        );
        _log('  structured=${json.encode(cut(st.fullText))}');
        _log('  raw       =${json.encode(cut(raw?.fullText ?? ''))}');
      case 'find': // find <page> <needle...> — first match; spaces match any whitespace (incl. \n)
        final page = int.parse(a[1]);
        final words = a
            .sublist(2)
            .where((w) => w.isNotEmpty)
            .map(RegExp.escape);
        final st = await _need().document.pages[page - 1].loadStructuredText();
        final m = RegExp(words.join(r'\s+')).firstMatch(st.fullText);
        _log(
          m == null
              ? '  FIND none'
              : '  FIND ${m.start} ${m.end - 1} ${json.encode(m.group(0))}',
        );
      case 'colbreak': // colbreak <page> — first big jump right+up in reading order
        final st = await _need().document.pages[int.parse(a[1]) - 1]
            .loadStructuredText();
        var found = -1;
        for (var i = 1; i < st.charRects.length; i++) {
          final p = st.charRects[i - 1], c = st.charRects[i];
          if (c.left > p.right + 40 && c.top > p.top + 20) {
            found = i;
            break;
          }
        }
        _log(
          found < 0
              ? '  COLBREAK none'
              : '  COLBREAK $found before=${json.encode(st.fullText.substring(math.max(0, found - 30), found))} '
                    'after=${json.encode(st.fullText.substring(found, math.min(st.fullText.length, found + 30)))}',
        );
      case 'selpages': // selpages <p0> <i0> <p1> <i1> — programmatic multi-page selection
        final c = _need();
        final t0 = await c.document.pages[int.parse(a[1]) - 1]
            .loadStructuredText();
        final t1 = await c.document.pages[int.parse(a[3]) - 1]
            .loadStructuredText();
        await c.textSelectionDelegate.setTextSelectionPointRange(
          PdfTextSelectionRange.fromPoints(
            PdfTextSelectionPoint(t0, int.parse(a[2])),
            PdfTextSelectionPoint(t1, int.parse(a[4])),
          ),
        );
      case 'lastchars': // lastchars <page> <n> — count and tail of a page's text
        final t = await _need().document.pages[int.parse(a[1]) - 1]
            .loadStructuredText();
        final n = int.parse(a[2]);
        _log(
          '  len=${t.fullText.length} tail=${json.encode(t.fullText.substring(math.max(0, t.fullText.length - n)))}',
        );
      case 'scanhyphen': // scanhyphen <from> <to> — occurrences of U+0002 and of "-\n"
        final from = int.parse(a[1]), to = int.parse(a[2]);
        var wraps = 0, literal = 0;
        final samples = <String>[];
        for (var p = from; p <= to; p++) {
          final t = await _need().document.pages[p - 1].loadStructuredText();
          final txt = t.fullText;
          for (var i = 0; i < txt.length; i++) {
            if (txt.codeUnitAt(i) == 2) {
              wraps++;
              if (samples.length < 8) {
                samples.add(
                  json.encode(
                    txt.substring(
                      math.max(0, i - 12),
                      math.min(txt.length, i + 12),
                    ),
                  ),
                );
              }
            } else if (txt.codeUnitAt(i) == 0x2d &&
                i + 1 < txt.length &&
                txt.codeUnitAt(i + 1) == 0x0a) {
              literal++;
            }
          }
        }
        _log('  pages $from..$to: U+0002=$wraps  hyphen+newline=$literal');
        for (final s in samples) {
          _log('   $s');
        }
      case 'anchor': // anchor — predicted on-screen rects of the selection's end characters
        final c = _need();
        final sel = widget.selection();
        final anchors = sel == null ? null : selectionAnchors(c, sel);
        if (anchors == null) {
          _log('  ANCHOR none');
        } else {
          final origin = c.localToGlobal(Offset.zero)!;
          Rect g(Rect r) => r.shift(origin);
          Map<String, double> m(Rect r) => {
            'l': r.left,
            't': r.top,
            'r': r.right,
            'b': r.bottom,
          };
          _log(
            '  ANCHOR ${json.encode({
              'start': m(g(anchors.start)),
              'end': m(g(anchors.end)),
              'bounds': m(g(anchors.bounds)),
              'zoom': c.currentZoom,
              'page': c.pageNumber,
              'origin': [origin.dx, origin.dy],
            })}',
          );
        }
      case 'pill': // pill — global rect of the real pill, or "none"
        final box =
            SelectionPill.pillKey.currentContext?.findRenderObject()
                as RenderBox?;
        if (box == null || !box.attached) {
          _log('  PILL none');
        } else {
          final tl = box.localToGlobal(Offset.zero);
          _log(
            '  PILL ${json.encode({'l': tl.dx, 't': tl.dy, 'r': tl.dx + box.size.width, 'b': tl.dy + box.size.height})}',
          );
        }
      case 'key': // key ctrl+e | key escape — through the engine's key-data pipeline
        final combo = a[1].toLowerCase();
        final ctrl = combo.startsWith('ctrl+');
        final name = ctrl ? combo.substring(5) : combo;
        final (phys, logi, ch) = switch (name) {
          'e' => (PhysicalKeyboardKey.keyE, LogicalKeyboardKey.keyE, 'e'),
          'escape' => (
            PhysicalKeyboardKey.escape,
            LogicalKeyboardKey.escape,
            null,
          ),
          _ => throw ArgumentError('unknown key $name'),
        };
        var t = 0;
        void send(
          PhysicalKeyboardKey p,
          LogicalKeyboardKey l,
          bool down, [
          String? c,
        ]) {
          // Framework-level injection: update HardwareKeyboard, then hand the
          // event to the focus manager's key handler (what the engine's key
          // pipeline ends in). The engine-level KeyData path waits for a legacy
          // raw-key message that only a real embedder sends.
          final stamp = Duration(microseconds: 1000 * ++t);
          final KeyEvent ev = down
              ? KeyDownEvent(
                  physicalKey: p,
                  logicalKey: l,
                  character: c,
                  timeStamp: stamp,
                )
              : KeyUpEvent(physicalKey: p, logicalKey: l, timeStamp: stamp);
          // Update HardwareKeyboard, then run the focus tree's key handler: the
          // two steps the engine pipeline performs for a real key press.
          HardwareKeyboard.instance.handleKeyEvent(ev);
          final handled = ServicesBinding
              .instance
              .keyEventManager
              .keyMessageHandler
              ?.call(KeyMessage([ev], null));
          _log(
            '  key ${down ? "down" : "up"} ${l.keyLabel} handled=$handled '
            'ctrlPressed=${HardwareKeyboard.instance.isControlPressed}',
          );
        }
        if (ctrl) {
          send(
            PhysicalKeyboardKey.controlLeft,
            LogicalKeyboardKey.controlLeft,
            true,
          );
        }
        send(phys, logi, true, ch);
        send(phys, logi, false);
        if (ctrl) {
          send(
            PhysicalKeyboardKey.controlLeft,
            LogicalKeyboardKey.controlLeft,
            false,
          );
        }
        await Future<void>.delayed(const Duration(milliseconds: 150));
      case 'focus': // focus — who has primary focus, and its ancestor chain
        final f = FocusManager.instance.primaryFocus;
        final chain = <String>[];
        for (FocusNode? n = f; n != null; n = n.parent) {
          chain.add(
            '${n.debugLabel ?? n.runtimeType} canRequest=${n.canRequestFocus}',
          );
        }
        _log(
          '  FOCUS primary=${f?.debugLabel ?? f?.runtimeType} chain=${chain.length}',
        );
        for (final c in chain) {
          _log('    $c');
        }
      case 'viewport':
        final c = _need();
        _log(
          '  viewSize=${c.viewSize} zoom=${c.currentZoom.toStringAsFixed(3)} '
          'page=${c.pageNumber} visibleRect=${c.visibleRect}',
        );
      case 'dump':
        final s = widget.selection();
        if (s == null) {
          _log('  no selection object yet');
        } else {
          _log(
            '  hasSelectedText=${s.hasSelectedText} text=${json.encode(await s.getSelectedText())}',
          );
          final ranges = await s.getSelectedTextRanges();
          _log(
            '  ranges=${ranges.map((r) => 'p${r.pageNumber}[${r.start},${r.end})').toList()}',
          );
        }
      case 'sleep':
        await Future<void>.delayed(
          Duration(milliseconds: math.max(0, int.parse(a[1]))),
        );
      default:
        _log('  unknown command');
    }
    _log('< done');
  }

  @override
  Widget build(BuildContext context) => widget.child;
}
