# `SearchWebView` adapter contract

What an engine adapter behind `lib/features/search/search_web_view.dart` must do to be a correct
`SearchWebView`. This is normative for the two shipped adapters (`CefSearchWebView` on Linux/macOS,
`Webview2SearchWebView` on Windows) and for any future one (mobile, M7). Derived from the two
shipped adapters' actual behaviour, not invented: where they already differ, this document says
which behaviour is normative and which is an engine quirk the adapter absorbs.

Out of scope: the text of engine-specific error codes (passed through unfiltered — see `onLoadError`
below); page content (an adapter never parses, scrapes, or automates it — see "Security invariants").

The companion conformance suite (`test/search/search_web_view_conformance.dart`,
`integration_test/search_web_view_conformance_test.dart`) exercises every assertion this document
makes that can be checked mechanically. A new adapter should be written against this document and
proven against that suite before it ships.

## `start(Uri initialUrl)`

Starts the engine and loads `initialUrl`.

- On success, the adapter is ready to receive `loadUrl`/`goBack`/`reload` calls and `widget` returns
  something other than an empty placeholder once the engine reports it is ready.
- On failure to start the sandboxed engine, `start` throws `SearchUnavailableException` and
  **nothing was started**: no controller, no OS-level handle, no background process left running.
  `dispose()` must be safe to call afterwards (both adapters guard this: `CefSearchWebView` tracks
  `_cefStarted` and skips `WebviewManager().quit()` when it's false; `Webview2SearchWebView` disposes
  its controller and deletes its throwaway profile directory before rethrowing). The caller
  (`SearchSession`) treats this as "the embedded browser is unavailable here": the app degrades to an
  "Open in browser" action and remains fully usable as a reader.
- A second call to `start()` on the same instance is **out of contract** — neither adapter guards
  against it (CEF would silently reassign its controller and leak the first one; Windows would
  re-register its shutdown hook and leak the first controller and profile directory). This is a
  caller obligation, not an adapter responsibility: `SearchSession` already enforces single-call by
  gating on `_webView == null`. An adapter does not need to detect or reject a second call, and the
  conformance suite does not exercise one.

## `loadUrl(Uri)` / `goBack()` / `reload()`

Navigation on an already-started instance. None of these repeat `start()`'s preconditions (they
assume a running engine) and none promise synchronous completion — the outcome always arrives
through the callbacks below, including for `goBack`, which also only arrives as a normal
`onUrlChanged`/`onLoadEnd` pair.

Each of these **must** clear any load-end suppression pending from a previous failure on this
instance (see the failed-load-end rule below), so the next completion is evaluated fresh rather than
being mistaken for the old failure's trailing event. `CefSearchWebView` does this explicitly
(`_failedLoads.navigationStarted()` in all three methods). `Webview2SearchWebView` does **not** —
this is a known adapter defect, not contract-compliant behaviour; see "Known adapter non-conformance"
below.

Called before `start()` finishes or after `dispose()`: must no-op silently, never throw (a legitimate
no-op — see below).

## The callbacks

### `onUrlChanged(String url)`

Main-frame URL changes only. May fire more than once for a single navigation (a redirect chain, a
page rewriting its own URL after load). Must not fire for a sub-frame's address.

### `onLoadEnd(String url)`

A frame finished loading. **May fire for sub-frames** (ads, embeds, `about:blank`) as well as the
main frame — this is tolerated by design, not a per-adapter capability: **the session, not the
adapter, decides which URL counts as "the page"** (`SearchSession._handleLoadEnd` matches `url`
against its own notion of the current page before acting on it). An adapter must not try to filter
sub-frames itself; it only needs to report what the engine reports.

**The failed-load-end rule.** Both CEF and WebView2 report a load *end* for a navigation that just
failed, immediately after the error, carrying the failed URL — an engine quirk, not a second
navigation. Forwarding it turns a failure into a false "loaded" the instant it fires (this is
exactly the Linux regression `FailedLoadEndFilter` was written to fix: offline, CEF's trailing
load-end for the failed URL made every search failure silently report "loaded"). Stated normatively,
per failed URL:

1. If the engine's own next load-end for the main frame, with **no** intervening
   `loadUrl`/`goBack`/`reload`/fresh `start` call, repeats the exact URL just reported via
   `onLoadError`, the adapter must **not** forward it.
