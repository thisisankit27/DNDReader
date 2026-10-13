# DNDReader — Progress

Source of truth for the plan is `docs/implementation-plan.md`. This file records what was
**observed**, not what was intended. Where something was not performed it says so.

| Milestone | Status |
|---|---|
| P0 Planning | Done (`da3813a`) |
| M0 Feasibility spike | **Done 2026-10-13** — see below. Checks 1, 2, 5, 7 observed; 3 and 4 have evidence but the judgement is the owner's; 6 partly observed (no interstitial appeared). |
| Security investigation | **Done 2026-10-13/14** — see "Security investigation" below. Decisions logged. |
| M1 Shell | Pending |
| M2 PDF reading (+ §5.1.1 gates 1–2) | Pending |
| M3 Selection → action (+ gate 3) | Pending |
| M0b Hardened fork | Pending — runs **after M3's gates clear**, before M4 |
| M4 Embedded search panel (+ GPU spike) | Pending |
| M5 Polish | Pending |
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
