import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

/// Lets the native runner ask Dart to finish its clean-up *before* the window is
/// destroyed.
///
/// `AppLifecycleListener.onExitRequested` is not reliable here: the Windows
/// runner's `WM_CLOSE` goes straight to `DestroyWindow` without a round trip
/// to Dart (observed: 47 ms from `WM_CLOSE` to `WM_DESTROY`, no exit request
/// ever reaches the framework). So on Windows the runner sends
/// `prepareToClose` over `dndreader/lifecycle` and waits for the reply (or a
/// timeout) before closing. Elsewhere the channel is simply never called.
///
/// Hooks run once, in parallel, each guarded: a hook that throws or hangs can
/// delay the close by at most [timeout] and never prevents it.
class AppShutdown {
  AppShutdown._();

  static const MethodChannel _channel = MethodChannel('dndreader/lifecycle');

  static final List<Future<void> Function()> _hooks =
      <Future<void> Function()>[];
  static bool _installed = false;
  static Future<void>? _running;

  /// How long the hooks together may take before the close goes ahead. The
  /// native runner's own backstop is slightly longer (6 s).
  static const Duration defaultTimeout = Duration(seconds: 4);

  /// Starts answering `prepareToClose` from the native runner. Idempotent.
  static void install() {
    if (_installed) return;
    _installed = true;
    _channel.setMethodCallHandler((call) async {
      if (call.method == 'prepareToClose') {
        await run();
      }
      return null;
    });
  }

  /// Adds [hook]; it runs when the window is about to close.
  static void register(Future<void> Function() hook) {
    if (!_hooks.contains(hook)) _hooks.add(hook);
  }

  static void unregister(Future<void> Function() hook) => _hooks.remove(hook);

  /// Runs the registered hooks (once; later callers share the same run).
  @visibleForTesting
  static Future<void> run({Duration timeout = defaultTimeout}) =>
      _running ??= _run(timeout);

  static Future<void> _run(Duration timeout) async {
    final hooks = List<Future<void> Function()>.of(_hooks);
    if (hooks.isEmpty) return;
    final all = Future.wait<void>(
      hooks.map((hook) async {
        try {
          await hook();
        } catch (e) {
          debugPrint('[shutdown] hook failed: $e');
        }
      }),
    );
    await all.timeout(
      timeout,
      onTimeout: () {
        debugPrint('[shutdown] hooks still running after $timeout; closing');
        return const <void>[];
      },
    );
  }

  /// Test support: forget hooks and state.
  @visibleForTesting
  static void resetForTest() {
    _hooks.clear();
    _running = null;
  }
}
