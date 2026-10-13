import 'package:dndreader/features/reader/selection_anchor.dart';
import 'package:dndreader/features/reader/selection_pill.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  const view = Size(800, 600);

  Future<void> pump(
    WidgetTester tester, {
    required ValueNotifier<SelectionAnchors?> anchors,
    VoidCallback? onPressed,
  }) async {
    tester.view.physicalSize = view;
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: ValueListenableBuilder<SelectionAnchors?>(
            valueListenable: anchors,
            builder: (context, a, _) => SelectionPill(
              anchors: () => a,
              repaint: anchors,
              onPressed: onPressed ?? () {},
            ),
          ),
        ),
      ),
    );
  }

  SelectionAnchors line(double x, double y, {double w = 60}) =>
      SelectionAnchors(
        start: Rect.fromLTWH(x, y, 8, 18),
        end: Rect.fromLTWH(x + w, y, 8, 18),
      );

  Rect pillRect(WidgetTester tester) {
    final box = tester.renderObject<RenderBox>(
      find.byKey(SelectionPill.pillKey),
    );
    return box.localToGlobal(Offset.zero) & box.size;
  }

  testWidgets('appears below the end of the selection', (tester) async {
    final anchors = ValueNotifier<SelectionAnchors?>(line(300, 200));
    await pump(tester, anchors: anchors);

    expect(find.text('Find meaning'), findsOneWidget);
    final r = pillRect(tester);
    expect(r.top, closeTo(200 + 18 + 8, 0.5));
    expect(r.center.dx, closeTo(360 + 4, 1.0)); // centred on the end character
  });

  testWidgets('flips above near the bottom edge and stays inside the view', (
    tester,
  ) async {
    final anchors = ValueNotifier<SelectionAnchors?>(line(300, 570));
    await pump(tester, anchors: anchors);

    final r = pillRect(tester);
    expect(r.bottom, lessThan(570));
    expect(r.top, greaterThanOrEqualTo(8));
  });

  testWidgets('follows the selection when the view scrolls', (tester) async {
    final anchors = ValueNotifier<SelectionAnchors?>(line(300, 300));
    await pump(tester, anchors: anchors);
    final before = pillRect(tester).top;

    anchors.value = line(300, 200); // scrolled up by 100
    await tester.pump();
    expect(pillRect(tester).top, closeTo(before - 100, 0.5));
  });

  testWidgets('disappears when the selection is scrolled out of view', (
    tester,
  ) async {
    final anchors = ValueNotifier<SelectionAnchors?>(line(300, 300));
    await pump(tester, anchors: anchors);
    expect(find.byKey(SelectionPill.pillKey), findsOneWidget);

    anchors.value = line(300, -400);
    await tester.pump();
    expect(find.byKey(SelectionPill.pillKey), findsNothing);
  });

  testWidgets('uses the start of the selection when only that is on screen', (
    tester,
  ) async {
    final anchors = ValueNotifier<SelectionAnchors?>(
      const SelectionAnchors(
        start: Rect.fromLTWH(100, 100, 8, 18),
        end: Rect.fromLTWH(100, 900, 8, 18),
      ),
    );
    await pump(tester, anchors: anchors);
    expect(find.byKey(SelectionPill.pillKey), findsOneWidget);
    expect(pillRect(tester).top, closeTo(100 + 18 + 8, 0.5));
  });

  testWidgets('tapping the pill invokes the action', (tester) async {
    var taps = 0;
    final anchors = ValueNotifier<SelectionAnchors?>(line(300, 200));
    await pump(tester, anchors: anchors, onPressed: () => taps++);

    await tester.tap(find.byKey(SelectionPill.pillKey));
    expect(taps, 1);
  });

  testWidgets('does not intercept taps elsewhere (hit-test transparent)', (
    tester,
  ) async {
    var behind = 0;
    final anchors = ValueNotifier<SelectionAnchors?>(line(300, 200));
    tester.view.physicalSize = view;
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Stack(
            children: [
              Positioned.fill(
                child: GestureDetector(
                  behavior: HitTestBehavior.opaque,
                  onTap: () => behind++,
                ),
              ),
              Positioned.fill(
                child: SelectionPill(
                  anchors: () => anchors.value,
                  repaint: anchors,
                  onPressed: () {},
                ),
              ),
            ],
          ),
        ),
      ),
    );

    await tester.tapAt(const Offset(700, 500));
    expect(
      behind,
      1,
      reason: 'a tap away from the pill must reach the viewer underneath',
    );
  });

  testWidgets('scroll signals over the pill are forwarded, not swallowed', (
    tester,
  ) async {
    final received = <PointerSignalEvent>[];
    final anchors = ValueNotifier<SelectionAnchors?>(line(300, 200));
    tester.view.physicalSize = view;
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SelectionPill(
            anchors: () => anchors.value,
            repaint: anchors,
            onPressed: () {},
            onScrollSignal: received.add,
          ),
        ),
      ),
    );

    final center = tester.getCenter(find.byKey(SelectionPill.pillKey));
    final pointer = TestPointer(1, PointerDeviceKind.mouse)..hover(center);
    await tester.sendEventToBinding(pointer.scroll(const Offset(0, 120)));
    expect(received, hasLength(1));
    expect(received.single, isA<PointerScrollEvent>());
  });
}
