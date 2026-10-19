import 'dart:async';

import 'package:flutter/widgets.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:webview_flutter/webview_flutter.dart';
import 'package:webview_flutter_android/webview_flutter_android.dart';

import 'search_web_view.dart';

/// What the panel does with a main-frame navigation request.
enum NavigationVerdict {
  /// Load it in the panel.
  allow,

  /// Never load it; do nothing.
  block,

  /// Never load it in the panel; the system opens it (the user tapped a link).
  external,
}

/// Decides, from the URL alone, what a main-frame navigation in the panel does. Pure.
///
/// Only `http`/`https` (and `about:`) load in the panel. `tel:`/`mailto:`/`sms:` are handed to the system
/// because the user tapped them; `intent:`, `market:`, `file:`, `content:`, `javascript:`, `data:`, `blob:`
/// and anything else is dropped, never launched. A link to a `.pdf` goes to the system browser: the system
/// WebView cannot show a PDF, and the alternative is a blank panel. Only the URL is read, never the page.
@visibleForTesting
NavigationVerdict decideNavigation(String url) {
  final uri = Uri.tryParse(url);
  if (uri == null) return NavigationVerdict.block;
  switch (uri.scheme.toLowerCase()) {
    case 'http':
    case 'https':
      return uri.path.toLowerCase().endsWith('.pdf')
          ? NavigationVerdict.external
          : NavigationVerdict.allow;
    case 'about':
      return NavigationVerdict.allow;
    case 'tel':
    case 'mailto':
    case 'sms':
      return NavigationVerdict.external;
    default:
      return NavigationVerdict.block;
  }
}

/// The search panel on mobile: the official `webview_flutter` plugin, which uses the **system** WebView
/// (Android System WebView / Chrome; nothing is bundled). Reused by iOS later (`WKWebView`).
///
/// See `docs/search-web-view-contract.md`. Android specifics:
/// * Privacy: the system WebView has no in-memory profile; it writes `app_webview/` in this app's private
///   storage. Cookies, cache and web storage are cleared **before the first load of every run** (this covers a
///   run that was killed, which gets no chance to clean up) and best-effort on detach and dispose.
/// * Permission requests are denied (the plugin's default); JS dialogs are dismissed without being shown.
/// * Navigations other than http(s) are not loaded ([decideNavigation]).
class MobileSearchWebView implements SearchWebView {
  MobileSearchWebView({Future<bool> Function(Uri url)? openExternally})
    : _openExternally =
          openExternally ??
          ((url) => launchUrl(url, mode: LaunchMode.externalApplication));

  final Future<bool> Function(Uri url) _openExternally;

  WebViewController? _controller;
  Widget? _widget;
  AppLifecycleListener? _lifecycle;
  bool _disposed = false;
  final FailedLoadEndFilter _failedLoads = FailedLoadEndFilter();

  void Function(String url)? _onUrlChanged;
  void Function(String url)? _onLoadEnd;
  void Function(String url, String errorText, int errorCode)? _onLoadError;
  void Function(bool canGoBack)? _onHistoryChanged;

  @override
  SearchWebViewCapabilities get capabilities => const SearchWebViewCapabilities(
    reportsHistory: true,
    // Focus belongs to Flutter's own tree on Android; nothing to hand back.
    releaseFocusIsNoop: true,
  );

