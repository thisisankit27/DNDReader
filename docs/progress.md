# DNDReader — Progress

Source of truth for the plan is `docs/implementation-plan.md`. This file records what was
**observed**, not what was intended. Where something was not performed it says so.

| Milestone | Status |
|---|---|
| P0 Planning | Done (`da3813a`) |
| M0 Feasibility spike | **Done 2026-10-13** — see below. Checks 1, 2, 5, 7 observed; 3 and 4 have evidence but the judgement is the owner's; 6 partly observed (no interstitial appeared). |
| Security investigation | **Done 2026-10-13/14** — see "Security investigation" below. Decisions logged. |
| M1 Shell | **Done 2026-10-14** — see "M1" below |
| M2 PDF reading (+ §5.1.1 gates 1–2) | **Done 2026-10-14** — gates 1 and 2 hold; see "M2" below |
| M3 Selection → action (+ gate 3) | **Done 2026-10-14** — gate 3 holds; see "M3" below |
| M0b Hardened fork | **Built and verified except the profile success path (needs the owner's `sudo`)** — see "M0b" below |
| M4 Embedded search panel (+ GPU spike) | **Done 2026-10-14** — see "M4" below |
| M5 Polish (+ table of contents) | **Done 2026-10-14** — see "M5" below |
| M6 Tests, packaging, docs | Pending |

**Order (amended 2026-10-14): M1 → M2 → M3 → M0b → M4 → M5 → M6.** The hardened fork is not a
dependency of the shell, reader or selection action, while §5.1.1 gate 3 is the last existential
unknown; the native-fork effort waits until the gates clear.

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
README states Linux uses the software path. *(Superseded: verified during the security investigation — the browser command line carries `--disable-gpu --disable-gpu-compositing`, so the software path is in use; see below.)*

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

1. **Persistent profile at `~/.config/cef_user_data/`** *(0.6.2 only: upstream `main` can relocate it — see "Security investigation")* (114 MB after a few minutes) — contradicting my
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
- Verifying whether CEF used its software or GPU path. *(Done later — verified software; see "Security investigation".)*

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

---

## Security investigation (2026-10-13/14)

Question: the plugin ships Chromium with protections off — what should DNDReader do before M1?
**[V]** = read from source/docs or observed this session; **[H]** = hypothesis, not yet tested.
All experiments ran in `~/scratch` against a patched *copy* of upstream `main`; the repository and
`~/.pub-cache` were not modified.

### What the plugin does
- **[V]** `common/webview_app.cc` (`OnBeforeCommandLineProcessing`, browser process, unconditional, no
  Dart opt-out): `disable-web-security` (l.116), `allow-running-insecure-content` (l.117),
  `no-sandbox` (l.120), `disable-features=SameSiteByDefaultCookies,CookiesWithoutSameSiteMustBeSecure`
  (l.139–153, in a block commented `//Support cross domain requests`).
- **[V]** The sandbox is disabled in a **second** place: `cefs.no_sandbox = true`
  (`common/webview_plugin.cc:701`). The `no-sandbox` switch was misspelled `no-sanbox` until June 2026,
  so `CefSettings.no_sandbox` was the only effective disable for years.
- **[V]** Conditional on a non-empty filter domain, hence inactive: `ignore-certificate-errors`,
  `unsafely-treat-insecure-origin-as-secure`. Also forced: `--process-per-site
  --renderer-process-limit=8`, `--autoplay-policy=no-user-gesture-required`.
- **[V]** Rationale: none documented. The flags arrived in a squash commit (#118, 2024-05-10) whose
  message does not mention them. The maintainer's own comment (issue #110): the setting "can ignore all
  browser security settings, but be careful to only load pages that you fully trust … another way which
  more securely is set white list, but we have not finish the api yet". README (eLinux section): the
  sandbox is disabled "to avoid SUID permission issues common on embedded filesystems". These are
  convenience defaults for integrators loading their own content, not requirements of offscreen rendering.
- **[V]** The plugin's CMake has `SET_LINUX_SUID_PERMISSIONS(...)` **commented out**
  (`linux/CMakeLists.txt:116`); CEF's own samples run `chown root:root && chmod 4755` on
  `chrome-sandbox`. The helper setup was never wired up.

### Versions
- **[V]** pub.dev latest is 0.6.2 (2026-08-25) with **no** root-cache-path option and no flag opt-out.
- **[V]** Upstream `main` `bb2dbcc` (2026-09-18, PR #224) adds `initialize(rootCachePath: …)`. Its
  `webview_app.cc` is byte-identical to 0.6.2 — **main still forces every flag**. Same CEF
  (149.0.4+g2f1bfd8). Tested: profile lands at the custom path; default dir untouched.

### Sandbox behaviour (the decisive question)
| Launch context | Observed |
|---|---|
| From the VS Code snap shell (AppArmor label `snap.code.code (complain)`), sandbox on | **[V]** Works; Google renders. Renderers: seccomp-BPF (`Seccomp: 2`), `NoNewPrivs`, own user/pid/net namespaces. The 0644 `chrome-sandbox` was not used. ⇒ the sandbox is **compatible with offscreen rendering**. |
| **Unconfined** (`systemd-run --user`), sandbox on | **[V]** Aborts at startup (SIGTRAP, ~2 s): `FATAL setuid_sandbox_host.cc:166 The SUID sandbox helper binary was found, but is not configured correctly … lib/chrome-sandbox is owned by root and has mode 4755`. |
- **[V]** `kernel.apparmor_restrict_unprivileged_userns = 1`, `…_unconfined = 1`; Ubuntu's
  `unprivileged_userns` profile does `audit deny capability`; Ubuntu ships `userns` profiles for
  Chrome/Chromium/Signal/Slack/VS Code (`/etc/apparmor.d/`). Syntax of the candidate profile produced no
  diagnostics from `apparmor_parser -Q -K` (weak: the pipeline hid the exit status).
- **[H]** The restriction is why the namespace route fails when unconfined.
- **[V]** Chromium's own docs: the SUID sandbox is "almost but not completely removed… page is mostly
  out-of-date".
- **Not tested:** the SUID route and the AppArmor-profile success path (both need root).

### Flag removal (one query, one machine)
- **[V]** Removing web-security + insecure-content; removing the SameSite entry; removing all three
  (sandbox still off): Google results rendered identically in each. Cookies' SameSite behaviour under
  the changed defaults was not examined beyond page load.

### Navigation veto prototype (deferred product decision — not built)
- **[V]** No navigation callback exists in the Dart API; `WebviewHandler` implements no
  `CefRequestHandler`, so a veto needs a native patch. CEF 149's `OnBeforeBrowse` can cancel before commit.
- **[V]** Observed with a logging prototype: a result click is **two hops** — `google.com/goto?url=…`
  (main frame, allowed) then a **redirect** (`redirect=1`) to the external site. `target=_blank` /
  `window.open` reach the same hook via `OnBeforePopup` → `loadUrl`. **Sub-frames** also hit the hook (a
  naive allow-list vetoed Google's own `ep2.adtrafficquality.google` iframe), so any veto must be
  main-frame-only. User-gesture information is lost on popups.

### Profile and persistence
- **[V]** `~/.config/cef_user_data` (114 MB): mostly installation data (component cache, Widevine,
  TTS/suggestion models); per-profile data under `Default/` (Cookies, Local Storage, Session Storage,
  History, IndexedDB, …) plus `Singleton*` lock files. Cookie hosts seen: google.com, youtube.com,
  nih.gov, nhlbi.nih.gov, 122.2o7.net.
- **[V]** The plugin offers per-cookie `deleteCookie(domain,key)` only — no clear-all, no cache clear.
- **[V]** CEF's header says an empty `cache_path` means in-memory "incognito" mode, yet this build
  persisted anyway. A request context created with an empty `cache_path` persisted **0 cookies, no Local
  Storage origins, no Session Storage** while Google loaded normally; the control persisted 5 cookies.
  **[H]** holds across restarts and CEF versions.
- Installation-specific data (≈2.3 MB, 38 entries) still lands in `root_cache_path`.

### Rendering path
- **[V]** `WEBVIEW_CEF_GPU_TEXTURE` is defined only on Windows/macOS; Linux uses
  `FlPixelBufferTexture` (CPU buffer) and the command line carries `--disable-gpu
  --disable-gpu-compositing`. `SetEnableGPU()` exists with **no caller**. CEF 149 exposes
  `OnAcceleratedPaint` (dmabuf planes) on Linux, but consuming it needs a custom `FlTextureGL` +
  EGLImage import in Flutter's Linux embedder — out of scope.
- **[V]** `xclip` is invoked via `system()` for paste.

### Decisions (owner, 2026-10-14)
1. **B is the security fix; A (navigation veto) is a deferred product choice.** Once the sandbox and
   web security are on, third-party pages sit at roughly a normal browser's posture.
2. **Pinned public fork** `thisisankit27/webview_cef` at upstream `bb2dbcc`; remove the three
   convenience flags first; in-memory context by default; sandbox on and **fail closed**.
3. **AppArmor `userns` profile, not SUID** (idiomatic on Ubuntu 26.04, what Chrome ships). Consequence:
   AppImage unsupported on Ubuntu ≥ 24.04.
4. **Navigation policy follows the security state:** sandbox active ⇒ in-panel click-through; unavailable
   ⇒ "Open in browser".
5. **Consent:** one long-lived webview + shared request context ⇒ consent at most once per launch;
   URL-only detection + hint; persistence opt-in deferred (fork keeps an optional cache path). Not
   observable on this network ⇒ **unverified**.
6. **GPU:** time-boxed spike after M4 (frames/s + CPU, GPU off vs on, sandbox on, local page); scroll
   *feel* remains the owner's judgement.
7. **Resequenced:** M1 → M2 → M3 → **M0b** → M4 → M5 → M6.

### Environment notes (learned the hard way)
- Launching from the VS Code *snap* terminal inherits snap GTK/GSettings variables (GTK apps abort:
  `GLib-GIO-ERROR … 'antialiasing'`) **and** the `snap.code.code (complain)` AppArmor label, which makes a
  sandbox test pass when a normal launch would not. Use `systemd-run --user` (unconfined) or `env -i`.
- `pkill -f` matches the invoking shell; use `pkill -x`.
- XTest under XWayland does not reach the app; external window capture of a GL window is unreliable.
  The spike used in-app frame capture and in-Flutter pointer injection.

### Still unverified
SUID route (not shipped); AppArmor success path (needs the owner's `sudo`); in-memory context across
restarts; EEA/UK consent behaviour; flag removal beyond one query/one machine; GPU benefit; probe/CEF
agreement (to be tested in M0b); Chromium cadence is policy, not measurement.

---

## M1 — Shell runs on Ubuntu (2026-10-14, branch `feat/m1-shell`)

**Built:** Flutter project at the repo root (`flutter create --platforms=linux`, app id
`io.github.thisisankit27.dndreader`); pinned deps `pdfrx ^2.6.5`, `file_picker ^13.1.0`,
`shared_preferences ^2.5.6`, `url_launcher ^6.3.3`, dev `flutter_lints ^6.0.0` + `integration_test`
(`webview_cef` deliberately absent — it joins at M4 via the fork); Material 3 theme from one seed,
light/dark following the system; one-row header (title, page n / N, zoom −/+, Open) that collapses to an
icon button under 560 px; empty state; `Ctrl+O` binding (inert until M2); `lib/services/search_url.dart`
implemented in full with tests; a debug-only frame-capture hook (`lib/dev/dev_capture.dart`, inert in
release builds and without `--dart-define=DNDREADER_CAPTURE_DIR`); window title "DNDReader", 1100×760.

**`flutter create` guard:** README.md, `docs/implementation-plan.md` and `docs/progress.md` were
hash-checked before and after — **none were touched**. It only added new files: `.gitignore`,
`.metadata`, `analysis_options.yaml`, `pubspec.yaml`, `lib/`, `linux/`, `test/` (and an ignored
`.iml`). I then replaced its sample `test/widget_test.dart`, removed `cupertino_icons`, set the
version to `0.1.0+1`, and let the Flutter tool add `build/**` and `linux/**` to the analyzer excludes.

**Verified (run, this session):** `dart format --set-exit-if-changed .` clean; `flutter analyze` — no
issues; `flutter test` — 22 passing (the §5.2 query table for `search_url`, plus shell/disabled-state/
narrow-window widget tests); `flutter build linux --debug` succeeds (22 s incremental; first build
pulled pdfium); the app launched unconfined via `systemd-run --user` and rendered the empty state in the
system dark theme at the expected size (frame captured by the in-app hook).

**Deviation from plan §5.2 (deliberate):** the plan's hyphen repair `(\w)-\s+(\w)` would also glue
"pre- and post-operative" into "preand post-operative" — a common construction in medical text. The
implementation repairs a hyphen only at a *line break* followed by a lowercase letter (Unicode-aware).
Whether pdfrx actually delivers `\n` at wrapped lines is §5.1.1 gate 1; this rule is revisited with
that observation.

**Not verified / open:**
- Light theme was not rendered (only the system's dark theme was exercised); widget tests ran with
  the default theme.
- Keyboard focus/Tab order and screen-reader semantics were set but not exercised.
- `file_picker` on Linux shells out to `zenity`/`kdialog` — `zenity` exists on this machine; whether it
  becomes a `Depends:` entry is decided at M2/M6 once the picker is exercised.
- Open/zoom controls are intentionally disabled (no document yet).

---

## M2 — Real PDF reading (+ §5.1.1 gates 1 and 2) (2026-10-14, branch `feat/m2-pdf-reading`)

**Built:** `file_picker` → `pdfrx` reader: continuous scroll, zoom −/+ (header), page indicator `n / N`,
open another document, command-line/"Open With" opening (`main(args)`), a clean failure state (no raw
error text), `Ctrl+O`. Text selection enabled with `showContextMenuAutomatically: false`. Fixtures:
`test_fixtures/make_fixtures.sh` (headless Chrome → `prose.pdf`, `technical.pdf`, `two_column.pdf`;
original text, no personal files). Dev-only tooling (inert in release builds / without dart-defines):
`lib/dev/selection_debug.dart` (gate readout + a plain "test pill"), `lib/dev/dev_harness.dart`
(command-file driver that injects pointer events *inside Flutter* and dumps pdfrx state).

**`file_picker` on Linux** uses the XDG desktop portal over D-Bus (`xdp_filechooser.dart`), not
zenity/kdialog — so no extra `Depends:` entry for it.

### §5.1.1 gate 1 — text retrieval (observed)
All selections below were made with **real pointer drags** (injected through Flutter's
`GestureBinding`), then read back through `PdfTextSelection`.

| Selection | `getSelectedText()` | `getSelectedTextRanges()` |
|---|---|---|
| word `efficient` | `"efficient"` | `p1[41,50)` |
| phrase `Idiopathic pulmonary fibrosis` | exact | `p1[139,168)` |
| 3-line sentence | exact, with `\n` at each wrap | `p1[14,138)` |
| `Pre- and\npost-operative care, a state-of-the-art device` | exact (`\n` at the wrap, compound hyphens kept) | `p1[462,517)` |
| across the column break (two-column fixture) | `…quotes and dashes.\nThe office staff found…` (reading order col 1 → col 2) | `p1[1900,2011)` |
| across a page boundary (real spec PDF) | continues into the running header: `…themselves.\n3Shared MIME-info Database\n2.2. The…` | **two entries**: `p3[2681,2741)`, `p4[0,71)` |
| technical fixture: superscripts | `Let x\n2 + y\n2 = z\n2 hold [12].` (superscripts on their own line) | `p1[697,727)` |
| URL with `? & =`, `< 0.05`, en dash, a code block | exact | exact |

- **Offsets:** `PdfPageTextRange` is `[start, end)` (end **exclusive**); `textSelectionPointRange`'s end is
  **inclusive** (`p1#41 → p1#49` for the same word).
- **`PdfPageText.fullText`** is non-empty on every text page tried; `charRects.length == fullText.length`.
  Raw text (`loadText`) uses `\r\n`, structured text (`loadStructuredText`, what selection uses) uses `\n`.
- **Ligatures** (`ffi fi fl ff`: *efficient, office, difficult, affluent, official, workflow, findings*)
  come out as ordinary letters, correctly.
- **Hyphenation — three distinct shapes, all of which matter:**
  1. An ASCII hyphen at a line end (a real compound broken across lines) arrives as **U+0002**, with the
     newline swallowed: `a well\u0002known "quoted phrase"`. U+0002 reaches application code unless stripped.
  2. A typeset wrap hyphen (Chrome soft-hyphen break) arrives as **U+2010 + `\n`**:
     `pneumonoultramicroscopicsilico‐\nvolcanoconiosis`. Invisible soft hyphens (U+00AD) are dropped.
  3. A hyphen followed by a space on the same line (`Pre- and`) is a plain `-`.
  There is **no way to tell a real compound from a typeset wrap** in cases 1–2; joining is the
  better trade for search ("idiopathic" over "idio- pathic").
- The real 19-page pdfTeX document (shared-mime-info spec) contains **no** line-end hyphens at all
  (pdfrx and `pdftotext` agree), so real-world hyphenation evidence comes from the generated fixtures only.
- Independent cross-check: `pdftotext` agreed on line content and ordering for `prose.pdf`.

**Change made because of gate 1:** `normalizeQuery` now removes U+00AD and U+0002, joins `-`/U+2010 + line
break + lowercase, and replaces other control characters (tests use the exact observed strings). Plan §5.2
was amended (the original `(\w)-\s+(\w)` rule would also have produced "preand post-operative").

### §5.1.1 gate 2 — selection preservation (observed)
- `selectionWhilePillShown = true`: the selection was still present 500 ms after a plain widget
  (stacked above the viewer, overlapping the page's top edge) appeared.
- Two **real pointer taps** on that widget: `pillTaps = 2`, `selectionAfterLastPillTap = true`, and
  `onTextSelectionChange` did **not** fire again (2 callbacks total for the whole sequence); highlight intact
  in the captured frame.
- With `showContextMenuAutomatically: false` **no pdfrx context menu appeared** after selecting. Right-click
  behaviour was not exercised.
- Caveat for M3: the test widget sat at a fixed position. Re-verify with the real pill anchored over the
  selection, and confirm the widget is *above* the viewer in hit-testing order.

### Other behaviour observed
- Zoom: header `+` → 1.73 → 3.46, `−` → 1.73 (real pointer clicks). Page indicator `2 / 2` after `goToPage(2)`.
- A non-PDF file renamed `.pdf` shows the failure state with no raw error text; zoom controls disabled.
- Opening a second document resets selection state (a stale-selection bug in the *debug* readout was
  found and fixed; the product code already cleared `_selection` on open).
- Debug build: ~29 s incremental; first-launch document load 145 ms for a 3-page file.

### Not verified / open
- The **native file dialog** (portal) was not exercised: it is an out-of-process interactive dialog.
  Opening by argument and via the harness *was* exercised.
- Password-protected PDFs: shown as the generic failure state; no password prompt (out of scope).
- Scanned/image-only pages (no text layer): not tested here (plan §9 #6 "no selectable text" message
  is not built yet).
- Behaviour with very large documents and memory use: the largest document tried has 19 pages.
- Light theme still not rendered; keyboard Tab order not exercised.
- Selection by **touch/handles** is not applicable on this platform and was not tested.
- **Release build** (`flutter build linux --release`, no CEF yet): succeeds in 38 s, 30 MB bundle; the
  dev driver's command strings (`scanhyphen`, `dragchars`, `clickpill`, `colbreak`) are **absent** from
  the release `libapp.so` (checked with `strings`).

---

## M3 — Selection → action (§5.1.1 gate 3 first) (2026-10-14, branch `feat/m3-selection-action`)

### Gate 3 — selection → screen coordinates under scroll and zoom (observed)
**Method.** The anchor is computed by `selectionAnchors()` (`lib/features/reader/selection_anchor.dart`)
from pdfrx's public API only: `textSelectionPointRange` → `PdfPageText.charRects[index]` (PDF page
coordinates) → `PdfViewerController.calcRectForRectInsidePage` (document coordinates) →
`documentToLocal`. It was **not** checked against itself: for each case a frame *without* the selection
and a frame *with* it were captured and diffed; the bounding box of the changed pixels is the highlight pdfrx
actually drew, compared with the predicted rectangle (window logical px; capture ratio 1.0).

| Case | Zoom | Scroll / action | err (left, top, right, bottom), px |
|---|---|---|---|
| prose, word | 0.90 (fit) | 0 | +1.1, 0.0, +0.1, −2.5 |
| prose, word | 1.73 | 0 / 150 / 400 | +1.0, +0.3…0.7, −0.4, −3.7…−4.4 |
| prose, word | 3.0 | 0 / 100 | +0.3, +0.3, −0.6, −7.5 |
| prose, 3-word phrase | 1.73 | 0 / 150 | −0.1…+0.9, +0.3…+0.4, −0.4, +0.2…+0.3 |
| **selection held, then scrolled** (prose) | 1.73 | +120, +120, −200 | +1.0…+2.0, +0.2…+0.9, −0.4, −3.7…−4.2 |
| **selection held, then zoomed** (prose) | 1.73→3.46→1.73→0.90 | zoom in / out / fit | +0.9…+1.1, ≤0.4, ≤0.2, −2.5…−8.8 |
| two-column, phrase | 1.20 / 1.73 / 0.87 | scroll +100, zoom in, zoom out | ≤ +1.0, ≤ +0.9, ≤ −0.4, ≤ −0.5 |
| multi-line (prose, 3 lines) | 1.73 | — | bbox.top − start.top = +0.1; bbox.bottom − end.bottom = +0.3; bbox.left − start.left = −0.1 |
| multi-line (technical code block) | 1.5 | — | +0.1 / −0.1 / −0.2 |
| real LaTeX spec PDF, multi-line | 1.74 | 0 / 200 | top +0.3…+0.8, bottom −3.2…−3.8 (left/right differ: middle lines extend beyond the end characters, as expected) |

**Reading.** Left/top/right agree within ~1–2 px at every zoom (0.87–3.46) and scroll offset tried,
including with the selection held while scrolling or zooming. The *bottom* is 2–9 px lower than the
highlight because `charRects` is the glyph box (descender included) and pdfrx paints a shorter band — the
safe direction for placing something *under* the text. Multi-line: the highlight's top/bottom equal the start
character's top and the end character's bottom, so anchoring on the end character is right.
**Gate 3 holds; no fallback to hand-rolled transforms was needed.**

*Not covered:* rotated pages, pages with different sizes in one document, cropped/offset media boxes,
a selection whose end is on a different page and off-screen (the pill falls back to the start anchor, then
hides — tested with fake anchors, not with a real document), and zoom values the viewer clamps (the spec PDF
silently clamped requested zooms to 1.74).

### What was built
- `selection_anchor.dart` (above), `pill_placement.dart` (pure: below by default, flip above the selection top,
  clamp inside the viewport, report the degenerate overlap case), `selection_action_controller.dart` (debounced
  120 ms; reads the text once; `normalizeQuery`; no searchable text ⇒ no action; `dismiss`, `reset`; stale reads
  cannot overwrite newer selections), `selection_pill.dart` (the action; hit-test transparent outside itself;
  follows the viewer controller).
- Wiring in `ReaderScreen`: pill over the viewer, `Ctrl+E`, `Esc` (hides the pill **and** clears the
  selection), reset on document change. The action is a **stub** until M4: it logs the built URL
  (`https://www.google.com/search?q=…`) and shows a transient message; nothing is navigated.

### Verified in the running app (real pointer drags; key events via Flutter's focus pipeline)
- Pill appears below the end of the selection, centred on the last character, 8 px gap (pill top 383.75 vs
  end-char bottom 376; centre 506 vs 506).
- Scrolling by wheel **with the cursor exactly over the pill**: the document scrolls and the pill moves with
  the text (−52 px both). *Before the fix it did not scroll at all* (see below).
- Real pointer click on the pill: stub fired (`[find-meaning] …?q=fibrosis`), snackbar shown, **selection and
  pill unchanged** — §5.1.1 gate 2 re-confirmed with the real pill stacked over the viewer.
- `Ctrl+E` → handled, stub fired; `Esc` → handled, pill gone, selection cleared.
- Flip: for a selection on the first line of the next paragraph, the pill sat above it (704 vs selection top 712).
- 53 automated tests pass (placement, controller debounce/stale/dismiss/reset, pill widget geometry and
  hit-testing, shortcut wiring).

### Bugs found by driving the real app (fixed)
1. **Wheel over the pill was swallowed.** The pill is above the viewer in hit-test order, so scroll signals
   landing on it never reached pdfrx. Fixed by forwarding them to `PdfViewerController.handlePointerSignalEvent`;
   regression test added.
2. **Re-opening the same file left the controller detached** (same `ValueKey` ⇒ the old viewer state was reused
   with a new controller: zoom buttons and page indicator dead). Fixed with a per-open serial in the key.

### Deviations / decisions
- Pill icon is **search**, not `✦` (sparkle reads as AI; the README promises no AI answer). Plan §5.1 amended.
- Pill height 44 (plan: ≥48 dp for touch; desktop pointer only here).
- The pill is *not* shown when neither end of the selection is on screen; `Ctrl+E` still works then.

### Not verified / open
- Tab-key reachability of the pill (InkWell is focusable by default; not exercised).
- Touch handles/magnifier and ≥48 dp targets (mobile, M7).
- Right-click on a selection (pdfrx's own secondary-tap behaviour) was not exercised.
- Real OS-level key delivery (GTK → engine): the key tests inject at the framework level because the engine's
  `KeyData` path waits for a legacy raw-key message only a real embedder sends. The engine→framework hop for
  keys is therefore unverified (the owner's hands-on use covers it).
- The dev harness's pointer events are Flutter-level, as in M2.

---

## M0b — Hardened fork (2026-10-14, branch `feat/m0b-hardened-fork`)

### Pin
- Fork: <https://github.com/thisisankit27/webview_cef> (public, Apache-2.0), branch `dndreader/hardened`.
- **Pinned commit: `0970b4447cb667dc4a512ba5350a39a253d6d273`** (4 commits on upstream `bb2dbcc`; 11 files, +415/−34; the first two were M0b, the last two came from M4: `onLoadError`, and removal of the helper it orphaned). *M0b originally pinned `fe58efa`; M4 re-pinned.*
- `HARDENING.md` in the fork lists every change and serves as the Apache-2.0 §4(b) modified-files notice.
  No upstream PR was opened.
- Local working copy: `~/scratch/upstream/webview_cef` (remote `fork`). `~/scratch/plugin/wcef_exp` (the
  experiment basis, env-var switches) is preserved but is **not** what is pinned.

### What the patch does
Removes `--disable-web-security`, `--allow-running-insecure-content` and the SameSite `disable-features`
entries; sandbox **on by default on Linux** (`--no-sandbox` and `CefSettings.no_sandbox` only when the
embedder passes `WebviewSandboxMode.disabled`; Windows/macOS unchanged); a **native preflight** before
`CefInitialize` (fork a throw-away child → `unshare(CLONE_NEWUSER)`, write setgroups/uid_map/gid_map,
`unshare(CLONE_NEWPID|CLONE_NEWNET)`, `chroot("/proc/self/fdinfo")`) that returns
`sandbox_unavailable: <reason>` and **does not start CEF** on failure; one shared **in-memory**
`CefRequestContext` (optional `cachePath`); `enableGpu` wired to the existing `SetEnableGPU`. Dart:
`initialize({sandbox, cachePath, enableGpu})`, `WebviewSandboxException`. 10 Dart unit tests pass (5 new).
No navigation delegate (deferred).

### Evidence (all run this session on Ubuntu 26.04; the throwaway spike app built against the fork)
| # | Context | Settings | Observed |
|---|---|---|---|
| F1 | **unconfined** (`systemd-run --user`) | sandbox required (default) | `INIT FAILED (sandbox): … preflight stage 12`; app **stays alive**, **0 CEF child processes**, no profile directory created, no crash. **Fail-closed verified.** |
| F2 | VS Code snap shell (`snap.code.code (complain)`) | sandbox required | preflight passes, Google loads; renderers `Seccomp: 2`, `NoNewPrivs: 1`, **own user namespace**; gpu-process `Seccomp: 2`. Child cmdlines: no `--no-sandbox`, no `--disable-web-security`, no `--allow-running-insecure-content`, no SameSite entry. |
| F3 | unconfined | `sandbox: disabled` | Google loads; `--no-sandbox` present in 7/7 children (**positive control** for the cmdline method); the three other flags still absent. The escape hatch works. |
| F5 | snap shell | sandbox required, `enableGpu: true` | loads and renders; `--disable-gpu*` absent from children; **gpu-process `Seccomp: 0`** (it was 2 with GPU disabled) |
| F2/F3/F5 | — | in-memory default | after each run: **0 cookie rows, 0 Local-Storage origins** in the profile's `Default/`; nothing at `~/.config/cef_user_data` |

- **Method note.** Switches appended in `OnBeforeCommandLineProcessing` are *not* in the browser's
  `/proc/<pid>/cmdline`; they are visible in the **child** processes' command lines. The check was validated with
  positive controls (`--no-sandbox` appears in children exactly when disabled; `--disable-gpu*` appear by default;
  `--disable-features=…` is propagated, so "no SameSite entry" is meaningful).
- **Probe vs CEF.** The time-boxed preflight agreed with CEF's real behaviour in **both** launch contexts
  observed earlier (unconfined: CEF FATAL / probe fail; snap-complain: CEF starts / probe pass). **No fallback to the
  `/proc/self/attr/current` check was needed**; the more authoritative probe ships. It is ~60 lines, async-signal-safe
  in the child.
- **GPU (input to the post-M4 spike):** enabling GPU worked, but weakens the GPU process's sandbox
  (`Seccomp: 0` vs `2`). The software path is therefore also the *more sandboxed* configuration; GPU must earn its
  place with a measured benefit.

### AppArmor deliverables (root needed to *install*; nothing was installed)
- `packaging/linux/apparmor/dndreader` — profile for `/usr/lib/dndreader/dndreader` (installed by the `.deb`, M6).
- `packaging/linux/dev/install-dev-apparmor.sh [BUNDLE_DIR]` / `uninstall-dev-apparmor.sh` — **reviewable
  root-only scripts**; refuse to run unprivileged (verified), validate the generated profile with
  `apparmor_parser -Q -K` before touching `/etc`, refuse paths containing AppArmor pattern characters.
- Syntax check proven able to fail (a deliberately bad profile exits 1; the real profiles exit 0). Earlier in the
  project that check was weak (a pipe hid the exit code); this one uses the parser's own status.

### OWNER ACTION (hard stop for one item; everything else continued)
The **success path of the profile** — an *unconfined* launch starting with a real sandbox — needs root and has
**not** been run. To test it:
```
cd ~/Desktop/Projects/SaaS/DNDReader && flutter build linux --release
sudo packaging/linux/dev/install-dev-apparmor.sh        # review it first; undo with the uninstall script
systemd-run --user --collect --unit=dndreader-check "$PWD/build/linux/x64/release/bundle/dndreader" test_fixtures/prose.pdf
```
Expected: the app starts normally (it needs the M4 panel to show a webview; until then use the spike), and
`/proc/<renderer-pid>/status` shows `Seccomp: 2`. Not claimed done.

### Not verified
- The AppArmor profile success path (above); behaviour on other Ubuntu versions/distros; kernels with user
  namespaces disabled (expected: same fail-closed path, not exercised).
- In-memory behaviour **across restarts** was not separately tested (each run starts from an empty store by
  construction); EEA/UK consent behaviour (not observable here).
- Windows/macOS: untouched sandbox setting; the three flag removals have not been exercised there.
- The release build ignoring the unsandboxed dev override is an *app-level* check, done in M4.
- Probe false negatives (probe passes, CEF fails) — none seen; not provable from two contexts.

---

## M4 — Embedded search panel on the hardened fork (2026-10-14, branch `feat/m4-search-panel`)

### Built
- `lib/features/search/`: `SearchWebView` (the platform seam; desktop = CEF fork, others are an
  always-unavailable stand-in until M7), `CefSearchWebView`, `SearchSession` (state machine), `SearchPanel`.
- Panel overlays the right edge (420–480 px, `widthFor`), **one long-lived browser** shared by all searches,
  closing hides it (`Offstage`), header = Back · query (2 lines) · Open in browser · Close.
- States: starting/loading (progress bar), loaded, **failed** (Retry + Open in browser; 20 s timeout; no raw
  error text), **unavailable** (sandbox cannot start: explanation + Open in browser), **consent hint** (URL host
  only), and a loud red banner when the **development override** is active.
- Navigation policy follows the security state: sandbox active ⇒ in-panel click-through + Back; unavailable ⇒
  the panel is never created.
- `Esc` closes the panel first, then dismisses the selection; a plain tap on the document closes the panel.
- App pins the fork by SHA (`pubspec.yaml`); an untracked `pubspec_overrides.yaml` points local builds at
  `~/scratch/upstream/webview_cef` (which symlinks the single shared CEF tree). **Both resolution paths were
  exercised** (override, and the pure git pin from GitHub).
- `flutter create`-style runner changes from the plugin's CMake step are committed
  (`linux/runner/main.cc` +5, `my_application.cc` +3, plugin registrant files).

### Verified in the running app (Ubuntu 26.04; driven with Flutter-level pointer/key injection)
| Check | Observed |
|---|---|
| Unconfined launch, sandbox required (default) | panel opens in the **unavailable** state; reason shown; app alive; **0 CEF processes**; document untouched |
| Same build, snap-shell context (sandbox can start) | Google results render in the panel; renderers sandboxed |
| Opening the panel | document `visibleRect` **identical** before/with panel (no reflow, no scroll change) |
| Wheel scroll inside the panel | works (frame `m4_panel_scrolled`) |
| Click a result | navigates **in the panel** (pmc.ncbi.nlm.nih.gov); Back becomes enabled |
| Back | returns to the Google results; **stays loaded** (checked again 23 s later) |
| Close (✕) / reopen (`Ctrl+E`) | panel hides; document viewport unchanged; reopen reuses the same browser |
| `Esc` ×2 | first closes the panel (selection kept), second dismisses the selection |
| Tap on document text | closes the panel |
| Unresolvable host | **failed** state: "Couldn’t load results", Retry, Open in browser; no raw error |
| Dev override (unconfined, `DNDREADER_ALLOW_UNSANDBOXED_DEV=1`, debug build) | loads; banner visible; `--no-sandbox` in 7/7 children |
| Same build, no override, unconfined | fails closed (0 CEF processes) |
| **Release build** | override lookup **compiled out**: the variable name appears **0×** in `libapp.so`, `dndreader`, `libwebview_cef_plugin.so` (control: present in the debug kernel); dev-driver strings also absent; pure-function tests for `releaseMode: true` |

85 automated tests pass (session state machine incl. the observed CEF event orders, panel states, shortcut
wiring, placement, dev-override rules). `flutter analyze` clean.

### Bugs found by driving the real app (all fixed)
1. **False "failed" after Back.** CEF sends `loadEnd` for the restored page and *then* an address change for the
   same page; the session treated that as a new navigation, restarted loading, and no second `loadEnd` ever
   came ⇒ the 20 s timeout flipped a working page to "failed". A URL report for the page already loaded is now
   not a navigation. Regression tests encode the observed order.
2. **Raw error page.** The plugin rendered load failures as a `data:text/html` "Failed to load URL … with error
   ERR_NAME_NOT_RESOLVED (-105)" page (cefclient sample code), which my `chrome-error://` check never saw. Fixed
   in the **fork**: main-frame failures are reported via `onLoadError`; no page is rendered.
3. **Same-page URL rewrites counted as history.** Google appends `&sei=…` after load; that is now the same
   history entry (otherwise Back looked enabled when there was nowhere to go).
4. **`-Werror`:** removing the data-URI page orphaned a helper; removed it.

### GPU compositing spike (time-boxed; resolution 2 in the plan)
Same scripted scroll (60 wheel events × 120 units, 40 ms apart) of a local 630 kB page I authored (cards with
shadows, gradients, a transform; **not Google**), sandbox required, snap-shell context, page reloaded per run,
CEF `OnPaint` callbacks counted natively by a throw-away patch (not committed; the fork tree was reverted).
First attempt using Flutter `FrameTiming` was discarded: the callback delivered 0 frames in one config.

| Config | OnPaint/s during scroll (valid runs) | CPU ticks per 3.1 s run | GPU-process sandbox |
|---|---|---|---|
| GPU off (default) | 38, 42, 41 | ≈ 700–780 | seccomp **2** |
| GPU on (`DNDREADER_GPU=1`) | 56, 61, 60 | ≈ 600–670 | seccomp **0** |

- **Result:** GPU on delivered ≈ 50 % more frames at ≈ 10–15 % less CPU in this test. Run 1 of each config was a
  warm-up with no samples and is excluded; three runs per config, one machine, one page.
- **Cost:** with the GPU on, the GPU process has **no seccomp filter** (it shares the browser's user/pid/net
  namespaces in *both* configs). Renderers — the processes that handle untrusted pages — are fully sandboxed
  (seccomp 2, own namespaces) either way.
- **Decision:** GPU stays **off by default** (the approved criteria were performance-only; this security cost
  was discovered during the spike, so the choice is surfaced rather than made silently). It is an explicit
  opt-in: `DNDREADER_GPU=1`, honoured in every build. **Scroll feel remains the owner's judgement** (M0 check 4):
  M6 will hand over a release build and both configurations.
- Zero-copy (`OnAcceleratedPaint`/dmabuf) remains out of scope.

### Consent
URL-only detection is implemented and unit-tested (host `consent.google.com` / `consent.youtube.com`).
**Not observed live:** no consent interstitial appeared on this network, so the panel-level hint was verified
with fakes only, and in-memory behaviour behind an EEA/UK consent wall is **unverified**. I did not try
Google's public consent URL: reaching it from here would not reproduce a regional wall and I preferred not to
drive Google's consent UI to manufacture evidence.

### Not verified / open
- The **success path of the AppArmor profile** (an unconfined launch with a *real* sandbox) — awaiting the
  owner's `sudo` (see M0b). All sandbox-active evidence above comes from the snap-shell (`complain`) context.
- Right-click inside the panel, text input in Google's search box (IME, paste needs `xclip`), downloads, and
  popups opened by *real* result pages (popups were verified against a local page in M0).
- Keyboard focus moving between the document and the panel (Tab order).
- Behaviour with two app windows (singleton lock) and across a crash.
- The unsandboxed override is exercised only via the harness; no user-facing setting exists, by design.

## M5 — Finish the experience (2026-10-14, branch `feat/m5-polish`)

### Built
- **Persistence** (`shared_preferences`, Linux: `$XDG_DATA_HOME/io.github.thisisankit27.dndreader/`): theme mode,
  zoom, last document + page, recents (cap in `AppSettings.maxRecents`). Writes debounced 600 ms. Corrupt or
  out-of-range values fall back to defaults (unit-tested).
- **Window size** persisted by the GTK runner (`$XDG_CONFIG_HOME/dndreader/window-size`, debounced).
- **Reopen last document** at start-up when no argv path is given and the file still exists.
- **Menu**: open recent, theme (system/light/dark), keyboard shortcuts, About (app version + bundled Chromium).
- **Table of contents** (owner request): the document's own outline, shown as a left-edge overlay (document
  never reflows). Header button or `Ctrl+T`; `Esc` closes it (search panel takes priority). Nested entries with
  page numbers, current page emphasised, entries without a destination are inert, "no table of contents"
  state. Navigation uses `PdfViewerController.goToDest`.
- Shortcuts: `Ctrl+O/E/T`, `Ctrl+= / Ctrl+−`, `Ctrl+0` (fit page), `Esc`.
- New fixture `test_fixtures/outline.pdf` (nested headings, one chapter per page; Chrome `--generate-pdf-document-outline`).
  The three older fixtures are unchanged (headless Chrome output is not byte-reproducible).

### Verified (how)
- `dart format --set-exit-if-changed .`, `flutter analyze`: clean. `flutter test`: **99 tests pass** (6 new for the
  outline panel, settings-service tests).
- In the running debug app (isolated `XDG_*`, unconfined launch via `systemd-run --user`, in-app capture):
  - TOC from `outline.pdf` rendered with 3 chapters / 5 sections and correct page numbers (screenshot
    `~/scratch/evidence/m5_toc_outline.png`, dark and light); clicking "Chapter Three" moved the viewer to page 3
    (`viewport` → `page=3`).
  - `technical.pdf` (no outline) shows the "no table of contents" state.
  - Persistence across restart without argv: reopened `outline.pdf` at page **3**, zoom **3.459** (the saved
    values), header label `3 / 3`.
  - Window size: wrote `900 640`, restarted → view width 900.
  - Light theme read from preferences and rendered.
- Release build (`flutter build linux --release`) succeeds; the compiled `libapp.so` contains none of the dev
  define names (`strings … | grep -c` → 0).

### Bugs found and fixed
- Opening a document via argv hung on the spinner after settings were wired in: `PdfViewer.file` created a new
  document ref on every rebuild and stranded the in-flight load. The owner now holds one `PdfDocumentRefFile`
  per opened document.
- After restore, the header showed `1 / N` until the first scroll (restored page was not seeded). Fixed.

### Not verified / open
- **Within-page scroll offset is not restored** (page + zoom only, by design).
- Reopen-at-restore was exercised with a single document; behaviour when the saved zoom is far from fit-width
  on a different-sized window is unjudged.
- Recents menu was rendered by tests, not clicked in the live app.
- The TOC panel overlays the left edge; at very narrow windows it clamps to 80 % of width (unit-level only).
- Keyboard-only navigation of the TOC (Tab/Enter) not exercised.
- Scroll feel (M0 check 4) is still the owner's judgement — surfaced at M6 with a release build.
