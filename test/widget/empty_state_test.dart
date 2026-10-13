import 'package:dndreader/app.dart';
import 'package:dndreader/features/reader/empty_state.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('shell shows the header and the empty state', (tester) async {
    await tester.pumpWidget(const DndReaderApp());

    expect(find.text('DNDReader'), findsOneWidget);
    expect(find.byType(EmptyState), findsOneWidget);
    expect(find.text('Open a PDF to start reading'), findsOneWidget);
  });

  testWidgets('Open controls are disabled until opening is wired', (
    tester,
  ) async {
    await tester.pumpWidget(const DndReaderApp());

    final button = tester.widget<FilledButton>(
      find.widgetWithText(FilledButton, 'Open PDF'),
    );
    expect(button.onPressed, isNull);
  });

  testWidgets('document controls are disabled with no document', (
    tester,
  ) async {
    await tester.pumpWidget(const DndReaderApp());

    final zoomIn = tester.widget<IconButton>(
      find.widgetWithIcon(IconButton, Icons.add),
    );
    expect(zoomIn.onPressed, isNull);
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
}