2. This suppression is per-failure and fires **at most once**. A later load-end for that same URL
   (the engine quietly redirecting or retrying on its own, with no Dart-side call in between) must be
   forwarded — it is not assumed to be more engine noise.
3. Any `loadUrl`/`goBack`/`reload`/fresh `start` clears the pending suppression immediately, even
   before the engine's own trailing end for the old failure has arrived. The next load-end belongs to
   the new navigation and must be forwarded (subject to its own, independent failure).

Reference implementation: `FailedLoadEndFilter` in `search_web_view.dart`. An adapter must reuse it
or implement an equivalent per-URL state machine — not a bare boolean that isn't keyed to the URL and
isn't reset by the navigation calls (see "Known adapter non-conformance").

**Is `SearchSession`'s "recovers from failed" rule reachable through a bare single load-end in
production?** `SearchSession._handleLoadEnd` treats any load-end that arrives while `phase` is
already `failed` as a recovery. Investigation for this document found that, on both shipped adapters,
the *first* load-end after a failure is always suppressed (clause 1 above), so this branch is
reachable only via: (a) an explicit navigation call first (which resets `phase` away from `failed`
*before* the adapter's completion arrives — not really "recovering from failed" at the adapter-event
level, see the recovery-via-navigation scenario in the conformance suite), or (b) a genuine *second*
load-end for the same URL, per clause 2, with no intervening navigation call (an engine retrying
internally on its own). Neither shipped adapter has been observed exercising (b) in production: the
real Cloudflare-gated case recorded in `docs/windows-verification/REPORT.md` (D3, and the Linux
`gated` regression pass, §9) only ever produced `WebErrorStatus`/CEF `unknown`-class errors for an
*aborted* navigation, handled entirely by `SearchSession`'s ambiguous-error grace timer before phase
ever reaches `failed` — a different code path. The `_phase == SearchPhase.failed` recovery branch is
therefore a defensive guarantee of what the session does *if* clause 2 is ever exercised, not a path
either shipped adapter is known to take today. Treat it as such when writing adapter conformance
tests: model clause 2 explicitly (first end suppressed, second end genuine), not a bare single end.

### `onLoadError(String url, String errorText, int errorCode)`

The main frame failed to load (offline, DNS, refused, …). Main-frame only. `errorText`/`errorCode`
are passed through unfiltered and raw — bucketing ambiguous-vs-definite errors is `SearchSession`'s
policy, not the adapter's; an adapter must not translate, summarise, or suppress an error code before
forwarding it.

### `onHistoryChanged(bool canGoBack)`

The engine's own history state, for engines that report it. **Capability-gated**: an engine that
does not track native history simply never calls this — not "calls it once with a default value."
`CefSearchWebView` never calls it at all; `SearchSession` then relies entirely on its own navigation
record. See "Capability flags" below for how this is declared and consumed by the conformance suite.

## Legitimate no-ops

A legitimate no-op must not read as a defect. These are deliberate, not missing functionality:

- `CefSearchWebView.onHistoryChanged` setter: the callback is stored but never invoked (CEF is not
  asked for its history state; the session keeps its own record).
- `CefSearchWebView.releaseFocus()`: a no-op. Meaningful only where the embedder can hold native OS
  focus after the webview is hidden (WebView2 on Windows); CEF's focus is handled by Flutter's own
  focus tree.
- Any navigation call (`loadUrl`/`goBack`/`reload`) issued before `start()` finishes or after
  `dispose()`: must no-op silently, never throw.

## Capability flags

```dart
@immutable
class SearchWebViewCapabilities {
  const SearchWebViewCapabilities({
    required this.reportsHistory,     // calls onHistoryChanged at all
    required this.releaseFocusIsNoop, // releaseFocus() has no observable effect
  });
  final bool reportsHistory;
  final bool releaseFocusIsNoop;
}
```

Exposed as `SearchWebView.capabilities`. The conformance suite reads this to decide which assertions
apply — e.g. it asserts `onHistoryChanged` is forwarded when `reportsHistory` is true, and asserts it
is *never* called when false, rather than skipping the check silently. There is deliberately no
`subFrameLoadEndPossible`-style flag: sub-frame `onLoadEnd` tolerance (above) is a universal contract
guarantee, not something that varies per adapter, so it is covered by never asserting "`onLoadEnd`
fires exactly once in total," not by a capability flag.

