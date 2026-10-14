# DNDReader — Windows Implementation Plan (WebView2)

> **Status:** approved 2026-10-14 and **implemented** (W1–W6, then defects D1–D7 from a real-machine
> verification). This document is the **plan of record**, kept as written; the tense below ("no Windows code
> exists", "the next action is W1") describes the day it was approved. What was actually built, decided and
> verified is in `docs/completion-report-windows.md` and `docs/windows-verification/REPORT.md`.
> `docs/implementation-plan.md` remains the source of truth for Linux and is **not** superseded by this one.
>
> **Labelling convention, used throughout and required in every report this work produces:**
> **verified** (observed in this project, with how it was observed stated), **read** (taken from
> source or documentation, not executed), **not verified** (neither). On Windows specifically,
> **nothing is verified until CI or the owner demonstrates it.** A green CI run proves the app
> compiles and its unit tests pass; it is **not** evidence that the app runs or looks right.
> Never report as executed something that was not run.

---

## 1. Context and objective

DNDReader is a Flutter PDF reader: open a PDF → select text → a **Find meaning** action appears →
Google Search results load in an embedded side panel, without leaving the app. No AI, no accounts,
no backend, no telemetry.

The Ubuntu MVP (v0.1.5) is complete and merged. The goal here is a **Windows** build with the same
**observable** behaviour: the same reading experience, the same Find-meaning interaction, the same
embedded Google Search panel, the same keyboard shortcuts, and an honestly-stated privacy posture.

**"Same behaviour" means observable behaviour — the interaction, the panel, the shortcuts and the
privacy guarantees — not the same underlying engine.** The engine does differ (see §3), and every
divergence a user could notice must be **recorded**, not absorbed silently.

**Reuse the existing code.** The Dart layer is already platform-agnostic and `SearchWebView` was
built as the platform seam for exactly this. The work is in the **webview implementation, the
native runner seams, and packaging** — not in the shared UI. Port, don't re-author.

### Repository state (verified by inspection, 2026-10-14)

| Fact | Value |
|---|---|
| Path | `<repo checkout>` |
| Remote | `https://github.com/thisisankit27/DNDReader` — **public** |
| Base commit | `main` = **`f0bc24d`** ("Merge feat/mvp-reader: Ubuntu MVP v0.1.5") |
| Integration branch for this work | **`feat/windows-port`**, cut from `f0bc24d` |
| Retained for history, do not work on | `feat/mvp-reader` = `f967768` |
| Size | 74 tracked files; `lib/` ≈ 4,350 lines; `test/` ≈ 1,700 lines; **115 tests** passing on Linux |
| Flutter | 3.47.7 / Dart 3.13.5. **The SDK is not on `PATH`** — use `export PATH=$HOME/sdk/flutter/bin:$PATH` |
| Platforms scaffolded | `linux` only (`.metadata` lists `root` and `linux`) |
| Fork dependency | `webview_cef` pinned to `thisisankit27/webview_cef` @ `0970b4447cb667dc4a512ba5350a39a253d6d273` (public repo; **zero GitHub Actions runs ever**, so its inherited `test_windows_x64.yaml` has never executed) |
| Local dev override | `pubspec_overrides.yaml` is **gitignored** and points `webview_cef` at `<local fork checkout>` (byte-identical to the pinned ref). It must not reach CI |

**Read first:** `docs/completion-report.md` (what exists and how it was evidenced),
`docs/implementation-plan.md` (the Ubuntu plan), `docs/progress.md` (~950 lines of per-milestone
evidence), `README.md`.

### The hard constraint

**This machine is Ubuntu 26.04 and Flutter cannot cross-compile Windows from Linux.** Code can be
authored here; it cannot be built, run, or seen. The agreed verification route is **GitHub Actions
`windows-latest` only**, plus the owner's interactive passes. A CI workflow is therefore a
first-class deliverable, not an afterthought.

The owner **dual-boots Windows 10 on this same machine** and will do the interactive passes. The
build must support **Windows 10 and Windows 11**. Because it is the same machine, the mouse-wheel
notch size — listed as *not verified* on Linux because it was inferred from the embedder rather
than measured — can finally be measured on real hardware (see W4).

---

## 2. Feature parity target

Match the Ubuntu app as described in `docs/completion-report.md` §2:

PDF open (picker, `Ctrl+O`, command line) · PDFium rendering · scroll/zoom/fit · selection by drag
and by double-click · the pill / `Ctrl+E` / right-click **Find meaning** · the 420–480 px search
panel with in-panel navigation, Back and "Open in browser" · the `Ctrl+T` table of contents ·
scrollbars clear of the panels · editable page field · rotate (`Ctrl+R` / `Ctrl+Shift+R`) · full
screen (`F11`, `Esc` leaves) · themes (system/light/dark) · recents · restored page/zoom/window
size · the user-selectable selection highlight colour.

Any deliberate Windows divergence must be justified and recorded, not silently introduced.

---

## 3. Decision 1 — engine: **WebView2, not CEF**

CEF was chosen for Ubuntu **because of Linux specifically**: Flutter has no official Linux webview,
`flutter_inappwebview` ships no Linux package, and WPE WebKit is absent from Ubuntu's repositories.
**None of those constraints exist on Windows**, and the evidence runs strongly against carrying CEF
over.

### 3.1 The CEF route's sandbox problem is worse than it first appears

The fork's own `HARDENING.md` says, verbatim:

> Developed and tested **on Ubuntu 26.04 only**. On Windows and macOS the sandbox setting is *not*
> changed (their sandbox needs a bootstrap/helper layout this plugin does not provide), but the
> three flag removals apply to every platform and have **not** been exercised there.

Concretely, in the pinned fork (**read**, `common/webview_plugin.cc:847-851`):

```cpp
#ifdef __linux__
	cefs.no_sandbox = sandboxDisabled;
#else
	cefs.no_sandbox = true;
#endif
```

and the fail-closed preflight at `common/webview_plugin.cc:402-414` is wrapped in `#ifdef __linux__`,
so it compiles out entirely on Windows. `CefInitialize` (`:917`) and `CefExecuteProcess` (`:837`)
both pass `nullptr` for the sandbox-info argument, and `windows/CMakeLists.txt:24-25` forces
`USE_SANDBOX OFF` with `CEF_RUNTIME_LIBRARY_FLAG "/MD"`. The Dart `sandbox:` parameter never
reaches native code at all: `WebviewSandboxMode.required` sends *nothing* on the wire, and only
`.disabled` sets a key (`lib/src/webview_manager.dart:89`).

So a CEF build on Windows today would call `initialize(sandbox: WebviewSandboxMode.required)`,
silently inherit `no_sandbox = true`, and **run unsandboxed while the UI claims it fails closed** —
a security defect and a false claim. **Silently inheriting `no_sandbox = true` was never an
option.**

Fixing it properly is not what the original brief assumed. It assumed linking `cef_sandbox.lib` and
passing a sandbox-info pointer. **That library no longer exists.**

- **Verified** — the file list of the real CEF 149 `windows64` distribution that the fork pins
  (`cef_binary_149.0.4+g2f1bfd8+chromium-149.0.7827.156_windows64.tar.bz2`, 342,397,229 bytes) was
  streamed and inspected directly. It contains `Release/libcef.lib`, `Release/bootstrap.exe` and
  `Release/bootstrapc.exe`. **`cef_sandbox.lib` is absent**, in both `Debug/` and `Release/`.
- **Read** — CEF's own sandbox-setup documentation: *"In M138 and newer `cef_sandbox` is no longer
  distributed as a static library… On Windows it has been removed in favor of bootstrap
  executables."* The replacement model: *"Build your client application as a DLL (`client.dll`)
  instead of an executable"*, implement and export `RunWinMain`, and *"rename `bootstrap[c].exe` to
  `client.exe` to have it load `client.dll` from the same directory by default."* The bootstrap
  process creates the sandbox-info object and passes it into the DLL. The pre-M138 static-link
  instructions are now labelled *"Deprecated build instructions for older versions."*

Genuine CEF sandboxing on Windows therefore means **converting the Flutter Windows runner into a
DLL** exporting `RunWinMain` and shipping a renamed `bootstrap.exe`. No Flutter application is
known to do this; it is unverifiable from Linux (CI could prove it links, never that it runs); and
it is a plausible way to consume the entire budget. CEF's only other documented option for an
exe-based application is **the sandbox disabled**.

### 3.2 WebView2 removes the problem rather than solving it

| | CEF fork | **WebView2** |
|---|---|---|
| Sandbox | DLL + bootstrap conversion, or none | Microsoft's, on by default; not ours to disable |
| Chromium patch cadence (Ubuntu plan §10, a standing risk) | **DNDReader's duty on Windows too** | **Microsoft's** — the risk disappears on Windows |
| Engine download | 326 MB per clean CI run, long MSVC C++20 build | none (NuGet SDK, a few MB) |
| Installer | ~300 MB plus a subprocess layout | ~40 MB plus a 2 MB Runtime bootstrapper |
| Upstream's three dangerous flags | removals never exercised on Windows | moot — we pass no browser arguments |
| Linux-only native hooks to reproduce | `initCEFProcesses`, `handleWndProcForCEF`, `processKeyEventForCEF` | none of them needed |

Both of the Ubuntu plan's two largest standing risks — the sandbox and the Chromium security-update
cadence — are discharged on Windows by this choice rather than carried.

### 3.3 The package: `webview_flutter_windows`, pinned to 1.3.0

**Verified for this plan (pub.dev, 2026-10-14):** version **1.3.0**, published **2026-09-29**;
publisher **`tomars.tech`** (verified publisher); repository
**`github.com/omar-hanafy/webview_flutter_windows`**; **4 likes**, **5,730 downloads/30d**,
**160/160 pub points**; SDK `^3.12.0`, Flutter `>=3.44.0` (we are on Dart 3.13.5 / Flutter 3.47.7,
so this is satisfied).

**Read** from its pub.dev page: it is a maintained fork of `jnschulze/flutter-webview-windows`,
states it is *"not affiliated with the Flutter team's `webview_flutter` packages"*, and runs the
browser off-screen, compositing it into the Flutter widget tree as a `Texture` via
`Windows.Graphics.Capture`. **That texture composition is why this package and not a native-HWND
one**: Flutter widgets must be able to paint *over* the webview, which the overlay-panel design
requires (the panel overlays the right edge; the pill and scrollbars sit above it).

Its API maps almost one-to-one onto the existing `SearchWebView` interface
(`lib/features/search/search_web_view.dart:38-59`):

| `SearchWebView` | `webview_flutter_windows` |
|---|---|
| `start(Uri)` | `initializeEnvironment(userDataPath:)` + `initialize()` + `loadUrl` |
| `loadUrl` / `goBack` / `reload` | `loadUrl` / `goBack` / `reload` |
| `widget` | the `Webview(controller)` widget |
| `onUrlChanged` | `url` stream |
| `onLoadEnd` | `loadingState` stream |
| `onLoadError(url, errorText, errorCode)` | `onLoadError` stream of `WebErrorStatus` |
| `dispose` | `dispose` |

Also available and useful: `focus()`, `releaseFocus()`, `onFocusChanged`, `hasNativeFocus`,
`clearCookies()`, `clearCache()`, `getWebViewVersion()`, `setBackgroundColor`, `setUserAgent`,
`setPopupWindowPolicy`, `setDefaultContextMenusEnabled`.

**Rejected alternatives:**

- `flutter_inappwebview_windows` — the route the brief first suggested. **Verified:** stable
  **0.6.0 is two years old** (min Dart 3.5); the only later release is `0.7.0-beta.3`, **8 months
  old**; no stable release has followed it. `incognito` support on Windows is unconfirmed and is
  not in the Windows changelog's list of implemented settings. High download volume (1.12M) comes
  from being the endorsed federated implementation, not from Windows adoption.
- `webview_windows` 0.4.0 (jnschulze) — SDK constraint `>=2.13.0 <3.0.0` **excludes Dart 3**.
  `webview_flutter_windows` is its maintained fork.
- `webview_win_floating` — a native HWND overlay; Flutter widgets cannot paint over it. Fails the
  overlay-panel requirement.

### 3.4 Risk accepted, and the supply-chain check that must precede it

4 likes and 5,730 downloads/30d is **low adoption for a package carrying the product's headline
feature**, and this is a **supply-chain decision, not only a maturity risk**:

- The name **borrows the Flutter team's federated convention** — `webview_flutter_android` and
  `webview_flutter_wkwebview` genuinely are flutter.dev-published, and this is not.
- The publisher domain **`tomars.tech` does not match the repository owner `omar-hanafy`**.
- The build **downloads `nuget.exe` at build time if it is missing**.

**Before the dependency is relied on, W1 must:**

1. Confirm the claimed lineage from `jnschulze/flutter-webview-windows` **by reading the source**,
   not by trusting the README.
2. **Read the build hook / CMake** and record exactly what URL it fetches, when, and whether it
   verifies anything (checksum, signature, pinned version).
3. **Write the finding into `docs/progress.md`** — including what could not be established.

Mitigations either way: **pin the exact version** (`webview_flutter_windows: 1.3.0`, no caret);
keep the implementation thin (~150 lines behind the existing interface) so replacing it is cheap;
and keep "Open in browser" as the universal escape hatch, as on Linux.

### 3.5 Divergences this decision creates — to be recorded, not absorbed

- A different engine: Edge/Chromium (WebView2 Runtime) instead of CEF 149 / Chromium 149.0.7827.156.
- The privacy guarantee is weaker on Windows (§4).
- `DNDREADER_GPU` is CEF-specific and is **ignored** on Windows; the measured Linux finding that
  GPU compositing costs the GPU process its seccomp filter does not transfer.
- `DNDREADER_ALLOW_UNSANDBOXED_DEV` and the `_UnsandboxedBanner` are CEF-specific and must **not**
  appear on Windows.
- `xclip` disappears — it was a Linux-X11 artefact of the CEF plugin shelling out for paste.
  WebView2 uses the native clipboard. (**Verified:** nothing in `lib/`, `test/` or `linux/runner/`
  touches the clipboard or `xclip`; it was only a `.deb` `Depends:` entry.)
- There is no AppArmor analogue and no Windows equivalent of `packaging/linux/verify-sandbox.sh`:
  the sandbox belongs to Microsoft's Runtime, not to us. Say so plainly; do not substitute a
  weaker check and present it as equivalent.

---

## 4. Decision 2 — privacy: a documented, per-platform divergence

**Privacy parity was a hard requirement, and it cannot be met exactly.** This was raised with the
owner and the divergence was **explicitly accepted** on 2026-10-14.

Ubuntu guarantees that search cookies and storage are **in memory only** and discarded on quit —
the fork gives every browser a shared `CefRequestContext` with an empty `cache_path`.

**WebView2 cannot reproduce this. Read**, from Microsoft's `ICoreWebView2Environment10`
documentation: the profile is created on disk (or opened) when the controller is created —
**whether or not InPrivate mode is on** — and although it is released from memory when the
controller closes, the files *still remain on disk*. `IsInPrivateModeEnabled` exists on
`ICoreWebView2ControllerOptions`, but **`webview_flutter_windows` does not expose it**: the only
environment knobs are `userDataPath`, `browserExePath` and `additionalArguments`.

**Therefore, on Windows:**

- A throwaway user-data folder under `%TEMP%\dndreader-search-<pid>`.
- `clearCookies()` + `clearCache()` on teardown.
- The folder deleted on quit.
- Stale folders left by an earlier crash swept at launch (**see W2.1 — this is the one piece of
  this port that can destroy user data; its constraints are mandatory**).

**Net guarantee on Windows: "discarded when you quit" — not "never written to disk."** During a
session the data is on disk, and a crash before cleanup can leave a folder behind until the next
launch sweeps it.

This must be recorded in `README.md`, `docs/implementation-plan.md` §9.11, `docs/progress.md` and
the Windows completion report — **in W6**, once the behaviour exists. The README's privacy claim
becomes explicitly per-platform.

---

## 5. Decision 3 — packaging: Inno Setup, not MSIX

**Inno Setup.** No code-signing certificate is required to install; no MSIX container to interfere
with WebView2's own processes; straightforward `.pdf` association and WebView2 Runtime
bootstrapping; and it can be signed later if the owner chooses. MSIX's container and signing
requirements buy nothing here. **One installer path only** — do not build both.

With WebView2 the bundle is small (~40 MB) rather than CEF's ~1.5 GB, so the installer's size and
shape follow directly from Decision 1.

---

## 6. Git and process discipline

- Integration branch **`feat/windows-port`**, cut from `main` (**`f0bc24d`**). Already created.
- **One short-lived branch per milestone** (`feat/w1-scaffold-ci`, `feat/w2-webview2-panel`, …),
  `--no-ff` merged back into `feat/windows-port`.
- **Push `feat/windows-port` after each milestone merge.**
- **Never commit, merge or open a PR to `main`.** The owner merges to `main`.
- Commits end with the trailer used in existing history:
  `Co-Authored-By: Claude Opus 5 <noreply@anthropic.com>`
  (a session running under a different model uses its own name in that trailer).
- Keep `docs/progress.md` current as each milestone closes, with "Verified (how)" and
  "Not verified" sections, exactly as the Linux milestones do.

---

## 7. Milestones

### W1 — scaffold, CI, and a green Windows build

**The highest-information milestone: it establishes whether the dependency set builds on Windows at
all, and everything else depends on it. Do it first and do not start W2 until CI is green.**

1. **Supply-chain check on `webview_flutter_windows` before relying on it** — the three steps in
   §3.4 (confirm lineage by reading the source; read the build hook and record the fetched URL and
   whether anything is verified; write the finding into `docs/progress.md`). If the check turns up
   something that makes the package untrustworthy, that is a **hard stop** (a dependency decision),
   not something to work around.

2. **`flutter create --platforms=windows .` — guarded.** In M1 of the Ubuntu work `flutter create`
   was noted as able to overwrite `README.md`, `.gitignore` and `analysis_options.yaml`. Run
   `git status` and `git diff` **immediately** afterwards, restore anything clobbered, and **report
   exactly what it touched**. It will also add `platform: windows` to `.metadata`, which is correct
   and should be kept.

3. **Exclude CEF from the Windows build.** `webview_cef`'s `pubspec.yaml` declares
   `windows: pluginClass: WebviewCefPluginCApi`, so a Windows build would download 326 MB of CEF,
   compile `libcef_dll_wrapper` from source, and ship CEF's binaries in the installer — **all
   unused**, because Windows takes the WebView2 path. Fix it in the fork:
   - In `<local fork checkout>` (HEAD `0970b44`, clean, byte-identical to the
     pin), create branch **`dndreader/windows`**.
   - Drop the `windows:` entry from `flutter.plugin.platforms`. Leave Linux and macOS untouched.
   - Record the change and its reason in the fork's `HARDENING.md`.
   - Push to `thisisankit27/webview_cef` (public; `gh` is authenticated as `thisisankit27` with
     `repo` and `workflow` scopes) and **pin the new SHA** in `pubspec.yaml` — never a branch name.
   - **Trade-off to record:** the fork becomes DNDReader-specific on this axis, against its stated
     "small, deletion-heavy, rebasable, upstreamable" intent. The alternative is shipping ~300 MB
     of dead CEF in every Windows installer.
   - Dart-side consequence: `WebviewManager()` would throw `MissingPluginException` on Windows if
     called — it never is, because the factory routes Windows to WebView2 (W2).

4. **`.github/workflows/windows.yml`:**
   - Job `analyze_test` on `ubuntu-latest`: `dart format --set-exit-if-changed .`,
     `flutter analyze`, `flutter test`. Fast feedback, no Windows minutes.
   - Job `build_windows` on `windows-latest`: `flutter build windows --release`, then **assert** the
     bundle contains `dndreader.exe` and `WebView2Loader.dll`, and upload the bundle as an artifact.
     (`WebView2Loader` must ship with the app — **read**, Microsoft's distribution docs. Normally
     the SDK's `.targets` handles it; the assertion catches the case where it does not.)
   - Triggers: push to `feat/windows-port` and `feat/w*` branches, pull requests, and
     `workflow_dispatch`. A `concurrency` group with `cancel-in-progress: true` so superseded runs
     stop.
   - Flutter pinned to **3.47.7** via `subosito/flutter-action` with `cache: true`.
   - **Caching — deliberately, but much smaller than the brief anticipated.** With CEF excluded
     there is no 650 MB download and no MSVC engine compile, so caching is an optimisation rather
     than a precondition. Cache the pub cache (`%LOCALAPPDATA%\Pub\Cache`) keyed on `pubspec.lock`;
     cache `build/windows` keyed on `pubspec.lock` + `windows/**` with a loose `restore-keys` prefix
     so a partial hit still gives an incremental MSBuild. **Both repositories are public, so Actions
     minutes are free** and iteration is unconstrained.
   - `pubspec_overrides.yaml` is gitignored and must not reach CI — confirm CI resolves the pinned
     fork SHA, not a local path.

5. **First-run CI risks to resolve here, in this order of likelihood:**
   - **`jni`** declares `windows: ffiPlugin: true` and arrives transitively (`jni`, `jni_flutter`,
     `jni_util` are in `pubspec.lock`; `jni` appears in the Windows plugin list of
     `.flutter-plugins-dependencies` with a native build). **This is the likeliest blocker.**
   - **`pdfium_dart`**'s build hook downloads PDFium from `bblanchon/pdfium-binaries`; its
     `OS.windows` target is `bin/pdfium.dll` (**read**, `hook/build.dart:105-109`). Note that
     `pdfium_flutter` has **no** native plugin on Windows or Linux — PDFium arrives through this
     Dart build hook on both.
   - **`webview_flutter_windows`** needs NuGet (it downloads `nuget.exe` if missing) and **C++23**;
     Flutter's `apply_standard_settings` sets `cxx_std_17`, and the plugin raises it.
   - The remaining plugins already have Windows implementations (**verified** from
     `.flutter-plugins-dependencies`): `windows_file_picker`, `path_provider_windows`,
     `shared_preferences_windows`, `url_launcher_windows`. Verify versions resolve; do not assume.

**Exit criterion:** both CI jobs green, the Windows job producing a bundle artifact, and the
supply-chain finding written into `docs/progress.md`.

### W2 — the WebView2 search panel

- **New file** `lib/features/search/search_web_view_windows.dart` —
  `Webview2SearchWebView implements SearchWebView`. The interface is **unchanged**; no shared code
  moves.
- `search_web_view.dart:28` factory currently returns `CefSearchWebView()` for
  `Platform.isLinux || Platform.isWindows || Platform.isMacOS`. Route `Platform.isWindows` to the
  new implementation; leave Linux and macOS on `CefSearchWebView`. Use a conditional import so each
  package is only referenced where it applies.
- **Fail closed, honestly.** Map `initialize()` failure — notably
  `environment_creation_failed`, which is what a **missing WebView2 Runtime** produces — to
  `SearchUnavailableException`. The existing machinery then renders it with no changes:
  `search_session.dart:121-134` sets `SearchPhase.unavailable` and never retries, and
  `search_panel.dart:126-136` shows *"Search can't run inside DNDReader here"* with **Open in
  browser**. The reused state carries an **honest Windows reason** (the Runtime is missing), not a
  borrowed Linux sandbox reason. Note the existing body text mentions "the browser's security
  sandbox" — it needs a Windows-appropriate variant.
- **Privacy** per §4: temp `userDataPath`, `clearCookies()` + `clearCache()` on teardown, delete on
  quit, sweep stale folders (constraints in W2.1 below are mandatory).
- **Pass no `additionalArguments`.** That is precisely where upstream CEF's
  `--disable-web-security`, `--allow-running-insecure-content` and the SameSite `disable-features`
  entry lived. Passing nothing is what makes those three removals moot on Windows.
- Suppress the CEF-only `_UnsandboxedBanner` (`search_panel.dart:39`) and the
  `unsandboxedDevOverrideActive` path on Windows.
- **Windows 11 — `Windows.Graphics.Capture` border.** WGC draws a **yellow border** around captured
  content unless the application opts out via `IsBorderRequired` (available on Windows 11 build
  22000+). Because this package's texture path is WGC-based, a border **may be visible around the
  search panel on Windows 11 and absent on the owner's Windows 10**. Check whether
  `webview_flutter_windows` already opts out; if it does not, determine whether it can be opted out
  of from the Dart side, and if it cannot, **record it as a known Windows 11 divergence** and add it
  to the owner's Windows 11 checklist (W6). Do not assume its absence from a Windows 10 test.
- **Tests:** extend the existing fake pattern in `test/search/fake_search_web_view.dart` — the
  webview itself is never driven in tests, as on Linux. Add unit tests for the temp-profile path
  construction and for the stale-folder sweep (W2.1).

#### W2.1 — the stale-profile sweep: mandatory constraints

**This is the one piece of this port that can destroy user data.** A sweep that deletes directories
under a path derived at runtime is a delete loop one bug away from removing the wrong tree.
Specify and enforce:

1. **Match only `dndreader-search-<digits>`** — an anchored pattern, digits only, nothing else.
2. **Resolve the path and assert it is inside the temp directory** *before any delete*. Resolve
   first, compare after; a prefix check on an unresolved string is not sufficient.
3. **Do not follow symlinks out of the temp directory.** A symlinked entry must be rejected, not
   traversed.
4. **Unit-test the rejection cases as thoroughly as the happy path** — a non-matching name, a name
   with a non-digit suffix, a path that resolves outside temp, a symlink pointing outside temp, and
   a directory that is not ours. Deletion must be refused in every one.

Pure-logic decision functions, tested directly, are strongly preferred over a single procedure that
both decides and deletes.

### W3 — native runner seams

Reproduce in `windows/runner/` what `linux/runner/my_application.cc` does by hand (~153 lines of
non-scaffold C across four blocks). **The CEF hooks — `initCEFProcesses` (`linux/runner/main.cc`),
`handleWndProcForCEF`, and the `processKeyEventForCEF` modifier passthrough
(`my_application.cc:125-148, 199-202`) — are not needed on the WebView2 route.** That whole seam,
including the brief's "`main.cpp` must call `initCEFProcesses` first in `wWinMain`" requirement,
disappears. Two blocks do carry over.

**1. The `dndreader/window` method channel.** Contract from `lib/services/window_service.dart:15-43`:

- Channel name **`dndreader/window`**, `StandardMethodCodec` (match with
  `flutter::StandardMethodCodec`; Linux uses `fl_standard_method_codec_new()`).
- Dart → native: **`setFullscreen`** with a **bare `bool`** argument (not a map), reply `void`.
  Both `MissingPluginException` and `PlatformException` are swallowed on the Dart side, so a missing
  channel degrades to full screen silently doing nothing.
- Native → Dart: **`fullscreenChanged`** with a `bool`. **This is required, not optional:**
  `_fullscreen` is *only* ever updated by this push (`window_service.dart:33-43`), so without it
  `toggleFullscreen()` always sends `true`, and `F11`, `Esc` (`reader_screen.dart:314-318`) and the
  header icon (`reader_header.dart:131-137`) all behave wrongly.
- `isFullscreen` exists in the Linux handler but **has no Dart caller anywhere** — skip it.
- Windows has **no fullscreen window state to observe**, unlike GTK's
  `GDK_WINDOW_STATE_FULLSCREEN`. Emulate: save the window style and placement, strip
  `WS_OVERLAPPEDWINDOW`, `SetWindowPos` to the monitor bounds, restore on exit — and **synthesise
  `fullscreenChanged` from the runner itself**, since no window-manager event will arrive.

**2. Window-size persistence.** Linux keeps `"W H"` in
`$XDG_CONFIG_HOME/dndreader/window-size` (`my_application.cc:21-78`), with defaults **1100×760**,
width clamped to **480–10000** and height to **360–10000**, a **skip when maximised or
fullscreen** ("a maximized or full-screen window is not the size to restore to"), a rejection
below 480×360, and a **500 ms debounce** because a drag-resize fires many events. Windows
equivalent under `%APPDATA%` (`SHGetKnownFolderPath(FOLDERID_RoamingAppData)`), `IsZoomed()` for the
maximised check, debounced on `WM_EXITSIZEMOVE` / `WM_SIZE`. Settings do **not** migrate from Linux,
which is fine for a port.

**3. Also confirm in the generated runner:**
- The window title (`"DNDReader"`) and the black view background (`my_application.cc:203-207`).
- **The command-line `.pdf` argument still reaches Dart.** `lib/main.dart:_pdfFromArgs` takes the
  first argument ending in `.pdf` that exists on disk. The Windows template forwards
  `GetCommandLineArguments()` to `DartProject::set_dart_entrypoint_arguments` — **confirm it
  survives in the generated `windows/runner/main.cpp`/`flutter_window.cpp`**, since it is what makes
  "Open With" work.

**4. Focus.** `webview_flutter_windows` offers `focus()`, `releaseFocus()`, `onFocusChanged` and
`hasNativeFocus` — better tooling than CEF gave us. Wire `releaseFocus()` when the panel closes,
alongside the existing Dart focus return (`reader_screen.dart:92-95`, `ExcludeFocus` on the hidden
panel). **The package author reports focus bouncing — blur and focus firing on every click inside
the texture. Investigate on Windows; do not assume either outcome.** Focus was already a
security-adjacent bug source in this project: the CEF plugin consumed every key while its focus node
held focus, hiding `Ctrl` from Flutter so `Ctrl`+wheel zoom "sometimes worked"
(`docs/progress.md:865-878`, completion report finding 6).

### W4 — reader ergonomics and honesty on Windows

- **Mouse wheel.** `PdfView.wheelScrollFactor = 2.0` (`lib/features/reader/pdf_view.dart:24-30`) is
  calibrated to the Linux embedder's ~53 px per notch; pdfrx's own default of 0.2 gave ~10 px, which
  read as painfully slow. Windows reports via `WHEEL_DELTA` (120) scaled by the system
  lines-per-notch setting, so the magnitude differs. Make the constant **per-platform** and
  **retune by measurement** — the owner dual-boots the same machine, so for the first time the real
  notch size can be measured rather than inferred. `arrowKeyStep = 60` is not embedder-specific.
  Note `Ctrl`+wheel zoom is entirely pdfrx-internal (gated on
  `HardwareKeyboard.instance.isControlPressed`); there is no Ctrl+wheel code in `lib/`.
- **Filename display.** `reader_menu.dart:30` and `reader_screen.dart:220-222` both use
  `path.split(Platform.pathSeparator).last`. Correct on Windows for `\`, but a path arriving with
  forward slashes would render the whole string as the "name". Use mixed-separator-safe basename
  handling.
- **Comments that become false on Windows:** `window_service.dart:5` ("channel (Linux)"),
  `pdf_picker.dart:6` ("the XDG desktop portal on Linux"), `pdf_view.dart:24` ("The Linux embedder
  reports about 53 px").
- **About dialog.** `lib/build_info.dart` exposes `kBundledChromium = 'CEF 149.0.4 (Chromium
  149.0.7827.156)'`, shown by `reader_screen.dart:301-309`. On Windows that is simply **wrong** —
  show the WebView2 Runtime version from `getWebViewVersion()` instead, plus a line stating that
  search data lives in a temporary folder deleted on quit (the in-product half of §4).

### W5 — packaging

- `packaging/windows/dndreader.iss` (Inno Setup) plus a build script that reads the version from
  `lib/build_info.dart` **the same way `packaging/linux/build-deb.sh:18` does**
  (`sed -n "s/^const String kAppVersion = '\(.*\)';/\1/p"`), so the two cannot drift. Note
  `pubspec.yaml` carries `version: 0.1.5+1` separately, and Windows uses the build-name for the
  product and file versions in the generated `Runner.rc`.
- **WebView2 Runtime handling — required, because Windows 10 is a target.** **Read**, Microsoft's
  distribution docs: the Evergreen Runtime *"will be included as part of the Windows 11 operating
  system"*, and *"the vast majority of Windows 10 devices have the WebView2 Runtime installed
  already… A small number of Windows 10 devices don't have the WebView2 Runtime installed. We
  recommend that you handle this edge case."*
  - **Detect** via the `pv (REG_SZ)` value under
    `…\Microsoft\EdgeUpdate\Clients\{F3017226-FE2A-4295-8BDF-00C3A9A7E4C5}` at **both**
    `HKEY_LOCAL_MACHINE\SOFTWARE\WOW6432Node` (per-machine) and `HKEY_CURRENT_USER\Software`
    (per-user). Absent, `null`, empty, or `0.0.0.0` all mean **not installed**.
  - **Install if missing**: bundle the ~2 MB **`MicrosoftEdgeWebview2Setup.exe`** bootstrapper and
    run `MicrosoftEdgeWebview2Setup.exe /silent /install`. Microsoft explicitly permits packaging
    the bootstrapper with an app. Elevated ⇒ per-machine; non-elevated ⇒ per-user.
- **`.pdf` association** — the counterpart of `Exec=dndreader %f` and `MimeType=application/pdf;` in
  `packaging/linux/deb/dndreader.desktop`: a ProgID with
  `shell\open\command` → `"…\dndreader.exe" "%1"`, plus `OpenWithProgids` under `.pdf`.
- **Minimum target: Windows 10 1809, x64** — required by `Windows.Graphics.Capture`, which the
  package's texture path uses. State it in the README and the installer.
- CI builds the installer and uploads it as an artifact, so the owner can install directly from a
  run rather than building anything locally.
- **No** AppArmor analogue and **no** Windows `verify-sandbox.sh`. Stated plainly (§3.5).

### W6 — documentation and handover

- `docs/progress.md`: a Windows section per milestone, with "Verified (how)" and "Not verified",
  exactly as the Linux milestones do.
- `README.md` and `docs/implementation-plan.md`: make the engine, privacy, sandbox and
  patch-cadence statements **per-platform**. On Windows, the Chromium-update duty (§10 and §9.9)
  and the AppArmor requirement (§9.10) **do not apply**; the privacy guarantee (§9.11) is
  **weaker**; `xclip` (§9.13) is **irrelevant**; §9.5's bundle size and software-rendering note is
  CEF-specific. **These edits belong here, in W6 — not earlier.** Those files describe shipped
  behaviour, and editing them before the Windows behaviour exists would be writing claims about
  software that has not been written.
- `docs/completion-report-windows.md`, in the style of `docs/completion-report.md`: brief, what was
  delivered, milestones, the engine and privacy decisions with their evidence, what was learned,
  **what is not verified**, and open items for the owner.
- An ordered **owner verification checklist** (§8.3), mirroring the Ubuntu §8 manual checklist.
- **Stop at "ready for review"** on `feat/windows-port`. The owner merges to `main`.

---

## 8. Verification

### 8.1 Here, on Linux — what can actually be run

```bash
export PATH=$HOME/sdk/flutter/bin:$PATH
dart format --set-exit-if-changed . && flutter analyze && flutter test   # 115 tests + new ones
flutter build linux --release                                            # no Linux regression
```

The whole test suite is platform-agnostic (`FakeSearchWebView`, in-memory `SettingsService`), so it
must keep passing here, and **the Linux build must keep working**: this port adds no Linux
regression. That is the limit of what this machine can establish.

### 8.2 CI — `windows-latest`

`flutter analyze`, `flutter test`, `flutter build windows --release`, the bundle assertions
(`dndreader.exe`, `WebView2Loader.dll`), the Inno Setup installer, both uploaded as artifacts.

**This proves compilation and unit tests. Nothing more.** It is not evidence that the app runs,
renders, or looks right. Never present a green run as a working app.

### 8.3 The owner, on Windows 10 (and Windows 11 if available)

Install from the CI installer artifact, then: Runtime detection on a machine that has the Runtime
and, if possible, one that does not · launch · open a fixture from `test_fixtures/` · "Open With"
from Explorer · select a word, a phrase, a sentence, a multi-line span · selection near the bottom
and right edges · **Find meaning** → the panel loads Google results · scroll inside the panel ·
click a result and use Back · Open in browser · close the panel and confirm the document's scroll
position is unchanged · `Ctrl+O`, `Ctrl+E`, `Ctrl+T`, `Ctrl+R` / `Ctrl+Shift+R`, `F11`, `Esc` ·
editable page field · rotate · themes · recents · restored page/zoom/window size · selection
colour · wheel speed and `Ctrl`+wheel zoom · **on Windows 11, whether a yellow WGC capture border
appears around the panel** · and confirm `%TEMP%\dndreader-search-*` is gone after quitting.

### 8.4 Cannot be verified by me — and will be labelled so

That the app runs or looks right at all · WebView2's sandbox actually being active · the
focus-bounce behaviour · the WGC border on Windows 11 · scroll feel · the retuned wheel-notch
constant · the installer on a machine without the Runtime · anything about Windows 11 unless the
owner has access to one · and the EEA/UK consent wall, which was never observable from this network
on Linux either.

---

## 9. Risks

| Risk | Handling |
|---|---|
| `webview_flutter_windows` is young (4 likes, 5,730 downloads/30d) and carries the headline feature; its name borrows the flutter.dev federated convention and its publisher domain does not match the repo owner | The §3.4 supply-chain check **before** relying on it; pin 1.3.0 exactly; keep the implementation ~150 lines behind the existing interface so swapping is cheap; "Open in browser" always present |
| CI cannot build at all — the `jni` Windows FFI build is the likeliest culprit | W1 exists to find out **first**, before any dependent work. Time-boxed; a genuine dead end is a hard stop and gets reported, not worked around silently |
| `flutter create` clobbers `README.md`, `.gitignore` or `analysis_options.yaml` | Guarded: diff immediately after, restore, and report exactly what it touched |
| The fork change (dropping `windows:`) makes the fork DNDReader-specific | Small, documented in `HARDENING.md`, Linux untouched; the alternative is shipping ~300 MB of dead CEF |
| The stale-profile sweep deletes the wrong tree | W2.1's constraints are mandatory and its rejection cases are unit-tested as thoroughly as the happy path |
| A green CI run read as a working app | Stated in every deliverable; the completion report separates CI evidence from owner evidence |
| WebView2 behaves visibly differently from CEF (WGC border, focus, scroll feel, consent handling) | Each divergence recorded in `docs/progress.md` and the README. Anything that changes **what the product is** stops and asks |
| A long-running app keeps an outdated Runtime — Microsoft's own security note, and it matters because the panel loads third-party content | Documented; the panel is per-launch and a restart picks up the new Runtime. `NewBrowserVersionAvailable` is noted but not wired |
| WebView2 Runtime missing on a Windows 10 machine | Installer detects and bootstraps (W5); at runtime it fails closed into the existing "Open in browser" state |

---

## 10. Hard stops — report and wait

- **Anything that changes what the product is** — a different search engine, dropping the panel, a
  dependency not in this plan, or Windows behaviour diverging visibly from Ubuntu beyond the
  divergences recorded in §3.5 and §4.
- **CI cannot be made to build at all**, after a time-boxed effort.
- **A decision that needs hardware or credentials** not available.
- **The supply-chain check (§3.4) turns up something that makes the package untrustworthy.**

The sandbox question that was the brief's original headline **is settled** (§3, §4) and is not a
stop condition any more — but if the WebView2 sandbox turns out not to be active, that changes what
the product claims about its security, and it stops.

## 11. Standing constraints (unchanged from the Ubuntu work)

No AI, no API keys, no backend, no database, no accounts, no telemetry. **No scraping or parsing of
Google result HTML, no automating Google, no aiming synthetic input at a CAPTCHA, no circumventing
webview restrictions** — the app builds a URL with the selected text percent-encoded and navigates
to it, once per explicit user action. **Never use the owner's personal PDFs** — fixtures live in
`test_fixtures/` and are generated by headless Chrome. Label every claim **verified** (and how),
**read**, or **not verified**, and never report as executed something that was not run.
