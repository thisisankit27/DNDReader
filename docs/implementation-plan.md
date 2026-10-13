# DNDReader — Implementation Plan (embedded Google Search, no AI)

> **Status:** plan approved 2026-10-13; **updated 2026-10-14** after the M0 spike and the security
> investigation (both recorded in `docs/progress.md`). Implementation proceeds on `feat/mvp-reader`.
> **Milestone order (amended):** M1 → M2 → M3 (§5.1.1 gates) → **M0b hardened fork** → M4 → M5 → M6.
> Progress and observations belong in `docs/progress.md`.

## Context

**The product.** A minimal PDF reader that removes the context switch between reading and looking
something up. Open a PDF → select a word, phrase or passage → a contextual **"Find meaning"**
action appears → a side panel opens inside the reader showing **Google Search results** for that
text → read, then carry on without ever leaving the app or losing your place.

We are **not** building an AI explanation engine. Google provides the search experience and
whatever it chooses to show, which sometimes includes an AI Overview and sometimes does not. The
product promises *search inside the reader*, never *an AI answer every time*.

**Repository:** `github.com/thisisankit27/DNDReader`. `main` holds the plan and README;
MVP work lands on the integration branch `feat/mvp-reader` (milestone branches merged `--no-ff`).
Nothing is merged to `main` without the owner's explicit approval.

**What this supersedes.** Two earlier drafts of this plan are void: one built a Tauri + Anthropic
API reader, one built a Flutter + Gemini reader. Everything AI-related is **removed** — no Gemini,
no Claude, no Ollama, no API keys, no model selection, no provider abstraction, no prompts, no LLM
context extraction, no response streaming, no backend, no database, no accounts. None of that
infrastructure survives into this plan.

*History:* the first session was planning only (this document and `README.md`). M0 (the §2 spike)
and a follow-up security investigation have since been executed; their results changed §1, §3, §7,
§8, §9, §10 and §11 below.

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

- Desktop (Linux/Windows/macOS): **a pinned, security-hardened fork of `webview_cef`**
  (`github.com/thisisankit27/webview_cef`, branch `dndreader/hardened`, pinned by commit SHA —
  recorded below once M0b lands: **`<fork SHA: pending M0b>`**), based on upstream `main` at
  `bb2dbcc` (2026-09-18). CEF 149; renders into a Flutter `Texture` so web content composes with the
  Flutter UI. **M0 exercised this**: it builds on Ubuntu 26.04 and Google Search is usable in a
  420–480 px panel (`docs/progress.md`).
  **Why a fork, not `^0.6.2`:** (a) published 0.6.2 unconditionally disables web security, insecure-
  content blocking, SameSite cookie protections and the Chromium sandbox, with no opt-out in its API;
  (b) a per-application cache path (`rootCachePath`) exists only on unreleased upstream `main`;
  (c) an in-memory request context and a sandbox preflight are needed. The fork's diff is kept small
  and deletion-heavy (`HARDENING.md` in the fork) so it can be rebased and offered upstream.
- Mobile (Android/iOS): **`webview_flutter ^4.14.1`** — official and boring, which is what we want.

Both sit behind one `SearchWebView` interface (~60 lines of conditional wiring). All shared logic —
reader, selection, action, panel chrome, URL building, preferences — is written once.

**Costs accepted, stated plainly:** CEF makes the Linux/Windows/macOS bundle large (~150–250 MB,
**unmeasured for a release build**; the debug bundle was 1.8 GB); Linux uses the **software**
rendering path — *verified in M0*: `--disable-gpu --disable-gpu-compositing` are active — so panel
scrolling may be less smooth than a native browser (the feel is the owner's judgement; GPU
compositing is evaluated in a time-boxed spike after M4); CEF 149 requires a **C++20** toolchain;
and shipping Chromium makes this project responsible for Chromium security updates (§10).

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

### M0 spike — **executed 2026-10-13** (results: `docs/progress.md`)

> **Outcome:** Google results rendered and were operable at 420/450/480 px, signed out; results,
> scroll, click-through and `goBack()` worked; no consent wall or `/sorry` CAPTCHA appeared (one
> machine, one network). The seven checks below are retained as the acceptance list; do not read
> "executed" as "judged": checks 3 and 4 are the owner's call.