  @override
  Future<void> start(Uri initialUrl) async {
    final WebViewController controller;
    try {
      controller = WebViewController();
      await controller.setJavaScriptMode(JavaScriptMode.unrestricted);
      await controller.setNavigationDelegate(
        NavigationDelegate(
          onNavigationRequest: _onNavigationRequest,
          onUrlChange: (change) {
            final url = change.url;
            if (url != null) _onUrlChanged?.call(url);
            unawaited(_reportHistory());
          },
          onPageFinished: (url) {
            if (_disposed) return;
            if (_failedLoads.shouldForwardEnd(url)) _onLoadEnd?.call(url);
            unawaited(_reportHistory());
          },
          onWebResourceError: _onWebResourceError,
        ),
      );
      final platform = controller.platform;
      if (platform is AndroidWebViewController) {
        await platform.setAllowFileAccess(false);
        await platform.setAllowContentAccess(false);
        await platform.setMediaPlaybackRequiresUserGesture(true);
        // Dismiss page dialogs without showing them; permission prompts are denied by the plugin.
        await platform.setOnJavaScriptAlertDialog((_) async {});
        await platform.setOnJavaScriptConfirmDialog((_) async => false);
        await platform.setOnJavaScriptTextInputDialog((_) async => '');
      }
      // A failure to create the native WebView (missing, disabled, mid-update) surfaces here.
      await controller.getUserAgent();
      await _clearSearchData(controller);
      _controller = controller;
      _widget = WebViewWidget(controller: controller);
      _lifecycle = AppLifecycleListener(
        onDetach: () {
          final c = _controller;
          if (c != null) unawaited(_clearSearchData(c));
        },
      );
      await controller.loadRequest(initialUrl);
    } on Object catch (e) {
      _controller = null;
      _widget = null;
      _lifecycle?.dispose();
      _lifecycle = null;
      throw SearchUnavailableException(
        'The system WebView is missing, disabled or could not start ($e).',
      );
    }
  }

  Future<NavigationDecision> _onNavigationRequest(NavigationRequest r) async {
    switch (decideNavigation(r.url)) {
      case NavigationVerdict.allow:
        return NavigationDecision.navigate;
      case NavigationVerdict.external:
        final uri = Uri.tryParse(r.url);
        if (uri != null) unawaited(_openExternally(uri));
        return NavigationDecision.prevent;
      case NavigationVerdict.block:
        return NavigationDecision.prevent;
    }
  }

  void _onWebResourceError(WebResourceError error) {
    if (_disposed) return;
    // Sub-resource failures (an ad, an image) are not the page failing.
    if (error.isForMainFrame == false) return;
    final url = error.url ?? '';
    _failedLoads.failed(url);
    // Raw, unfiltered: bucketing ambiguous errors is the session's policy.
    _onLoadError?.call(
      url,
      error.errorType?.name ?? error.description,
      error.errorCode,
    );
  }

  Future<void> _reportHistory() async {
    final controller = _controller;
    if (_disposed || controller == null) return;
    final can = await controller.canGoBack();
    // Reported every time: the session already ignores a repeat, and the adapter has no reason to.
    if (_disposed) return;
    _onHistoryChanged?.call(can);
  }

  static Future<void> _clearSearchData(WebViewController controller) async {
    try {
      await WebViewCookieManager().clearCookies();
    } on Object catch (e) {
      debugPrint('[search] clearing cookies failed: $e');
    }
    try {
      await controller.clearCache();
      await controller.clearLocalStorage();
    } on Object catch (e) {
      debugPrint('[search] clearing web storage failed: $e');
    }
  }

  @override
  Future<void> loadUrl(Uri url) async {
    final controller = _controller;
    if (_disposed || controller == null) return;
    _failedLoads.navigationStarted();
    await controller.loadRequest(url);
  }

  @override
  Future<void> goBack() async {
    final controller = _controller;
    if (_disposed || controller == null) return;
    _failedLoads.navigationStarted();
    await controller.goBack();
  }

  @override
  Future<void> reload() async {
    final controller = _controller;
    if (_disposed || controller == null) return;
    _failedLoads.navigationStarted();
    await controller.reload();
  }

  @override
  Future<void> releaseFocus() async {}

  @override
  Widget get widget => _widget ?? const SizedBox.shrink();

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
  set onHistoryChanged(void Function(bool canGoBack)? callback) =>
      _onHistoryChanged = callback;

  @override
  void dispose() {
    if (_disposed) return;
    _disposed = true;
    _lifecycle?.dispose();
    _lifecycle = null;
    final controller = _controller;
    _controller = null;
    _widget = null;
    _onUrlChanged = null;
    _onLoadEnd = null;
    _onLoadError = null;
    _onHistoryChanged = null;
    if (controller != null) unawaited(_clearSearchData(controller));
  }
}
