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
| M6 Tests, packaging, docs | **Done 2026-10-14** except host install of the `.deb` (needs the owner's `sudo`) — see "M6" below |

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

## M6 — Tests, packaging, docs (2026-10-14, branch `feat/m6-tests-packaging`)

### Built
- `packaging/linux/build-deb.sh` → `dist/dndreader_0.1.0-1_amd64.deb` (**326 MB**, 1.5 GB installed, zstd, built
  under `fakeroot`, no root). Contents: bundle under `/usr/lib/dndreader`, `/usr/bin/dndreader` symlink,
  `/etc/apparmor.d/dndreader` (a conffile), `.desktop` (`MimeType=application/pdf`, `Exec=dndreader %f`), SVG icon,
  `/usr/share/doc/dndreader/{copyright,HARDENING.md,webview_cef.LICENSE,cef/LICENSE.txt,cef/CREDITS.html}`.
  `chrome-sandbox` is **not** shipped.
- `postinst` loads the profile (`apparmor_parser -r`, non-fatal); `prerm` unloads it.
- `packaging/linux/verify-sandbox.sh`: non-root check of a running instance.
- README rewritten to what exists (status, features, install, sandbox requirement, limitations 1–15).
- Plan §8 gained an "As built" paragraph (deviations: prerm not postrm; hand-added Depends).

### Verified (how)
- **Dependency derivation:** `ldd` over every bundled object → `dpkg -S`, plus hand-added `libegl1`, `libgles2`,
  `xclip`, `apparmor`. The first clean-container start **failed** on `libEGL.so.1`, then `libGLESv2.so.2`
  (runtime `dlopen`s `ldd` cannot see); both were added and the check re-run.
- **Clean Ubuntu 26.04 container** (`docker run ubuntu:26.04`, no Flutter/clang/CEF): `apt-get install ./….deb`
  resolved all dependencies from the archive with no manual installs; `postinst` ran (no AppArmor in a
  container, so the guarded branch skipped it — as designed); the app **started under Xvfb** and loaded the 3-page
  fixture (`PdfViewer: Loaded 3 of 3 pages`); `remove` left the conffile, `purge` removed it. Two `ldd`
  "not found" lines remain and are benign: `libjvm.so` (needed only by `libdartjni.so`, never loaded) and
  `libflutter_linux_gtk.so` (resolved at run time because the executable loads it first; the app started).
- **Sandbox without `chrome-sandbox`:** on the host (snap-shell `complain` label), with the file removed from the
  bundle, search loaded and `verify-sandbox.sh` printed `PASS: 2 renderer(s) sandboxed` (seccomp 2, no shared
  user/pid/net namespace). Same result with the file present.
- Pre-PR checks on the branch tip: `dart format --set-exit-if-changed .`, `flutter analyze`, `flutter test`
  (99 tests), `flutter build linux --release` — all pass (see the run at the end of this section).

### Not verified
- **Installing the `.deb` on the host and starting the sandbox under the packaged AppArmor profile.** It needs
  root. Commands for the owner (read `packaging/linux/apparmor/dndreader` first):
  `sudo apt install ./dist/dndreader_0.1.0-1_amd64.deb`, then start `dndreader`, select text, `Ctrl+E`, and run
  `packaging/linux/verify-sandbox.sh` — expect label `dndreader` and `PASS`. Everything sandbox-active above was
  observed in the snap `complain` context; the unconfined success path is **unobserved**.
- **Fail-closed in the packaged release binary:** observed in the debug build (unconfined launch ⇒ no CEF init,
  no renderers, panel shows "Search unavailable"); the release binary has no dev harness to trigger a search, so
  it was not driven.
- `.deb` on Ubuntu 24.04 or any other release (built against 26.04's library names, e.g. `libglycin-2-0`).
- Wayland vs X11 behaviour of the packaged app beyond the Xvfb start (the dev runs used Wayland/XWayland).
- Lintian, upgrade paths between package versions, and a published apt repository (none exists).
- **Scroll feel (M0 check 4) and GPU opinion remain the owner's.** Run the release bundle both ways:
  `build/linux/x64/release/bundle/dndreader file.pdf` (default, software) and
  `DNDREADER_GPU=1 …` (GPU compositing; faster in the scripted test, but the GPU process has no seccomp filter).
- DNDReader's own licence: no `LICENSE` file exists; this is an owner decision and is stated in the package's
  `copyright` file.

### State of the branch
`main` is untouched (`da3813a`); everything is on `feat/mvp-reader`, ready for review. No PR was opened.

## Post-MVP: reading ergonomics (2026-10-14, branch `feat/m7-reader-ergonomics`)

Owner feedback after running the installed `.deb` (`verify-sandbox.sh` printed `PASS: 3 renderer(s) sandboxed`
with label `dndreader (unconfined)` — i.e. the packaged AppArmor success path **was observed by the owner**).
Three requests:

### Built
1. **Contents panel: collapse / expand.** Topics with sub-topics start collapsed, except the branch holding the
   current page (ancestors of the last entry starting on or before it), so a long outline opens where you are.
   A chevron toggles; the title navigates (the two are separate hit targets). `outline_panel.dart` is now stateful.
2. **Scrollbars.** `document_scrollbars.dart`: vertical + horizontal bars driven by the viewer's own position
   (follow wheel, drag, keys, contents navigation), draggable thumb, click on the track pages by 0.9 viewport,
   each shown only on an axis that scrolls. They sit in the free area: offset by the open panels' widths, so a
   bar is never hidden under the contents or search panel.
   - Panels still overlay (no reflow, vertical position kept), but their widths are now passed to the viewer as
     `boundaryMargin` (`PdfView.contentInsets`). pdfrx only re-applies a changed margin on its next interaction,
     so `ReaderScreen._syncInsets` re-sets the current matrix after an inset change; the viewer then re-clamps.
     Effect: with the search panel open the page **centres in the space left over** (and is horizontally
     scrollable if wider) instead of sitting partly under the panel.
3. **Mouse-wheel speed.** pdfrx's `scrollByMouseWheel` defaults to 0.2; Linux reports ~53 px per notch, so a notch
   moved ~10 px. Set to 2.0 (`PdfView.wheelScrollFactor`); arrow keys 25 → 60 px.

### Verified (how)
- `dart format`, `flutter analyze`, `flutter test` (outline panel: 9 tests incl. collapsed-by-default, toggle does
  not navigate, current branch auto-open, leaf has no toggle).
- Driven in the debug build under Ubuntu 26.04 (Flutter-level pointer injection):
  - wheel delta 53 → visible area moved 106 document units (formerly 0.2×53 ≈ 10.6 by the formula — the old
    value was **not** re-measured);
  - search panel open: page shifted left 220 units (half the 440 px panel) and returned on close, vertical
    offset unchanged; vertical bar sits left of the panel, horizontal bar ends at the panel's edge when zoomed in;
  - thumb drags moved the view (vertical top 164.6 → 512.8; horizontal left 232.4 → 343.1); a click on the
    track advanced a page;
  - contents: chevron expands/collapses; current branch open on first show. Screenshots:
    `~/scratch/evidence/m7_*.png`.

### Not verified
- **Real mouse-wheel notch size on the owner's hardware** (53 px/notch is the Flutter Linux embedder's constant as
  I understand it, not measured here). 2.0 is a single constant if it feels too fast or slow.
- **Touchpad**: pan/zoom gestures bypass `scrollByMouseWheel`; their speed is unchanged and unjudged.
- Scrollbar thumb drag at the document extremes with very large documents (only the 3-page fixtures were driven).
- No widget test for `DocumentScrollbars` (needs a live pdfrx controller); covered by the driven run above.

## Post-MVP: Ctrl+wheel zoom, rotate, full screen, page jump (2026-10-14, branch `feat/m8-rotate-fullscreen-pagejump`, v0.1.2)

Owner feedback: Ctrl+scroll zooms only sometimes; wanted rotate, a full-screen button beside the zoom buttons,
an editable page number, and Esc to leave full screen.

### Ctrl+scroll — cause and fix
- **Cause (read from source, observed in the app):** the runner connected the plugin's `processKeyEventForCEF` to
  GTK's key events. While the embedded browser's Flutter focus node holds primary focus the plugin returns TRUE for
  *every* key, so Flutter never saw Ctrl go down and `HardwareKeyboard.isControlPressed` stayed false (pdfrx zooms
  on Ctrl+wheel only when it is true). The browser took primary focus on a click in the panel and **kept it after the
  panel closed and after clicking the document** (observed: focus chain 14 → 16 and it stayed) — hence "sometimes".
- **Fix:** (1) closing the panel returns focus to the reader, and the hidden panel is wrapped in `ExcludeFocus`;
  (2) `linux/runner/my_application.cc`: modifier keys are passed to the browser *and* left for Flutter
  (`key_event_cb`). Other keys behave as before.
- **Verified:** after clicking into the panel and closing it, primary focus is `reader` (was the browser's node).
- **Not verified:** the GTK key path itself — OS-level input does not reach this app under XWayland here, so
  "Ctrl is now seen while the browser has focus" and a real wheel+Ctrl run are **unobserved**; pdfrx's own
  Ctrl+wheel handling was not changed. Touchpad two-finger scroll is delivered as a pan, not a wheel event, and
  does not zoom with Ctrl (pinch does) — unchanged, and a possible second cause on a touchpad.

### Features
- **Rotate:** header button, `Ctrl+R` clockwise, `Ctrl+Shift+R` counter-clockwise. Pages are replaced with rotated
  proxies (`document.pages = …`), so the viewer re-lays out; text selection and the pill follow (checked: "the" on a
  rotated page selects, the pill sits under it). A view setting only: not written to the file, not remembered.
  Outline destinations that carry an exact x/y position were not checked on rotated pages.
- **Full screen:** button next to the zoom buttons, `F11`; `Esc` leaves it first. Implemented as a tiny
  `dndreader/window` channel in the runner (no new dependency). Window size is not saved while full screen.
- **Page number:** the header shows an editable field plus `/ N`. Enter jumps (clamped to 1..N), Esc or clicking
  away restores the real page, non-digits are rejected.

### Verified (how)
- `dart format`, `flutter analyze`, `flutter test` (111 tests; 9 new header tests: jump, clamp, empty, follow, buttons).
- Driven in the debug build: rotation changed the viewport and rendered correctly (screenshots
  `~/scratch/evidence/m8_*.png`); F11 took the viewer from 1100×708 to 1536×812 and Esc back; saved window size
  stayed `1100 760`; page field takes and releases focus.
- **Not verified:** typing digits into the page field in the running app (the harness cannot feed the text-input
  channel; covered by widget tests); full screen on X11 or other window managers; narrow-window header (<560 px)
  was checked only by the existing no-overflow test.

## Post-MVP: right-click menu and double-click (2026-10-14, branch `feat/m9-menu-doubleclick`, v0.1.3)

Owner report (with screenshot): the right-click menu was hidden behind the "Find meaning" pill, and double-click
did not select a word.

- **Double-click:** pdfrx delivers `PdfViewerGeneralTapType.doubleTap` but does nothing with it (only a touch
  long-press selects a word). The viewer now calls `textSelectionDelegate.selectWord` for a double-click on text.
  Verified in the app: double-click on a character selects "efficient".
- **Right-click menu:** reproduced exactly (pill painted over the menu, because pdfrx draws the menu inside the
  viewer, below the pill in the stack). Fixed by (1) hiding the pill while the menu is on screen, via a presence
  flag tied to the menu widget's lifecycle, and (2) drawing the menu ourselves. pdfrx's default menu was also
  almost unreadable in the dark theme (pale surface, faint text), so it now uses the theme's own surface colours.
  Items: Copy, **Find meaning** (new; only when text is selected), Select all.
- **Verified:** pill hidden and menu legible on right-click over a selection; "Find meaning" from the menu loaded
  the results panel (`q=efficient`); a pill-less state after Copy (pdfrx clears the selection after copying — its
  behaviour, not changed).
- **Not verified:** the light theme (screenshots were dark); triple-click (not implemented); right-click with the
  contents panel open. (The Ctrl+C / Ctrl+A hints in the menu are pdfrx's own key bindings, read from its source,
  not exercised here.)

## Post-MVP: right-click "Find meaning" before the pill appears (2026-10-14, branch `feat/m10-menu-fast-path`, v0.1.4)

Owner report: double-click then an immediate right-click showed a menu without "Find meaning"; waiting for the pill
first made it appear.

- **Cause:** the menu offered the item only when `SelectionActionController.available` was true, and that is set
  after a 120 ms debounce plus an async text read — a fast right-click beat it.
- **Fix:** the menu offers "Find meaning" whenever text is selected, and choosing it reads the selection at that
  moment (`SelectionActionController.resolveQueryNow()`), so it neither depends on the debounce nor uses a stale
  query. A selection that normalises to nothing (whitespace) does nothing.
- **Verified:** 2 new unit tests (query resolved before the debounce settles; null for none/blank), 113 tests pass;
  in the app, double-click → right-click → "Find meaning" issued the search `q=efficient`.
- **Not verified:** the *fast* timing itself in the running app — the harness polls every 400 ms, longer than the
  debounce, so it cannot reproduce "instantly"; the unit test covers the logic. Google answered that session's
  repeated test searches with its `/sorry/` page (rate limit); not automated against, per the standing rule.

## Post-MVP: selection highlight colour (2026-10-14, branch `feat/m11-selection-colour`, v0.1.5)

Owner request: let the user choose the text-selection highlight colour; the default read as green, which can be a
problem for colour-blind users.

- **Built:** `SelectionHighlight` (sky blue — new default, yellow, orange, pink, grey; the Okabe–Ito
  colour-blind-safe hues plus a neutral grey) in `models/app_settings.dart`; Menu → **Selection colour** with a
  radio per colour and a swatch drawn as it looks over the white page; persisted (`selectionHighlight`, validated
  on load: an unknown value falls back to the default); applied through `TextSelectionThemeData` so the PDF viewer
  (and text fields) follow it live.
- **Verified:** 3 new unit tests (default, persistence + bad value, survives "forget last document"); 115 tests
  pass; in the running app the default highlight is sky blue, choosing Orange recolours the existing selection
  immediately, and after a restart the stored value (`flutter.selectionHighlight: orange`) is applied.
  (The test choice was then removed from the owner's preferences file so their default is untouched.)
- **Not verified:** how each colour looks to people with each type of colour-vision deficiency — the palette is the
  published Okabe–Ito set, not tested with a simulator or with users; the dark theme is unaffected because the page
  is always white, but the light theme was not re-screenshotted for this change; contrast of the translucent
  overlay against *coloured* PDF backgrounds or images was not examined.

---

# Windows port (WebView2) — `feat/windows-port`

Source of truth: `docs/windows-implementation-plan.md`. Labels as there: **verified** (with how),
**read** (source/docs, not executed), **not verified**. **Nothing on Windows is verified until CI or
the owner demonstrates it; a green CI run proves compilation and unit tests, not that the app runs.**

| Milestone | Status |
|---|---|
| W1 Scaffold, CI, green Windows build | **Done 2026-10-14** — both CI jobs green (run `38514280955`); see "W1" below |
| W2 WebView2 search panel | **Done 2026-10-14** — CI green; compiles and unit-tested only, never run — see "W2" below |
| W3 Native runner seams | **Done 2026-10-14** — CI green (compile only); nothing run — see "W3" below |
| W4 Reader ergonomics and honesty | **Done 2026-10-14** — see "W4" below; wheel feel unmeasured |
| W5 Packaging | **Done 2026-10-14** — installer built and silently installed/uninstalled on a CI runner; see "W5" below |
| W6 Docs and handover | **Done 2026-10-14** — `docs/completion-report-windows.md`; ready for review |

## W1 — Scaffold, CI, green Windows build (2026-10-14, branch `feat/w1-scaffold-ci`)

### Supply-chain check on `webview_flutter_windows` 1.3.0 (plan §3.4) — passed, with stated limits

The package borrows the Flutter team's federated naming and its publisher domain (`tomars.tech`)
does not match its repo owner (`omar-hanafy`). Findings:

**1. Lineage — verified by comparing source, not by reading the README.**
- The published archive (`pub.dev/api/archives/webview_flutter_windows-1.3.0.tar.gz`) was downloaded
  and its sha256 (`599d1254…dd35`) **matches** `pubspec.lock`'s recorded hash. 
- `omar-hanafy/webview_flutter_windows` is a **GitHub fork** (`fork: true`, parent
  `jnschulze/flutter-webview-windows`). Cloned: 151 commits, of which 92 are by the original author
  (Niklas Schulze) from 2021-04-30 onward; the merge-base with upstream `main` is `ed81bbe`
  (2025-06-26), upstream's current head. The fork adds 31 commits (29 by Omar Khaled, 2 by external
  contributors) on top.
- Tag `webview_flutter_windows-v1.3.0` (`fa4ee15`): its `windows/` and `lib/` trees are
  **byte-identical** to the published archive (`diff -rq`; the only difference is a `.gitignore`
  that is not published). What pub.dev ships is what the repo's tag contains.
- `LICENSE` is the original BSD-3-Clause, copyright Niklas Schulze.
- The owner account is 7 years old (2019-03-13) with 84 public repos. The repo was forked
  2026-06-10; 2 stars. **Adoption is low**, as the plan says; that is a maturity risk, not
  evidence of malice.

**2. What the build fetches — read from `windows/cmake/nuget.cmake` and `windows/CMakeLists.txt`.**
- `find_program(NUGET nuget)` first; **only if no `nuget` is on `PATH`** does it download
  `https://dist.nuget.org/win-x86-commandline/v7.6.0/nuget.exe` with `TLS_VERIFY ON` and
  `EXPECTED_HASH SHA256=751ee5e7…8fb8a2`, then re-checks the hash and `FATAL_ERROR`s on mismatch.
  **Verified by me:** I downloaded that URL independently and its sha256 equals the pinned value.
  This is stronger than the plan's "downloads nuget.exe if missing" worry implied: it is pinned by
  version and by hash.
- It then runs `nuget install` (at CMake configure time) for **two pinned versions** from
  nuget.org: `Microsoft.Web.WebView2` 1.0.3967.48 and `Microsoft.Windows.ImplementationLibrary`
  1.0.260126.7.
- **Not established / residual trust:** (a) the plugin pins those NuGet package *versions* but not
  their *content hashes*; integrity there rests on nuget.org and NuGet's own package-signature
  handling (Microsoft publishes both packages signed — **read**, not checked here).
  (b) **On CI the hash-pinned download path never ran:** the `where nuget` diagnostic (run 2)
  shows `C:\ProgramData\Chocolatey\bin\nuget.exe` already on the runner's `PATH`, so
  `find_program` found it and no `nuget.exe` was fetched. The runner's NuGet is whatever the
  GitHub image ships; it is not pinned by this project. The download-and-verify branch was read
  and its hash checked by hand, but it has **not been executed** by anything here.
- `windows/CMakeLists.txt` contains no other `file(DOWNLOAD)`, `execute_process` or
  `add_custom_command`; the plugin's own Windows sources contain no HTTP client, process-spawn or
  shell-execute calls (`grep` over `windows/` and `lib/`: only `LoadLibraryA("ComBase.dll")` and
  `("coremessaging.dll")`, both OS libraries, for WinRT activation).
- The Dart side opens only its own method/event channels.

**3. Conclusion.** Lineage is genuine and the build hook is pinned and hash-checked. **No hard stop.**
I did not audit the C++ source line by line; the claims above are about provenance, the build
hook and the absence of network/process primitives, not a full security review. The mitigations in
plan §3.4 stand: exact pin (`webview_flutter_windows: 1.3.0`, no caret), thin wrapper behind
`SearchWebView`, "Open in browser" as the escape hatch.

### What was built

- **Fork change** — `thisisankit27/webview_cef` branch `dndreader/windows`, commit
  `0e82566`: removes the `windows:` entry from `flutter.plugin.platforms` (Linux/macOS untouched) and
  records the change and trade-off in the fork's `HARDENING.md`. `pubspec.yaml` pins that **SHA**,
  not the branch. Trade-off, as in the plan: the fork becomes DNDReader-specific on this axis.
- **`flutter create --platforms=windows`** (guarded). Touched exactly:
  - `.metadata` — **replaced** the `linux` migration entry with `windows` rather than adding one;
    restored the `linux` entry by hand, so both are present (plus `root`).
  - `analysis_options.yaml` — added `windows/**` to `analyzer.exclude` (kept; correct).
  - `pubspec.lock` — see below.
  - `test/widget_test.dart` — a default counter test that cannot pass against this app; **deleted**.
  - `windows/` — 16 new files (runner, CMake, generated plugin registrant).
  - `README.md` and `.gitignore` were **not** touched.
- **`pubspec.yaml`** — `webview_cef` ref → `0e82566…`; added `webview_flutter_windows: 1.3.0`.
- **`pubspec.lock`** — regenerated with the local `pubspec_overrides.yaml` moved aside, so it records
  the git ref and the hosted package (the `flutter create` run had written the local override path
  into the lock). The new package's sha256 equals the archive hash checked above.
- **`.github/workflows/windows.yml`** — `analyze_test` (ubuntu-latest) and `build_windows`
  (windows-latest) as specified in plan §7 W1, plus guards that `pubspec_overrides.yaml` is absent
  and that the fork resolves from a git ref, and a bundle assertion that also fails if any `libcef*`
  ships.

### CI results

**Run 1** (`38513515416`, commit `8ca3e29` on `feat/w1-scaffold-ci`):

- `build_windows` — **success**. `flutter build windows --release` built `dndreader.exe` in
  **215 s** (cold caches). The `jni` FFI build, named as the likeliest blocker, **built without
  intervention** (`dartjni.dll` is in the bundle). All four assertions passed (`dndreader.exe`,
  `WebView2Loader.dll`, `flutter_windows.dll`, `data/app.so`); **no `libcef*` in the bundle**.
  Bundle is **37 MB**: `dndreader.exe` 92 KB, `flutter_windows.dll` 21 MB, `pdfium.dll` 7.2 MB,
  `webview_flutter_windows_plugin.dll` 554 KB, `WebView2Loader.dll` 159 KB, `dartjni.dll` 58 KB,
  `url_launcher_windows_plugin.dll` 98 KB. (Plan estimated ~40 MB; CEF's 326 MB is absent.)
- `analyze_test` — **failed on my own guard step**, not on format/analyze/test: the `grep -A6`
  window was one line short of `source: git`. Fixed (`sed` range). The format, analyze and test
  steps in that job were therefore skipped on run 1.

**Run 2** (`38514280955`, commit `1bbdd01`) — **both jobs green.**

- `analyze_test` — success: no overrides file, fork resolved as `source: git`, `dart format`
  (41 files, 0 changed), `flutter analyze` (no issues) and `flutter test` all passed on Ubuntu.
- `build_windows` — success; the build took **93 s** with the Flutter, pub and `build/windows`
  caches restored (215 s cold). The same four bundle assertions passed.
- `where nuget` → `C:\ProgramData\Chocolatey\bin\nuget.exe` (see the supply-chain note above).

### Verified (how)

- 115/115 tests pass, `dart format --set-exit-if-changed .` clean, `flutter analyze` clean —
  **run locally** on Linux after the scaffold.
- `flutter build linux --release` — **run locally**, succeeded with the new pins (via the local
  override, which now resolves to the fork's `dndreader/windows` checkout).
- Windows app **compiles and links** with all plugins, and the bundle contains the expected files and
  no CEF — **CI run 1**, `build_windows` job.
- The pinned fork SHA resolves from the public repo — CI `flutter pub get` fetched it (`Got
  dependencies`), no override present on the runner.

### Not verified

- That the Windows app **starts**, shows a window, opens a PDF, or renders anything — never run.
- That `WebView2Loader.dll` sitting beside `dndreader.exe` is what the plugin loads at runtime.
- The hash-pinned `nuget.exe` download branch — CI used the runner's preinstalled NuGet.
- Runtime behaviour of `jni`/`dartjni.dll` on Windows; it compiles, nothing more is claimed.
- WebView2 sandbox state, Windows 11 behaviour — as plan §8.4.

## W2 — The WebView2 search panel (2026-10-14, branch `feat/w2-webview2-panel`)

### What was built

- `lib/features/search/search_web_view_windows.dart` — `Webview2SearchWebView implements
  SearchWebView` (~190 lines). The interface is unchanged and no shared code moved.
  - `start`: `getWebViewVersion()` → `null`/empty means the Runtime is missing →
    `SearchUnavailableException('The Microsoft Edge WebView2 Runtime is not installed.')`; then
    stale-profile sweep, `create()` the profile folder, `initializeEnvironment(userDataPath:)`,
    `initialize()`. Any `PlatformException` there (notably `environment_creation_failed`) becomes
    `SearchUnavailableException` with a Windows reason; `environment_already_initialized` is reused.
  - **No `additionalArguments`** are passed — that is where upstream CEF's three dangerous flags
    lived, so their removal is moot here.
  - Event mapping: `url` → `onUrlChanged`; `loadingState == navigationCompleted` → `onLoadEnd`
    (with the last URL seen); `onLoadError` → `onLoadError(url, status.name, status.index)`.
  - `WebErrorStatus.operationCanceled` is **not** forwarded: it is what a superseded navigation
    reports, and the session treats any load error as "failed". (Decision from reading the
    plugin; not observed.)
  - `setPopupWindowPolicy(sameWindow)` — the CEF fork's `OnBeforePopup` loads the target URL in the
    same view (`common/webview_handler.cc:161-176`), so `target=_blank` results stay in the panel
    instead of opening a separate native window.
  - `setDevToolsEnabled(false)`; the `Webview` widget gets a `permissionRequested` delegate that
    **denies** every browser permission request (camera, microphone, location, notifications,
    clipboard-read) rather than letting WebView2 prompt. Both are choices of mine, not in the plan.
  - Teardown (`dispose()` and an `AppLifecycleListener.onExitRequested`): `clearCookies()`,
    `clearCache()`, controller `dispose()`, then delete the profile folder, retrying 10 × 300 ms
    while WebView2's processes exit. Runs once.
- `lib/features/search/search_profile.dart` — the throwaway profile and the stale sweep (W2.1),
  split into a **pure** `decideSweep()` and a thin IO layer (`SearchProfileStore`).
  - Name must match `^dndreader-search-[0-9]+$` and is checked **before** anything is stat'ed.
  - Entry type is read with `followLinks: false`; a link is refused without being resolved.
  - The entry and the temp directory are both fully resolved, and the entry must equal
    `<resolved temp><sep><name>` exactly (an exact comparison, not a prefix test; case-insensitive
    only on Windows).
  - Own pid is never swept. Not in the plan, added because it is necessary: a **live second
    instance** has its own `dndreader-search-<pid>` folder, so each instance holds an exclusive
    lock on `<folder>\.dndreader-lock` for its lifetime and the sweeper refuses a folder it cannot
    lock. A folder with no lock file is swept only once it is 60 s old. (A pid-liveness check was
    rejected: pids are reused, and it needs either a process spawn or a new direct dependency.)
  - The delete of our own folder re-runs the direct-child check and refuses a symlink.
- Factory: `Platform.isWindows` → `Webview2SearchWebView`; Linux/macOS stay on
  `CefSearchWebView`. **Deviation from the plan's "conditional import":** Dart's conditional
  imports select on `dart.library.*`, not on the operating system, so they cannot separate Windows
  from Linux; the choice is a run-time `Platform` check and both packages are compiled everywhere.
  Only the matching class is ever constructed.
- `unsandboxedDevOverrideActive` is always `false` on Windows, so the `_UnsandboxedBanner` and the
  override path do not exist there. `DNDREADER_GPU` is only read inside `CefSearchWebView` and is
  therefore ignored on Windows.
- Panel text: the "can't run here" body names the **WebView2 Runtime** on Windows instead of the
  Linux sandbox, and the consent note no longer claims cookies are "not kept on disk" on Windows
  (it says the data is in a temporary folder deleted when you quit). That sentence would have been
  false there.

### Tests

142 pass (115 + 27 new). `test/search/search_profile_test.dart` (23): the name matcher against 19
bad names including `12a`, trailing newline, `/..`, full-width digits and a bare prefix; the
direct-child check (sibling-prefix, nested, elsewhere); every `decideSweep` refusal (name, symlink,
non-directory, unresolved, outside temp ×4, own pid, in use, too new); and real-directory runs:
sweeps only stale folders of ours, **a symlink to an outside directory is neither followed nor
removed** and the outside files survive, a symlink to a same-named directory, a held lock, a fresh
lock-less folder, a missing temp directory, and `delete()` refusing a symlinked profile path.
`test/search/search_panel_text_test.dart` (4). The webview itself is never driven.

Limits of those tests: they run on Linux, where `FileLock.exclusive` is per-process, so a lock
**held by another process** is exercised through an injected probe, not for real; Windows junctions
(as opposed to symlinks) and Windows path casing are covered only by the pure functions.

### Windows 11 capture border (plan W2)

**Read:** the plugin builds its capture item with `CreateGraphicsCaptureItemFromVisual` — a
*Composition visual*, not a window or monitor (`texture_bridge.cc:19`) — and calls
`StartCapture()` without setting `IsBorderRequired`; the package exposes no API for it. My reading
of Microsoft's documentation is that the yellow border is drawn for window/display capture, which
this is not, so it is likely absent — but **not verified**, and it stays on the owner's Windows 11
checklist. Not a divergence recorded as fact.

### Verified (how)

- 142 tests, format and analyze clean, Linux release build — **run locally**.
- Windows compile and the 142 tests on Ubuntu — **CI run `38515229190`**, both jobs green. This
  proves compilation only.

### Not verified

- That the panel starts, loads Google, scrolls, goes back, or fails closed with the Runtime absent —
  **never run on Windows**.
- That `getWebViewVersion()` returns `null` (rather than throwing) when the Runtime is missing —
  taken from the package's documentation (**read**).
- That `AppLifecycleListener.onExitRequested` fires when the Windows window is closed (**read**
  from Flutter docs, not observed); if it does not, the folder is removed by the next launch's
  sweep, not at quit — which the owner's checklist item "folder gone after quit" will show.
- That denying permissions or disabling DevTools has no visible effect on Google results.
- The lock-based liveness check across two real processes on Windows.

## W3 — Native runner seams (2026-10-14, branch `feat/w3-runner-seams`)

### What was built (all in `windows/runner/` unless stated)

- **`dndreader/window` channel** (`flutter_window.cpp`): `flutter::MethodChannel<EncodableValue>` over
  `StandardMethodCodec`, created after `RegisterPlugins`. `setFullscreen` takes a **bare bool**
  (anything else → `bad-args` error, as on Linux), replies `void`; any other method →
  `NotImplemented`. `isFullscreen` is not implemented (no Dart caller, per the plan).
- **Fullscreen** is emulated: on enter the style and `WINDOWPLACEMENT` are saved, `WS_OVERLAPPEDWINDOW`
  stripped and the window sized to the monitor (`MonitorFromWindow`/`GetMonitorInfo`); on exit the
  style and placement are restored (a maximized window returns maximized).
  **`fullscreenChanged(bool)` is pushed from the runner** after each change, because no window-manager
  event exists to observe. Dart's `_fullscreen` is only ever updated by this push.
- **Window size** (`window_settings.{h,cpp}`, new): `%APPDATA%\dndreader\window-size` (`"W H"`) via
  `SHGetKnownFolderPath(FOLDERID_RoamingAppData)`. Same constants as `my_application.cc`: default
  **1100×760**, accepted range width 480–10000 / height 360–10000, anything else falls back to the
  default. Sizes are stored in **logical** pixels (`GetWindowRect` ÷ `GetDpiForWindow/96`), because
  `Win32Window::Create` scales the requested size by the monitor's DPI. Saves are **debounced
  500 ms** (`SetTimer`, restarted by every `WM_SIZE` and `WM_EXITSIZEMOVE`; minimise ignored) and
  **skipped while maximised, minimised or full screen**, mirroring the Linux rule.
- `main.cpp`: window title is **`DNDReader`** (the template's `dndreader`), size comes from
  `LoadWindowSize()`.
- **Focus**: `SearchWebView.releaseFocus()` added to the interface (CEF: no-op; Windows:
  `WebviewController.releaseFocus()`; fake: counted). `ReaderScreen` calls it when the panel closes,
  alongside the existing `_focusReader()`. The package already reclaims focus on a click outside the
  webview; this covers closing by keyboard.

### Confirmed in the generated runner (read)

- **Command-line `.pdf` argument reaches Dart.** `main.cpp` calls `GetCommandLineArguments()` and
  `project.set_dart_entrypoint_arguments(...)`; `utils.cpp` skips `argv[0]` and converts the rest
  to UTF-8. `_pdfFromArgs` therefore sees what "Open With" passes. Not run.
- **Black view background** (Linux `fl_view_set_background_color`): not reproduced. The Windows
  window class has `hbrBackground = 0` and the window is not shown until the first Flutter frame
  (`SetNextFrameCallback → Show()`), so there is no pre-frame white flash to colour. **Read**, not
  observed.
- `isFullscreen`: not implemented, see above.

### Build issue found by CI

First CI run failed to compile `window_settings.cpp`: `knownfolders.h` was included before
`windows.h` (`EXTERN_C`/`GUID` undefined). Fixed by including `windows.h` first; run
`38516722765` is green. This is exactly the class of error only a Windows build finds.

### Tests

142 pass; one new assertion — closing the panel with Esc calls `releaseFocus()` once
(`test/widget/empty_state_test.dart`). The C++ is **not unit-tested**: there is no native test
harness here, and CI only compiles it.

### Verified (how)

- Runner C++ compiles and links — **CI run `38516722765`** (`build_windows`), after one fix.
- Dart: format, analyze, 142 tests — local and CI `analyze_test`.

### Not verified

- That `setFullscreen` works at all: that the frame strips, the monitor is covered, the taskbar is
  hidden, and that `F11`/`Esc` and the header icon behave — **never run**.
- That window size restores, that a drag-resize saves once, that the DPI handling is right on a
  scaled display or when moved between monitors.
- Focus: whether the package's reported "focus bouncing" occurs in this app, and whether
  `releaseFocus()` on close is sufficient. Plan §W3.4 says investigate on Windows; not done.
- That `%APPDATA%\dndreader` can be created on a locked-down profile (failures are silent by design).

## W4 — Reader ergonomics and honesty on Windows (2026-10-14, branch `feat/w4-ergonomics`)

### What changed

- **Mouse wheel is per-platform** (`PdfView.wheelScrollFactorFor`): Linux stays **2.0**, Windows is
  **1.0**. The plan said to retune "by measurement" and I cannot measure on Windows, so this is
  derived from source instead: I fetched the Flutter engine at this SDK's revision
  (`abaf9c5`, `engine/src/flutter/shell/platform/windows/flutter_window.cc`) and **read**
  `UpdateScrollOffsetMultiplier()` — the per-notch scroll is `lines_per_scroll × 100/3` px, with
  `lines_per_scroll` from `SPI_GETWHEELSCROLLLINES` (default 3), i.e. **100 px per notch** by
  default and following the user's Windows setting. Linux's is `53` (`fl_scrolling_manager.cc`).
  Linux 53 × 2.0 ≈ 106 px; Windows 100 × 1.0 = 100 px — the same target. Keeping 2.0 on Windows
  would have been ~200 px per notch. **This is a calculation, not a measurement**: whether it
  *feels* right is on the owner's checklist, and `arrowKeyStep = 60` is unchanged. `Ctrl`+wheel
  zoom remains entirely pdfrx-internal.
- **Document name** — new `lib/services/path_names.dart` `baseName()`, used by the header and the
  Recents menu. On Windows it splits on `\` **and** `/`; elsewhere only `/` (a backslash is a legal
  filename character on Linux). Trailing separators are ignored.
- **About dialog** — `embedded_browser_info.dart`. On Windows it shows `Microsoft Edge WebView2
  Runtime <version>` from `getWebViewVersion()` (or "not found") plus "Search data is kept in a
  temporary folder that is deleted when you quit"; `kBundledChromium` (a CEF string that would be
  **wrong** there) is shown on Linux only. `_showAbout` became `async` for the version lookup.
- Three comments that became false were corrected: `window_service.dart` ("Linux and Windows"),
  `pdf_picker.dart`, and `pdf_view.dart` (rewritten with the per-platform derivation).

### Tests

149 pass (142 + 7 new, `test/path_names_test.dart`): mixed and trailing separators on both
conventions, the backslash-is-a-filename-character case, empty/root, both About variants, and the
two wheel factors.

### Verified (how)

- Dart: format, analyze, 149 tests — local; CI recorded below.
- The Windows per-notch distance — **read** from engine source at the matching revision.

### Not verified

- How the wheel *feels* on Windows, and the actual px per notch with the owner's mouse and system
  setting (a Precision touchpad sends its own deltas, not covered by this reasoning).
- That the About dialog's Runtime version lookup returns what the code expects.
- On Windows, that `Platform.pathSeparator` is no longer used anywhere that matters (grep: no
  remaining `split(Platform.pathSeparator)` in `lib/`).

## W5 — Packaging (2026-10-14, branch `feat/w5-packaging`)

### What was built

- `packaging/windows/dndreader.iss` — Inno Setup 6.3+. Per-user by default (`PrivilegesRequired=lowest`
  with the dialog override, so it can be installed per-machine); `MinVersion=10.0.17763` (Windows 10
  1809), x64 only; no signing certificate.
  - **`.pdf` association**: ProgID `DNDReader.pdf` with `shell\open\command` →
    `"{app}\dndreader.exe" "%1"`, plus `OpenWithProgids` under `.pdf` and an `Applications\dndreader.exe`
    entry. All under `HKA\Software\Classes` (HKCU for a per-user install). It **offers** DNDReader in
    "Open with"; it does not seize the default (Windows 10+ leaves that to the user).
  - **WebView2 Runtime**: detected by the `pv` value under
    `Software\Microsoft\EdgeUpdate\Clients\{F3017226-FE2A-4295-8BDF-00C3A9A7E4C5}` in
    `HKLM32` (WOW6432Node) and `HKCU`; absent/empty/`0.0.0.0` = missing. If missing, the bundled
    ~1.8 MB `MicrosoftEdgeWebview2Setup.exe` is extracted to `{tmp}` and run with `/silent /install`.
- `packaging/windows/build-installer.sh` — reads `kAppVersion` with the **same `sed`** as
  `build-deb.sh`, copies the plugin's BSD-3 `LICENSE` plus a short notices README into
  `{app}\licenses`, and calls `ISCC`. The bootstrapper is gitignored.
- CI (`windows.yml`, `build_windows` job): fetches the bootstrapper from Microsoft's
  `go.microsoft.com/fwlink/p/?LinkId=2124703`, **fails the build unless its Authenticode signature is
  `Valid` and issued to Microsoft Corporation** (there is no stable hash to pin — Microsoft updates
  the file), installs Inno Setup if the image lacks it, builds the installer, uploads it, then runs a
  silent install / launch / uninstall smoke test (`continue-on-error`, so a failure is shown rather
  than hidden).
- **No** AppArmor analogue and **no** Windows `verify-sandbox.sh` — the sandbox belongs to Microsoft's
  Runtime, not to us (plan §3.5).

### Evidence — CI run `38518338633` (both jobs green)

- Bootstrapper: signature `Valid`, `CN=Microsoft Corporation`, 1,860,304 bytes.
- Installer: `DNDReader-0.1.5-setup-x64.exe`, ~15 MB (artifact 14,963,459 B); the whole bundle is 37 MB
  uncompressed. Both are well under the plan's ~40 MB estimate because CEF is absent.
- **Executed on a `windows-latest` runner** by the smoke step:
  - silent install exit code 0; `dndreader.exe`, `WebView2Loader.dll`, `flutter_windows.dll`,
    `licenses\README.txt` and `unins000.exe` present in the install dir;
  - HKCU registry: `DNDReader.pdf\shell\open\command` =
    `"<dir>\dndreader.exe" "%1"`, and `OpenWithProgids` lists `DNDReader.pdf`;
  - `dndreader.exe` **was still running after 15 s** and its main window title was `DNDReader`
    (W3's title change, observed);
  - `%APPDATA%\dndreader\window-size` **was written**, containing `1044 760` — W3's persistence code
    ran. (1044 rather than the 1100 default is because the runner's virtual display is evidently
    1024 px wide, so Windows clamped the window; this is not a defect and the height is 760.)
  - silent uninstall exit code 0, install dir and the ProgId key removed.
- The runner already had the WebView2 Runtime, so the **bootstrap branch of the installer was not
  executed**. NuGet was again the runner's own (`C:\ProgramData\Chocolatey\bin\nuget.exe`).

### What this does and does not show

It shows the installer builds, installs and uninstalls cleanly and the app **starts and stays up** on
a Windows runner without a PDF argument. A hosted runner is not a desktop a person is using: it says
nothing about rendering, the panel, input, focus, or the Windows 10 machine the owner will use.

### Not verified

- The WebView2 bootstrapper path on a machine **without** the Runtime — the installer's `Check`
  expression and the `/silent /install` invocation are **read** from Microsoft's documentation only.
- That Explorer's "Open with" / double-click actually launches DNDReader with the file (only the
  registry values were checked).
- Per-machine (admin) install behaviour, upgrade-over-existing, and the installer on Windows 10 (the
  runner is a newer Windows Server image).
- The Inno Setup version used (installed by the image or Chocolatey; the exact version was not
  recorded by this run).

## W6 — Documentation and handover (2026-10-14, branch `feat/w6-docs`)

- `README.md`: Status gains a Windows row that says exactly how far the port has been taken (built,
  packaged and started in CI; nothing else observed); the search-panel row, prerequisites/build
  steps, "What leaves your device" and limitations 5, 7, 9, 10, 11, 12 are now per-platform. The
  privacy statement is explicitly *discarded when you quit* on Windows, not *never written to disk*.
- `docs/implementation-plan.md` §9 items 5, 7, 9, 10, 11, 13 and the Chromium-cadence risk row carry a
  Windows note: the Chromium-update duty and the AppArmor requirement do not apply, the privacy
  guarantee is weaker, `xclip` is irrelevant, and the bundle-size/software-rendering item is CEF-only.
  Nothing else in that document was changed.
- `docs/completion-report-windows.md`: delivered work, milestones with CI run ids, the engine, trust
  and privacy decisions with their evidence, every place I departed from or added to the plan, what is
  not verified, and the ordered owner checklist (17 steps).

### Verified (how)

Final local checks on the branch head are recorded in the completion report's §1 and §9 and were run
for this milestone: `dart format --set-exit-if-changed .`, `flutter analyze`, `flutter test` (149),
`flutter build linux --release`.

### Not verified

Everything listed in `docs/completion-report-windows.md` §7. In particular, nothing about how the
Windows app looks or behaves has been observed by anyone.

## Follow-up: D4 and D2 from the Windows verification (2026-10-14, Ubuntu session)

Source: `docs/windows-verification/REPORT.md`. Branches `fix/d4-page-field-focus` (`d47c9d1`) and
`fix/d2-sweep-at-launch` (`979aa60`), merged into `feat/windows-port`.

- **D4 reproduced on Linux** with the real app (`flutter test integration_test -d linux`, Flutter-level key
  injection): shared bug, not Windows-specific. Fixed in `ReaderScreen._onPageEditDone`. 3 of 4 integration
  assertions failed before, 4/4 pass after.
- **D2**: the stale-profile sweep moved from the search view's `start()` to `main()` at launch, in a background
  isolate; Windows only; guards unchanged; 4 new end-to-end unit tests.
- Tests: 149 → **155** (`test/widget/page_field_focus_test.dart` ×2, `test/search/search_profile_test.dart` ×4).
  `dart format`, `flutter analyze` clean; `flutter build linux --release` succeeds and the built app opens
  `outline.pdf` and runs.
- **Not verified:** everything on Windows. The Linux app was driven with in-Flutter key events only.

## Follow-up: D1, D3, D5, D6, D7 (2026-10-14, Windows session)

Branches off `feat/windows-port`, each merged `--no-ff`: `fix/test-profile-path-separator`, `fix/d1-quit-crash`,
`fix/d3-load-error-and-back`, `fix/d5-window-fit-work-area`, `fix/d6-d7-branding-and-uninstall`,
`fix/d1b-shutdown-timing`. First time the toolchain (Flutter 3.47.7, VS Build Tools 17.14, Inno Setup 6.7.3) and
the test suite ran on Windows.

- **Test suite on Windows:** 154/155 before (a `/` literal in an expected profile path), 155/155 after; now 170.
- **D1** — root cause found with a debug build and a native trace: the runner sends `WM_CLOSE` to `DestroyWindow`
  (47 ms to `WM_DESTROY`) and the engine never sends an exit request, so `onExitRequested` never ran and the
  WebView2 environment was destroyed inside `FlutterWindow::OnDestroy()`, which faulted. Fix: the runner defers
  `WM_CLOSE`, calls `prepareToClose` on `dndreader/lifecycle`, and closes on Dart's reply or a 6 s backstop;
  `lib/services/app_shutdown.dart` runs registered hooks (4 s cap). **Verified** on debug and release: three quit
  paths, no Application Error event, nothing left. **Not eliminated:** a quit with a heavy live page was 2.5–8 s
  in 3 of 11 release runs (profile delete retrying while WebView2 exits); the launch sweep recovers it.
- **D3** — real status `WebErrorStatus.unknown` for a superseded challenge navigation. View pairs an error with its
  own `NavigationCompleted`; session holds ambiguous errors 5 s, recovers from `failed`, ignores `__cf_chl_*`
  hops, and Back reloads our previous page when the browser says it cannot go back.
- **D5** — `FitToWorkArea` (header-only, 184 checks in `windows/runner/test/`, run by `windows.yml`).
- **D6/D7** — brand icon from `packaging/linux/deb/dndreader.svg`, names, publisher; whole
  `Applications\dndreader.exe` key and user data removed on uninstall (decision recorded in the commit).
- **Method notes:** `flutter run -d windows --debug` with its log captured; synthetic input via
  `docs/windows-verification/tools/input-helpers.ps1`; dead-proxy runs use `WEBVIEW2_ADDITIONAL_BROWSER_ARGUMENTS`
  so no query reaches Google.

## Follow-up: Linux regression pass on the Windows port's shared changes (2026-10-14, Ubuntu)

Details and evidence: `docs/windows-verification/REPORT.md` §9.

- **A real regression was found and fixed:** the D3 "recover from failed on load-end" rule turned a CEF load
  failure into a successful load (CEF raises a load-end for the failed URL right after the error). Reproduced
  offline on the real Linux app; fixed by `FailedLoadEndFilter` in the CEF view (`fix/linux-failed-load-end`).
- Verified on the real Linux app: search, Back tracking, Open in browser (opener injected), scroll unchanged on
  close, offline failure shown in 723 ms and recovered by Retry, clean quit in 0.3 s, no search data on disk.
- The Back divergence (Windows: webview history; Linux: session list + `goBack()`) is **deliberate**; not
  reproduced on Linux.
- Tests 170 → 173. `dart format`, `flutter analyze` clean; `flutter build linux --release` succeeds.
- **Not verified:** the sandboxed path (needs root for AppArmor), real disconnect, real link clicks, the
  Cloudflare gate on Linux, everything on Windows.

## Linux release candidate 0.2.0 (2026-10-14, branch `release/0.2.0-rc`, Ubuntu)

Version bumped 0.1.5 → 0.2.0; `.deb` built (341,599,198 B, `Depends:` unchanged vs 0.1.5). Fail-closed,
sandbox-on, offline, Back, scroll, quit and on-disk-residue checks run on the real app (debug build; release
cannot be driven here) — see `docs/windows-verification/REPORT.md` §10 and
`docs/linux-0.2.0-release-checklist.md`. One small fix: no `WebviewManager().quit()` when CEF never started.
**Not verified:** the installed package and its AppArmor profile (needs the owner's `sudo`).

## Pre-merge cleanup (2026-10-14)

Before merging the Windows port to `main`: removed all verification screenshots and their references (the repo
is public; some captures showed desktop context); removed local filesystem paths from the Windows plan;
rewrote the 20 commits that carried a personal e-mail address in their metadata to the project's GitHub
no-reply identity, and dropped the screenshots from history, so neither enters `main`; refreshed stale status
text (README Windows row, both plans, completion report banner); added `docs/README.md` (index) and
`docs/windows-owner-test.md`; added `main` to the CI triggers.
