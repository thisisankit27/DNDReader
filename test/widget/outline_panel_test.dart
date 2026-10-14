import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pdfrx/pdfrx.dart';

import 'package:dndreader/features/reader/outline_panel.dart';

PdfOutlineNode _node(
  String title,
  int? page, [
  List<PdfOutlineNode> children = const [],
]) => PdfOutlineNode(
  title: title,
  dest: page == null ? null : PdfDest(page, PdfDestCommand.fit, null),
  children: children,
);

Widget _host({
  required List<PdfOutlineNode>? outline,
  ValueChanged<PdfDest>? onSelect,
  VoidCallback? onClose,
  int? currentPage,
}) => MaterialApp(
  home: Scaffold(
    body: SizedBox(
      width: OutlinePanel.width,
      child: OutlinePanel(
        outline: outline,
        currentPage: currentPage,
        onSelect: onSelect ?? (_) {},
        onClose: onClose ?? () {},
      ),
    ),
  ),
);

void main() {
  testWidgets('shows a spinner while the outline loads', (tester) async {
    await tester.pumpWidget(_host(outline: null));
    expect(find.byType(CircularProgressIndicator), findsOneWidget);
  });

  testWidgets('says so when the document has no outline', (tester) async {
    await tester.pumpWidget(_host(outline: const []));
    expect(
      find.text('This document has no table of contents.'),
      findsOneWidget,
    );
  });

  testWidgets('sub-topics are collapsed until the topic is expanded', (
    tester,
  ) async {
    await tester.pumpWidget(
      _host(
        outline: [
          _node('1. Introduction', 1),
          _node('2. Method', 3, [_node('2.1 Data', 4)]),
        ],
      ),
    );
    expect(find.text('1. Introduction'), findsOneWidget);
    expect(find.text('2. Method'), findsOneWidget);
    expect(find.text('3'), findsOneWidget);
    expect(find.text('2.1 Data'), findsNothing);

    await tester.tap(find.byTooltip('Expand'));
    await tester.pump();
    expect(find.text('2.1 Data'), findsOneWidget);
    expect(find.text('4'), findsOneWidget);

    await tester.tap(find.byTooltip('Collapse'));
    await tester.pump();
    expect(find.text('2.1 Data'), findsNothing);
  });

  testWidgets('toggling a topic does not navigate', (tester) async {
    PdfDest? picked;
    await tester.pumpWidget(
      _host(
        outline: [
          _node('Chapter', 2, [_node('Section', 3)]),
        ],
        onSelect: (d) => picked = d,
      ),
    );
    await tester.tap(find.byTooltip('Expand'));
    await tester.pump();
    expect(picked, isNull);
  });

  testWidgets('the branch holding the current page starts expanded', (
    tester,
  ) async {
    await tester.pumpWidget(
      _host(
        currentPage: 5,
        outline: [
          _node('A', 1, [_node('A.1', 2)]),
          _node('B', 4, [
            _node('B.1', 5, [_node('B.1.a', 5)]),
            _node('B.2', 7),
          ]),
        ],
      ),
    );
    expect(find.text('A.1'), findsNothing);
    expect(find.text('B.1'), findsOneWidget);
    expect(find.text('B.2'), findsOneWidget);
    // The current entry itself is reachable: its ancestors are open.
    expect(find.text('B.1.a'), findsOneWidget);
  });

  testWidgets('a chapter without sub-topics has no toggle', (tester) async {
    await tester.pumpWidget(_host(outline: [_node('Only', 1)]));
    expect(find.byTooltip('Expand'), findsNothing);
    expect(find.byTooltip('Collapse'), findsNothing);
  });

  testWidgets('tapping an entry reports its destination', (tester) async {
    PdfDest? picked;
    await tester.pumpWidget(
      _host(outline: [_node('Chapter', 7)], onSelect: (d) => picked = d),
    );
    await tester.tap(find.text('Chapter'));
    expect(picked?.pageNumber, 7);
  });

  testWidgets('an entry without a destination is inert', (tester) async {
    PdfDest? picked;
    await tester.pumpWidget(
      _host(outline: [_node('Part I', null)], onSelect: (d) => picked = d),
    );
    await tester.tap(find.text('Part I'));
    expect(picked, isNull);
  });

  testWidgets('close button calls onClose', (tester) async {
    var closed = false;
    await tester.pumpWidget(
      _host(outline: const [], onClose: () => closed = true),
    );
    await tester.tap(find.byIcon(Icons.close));
    expect(closed, isTrue);
  });
}
