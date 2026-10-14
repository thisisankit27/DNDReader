#!/usr/bin/env bash
# Builds dist/dndreader_<version>_amd64.deb from a release bundle.
#
#   packaging/linux/build-deb.sh            # uses build/linux/x64/release/bundle
#   BUNDLE=/path/to/bundle packaging/linux/build-deb.sh
#
# Needs no root. The package ships:
#   /usr/lib/dndreader/…            the Flutter bundle (CEF included)
#   /usr/bin/dndreader              symlink to the binary
#   /etc/apparmor.d/dndreader       profile bound to /usr/lib/dndreader/dndreader
#   /usr/share/doc/dndreader/…      licences and the fork's HARDENING.md
# chrome-sandbox (the SUID helper) is deliberately NOT shipped: the sandbox is
# Chromium's namespace sandbox, enabled by the AppArmor profile.
set -euo pipefail

repo="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
bundle="${BUNDLE:-$repo/build/linux/x64/release/bundle}"
version="$(sed -n "s/^const String kAppVersion = '\(.*\)';/\1/p" "$repo/lib/build_info.dart")"
[ -n "$version" ] || { echo "cannot read kAppVersion" >&2; exit 1; }
arch=amd64
out="$repo/dist"
stage="$(mktemp -d)"
trap 'rm -rf "$stage"' EXIT

[ -x "$bundle/dndreader" ] || { echo "no release bundle at $bundle (run: flutter build linux --release)" >&2; exit 1; }

# Where CEF's own licence files live: the webview_cef package the app was built with.
plugin="$(readlink -f "$repo/linux/flutter/ephemeral/.plugin_symlinks/webview_cef")"
cef_license="$plugin/third/cef/LICENSE.txt"
cef_credits="$plugin/third/cef/CREDITS.html"
for f in "$cef_license" "$cef_credits" "$plugin/LICENSE" "$plugin/HARDENING.md"; do
  [ -f "$f" ] || { echo "missing licence/notice file: $f" >&2; exit 1; }
done

root="$stage/pkg"
lib="$root/usr/lib/dndreader"
doc="$root/usr/share/doc/dndreader"
install -d "$lib" "$doc/cef" "$root/usr/bin" "$root/etc/apparmor.d" \
  "$root/usr/share/applications" "$root/usr/share/icons/hicolor/scalable/apps" "$root/DEBIAN"

# The bundle, minus the SUID helper.
cp -a "$bundle"/. "$lib"/
rm -f "$lib/lib/chrome-sandbox"
ln -s /usr/lib/dndreader/dndreader "$root/usr/bin/dndreader"

install -m 0644 "$repo/packaging/linux/apparmor/dndreader" "$root/etc/apparmor.d/dndreader"
install -m 0644 "$repo/packaging/linux/deb/dndreader.desktop" "$root/usr/share/applications/dndreader.desktop"
install -m 0644 "$repo/packaging/linux/deb/dndreader.svg" "$root/usr/share/icons/hicolor/scalable/apps/dndreader.svg"

# Licences. Apache-2.0 §4: keep the licence; HARDENING.md is the modified-files notice.
if [ -f "$repo/LICENSE" ]; then
  install -m 0644 "$repo/LICENSE" "$doc/LICENSE"
  own_license="DNDReader itself is licensed as described in /usr/share/doc/dndreader/LICENSE."
else
  own_license="DNDReader's own licence has not been chosen by the project owner yet; no licence is granted by this package beyond the bundled components' own terms."
fi
install -m 0644 "$plugin/LICENSE" "$doc/webview_cef.LICENSE"
install -m 0644 "$plugin/HARDENING.md" "$doc/HARDENING.md"
install -m 0644 "$cef_license" "$doc/cef/LICENSE.txt"
install -m 0644 "$cef_credits" "$doc/cef/CREDITS.html"
cat >"$doc/copyright" <<COPY
DNDReader $version

$own_license

Bundled components
  - Chromium Embedded Framework / Chromium: BSD-style and many third-party
    licences, see /usr/share/doc/dndreader/cef/LICENSE.txt and
    /usr/share/doc/dndreader/cef/CREDITS.html.
  - webview_cef (Apache-2.0), modified: /usr/share/doc/dndreader/webview_cef.LICENSE
    and the list of modifications in /usr/share/doc/dndreader/HARDENING.md.
  - PDFium (BSD-3-Clause-style) via the pdfrx package, and the Flutter engine and
    framework (BSD-3-Clause): their licences are listed in the application under
    Menu > About DNDReader > View licenses.
COPY

# Dependencies: shared libraries not provided by the bundle itself, mapped to packages.
mapfile -t objs < <(find "$lib" -type f \( -name '*.so' -o -name '*.so.*' -o -name dndreader \))
declare -A bundled=()
for o in "${objs[@]}"; do bundled["$(basename "$o")"]=1; done
deps="$(
  for o in "${objs[@]}"; do ldd "$o" 2>/dev/null; done |
    awk '/=> \//{print $1, $3}' | sort -u |
    while read -r name path; do
      [ -n "${bundled[$name]:-}" ] && continue
      dpkg -S "$(readlink -f "$path")" 2>/dev/null | head -1 | cut -d: -f1
    done | sort -u | paste -sd, - | sed 's/,/, /g'
)"
[ -n "$deps" ] || { echo "could not derive dependencies" >&2; exit 1; }
# Not visible to ldd: libraries the runtime dlopen()s (libepoxy -> libEGL.so.1,
# found missing by the clean-container smoke start), the paste helper and the
# AppArmor tooling the profile needs.
deps="$deps, libegl1, libgles2, xclip, apparmor"

size_kb="$(du -sk "$root" | cut -f1)"
cat >"$root/DEBIAN/control" <<CTRL
Package: dndreader
Version: $version-1
Section: text
Priority: optional
Architecture: $arch
Maintainer: thisisankit27 <thisisankit27@users.noreply.github.com>
Installed-Size: $size_kb
Depends: $deps
Homepage: https://github.com/thisisankit27/DNDReader
Description: Minimal PDF reader with a "Find meaning" action
 Read a PDF, select text, and see Google Search results in a side panel.
 No account, no telemetry. Bundles Chromium (CEF) for the panel and needs the
 AppArmor profile installed with this package for the browser sandbox.
CTRL
install -m 0755 "$repo/packaging/linux/deb/postinst" "$root/DEBIAN/postinst"
install -m 0755 "$repo/packaging/linux/deb/prerm" "$root/DEBIAN/prerm"
echo /etc/apparmor.d/dndreader >"$root/DEBIAN/conffiles"

find "$root" -type d -exec chmod 0755 {} +
mkdir -p "$out"
deb="$out/dndreader_${version}-1_${arch}.deb"
fakeroot dpkg-deb -Zzstd -z3 --build "$root" "$deb" >/dev/null
echo "built $deb ($(du -h "$deb" | cut -f1))"
echo "Depends: $deps"
