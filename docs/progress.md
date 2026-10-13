# DNDReader — Progress

Source of truth for the plan is `docs/implementation-plan.md`. This file records what was
**observed**, not what was intended. Where something was not performed it says so.

| Milestone | Status |
|---|---|
| P0 Planning | Done (`da3813a`) |
| **M0 Feasibility spike** | **Executed 2026-10-13 — see below. Checks 1, 2, 5, 7 observed; 3 and 4 have evidence but the judgement is the user's; 6 partly observed (no interstitial appeared).** |
| M1 onward | Not started |

---

## M0 — Feasibility spike

### Headline

On this machine, `webview_cef 0.6.2` built (first build 7 min 4 s) and ran, and a real
signed-out Google Search results page rendered and was operable inside a 420 / 450 / 480 px
panel: results, scroll, click-through and `goBack()` all worked. No consent wall, `/sorry`
CAPTCHA, or sign-in redirect appeared in any run. This is a **single machine, single network, single
~10-minute session** sample — not evidence about other regions or IPs.

Not decided here, and not mine to decide: whether it *feels* good (checks 3, 4). Screenshots are
listed so the user can judge.

### Environment facts (verified)

| Item | Observed |
|---|---|
| OS | Ubuntu 26.04.1 LTS (resolute), kernel 7.0.0-38-generic, GNOME, Wayland session (XWayland on `:0`) |
| Display | 3072×1728 X pixels; Flutter reported DPR 2.0 |
| Disk `/home` | 30 GB free at start → 20 GB free after the spike (≈10 GB consumed, see "Footprint") |
| Flutter / Dart | 3.47.7 stable / Dart 3.13.5 (installed this session at `~/sdk/flutter`; neither was present) |
| Build deps at start | clang, cmake, ninja, libgtk-3-dev, liblzma-dev, libstdc++-14-dev all absent; `pkg-config` present |
| Build deps after | clang 21.1.8, cmake 4.2.3, ninja 1.13.2, GTK 3.24.52 (installed by the user via `sudo apt`; my dry run said 112 new packages) |
| `flutter doctor` (before) | Linux toolchain ✗: clang++, CMake, ninja, GTK 3 missing |
| `flutter doctor` (after) | Linux toolchain ✓. One warning: `eglinfo` not found (mesa-utils) — cosmetic |
| Android toolchain | ✓ (SDK at `~/Android/Sdk`); not used. Warns about two `adb` binaries |
| Repo at start | `main`, clean, HEAD `da3813a`, `git ls-remote origin` identical, two files — matched the handoff |

### Environment changes made outside the repository

