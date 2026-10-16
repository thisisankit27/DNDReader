# DNDReader 0.2.1 — Linux owner checklist (needs a real install)

Package: `dist/dndreader_0.2.1-1_amd64.deb` — 341,593,482 bytes (≈ 326 MiB), sha256
`6a7a30220a10f07ea07498028c48b5255d318e919fa42159fababb4edf99ee9a`, built from branch
`fix/gnome50-xsettings-crash`. `dist/` is git-ignored: the file exists on this machine only.

**Why this release exists.** 0.2.0 (and a freshly built 0.2.0 bundle) abort immediately on this
machine with `GLib-GIO-ERROR: Settings schema 'org.gnome.settings-daemon.plugins.xsettings' does
not contain a key named 'antialiasing'` — a GNOME 50 incompatibility in GTK3 itself (details:
`docs/progress.md`, dated entry for this fix), not something in DNDReader's own code. 0.2.1's only
change is `linux/runner/main.cc` setting `GTK_USE_PORTAL=1` before GTK initialises, which steers
GDK past the broken code path. Everything else — the `Depends:` list, the AppArmor profile, the
`.desktop` entry — is byte-for-byte identical to 0.2.0 (`Depends:` diffed with `dpkg-deb -f`, zero
differences across all 89 entries).

Only what could **not** be verified without root and an installed package. Everything else —
including the crash itself, this fix, and a real reading pass through the actual Linux app with the
search panel — was verified against an **unpackaged** release build and the **extracted** package
contents (not the installed, apt-registered package) on this machine; see `docs/progress.md` for
exactly what and how.

1. **If 0.2.0 is currently installed, confirm you can reproduce the crash first** (so you know this
   release actually fixes something on your system, not just on the build machine):
   `dndreader` from a terminal should print the `GLib-GIO-ERROR ... 'antialiasing'` line and exit
   with signal ABRT. If it does **not** crash, your system's `gnome-settings-daemon` likely still
   has the key DNDReader 0.2.0 expects, and 0.2.1 is not something you need (though it should still
   be a safe, side-effect-free install).
2. **Install.** `sudo apt install ./dist/dndreader_0.2.1-1_amd64.deb`. Expect no dependency errors
   (the `Depends:` list is unchanged from 0.2.0). Watch for `dndreader: could not load
   /etc/apparmor.d/dndreader` — that line means step 4 will fail.
3. **Launch from the app menu**, and once by `dndreader ~/…/some.pdf` from a terminal. Neither
   should print the GLib-GIO-ERROR line or crash. Menu → About must say version **0.2.1** and `CEF
   149.0.4 (Chromium 149.0.7827.156)` (the CEF version is unchanged).
4. **The sandbox is active.** Open a PDF, select a word, press `Ctrl+E`, wait for results, then in a
   terminal: `packaging/linux/verify-sandbox.sh`. Expect `AppArmor label: dndreader (unconfined)`,
   ≥ 1 renderer, each `Seccomp: 2`, and `PASS`. If the panel instead says "Search can't run inside
   DNDReader here", the profile did not load: `sudo apparmor_parser -r -T -W
   /etc/apparmor.d/dndreader` and retry.
5. **Search through the installed app**: results load; click a result; Back (arrow enabled/disabled
   matches what is shown); Open in browser opens your default browser; close the panel and the page
   is where you left it.
6. **Clean quit**: close the window with the X. It should be gone in well under a second;
   `pgrep -x dndreader` prints nothing.
7. **Upgrade**: installing 0.2.1 over 0.2.0 should preserve settings (recent files, theme, zoom);
   `/etc/apparmor.d/dndreader` is a conffile — answer `N` (keep) if dpkg asks (it should be
   byte-identical anyway).

Not covered by anyone: a GNOME version other than 50, a desktop with no
`org.freedesktop.portal.Settings` implementation running at all (this fix's effect there is
untested — see `docs/progress.md`), Wayland-native input, and Windows (unaffected by this bug;
unchanged in this release).
