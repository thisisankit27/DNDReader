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

**Planning complete; no application code exists yet.** The implementation plan is in
[docs/implementation-plan.md](docs/implementation-plan.md), and the next step is the embedded-search
feasibility spike described in its §2.

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
| Search panel, desktop | [`webview_cef`](https://pub.dev/packages/webview_cef) (CEF), docked into the layout |
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

## Known limitations

1. **An AI Overview is not guaranteed** — Google decides what to show, and often there is none.
2. **You cannot sign in to Google inside the panel.** Google blocks sign-in in embedded webviews by
   design, so results are signed-out and unpersonalised.
3. **Consent screens, and occasionally a CAPTCHA, may appear** in the panel — more likely on shared
   or VPN connections. They can be dealt with in place, as in any browser.
4. **The panel needs a network connection.** Reading PDFs works offline.
5. **The desktop build is large** (~150–250 MB) because CEF bundles Chromium, and CEF uses a
   software rendering path on Linux, so panel scrolling may feel less smooth than a real browser.
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

## Not included

OCR · DOCX / EPUB · annotation or editing · highlight persistence · cloud storage · accounts ·
sync · collaboration · in-panel tabs or bookmarks · a general-purpose browser · AI of any kind.
