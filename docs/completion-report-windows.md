# DNDReader — completion report (Windows port, WebView2)

Written for: the owner, who will install the CI installer on Windows 10 and judge whether it works; and an
independent reviewer judging how the claims below were evidenced. Every claim is labelled **verified**
(observed, with how), **read** (from source or documentation, not run) or **not verified**.

> **Update (after this report was written).** A real-machine verification on Windows 10 found seven defects
> (quit crash and leftover browsing data, spurious errors after a challenge page, shortcuts dead after the page
> field, window taller than the work area, icon/publisher, uninstall leftovers); all are fixed and re-verified —
> see `docs/windows-verification/REPORT.md` and `ORCHESTRATOR-HANDOFF.md`. §7's "not verified" list below is
> therefore partly superseded; what is still unverified is listed in `docs/windows-owner-test.md`.
>
> **Read this first.** A green CI run proves the app **compiles**, its **unit tests pass**, and — here — that
> its installer installs and uninstalls and the process **starts and stays up for 15 s on a hosted runner**.
> It does **not** prove the app renders, that the search panel loads Google, that input or focus work, or that
> it looks right. **Nobody has seen this app on a screen.** That is the owner's pass (§7).

## 1. Brief

A Windows build with the same *observable* behaviour as the Ubuntu app (v0.1.5): the reading experience, Find
meaning, the embedded search panel, the shortcuts, and an honestly stated privacy posture. Engine and privacy
divergences are recorded, not absorbed. Source of truth: `docs/windows-implementation-plan.md`.

| Constraint | Outcome |
|---|---|
| Work on `feat/windows-port`; one branch per milestone, `--no-ff`, push after each merge | Done: 6 branches (`feat/w1-scaffold-ci` … `feat/w6-docs`), 5 merge commits before this one, pushed after each |
| Never commit, merge or open a PR to `main` | Kept. `main` untouched at `f0bc24d`; no PR |
| Keep Linux working | **Verified (run locally at the head of W6):** `dart format`, `flutter analyze` and all 149 tests (the 115 originals included) pass, and `flutter build linux --release` succeeds. The Linux app was **not launched** after the port — only built and unit-tested |
| Never use the owner's PDFs; no AI/keys/backend/telemetry; no scraping or automation | Kept. Nothing was opened except the installer's own start-up (no PDF argument) |
| Hard stops (plan §10) | **None triggered.** Supply-chain check passed; CI built on its second run; no dependency outside the plan was added |
| README and Linux plan per-platform corrections only in W6 | Done in W6 |

## 2. What was delivered

- **A Windows build that compiles in CI** on `windows-latest` (37 MB bundle; no CEF) and an **Inno Setup
  installer** (~15 MB) uploaded as a CI artifact.
- **`Webview2SearchWebView`** behind the unchanged `SearchWebView` seam, with fail-closed handling of a missing
  Runtime into the existing "Open in browser" state and Windows-specific wording.
- **The throwaway profile and its guarded stale sweep** (the one part of the port that deletes directories),
  split into a pure `decideSweep()` and a thin IO layer.
- **Runner seams in C++**: the `dndreader/window` channel with emulated full screen and the
  `fullscreenChanged` push; window-size persistence at the Linux defaults and limits; title `DNDReader`.
- **Per-platform honesty**: mouse-wheel factor, mixed-separator document names, an About dialog that names
  the WebView2 Runtime (not CEF) and says where search data lives, panel text that no longer claims "not kept
  on disk" on Windows.
- **`webview_cef` fork branch `dndreader/windows`** (`0e82566`), removing the fork's `windows:` plugin
  platform so a Windows build neither downloads nor ships CEF.
- **Docs**: README and `docs/implementation-plan.md` made per-platform; this report; a Windows section per
  milestone in `docs/progress.md`.

Size: `lib/` 5,067 lines and `test/` 2,163 lines (from ≈4,350 and ≈1,700); **149 tests** (115 + 34); about 20 commits
on the branch beyond `main`.