The spike was a throwaway Flutter app, run before any application code was written.

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
   *(M0 finding: that parameter sets CEF's `user_agent_product` — a product token — not the full
   UA string; CEF's default UA is already Chrome-149-based. The ladder was not needed.)*
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

`pdfrx ^2.6.5` · `webview_cef` (desktop; **git dependency on the hardened fork, pinned by SHA** —
see §1) · `webview_flutter ^4.14.1` (mobile) · `url_launcher ^6.3.3` · `file_picker ^13.1.0` ·
`shared_preferences ^2.5.6`
dev: `flutter_lints ^6.0.0`, `integration_test`
(All versions re-checked against pub.dev on 2026-10-14; they satisfy Flutter 3.47.7 / Dart 3.13.5.)

```yaml
# pubspec.yaml (added in M4, after the fork exists)
dependencies:
  webview_cef:
    git:
      url: https://github.com/thisisankit27/webview_cef
      ref: <40-char commit SHA>        # never a branch name
```

For local development, an untracked `pubspec_overrides.yaml` may point at a local checkout whose
`third/cef` symlinks to a single shared CEF tree (a second 3 GB copy is avoided).

**Runtime (not pub):** `xclip` — the plugin shells out to it for paste in the webview.

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
1. Drop U+00AD (soft hyphen) and U+0002 (PDFium's marker for a hyphen at a line end — it swallows
   the line break, so "well\u0002known" joins to "wellknown").
2. Repair visible wrap hyphens across a *line break* only:  (\p{L})[-\u2010]\s*\n\s*(\p{Ll}) → "$1$2"
   ("silico\u2010\nvolcano" → "silicovolcano"; "pre- and post-operative" is left alone).
3. Replace any remaining control character with a space.
4. Collapse CR/LF/tabs and runs of whitespace to single spaces; trim.
5. Reject empty/whitespace-only → noSelection state, no navigation.
6. Cap at ~300 code points on a word boundary (a search query, not a document).
7. Uri.encodeQueryComponent(query) into the single URL template constant.
```

*(Amended after §5.1.1 gate 1: the original rule `(\w)-\s+(\w)` would have turned "pre- and
post-operative" into "preand post-operative", and the observed PDFium output (U+0002, U+2010) was
not what the rule assumed. See `docs/progress.md`, M2.)*

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
- **Security-driven states.** *Search unavailable — sandbox not active:* if the Chromium sandbox
  cannot start, the embedded panel is **not created**; the user sees a short explanation and
  **Open in browser** (the app never runs the embedded browser unsandboxed in a release build).
  *Consent hint:* if the panel lands on a Google consent host, a single quiet line explains that the
  choice applies until DNDReader quits (search cookies are in memory only). Navigation policy is tied
  to the security state: sandbox active ⇒ in-panel click-through and Back; unavailable ⇒ browser only.
- **Accessibility:** semantic labels, ≥48 dp targets, WCAG AA contrast in light and dark, full
  keyboard path, nothing conveyed by colour or hover alone.

---

## 7. Milestones

**Branching.** `feat/mvp-reader` is the integration branch. Each milestone is developed on its own
short-lived branch (`feat/m1-shell`, `feat/m2-pdf-reading`, `feat/m3-selection-action`,
`feat/m0b-hardened-fork`, `feat/m4-search-panel`, `feat/m5-polish`, `feat/m6-tests-packaging`) and
merged back with `--no-ff` once its checks pass; `feat/mvp-reader` is pushed after each merge.
**Nothing is committed or merged to `main`, and no PR is opened against it, without the owner's
explicit approval.** Update `docs/progress.md` at each milestone.

**Order (amended 2026-10-14): M1 → M2 → M3 → M0b → M4 → M5 → M6.** The hardened fork is not a
dependency of the shell, the reader or the selection action, while §5.1.1 gate 3 is the last
existential unknown (a failure would put the contextual-pill interaction in question). So the native
fork work waits until the gates clear — and then lands before anything that needs a webview.

- **P0 — Planning.** *Done* (`da3813a`).
- **M0 — Feasibility spike.** *Done* (2026-10-13; `docs/progress.md`). Plus a *security
  investigation* (2026-10-13/14) that produced the M0b scope below.
- **M1 — Shell runs on Ubuntu.** `flutter create` (guarded: it can overwrite `README.md`,
  `.gitignore`, `analysis_options.yaml`), pinned deps, theme, responsive shell, header, empty state.
  `flutter run -d linux` shows a considered window.
- **M2 — Real PDF reading.** `file_picker` → `pdfrx`; scroll, zoom, page indicator, open another
  document, argv/`%f` opening. Verify word/phrase/sentence/multi-line selection on all fixtures,
  and complete **§5.1.1 gates 1 and 2** (text retrieval, selection preservation).
- **M3 — Selection → action.** Complete **§5.1.1 gate 3** (selection → screen coordinates, correct
  under scroll and zoom) **first**; only then build `PdfTextSelectionParams` wiring, the debounced
  callback, the anchored pill with edge flipping and clamping, `Ctrl+E`, `Esc`, and dismissal.
  Confirm the pill never breaks selection.
- **M0b — Hardened fork (runs after M3's gates clear; lands before M4).** Fork `webview_cef` at
  upstream `bb2dbcc`; **remove** `disable-web-security`, `allow-running-insecure-content` and the
  SameSite `disable-features` entry; **enable the sandbox** (drop both the `no-sandbox` switch and
  `cefs.no_sandbox`), **failing closed** via a native preflight (time-boxed; fall back to reading
  `/proc/self/attr/current` + `kernel.apparmor_restrict_unprivileged_userns`); **in-memory request
  context** by default; wire the existing `SetEnableGPU`; debug-only unsandboxed dev override
  (ignored in release builds). Ship an AppArmor `userns` profile (§8) and a reviewable dev install
  script (root ⇒ the owner runs it). Evidence: flags absent from the browser `cmdline`, fail-closed
  behaviour exercised, profile success-path pending the owner's `sudo`. Navigation veto is **not**
  built (deferred product decision).
- **M4 — Embedded search panel (on the hardened fork).** Docked panel, URL building,
  loading/error/retry, Back, Open-in-browser, Close restoring scroll position; sandbox-unavailable
  and consent-hint states (§6). **Then a time-boxed GPU-compositing spike** (frames/s and CPU,
  GPU off vs on, sandbox on, against a locally authored long page — not Google).
- **M5 — Finish the experience.** Persisted zoom/theme/last document/recents/window size,
  keyboard shortcuts, typography and spacing pass.
- **M6 — Tests, packaging, docs.** Full test run, `.deb` (with AppArmor profile, `xclip`, CEF
  attribution files), README rewritten to match reality. The scroll-feel judgement (M0 check 4) is
  surfaced to the owner with a release build. **Stops at "ready for review" on `feat/mvp-reader`;
  PR/merge to `main` is the owner's decision.**
- **M7 — Android** (after Ubuntu is merged). Swap in `search_web_view_mobile.dart`; verify touch
  selection, handles, magnifier, bottom sheet. The Android SDK is already installed at
  `~/Android/Sdk`.
- **Later — Windows / macOS / iOS.** Architecturally supported; each needs its own hardware and its
  own verification pass. **Do not claim any of them works until it has been built and tested.**

**Not in scope:** OCR, DOCX/EPUB, annotations, highlight persistence, accounts, sync,
collaboration, in-panel tabs or bookmarks, a general-purpose browser, AI of any kind.

---

## 8. Build, test, package (Ubuntu)

**Prerequisites** — available in the Ubuntu 26.04 repos (installed on the dev machine during M0):

```bash
sudo apt update && sudo apt install -y \
  clang cmake ninja-build pkg-config libgtk-3-dev liblzma-dev libstdc++-14-dev
```

Flutter stable **3.47.7** (Dart 3.13.5) — satisfies `pdfrx`'s ≥3.47.0 floor. `flutter doctor` must
be clean for `linux`. CEF downloads on first build (**658,704,712 bytes**, ~3.1 GB extracted; first
build 7 min in M0). **Measured disk cost in M0 ≈ 10 GB** (Flutter SDK 2.3 GB + its 1.5 GB tarball,
CEF tree 3.1 GB, debug build 2 GB, profile) on a machine with ~30 GB free — keep **one** shared CEF
tree, don't install extra Android system images, and delete the Flutter tarball after extracting.

**Launching during development.** Do not launch GTK apps from the VS Code *snap* terminal: it
inherits snap GTK/GSettings variables (the app aborts with a `GLib-GIO-ERROR … 'antialiasing'`) and the
AppArmor label `snap.code.code (complain)`, which makes the sandbox appear to work when a normal launch
would not. Use `systemd-run --user` (unconfined, the realistic case) or `env -i` with the display
variables.

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
icons, `DEBIAN/control`, `postinst`/`postrm`, `/etc/apparmor.d/dndreader` and the licence/attribution
files, then `dpkg-deb --build`. `.deb` is the only MVP format; AppImage is **deferred and, on Ubuntu
≥ 24.04, unsupported** (see "Sandbox" below).

**Sandbox (decision: AppArmor `userns` profile, no SUID helper).** The embedded browser runs with the
Chromium sandbox enabled and **fails closed** when it cannot start (§6). On Ubuntu ≥ 24.04
`kernel.apparmor_restrict_unprivileged_userns=1` denies capabilities to unprivileged user namespaces
for *unconfined* programs, so the namespace sandbox cannot start unless the application has a profile
that grants `userns` — exactly what Ubuntu ships for Chrome, Chromium, Signal, Slack, VS Code
(`/etc/apparmor.d/`). The `.deb` therefore installs:

```
# /etc/apparmor.d/dndreader — profile bound to the installed binary
abi <abi/5.0>,
include <tunables/global>

profile dndreader /usr/lib/dndreader/dndreader flags=(unconfined) {
  userns,
  @{exec_path} mr,
  include if exists <local/dndreader>
}
```

`postinst` loads it (`apparmor_parser -r`; guarded and non-fatal, because the app fails closed);
`postrm` unloads and removes it. Chromium re-execs the same binary for its helper processes, so they
inherit the profile. A SUID `chrome-sandbox` is **not** shipped: Chromium documents the SUID sandbox
as "almost but not completely removed", and a root-owned setuid helper is the wrong thing to add.
Consequences: an **AppImage cannot install a system profile** (and its FUSE mount is `nosuid`), so on
Ubuntu ≥ 24.04 it would always fail closed; distros without the restriction need no profile
[unverified here]; kernels with user namespaces disabled fail closed.

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

Put the resulting package names in `DEBIAN/control` `Depends:` — **plus `xclip`** (the plugin shells
out to it for paste; it is not a linked library, so `ldd` will not find it) — and record the derived
list in `docs/progress.md`. Ship CEF's `LICENSE.txt` and `CREDITS.html` and the fork's `LICENSE`
under `/usr/share/doc/dndreader/`.

**The `.deb` must then be tested in a clean Ubuntu environment** — not on this machine, where every
build dependency is already installed and a passing launch proves nothing. Use a fresh Ubuntu 26.04
container or VM with no Flutter, no clang, and no CEF present:

```bash
# e.g. podman/docker run -it --rm ubuntu:26.04   (plus X/Wayland socket passthrough for the GUI)
apt-get install -y ./dndreader_<ver>_amd64.deb   # must resolve deps with no manual apt installs
dndreader test_fixtures/prose.pdf                # must launch, render, select, and open the panel
```

**The sandbox must be shown to actually start, and to fail closed.** On a host or VM with the
package installed: launch, then for each `--type=renderer` process read `/proc/<pid>/status`
(`Seccomp: 2`, `NoNewPrivs: 1`) and `/proc/<pid>/ns/{user,pid,net}` (different from the browser
process), and confirm the browser `cmdline` contains none of `--no-sandbox`, `--disable-web-security`,
`--allow-running-insecure-content`. Then remove the profile (or launch an unconfined copy) and
confirm the app **fails closed**: no CEF initialisation, no renderer processes, the §6
*Search unavailable* state, and "Open in browser" works. A container shares the host's LSM, so it can
validate dependency resolution and the fail-closed path but **not** the profile's success path.

A missing-dependency failure here is a packaging bug to fix, not a note to add to the README.
If GUI passthrough into a container proves impractical, say so explicitly and test in a VM or a
fresh user account instead — but do not skip the clean-environment install check, and do not
report it as done if it was not run.

**Fixtures:** `test_fixtures/make_fixtures.sh` generates three PDFs from local HTML via
`google-chrome --headless --print-to-pdf` (verified present): book prose, a technical article with
headings, and a two-column long-paragraph layout. For a real-world technical document use
`/usr/share/doc/shared-mime-info/shared-mime-info-spec.pdf` (verified present; **19 pages**, pdfTeX — it has no hyphen wraps). **Do not use the
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
5. **Large desktop bundle** (~150–250 MB estimated; a release build has not been measured — the
   debug bundle was 1.8 GB) because CEF ships Chromium. **Linux uses CEF's software rendering path —
   verified in M0** (`--disable-gpu --disable-gpu-compositing` observed on the browser command line;
   frames reach Flutter as CPU pixel buffers), so panel scrolling may be less smooth than a real
   browser. GPU compositing is evaluated in a spike after M4; its outcome is recorded in
   `docs/progress.md`. Whether scrolling *feels* acceptable is the owner's judgement, not a measurement.
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
9. **Chromium security-update cadence is this project's responsibility** (desktop only). Pinning
   CEF in a fork means DNDReader must ship Chromium security fixes itself, indefinitely; a bare
   `.deb` has **no automatic update channel**, so fixes reach users only when they install a new
   package. See the bump policy in §10.
10. **The sandbox needs an AppArmor profile on Ubuntu ≥ 24.04** (installed by the `.deb`). If the
    sandbox cannot start, the embedded panel is disabled and results open in the system browser
    (fail closed) — the app never runs the embedded browser unsandboxed in a release build. An
    **AppImage is unsupported** on those systems. On kernels with user namespaces disabled it also
    fails closed.
11. **Search cookies and storage are in memory only** and are discarded on quit — nothing about
    searches persists on disk (a consent choice may reappear **once per launch**, where Google shows
    one). Behaviour behind an EEA/UK consent wall is **unverified**: none appeared in testing.
12. **The embedded panel is not a jail.** With the sandbox and web security on, result pages from
    third-party sites render at roughly a normal browser's posture; DNDReader does not restrict
    where in-panel navigation can go (a navigation delegate is a deferred product decision).
13. **`xclip` is needed to paste** into the webview (the plugin shells out to it).

---

## 10. Risks and mitigations

| Risk | Mitigation |
|---|---|
| **Google unusable in `webview_cef` on Ubuntu** — the single biggest risk | **M0 found it usable (one machine/network).** The M0 usability spike ran before any application code; §2's ladder to make Google work; if it cannot be made to work, the failure is documented and escalated as an explicit product decision (Google stays the intended engine — the URL is isolated in one constant so the switch is cheap *once decided*, not automatic) |
| `webview_cef` is a community plugin carrying a central feature | Active (243 stars, Sept 2026 commits, CEF 149); M0 exercised it. We now depend on a **pinned fork**, so we also own its rebase cost: keep the diff small and deletion-heavy (`HARDENING.md`), rebase on upstream at least quarterly, and offer the opt-out/`rootCachePath`-style changes upstream. `desktop_webview_window` remains the degraded fallback (separate window) |
| **Chromium security patch cadence** — standing risk | Pinning CEF 149 in a fork makes this project responsible for shipping Chromium security updates to its own users indefinitely, **on desktop only** (Android/iOS get a vendor-patched system WebView). **Bump policy:** the CEF version has one source of truth (`third/download.cmake` in the fork). Check CEF *stable-branch* builds at least monthly and on every Chrome stable security release. Target a rebuilt, released package within **14 days** of a Critical or exploited-in-the-wild fix and **30 days** otherwise; never release with a pin more than **60 days** behind the newest stable of its major. Every bump re-runs the sandbox-active and fail-closed checks (§8). With no apt repository there is no automatic delivery to users — a stated limitation, not a solved problem. The app shows its Chromium version in an About/diagnostics line. *(These intervals are proposed defaults, not measurements.)* |
| Sandbox cannot start on the user's system | Fail closed (§6): panel disabled, Open in browser. AppArmor profile installed by the `.deb`; fail-closed path tested, profile success path verified on a host/VM (§8) |
| Google consent wall behind an in-memory profile (EEA/UK) | One long-lived webview ⇒ at most once per launch; URL-only detection + hint (§6); persistence opt-in deferred but the fork keeps an optional cache path. **Unverified** — not observable on the dev network |
| CEF build friction (C++20, first-build download) | Prerequisites installed up front; **verified in M0** (7 min first build, no toolchain errors with clang 21 / cmake 4.2) |
| Disk headroom (~20 GB free at 90 %) | One shared CEF tree; delete the Flutter tarball; watch free space before release builds |
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
- **Security posture, observed not assumed:** the browser process command line contains none of
  `--no-sandbox`, `--disable-web-security`, `--allow-running-insecure-content` or the SameSite
  `disable-features` entry; renderers are sandboxed (`Seccomp: 2`, own user/pid/net namespaces); the
  **fail-closed** path is exercised; the release build ignores the dev override; no search data is
  written to disk; and the **CEF bump policy** (§10) and the pinned fork SHA are recorded.
- The **derived CEF dependency list** (plus `xclip`) is in `DEBIAN/control` and recorded in
  `docs/progress.md`, with no unresolved `ldd` entries.
- The `.deb` **installs and runs in a clean Ubuntu 26.04 environment** with no manual dependency
  installation, launches from the app menu, and opens a PDF via "Open With".
- The §8 manual checklist passes, with results recorded in `docs/progress.md`.
- README reproduces a working app from a clean clone and states every limitation in §9.
- The MVP is complete on `feat/mvp-reader`, self-reviewed, with `docs/progress.md` current so a
  fresh session can resume from it. **Merging to `main` (or opening a PR) is the owner's decision.**
- **Nothing is reported as verified that was not actually executed** — unexercised APIs, untested
  packages and unbuilt platforms are described as such, in both the PR and the README.

---

## Immediate next step

Work proceeds on `feat/mvp-reader` in the amended order **M1 → M2 → M3 → M0b → M4 → M5 → M6**
(§7). `docs/progress.md` is the running record; each milestone ends with a short report of what was
built, how it was verified, what failed and what remains unverified.
