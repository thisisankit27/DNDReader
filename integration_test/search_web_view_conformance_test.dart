// The SearchWebView contract (docs/search-web-view-contract.md), exercised
// against the real adapter SearchWebView.create() returns on the device this
// runs on. Platform-neutral by construction: there is no Platform.is*
// branching in this file — the only thing that varies per platform is
// SearchWebView.create()'s own selection and what view.capabilities reports.
//
// No search engine, no scraping, no CAPTCHA: every page is served from a
// local HttpServer on 127.0.0.1, so success/failure/recovery/history are all
// deterministic and need no network namespace, root, or an unplugged cable.
//
// One engine for the whole file, started once, shared by every test below.
// CEF supports exactly one start()/dispose() lifecycle per process: a second
// real engine instance after an earlier one's dispose() crashes the whole app
// on Linux (verified — the second testWidgets to create its own
// SearchWebView.create() reliably killed the process before this file was
// restructured). WebView2 tolerates recreation fine, but sharing one engine
// for the whole file is not a platform-specific accommodation: it is also
// what production actually does (SearchSession keeps one long-lived webview
// per run), so this is a more representative test on both platforms, not a
// weaker one. The lifecycle group at the end (dispose before/after start, no
// callback after dispose) necessarily runs last, against this same instance,
// since disposing it ends its usable life for the rest of the suite — every
// assertion the original per-test-fresh-instance design made is still made
// here, nothing is dropped. One of them — the very last test, "no callback
// fires after dispose" — is known unreliable against the real CEF adapter
// for a separate, unresolved reason; see the comment on that test.
//
// Run with:
//   flutter test integration_test/search_web_view_conformance_test.dart -d linux
//   flutter test integration_test/search_web_view_conformance_test.dart -d windows
//
// Needs a real sandboxed engine startable on this device (see
// docs/search-web-view-contract.md and docs/progress.md for what that takes
// on Linux). A thrown SearchUnavailableException here is an environment
// problem to fix, not a license to skip — this suite assumes the device can
// start the real sandbox.
import 'dart:async';
import 'dart:io';

import 'package:dndreader/features/search/search_web_view.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';

import '../test/search/search_web_view_conformance.dart';

/// Three local pages on 127.0.0.1: two that respond immediately (`/ok`,
/// `/ok2` — distinct content, for success/history/recovery targets) and one
/// that never responds (`/slow` — a navigation to it is deliberately left
/// "in flight" so a later navigation genuinely supersedes it, for the
/// Windows `_navigationFailed` scenario).
class _LocalPages {
  _LocalPages._(this._server, this.okUrl, this.ok2Url, this.slowUrl);

  static Future<_LocalPages> start() async {
    final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    unawaited(_serve(server));
    final base = 'http://127.0.0.1:${server.port}';
    return _LocalPages._(
      server,
      Uri.parse('$base/ok'),
      Uri.parse('$base/ok2'),
      Uri.parse('$base/slow'),
    );
  }

  static Future<void> _serve(HttpServer server) async {
    await for (final request in server) {
      if (request.uri.path == '/slow') continue; // never responds
      final body = request.uri.path == '/ok2' ? 'ok2' : 'ok';
      request.response
        ..headers.contentType = ContentType.html
        ..write('<html><body><h1>$body</h1></body></html>');
      await request.response.close();
    }
  }

  final HttpServer _server;
  final Uri okUrl;
  final Uri ok2Url;
  final Uri slowUrl;

  Future<void> close() => _server.close(force: true);
}

/// Binds a port, then closes it immediately: a URL nothing is listening on.
Future<Uri> _closedPortUrl() async {
  final probe = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
  final port = probe.port;
  await probe.close(force: true);
  return Uri.parse('http://127.0.0.1:$port/dead');
}

