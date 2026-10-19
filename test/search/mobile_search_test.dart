import 'package:dndreader/features/reader/reader_screen.dart';
import 'package:dndreader/features/reader/selection_action_controller.dart';
import 'package:dndreader/features/search/embedded_browser_info.dart';
import 'package:dndreader/features/search/search_panel.dart';
import 'package:dndreader/features/search/search_presentation.dart';
import 'package:dndreader/features/search/search_session.dart';
import 'package:dndreader/features/search/search_sheet.dart';
import 'package:dndreader/features/search/search_web_view_mobile.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

import 'fake_search_web_view.dart';

class _ReadyAction extends SelectionActionController {
  @override
  String? get query => 'idiopathic pulmonary fibrosis';
  @override
  bool get available => true;
}

void main() {
  group('decideNavigation (what the panel will and will not load)', () {
    test('web pages load in the panel', () {
      for (final url in [
        'https://www.google.com/search?q=cat',
        'http://example.com/',
        'about:blank',
      ]) {
        expect(decideNavigation(url), NavigationVerdict.allow, reason: url);
      }
    });

    test('tel:, mailto: and sms: go to the system, never into the panel', () {
      for (final url in ['tel:+15551234', 'mailto:a@b.example', 'sms:123']) {
        expect(decideNavigation(url), NavigationVerdict.external, reason: url);
      }
    });

    test('intent:, market:, file:, content:, javascript:, data:, blob: are dropped', () {
      for (final url in [
        'intent://scan/#Intent;scheme=zxing;end',
        'market://details?id=com.example',
        'file:///data/data/x/secret',
        'content://contacts/people',
        'javascript:alert(1)',
        'data:text/html,hi',
        'blob:https://x/1',
        'weird://thing',
      ]) {
        expect(decideNavigation(url), NavigationVerdict.block, reason: url);
      }
    });

    test(
      'a link to a PDF opens outside the panel (the WebView cannot show one)',
      () {
        expect(
          decideNavigation('https://example.com/paper.PDF'),
          NavigationVerdict.external,
        );
        expect(
          decideNavigation('https://example.com/paper.pdf?x=1'),
          NavigationVerdict.external,
        );
        expect(
          decideNavigation('https://example.com/pdf-guide'),
          NavigationVerdict.allow,
        );
      },
    );

    test('garbage is blocked, not thrown on', () {
      expect(decideNavigation('http://[bad'), NavigationVerdict.block);
      expect(decideNavigation(''), NavigationVerdict.block);
    });
  });

  group('MobileSearchWebView before it starts', () {
    test('navigation calls are silent no-ops, dispose is idempotent', () async {
      final view = MobileSearchWebView();
      await view.loadUrl(Uri.parse('https://example.com'));
      await view.goBack();
      await view.reload();
      await view.releaseFocus();
      view.dispose();
      view.dispose();
      expect(view.widget, isA<SizedBox>());
    });

    test('capabilities are declared honestly', () {
      final caps = MobileSearchWebView().capabilities;
      expect(caps.reportsHistory, isTrue);
      expect(caps.releaseFocusIsNoop, isTrue);
    });
  });

  group('SearchSheet.snapFor', () {
    test('a slow release goes to the nearest resting height', () {
      expect(SearchSheet.snapFor(0.55, 0), 0.5);
      expect(SearchSheet.snapFor(0.8, 0), 0.92);
    });
    test(
      'released low closes it',
      () => expect(SearchSheet.snapFor(0.2, 0), isNull),
    );
    test(
      'a fast fling up goes to the top',
      () => expect(SearchSheet.snapFor(0.5, -2000), 0.92),
    );
    test('a fast fling down from the top goes to the middle, from the middle closes', () {
      expect(SearchSheet.snapFor(0.92, 2000), 0.5);
      expect(SearchSheet.snapFor(0.5, 2000), isNull);
    });
  });

  group('SearchPresentation', () {
    test('the sheet is for phone widths only', () {
      expect(SearchPresentation.adaptive.usesSheet(432), isTrue);
      expect(SearchPresentation.adaptive.usesSheet(599.9), isTrue);
      expect(SearchPresentation.adaptive.usesSheet(600), isFalse);
      expect(SearchPresentation.adaptive.usesSheet(1200), isFalse);
    });
    test('desktop is always the side panel', () {
      expect(SearchPresentation.sidePanel.usesSheet(300), isFalse);
    });
  });

  group(
    'Android wording (the flag defaults to false, so desktop is unchanged)',
    () {
      test('About names the system WebView and who patches it', () {
        final text = embeddedBrowserLines(
          windows: false,
          android: true,
          runtimeVersion: 'com.google.android.webview 149.0.7827.160',
        );
        expect(
          text,
          contains(
            'Android System WebView com.google.android.webview 149.0.7827.160',
          ),
        );
        expect(text, contains('provided and updated by Android'));
        expect(text, contains('not bundled with or patched by DNDReader'));
        expect(text, contains('cleared each time the app starts'));
      });

      test('About with no WebView version says so instead of guessing', () {
        expect(
          embeddedBrowserLines(windows: false, android: true),
          contains('version not available'),
        );
      });

      test('existing platforms are untouched by the new flag', () {
        expect(
          embeddedBrowserLines(windows: false),
          startsWith('Embedded browser: '),
        );
        expect(
          embeddedBrowserLines(windows: false),
          isNot(contains('Android')),
        );
        expect(
          embeddedBrowserLines(windows: true, runtimeVersion: '1.2'),
          contains('WebView2 Runtime 1.2'),
        );
      });

      test('panel texts: Android has its own, others are as before', () {
        expect(
          SearchPanel.consentNote(windows: false, android: true),
          contains('cleared'),
        );
        expect(
          SearchPanel.consentNote(windows: false, android: true),
          isNot(contains('quit')),
        );
        expect(
          SearchPanel.consentNote(windows: false),
          contains('not kept on disk'),
        );
        expect(
          SearchPanel.consentNote(windows: true),
          contains('temporary folder'),
        );
        expect(
          SearchPanel.unavailableBody(windows: false, android: true),
          contains('WebView'),
        );
        expect(
          SearchPanel.unavailableBody(windows: false),
          contains('sandbox'),
        );
        expect(
          SearchPanel.unavailableBody(windows: true),
          contains('WebView2'),
        );
      });
    },
  );

  group('the reader presents search by window width', () {
    Future<SearchSession> openSearch(
      WidgetTester tester,
      Size size,
      SearchPresentation presentation,
    ) async {
      tester.view.physicalSize = size;
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

    // The session holds a load timeout; end each test the way the reader tests do.
    Future<void> finish(WidgetTester tester, SearchSession search) async {
      await tester.pumpWidget(const SizedBox());
      search.dispose();
    }

    testWidgets('a phone-width window with adaptive shows the bottom sheet', (
      tester,
    ) async {
      final search = await openSearch(
        tester,
        const Size(432, 984),
        SearchPresentation.adaptive,
      );
      expect(find.byType(SearchSheet), findsOneWidget);
      expect(find.byType(SearchPanel), findsOneWidget);
      // The sheet rests at half the reading area, not full height.
      expect(
        tester.getSize(find.byType(SearchPanel)).height,
        lessThan(984 * 0.6),
      );
      await finish(tester, search);
    });

    testWidgets('a tablet-width window with adaptive keeps the side panel', (
      tester,
    ) async {
      final search = await openSearch(
        tester,
        const Size(1000, 700),
        SearchPresentation.adaptive,
      );
      expect(find.byType(SearchSheet), findsNothing);
      expect(find.byType(SearchPanel), findsOneWidget);
      await finish(tester, search);
    });

    testWidgets(
      'the default (desktop) never shows a sheet, even on a narrow window',
      (tester) async {
        final search = await openSearch(
          tester,
          const Size(432, 984),
          SearchPresentation.sidePanel,
        );
        expect(find.byType(SearchSheet), findsNothing);
        expect(find.byType(SearchPanel), findsOneWidget);
        await finish(tester, search);
      },
    );

    testWidgets('closing the panel keeps the one browser alive, hidden', (
      tester,
    ) async {
      final search = await openSearch(
        tester,
        const Size(432, 984),
        SearchPresentation.adaptive,
      );
      search.close();
      await tester.pump();
      expect(search.webView, isNotNull);
      // Offstage: neither painted nor hit-tested, but still in the tree.
      expect(find.byType(SearchPanel), findsNothing);
      expect(find.byType(SearchPanel, skipOffstage: false), findsOneWidget);
      await finish(tester, search);
    });
  });
}
