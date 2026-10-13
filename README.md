# DNDReader

A minimal PDF reader that removes the context switch between reading and looking something up.

Select a word, phrase or passage → a **"Find meaning"** action appears → a side panel opens
**inside the reader** with Google Search results for that text. Read it, close the panel, carry on
from exactly where you were.

No AI engine of our own. No API keys. No accounts. No backend.

> **DNDReader does not promise an AI answer.** The panel shows Google Search results. Google
> decides what to display, and that sometimes includes an AI Overview and often does not.

---

## Status

**In development; no released app.** The embedded-search feasibility spike (M0) and a security
investigation are done, and implementation is under way on the `feat/mvp-reader` branch. The plan is
in [docs/implementation-plan.md](docs/implementation-plan.md); what has actually been observed is in
[docs/progress.md](docs/progress.md). Ubuntu is the only target of the first MVP.

| Platform | State |
|---|---|
| Ubuntu / Linux | Target of the first MVP — **not yet built** |
| Android | Architecturally supported — **not built, not tested** |
| iOS, Windows, macOS | Architecturally supported — **not built, not tested** |

The architecture is a single Flutter codebase intended to reach all five platforms. Nothing in this
README should be read as a claim that a platform works until it has actually been built and
verified on that platform.

## How it will work

| Piece | Choice |
|---|---|
| Framework | Flutter 3.47.7 / Dart 3.13.5 — one codebase for all five platforms |
| PDF rendering + text selection | [`pdfrx`](https://pub.dev/packages/pdfrx) (PDFium) |
| Search panel, desktop | a pinned, security-hardened fork of [`webview_cef`](https://pub.dev/packages/webview_cef) (CEF) — [`thisisankit27/webview_cef`](https://github.com/thisisankit27/webview_cef) @ `fe58efa` (see its `HARDENING.md`) — docked into the layout |
| Search panel, mobile | [`webview_flutter`](https://pub.dev/packages/webview_flutter) |
| Preferences | `shared_preferences` |

The search panel is an ordinary embedded webview. The selected text is percent-encoded into a
search URL and navigated to, in response to an explicit click. **Result HTML is never parsed,
scraped or automated.**

Full reasoning — including the frameworks and webview plugins that were evaluated and rejected, and
why — is in [docs/implementation-plan.md](docs/implementation-plan.md).

## Prerequisites (Ubuntu)

```bash
sudo apt update && sudo apt install -y \
  clang cmake ninja-build pkg-config libgtk-3-dev liblzma-dev libstdc++-14-dev
```

Flutter **3.47.7** or newer (`pdfrx` requires ≥ 3.47.0). CEF is downloaded automatically on the
first desktop build. Allow roughly **6–8 GB** of free disk for the Flutter SDK, CEF and build
artifacts.

## Run and build

These commands describe the intended workflow; they will work once the application exists.

```bash
flutter pub get
flutter run -d linux                  # development

dart format --set-exit-if-changed .   # pre-PR checks
flutter analyze
flutter test
flutter build linux --release

bash packaging/linux/build-deb.sh     # → build/dndreader_<ver>_amd64.deb
sudo apt-get install -y ./build/dndreader_<ver>_amd64.deb
```

Installing the `.deb` registers DNDReader for `application/pdf`, so PDFs can be opened with it from
the file manager, or from a terminal with `dndreader path/to/file.pdf`.

## What leaves your device

- **The text you select** is sent to Google as a search query when you click "Find meaning" —
  the same thing that happens when you type it into a search box.
- **Your PDF is never uploaded.** It is opened and rendered locally. Nothing beyond the selected
  text is transmitted.
- **No telemetry, no analytics, no crash reporting.** There is no server component.
- Only your preferences and the paths of recently opened documents are stored locally.

Loading Google Search in the panel involves Google's own cookies, exactly as it would in a browser.
The panel's cookies and storage are held **in memory only** and discarded when DNDReader quits.

## Known limitations

1. **An AI Overview is not guaranteed** — Google decides what to show, and often there is none.
2. **You cannot sign in to Google inside the panel.** Google blocks sign-in in embedded webviews by
   design, so results are signed-out and unpersonalised.
3. **Consent screens, and occasionally a CAPTCHA, may appear** in the panel — more likely on shared
   or VPN connections. They can be dealt with in place, as in any browser.
4. **The panel needs a network connection.** Reading PDFs works offline.
5. **The desktop build is large** (~150–250 MB estimated) because CEF bundles Chromium. On Linux CEF
   uses a **software** rendering path (verified), so panel scrolling may feel less smooth than a real
   browser; GPU compositing is still being evaluated.
6. **Text-based PDFs only.** Scanned pages have no text layer and nothing to select. No OCR.
7. **Ubuntu is the only platform the MVP will verify.** The other four are untested.
8. **An unresolved policy question.** DNDReader performs no scraping, parsing or automation — it
   navigates an embedded webview to a search URL when you click. Whether Google's terms permit
   loading Search inside a third-party application panel is **not something this project has
   established**, in any distribution context. Google's terms are written around browsers, and the
   research behind this plan found no provision clearly permitting or clearly prohibiting this
   arrangement. Nothing here concludes that personal, open-source or commercial use is exempt. If
   you intend to distribute DNDReader, resolve this yourself — with legal advice if it matters to
   you. Google may also change embedded-webview behaviour at any time without notice.

9. **The embedded browser runs sandboxed, or not at all.** The Chromium sandbox is required. If it
   cannot start, the panel is disabled and results open in your system browser. On Ubuntu 24.04 and
   later it needs an AppArmor profile that the `.deb` installs, so an **AppImage is not supported**
   there.
10. **Shipping Chromium makes security updates this project's job.** DNDReader pins a specific CEF
    (Chromium) build; a bare `.deb` has **no automatic update channel**, so fixes reach you only when
    you install a newer package.
11. **Consent screens may reappear once per launch**, because search cookies are not persisted.
    Behaviour behind an EEA/UK consent wall is **unverified** — none appeared in testing.
12. **`xclip` is needed to paste** into the panel (the plugin shells out to it).

## Not included

OCR · DOCX / EPUB · annotation or editing · highlight persistence · cloud storage · accounts ·
sync · collaboration · in-panel tabs or bookmarks · a general-purpose browser · AI of any kind.
