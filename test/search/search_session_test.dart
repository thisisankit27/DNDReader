import 'package:dndreader/features/search/search_session.dart';
import 'package:dndreader/features/search/search_web_view.dart';
import 'package:flutter_test/flutter_test.dart';

import 'fake_search_web_view.dart';

void main() {
  final results = Uri.parse('https://www.google.com/search?q=fibrosis');

  late FakeSearchWebView view;
  late List<Uri> opened;
  late int factoryCalls;

  SearchSession make({
    FakeSearchWebView? webView,
    Duration timeout = const Duration(seconds: 20),
  }) {
    view = webView ?? FakeSearchWebView();
    opened = [];
    factoryCalls = 0;
    return SearchSession(
      webViewFactory: () {
        factoryCalls++;
        return view;
      },
      openUrl: (uri) async {
        opened.add(uri);
        return true;
      },
      loadTimeout: timeout,
    );
  }

  test('first search starts the browser and reaches loaded', () async {
    final s = make();
    addTearDown(s.dispose);
    expect(s.phase, SearchPhase.idle);

    final done = s.search(results, 'fibrosis');
    expect(s.phase, SearchPhase.starting);
    await done;

    expect(view.started, [results]);
    expect(s.phase, SearchPhase.loading);
    expect(s.visible, isTrue);
    expect(s.queryText, 'fibrosis');

    view.emitUrl(results.toString());
    view.emitLoadEnd(results.toString());
    expect(s.phase, SearchPhase.loaded);
  });

  test('a sub-frame finishing does not mark the page loaded', () async {
    final s = make();
    addTearDown(s.dispose);
    await s.search(results, 'fibrosis');
    view.emitLoadEnd('https://www.youtube.com/embed/abc');
    view.emitLoadEnd('about:blank');
    expect(s.phase, SearchPhase.loading);
  });

  test('a second search reuses the same browser', () async {
    final s = make();
    addTearDown(s.dispose);
    await s.search(results, 'fibrosis');
    view.emitLoadEnd(results.toString());

    final second = Uri.parse('https://www.google.com/search?q=alveoli');
    await s.search(second, 'alveoli');

    expect(factoryCalls, 1, reason: 'one long-lived browser per run');
    expect(view.started, hasLength(1));
    expect(view.loaded, [second]);
    expect(s.phase, SearchPhase.loading);
    expect(s.canGoBack, isFalse, reason: 'history restarts with a new search');
  });

  test('close hides the panel but keeps the browser alive', () async {
    final s = make();
    addTearDown(s.dispose);
    await s.search(results, 'fibrosis');
    s.close();
    expect(s.visible, isFalse);
    expect(view.disposed, isFalse);
    expect(s.webView, isNotNull);
  });

  test('dispose disposes the browser', () async {
    final s = make();
    await s.search(results, 'fibrosis');
    s.dispose();
    expect(view.disposed, isTrue);
  });

  group('fail closed', () {
    test('an unavailable sandbox never loads a page', () async {
      final s = make(
        webView: FakeSearchWebView(unavailableReason: 'userns restricted'),
      );
      addTearDown(s.dispose);
      await s.search(results, 'fibrosis');

      expect(s.phase, SearchPhase.unavailable);
      expect(s.unavailableReason, 'userns restricted');
      expect(s.webView, isNull);
      expect(view.loaded, isEmpty);
      expect(view.disposed, isTrue);
    });

    test('later searches do not retry starting the browser', () async {
      final s = make(webView: FakeSearchWebView(unavailableReason: 'x'));
      addTearDown(s.dispose);
      await s.search(results, 'fibrosis');
      await s.search(Uri.parse('https://www.google.com/search?q=b'), 'b');
      expect(factoryCalls, 1);
      expect(s.phase, SearchPhase.unavailable);
      expect(s.visible, isTrue);
    });

    test(
      'Open in browser opens the search externally when unavailable',
      () async {
        final s = make(webView: FakeSearchWebView(unavailableReason: 'x'));
        addTearDown(s.dispose);
        await s.search(results, 'fibrosis');
        await s.openInBrowser();
        expect(opened, [results]);
      },
    );
  });

  group('failure states', () {
    test('a load that never finishes times out', () async {
      final s = make(timeout: const Duration(milliseconds: 40));
      addTearDown(s.dispose);
      await s.search(results, 'fibrosis');
      await Future<void>.delayed(const Duration(milliseconds: 90));
      expect(s.phase, SearchPhase.failed);
    });

    test('finishing in time cancels the timeout', () async {
      final s = make(timeout: const Duration(milliseconds: 40));
      addTearDown(s.dispose);
      await s.search(results, 'fibrosis');
      view.emitLoadEnd(results.toString());
      await Future<void>.delayed(const Duration(milliseconds: 90));
      expect(s.phase, SearchPhase.loaded);
    });

    test(
      'a reported main-frame load error is a failure (no raw text kept)',
      () async {
        final s = make();
        addTearDown(s.dispose);
        await s.search(results, 'fibrosis');
        view.emitLoadError('https://dndreader-offline.invalid/');
        expect(s.phase, SearchPhase.failed);
      },
    );

    test('a browser error page is a failure; Retry reloads the page', () async {
      final s = make();
      addTearDown(s.dispose);
      await s.search(results, 'fibrosis');
      view.emitLoadEnd('chrome-error://chromewebdata/');
      expect(s.phase, SearchPhase.failed);

      await s.retry();
      expect(s.phase, SearchPhase.loading);
      expect(view.loaded.last, results);
    });
  });

  group('navigation and consent', () {
    test('clicking a result enables Back; Back goes back', () async {
      final s = make();
      addTearDown(s.dispose);
      await s.search(results, 'fibrosis');
      view.emitUrl(results.toString());
      view.emitLoadEnd(results.toString());
      expect(s.canGoBack, isFalse);

      const article =
          'https://www.nhlbi.nih.gov/health/idiopathic-pulmonary-fibrosis';
      view.emitUrl(article);
      expect(s.canGoBack, isTrue);
      expect(s.currentUrl, article);
      view.emitLoadEnd(article);
      expect(s.phase, SearchPhase.loaded);

      await s.back();
      expect(view.backs, 1);
      expect(s.currentUrl, results.toString());
      expect(s.canGoBack, isFalse);
    });

    test('Google rewriting its own URL is not a navigation', () async {
      final s = make();
      addTearDown(s.dispose);
      await s.search(results, 'fibrosis');
      view.emitUrl(results.toString());
      view.emitUrl('${results.toString()}&sei=abc123');
      expect(s.canGoBack, isFalse);
    });

    test('a consent host shows the hint; leaving it hides the hint', () async {
      final s = make();
      addTearDown(s.dispose);
      await s.search(results, 'fibrosis');
      expect(s.consentHint, isFalse);

      view.emitUrl(
        'https://consent.google.com/m?continue=https://www.google.com/search%3Fq%3Dfibrosis',
      );
      expect(s.consentHint, isTrue);

      view.emitUrl(results.toString());
      expect(s.consentHint, isFalse);
    });

    test('Open in browser opens the page currently shown', () async {
      final s = make();
      addTearDown(s.dispose);
      await s.search(results, 'fibrosis');
      view.emitUrl('https://www.nhlbi.nih.gov/health/x');
      await s.openInBrowser();
      expect(opened.single.toString(), 'https://www.nhlbi.nih.gov/health/x');
    });
  });

  group('observed CEF event orders (regressions)', () {
    test(
      'Back: load-end then URL report for the same page stays loaded',
      () async {
        final s = make(timeout: const Duration(milliseconds: 60));
        addTearDown(s.dispose);
        const withSei = 'https://www.google.com/search?q=fibrosis&sei=abc';
        await s.search(results, 'fibrosis');
        view.emitUrl(results.toString());
        view.emitLoadEnd(results.toString());
        view.emitUrl(withSei);
        const article = 'https://pmc.ncbi.nlm.nih.gov/articles/PMC9963026/';
        view.emitUrl(article);
        view.emitLoadEnd(article);
        expect(s.phase, SearchPhase.loaded);

        await s.back(); // phase -> loading
        expect(s.phase, SearchPhase.loading);
        // What CEF actually sent: load-end first, THEN the address change.
        view.emitLoadEnd(withSei);
        expect(s.phase, SearchPhase.loaded);
        view.emitUrl(withSei);
        expect(s.phase, SearchPhase.loaded, reason: 'must not restart loading');

        await Future<void>.delayed(const Duration(milliseconds: 120));
        expect(s.phase, SearchPhase.loaded, reason: 'and must not time out');
      },
    );

    test(
      'Google adding parameters after load does not restart loading',
      () async {
        final s = make(timeout: const Duration(milliseconds: 60));
        addTearDown(s.dispose);
        await s.search(results, 'fibrosis');
        view.emitLoadEnd(results.toString());
        expect(s.phase, SearchPhase.loaded);
        view.emitUrl('${results.toString()}&sei=zzz');
        expect(s.phase, SearchPhase.loaded);
        await Future<void>.delayed(const Duration(milliseconds: 120));
        expect(s.phase, SearchPhase.loaded);
      },
    );

    test('a different page after load does restart loading', () async {
      final s = make();
      addTearDown(s.dispose);
      await s.search(results, 'fibrosis');
      view.emitLoadEnd(results.toString());
      view.emitUrl('https://www.nhlbi.nih.gov/health/x');
      expect(s.phase, SearchPhase.loading);
    });
  });

  group('unsandboxed development override', () {
    test('is honoured in a non-release build when explicitly set', () {
      expect(
        unsandboxedOverrideAllowed(releaseMode: false, envValue: '1'),
        isTrue,
      );
    });

    test('is never honoured in a release build', () {
      expect(
        unsandboxedOverrideAllowed(releaseMode: true, envValue: '1'),
        isFalse,
      );
    });

    test('requires the exact opt-in value', () {
      expect(
        unsandboxedOverrideAllowed(releaseMode: false, envValue: null),
        isFalse,
      );
      expect(
        unsandboxedOverrideAllowed(releaseMode: false, envValue: '0'),
        isFalse,
      );
      expect(
        unsandboxedOverrideAllowed(releaseMode: false, envValue: 'true'),
        isFalse,
      );
      expect(
        unsandboxedOverrideAllowed(releaseMode: false, envValue: ''),
        isFalse,
      );
    });

    test(
      'the test environment (a non-release build) has it off by default',
      () {
        expect(unsandboxedDevOverrideActive, isFalse);
      },
    );
  });
}
