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

**Version 0.2.2: Ubuntu and Windows. No release has been published.** 0.2.2 is Linux-only: narrows
0.2.1's GNOME 50 startup-crash workaround to only apply when actually needed, and fixes the AppArmor
profile's ABI pin (`abi/5.0` → `abi/4.0`) so the sandbox installs on Ubuntu 24.04 and on CI, not just
on this machine's newer Ubuntu (see progress.md). The Windows build is unchanged from 0.2.0 and has
not been rebuilt or re-verified as part of this fix. The Ubuntu build is verified on Ubuntu 26.04 only (installed `.deb` and AppArmor profile confirmed by the owner); the Windows build is described below. What has actually been observed — and what has not — is in
[docs/progress.md](docs/progress.md); the plan is in [docs/implementation-plan.md](docs/implementation-plan.md).

| Platform | State |
|---|---|
| Ubuntu / Linux | **Built and verified** on Ubuntu 26.04 (x86-64) — see the "not verified" list in progress.md |
| Windows 10 1809+ / 11 (x64) | **Built in CI and hand-verified on one Windows 10 22H2 machine** (150 % display): install, read, select, Find meaning, search panel, full screen, quit and temp-data cleanup, uninstall — after seven defects were found and fixed. **Not verified:** Windows 11 (incl. the capture border), a machine without the WebView2 Runtime, other display scales, per-machine install. The installer is **unsigned** (Windows shows "Unknown publisher"). See [docs/windows-owner-test.md](docs/windows-owner-test.md) and [docs/windows-verification/REPORT.md](docs/windows-verification/REPORT.md) |
| Android 8.0+ (API 26+) | **Built, and hand-verified on one arm64 phone** (Moto G60, Android 12, system WebView 149) plus an x86-64 API 36 emulator for predictive back and edge-to-edge (the armeabi-v7a APK builds but has never been run): open from the picker or "Open with"/"Share", touch selection with handles, Find meaning in a bottom sheet, layered Back, full screen, rotation, restoration after the process was killed. **Not verified:** TalkBack, a Bluetooth keyboard/mouse/stylus, two-finger pinch, split screen, a missing or very old system WebView, Android 13+ on a real phone, a 16 KB-page device. The APK is for sideloading from GitHub Releases (no Play listing yet). See [docs/android-owner-test.md](docs/android-owner-test.md) and the Android sections of [docs/progress.md](docs/progress.md) |
| iOS, macOS | Architecturally supported — **not built, not tested** |

The architecture is a single Flutter codebase intended to reach other platforms. Nothing in this
README should be read as a claim that a platform other than Ubuntu has been **used**; the Windows
row says exactly how far that port has been taken.

## What it does

- Opens a PDF (file picker, `Ctrl+O`, command-line argument, or "Open With"), scrolls (wheel, keys, draggable vertical and horizontal scrollbars), zooms, shows `page / total`.
- Type a page number in the header and press Enter to jump there; rotate the document (`Ctrl+R`, `Ctrl+Shift+R`); full screen (`F11`, `Esc` leaves it).
- **Contents** (`Ctrl+T`): the document's own outline in a left-edge panel; topics expand and collapse, click a title to jump.
- Select text → **Find meaning** (or `Ctrl+E`) → Google Search results in a side panel on the right;
  `Esc` closes it and you are exactly where you were.
- Remembers theme, zoom, last document and page, recent documents and window size.
- Selection highlight colour is your choice (Menu → Selection colour): sky blue (default), yellow, orange, pink or grey — chosen from the colour-blind-safe Okabe–Ito palette rather than the theme's default.
- Light/dark/system theme, keyboard shortcuts (Menu → Keyboard shortcuts).
- **Android:** the same reader for touch. Long-press a word and drag the handles to select; **Find meaning**
  raises a draggable bottom sheet (a side panel when the window is wide, e.g. landscape); the system **Back**
  closes things one layer at a time (menu, panel history, contents, selection, full screen) before it leaves;
  documents open from the picker, from "Open with" and from "Share" in other apps. Rotate, fit-page and full
  screen are in the menu on a phone.

## How it works