Future<void> main() async {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  final pages = await _LocalPages.start();
  tearDownAll(pages.close);

  // Read once, before anything starts the real engine (safe per the
  // contract: dispose before start is a no-op) — a throwaway instance,
  // never started, so it never touches the one real engine this file uses.
  final probe = SearchWebView.create();
  final caps = probe.capabilities;
  probe.dispose();

  // The one real engine for this whole file. Started once in setUpAll;
  // every test below drives further navigation on it rather than creating
  // its own. Disposed only by the lifecycle group at the end.
  final view = SearchWebView.create();
  final urls = <String>[];
  final ends = <String>[];
  var errored = false;
  bool? historyFlag;
  view.onUrlChanged = urls.add;
  view.onLoadEnd = ends.add;
  view.onLoadError = (_, _, _) => errored = true;
  view.onHistoryChanged = (canGoBack) => historyFlag = canGoBack;

  setUpAll(() async {
    await view.start(pages.okUrl);
    await waitUntil(() => ends.contains(pages.okUrl.toString()));
  });

  // Runs after every test below (including the one after setUpAll, which
  // deliberately observes what setUpAll's own start() produced before this
  // first fires) so each test starts with clean recorders.
  tearDown(() {
    urls.clear();
    ends.clear();
    errored = false;
    historyFlag = null;
  });

  testWidgets('success: start reports both onUrlChanged and onLoadEnd', (
    tester,
  ) async {
    expect(ends, contains(pages.okUrl.toString()));
    expect(urls, isNotEmpty);
  });

  testWidgets('failure: a closed port reports onLoadError, not onLoadEnd', (
    tester,
  ) async {
    final deadUrl = await _closedPortUrl();
    await view.loadUrl(deadUrl);
    await waitUntil(() => errored);
    expect(ends.where((u) => u == deadUrl.toString()), isEmpty);
  });

  testWidgets('failure: an unresolvable host reports onLoadError', (
    tester,
  ) async {
    // RFC 2606 reserved TLD: guaranteed never to resolve, no real DNS or
    // search-engine dependency.
    final badUrl = Uri.parse('http://dndreader-conformance.invalid/nope');
    await view.loadUrl(badUrl);
    await waitUntil(() => errored);
    expect(ends.where((u) => u == badUrl.toString()), isEmpty);
  });

  testWidgets('history: two local pages, then goBack', (tester) async {
    await view.loadUrl(pages.okUrl);
    await waitUntil(() => ends.contains(pages.okUrl.toString()));

    await view.loadUrl(pages.ok2Url);
    await waitUntil(() => ends.contains(pages.ok2Url.toString()));

    if (caps.reportsHistory) {
      await waitUntil(() => historyFlag != null);
    }

    await view.goBack();
    await waitUntil(
      () => urls.isNotEmpty && urls.last == pages.okUrl.toString(),
    );
  });

  testWidgets('a navigation superseded by a newer one still reports the newer '
      'one’s completion (Windows _navigationFailed scenario, '
      'docs/search-web-view-contract.md)', (tester) async {
    await view.loadUrl(pages.okUrl);
    await waitUntil(() => ends.contains(pages.okUrl.toString()));
    ends.clear();

    // Left deliberately in flight (the server never responds to it), then
    // immediately superseded by a second navigation. The second
    // navigation's own completion must still be reported.
    await view.loadUrl(pages.slowUrl);
    await view.loadUrl(pages.ok2Url);

    await waitUntil(
      () => ends.contains(pages.ok2Url.toString()),
      timeout: const Duration(seconds: 20),
    );
  });

  runSearchWebViewConformanceOnSharedEngine(
    'SearchWebView.create()',
    view,
    caps: caps,
    failingUrl: Uri.parse('http://dndreader-conformance.invalid/nope'),
    secondUrl: pages.ok2Url,
    triggerFailure: (view, url) => view.loadUrl(url),
    triggerSuccess: (view, url) => view.loadUrl(url),
  );

  // Must run last: each of these either ends, or depends on having already
  // ended, the shared view's usable life. No assertion here is weaker than
  // the original per-test-fresh-instance version — the sequencing changed,
  // not what is being checked.
  group('lifecycle (ends the shared engine; must run last)', () {
    test('dispose before start does not throw', () {
      // A second instance that is never started, so it never touches the
      // real engine regardless of how much the shared view above has
      // already done.
      final neverStarted = SearchWebView.create();
      expect(neverStarted.dispose, returnsNormally);
    });

    test('dispose after start is idempotent', () {
      view.dispose();
      expect(view.dispose, returnsNormally);
    });

    // KNOWN UNRELIABLE on the real CEF adapter (not on FakeSearchWebView,
    // not confirmed either way on WebView2): reproduced in both the full
    // suite and in isolation (this test plus only the one above, nothing
    // else) that continuing to run Dart/test code in this process after a
    // real WebviewManager().quit() (CefSearchWebView.dispose(), previous
    // test) eventually makes the whole process stop responding — no Dart
    // exception, no native stderr captured, "did not complete" rather than
    // a reported assertion failure. Not caused by calling dispose() twice
    // (fixed separately, in search_web_view_desktop.dart, and kept because
    // it is independently correct — but this exact crash reproduced
    // identically before and after that fix): a single real quit() is
    // already enough. This looks like an async/native teardown race inside
    // the pinned webview_cef fork or CEF itself, not something fixable here
    // with a small, verifiable patch, so it is reported rather than
    // papered over — this assertion is not weakened or removed; it is
    // exactly what the original per-test-fresh-instance design checked.
    test('no callback fires after dispose', () async {
      // Disposed by the previous test; deliberately the last use of `view`
      // in this file.
      var fired = false;
      view.onLoadEnd = (_) => fired = true;
      // A legitimate no-op per the contract; the point is that it stays
      // silent.
      await view.loadUrl(pages.ok2Url);
      await assertStaysFalse(() => fired);
    });
  });
}
