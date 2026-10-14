import 'package:dndreader/features/reader/reader_header.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

/// D4 (docs/windows-verification/REPORT.md): after the page field's Enter or
/// Esc, the shortcuts and the document's keys were dead until the document was
/// clicked. Reproduced on Linux with the real app by
/// integration_test/page_field_focus_test.dart; pdfrx cannot start inside a
/// widget test, so this covers the contract the reader screen relies on, on the
/// same tree shape: shortcuts above a reader focus node that is an *ancestor* of
/// the field, with the document's own focus node beside it.
void main() {
  Future<_Harness> pump(WidgetTester tester) async {
    final h = _Harness();
    await tester.pumpWidget(
      MaterialApp(
        home: CallbackShortcuts(
          bindings: {
            const SingleActivator(LogicalKeyboardKey.keyT, control: true): () =>
                h.shortcutFired++,
          },
          child: Focus(
            focusNode: h.readerFocus,
            autofocus: true,
            child: Scaffold(
              body: Column(
                children: [
                  PageField(
                    pageNumber: 1,
                    pageCount: 9,
                    onGoToPage: (p) => h.jumps.add(p),
                    // What ReaderScreen._onPageEditDone does with a ready viewer.
                    onDone: () => h.documentFocus.requestFocus(),
                  ),
                  Expanded(
                    child: Focus(
                      focusNode: h.documentFocus,
                      child: const SizedBox.expand(),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
    return h;
  }

  Future<void> ctrlT(WidgetTester tester) async {
    await tester.sendKeyDownEvent(LogicalKeyboardKey.controlLeft);
    await tester.sendKeyEvent(LogicalKeyboardKey.keyT);
    await tester.sendKeyUpEvent(LogicalKeyboardKey.controlLeft);
    await tester.pump();
  }

  testWidgets('Enter in the page field jumps, then focus is on the document', (
    tester,
  ) async {
    final h = await pump(tester);
    await tester.tap(find.byKey(const ValueKey('page-field')));
    await tester.pump();
    await tester.enterText(find.byKey(const ValueKey('page-field')), '4');
    await tester.testTextInput.receiveAction(TextInputAction.done);
    await tester.pump();

    expect(h.jumps, [4]);
    expect(h.documentFocus.hasPrimaryFocus, isTrue);
    await ctrlT(tester);
    expect(h.shortcutFired, 1, reason: 'shortcuts act with no extra click');
  });

  testWidgets(
    'Esc in the page field abandons the edit, focus on the document',
    (tester) async {
      final h = await pump(tester);
      await tester.tap(find.byKey(const ValueKey('page-field')));
      await tester.pump();
      await tester.enterText(find.byKey(const ValueKey('page-field')), '7');
      await tester.sendKeyEvent(LogicalKeyboardKey.escape);
      await tester.pump();

      expect(h.jumps, isEmpty, reason: 'Esc must not jump');
      expect(
        tester
            .widget<TextField>(find.byKey(const ValueKey('page-field')))
            .controller!
            .text,
        '1',
        reason: 'the abandoned edit is replaced by the real page',
      );
      expect(h.documentFocus.hasPrimaryFocus, isTrue);
      await ctrlT(tester);
      expect(h.shortcutFired, 1);
    },
  );
}

class _Harness {
  final FocusNode readerFocus = FocusNode(debugLabel: 'reader');
  final FocusNode documentFocus = FocusNode(debugLabel: 'document');
  final List<int> jumps = [];
  int shortcutFired = 0;
}