## 3. Milestones and CI evidence

| # | Milestone | Result | CI run(s) |
|---|---|---|---|
| W1 | Scaffold, supply-chain check, fork change, CI | Done. First build green on its first attempt; `jni` (named as the likeliest blocker) built unaided | `38513515416` (my own guard step failed), `38514280955` (green) |
| W2 | WebView2 panel, profile, sweep | Done | `38515229190` |
| W3 | Runner seams | Done after one compile fix (`windows.h` include order) | `38515990705` (red), `38516722765` (green) |
| W4 | Wheel, names, About | Done | `38517546735` |
| W5 | Installer + smoke test | Done | `38518338633` |
| W6 | Docs | Done | — |

## 4. Decisions, with evidence

**Engine: WebView2, not CEF** (plan §3). The plan's evidence stands as written (CEF 149's Windows distribution
has no `cef_sandbox.lib`; the fork sets `no_sandbox = true` off Linux). Confirmed by building: removing the
fork's Windows platform drops the bundle to 37 MB with no `libcef*` (**verified**, CI bundle assertion).

**Dependency trust** (plan §3.4) — `webview_flutter_windows` 1.3.0, checked before use:

- **Verified:** the published archive's sha256 equals `pubspec.lock`'s; its `windows/` and `lib/` are
  byte-identical to the repo's `…-v1.3.0` tag; the repo is a GitHub fork of `jnschulze/flutter-webview-windows`
  with 92 of its 151 commits by the original author and the upstream head as merge-base; licence is the
  original BSD-3.
- **Verified:** its build hook finds `nuget` on `PATH` first and otherwise downloads `nuget.exe` **v7.6.0 with a
  pinned sha256 and `TLS_VERIFY ON`**, re-checking the hash — I independently downloaded it and the hash
  matches. It then installs two NuGet packages at **pinned versions** (not content hashes).
