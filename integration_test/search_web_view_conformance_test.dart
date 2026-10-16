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
  // contract: dispose before start is a no-op).
  final probe = SearchWebView.create();
  final caps = probe.capabilities;
  probe.dispose();

  testWidgets('success: start reports both onUrlChanged and onLoadEnd', (
    tester,
  ) async {
    final view = SearchWebView.create();
    addTearDown(view.dispose);
    final urls = <String>[];
    final ends = <String>[];
    view.onUrlChanged = urls.add;
    view.onLoadEnd = ends.add;

    await view.start(pages.okUrl);
    await waitUntil(() => ends.contains(pages.okUrl.toString()));
    expect(urls, isNotEmpty);
  });

  testWidgets('failure: a closed port reports onLoadError, not onLoadEnd', (
    tester,
  ) async {
    final deadUrl = await _closedPortUrl();
    final view = SearchWebView.create();
    addTearDown(view.dispose);
    var errored = false;
    final ends = <String>[];
    view.onLoadError = (_, _, _) => errored = true;
    view.onLoadEnd = ends.add;

    await view.start(pages.okUrl);
    await waitUntil(() => ends.contains(pages.okUrl.toString()));

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
    final view = SearchWebView.create();
    addTearDown(view.dispose);
    var errored = false;
    final ends = <String>[];
    view.onLoadError = (_, _, _) => errored = true;
    view.onLoadEnd = ends.add;

    await view.start(pages.okUrl);
    await waitUntil(() => ends.contains(pages.okUrl.toString()));

    await view.loadUrl(badUrl);
    await waitUntil(() => errored);
    expect(ends.where((u) => u == badUrl.toString()), isEmpty);
  });

  testWidgets('history: two local pages, then goBack', (tester) async {
    final view = SearchWebView.create();
    addTearDown(view.dispose);
    final urls = <String>[];
    final ends = <String>[];
    bool? historyFlag;
    view.onUrlChanged = urls.add;
    view.onLoadEnd = ends.add;
    view.onHistoryChanged = (canGoBack) => historyFlag = canGoBack;

    await view.start(pages.okUrl);
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
    final view = SearchWebView.create();
    addTearDown(view.dispose);
    final ends = <String>[];
    view.onLoadEnd = ends.add;

    await view.start(pages.okUrl);
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

  testWidgets('dispose then no callbacks', (tester) async {
    final view = SearchWebView.create();
    var fired = false;
    view.onLoadEnd = (_) => fired = true;

    await view.start(pages.okUrl);
    await waitUntil(() => fired);
    fired = false;

    view.dispose();
    // A legitimate no-op per the contract; the point is that it stays silent.
    await view.loadUrl(pages.ok2Url);
    await assertStaysFalse(() => fired);
  });

  runSearchWebViewConformance(
    'SearchWebView.create()',
    SearchWebView.create,
    caps: caps,
    startUrl: pages.okUrl,
    failingUrl: Uri.parse('http://dndreader-conformance.invalid/nope'),
    secondUrl: pages.ok2Url,
    triggerFailure: (view, url) => view.loadUrl(url),
    triggerSuccess: (view, url) => view.loadUrl(url),
  );
}
