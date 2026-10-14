import 'package:dndreader/features/search/search_web_view.dart';
import 'package:flutter/widgets.dart';

/// A scripted [SearchWebView]: records calls and lets a test fire events.
class FakeSearchWebView implements SearchWebView {
  FakeSearchWebView({this.unavailableReason});

  /// When set, [start] throws [SearchUnavailableException] with this reason.
  final String? unavailableReason;

  final List<Uri> started = [];
  final List<Uri> loaded = [];
  int backs = 0;
  int reloads = 0;
  int focusReleases = 0;
  bool disposed = false;

  void Function(String url)? _onUrl;
  void Function(String url)? _onEnd;
  void Function(String url, String errorText, int errorCode)? _onError;

  @override
  set onUrlChanged(void Function(String url)? callback) => _onUrl = callback;
  @override
  set onLoadEnd(void Function(String url)? callback) => _onEnd = callback;

  void Function(bool canGoBack)? _onHistory;

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
  }) => _onError?.call(url, text, code);

  void emitUrl(String url) => _onUrl?.call(url);
  void emitLoadEnd(String url) => _onEnd?.call(url);

  @override
  Future<void> start(Uri initialUrl) async {
    started.add(initialUrl);
    final reason = unavailableReason;
    if (reason != null) throw SearchUnavailableException(reason);
  }

  @override
  Future<void> loadUrl(Uri url) async => loaded.add(url);
  @override
  Future<void> goBack() async => backs++;
  @override
  Future<void> reload() async => reloads++;
  @override
  Future<void> releaseFocus() async => focusReleases++;
  @override
  Widget get widget => const SizedBox(key: ValueKey('fake-webview'));
  @override
  void dispose() => disposed = true;
}
