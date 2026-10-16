# DNDReader 0.2.2 — Linux owner checklist (needs a real install)

Package: `dist/dndreader_0.2.2-1_amd64.deb` — 341,562,916 bytes (≈ 326 MiB), sha256
`b759d3c01e5c55887262ef94c8719caca60c89852272c16f3788a0aa62ba2de5`, built from branch
`fix/gnome50-xsettings-crash`. `dist/` is git-ignored: the file exists on this machine only.

**Why this release exists.** Two fixes to 0.2.1, both read-only/analysis-confirmed, neither needing
anything from you to have caused a problem on your machine specifically:

1. **0.2.1's `GTK_USE_PORTAL=1` was unconditional.** It only needs to be set when GDK's
   Wayland-only xsettings fallback would actually crash (docs/progress.md, 0.2.1's entry); setting
   it always also changes which dialogs (file chooser, print, app chooser) go through the desktop
   portal everywhere, including on X11 sessions this bug can't occur on. 0.2.2 checks the actual
   broken condition at startup (`g_settings_schema_has_key` on `org.gnome.settings-daemon.plugins.xsettings`)
   and only sets the variable then. On this machine the condition is still true, so nothing about
   your day-to-day experience should change — the point is narrowing the blast radius for systems
   that never had the crash, not changing behaviour on this one.
2. **The AppArmor profile's `abi <abi/5.0>,` pin doesn't exist on Ubuntu 24.04**, or on GitHub's own
   `ubuntu-latest` CI runner (verified there: `apparmor_parser` refused the profile outright, "Could
   not open 'abi/5.0'", so the sandbox could never start). Repinned to `abi <abi/4.0>,` — the lowest
   ABI that has the `userns` rule this profile actually uses, present on 24.04 and on this machine
   (26.04) alike.

**`/etc/apparmor.d/dndreader` is a conffile, and its content changed this time** (abi/4.0 replaces
abi/5.0) — unlike 0.2.1, which shipped a byte-identical profile to 0.2.0. If `apt`/`dpkg` asks
whether to keep your currently-installed version or install the package's, **take the new one**
(usually the default, `Y`/install the package maintainer's version) — keeping the old 0.2.1 profile
would silently keep the `abi/5.0` pin this release exists to fix.

1. **Install.** `sudo apt install ./dist/dndreader_0.2.2-1_amd64.deb`. Expect no dependency errors
   (`Depends:` re-derived and diffed against 0.2.1: unchanged, same 89 entries — neither fix touches
   a linked library). Watch for `dndreader: could not load /etc/apparmor.d/dndreader` — if you see
   it, `apparmor_parser --version` and `ls /etc/apparmor.d/abi/4.0` on your system, since that would
   mean even 4.0 isn't available, a configuration older than this profile now assumes.
2. **Launch from the app menu**, and once by `dndreader ~/…/some.pdf` from a terminal. Menu → About
   must say version **0.2.2**.
3. **The sandbox is active.** Open a PDF, select a word, press `Ctrl+E`, wait for results, then in a
   terminal: `packaging/linux/verify-sandbox.sh`. Expect `AppArmor label: dndreader (unconfined)`,
   ≥ 1 renderer, each `Seccomp: 2`, and `PASS`.
4. **Search through the installed app**: results load; click a result; Back; Open in browser; close
   the panel and the page is where you left it. (Unchanged from 0.2.1 — re-checking only because the
   AppArmor profile text changed, and this is the thing that profile gates.)
5. **Clean quit**: close the window with the X; `pgrep -x dndreader` prints nothing afterward.
6. **Upgrade**: settings (recent files, theme, zoom) should survive installing over 0.2.1.

Not covered by anyone: a GNOME version other than 50; a desktop with no
`org.freedesktop.portal.Settings` implementation at all (the narrower condition means this matters
even less than in 0.2.1, but still untested); an X11 session on a system whose
`gnome-settings-daemon` package also lacks the `antialiasing` key (the fix does not additionally
check the Wayland-vs-X11 backend — see the comment in `linux/runner/main.cc` for why — so
`GTK_USE_PORTAL` would still be set there, harmlessly but unnecessarily); Windows (unaffected by
either fix; unchanged in this release).
