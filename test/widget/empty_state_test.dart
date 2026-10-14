import 'package:dndreader/app.dart';
import 'package:dndreader/features/reader/empty_state.dart';
import 'package:dndreader/features/reader/open_failure.dart';
import 'package:dndreader/features/reader/reader_screen.dart';
import 'package:dndreader/features/reader/selection_action_controller.dart';
import 'package:dndreader/features/search/search_session.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

import '../search/fake_search_web_view.dart';

void main() {
  testWidgets('shell shows the header and the empty state', (tester) async {
    await tester.pumpWidget(const DndReaderApp());

    expect(find.text('DNDReader'), findsOneWidget);
    expect(find.byType(EmptyState), findsOneWidget);
    expect(find.text('Open a PDF to start reading'), findsOneWidget);
  });

  testWidgets('document controls are disabled with no document', (
    tester,
  ) async {
    await tester.pumpWidget(const DndReaderApp());

    final zoomIn = tester.widget<IconButton>(
      find.widgetWithIcon(IconButton, Icons.add),
    );
    expect(zoomIn.onPressed, isNull);
    expect(
      find.textContaining(' / '),
      findsNothing,
      reason: 'no page indicator without a document',
    );
  });

  testWidgets('Open asks the picker; cancelling leaves the empty state', (
    tester,
  ) async {
    var asked = 0;
    await tester.pumpWidget(
      MaterialApp(
        home: ReaderScreen(
          pickPdf: () async {
            asked++;
            return null;
          },
        ),
      ),
    );

    await tester.tap(find.widgetWithText(FilledButton, 'Open PDF'));
    await tester.pump();
    expect(asked, 1);
    expect(find.byType(EmptyState), findsOneWidget);
  });

  testWidgets('Ctrl+O triggers the picker', (tester) async {
    var asked = 0;
    await tester.pumpWidget(
      MaterialApp(
        home: ReaderScreen(
          pickPdf: () async {
            asked++;
            return null;
          },
        ),
      ),
    );

    await tester.sendKeyDownEvent(LogicalKeyboardKey.controlLeft);
    await tester.sendKeyEvent(LogicalKeyboardKey.keyO);
    await tester.sendKeyUpEvent(LogicalKeyboardKey.controlLeft);
    await tester.pump();
    expect(asked, 1);
  });

  testWidgets('the failure state names the file and offers another', (
    tester,
  ) async {
    var again = 0;
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: OpenFailure(
            fileName: 'broken.pdf',
            onOpenAnother: () => again++,
          ),
        ),
      ),
    );

    expect(find.textContaining('broken.pdf'), findsOneWidget);
    expect(
      find.textContaining('Exception'),
      findsNothing,
      reason: 'no raw error strings',
    );
    await tester.tap(find.text('Open another PDF'));
    expect(again, 1);
  });

  testWidgets('layout survives a narrow window without overflow', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(360, 640);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(const DndReaderApp());
    expect(tester.takeException(), isNull);
  });

  testWidgets(
    'Ctrl+E searches for the held query; Esc closes the panel, then dismisses',
    (tester) async {
      final action = _ReadyAction('idiopathic pulmonary fibrosis');
      final view = FakeSearchWebView();
      final search = SearchSession(webViewFactory: () => view);
      await tester.pumpWidget(
        MaterialApp(
          home: ReaderScreen(actionController: action, searchSession: search),
        ),
      );
      expect(action.available, isTrue);

      await tester.sendKeyDownEvent(LogicalKeyboardKey.controlLeft);
      await tester.sendKeyEvent(LogicalKeyboardKey.keyE);
      await tester.sendKeyUpEvent(LogicalKeyboardKey.controlLeft);
      await tester.pump();

      expect(search.visible, isTrue);
      expect(search.queryText, 'idiopathic pulmonary fibrosis');
      expect(
        view.started.single.toString(),
        'https://www.google.com/search?q=idiopathic+pulmonary+fibrosis',
      );

      // First Esc closes the panel and leaves the selection action alone.
      await tester.sendKeyEvent(LogicalKeyboardKey.escape);
      await tester.pump();
      expect(search.visible, isFalse);
      expect(action.available, isTrue);

      // Second Esc dismisses the action.
      await tester.sendKeyEvent(LogicalKeyboardKey.escape);
      await tester.pump();
      expect(action.available, isFalse);

      await tester.pumpWidget(const SizedBox());
      search.dispose();
    },
  );

  testWidgets('Ctrl+E does nothing without a searchable selection', (
    tester,
  ) async {
    final action = SelectionActionController();
    await tester.pumpWidget(
      MaterialApp(home: ReaderScreen(actionController: action)),
    );

    await tester.sendKeyDownEvent(LogicalKeyboardKey.controlLeft);
    await tester.sendKeyEvent(LogicalKeyboardKey.keyE);
    await tester.sendKeyUpEvent(LogicalKeyboardKey.controlLeft);
    await tester.pump();
    expect(find.textContaining('Find meaning:'), findsNothing);
  });
}

/// A controller that is already "settled" on a query.
class _ReadyAction extends SelectionActionController {
  _ReadyAction(this._fixed);

  final String _fixed;
  bool _hidden = false;

  @override
  String? get query => _fixed;

  @override
  bool get available => !_hidden;

  @override
  void dismiss() {
    _hidden = true;
    notifyListeners();
  }
}
