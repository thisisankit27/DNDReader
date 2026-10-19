import 'dart:async';

import 'package:dndreader/features/reader/empty_state.dart';
import 'package:dndreader/features/reader/reader_screen.dart';
import 'package:dndreader/services/document_access.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

/// A stand-in for Android's document access: no native side.
class _FakeDocuments implements DocumentAccess {
  final StreamController<DocumentEvent> controller =
      StreamController<DocumentEvent>();
  final ValueNotifier<bool> busy = ValueNotifier<bool>(false);
  final List<List<String>> pruned = [];
  Future<String?> Function() onPick = () async => null;

  @override
  Stream<DocumentEvent> get incoming => controller.stream;
  @override
  ValueListenable<bool> get importing => busy;
  @override
  Future<String?> pick() => onPick();
  @override
  Future<DocumentEvent?> initialDocument() async => null;
  @override
  Future<void> prune(Iterable<String> keep) async => pruned.add(keep.toList());
}

void main() {
  testWidgets('a picker failure is a calm message, not a crash', (
    tester,
  ) async {
    final docs = _FakeDocuments()
      ..onPick = () async => throw const DocumentImportException(
        'That file is no longer available.',
      );
    await tester.pumpWidget(MaterialApp(home: ReaderScreen(documents: docs)));

    await tester.tap(find.widgetWithText(FilledButton, 'Open PDF'));
    await tester.pump();
    await tester.pump();

    expect(find.text('That file is no longer available.'), findsOneWidget);
    expect(find.byType(EmptyState), findsOneWidget);
  });

  testWidgets('the document access, not the desktop picker, is asked', (
    tester,
  ) async {
    var desktopAsked = 0;
    var accessAsked = 0;
    final docs = _FakeDocuments()
      ..onPick = () async {
        accessAsked++;
        return null;
      };
    await tester.pumpWidget(
      MaterialApp(
        home: ReaderScreen(
          documents: docs,
          pickPdf: () async {
            desktopAsked++;
            return null;
          },
        ),
      ),
    );

    await tester.tap(find.widgetWithText(FilledButton, 'Open PDF'));
    await tester.pump();
    expect((accessAsked, desktopAsked), (1, 0));
  });

  testWidgets('a failed intent import shows its reason once', (tester) async {
    final docs = _FakeDocuments();
    await tester.pumpWidget(MaterialApp(home: ReaderScreen(documents: docs)));

    docs.controller.add(const DocumentEvent.failed('Couldn’t open that file.'));
    await tester.pump();
    await tester.pump();

    expect(find.text('Couldn’t open that file.'), findsOneWidget);
    expect(find.byType(EmptyState), findsOneWidget);
  });

  testWidgets('a second intent opens its document and prunes the rest', (
    tester,
  ) async {
    final docs = _FakeDocuments();
    await tester.pumpWidget(MaterialApp(home: ReaderScreen(documents: docs)));

    docs.controller.add(
      const DocumentEvent.opened('/data/documents/k/Spec.pdf'),
    );
    await tester.pump();

    expect(find.text('Spec.pdf'), findsOneWidget);
    expect(docs.pruned, isNotEmpty);
    expect(docs.pruned.last, contains('/data/documents/k/Spec.pdf'));
  });

  testWidgets('a copy in progress shows a thin progress strip', (tester) async {
    final docs = _FakeDocuments();
    await tester.pumpWidget(MaterialApp(home: ReaderScreen(documents: docs)));
    expect(find.byType(LinearProgressIndicator), findsNothing);

    docs.busy.value = true;
    await tester.pump();
    expect(find.byType(LinearProgressIndicator), findsOneWidget);
  });

  testWidgets('without document access the screen is exactly as before', (
    tester,
  ) async {
    await tester.pumpWidget(const MaterialApp(home: ReaderScreen()));
    expect(find.byType(LinearProgressIndicator), findsNothing);
    expect(find.byType(EmptyState), findsOneWidget);
  });
}