| Piece | Choice |
|---|---|
| Framework | Flutter 3.47.7 / Dart 3.13.5 — one codebase for all five platforms |
| PDF rendering + text selection | [`pdfrx`](https://pub.dev/packages/pdfrx) (PDFium) |
| Search panel, Linux | a pinned, security-hardened fork of [`webview_cef`](https://pub.dev/packages/webview_cef) (CEF) — [`thisisankit27/webview_cef`](https://github.com/thisisankit27/webview_cef) (see its `HARDENING.md`) — docked into the layout |
| Search panel, Windows | Microsoft's **WebView2** via [`webview_flutter_windows`](https://pub.dev/packages/webview_flutter_windows) **1.3.0** (exact pin), composited as a texture so Flutter widgets paint over it. The Runtime, its sandbox and its security updates are Microsoft's. The CEF fork is not built or shipped on Windows |
| Search panel, Android | [`webview_flutter`](https://pub.dev/packages/webview_flutter) using the phone's own **system WebView**. Nothing browser-sized is bundled (the APK is ~25 MB, ~11.5 MB to download) and **CEF is not used on Android**. The WebView is Android's: it is updated and patched by Android/Play, not by this project. iOS would reuse the same adapter |
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
first desktop build (the pinned fork's `third/cef`). Allow roughly **6–8 GB** of free disk for the Flutter SDK, CEF and build
artifacts.

## Prerequisites (Windows)

Windows 10 1809 or later, x64. Flutter **3.47.7**, Visual Studio 2022 with the *Desktop development
with C++* workload (the Windows 10/11 SDK), and — for the installer only — Inno Setup 6.3+. The WebView2
Runtime is needed at run time (it ships with Windows 11 and most Windows 10 machines; the installer
installs it when it is missing). **A Windows build cannot be made from Linux**; CI
(`.github/workflows/windows.yml`) builds it on `windows-latest`.

```powershell
flutter pub get
flutter build windows --release        # → build\windows\x64\runner\Release (~37 MB)
bash packaging/windows/build-installer.sh   # Git Bash; → dist\DNDReader-<ver>-setup-x64.exe (~15 MB)
```

The installer is per-user by default (no admin prompt), offers DNDReader under "Open with" for
`.pdf`, and is not code-signed — Windows SmartScreen may warn. CI uploads the installer as an
artifact of each run.

## Prerequisites and build (Android)

Flutter **3.47.7**, the Android SDK (platform 36; Gradle fetches the NDK it needs), and a JDK 17+ (Android Studio's
bundled JDK 25 was used and works). `minSdk` is 26; the target is API 36.

```bash
flutter pub get
flutter build apk --release --split-per-abi --obfuscate --split-debug-info=build/symbols
# → build/app/outputs/flutter-apk/app-arm64-v8a-release.apk (about 25 MB)
```

An unsigned-by-you build is signed with the debug key and is only good for trying the app. A release APK is signed
with a keystore that is **never committed**: see [docs/android-release.md](docs/android-release.md). The first build
downloads PDFium from GitHub (via `pdfrx`).

## Run and build (Linux)

```bash
flutter pub get
flutter run -d linux                  # development; see the sandbox note below

dart format --set-exit-if-changed .   # pre-PR checks
flutter analyze
flutter test
flutter build linux --release

packaging/linux/build-deb.sh          # → dist/dndreader_<ver>-1_amd64.deb
sudo apt install ./dist/dndreader_0.2.2-1_amd64.deb
```

The `.deb` is built for the Ubuntu release it is built on (its `Depends` are derived from the
bundle's shared libraries). It installs to `/usr/lib/dndreader`, registers DNDReader for
`application/pdf`, and installs the AppArmor profile described below. It is about 330 MB
(1.5 GB installed).

### The browser sandbox needs an AppArmor profile

DNDReader requires Chromium's sandbox for the search panel. On Ubuntu 24.04+
(`kernel.apparmor_restrict_unprivileged_userns=1`) an unconfined program cannot create the user
namespace that sandbox needs, so the package installs `/etc/apparmor.d/dndreader` and loads it. **If
the sandbox cannot start, the app does not fall back to an unsandboxed browser**: the panel shows
"Search unavailable" and offers *Open in browser*.

The profile declares `abi <abi/4.0>,` — AppArmor's `userns` rule exists from abi/4.0 onward, which is
what Ubuntu ships starting with 24.04, the same release that introduced the restriction this profile
is for. A working sandbox therefore needs Ubuntu 24.04 or later (older Ubuntu doesn't need this
profile at all: the restriction it works around doesn't exist there, so the sandbox just starts
unconfined). A system with an `abi/4.0` file missing or an AppArmor build older than that will fail
to load the profile (`apparmor_parser` refuses it outright) and search will be unavailable for the
same fail-closed reason.

- Running a development build from the source tree is therefore unsandboxed-unavailable by default.
  Either install the profile for your build directory (root; read the script first):
  `sudo packaging/linux/dev/install-dev-apparmor.sh`, or, **debug builds only**, set
  `DNDREADER_ALLOW_UNSANDBOXED_DEV=1` (loudly logged; release builds ignore it).
- To check that the sandbox is really active, open the search panel and run
  `packaging/linux/verify-sandbox.sh` (no root).

## What leaves your device

- **The text you select** is sent to Google as a search query when you click "Find meaning" —
  the same thing that happens when you type it into a search box.
- **Your PDF is never uploaded.** It is opened and rendered locally. Nothing beyond the selected
  text is transmitted.
- **No telemetry, no analytics, no crash reporting.** There is no server component.
- Only your preferences and the paths of recently opened documents are stored locally. **On Android** the app also keeps
  a private copy of each document you open (up to your eight most recent plus the open one) inside its own storage;
  see "Known limitations".

Loading Google Search in the panel involves Google's own cookies, exactly as it would in a browser.
What happens to them **differs by platform**:

- **Linux:** the panel's cookies and storage are held **in memory only** and discarded when DNDReader quits.
- **Windows:** WebView2 cannot keep a profile in memory. The panel uses a throwaway folder
  `%TEMP%\dndreader-search-<pid>`; cookies and cache are cleared and the folder is **deleted when you
  quit**. The guarantee is therefore *discarded when you quit*, **not** *never written to disk*: during a
  session the data is on disk, and a crash can leave a folder behind until the next launch removes it
  (it only ever removes folders named `dndreader-search-<digits>` directly under the temp directory).

- **Android:** the system WebView has no in-memory mode, so the panel's cookies, cache and storage live in the app's
  private storage (which other apps cannot read) **during a run**. That folder is **deleted every time the app next
  starts** (a run that was killed is covered the same way), and the adapter also clears it before the first search.
  The guarantee is therefore *deleted at the next start*, **not** *never written to disk* and **not** *gone the moment
  you swipe the app away*. A Google cookie choice lasts until the app is closed and reopened.

## Known limitations

1. **An AI Overview is not guaranteed** — Google decides what to show, and often there is none.
2. **You cannot sign in to Google inside the panel.** Google blocks sign-in in embedded webviews by
   design, so results are signed-out and unpersonalised.
3. **Consent screens, and occasionally a CAPTCHA, may appear** in the panel — more likely on shared
   or VPN connections. They can be dealt with in place, as in any browser.
4. **The panel needs a network connection.** Reading PDFs works offline.
5. **The Linux build is large** (~1.5 GB installed, a ~330 MB `.deb`)
   because CEF bundles Chromium. On Linux CEF uses a **software** rendering path by default (verified), so panel
   scrolling may feel less smooth than a real browser. GPU compositing is an explicit, off-by-default opt-in
   (`DNDREADER_GPU=1`): it is smoother in a scripted-scroll test, but the GPU process then runs without its
   seccomp filter. **The Windows build is small** (37 MB bundle, ~15 MB installer) because it uses the
   system's WebView2 Runtime; `DNDREADER_GPU` does not apply there.
6. **Text-based PDFs only.** Scanned pages have no text layer and nothing to select. No OCR.
7. **What has been observed in use is limited to the platforms in the Status table, each as far as that row says**
   (Ubuntu; one Windows 10 machine; one Android phone plus an emulator). The others are untested.
8. **An unresolved policy question.** DNDReader performs no scraping, parsing or automation — it
   navigates an embedded webview to a search URL when you click. Whether Google's terms permit
   loading Search inside a third-party application panel is **not something this project has
   established**, in any distribution context. Google's terms are written around browsers, and the
   research behind this plan found no provision clearly permitting or clearly prohibiting this
   arrangement. Nothing here concludes that personal, open-source or commercial use is exempt. If
   you intend to distribute DNDReader, resolve this yourself — with legal advice if it matters to
   you. Google may also change embedded-webview behaviour at any time without notice.

9. **The embedded browser runs sandboxed, or not at all.** On Linux the Chromium sandbox is required: if it
   cannot start, the panel is disabled and results open in your system browser, and on Ubuntu 24.04 and
   later it needs an AppArmor profile that the `.deb` installs, so an **AppImage is not supported**
   there. On Windows the sandbox is WebView2's own and is not ours to switch off; DNDReader passes no
   browser arguments. If the WebView2 Runtime is missing the panel is disabled the same way. There is no
   AppArmor analogue and no `verify-sandbox.sh` equivalent on Windows, and **that the WebView2 sandbox is
   active has not been verified**.
10. **On Linux, shipping Chromium makes security updates this project's job.** DNDReader pins a specific CEF
    (Chromium) build; a bare `.deb` has **no automatic update channel**, so fixes reach you only when
    you install a newer package. The intended cadence is in plan §10 (rebuild within 14 days of a critical
    fix, 30 days otherwise); the bundled version is shown under Menu → About. The current pin is
    Chromium 149.0.7827.156 (CEF 149.0.4). **On Windows this duty does not apply:** Microsoft updates the
    Evergreen Runtime (About shows the installed version). A long-running DNDReader keeps the Runtime it
    started with; a restart picks up an update.
11. **Consent screens may reappear once per launch**, because search data is discarded on quit.
    Behaviour behind an EEA/UK consent wall is **unverified** — none appeared in testing.
12. **On Linux, `xclip` is needed to paste** into the panel (the plugin shells out to it); the `.deb` depends
    on it. Not needed on Windows.
13. **Restoring the last position restores the page and zoom**, not the scroll offset within the page.
14. **Selecting text across a page boundary, or in scanned/odd PDFs, depends on `pdfrx`/PDFium text
    extraction**; wrapped-hyphen handling is covered by fixtures, not by arbitrary documents.
15. **The licence of DNDReader itself has not been chosen yet** (no `LICENSE` file). The bundled
    components' licences ship in `/usr/share/doc/dndreader/`.

16. **Android opens a copy, not the original.** Android does not give apps durable file paths, so each document is
    copied into the app's private storage when you open it (from the picker, "Open with" or "Share") and read from there.
    **Edits to the original never appear in the copy**: open or share the file again to refresh it. This differs from
    Linux and Windows, which read the file where it is. Copies are identified by their contents, so sharing the same
    file twice does not duplicate it, and copies that leave your recents list are deleted; uninstalling removes them all.
    Files larger than 1 GB are refused.
17. **Android memory use is high while the panel's browser is alive**: about 520 MB resident (mostly GPU memory) on the test
    phone with a 240-page PDF open and the browser hidden after one search, against a stated budget of 300 MB (missed;
    see docs/progress.md). Reading without searching measured about 250–280 MB.
18. **Android asks for one permission, `INTERNET`** (to load the search panel; it is an install-time permission with no
    prompt). There is no storage permission: documents arrive through the system picker or the apps you share from.
19. **On Android the Google page keeps its colour scheme until it reloads** when you switch the app theme with the panel open, and a
    result link to a `.pdf` opens in your browser (the system WebView cannot show PDFs). Links such as `tel:`/`mailto:` go
    to the system; `intent:`, `market:` and similar links are ignored.

## Not included

OCR · DOCX / EPUB · annotation or editing · highlight persistence · cloud storage · accounts ·
sync · collaboration · in-panel tabs or bookmarks · a general-purpose browser · AI of any kind.