Declared values:

| Adapter | `reportsHistory` | `releaseFocusIsNoop` |
|---|---|---|
| `CefSearchWebView` | `false` | `true` |
| `Webview2SearchWebView` | `true` | `false` |
| `_UnsupportedSearchWebView` | `false` | `true` (arbitrary — never exercised, see below) |

`_UnsupportedSearchWebView` is a deliberate always-unavailable stand-in for platforms with no adapter
yet (mobile, pre-M7); its `start()` always throws `SearchUnavailableException`, so the conformance
suite is never run against it.

## `dispose()`

Must be idempotent (safe to call more than once) and safe to call when `start()` was never called,
or threw. After `dispose()` is called, no **new** callback-triggering work may be started — this is
"no new work starts," not "every in-flight callback is synchronously cancelled before `dispose()`
returns": `Webview2SearchWebView.dispose()` kicks off `unawaited(_shutdown())`, an async teardown, so
a conformance check for "no callbacks after dispose" must poll or wait briefly rather than assert
silence in the same microtask.

## Security invariants

These are part of the contract, not decoration:

- A release build never honours `DNDREADER_ALLOW_UNSANDBOXED_DEV` — the check is gated on
  `kReleaseMode`, a compile-time constant, so in a release build the environment variable is not even
  read.
- An adapter that cannot start a sandboxed engine **fails closed**: it throws
  `SearchUnavailableException` rather than falling back to an unsandboxed engine. The only way to run
  unsandboxed at all is the development override, and only in non-release builds.
- An adapter never parses, scrapes, or automates page content. It only ever observes URLs, load
  completion, load errors, and (where supported) history state. This is also why the conformance
  suite's test pages carry no body/content assertions — only URL and event-sequence assertions.

## Known adapter non-conformance (tracked, not fixed here)

`Webview2SearchWebView._navigationFailed` is a bare boolean, not a per-URL filter: it is set to
`true` in the `onLoadError` listener (before the early return for `operationCanceled`) and cleared
only by the *next* `NavigationCompleted`, regardless of which navigation that completion belongs to.
Unlike CEF's `navigationStarted()`, `loadUrl`/`goBack`/`reload` do **not** clear it. Concretely: if a
second `loadUrl` is issued while a first navigation is still in flight — the ordinary "clicked a
second result before the first finished" case — WebView2 reports the first navigation as
`operationCanceled` (setting `_navigationFailed = true`), and the *second* navigation's own
`NavigationCompleted` is then swallowed as if it were the first failure's trailing event. No error is
ever reported for the second navigation, so `SearchSession` has no error to react to; it simply waits
out the full load timeout and shows a false failure for a page that did load. This violates clause 3
of the failed-load-end rule (a new navigation must clear the pending suppression) and is exercised by
a dedicated Layer 2 conformance scenario; see that suite's report for whether it was reproduced.

`CefSearchWebView.dispose()` is not idempotent as written: `_cefStarted` is set once in `start()` and
never reset, so a second `dispose()` call runs `WebviewManager().quit()` a second time. Fixed (small,
obviously correct, demonstrated on Linux): `dispose()` now clears `_cefStarted` before quitting, so a
second call is a no-op. Separately, and **not fixed**: even a single real `WebviewManager().quit()`
leaves the process unable to reliably keep running Dart/test code afterward — the Layer 2
conformance suite's final assertion (`no callback fires after dispose`) reproducibly fails to
*complete* (no Dart exception, no native stderr, "did not complete" rather than a reported
assertion) both at the end of the full suite and in a minimal two-test isolation, identically before
and after the `_cefStarted` fix. This looks like an async/native teardown race inside the pinned
`webview_cef` fork or CEF itself, surfaced only because the conformance suite now reuses one engine
for a whole process instead of one per test (see `integration_test/search_web_view_conformance_test.dart`);
production code never continues running after disposing its webview (it is always the last thing
`SearchSession.dispose()` does before the app itself exits), so this has no known user-facing
consequence, but it is also not something a small patch here can responsibly fix. Tracked, not
fixed.
