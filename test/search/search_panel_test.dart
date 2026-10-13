import 'package:dndreader/features/search/search_panel.dart';
import 'package:dndreader/features/search/search_session.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'fake_search_web_view.dart';

void main() {
  final results = Uri.parse('https://www.google.com/search?q=fibrosis');

  /// Pumps a panel over a session whose first search has run, runs [body], and
  /// always disposes the session (cancelling its load-timeout timer) before the
  /// test ends.
  Future<void> withPanel(
    WidgetTester tester,
    Future<void> Function(
      SearchSession session,
      FakeSearchWebView view,
      List<Uri> opened,
    )
    body, {
    FakeSearchWebView? view,
    VoidCallback? onClose,
  }) async {
    final fake = view ?? FakeSearchWebView();
    final opened = <Uri>[];
    final session = SearchSession(
      webViewFactory: () => fake,
      openUrl: (u) async {
        opened.add(u);
        return true;
      },
    );
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Align(
            alignment: Alignment.centerRight,
            child: SizedBox(
              width: 450,
              child: SearchPanel(session: session, onClose: onClose ?? () {}),
            ),
          ),
        ),
      ),
    );
    await session.search(results, 'idiopathic pulmonary fibrosis');
    await tester.pump();
    try {
      await body(session, fake, opened);
    } finally {
      await tester.pumpWidget(const SizedBox());
      session.dispose();
    }
  }

  testWidgets('shows the query, the browser and a progress bar while loading', (
    tester,
  ) async {
    await withPanel(tester, (session, view, opened) async {
      expect(find.text('idiopathic pulmonary fibrosis'), findsOneWidget);
      expect(find.byKey(const ValueKey('fake-webview')), findsOneWidget);
      expect(find.byType(LinearProgressIndicator), findsOneWidget);
    });
  });

  testWidgets('the progress bar goes away once loaded', (tester) async {
    await withPanel(tester, (session, view, opened) async {
      view.emitLoadEnd(results.toString());
      await tester.pump();
      expect(find.byType(LinearProgressIndicator), findsNothing);
    });
  });

  testWidgets('Close calls back', (tester) async {
    var closed = 0;
    await withPanel(tester, onClose: () => closed++, (
      session,
      view,
      opened,
    ) async {
      await tester.tap(find.byTooltip('Close (Esc)'));
      expect(closed, 1);
    });
  });

  testWidgets('Open in browser is always available', (tester) async {
    await withPanel(tester, (session, view, opened) async {
      await tester.tap(find.byTooltip('Open in browser'));
      expect(opened, [results]);
    });
  });

  testWidgets('Back is disabled until the panel has navigated', (tester) async {
    await withPanel(tester, (session, view, opened) async {
      var back = tester.widget<IconButton>(
        find.widgetWithIcon(IconButton, Icons.arrow_back),
      );
      expect(back.onPressed, isNull);

      view.emitUrl(results.toString());
      view.emitUrl('https://www.nhlbi.nih.gov/health/x');
      await tester.pump();
      back = tester.widget<IconButton>(
        find.widgetWithIcon(IconButton, Icons.arrow_back),
      );
      expect(back.onPressed, isNotNull);
    });
  });

  testWidgets('failure state offers Retry and Open in browser, no raw errors', (
    tester,
  ) async {
    await withPanel(tester, (session, view, opened) async {
      view.emitLoadEnd('chrome-error://chromewebdata/');
      await tester.pump();

      expect(find.text('Couldn’t load results'), findsOneWidget);
      expect(find.text('Retry'), findsOneWidget);
      expect(find.textContaining('chrome-error'), findsNothing);

      await tester.tap(find.text('Retry'));
      await tester.pump();
      expect(find.text('Couldn’t load results'), findsNothing);
    });
  });

  testWidgets(
    'sandbox unavailable: explanation + Open in browser, no webview',
    (tester) async {
      await withPanel(
        tester,
        view: FakeSearchWebView(unavailableReason: 'AppArmor restriction'),
        (session, view, opened) async {
          expect(
            find.textContaining('Search can’t run inside DNDReader here'),
            findsOneWidget,
          );
          expect(find.text('AppArmor restriction'), findsOneWidget);
          expect(find.byKey(const ValueKey('fake-webview')), findsNothing);
          expect(view.loaded, isEmpty);

          await tester.tap(
            find.widgetWithText(FilledButton, 'Open in browser'),
          );
          expect(opened, [results]);
        },
      );
    },
  );

  testWidgets('the consent hint appears on a consent host', (tester) async {
    await withPanel(tester, (session, view, opened) async {
      expect(find.textContaining('cookie choice'), findsNothing);
      view.emitUrl('https://consent.google.com/m?continue=x');
      await tester.pump();
      expect(find.textContaining('cookie choice'), findsOneWidget);
    });
  });

  test('panel width is 420–480 and never exceeds the window', () {
    expect(SearchPanel.widthFor(1500), 480);
    expect(SearchPanel.widthFor(1100), 440);
    expect(SearchPanel.widthFor(800), 420);
    expect(SearchPanel.widthFor(360), 360);
  });
}
