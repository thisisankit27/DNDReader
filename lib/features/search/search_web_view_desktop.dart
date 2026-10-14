import 'dart:io' show Platform;

import 'package:flutter/material.dart';
import 'package:webview_cef/webview_cef.dart';

import 'search_web_view.dart';

/// Desktop implementation on the hardened `webview_cef` fork.
///
/// The browser sandbox is required: if it cannot start, [start] throws
/// [SearchUnavailableException] and CEF is never initialised. The only way to
/// run unsandboxed is the development override, and only in non-release builds.
class CefSearchWebView implements SearchWebView {
  WebViewController? _controller;
  final FailedLoadEndFilter _failedLoads = FailedLoadEndFilter();

  /// CEF was initialised by this view (the sandbox preflight passed).
  bool _cefStarted = false;
  void Function(String url)? _onUrlChanged;
  void Function(String url)? _onLoadEnd;
  void Function(String url, String errorText, int errorCode)? _onLoadError;

  @override
  set onUrlChanged(void Function(String url)? callback) =>
      _onUrlChanged = callback;

  @override
  set onLoadEnd(void Function(String url)? callback) => _onLoadEnd = callback;

  // CEF is not asked for its history state; the session keeps its own record.
  @override
  set onHistoryChanged(void Function(bool canGoBack)? callback) {}

  @override
  set onLoadError(
    void Function(String url, String errorText, int errorCode)? callback,
  ) => _onLoadError = callback;

  @override
  Future<void> start(Uri initialUrl) async {
    final unsandboxed = unsandboxedDevOverrideActive;
    if (unsandboxed) {
      debugPrint(
        '[search] WARNING: running the embedded browser WITHOUT its sandbox (dev override).',
      );
    }
    try {
      await WebviewManager().initialize(
        sandbox: unsandboxed
            ? WebviewSandboxMode.disabled
            : WebviewSandboxMode.required,
        // Off by default: with the GPU enabled the GPU process runs without its
        // seccomp filter (measured in M4). Opting in is the user's choice.
        enableGpu: Platform.environment['DNDREADER_GPU'] == '1',
      );
    } on WebviewSandboxException catch (e) {
      throw SearchUnavailableException(e.reason);
    }
    _cefStarted = true;
    final controller = WebviewManager().createWebView(
      loading: const Center(child: CircularProgressIndicator()),
    );
    controller.setWebviewListener(
      WebviewEventsListener(
        onUrlChanged: (url) => _onUrlChanged?.call(url),
        // CEF raises a load-end for the failed URL right after the error; that
        // is not the page loading, so it is not forwarded.
        onLoadEnd: (_, url) {
          if (_failedLoads.shouldForwardEnd(url)) _onLoadEnd?.call(url);
        },
        onLoadError: (_, url, text, code) {
          _failedLoads.failed(url);
          _onLoadError?.call(url, text, code);
        },
      ),
    );
    await controller.initialize(initialUrl.toString());
    _controller = controller;
  }

  @override
  Future<void> loadUrl(Uri url) async {
    _failedLoads.navigationStarted();
    await _controller?.loadUrl(url.toString());
  }

  @override
  Future<void> goBack() async {
    _failedLoads.navigationStarted();
    await _controller?.goBack();
  }

  @override
  Future<void> reload() async {
    _failedLoads.navigationStarted();
    await _controller?.reload();
  }

  // The CEF plugin's focus is handled by Flutter's own focus tree.
  @override
  Future<void> releaseFocus() async {}

  @override
  Widget get widget {
    final controller = _controller;
    if (controller == null) return const SizedBox.shrink();
    return ValueListenableBuilder<bool>(
      valueListenable: controller,
      builder: (context, ready, _) =>
          ready ? controller.webviewWidget : controller.loadingWidget,
    );
  }

  @override
  void dispose() {
    _controller?.dispose();
    _controller = null;
    // Never initialised (fail-closed start): there is nothing to quit, and
    // WebviewManager.quit() asserts that it was initialised.
    if (_cefStarted) WebviewManager().quit();
  }
}
