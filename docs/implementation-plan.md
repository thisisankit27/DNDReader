# DNDReader — Implementation Plan (embedded Google Search, no AI)

> **Status:** plan approved 2026-10-13. No application code exists yet.
> **Next action:** the M0 feasibility spike in §2 — before writing any application code.
> Progress and observations belong in `docs/progress.md` (created during M0).

## Context

**The product.** A minimal PDF reader that removes the context switch between reading and looking
something up. Open a PDF → select a word, phrase or passage → a contextual **"Find meaning"**
action appears → a side panel opens inside the reader showing **Google Search results** for that
text → read, then carry on without ever leaving the app or losing your place.

We are **not** building an AI explanation engine. Google provides the search experience and
whatever it chooses to show, which sometimes includes an AI Overview and sometimes does not. The
product promises *search inside the reader*, never *an AI answer every time*.

**Repository state:** empty. Branch `master`, no commits, remote
`github.com/thisisankit27/DNDReader`.

**What this supersedes.** Two earlier drafts of this plan are void: one built a Tauri + Anthropic
API reader, one built a Flutter + Gemini reader. Everything AI-related is **removed** — no Gemini,
no Claude, no Ollama, no API keys, no model selection, no provider abstraction, no prompts, no LLM
context extraction, no response streaming, no backend, no database, no accounts. None of that
infrastructure survives into this plan.

**This session is planning only.** Its sole output is `docs/implementation-plan.md` and
`README.md`. The implementation session starts at **M0** (§2 spike), then M1 onward.

---

## 1. The decision that drives everything

With AI gone, the central technical requirement is now a pair:

> **reliable PDF text selection** *and* **an embedded browser panel** — on five platforms, Ubuntu first.

The embedded browser is the harder half, and it is what picks the framework. Researched findings:

| Framework | Embedded webview, Linux desktop | Mobile | PDF text selection |
|---|---|---|---|
| **Flutter** | `webview_cef` (CEF 149, docked via `Texture`) | `webview_flutter` — official, 4.5k likes, 3.5M dl/mo | **`pdfrx`/PDFium — documents selection support on all 5 platforms** |
| Tauri v2 | **Blocked.** Child webviews are still an `unstable` feature, with an open Linux layout bug (tauri#13071). An `<iframe>` cannot be used — Google Search sends `X-Frame-Options`. | Young | pdf.js (fiddly touch selection) |
| Electron | Excellent (`WebContentsView`) | **None** | pdf.js |

Dead ends already checked and ruled out, so nobody re-treads them:

- `webview_flutter` — official, but **Android/iOS/macOS only**. No Linux, no Windows.
- `flutter_inappwebview` 6.1.5 — its dependency list is android/ios/macos/web/windows. **Linux is
  not in it.** The separate `flutter_inappwebview_linux` is `0.1.0-beta.1` and needs **WPE WebKit**,
  which **is not packaged in Ubuntu 26.04 at all** (`libwpewebkit*`, `libwpe*` all absent;
  `apt-cache search wpe` finds only an unrelated editor). Would mean vendoring WPE from source.
- `flutter_linux_webview` — last published 2024-08, pinned to `webview_flutter` 3.0.4. Abandoned.
- `webview_linux` 0.0.2 — FFI binding to WebKitGTK 4.1 (which *is* installed here), but brand new,
  0 likes, 28 downloads/month. Too immature to carry the MVP's central feature.
- `desktop_webview_window` (mature: 222 likes, 558k dl/mo) — opens a **separate OS window**, not an
  embedded panel. Kept as a documented degraded fallback only.

### Decision: **Flutter 3.47.7 / Dart 3.13.5**

Flutter is the only option that reaches all five platforms with one codebase while keeping
best-in-class PDF text selection. Electron is the better embedded browser but has no mobile path
at all; Tauri's docked-webview API is not ready on the MVP's own platform.

One platform seam is accepted, deliberately and in one place: the **webview host**.

- Desktop (Linux/Windows/macOS): **`webview_cef ^0.6.2`** — CEF 149, 243 stars, actively
  maintained (last commits Sept 2026). Its README states it renders into a Flutter `Texture` so
  web content composes with the rest of the Flutter UI, and documents `loadUrl`, `goBack`,
  `goForward`, `reload`, user-agent at init, and cookie access — everything the panel needs. It
  also states CEF downloads automatically on the first Linux build. **All of this is read from
  documentation; none of it has been exercised yet — that is what M0 is for.**
- Mobile (Android/iOS): **`webview_flutter ^4.14.1`** — official and boring, which is what we want.

Both sit behind one `SearchWebView` interface (~60 lines of conditional wiring). All shared logic —
reader, selection, action, panel chrome, URL building, preferences — is written once.

**Costs accepted, stated plainly:** CEF makes the Linux/Windows/macOS bundle large (~150–250 MB);
`webview_cef` notes Linux "still uses the software path", so panel scrolling may be less smooth
than a native browser; CEF 149 requires a **C++20** toolchain.

---

## 2. Embedded Google Search: what will and won't work

**Does Google Search need the user to sign in? No.** Signed-out search works normally. What Google
blocks in embedded webviews is **sign-in/OAuth** (`disallowed_useragent`) — a policy in force for
years in developer reports, the most recent found dating to Oct 2026 — note this comes from
those reports and from Microsoft's guidance on the same symptom, not from a single official Google
policy page that the research located. We never need sign-in, so this does not
block the feature. The consequence to document: **a user cannot sign in to Google inside the
panel**, so personalised results and anything gated behind an account are unavailable. Do not try
to work around this.

**Expected friction, and how to handle it:**

| Issue | Handling |
|---|---|
| Cookie/consent interstitial on first load (region-dependent) | Ordinary browsing — the user taps accept once; cookies persist in the webview profile. Not a blocker. |
| `/sorry/index` reCAPTCHA ("unusual traffic") | Triggered by automated-looking volume or shared/VPN IPs. We issue exactly one navigation per explicit user click, which is ordinary volume. If it appears, the user can solve it in the panel like any browser. |
| Results page cramped in a narrow panel | Panel ≥ 420 px on desktop; let Google serve its own responsive layout. Bottom sheet on mobile. |
| AI Overview missing | **Expected and documented.** Never promised anywhere in the UI or README. |

**Hard rules, from the brief:** build the query as a URL with the selected text properly
percent-encoded and navigate to it. **Do not parse or scrape result HTML. Do not automate
interaction. Do not attempt to defeat webview restrictions.** This is user-initiated ordinary
browsing in an embedded view — nothing is extracted programmatically.

### M0 spike — mandatory, and the first action of the implementation session

This planning session produces documentation only. **The implementation session begins with this
spike, before any application code is written.** It is a throwaway Flutter app, time-boxed to
about an hour.

The question this plan cannot resolve from documentation is not "does the URL load" — a blank page,
a consent wall, or an unreadable column all count as loading. **M0 must establish real usability.**
Check each of the following and **record what was actually observed — not merely pass/fail — in
`docs/progress.md`:**

1. **Results render.** Actual Google result listings appear for a realistic query (e.g.
   `idiopathic pulmonary fibrosis`), not an error, consent wall, or empty page.
2. **Signed-out operation.** Everything above works with no Google account and no sign-in attempt.
3. **Readability at panel width.** Results are legible and usable at the intended ~420–480 px
   panel width, not a broken or horizontally-scrolling desktop layout.
4. **Scrolling.** The results page scrolls smoothly inside the panel, and note how the Linux
   software rendering path actually feels.
5. **Navigation.** Clicking a result navigates within the panel, and `goBack()` returns to the
   results. Note what happens to links that try to open a new window or tab.
6. **Consent and challenge behaviour.** Whether a cookie/consent interstitial or a
   `/sorry/index` CAPTCHA appears, whether it is solvable in place, and whether accepting it
   persists across restarts.
7. **Whether an AI Overview appears at all**, for reference only — it is never a requirement.

Also record the CEF first-build experience: download size, build time, and any toolchain errors.

**Google is the default and intended search engine.** The ladder below exists to make Google work,
not to replace it casually. Stop at the first step that works; do not escalate past step 4.

1. Set a current desktop Chrome user-agent via `WebviewManager().initialize(userAgent: …)`.
2. Try the public `&igu=1` query parameter, which historically renders a lighter results page.
   Test it; do not depend on it.
3. If Google still proves unusable: **do not silently switch engines.** Write the specific observed
   failure into `docs/progress.md`, then surface it as an explicit product decision for the user —
   switching the default engine changes what the product is, and is the user's call, not the
   implementer's. The search URL lives in one constant in `services/search_url.dart` precisely so
   that decision is cheap to execute *once it has been made* (`https://duckduckgo.com/?q=` being
   the obvious candidate, since the panel and the whole UX stay identical).
4. The panel always carries an **"Open in browser"** button (`url_launcher`) as a universal escape
   hatch. This ships regardless of the spike's outcome — it is useful on its own.

Anything beyond step 4 is out of scope by instruction.

---

## 3. Dependencies — the complete list

`pdfrx ^2.6.5` · `webview_cef ^0.6.2` (desktop) · `webview_flutter ^4.14.1` (mobile) ·
`url_launcher ^6.3.3` · `file_picker ^13.1.0` · `shared_preferences ^2.5.6`
dev: `flutter_lints`, `integration_test`

No HTTP client, no secure storage, no state-management library, no markdown renderer — none are
needed any more.

---

## 4. Project structure

```
DNDReader/
├── README.md
├── docs/
│   ├── implementation-plan.md        # this document, committed
│   └── progress.md                   # milestone checklist + session handoff
├── pubspec.yaml
├── analysis_options.yaml
├── lib/
│   ├── main.dart                     # entry, argv (open PDF from file manager)
│   ├── app.dart                      # MaterialApp, theme, responsive shell
│   ├── models/
│   │   └── app_settings.dart         # zoom, theme, lastDocument, recents, windowSize
│   ├── services/
│   │   ├── search_url.dart           # selection → normalised query → encoded URL
│   │   └── settings_service.dart     # shared_preferences
│   ├── features/
│   │   ├── reader/
│   │   │   ├── reader_screen.dart     # layout: header + viewer + panel/sheet
│   │   │   ├── pdf_view.dart          # PdfViewer + PdfTextSelectionParams
│   │   │   ├── reader_header.dart     # title, page n/N, zoom, open
│   │   │   ├── selection_action.dart  # floating "Find meaning" pill
│   │   │   └── empty_state.dart
│   │   └── search/
│   │       ├── search_panel.dart          # shared chrome: header, back, close, states
│   │       ├── search_web_view.dart       # interface + platform factory
│   │       ├── search_web_view_desktop.dart   # webview_cef
│   │       └── search_web_view_mobile.dart    # webview_flutter
│   └── theme/{colors.dart,typography.dart}
├── test/
│   ├── search_url_test.dart          # the main pure-logic test target
│   ├── settings_service_test.dart
│   └── widget/{selection_action_test.dart,search_panel_test.dart}
├── integration_test/reading_journey_test.dart   # best-effort
├── test_fixtures/{make_fixtures.sh,prose.pdf,technical.pdf,two_column.pdf}
└── packaging/linux/{build-deb.sh,dndreader.desktop}
```

---

## 5. The two mechanisms worth specifying

### 5.1 Selection → "Find meaning" (`pdf_view.dart` + `selection_action.dart`)

These `pdfrx` APIs are documented in the 2.6.5 API reference and look like the right ones. **They
have been read, not run** — §5.1.1 is the gate that establishes they behave as described:

```dart
PdfViewerParams(
  textSelectionParams: PdfTextSelectionParams(
    enabled: true,
    enableSelectionHandles: isTouch,        // mobile handles
    showContextMenuAutomatically: false,    // we render our own action
    magnifier: isTouch ? const PdfViewerSelectionMagnifierParams() : null,
    onTextSelectionChange: _onSelectionChange,   // void Function(PdfTextSelection)
  ),
)
```

`PdfTextSelection` gives `hasSelectedText`, `getSelectedText() → Future<String>`,
`getSelectedTextRanges() → Future<List<PdfPageTextRange>>`, and `textSelectionPointRange` for
anchoring. `PdfPageText` exposes `fullText`, `charRects`, `pageNumber`.

- Debounce `onSelectionChange` by ~120 ms. If `hasSelectedText`, show the action anchored near the
  selection end; otherwise hide it.
- Anchor from `textSelectionPointRange`; **if that type's shape proves awkward, fall back to the
  last entry of `PdfPageText.charRects` transformed through `PdfViewerController`.**
- Flip above/below and clamp horizontally so the pill is never off-viewport, and never let it
  overlap the selection rectangle.
- The pill must not steal the selection: no focus grab, hit-testing only on the pill itself.
- Desktop: compact pill, `✦ Find meaning`, with a `Ctrl+E` hint. Touch: same action at the
  selection-toolbar position above the handles, ≥48 dp target.
- Keyboard: `Ctrl/Cmd+E` triggers, `Esc` closes the panel, `Tab` reaches the pill.

#### 5.1.1 pdfrx verification gate — do this in M2/M3 *before* polishing the action UI

Three pdfrx behaviours underpin the entire interaction, and all three are currently assumptions
read from documentation. Prove each one with a crude on-screen debug readout (dump the values into
a `Text` widget or the console) on every fixture, and record the observations in
`docs/progress.md`. **Do not style or refine the selection pill until all three hold.**

1. **Text retrieval.** `getSelectedText()` returns the expected string for a word, a phrase, a
   full sentence, and a multi-line span — and `getSelectedTextRanges()` returns usable page numbers
   and character offsets. Separately confirm `PdfPageText.fullText` is non-empty on a text-based
   page, and note how line breaks, hyphenated line-wraps and ligatures actually come through, since
   §5.2's normalisation depends on it.
2. **Selection preservation.** The selection survives showing our own widget: with
   `showContextMenuAutomatically: false`, confirm the selection is not cleared when the pill
   appears, when the pill is tapped or clicked, and that `pdfrx`'s own menu stays suppressed. If
   rendering the pill clears the selection, capture the selected text in the
   `onTextSelectionChange` callback and hold it in state rather than re-reading it on click.
3. **Selection → screen coordinates.** Establish which API actually yields a usable on-screen
   rectangle for anchoring — `textSelectionPointRange`, or `PdfPageText.charRects` transformed
   through `PdfViewerController`. Verify the anchor stays correct while **scrolling and zooming**,
   and at non-default zoom levels; a rect that is right only at 100% is not good enough.

If any of the three cannot be made to work, stop and report it before building on top of it — it
would be a genuine architectural finding, not a detail.

### 5.2 Selection → query → URL (`search_url.dart`)

This is the only non-trivial pure logic in the app, so it carries the unit tests. PDF text
selections are messy: hard line breaks, hyphenated line-wraps, ligatures, stray whitespace.

```
1. Collapse CR/LF/tabs to single spaces.
2. Repair line-wrap hyphenation: /(\w)-\s+(\w)/ → "$1$2"   (e.g. "idio-\npathic" → "idiopathic")
3. Collapse runs of whitespace; trim.
4. Reject empty/whitespace-only → noSelection state, no navigation.
5. Cap at ~300 characters on a word boundary (a search query, not a document).
6. Uri.encodeQueryComponent(query) into the single URL template constant.
```

Tests: spaces, `&`, `+`, `#`, `?`, quotes, em-dashes, non-Latin/Unicode text, multi-line
selections, hyphenated wraps, a 5,000-character selection, whitespace-only, and a single word.

---

## 6. UI/UX

The PDF is the product; search is a quiet utility beside it.

- **Header:** document title, `page n / N`, zoom −/+, "Open". One row, no chrome.
- **Reading surface:** PDFium pages, continuous vertical scroll, comfortable margins.
- **Panel (desktop):** ~420–480 px, **overlaying** the right edge so the document **never reflows
  and never loses scroll position**. Header shows the queried text (2 lines max) with Back,
  Open-in-browser, and Close. Body = the webview. Dismiss via `✕`, `Esc`, or clicking the document.
- **Panel (mobile):** the same content as a draggable bottom sheet, comfortable touch targets.
- **Panel never interferes with reading:** it does not capture scroll over the document, does not
  trap focus while closed, and closing restores the exact scroll offset.
- **States:** loading (calm placeholder while the page loads, with a 20 s timeout), loaded,
  navigation error / offline (clear message + Retry + Open in browser), no-selection (action simply
  does not appear). No spinner can run forever; no raw error strings.
- **Accessibility:** semantic labels, ≥48 dp targets, WCAG AA contrast in light and dark, full
  keyboard path, nothing conveyed by colour or hover alone.

---

## 7. Milestones

Branch `feat/mvp-reader`; one commit per milestone; update `docs/progress.md` at each.

- **P0 — Planning session (this session).** Produce `docs/implementation-plan.md` and `README.md`,
  and commit them. **No application code, no spike, nothing else.**
- **M0 — Feasibility spike. The first action of the implementation session, before any
  application code.** Run §2's usability checks in a throwaway app and write the observations into
  `docs/progress.md`. If Google proves unusable, stop and raise it as a product decision per §2
  step 3 rather than proceeding.
- **M1 — Shell runs on Ubuntu.** `flutter create`, pinned deps, theme, responsive shell, header,
  empty state. `flutter run -d linux` shows a considered window.
- **M2 — Real PDF reading.** `file_picker` → `pdfrx`; scroll, zoom, page indicator, open another
  document, argv/`%f` opening. Verify word/phrase/sentence/multi-line selection on all fixtures,
  and complete **§5.1.1 gates 1 and 2** (text retrieval, selection preservation).
- **M3 — Selection → action.** Complete **§5.1.1 gate 3** (selection → screen coordinates, correct
  under scroll and zoom) **first**; only then build `PdfTextSelectionParams` wiring, the debounced
  callback, the anchored pill with edge flipping and clamping, `Ctrl+E`, `Esc`, and dismissal.
  Confirm the pill never breaks selection.
- **M4 — Embedded search panel.** `webview_cef` docked panel, URL building, loading/error/retry,
  Back, Open-in-browser, Close restoring scroll position.
- **M5 — Finish the experience.** Persisted zoom/theme/last document/recents/window size,
  keyboard shortcuts, typography and spacing pass.
- **M6 — Tests, packaging, docs.** Full test run, `.deb`, README rewritten to match reality, PR →
  self-review → squash merge to `main`.
- **M7 — Android** (after Ubuntu is merged). Swap in `search_web_view_mobile.dart`; verify touch
  selection, handles, magnifier, bottom sheet. The Android SDK is already installed at
  `~/Android/Sdk`.
- **Later — Windows / macOS / iOS.** Architecturally supported; each needs its own hardware and its
  own verification pass. **Do not claim any of them works until it has been built and tested.**

**Not in scope:** OCR, DOCX/EPUB, annotations, highlight persistence, accounts, sync,
collaboration, in-panel tabs or bookmarks, a general-purpose browser, AI of any kind.

---

## 8. Build, test, package (Ubuntu)

**Prerequisites** — verified available in Ubuntu 26.04 repos; none currently installed:

```bash
sudo apt update && sudo apt install -y \
  clang cmake ninja-build pkg-config libgtk-3-dev liblzma-dev libstdc++-14-dev
```

Flutter stable **3.47.7** (Dart 3.13.5) — satisfies `pdfrx`'s ≥3.47.0 floor. `flutter doctor` must
be clean for `linux`. CEF downloads on first build. **Disk: only ~30 GB free on `/home`** — Flutter
SDK, CEF and build artifacts need ~6–8 GB; don't install extra Android system images.

**Pre-PR checks:**

```bash
dart format --set-exit-if-changed .
flutter analyze
flutter test
flutter build linux --release
bash packaging/linux/build-deb.sh     # → build/dndreader_<ver>_amd64.deb
```

**Packaging:** Flutter has no built-in `.deb`, so `build-deb.sh` (~40 lines) assembles
`usr/lib/dndreader/` (bundle incl. CEF), `usr/bin/dndreader`, the `.desktop` entry with
`MimeType=application/pdf` and `Exec=dndreader %f` (enables "Open With" from the file manager),
icons, and `DEBIAN/control`, then `dpkg-deb --build`. `.deb` is the only MVP format; AppImage
deferred.

**CEF runtime dependencies must be derived, not guessed.** `Depends: libgtk-3-0` is a starting
assumption, not an answer — CEF links a long list of X11, NSS, DBus and font libraries that are
present on this development machine and may be absent elsewhere. Before the PR:

```bash
# every shared object the bundle actually needs, and anything unresolved
find build/linux/x64/release/bundle -type f \( -name '*.so*' -o -perm -u+x \) \
  -exec ldd {} \; 2>/dev/null | grep -i 'not found' | sort -u          # must be empty
# map resolved libraries back to the packages that provide them
ldd build/linux/x64/release/bundle/dndreader | awk '{print $3}' | grep '^/' \
  | xargs -r dpkg -S 2>/dev/null | cut -d: -f1 | sort -u
```

Put the resulting package names in `DEBIAN/control` `Depends:`, and record the derived list in
`docs/progress.md`.

**The `.deb` must then be tested in a clean Ubuntu environment** — not on this machine, where every
build dependency is already installed and a passing launch proves nothing. Use a fresh Ubuntu 26.04
container or VM with no Flutter, no clang, and no CEF present:

```bash
# e.g. podman/docker run -it --rm ubuntu:26.04   (plus X/Wayland socket passthrough for the GUI)
apt-get install -y ./dndreader_<ver>_amd64.deb   # must resolve deps with no manual apt installs
dndreader test_fixtures/prose.pdf                # must launch, render, select, and open the panel
```

A missing-dependency failure here is a packaging bug to fix, not a note to add to the README.
If GUI passthrough into a container proves impractical, say so explicitly and test in a VM or a
fresh user account instead — but do not skip the clean-environment install check, and do not
report it as done if it was not run.

**Fixtures:** `test_fixtures/make_fixtures.sh` generates three PDFs from local HTML via
`google-chrome --headless --print-to-pdf` (verified present): book prose, a technical article with
headings, and a two-column long-paragraph layout. For a real-world 240-page technical document use
`/usr/share/doc/shared-mime-info/shared-mime-info-spec.pdf` (verified present). **Do not use the
PDFs in `~/Downloads` — those are the user's personal documents.**

**Automated tests** are deliberately modest, because with no AI provider there is little
deterministic logic left: `search_url.dart` (the full table in §5.2), settings persistence, and
widget tests for the selection pill (appear / position / flip / dismiss) and panel states
(loading → loaded → error → retry → close). The webview is never driven in unit tests.

**Manual verification checklist** — the GUI is available here (`DISPLAY=:0`, Wayland), so actually
run this and record results in `docs/progress.md`: launch; open each fixture; select a word, a
phrase, a sentence, a multi-line span; selection near the bottom and right edges; "Find meaning" →
panel loads results; scroll inside the panel; click a result and use Back; Open-in-browser; close
the panel and confirm the scroll position is unchanged; select something else and search again;
airplane-mode error + retry; zoom in/out; page navigation; relaunch and confirm preferences
restored.

**State honestly in the PR** whatever was not executed — in particular Windows/macOS/iOS (no
hardware), Android (until M7), and `integration_test` (best-effort on Linux desktop).

---

## 9. Known limitations (put these in the README)

1. **An AI Overview is not guaranteed.** Google decides what to show; often there is none.
2. **You cannot sign in to Google inside the panel** — Google blocks sign-in in embedded webviews
   by design. Results are signed-out and unpersonalised.
3. **Consent screens and, rarely, a CAPTCHA may appear** in the panel, especially on shared or VPN
   IPs. They are solvable in place, like in any browser.
4. **Network required** for the panel. The reader itself works offline.
5. **Large desktop bundle** (~150–250 MB) because CEF ships Chromium; Linux uses CEF's software
   rendering path, so panel scrolling may be less smooth than a real browser.
6. **Text-based PDFs only.** Scanned pages have no text layer — show "This page has no selectable
   text" rather than failing silently. No OCR.
7. **Ubuntu is the only verified platform in the MVP.** The other four are architecturally
   supported and unverified.
8. **Unresolved policy question.** This implementation performs no scraping, parsing or automation
   — it navigates an embedded webview to a search URL in response to an explicit user click.
   Whether Google's terms permit loading Search inside a third-party application panel is
   nonetheless **not something this plan establishes**, in any distribution context: Google's terms
   are written around browsers, the research behind this plan found no provision that clearly
   permits or clearly prohibits this arrangement, and nothing here should be read as concluding
   that personal, open-source or commercial use is exempt. It is an open question the user should
   resolve — with legal advice if distribution matters to them — rather than one the
   implementation has answered. Google may also change embedded-webview behaviour at any time
   without notice.

---

## 10. Risks and mitigations

| Risk | Mitigation |
|---|---|
| **Google unusable in `webview_cef` on Ubuntu** — the single biggest risk | M0 usability spike before any application code; §2's ladder to make Google work; if it cannot be made to work, the failure is documented and escalated as an explicit product decision (Google stays the intended engine — the URL is isolated in one constant so the switch is cheap *once decided*, not automatic) |
| `webview_cef` is a community plugin carrying a central feature | Active (243 stars, Sept 2026 commits, CEF 149); features we need are documented; `desktop_webview_window` is the degraded fallback (separate window) |
| CEF build friction (C++20, first-build download) | Prerequisites installed up front; verified in M0, not discovered in M4 |
| `textSelectionPointRange` shape under-documented | Verify in M3; fall back to `charRects` + `PdfViewerController` transform |
| Panel feels cramped / results unusable at 420 px | Test in M0 with real queries; widen the panel or accept Google's responsive layout |
| Flutter/Dart unfamiliarity | Few files, flat structure, `flutter analyze` + tests as guardrails |
| Mobile touch selection differs | Deferred to M7, after Ubuntu is verified and merged |
| 30 GB disk headroom | Flutter SDK only; no extra Android images |

---

## 11. Definition of done

- `flutter analyze` clean, `dart format` clean, `flutter test` passing.
- `flutter build linux --release` succeeds.
- **M0's observations** (§2, all seven checks) and the **§5.1.1 pdfrx gate results** are written in
  `docs/progress.md` as what was observed, not as pass/fail.
- The **derived CEF dependency list** is in `DEBIAN/control` and recorded in `docs/progress.md`,
  with no unresolved `ldd` entries.
- The `.deb` **installs and runs in a clean Ubuntu 26.04 environment** with no manual dependency
  installation, launches from the app menu, and opens a PDF via "Open With".
- The §8 manual checklist passes, with results recorded in `docs/progress.md`.
- README reproduces a working app from a clean clone and states every limitation in §9.
- PR created, self-reviewed, squash-merged to `main`; `docs/progress.md` current so a fresh session
  can resume from it.
- **Nothing is reported as verified that was not actually executed** — unexercised APIs, untested
  packages and unbuilt platforms are described as such, in both the PR and the README.

---

## Immediate next step

**This session:** write `docs/implementation-plan.md` (this document) and `README.md`, and commit
them. That is its entire output — no application code, no spike.

**Next (implementation) session:** start with the **M0 feasibility spike** (§2) before writing any
application code, record the observations in `docs/progress.md`, and only then proceed to M1.
