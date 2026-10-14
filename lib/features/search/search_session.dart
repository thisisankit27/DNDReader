import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:url_launcher/url_launcher.dart';

import 'search_web_view.dart';

enum SearchPhase {
  /// Never searched yet (no browser exists).
  idle,

  /// The embedded browser is being started.
  starting,

  /// A page is loading.
  loading,

  /// The page finished loading.
  loaded,

  /// Loading failed (offline, DNS, timeout, …).
  failed,

  /// The sandboxed browser cannot run on this system; results open externally.
  unavailable,
}

typedef UrlOpener = Future<bool> Function(Uri url);

Future<bool> _openExternally(Uri url) =>
    launchUrl(url, mode: LaunchMode.externalApplication);

/// State machine behind the search panel.
///
/// One long-lived web view is shared by every search in a run (closing the panel
/// hides it; it is not disposed), so a consent choice made once lasts until the
/// application quits. The session never inspects page content: it only watches
/// URLs of its own navigations.
class SearchSession extends ChangeNotifier {
  SearchSession({
    SearchWebView Function()? webViewFactory,
    UrlOpener? openUrl,
    this.loadTimeout = const Duration(seconds: 20),
    this.errorGrace = const Duration(seconds: 5),
  }) : _factory = webViewFactory ?? SearchWebView.create,
       _openUrl = openUrl ?? _openExternally;

  final SearchWebView Function() _factory;
  final UrlOpener _openUrl;
  final Duration loadTimeout;

  /// How long an ambiguous load error is held before it is shown. A challenge
  /// interstitial (e.g. Cloudflare's) aborts the first navigation and then
  /// loads the real page; showing "couldn't load" for those seconds is wrong.
  final Duration errorGrace;

  SearchWebView? _webView;
  Timer? _timeout;
  Timer? _errorGraceTimer;
  final List<String> _history = <String>[];

  SearchPhase _phase = SearchPhase.idle;
  bool _visible = false;
  String _queryText = '';
  Uri? _searchUri;
  String? _currentUrl;

  /// The URL the page was last reported *loaded* at. A later URL change for the
  /// same entry (Google adds parameters; history navigation reports its address
  /// after load-end) is not a new navigation.
  String? _loadedUrl;
  String? _unavailableReason;

  SearchPhase get phase => _phase;

  /// Whether the panel is shown.
  bool get visible => _visible;

  /// The (normalised) text being searched.
  String get queryText => _queryText;

  /// The URL the panel is showing, once known.
  String? get currentUrl => _currentUrl;

  /// Why the embedded browser is unavailable (phase [SearchPhase.unavailable]).
  String? get unavailableReason => _unavailableReason;

  /// Whether the browser itself says it can go back, when it reports that.
  /// Null for engines that do not.
  bool? _webCanGoBack;

  /// Back is possible when this panel has navigated past the search page.
  ///
  /// Our own list of pages is the truth for *whether*; the browser's history
  /// only decides *how*: a result link often replaces the search page's entry
  /// (the browser then reports it cannot go back), so Back reloads the previous
  /// page ourselves in that case.
  bool get canGoBack => _history.length > 1;

  /// Google asked for a cookie-consent choice (host-only detection).
  bool get consentHint => _isConsentUrl(_currentUrl);

  /// The embedded browser's widget; null before the first search.
  SearchWebView? get webView => _webView;

  static bool _isConsentUrl(String? url) {
    if (url == null) return false;
    final uri = Uri.tryParse(url);
    if (uri == null) return false;
    final host = uri.host.toLowerCase();
    return host == 'consent.google.com' || host == 'consent.youtube.com';
  }

  /// Opens the panel on [uri] (the search URL for [text]).
  Future<void> search(Uri uri, String text) async {
    _visible = true;
    _queryText = text;
    _searchUri = uri;
    _history
      ..clear()
      ..add(uri.toString());
    _currentUrl = uri.toString();

    if (_phase == SearchPhase.unavailable) {
      notifyListeners();
      return;
    }

    if (_webView == null) {
      _phase = SearchPhase.starting;
      notifyListeners();
      final view = _factory();
      view
        ..onUrlChanged = _handleUrlChanged
        ..onLoadEnd = _handleLoadEnd
        ..onLoadError = _handleLoadError
        ..onHistoryChanged = _handleHistoryChanged;
      try {
        await view.start(uri);
      } on SearchUnavailableException catch (e) {
        view.dispose();
        _phase = SearchPhase.unavailable;
        _unavailableReason = e.reason;
        notifyListeners();
        return;
      } catch (e) {
        view.dispose();
        _phase = SearchPhase.failed;
        notifyListeners();
        return;
      }
      _webView = view;
      _beginLoading();
      return;
    }

    _beginLoading();
    await _webView!.loadUrl(uri);
  }

  void _beginLoading() {
    _errorGraceTimer?.cancel();
    _phase = SearchPhase.loading;
    _loadedUrl = null;
    _timeout?.cancel();
    _timeout = Timer(loadTimeout, () {
      if (_phase == SearchPhase.loading) {
        _phase = SearchPhase.failed;
        notifyListeners();
      }
    });
    notifyListeners();
  }