- **Flutter SDK** extracted to `~/sdk/flutter` (tarball `~/scratch/dl/flutter_linux_3.47.7-stable.tar.xz`,
  1.58 GB, sha256 verified against Google's release manifest).
- **Analytics / telemetry:** disabled. This **initially failed to apply.**
  `flutter --disable-analytics` printed "Analytics reporting disabled." but
  `~/.dart-tool/dart-flutter-telemetry.config` still read `reporting=1` (file mtime 22:59:18, i.e. around my
  first call; I do not know the exact cause — likely the file being created/rewritten on first run).
  `dart --disable-analytics` then changed it to `reporting=0`. Verified by reading the
  file, twice, after the later `flutter` commands. Re-enable with `flutter --enable-analytics`.
- **CEF** (3.1 GB extracted) was placed inside the pub cache:
  `~/.pub-cache/hosted/pub.dev/webview_cef-0.6.2/third/cef`.
- **A CEF browser profile** was created at `~/.config/cef_user_data/` (114 MB) by the first spike
  launch (born 23:19:31). Not removed — see "Persistence".
- Spike app, build output, logs and evidence screenshots live in `~/scratch/` (outside the repo).

### Commands run (condensed)

```
sudo apt install -y clang cmake ninja-build pkg-config libgtk-3-dev liblzma-dev libstdc++-14-dev   # run by the user
flutter create --platforms=linux m0_spike && flutter pub add webview_cef      # → webview_cef 0.6.2
flutter build linux --debug            # first build: 7:03.86 wall, exit 0
flutter build linux --debug            # incremental rebuilds: 18.6 s
GDK_BACKEND=wayland|x11 env -i … ./build/linux/x64/debug/bundle/m0_spike     # clean environment, see Problems #1
```

### CEF first-build experience

| | Observed |
|---|---|
| CEF download | `cef_binary_149.0.4+g2f1bfd8+chromium-149.0.7827.156_linux64.tar.bz2` from `cef-builds.spotifycdn.com`, **658,704,712 bytes (~628 MiB)** — the plugin README says "~330 MB"; that figure is stale or for a different artifact |
| First build wall time | **7:03.86** including download and compiling `libcef_dll_wrapper` |
| Build errors / toolchain fixes | None once the apt packages were installed. No C++20 problem with clang 21 |
| Runner patching | The plugin's `modify_target.sh` edits `linux/runner/main.cc` and `my_application.cc` at CMake time. Expected, but it means the app's runner files are modified by a build step |
| Footprint | CEF tree 3.1 GB; debug bundle 1.8 GB; whole spike build dir 2.0 GB. **Release bundle size not measured** (plan §9 says ~150–250 MB — unverified) |
| Runtime footprint (debug) | 14 processes, ≈2.5 GiB summed RSS (overstates: shared pages are double-counted), ≈0 % CPU idle |
| Written into the app bundle dir | CEF created `bundle/extensions/` at runtime |

### M0 checks — what was observed

Evidence files are in `~/scratch/evidence/` (not committed; the brief limits this session's repo change
to this file). Frames were captured by the spike app itself (`RepaintBoundary.toImage`), which includes
the CEF texture; see "Capture method" for why.

**1. Results render — observed.** Query `idiopathic pulmonary fibrosis`, URL
`https://www.google.com/search?q=idiopathic+pulmonary+fibrosis`. Rendered: Google header and search
bar, tabs (AI Mode / All / Images / Videos / Shopping / Forums), AI Overview, "People also ask",
Images strip, then organic listings (nhlbi.nih.gov, pulmonaryfibrosis.org). Page title event:
`idiopathic pulmonary fibrosis - Google Search`. Frames: `01`, `04`, `12`.
Five launches in total (2× native Wayland, 3× XWayland): in all five the event log shows the Google
results URL loading and the expected page title; I have a rendered frame (or the user's screenshot) for
three of them (`01`, `12`, and the user's).

**2. Signed-out — observed.** The page shows a "Sign in" button throughout. No sign-in was attempted
and no account is present in this profile. The cookie DB holds only anonymous Google cookies
(`AEC`, `NID`, `SNID`, `SEARCH_SAMESITE`, `__Secure-STRP`, `DV`).

**3. Readability at panel width — evidence, judgement left to the user.** Google served a
single-column, phone-style layout at every width, with a vertical scrollbar and no horizontal
scrolling of the page body. The tab row (`All / Images / Videos / Shopping / Forums`) is cut off at the
right edge in some frames and is a horizontally scrollable strip ("Forum" is clipped at 450 px in `01`
but fully visible in `12`, so Google's layout varies run to run). Text reflows at each
width. Frames: `07_panel_420`, `01_initial_450px`, `08_panel_480`. The panel was 420 / 450 / 480
*logical* px at DPR 2.0 (= 840 / 900 / 960 physical px).

**4. Scrolling and software rendering — scrolling works; feel is NOT assessed.** A pointer-scroll
event with delta 500 moved the page from the AI Overview to People-also-ask and the first organic
results (frame `04`); Google's search bar stayed pinned. I did **not** measure frame rate or latency
and cannot judge smoothness from still frames. The user should scroll the window by hand.
README states Linux uses the software path; I did not verify which path ran.

**5. Navigation — observed.**
- Click on first organic result → navigated *in the same panel* to
  `https://www.nhlbi.nih.gov/health/idiopathic-pulmonary-fibrosis`; page rendered at 450 px
  (frame `05`).
- `goBack()` → returned to the Google results with the **scroll position preserved** and the
  visited link recoloured (frame `06`).
- New windows: tested **only against a local `data:` page I control**, not Google. A `target="_blank"`
  link navigated in-panel to `example.com`; `window.open()` navigated in-panel to `example.org`; no
  additional top-level window appeared (frames `10`, `11`). Matches the plugin source
  (`OnBeforePopup` → `loadUrl` in the same browser; popups are always redirected).
  Consequence: any link a result page opens "in a new tab" replaces the panel content.

**6. Consent / `/sorry` — partly observed.**
- **No consent interstitial appeared** and **no `/sorry/index` CAPTCHA appeared** in ~6 Google
  navigations over ~10 minutes (grep of all logs for `google.com/sorry`, `consent.google`, `accounts.google`
  found nothing). Therefore I could not test "is the consent solvable in place" or "does accepting persist"
  — there was nothing to accept.
- Persistence *mechanism* was observed: the profile is on disk (see below) and a restart reused it.
- No synthetic input was aimed at any CAPTCHA (none appeared).

**7. AI Overview — present in every run for which I have a frame** (the user's screenshot, `01`,
`12`; reference only). Its wording differed between runs. Google also painted a blue highlight over part
of the overview text in those frames; I did not interact with it.

### Experiments from plan §2 not run

The §2 ladder (desktop-Chrome UA, `&igu=1`) exists to make Google work if it resists. It did not
resist, so I **deliberately did not run either**. The spike app has a "Search +igu=1" button that was
never pressed. Related finding: `WebviewManager().initialize(userAgent:)` sets CEF's
`user_agent_product` (a product *token*), not the full UA string, so ladder step 1 as written in
the plan is not what that parameter does. CEF's default UA is already Chrome-149-based.

### Findings beyond the seven checks

1. **Persistent profile at `~/.config/cef_user_data/`** (114 MB after a few minutes) — contradicting my
   prior reading of the source, which predicted an in-memory profile. Contains `Default/Cookies`,
   Local Storage, Preferences, and `SingletonLock/SingletonCookie/SingletonSocket`. The plugin exposes no
   way to set `root_cache_path` (CEF logs: "Please customize CefSettings.root_cache_path … default may
   lead to unintended process singleton behavior"). Implications for the product: (a) it is a fixed,
   shared path, so any other CEF-default app on the machine shares it; (b) a second app instance will
   contend for the singleton lock — not tested; (c) it accumulates third-party cookies from pages the
   user follows (this session: `nih.gov`, `youtube.com`, `122.2o7.net`, Google `NID`/`SNID` expiring 2027).
   Changing it needs a plugin patch/fork.
2. **The plugin forces `--disable-web-security`, `--allow-running-insecure-content` and `--no-sandbox`**
   (`common/webview_app.cc`, `common/webview_plugin.cc`) for all loaded content. Every result link
   loads arbitrary third-party sites under those settings. This is a security-posture decision for the
   user, not something I changed or worked around.
3. **`'webview_cef' channel sent a message from native to Flutter on a non-platform thread`** —
   Flutter engine error logged once per run (5/5 runs). No visible effect observed; may become a
   crash risk on future Flutter versions.
4. **Tooltip mispositioned** — from the user's screenshot of an earlier run: a CEF tooltip
   ("Go to Google Home") appeared over the query field at the left instead of near the cursor over the
   Google logo. Reported by the user's screenshot; I did not observe it in my own frames, but those are
   Flutter-composited captures and may not show tooltip overlays, so it is **not reproduced**, not ruled
   out. Cosmetic.
5. **`GDK_BACKEND=x11` was not needed.** The webview rendered and loaded identically under native
   Wayland (frame `12`). I used XWayland only while trying to capture the window externally.
6. **Page content is non-deterministic** (AI Overview text varies between loads), so any later
   automated test must not assert on result content.

### Problems and blockers

1. **Launching from the VS Code snap terminal crashes any GTK3 app.** Run from this shell, the spike
   aborted at startup (`GLib-GIO-ERROR … Settings schema 'org.gnome.settings-daemon.plugins.xsettings'
   does not contain a key named 'antialiasing'`, exit 134). A plain Python GTK3 window did the same, so it
   is not `webview_cef`. Cause: the shell inherits VS Code's snap environment
   (`GSETTINGS_SCHEMA_DIR`, `GTK_PATH`, `GTK_EXE_PREFIX`, `GIO_MODULE_DIR`, `XDG_DATA_DIRS`, …).
   With a clean environment (`env -i` + HOME, DISPLAY, WAYLAND_DISPLAY, XDG_RUNTIME_DIR,
   DBUS_SESSION_BUS_ADDRESS, XAUTHORITY) both Wayland and X11 work. My first reading ("system-level
   GTK/gsd mismatch") was wrong and was corrected by checking. **Implication:** `flutter run` from the
   VS Code integrated terminal will likely fail for the same reason; use a normal terminal for M1+.
2. **OS-level synthetic input did not work.** XTest events under XWayland did not reach the app
   (injected pointer to (484, 356) was reported by X at (920, 758), under a different top-level window).
   `ydotool`/`xdotool` are not installed and uinput/portal paths need root or a consent prompt, which I did
   not pursue. Instead the spike injected `PointerEvent`s *inside* Flutter (`GestureBinding`), which
   exercises `webview_cef`'s Flutter→CEF forwarding but **not** the GTK→Flutter-engine input hop.
   That hop is untested by me; the user's manual interaction covers it.
3. **External window capture failed.** `XGetImage` on the GL window returned a partly black frame; the
   user's own screenshot showed the window painted correctly, so this was a capture artifact, not an
   app defect. Hence the in-app capture method.
4. **Debug-only capture race:** `toImage` occasionally threw `!debugNeedsPaint` and a stale frame was
   kept; I re-captured. One such stale pair is why a frame for the 480 px step was retaken.

### Capture method (for honesty about the evidence)

Frames are Flutter-composited output from `RepaintBoundary.toImage(pixelRatio: 1.0)`, saved every 4 s.
They reflect what Flutter drew, not what the compositor showed. The user's own screenshot of the
running window (earlier run) corroborates the display output for check 1/2/7.

### Not performed

- Release build (`flutter build linux --release`) and release bundle size.
- `.deb` packaging, dependency derivation, clean-container run.
- Anything in M1–M7, and the §5.1.1 pdfrx gates.
- The §2 UA and `igu=1` experiments (not needed — see above).
- Frame-rate / latency measurement for scrolling.
- A run with a different network, region, or VPN; consent-wall behaviour is therefore **unobserved**, not "passed".
- Two simultaneous app instances / singleton behaviour.
- Verifying whether CEF used its software or GPU path.

### Recommendation

**Proceed to M1 — conditional on the user's own judgement of checks 3 and 4** (screenshots
`~/scratch/evidence/01`, `07`, `08`, and hand-scrolling the window). Google Search is usable in
`webview_cef` on this machine; the plan's §2 stop condition was not triggered and no engine change is
proposed.

Decisions that are the user's, surfaced rather than made:
1. Acceptance of the plugin's forced `--disable-web-security` / `--no-sandbox` flags (Finding 2),
   and whether to patch/fork for an app-specific `root_cache_path` (Finding 1).
2. The open policy question in plan §9.8 is unchanged by this spike.
3. Consent/CAPTCHA remain unobserved; the plan's stated handling (user solves it in the panel) is
   still an untested assumption.

### Next step

Start M1 (`flutter create` in the repo, pinned deps, shell). Run the app from a normal terminal, not
the VS Code snap terminal. Keep `flutter analyze`/`dart format` on from the first commit.
