// The SearchWebView contract (docs/search-web-view-contract.md), exercised as
// a single shared suite against any adapter. Layer 1
// (failed_load_end_filter_test.dart's sibling, run in `flutter test`) runs
// this against FakeSearchWebView; Layer 2
// (integration_test/search_web_view_conformance_test.dart) runs the same
// assertions against a real adapter on a real device. Only what's checkable
// without a window lives here — a real engine's own timing and its
// capability-specific behaviour (history/back) are each layer's own job.
import 'package:dndreader/features/search/search_web_view.dart';
import 'package:flutter_test/flutter_test.dart';

import 'fake_search_web_view.dart';

/// Drives [view] to navigate to [url] in a way that will report success or
/// failure through its callbacks. For a scripted double this fires the event
/// directly; for a real adapter this issues a real navigation and the caller
/// is expected to await the resulting callback separately.
typedef TriggerNavigation = Future<void> Function(SearchWebView view, Uri url);

/// Polls [check] until it is true, or fails after [timeout].
Future<void> waitUntil(
  bool Function() check, {
  Duration timeout = const Duration(seconds: 10),
}) async {
  final stopwatch = Stopwatch()..start();
  while (!check()) {
    if (stopwatch.elapsed > timeout) {
      fail('timed out after $timeout waiting for a condition to become true');
    }
    await Future<void>.delayed(const Duration(milliseconds: 20));
  }
}

/// Asserts [check] stays false for [duration] — used to prove silence (e.g.
/// "no callback fires after dispose").
Future<void> assertStaysFalse(
  bool Function() check, {
  Duration duration = const Duration(milliseconds: 300),
}) async {
  final stopwatch = Stopwatch()..start();
  while (stopwatch.elapsed < duration) {
    if (check()) fail('condition became true when it must not have');
    await Future<void>.delayed(const Duration(milliseconds: 20));
  }
}

/// Every [SearchWebView] contract assertion checkable without a real window.
///
/// [startUrl] is loaded by `start()`. [failingUrl] must be a URL
/// [triggerFailure] can make fail; [secondUrl] a *different* URL
/// [triggerSuccess] can make succeed — different so a test can tell "the
/// first navigation's completion" apart from "the second's".
void runSearchWebViewConformance(
  String name,
  SearchWebView Function() createFn, {
  required SearchWebViewCapabilities caps,
  required Uri startUrl,
  required Uri failingUrl,
  required Uri secondUrl,
  required TriggerNavigation triggerFailure,
  required TriggerNavigation triggerSuccess,
}) {
  group(name, () {
    test('dispose before start does not throw', () {
      final view = createFn();
      expect(view.dispose, returnsNormally);
    });

    test('dispose after start is idempotent', () async {
      final view = createFn();
      await view.start(startUrl);
      view.dispose();
      expect(view.dispose, returnsNormally);
    });

    test('no callback fires after dispose', () async {
      final view = createFn();
      var urlChanged = false;
      var loadEnded = false;
      var loadErrored = false;
      view.onUrlChanged = (_) => urlChanged = true;
      view.onLoadEnd = (_) => loadEnded = true;
      view.onLoadError = (_, _, _) => loadErrored = true;
      await view.start(startUrl);
      view.dispose();
      // These are legitimate no-ops after dispose; their point here is that
      // whatever they do, no callback must result from it.
      await view.loadUrl(secondUrl);
      await assertStaysFalse(() => urlChanged || loadEnded || loadErrored);
    });

    test('a load-end for a URL that never failed is forwarded', () async {
      final view = createFn();
      addTearDown(view.dispose);
      final ends = <String>[];
      view.onLoadEnd = ends.add;
      await view.start(startUrl);
      await triggerSuccess(view, startUrl);
      await waitUntil(() => ends.contains(startUrl.toString()));
    });

    test(
      'recovery via an explicit navigation after a failure is reported',
      () async {
        final view = createFn();
        addTearDown(view.dispose);
        var failed = false;
        final ends = <String>[];
        view.onLoadError = (_, _, _) => failed = true;
        view.onLoadEnd = ends.add;
        await view.start(startUrl);
        await triggerFailure(view, failingUrl);
        await waitUntil(() => failed);

        await view.loadUrl(secondUrl);
        await triggerSuccess(view, secondUrl);
        await waitUntil(() => ends.contains(secondUrl.toString()));
      },
    );

    test('releaseFocus never throws', () async {
      final view = createFn();
      addTearDown(view.dispose);
      await view.start(startUrl);
      await expectLater(view.releaseFocus(), completes);
    });
  });
}

void main() {
  final startUrl = Uri.parse('https://example.invalid/start');
  final failingUrl = Uri.parse('https://example.invalid/failing');
  final secondUrl = Uri.parse('https://example.invalid/second');

  runSearchWebViewConformance(
    'FakeSearchWebView',
    FakeSearchWebView.new,
    caps: const SearchWebViewCapabilities(
      reportsHistory: true,
      releaseFocusIsNoop: false,
    ),
    startUrl: startUrl,
    failingUrl: failingUrl,
    secondUrl: secondUrl,
    triggerFailure: (view, url) async {
      (view as FakeSearchWebView).emitLoadError(url.toString());
    },
    triggerSuccess: (view, url) async {
      final fake = view as FakeSearchWebView;
      fake
        ..emitUrl(url.toString())
        ..emitLoadEnd(url.toString());
    },
  );

  // Fake-only: proves the *double*, not just FailedLoadEndFilter in isolation
  // (failed_load_end_filter_test.dart), obeys the failed-load-end rule — this
  // is what every test built on FakeSearchWebView relies on.
  group('FakeSearchWebView obeys the failed-load-end rule itself', () {
    test('a single trailing end for the failed URL is suppressed; '
        'a later one is forwarded', () async {
      final view = FakeSearchWebView();
      addTearDown(view.dispose);
      final ends = <String>[];
      view.onLoadEnd = ends.add;
      await view.start(startUrl);

      view.emitLoadError(failingUrl.toString());
      view.emitLoadEnd(failingUrl.toString());
      expect(ends, isEmpty, reason: 'that end was the engine’s own noise');

      view.emitLoadEnd(failingUrl.toString());
      expect(ends, [failingUrl.toString()], reason: 'a later end is genuine');
    });

    test('a navigation call clears the pending suppression', () async {
      final view = FakeSearchWebView();
      addTearDown(view.dispose);
      final ends = <String>[];
      view.onLoadEnd = ends.add;
      await view.start(startUrl);

      view.emitLoadError(failingUrl.toString());
      await view.loadUrl(secondUrl);
      view.emitLoadEnd(failingUrl.toString());
      expect(ends, [
        failingUrl.toString(),
      ], reason: 'the navigation cleared the pairing, so this end is genuine');
    });

    test('onHistoryChanged is forwarded as set', () async {
      final view = FakeSearchWebView();
      addTearDown(view.dispose);
      bool? received;
      view.onHistoryChanged = (canGoBack) => received = canGoBack;
      await view.start(startUrl);

      view.emitHistory(canGoBack: true);
      expect(received, isTrue);
    });
  });
}
