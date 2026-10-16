import 'package:dndreader/features/search/search_web_view.dart';
import 'package:flutter/widgets.dart';

/// A scripted [SearchWebView]: records calls and lets a test fire events.
///
/// Obeys the same failed-load-end rule a real adapter must
/// (docs/search-web-view-contract.md): [emitLoadError] records the failed URL,
/// [loadUrl]/[goBack]/[reload] clear it, and [emitLoadEnd] is suppressed for
/// the failed URL's own immediate trailing end, exactly like [FailedLoadEndFilter]
/// in a real adapter — a test that wants to model a *genuine* second
/// completion for the same URL (an engine retrying internally) calls
/// [emitLoadEnd] again, not once.
class FakeSearchWebView implements SearchWebView {
  FakeSearchWebView({
    this.unavailableReason,
    this.capabilities = const SearchWebViewCapabilities(
      reportsHistory: true,
      releaseFocusIsNoop: false,
    ),
  });

  /// When set, [start] throws [SearchUnavailableException] with this reason.
  final String? unavailableReason;

  // Defaults to the superset so a test exercises every capability-gated
  // assertion unless it deliberately dials one down to model a CEF-shaped
  // double.
  @override
  final SearchWebViewCapabilities capabilities;

  final List<Uri> started = [];
  final List<Uri> loaded = [];
  int backs = 0;
  int reloads = 0;
  int focusReleases = 0;
  bool disposed = false;

  final FailedLoadEndFilter _failedLoads = FailedLoadEndFilter();

  void Function(String url)? _onUrl;
  void Function(String url)? _onEnd;
  void Function(String url, String errorText, int errorCode)? _onError;
  void Function(bool canGoBack)? _onHistory;

  @override
  set onUrlChanged(void Function(String url)? callback) => _onUrl = callback;
  @override
  set onLoadEnd(void Function(String url)? callback) => _onEnd = callback;

  @override
  set onHistoryChanged(void Function(bool canGoBack)? callback) =>
      _onHistory = callback;

  void emitHistory({required bool canGoBack}) => _onHistory?.call(canGoBack);

  @override
  set onLoadError(
    void Function(String url, String errorText, int errorCode)? callback,
  ) => _onError = callback;

  void emitLoadError(
    String url, {
    String text = 'ERR_NAME_NOT_RESOLVED',
    int code = -105,
  }) {
    _failedLoads.failed(url);
    _onError?.call(url, text, code);
  }

  void emitUrl(String url) => _onUrl?.call(url);

  void emitLoadEnd(String url) {
    if (_failedLoads.shouldForwardEnd(url)) _onEnd?.call(url);
  }

  @override
  Future<void> start(Uri initialUrl) async {
    started.add(initialUrl);
    final reason = unavailableReason;
    if (reason != null) throw SearchUnavailableException(reason);
  }

  @override
  Future<void> loadUrl(Uri url) async {
    _failedLoads.navigationStarted();
    loaded.add(url);
  }

  @override
  Future<void> goBack() async {
    _failedLoads.navigationStarted();
    backs++;
  }

  @override
  Future<void> reload() async {
    _failedLoads.navigationStarted();
    reloads++;
  }

  @override
  Future<void> releaseFocus() async => focusReleases++;
  @override
  Widget get widget => const SizedBox(key: ValueKey('fake-webview'));

  @override
  void dispose() {
    disposed = true;
    // No callback may fire after dispose (docs/search-web-view-contract.md).
    _onUrl = null;
    _onEnd = null;
    _onError = null;
    _onHistory = null;
  }
}