- **Read:** no HTTP client, process-spawn or shell-execute call in the plugin's native source.
- **Not established:** I did not audit the C++ line by line; low adoption (a few stars, a young fork) is a
  maturity risk the plan already accepted; on CI the hash-pinned download branch never ran (the runner has
  Chocolatey's `nuget.exe`).

**Privacy: weaker on Windows, by the owner's acceptance** (plan §4). Search data lives in
`%TEMP%\dndreader-search-<pid>`, is cleared and deleted on quit, and a crash can leave a folder for the next
launch's sweep. The guarantee is *discarded when you quit*, **not** *never written to disk*. Stated in the
README, the Linux plan §9.11, `progress.md`, the About dialog and the consent note.

**The sweep** (plan W2.1). Name must match `^dndreader-search-[0-9]+$`, checked before anything is stat'ed;
links are refused unresolved; the entry and the temp directory are fully resolved and compared for an *exact*
direct-child match; own pid is never swept. **Verified** by 23 unit tests on Linux, including a symlink to an
outside directory that is neither followed nor removed. **Not verified on Windows:** junctions and path casing
(covered by the pure functions only) and the lock probe across two real processes.

## 5. Where I departed from or added to the plan (all visible in the code)

| Item | Why |
|---|---|
| **Run-time `Platform` check instead of a conditional import** | Dart conditional imports select on `dart.library.*`, not the OS, so they cannot separate Windows from Linux. Both packages compile everywhere; only the matching class is constructed |
| **A lock file in each profile folder + "never sweep own pid" + 60 s age rule** | Without it a second running instance's folder would be deleted from under it. pid-liveness was rejected (pid reuse; needs a process spawn or a new direct dependency) |
| `SearchWebView.releaseFocus()` added to the interface | The plan asked for `releaseFocus()` on panel close; the shared screen must not import the Windows package |
| Permission requests **denied**, DevTools **off**, popups open **in the same view** | Not in the plan. Denying is the conservative reading of "panel never needs the camera, microphone or location"; same-view popups match the CEF fork's `OnBeforePopup`; DevTools/F12 is not a feature of the panel. Revisit if any of these change what Google shows |
| `WebErrorStatus.operationCanceled` is not reported as a failure | A superseded navigation reports it; the session treats any error as "failed" |
| `AppLifecycleListener.onExitRequested` for teardown | A widget's `dispose()` is not guaranteed on quit |
| Wheel factor **1.0** on Windows, from engine source, not measurement | I cannot measure. Engine `flutter_window.cc` at this SDK revision: `lines × 100/3` px per notch (100 at the default of 3) vs Linux's 53; both aim at ≈100 px |
| Wheel factor and runner values are my derivations | See §6 |

## 6. What I learned

1. **The riskiest dependency built first time.** `jni`'s Windows FFI build and the C++23 plugin both compiled
   on the first CI attempt; the only red runs were my own mistakes (a one-line `grep` window; an include order).
   A Windows-only compile error — `knownfolders.h` before `windows.h` — is exactly what no Linux check can
   catch; CI earned its place.
2. **The plan's "downloads nuget.exe at build time" worry was weaker than stated:** it is version- and
   hash-pinned. Read the build hook, not the summary.
3. **Evidence about a hosted runner is real but narrow.** It executed the installer, started the app, and
   exercised the window-size persistence (`window-size` contained `1044 760`, the 1100-wide default clamped by a
   1024-px virtual display) — yet says nothing about rendering. I kept those two kinds of claim apart.
4. **Source beat memory.** I had two conflicting recollections of Flutter's Windows wheel multiplier (20 vs 100);
   fetching the engine file at the SDK's revision settled it before a constant was chosen.
5. **A "no live-instance" assumption hides in every "sweep stale files" feature.** The plan's sweep would have
   deleted a second window's profile; the lock file closes that.

## 7. Not verified — and the owner's ordered checklist

### Not verified (everything below is a claim I cannot make)

- That the app **renders** a PDF, scrolls, zooms, or selects text on Windows; that **Find meaning** opens the
  panel and Google loads; Back, in-panel navigation, "Open in browser".
- **Focus**: whether the package's reported blur/focus bouncing happens here; whether `Ctrl`+wheel and shortcuts
  work after the panel has been clicked, and after it closes.
- **Full screen** (`F11`/`Esc`/header icon), **window-size restore** across restarts and on a scaled display.
- **That WebView2's sandbox is active** — taken on Microsoft's word; no way to check from here. Per plan §10, if
  it is not active, that changes what the product claims and stops.
- **That `%TEMP%\dndreader-search-*` is gone after quit** — relies on `onExitRequested` firing on window close
  (**read**, not observed); otherwise it is removed by the next launch.
- **Wheel feel**, the **Windows 11 yellow capture border** (the plugin captures a Composition visual and never
  sets `IsBorderRequired`; I **read** that as no border, unconfirmed), the **bootstrapper path** on a machine
  without the Runtime, "Open with" from Explorer, per-machine install, the EEA/UK consent wall.
- `DNDREADER_GPU`, `DNDREADER_ALLOW_UNSANDBOXED_DEV` and the unsandboxed banner do not exist on Windows by
  design; that they are really inert is **read**, not observed.

### Owner verification checklist (Windows 10; repeat the marked items on Windows 11 if available)

Take the installer from the latest green run of `windows.yml` (artifact `dndreader-windows-installer`).

1. **Install.** Run `DNDReader-0.2.0-setup-x64.exe`. Note any SmartScreen prompt (the installer is unsigned) and
   whether it asked for admin. *(Installs per-user by default.)*
2. **WebView2 detection.** On this machine it should skip the Runtime install. If you can, try a machine or VM
   without the Runtime and confirm the wizard installs it (progress text mentions WebView2).
3. **Launch** from the Start menu. Title should read `DNDReader`; empty state appears.
4. **Open a fixture** from `test_fixtures/` with `Ctrl+O`. Then close and **"Open with" from Explorer** → DNDReader;
   the file should open.
5. **Select**: a word (double-click), a phrase, a sentence, a multi-line span; near the bottom and right edges.
   The pill sits under the selection.
6. **Find meaning** (pill, `Ctrl+E`, right-click). The panel opens at 420–480 px and **Google results load**.
   *(Note anything that looks like a blocked or half-rendered page.)*
7. **In the panel**: scroll with the wheel; click a result; **Back**; **Open in browser**.
8. **Close the panel** (`Esc`): the document's scroll position is unchanged, and **keyboard shortcuts work
   immediately** (this is the focus check — try `Ctrl+T`, then the arrow keys). Click in the panel, then press
   `Esc` again.
9. **Shortcuts**: `Ctrl+O`, `Ctrl+E`, `Ctrl+T`, `Ctrl+R` / `Ctrl+Shift+R`, `F11` (enters), `Esc` (leaves),
   and the header full-screen icon (it should toggle, not only enter).
10. **Page field**: type a number, Enter. **Rotate**, **themes** (system/light/dark), **recents**, selection
    colour.
11. **Wheel feel and zoom**: one notch of the wheel should move about 100 px; `Ctrl`+wheel zooms. If wheel
    speed is wrong, tell me the direction — the constant is `PdfView.wheelScrollFactorFor`.
12. **Persistence**: change the window size, set a zoom, move to a page; quit; relaunch. Page, zoom and window
    size should return. (Size is in `%APPDATA%\dndreader\window-size`.)
13. **Privacy** — a hard pass/fail, in **all three** quit paths: (a) click the title-bar X, (b) `Esc` to close
    the panel then X, (c) `CloseMainWindow`. With the panel used, a `dndreader-search-<pid>` folder should exist
    in `%TEMP%`; **after quitting it must be gone, the process must exit in about a second, and Windows'
    Application log must have no `dndreader.exe` Application Error event.** (Before the D1 fix every quit after a
    search hung ~5 s, crashed in `flutter_windows.dll`, and left the folder.) Then kill the app abruptly during a
    search, relaunch **without searching**: the old folder is removed within seconds.
14. **About** (Menu → About): shows `Microsoft Edge WebView2 Runtime <version>` and the temporary-folder line,
    and does **not** mention CEF.
15. **Windows 11 only**: is there a **yellow border** around the search panel?
16. **Offline / failure**: disconnect, run Find meaning → "Couldn't load results" with Retry and Open in browser.
17. **Uninstall** from Settings → Apps; confirm the folder and the "Open with" entry are gone.

## 8. Open items for the owner

1. Run the checklist; report the failures. The likeliest are focus, the wheel constant, and full screen.
2. **Merge to `main`** is yours (`feat/windows-port` @ the head of this branch); I did not and will not.
3. Licence: the repo still has no `LICENSE`; the installer ships the plugin's BSD-3 notice.
4. Code signing: the installer is unsigned, so SmartScreen will warn. It can be signed later.
5. Decide whether to **upstream or keep** the fork change `dndreader/windows`; the fork is now
   DNDReader-specific on that one axis (recorded in its `HARDENING.md`).
6. The `webview_flutter_windows` dependency is low-adoption; consider reviewing it further before any public
   release (§4).

## 9. How to re-verify

```bash
# Linux (this machine)
export PATH=$HOME/sdk/flutter/bin:$PATH
dart format --set-exit-if-changed . && flutter analyze && flutter test    # 149 tests
flutter build linux --release

# Windows: only GitHub Actions can build it from here
gh run list --branch feat/windows-port
```

Branch `feat/windows-port`; evidence per milestone in `docs/progress.md` ("Windows port" section).

## Addendum — Linux regression pass (2026-10-14)

A pass on the real Linux app after the D1–D4 changes found and fixed one Linux-only regression introduced by the
shared D3 session change (failed loads were turned into successful ones). Back is deliberately platform-specific
(Windows: webview history; Linux: session list + `goBack()`). Details: `docs/windows-verification/REPORT.md` §9.
