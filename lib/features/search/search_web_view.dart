import 'dart:io' show Platform;

import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';

import 'search_web_view_desktop.dart';

/// The embedded browser could not be started on this system, and starting it
/// unsandboxed is not allowed. [reason] is user-presentable.
class SearchUnavailableException implements Exception {
  const SearchUnavailableException(this.reason);

  final String reason;

  @override
  String toString() => 'SearchUnavailableException: $reason';
}

/// One long-lived embedded browser for search results.
///
/// The seam between shared reader logic and the platform webview (plan §1):
/// desktop uses CEF (a hardened fork of `webview_cef`); mobile will use
/// `webview_flutter` in M7. Everything above this interface is shared.
abstract class SearchWebView {
  /// The desktop implementation on desktop platforms; an always-unavailable
  /// stand-in elsewhere (mobile arrives in M7 and is not claimed to work).
  factory SearchWebView.create() {
    if (Platform.isLinux || Platform.isWindows || Platform.isMacOS) {
      return CefSearchWebView();
    }
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

  void dispose();
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
/// In a release build the environment is not even read: `kReleaseMode` is a
/// compile-time constant, so the lookup is removed from the binary.
bool get unsandboxedDevOverrideActive {
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

  @override
  Future<void> loadUrl(Uri url) async {}
  @override
  Future<void> goBack() async {}
  @override
  Future<void> reload() async {}
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
  void dispose() {}
}
