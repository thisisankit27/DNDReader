import 'dart:async';
import 'dart:ui' show AppExitResponse;

import 'package:flutter/services.dart' show PlatformException;
import 'package:flutter/widgets.dart';
import 'package:webview_flutter_windows/webview_flutter_windows.dart';

import '../../services/app_shutdown.dart';
import 'search_profile.dart';
import 'search_web_view.dart';

/// Windows implementation on WebView2 (`webview_flutter_windows`, plan §3).
///
/// Microsoft's Runtime owns the sandbox and its security updates; this class
/// passes **no** browser arguments, so nothing weakens it. Privacy differs from
/// Linux by design (plan §4): the profile is a throwaway folder under `%TEMP%`
/// that is cleared and deleted on quit, not an in-memory store.
class Webview2SearchWebView implements SearchWebView {
  Webview2SearchWebView({SearchProfileStore? profiles})
    : _profiles = profiles ?? SearchProfileStore();

  final SearchProfileStore _profiles;

  WebviewController? _controller;
  final List<StreamSubscription<dynamic>> _subscriptions = [];
  AppLifecycleListener? _exitListener;
  Future<void>? _teardown;

  String _lastUrl = '';
  void Function(String url)? _onUrlChanged;
  void Function(String url)? _onLoadEnd;
  void Function(String url, String errorText, int errorCode)? _onLoadError;

  @override
  set onUrlChanged(void Function(String url)? callback) =>
      _onUrlChanged = callback;

  @override
  set onLoadEnd(void Function(String url)? callback) => _onLoadEnd = callback;

  @override
  set onLoadError(
    void Function(String url, String errorText, int errorCode)? callback,
  ) => _onLoadError = callback;

  @override
  Future<void> start(Uri initialUrl) async {
    // A missing Runtime is the common failure on a bare Windows 10 install.
    String? runtime;
    try {
      runtime = await WebviewController.getWebViewVersion();
    } on PlatformException {
      runtime = null;
    }
    if (runtime == null || runtime.isEmpty) {
      throw const SearchUnavailableException(
        'The Microsoft Edge WebView2 Runtime is not installed.',
      );
    }

    // Leftovers from a crashed run are swept at launch (main.dart), not here.

    final dir = _profiles.create();
    final controller = WebviewController();
    try {
      try {
        await WebviewController.initializeEnvironment(userDataPath: dir.path);
      } on PlatformException catch (e) {
        // Already initialised by an earlier controller in this process: reuse.
        if (e.code != 'environment_already_initialized') rethrow;
      }
      await controller.initialize();
    } on PlatformException catch (e) {
      await controller.dispose();
      await _profiles.delete();
      throw SearchUnavailableException(
        'The Microsoft Edge WebView2 Runtime could not be started (${e.code}).',
      );
    } catch (_) {
      await controller.dispose();
      await _profiles.delete();
      rethrow;
    }

    _controller = controller;
    _subscriptions
      ..add(
        controller.url.listen((url) {
          _lastUrl = url;
          _onUrlChanged?.call(url);
        }),
      )
      ..add(
        controller.loadingState.listen((state) {
          if (state == LoadingState.navigationCompleted) {
            _onLoadEnd?.call(_lastUrl);
          }
        }),
      )
      ..add(
        controller.onLoadError.listen((status) {
          // A navigation superseded by a newer one (or turned into a download)
          // is reported as "cancelled"; it is not a failure the user needs to
          // see, and the newer navigation reports its own outcome.
          if (status == WebErrorStatus.operationCanceled) return;
          _onLoadError?.call(_lastUrl, status.name, status.index);
        }),
      );

    // Open target=_blank results in the panel, as the CEF path does, rather than
    // in a separate native window that would leave the app.
    await controller.setPopupWindowPolicy(WebviewPopupWindowPolicy.sameWindow);
    await controller.setDevToolsEnabled(false);

    // Quitting must clear and delete the profile before the process exits; a
    // widget's dispose() is not guaranteed to run on quit. The Windows runner
    // asks for this explicitly (AppShutdown) before it destroys the window;
    // the lifecycle listener is a second route where the framework does send an
    // exit request.
    AppShutdown.register(_shutdown);
    _exitListener = AppLifecycleListener(
      onExitRequested: () async {
        await _shutdown();
        return AppExitResponse.exit;
      },
    );

    _lastUrl = initialUrl.toString();
    await controller.loadUrl(initialUrl.toString());
  }

  @override
  Future<void> loadUrl(Uri url) async => _controller?.loadUrl(url.toString());

  @override
  Future<void> goBack() async => _controller?.goBack();

  @override
  Future<void> reload() async => _controller?.reload();

  /// Returns native (Win32) focus from the webview's texture to the Flutter
  /// view. The package does this itself on a click outside the webview; calling
  /// it when the panel closes covers closing by keyboard (Esc).
  @override
  Future<void> releaseFocus() => WebviewController.releaseFocus();

  @override
  Widget get widget {
    final controller = _controller;
    if (controller == null) return const SizedBox.shrink();
    return Webview(
      controller,
      // The panel never needs the camera, microphone, location or
      // notifications; refuse rather than let WebView2 prompt.
      permissionRequested: (url, kind, isUserInitiated) async =>
          WebviewPermissionDecision.deny,
    );
  }

  @override
  void dispose() {
    unawaited(_shutdown());
  }

  /// Clears cookies and cache, stops the browser, deletes the profile folder.
  /// Runs once; later callers share the same future.
  Future<void> _shutdown() => _teardown ??= _runShutdown();

  Future<void> _runShutdown() async {
    AppShutdown.unregister(_shutdown);
    _exitListener?.dispose();
    _exitListener = null;
    for (final sub in _subscriptions) {
      unawaited(sub.cancel());
    }
    _subscriptions.clear();
    final controller = _controller;
    _controller = null;
    if (controller != null) {
      try {
        await controller.clearCookies();
        await controller.clearCache();
      } catch (e) {
        debugPrint('[search] clearing search data failed: $e');
      }
      await controller.dispose();
    }
    final gone = await _profiles.delete();
    if (!gone) {
      debugPrint(
        '[search] profile folder not removed; the next launch will sweep it',
      );
    }
  }
}
