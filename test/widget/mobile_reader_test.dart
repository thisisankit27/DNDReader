import 'package:dndreader/features/reader/reader_header.dart';
import 'package:dndreader/features/reader/reader_menu.dart';
import 'package:dndreader/features/reader/reader_screen.dart';
import 'package:dndreader/features/reader/selection_action_controller.dart';
import 'package:dndreader/features/reader/selection_anchor.dart';
import 'package:dndreader/features/reader/selection_pill.dart';
import 'package:dndreader/features/search/search_panel.dart';
import 'package:dndreader/features/search/search_presentation.dart';
import 'package:dndreader/features/search/search_session.dart';
import 'package:dndreader/models/app_settings.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

import '../search/fake_search_web_view.dart';

class _ReadyAction extends SelectionActionController {
  @override
  String? get query => 'idiopathic pulmonary fibrosis';
  @override
  bool get available => true;
}

Widget _header({bool phone = false}) => MaterialApp(
  home: Scaffold(
    body: ReaderHeader(
      title: 'spec.pdf',
      pageNumber: 3,
      pageCount: 19,
      onOpen: () {},
      onRotate: () {},
      onToggleFullscreen: () {},
      onZoomIn: () {},
      onZoomOut: () {},
      onToggleContents: () {},
      phone: phone,
    ),
  ),
);

