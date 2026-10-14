// Linux regression pass for the Windows port's shared changes.
//
// Runs the REAL app with the REAL CEF webview on the Linux device:
//   LINUX_REGRESSION=online  flutter test integration_test/linux_regression_test.dart -d linux
//   LINUX_REGRESSION=offline  (same, inside a network namespace with no route out)
// Pointer and key events are injected inside Flutter, not through GTK.
import 'dart:io';

import 'package:dndreader/features/reader/reader_screen.dart';
import 'package:dndreader/features/reader/selection_action_controller.dart';
import 'package:dndreader/features/search/search_session.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:pdfrx/pdfrx.dart';

final String _mode = Platform.environment['LINUX_REGRESSION'] ?? 'online';

void _log(String m) => debugPrint('[regress] $m');

Future<void> _until(
  WidgetTester tester,
  bool Function() cond, {
  required Duration timeout,
  String what = 'condition',
}) async {
  final sw = Stopwatch()..start();
  while (!cond()) {
    if (sw.elapsed > timeout) {
      fail('timed out after $timeout waiting for $what');
    }
    await Future<void>.delayed(const Duration(milliseconds: 100));
    await tester.pump();
  }
}

Future<void> _settle(WidgetTester tester, Duration d) async {
  final sw = Stopwatch()..start();
  while (sw.elapsed < d) {
    await Future<void>.delayed(const Duration(milliseconds: 100));
    await tester.pump();
  }
}

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  late SearchSession session;
  late SelectionActionController action;
  late List<Uri> opened;

  Future<void> openReader(WidgetTester tester) async {
    opened = [];
    action = SelectionActionController();
    session = SearchSession(
      openUrl: (u) async {
        opened.add(u);
        return true;
      },
    );
    final path = '${Directory.current.path}/test_fixtures/prose.pdf';
    await tester.pumpWidget(
      MaterialApp(
        home: ReaderScreen(
          initialPath: path,
          actionController: action,
          searchSession: session,
        ),
      ),
    );
    await _until(
      tester,
      () => find.byKey(const ValueKey('page-field')).evaluate().isNotEmpty,
      timeout: const Duration(seconds: 20),
      what: 'document',
    );
    await _settle(tester, const Duration(seconds: 1));
  }

  /// Double-click words on a grid until the action is available.
  Future<void> selectAWord(WidgetTester tester) async {
    final rect = tester.getRect(find.byType(PdfViewer));
    for (var fy = 0.12; fy < 0.9 && !action.available; fy += 0.04) {
      for (var fx = 0.3; fx < 0.75 && !action.available; fx += 0.06) {
        final p = Offset(
          rect.left + rect.width * fx,
          rect.top + rect.height * fy,
        );
        await tester.tapAt(p);
        await tester.pump(const Duration(milliseconds: 60));
        await tester.tapAt(p);
        await _settle(tester, const Duration(milliseconds: 400));
      }
    }
    expect(action.available, isTrue, reason: 'a word got selected');
    _log('selected: "${action.query}"');
  }

  Future<void> ctrlE(WidgetTester tester) async {
    await tester.sendKeyDownEvent(LogicalKeyboardKey.controlLeft);
    await tester.sendKeyEvent(LogicalKeyboardKey.keyE);
    await tester.sendKeyUpEvent(LogicalKeyboardKey.controlLeft);
    await tester.pump();
  }

  if (_mode == 'quit') {
    testWidgets('quit: exits after a search without hanging', (tester) async {
      await openReader(tester);
      await selectAWord(tester);
      await ctrlE(tester);
      await _until(
        tester,
        () => session.phase == SearchPhase.loaded,
        timeout: const Duration(seconds: 40),
        what: 'results to load',
      );
      // The test binding refuses exitApplication(); an external helper sends
      // the window manager's close request (WM_DELETE_WINDOW), as clicking the
      // title bar's X would.
      _log('READY-TO-QUIT ${DateTime.now().toIso8601String()}');
      await Future<void>.delayed(const Duration(seconds: 60));
      fail('the app was not closed within 60 s');
    });
  } else if (_mode == 'gated') {
    // Observation only (no assertions): the D3 scenario on Linux — a result
    // that goes to a Cloudflare-gated site, then Back. The verification widget
    // is never touched.
    testWidgets('gated: observe phases and Back on Linux', (tester) async {
      await openReader(tester);
      await selectAWord(tester);
      await ctrlE(tester);
      await _until(
        tester,
        () => session.phase == SearchPhase.loaded,
        timeout: const Duration(seconds: 40),
        what: 'results',
      );
      await session.webView!.loadUrl(
        Uri.parse('https://www.thesaurus.com/browse/efficient'),
      );
      String last = '';
      final sw = Stopwatch()..start();
      while (sw.elapsed < const Duration(seconds: 30)) {
        await Future<void>.delayed(const Duration(milliseconds: 250));
        await tester.pump();
        final now =
            '${session.phase.name} back=${session.canGoBack} url=${session.currentUrl}';
        if (now != last) {
          _log('t=${sw.elapsedMilliseconds}ms $now');
          last = now;
        }
      }
      for (var i = 0; i < 3; i++) {
        final before = session.canGoBack;
        await session.back();
        await _settle(tester, const Duration(seconds: 6));
        _log(
          'back #${i + 1} (was enabled=$before): ${session.phase.name} '
          'back=${session.canGoBack} url=${session.currentUrl}',
        );
      }
    });
  } else if (_mode == 'online') {
    testWidgets('online: search loads, Back tracks, panel close keeps scroll', (
      tester,
    ) async {
      await openReader(tester);
      final controller = tester
          .widget<PdfViewer>(find.byType(PdfViewer))
          .controller!;
      // Scroll away from the top so "unchanged" means something.
      await controller.goToPage(pageNumber: 2, duration: Duration.zero);
      await _settle(tester, const Duration(milliseconds: 600));
      await selectAWord(tester);
      final before = controller.visibleRect;
      expect(before.top, greaterThan(0), reason: 'document is scrolled');

      final sw = Stopwatch()..start();
      await ctrlE(tester);
      expect(session.visible, isTrue);
      await _until(
        tester,
        () => session.phase == SearchPhase.loaded,
        timeout: const Duration(seconds: 40),
        what: 'results to load',
      );
      _log(
        'search loaded in ${sw.elapsedMilliseconds} ms, url=${session.currentUrl}',
      );
      expect(Uri.parse(session.currentUrl!).host, contains('google'));
      expect(session.canGoBack, isFalse);

      // Two in-panel navigations, as clicking results does.
      final view = session.webView!;
      await view.loadUrl(Uri.parse('https://example.com/'));
      await _until(
        tester,
        () =>
            session.phase == SearchPhase.loaded &&
            (session.currentUrl ?? '').contains('example.com'),
        timeout: const Duration(seconds: 30),
        what: 'example.com',
      );
      _log('at example.com canGoBack=${session.canGoBack}');
      expect(session.canGoBack, isTrue);
      await view.loadUrl(
        Uri.parse('https://www.iana.org/help/example-domains'),
      );
      await _until(
        tester,
        () =>
            session.phase == SearchPhase.loaded &&
            (session.currentUrl ?? '').contains('iana.org'),
        timeout: const Duration(seconds: 30),
        what: 'iana.org',
      );
      _log('at iana canGoBack=${session.canGoBack}');
      expect(session.canGoBack, isTrue);

      await session.back();
      await _until(
        tester,
        () =>
            session.phase == SearchPhase.loaded &&
            (session.currentUrl ?? '').contains('example.com'),
        timeout: const Duration(seconds: 30),
        what: 'back to example.com',
      );
      _log('back 1 -> ${session.currentUrl} canGoBack=${session.canGoBack}');
      expect(session.canGoBack, isTrue);

      await session.back();
      await _until(
        tester,
        () =>
            session.phase == SearchPhase.loaded &&
            Uri.parse(session.currentUrl ?? 'x:').host.contains('google'),
        timeout: const Duration(seconds: 40),
        what: 'back to the search page',
      );
      _log('back 2 -> ${session.currentUrl} canGoBack=${session.canGoBack}');
      expect(
        session.canGoBack,
        isFalse,
        reason: 'at the first page Back is off',
      );

      // Open in browser goes to the page being shown (opener injected: the
      // real xdg-open would pop a window on the desktop).
      await session.openInBrowser();
      expect(opened, hasLength(1));
      expect(opened.single.host, contains('google'));

      // Close the panel: the document has not moved.
      session.close();
      await _settle(tester, const Duration(milliseconds: 500));
      final after = controller.visibleRect;
      _log('visibleRect before=$before after=$after');
      expect(after, before);
      expect(session.visible, isFalse);
    });
  } else {
    testWidgets('offline: failure appears, stays, and recovery works', (
      tester,
    ) async {
      await openReader(tester);
      await selectAWord(tester);

      final sw = Stopwatch()..start();
      await ctrlE(tester);
      await _until(
        tester,
        () => session.phase == SearchPhase.failed,
        timeout: const Duration(seconds: 40),
        what: 'the failure to be shown',
      );
      _log('offline search -> failed after ${sw.elapsedMilliseconds} ms');
      // Must not flip back to loaded (the new recover-from-failed rule) nor to
      // anything else while still offline.
      await _settle(tester, const Duration(seconds: 10));
      _log('10 s later phase=${session.phase.name}');
      expect(session.phase, SearchPhase.failed);

      // Recovery: a loopback server that is down, then up, then Retry.
      final probe = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
      final port = probe.port;
      await probe.close(force: true);
      final url = Uri.parse('http://127.0.0.1:$port/hello');
      final sw2 = Stopwatch()..start();
      await session.search(url, 'loopback');
      await _until(
        tester,
        () => session.phase == SearchPhase.failed,
        timeout: const Duration(seconds: 30),
        what: 'refused connection to fail',
      );
      _log('loopback refused -> failed after ${sw2.elapsedMilliseconds} ms');

      final server = await HttpServer.bind(InternetAddress.loopbackIPv4, port);
      server.listen((r) {
        r.response
          ..headers.contentType = ContentType.html
          ..write('<html><body><h1>hello</h1></body></html>');
        r.response.close();
      });
      await session.retry();
      await _until(
        tester,
        () => session.phase == SearchPhase.loaded,
        timeout: const Duration(seconds: 30),
        what: 'recovery after Retry',
      );
      _log('retry -> loaded');
      await server.close(force: true);
      session.close();
    });
  }
}
