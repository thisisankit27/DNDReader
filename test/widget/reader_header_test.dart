import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:dndreader/features/reader/reader_header.dart';

Widget _host({
  int? page = 3,
  int? count = 40,
  ValueChanged<int>? onGoToPage,
  VoidCallback? onDone,
  VoidCallback? onRotate,
  VoidCallback? onFullscreen,
  bool fullscreen = false,
}) => MaterialApp(
  home: Scaffold(
    body: ReaderHeader(
      title: 'doc.pdf',
      pageNumber: page,
      pageCount: count,
      onGoToPage: onGoToPage,
      onPageEditDone: onDone,
      onRotate: onRotate,
      fullscreen: fullscreen,
      onToggleFullscreen: onFullscreen,
      onZoomIn: () {},
      onZoomOut: () {},
      onOpen: () {},
    ),
  ),
);

Future<void> _enter(WidgetTester tester, String text) async {
  await tester.tap(find.byKey(const ValueKey('page-field')));
  await tester.pump();
  await tester.enterText(find.byKey(const ValueKey('page-field')), text);
  await tester.testTextInput.receiveAction(TextInputAction.done);
  await tester.pump();
}

void main() {
  setUp(() => TestWidgetsFlutterBinding.ensureInitialized());

  testWidgets('shows the current page and the page count', (tester) async {
    await tester.pumpWidget(_host());
    expect(find.text('3'), findsOneWidget);
    expect(find.text('/ 40'), findsOneWidget);
  });

  testWidgets('typing a page number and confirming jumps there', (
    tester,
  ) async {
    int? went;
    var done = 0;
    await tester.pumpWidget(
      _host(onGoToPage: (p) => went = p, onDone: () => done++),
    );
    await _enter(tester, '17');
    expect(went, 17);
    expect(done, 1);
  });

  testWidgets('a number past the end goes to the last page', (tester) async {
    int? went;
    await tester.pumpWidget(_host(onGoToPage: (p) => went = p));
    await _enter(tester, '999');
    expect(went, 40);
  });

  testWidgets('zero goes to the first page', (tester) async {
    int? went;
    await tester.pumpWidget(_host(onGoToPage: (p) => went = p));
    await _enter(tester, '0');
    expect(went, 1);
  });

  testWidgets('an empty entry does not jump', (tester) async {
    int? went;
    await tester.pumpWidget(_host(onGoToPage: (p) => went = p));
    await _enter(tester, '');
    expect(went, isNull);
  });

  testWidgets('the field follows the page while it is not being edited', (
    tester,
  ) async {
    await tester.pumpWidget(_host(page: 3));
    await tester.pumpWidget(_host(page: 8));
    final field = tester.widget<TextField>(
      find.byKey(const ValueKey('page-field')),
    );
    expect(field.controller!.text, '8');
  });

  testWidgets('no document: no page field, rotate disabled', (tester) async {
    await tester.pumpWidget(_host(page: null, count: null, onRotate: () {}));
    expect(find.byKey(const ValueKey('page-field')), findsNothing);
    final rotate = tester.widget<IconButton>(
      find.widgetWithIcon(IconButton, Icons.rotate_right),
    );
    expect(rotate.onPressed, isNull);
  });

  testWidgets('rotate and full-screen buttons call back', (tester) async {
    var rotated = 0, toggled = 0;
    await tester.pumpWidget(
      _host(onRotate: () => rotated++, onFullscreen: () => toggled++),
    );
    await tester.tap(find.byIcon(Icons.rotate_right));
    await tester.tap(find.byIcon(Icons.fullscreen));
    expect(rotated, 1);
    expect(toggled, 1);
  });

  testWidgets('the full-screen button shows exit while in full screen', (
    tester,
  ) async {
    await tester.pumpWidget(_host(fullscreen: true, onFullscreen: () {}));
    expect(find.byIcon(Icons.fullscreen_exit), findsOneWidget);
    expect(find.byTooltip('Exit full screen (F11)'), findsOneWidget);
  });
}