void main() {
  group('the touch pill', () {
    Future<void> pump(WidgetTester tester, {required bool touch}) async {
      final controller = ValueNotifier<int>(0);
      addTearDown(controller.dispose);
      await tester.pumpWidget(
        MaterialApp(
          home: SizedBox(
            width: 400,
            height: 800,
            child: SelectionPill(
              repaint: controller,
              touch: touch,
              onPressed: () {},
              anchors: () => const SelectionAnchors(
                start: Rect.fromLTWH(100, 300, 10, 20),
                end: Rect.fromLTWH(180, 300, 10, 20),
              ),
            ),
          ),
        ),
      );
    }

    testWidgets('desktop shows the Ctrl+E hint and sits 8 dp below', (
      tester,
    ) async {
      await pump(tester, touch: false);
      expect(find.text('Ctrl+E'), findsOneWidget);
      final rect = tester.getRect(find.byKey(SelectionPill.pillKey));
      expect(rect.top - 320, 8);
      expect(rect.height, 44);
    });

    testWidgets(
      'touch has no hint, a 48 dp target, and clears the selection handles',
      (tester) async {
        await pump(tester, touch: true);
        expect(find.text('Ctrl+E'), findsNothing);
        final rect = tester.getRect(find.byKey(SelectionPill.pillKey));
        expect(rect.height, greaterThanOrEqualTo(48));
        expect(rect.top - 320, SelectionPill.touchGap);
        expect(SelectionPill.touchGap, greaterThan(24)); // taller than a handle
      },
    );

    testWidgets('the pill is labelled for a screen reader as a button', (
      tester,
    ) async {
      final handle = tester.ensureSemantics();
      await pump(tester, touch: true);
      final data = tester
          .getSemantics(find.byKey(SelectionPill.pillKey))
          .getSemanticsData();
      expect(data.label, 'Find meaning of the selected text');
      expect(data.flagsCollection.isButton, isTrue);
      handle.dispose();
    });
  });

  group('the phone header', () {
    testWidgets('desktop keeps rotate and full screen buttons', (tester) async {
      tester.view.physicalSize = const Size(432, 984);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.reset);
      await tester.pumpWidget(_header());
      expect(find.byIcon(Icons.rotate_right), findsOneWidget);
      expect(find.byIcon(Icons.fullscreen), findsOneWidget);
      expect(find.byTooltip('Contents (Ctrl+T)'), findsOneWidget);
    });

    testWidgets(
      'phone moves them to the menu, frees room for the title, and drops shortcut text',
      (tester) async {
        tester.view.physicalSize = const Size(432, 984);
        tester.view.devicePixelRatio = 1.0;
        addTearDown(tester.view.reset);
        await tester.pumpWidget(_header(phone: true));
        expect(find.byIcon(Icons.rotate_right), findsNothing);
        expect(find.byIcon(Icons.fullscreen), findsNothing);
        expect(find.byTooltip('Contents'), findsOneWidget);
        expect(find.byTooltip('Open PDF'), findsOneWidget);
        expect(tester.takeException(), isNull);
        // The title is readable, not squeezed to nothing.
        expect(tester.getSize(find.text('spec.pdf')).width, greaterThan(60));
      },
    );

    testWidgets('the page field is named as one control on a phone', (
      tester,
    ) async {
      final handle = tester.ensureSemantics();
      await tester.pumpWidget(_header(phone: true));
      expect(find.bySemanticsLabel('Page number, of 19'), findsOneWidget);
      handle.dispose();
    });
  });

  group('the menu and the dialog on a phone', () {
    testWidgets('offers rotate, full screen and "Gestures and shortcuts"', (
      tester,
    ) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: ReaderMenu(
              themeMode: ThemeMode.system,
              onThemeMode: (_) {},
              selectionHighlight: SelectionHighlight.skyBlue,
              onSelectionHighlight: (_) {},
              recents: const [],
              onOpenRecent: (_) {},
              onShowShortcuts: () {},
              onShowAbout: () {},
              touch: true,
              onRotate: () {},
              onFitPage: () {},
              onToggleFullscreen: () {},
            ),
          ),
        ),
      );
      await tester.tap(find.byTooltip('Menu'));
      await tester.pumpAndSettle();
      expect(find.text('Rotate page'), findsOneWidget);
      expect(find.text('Fit page'), findsOneWidget);
      expect(find.text('Full screen'), findsOneWidget);
      expect(find.text('Gestures and shortcuts'), findsOneWidget);
      expect(find.text('Keyboard shortcuts'), findsNothing);
    });

    testWidgets(
      'the touch dialog lists gestures first, then the keyboard shortcuts',
      (tester) async {
        await tester.pumpWidget(
          MaterialApp(
            home: Builder(
              builder: (context) => TextButton(
                onPressed: () => showShortcutsDialog(context, touch: true),
                child: const Text('go'),
              ),
            ),
          ),
        );
        await tester.tap(find.text('go'));
        await tester.pumpAndSettle();
        expect(find.text('Long-press'), findsOneWidget);
        expect(find.text('Double-tap'), findsOneWidget);
        expect(find.text('With a keyboard attached'), findsOneWidget);
        expect(find.text('Ctrl+E'), findsOneWidget);
      },
    );

    testWidgets('the desktop dialog is unchanged', (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Builder(
            builder: (context) => TextButton(
              onPressed: () => showShortcutsDialog(context),
              child: const Text('go'),
            ),
          ),
        ),
      );
      await tester.tap(find.text('go'));
      await tester.pumpAndSettle();
      expect(find.text('Keyboard shortcuts'), findsOneWidget);
      expect(find.text('Long-press'), findsNothing);
    });
  });

  group('system back, one layer at a time (touch layout only)', () {
    Future<SearchSession> pumpReader(
      WidgetTester tester,
      SearchPresentation presentation,
    ) async {
      tester.view.physicalSize = const Size(432, 984);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.reset);
      final search = SearchSession(webViewFactory: FakeSearchWebView.new);
      await tester.pumpWidget(
        MaterialApp(
          home: ReaderScreen(
            actionController: _ReadyAction(),
            searchSession: search,
            searchPresentation: presentation,
          ),
        ),
      );
      await tester.sendKeyDownEvent(LogicalKeyboardKey.controlLeft);
      await tester.sendKeyEvent(LogicalKeyboardKey.keyE);
      await tester.sendKeyUpEvent(LogicalKeyboardKey.controlLeft);
      await tester.pump();
      await tester.pump();
      return search;
    }

    testWidgets('back closes the open search sheet before anything else', (
      tester,
    ) async {
      final popped = <MethodCall>[];
      tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
        SystemChannels.platform,
        (call) async {
          popped.add(call);
          return null;
        },
      );
      addTearDown(
        () => tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
          SystemChannels.platform,
          null,
        ),
      );
      final search = await pumpReader(tester, SearchPresentation.adaptive);
      expect(search.visible, isTrue);

      await tester.binding.handlePopRoute();
      await tester.pump();
      expect(search.visible, isFalse, reason: 'first back dismisses the panel');
      expect(popped.where((c) => c.method == 'SystemNavigator.pop'), isEmpty);

      await tester.pumpWidget(const SizedBox());
      search.dispose();
    });

    testWidgets('on desktop the reader does not intercept back at all', (
      tester,
    ) async {
      final search = await pumpReader(tester, SearchPresentation.sidePanel);
      expect(search.visible, isTrue);
      await tester.binding.handlePopRoute();
      await tester.pump();
      expect(
        search.visible,
        isTrue,
        reason: 'desktop has Esc; nothing changes there',
      );
      await tester.pumpWidget(const SizedBox());
      search.dispose();
    });
  });

  group('keep the screen on while a document is open', () {
    testWidgets('asked on open, not asked on desktop', (tester) async {
      final calls = <MethodCall>[];
      tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
        const MethodChannel('dndreader/window'),
        (call) async {
          calls.add(call);
          return null;
        },
      );
      addTearDown(
        () => tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
          const MethodChannel('dndreader/window'),
          null,
        ),
      );

      await tester.pumpWidget(
        const MaterialApp(
          home: ReaderScreen(searchPresentation: SearchPresentation.adaptive),
        ),
      );
      await tester.pump();
      expect(
        calls
            .where((c) => c.method == 'setKeepScreenOn')
            .map((c) => c.arguments),
        [false],
        reason: 'no document: the screen may sleep',
      );

      calls.clear();
      await tester.pumpWidget(const SizedBox());
      await tester.pumpWidget(
        const MaterialApp(home: ReaderScreen(initialPath: '/nowhere/x.pdf')),
      );
      await tester.pump();
      expect(calls.where((c) => c.method == 'setKeepScreenOn'), isEmpty);
    });
  });

  group('the panel header on a phone', () {
    testWidgets('Close has no shortcut text for a screen reader to read', (
      tester,
    ) async {
      final search = SearchSession(webViewFactory: FakeSearchWebView.new);
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: SearchPanel(session: search, onClose: () {}, touch: true),
          ),
        ),
      );
      expect(find.byTooltip('Close'), findsOneWidget);
      expect(find.byTooltip('Close (Esc)'), findsNothing);
      await tester.pumpWidget(const SizedBox());
      search.dispose();
    });
  });
}
