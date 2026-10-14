// Runs the real app on the Linux device (`flutter test integration_test -d linux`).
// Key events are injected inside Flutter, not through GTK: that hop is untested.
import 'dart:io';

import 'package:dndreader/app.dart';
import 'package:dndreader/features/reader/outline_panel.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:pdfrx/pdfrx.dart';

Future<void> _ctrl(WidgetTester tester, LogicalKeyboardKey key) async {
  await tester.sendKeyDownEvent(LogicalKeyboardKey.controlLeft);
  await tester.sendKeyEvent(key);
  await tester.sendKeyUpEvent(LogicalKeyboardKey.controlLeft);
  await tester.pump(const Duration(milliseconds: 300));
}

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  Future<void> open(WidgetTester tester) async {
    final path = '${Directory.current.path}/test_fixtures/outline.pdf';
    await tester.pumpWidget(DndReaderApp(initialPath: path));
    for (var i = 0; i < 60; i++) {
      await tester.pump(const Duration(milliseconds: 100));
      if (find.byKey(const ValueKey('page-field')).evaluate().isNotEmpty) break;
    }
    await tester.pump(const Duration(seconds: 1));
    expect(find.byKey(const ValueKey('page-field')), findsOneWidget);
  }

  testWidgets('control: Ctrl+T works with no page-field interaction', (
    tester,
  ) async {
    await open(tester);
    await _ctrl(tester, LogicalKeyboardKey.keyT);
    expect(find.byType(OutlinePanel), findsOneWidget);
  });

  testWidgets(
    'Enter in the page field leaves focus where a click on the document does',
    (tester) async {
      await open(tester);
      await tester.tapAt(tester.getCenter(find.byType(PdfViewer)));
      await tester.pump(const Duration(milliseconds: 300));
      final clicked = FocusManager.instance.primaryFocus;

      await tester.tap(find.byKey(const ValueKey('page-field')));
      await tester.pump();
      expect(FocusManager.instance.primaryFocus, isNot(clicked));
      await tester.enterText(find.byKey(const ValueKey('page-field')), '2');
      await tester.testTextInput.receiveAction(TextInputAction.done);
      await tester.pump(const Duration(milliseconds: 300));

      // The viewer's own node: where the arrow keys are handled.
      expect(FocusManager.instance.primaryFocus, same(clicked));
    },
  );

  testWidgets('D4: Ctrl+T works after Enter in the page field', (tester) async {
    await open(tester);
    expect(find.byType(OutlinePanel), findsNothing);

    await tester.tap(find.byKey(const ValueKey('page-field')));
    await tester.pump();
    await tester.enterText(find.byKey(const ValueKey('page-field')), '2');
    await tester.testTextInput.receiveAction(TextInputAction.done);
    await tester.pump(const Duration(milliseconds: 300));
    debugPrint(
      'after Enter, primaryFocus = ${FocusManager.instance.primaryFocus}',
    );

    await _ctrl(tester, LogicalKeyboardKey.keyT);
    debugPrint(
      'outline panel shown: ${find.byType(OutlinePanel).evaluate().isNotEmpty}',
    );
    expect(find.byType(OutlinePanel), findsOneWidget);
  });

  testWidgets('D4: Ctrl+T works after Esc in the page field', (tester) async {
    await open(tester);
    await tester.tap(find.byKey(const ValueKey('page-field')));
    await tester.pump();
    await tester.enterText(find.byKey(const ValueKey('page-field')), '3');
    await tester.sendKeyEvent(LogicalKeyboardKey.escape);
    await tester.pump(const Duration(milliseconds: 300));
    debugPrint(
      'after Esc, primaryFocus = ${FocusManager.instance.primaryFocus}',
    );

    await _ctrl(tester, LogicalKeyboardKey.keyT);
    expect(find.byType(OutlinePanel), findsOneWidget);
  });
}