  void _handleUrlChanged(String url) {
    assert(() {
      debugPrint('[search] urlChanged $url (phase ${_phase.name})');
      return true;
    }());
    if (_isErrorPage(url)) return;
    // A bot-check interstitial's hop (…?__cf_chl_tk=…) is not a page the user
    // navigated to; the real URL follows. Not a history entry, nothing to show.
    if (_isChallengeUrl(url)) return;
    if (_history.isEmpty || !_sameEntry(_history.last, url)) {
      _history.add(url);
    } else {
      // Google rewrites its own URL after load (adds tracking parameters); that
      // is not a navigation the user can go back from.
      _history[_history.length - 1] = url;
    }
    _currentUrl = url;
    // A navigation to a *different* page inside the panel (e.g. a clicked
    // result) starts a load. A URL report for the page that is already loaded
    // does not.
    final loadedUrl = _loadedUrl;
    if (_phase == SearchPhase.loaded &&
        (loadedUrl == null || !_sameEntry(loadedUrl, url))) {
      _beginLoading();
      return;
    }
    notifyListeners();
  }

  /// Error names that often describe an aborted *intermediate* navigation (a
  /// challenge page, a redirect hop) rather than the page failing for good.
  static const Set<String> _ambiguousErrors = <String>{
    'unknown',
    'connectionAborted',
    'redirectFailed',
  };

  void _handleLoadError(String url, String errorText, int errorCode) {
    assert(() {
      debugPrint('[search] loadError $errorCode $errorText ($url)');
      return true;
    }());
    // The fork reports main-frame failures only. Never surface the raw text.
    if (_ambiguousErrors.contains(errorText) && _phase != SearchPhase.failed) {
      // Hold it: if the page then loads, there was no failure to show.
      _errorGraceTimer?.cancel();
      _errorGraceTimer = Timer(errorGrace, _fail);
      return;
    }
    _fail();
  }

  void _fail() {
    _errorGraceTimer?.cancel();
    _timeout?.cancel();
    _phase = SearchPhase.failed;
    notifyListeners();
  }

  void _handleHistoryChanged(bool canGoBack) {
    assert(() {
      debugPrint('[search] historyChanged canGoBack=$canGoBack');
      return true;
    }());
    if (_webCanGoBack == canGoBack) return;
    _webCanGoBack = canGoBack;
    notifyListeners();
  }

  void _handleLoadEnd(String url) {
    assert(() {
      debugPrint(
        '[search] loadEnd   $url (phase ${_phase.name}, current $_currentUrl)',
      );
      return true;
    }());
    if (_isErrorPage(url)) {
      _fail();
      return;
    }
    if (_isChallengeUrl(url)) return;
    // load-end also fires for sub-frames (ads, embeds, about:blank); only the
    // page the panel is showing counts. A page that completes after an error
    // (an aborted challenge navigation, a slow load past the timeout) did load,
    // so it also recovers from `failed`.
    if ((_phase == SearchPhase.loading || _phase == SearchPhase.failed) &&
        _currentUrl != null &&
        (url == _currentUrl || _sameEntry(url, _currentUrl!))) {
      _errorGraceTimer?.cancel();
      _timeout?.cancel();
      _loadedUrl = url;
      _phase = SearchPhase.loaded;
      notifyListeners();
    }
  }

  static bool _isErrorPage(String url) => url.startsWith('chrome-error://');

  /// Cloudflare's challenge hops carry a `__cf_chl_*` query parameter.
  static bool _isChallengeUrl(String url) => url.contains('__cf_chl_');

  /// Two URLs are the same history entry when they only differ in parameters
  /// the page itself adds after loading (same host, path and `q`).
  static bool _sameEntry(String a, String b) {
    if (a == b) return true;
    final ua = Uri.tryParse(a), ub = Uri.tryParse(b);
    if (ua == null || ub == null) return false;
    return ua.host == ub.host &&
        ua.path == ub.path &&
        ua.path == '/search' &&
        ua.queryParameters['q'] == ub.queryParameters['q'];
  }

  Future<void> back() async {
    if (!canGoBack) return;
    _history.removeLast();
    final previous = _history.last;
    _currentUrl = previous;
    _beginLoading();
    if (_webCanGoBack != false) {
      // The browser has the entry (or does not report its history, as CEF):
      // let it restore the page and its scroll position.
      await _webView?.goBack();
    } else {
      // The browser said it cannot go back: the entry was replaced (result
      // links often do that). Load the previous page again ourselves.
      final uri = Uri.tryParse(previous);
      if (uri != null) await _webView?.loadUrl(uri);
    }
  }

  Future<void> retry() async {
    final uri = Uri.tryParse(_currentUrl ?? '') ?? _searchUri;
    if (uri == null) return;
    _beginLoading();
    await _webView?.loadUrl(uri);
  }

  /// Opens the page being shown (or the search) in the system browser.
  Future<void> openInBrowser() async {
    final uri = Uri.tryParse(_currentUrl ?? '') ?? _searchUri;
    if (uri == null) return;
    await _openUrl(uri);
  }

  /// Hides the panel. The browser stays alive.
  void close() {
    if (!_visible) return;
    _visible = false;
    notifyListeners();
  }

  @override
  void dispose() {
    _timeout?.cancel();
    _errorGraceTimer?.cancel();
    _webView?.dispose();
    _webView = null;
    super.dispose();
  }
}
