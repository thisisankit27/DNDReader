import 'dart:io' show Platform;

import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';

import 'search_web_view_desktop.dart';
import 'search_web_view_windows.dart';

/// The embedded browser could not be started on this system, and starting it
/// unsandboxed is not allowed. [reason] is user-presentable.
class SearchUnavailableException implements Exception {
  const SearchUnavailableException(this.reason);

  final String reason;

  @override
  String toString() => 'SearchUnavailableException: $reason';
}

/// What an adapter does or does not do, for behaviour the contract allows to
/// vary by engine rather than requiring of every adapter.
///
/// Read by the conformance suite to decide which assertions apply — e.g. an
/// engine that does not report history must never call [SearchWebView.onHistoryChanged]
/// at all, not call it once with a default. See `docs/search-web-view-contract.md`.
@immutable
class SearchWebViewCapabilities {
  const SearchWebViewCapabilities({
    required this.reportsHistory,
    required this.releaseFocusIsNoop,
  });

  /// Whether this adapter ever calls [SearchWebView.onHistoryChanged].
  final bool reportsHistory;

  /// Whether [SearchWebView.releaseFocus] has no observable effect on this adapter.
  final bool releaseFocusIsNoop;
}

/// One long-lived embedded browser for search results.
///
/// The seam between shared reader logic and the platform webview (plan §1):
/// Linux uses CEF (a hardened fork of `webview_cef`); Windows uses WebView2
/// (`webview_flutter_windows`); mobile will use `webview_flutter` in M7.
/// Everything above this interface is shared.
///
/// The cross-adapter rules every implementation must follow — including the
/// failed-load-end rule below and the capability flags above — are specified
/// in `docs/search-web-view-contract.md`.
abstract class SearchWebView {
  /// The implementation for this platform; an always-unavailable stand-in
  /// elsewhere (mobile arrives in M7 and is not claimed to work).
  ///
  /// Chosen at run time: Dart's conditional imports select on `dart.library.*`,
  /// not on the operating system, so both packages are compiled everywhere but
  /// only the matching one is ever constructed.
  factory SearchWebView.create() {
    if (Platform.isWindows) return Webview2SearchWebView();
    if (Platform.isLinux || Platform.isMacOS) return CefSearchWebView();
    return _UnsupportedSearchWebView();
  }

  /// Starts the engine and loads [initialUrl].
  ///
  /// Throws [SearchUnavailableException] when the browser sandbox cannot start;
  /// in that case nothing was started.
  Future<void> start(Uri initialUrl);

  Future<void> loadUrl(Uri url);
  Future<void> goBack();
  Future<void> reload();

  /// What this adapter does or does not do (docs/search-web-view-contract.md).
  SearchWebViewCapabilities get capabilities;

  /// Gives keyboard focus back to the Flutter view. Called when the panel
  /// closes: a native webview can keep OS-level focus after it is hidden, which
  /// would swallow shortcuts. A no-op where the embedder has no such notion.
  Future<void> releaseFocus();

  /// The widget to place in the layout. Valid after [start] completes.
  Widget get widget;

  /// Main-frame URL changes.
  set onUrlChanged(void Function(String url)? callback);

  /// A frame finished loading. Fires for sub-frames too; the session decides
  /// which URL counts as "the page".
  set onLoadEnd(void Function(String url)? callback);

  /// The main frame failed to load (offline, DNS, refused, …).
  set onLoadError(
    void Function(String url, String errorText, int errorCode)? callback,
  );

  /// The browser's own history state, for engines that report it: whether Back
  /// can go anywhere. Engines that do not report it never call this, and the
  /// session then relies on its own record of visited pages.
  set onHistoryChanged(void Function(bool canGoBack)? callback);

  void dispose();
}

/// Pairs a failed navigation with the load-end its engine raises for it.
///
/// CEF (and WebView2) report a load *end* for a navigation that failed, right
/// after the error, carrying the failed URL. That is not "the page loaded". The
/// session accepts a load-end after an error as a recovery (a challenge page
/// that finishes loading after an aborted hop), so an engine that raises the
/// trailing end must not forward it: otherwise the failure is turned into a
/// successful load the instant it is shown (observed on Linux, offline).
class FailedLoadEndFilter {
  String? _failedUrl;

  /// Record that a main-frame navigation to [url] failed.
  void failed(String url) => _failedUrl = url;

  /// A new navigation starts: any pending pairing no longer applies.
  void navigationStarted() => _failedUrl = null;

  /// Whether a load-end for [url] is a real completion. False exactly once for
  /// the failed URL.
  bool shouldForwardEnd(String url) {
    if (_failedUrl != null && url == _failedUrl) {
      _failedUrl = null;
      return false;
    }
    return true;
  }
}

/// Whether the development override that permits an unsandboxed browser applies.
///
/// A release build never honours it, whatever the environment says.
@visibleForTesting
bool unsandboxedOverrideAllowed({
  required bool releaseMode,
  required String? envValue,
}) {
  return !releaseMode && envValue == '1';
}

/// True when the development override is active (non-release builds only).
///
/// CEF-only: on Windows the browser is WebView2, whose sandbox is Microsoft's
/// and cannot be switched off from here, so this is always false there.
///
/// In a release build the environment is not even read: `kReleaseMode` is a
/// compile-time constant, so the lookup is removed from the binary.
bool get unsandboxedDevOverrideActive {
  if (Platform.isWindows) return false;
  return unsandboxedOverrideAllowed(
    releaseMode: kReleaseMode,
    envValue: kReleaseMode
        ? null
        : Platform.environment['DNDREADER_ALLOW_UNSANDBOXED_DEV'],
  );
}

class _UnsupportedSearchWebView implements SearchWebView {
  @override
  Future<void> start(Uri initialUrl) async {
    throw const SearchUnavailableException(
      'The embedded search panel is not available on this platform yet.',
    );
  }

  // Never actually exercised: start() always throws above, so nothing ever
  // reads this. The values are arbitrary.
  @override
  SearchWebViewCapabilities get capabilities => const SearchWebViewCapabilities(
    reportsHistory: false,
    releaseFocusIsNoop: true,
  );

  @override
  Future<void> loadUrl(Uri url) async {}
  @override
  Future<void> goBack() async {}
  @override
  Future<void> reload() async {}
  @override
  Future<void> releaseFocus() async {}
  @override
  Widget get widget => const SizedBox.shrink();
  @override
  set onUrlChanged(void Function(String url)? callback) {}
  @override
  set onLoadEnd(void Function(String url)? callback) {}
  @override
  set onLoadError(
    void Function(String url, String errorText, int errorCode)? callback,
  ) {}
  @override
  set onHistoryChanged(void Function(bool canGoBack)? callback) {}
  @override
  void dispose() {}
}
