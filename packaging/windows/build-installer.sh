#!/usr/bin/env bash
# Builds dist/DNDReader-<version>-setup-x64.exe from a Flutter Windows release bundle.
#
#   packaging/windows/build-installer.sh     # bundle: build/windows/x64/runner/Release
#   BUNDLE=... BOOTSTRAPPER=... ISCC=... packaging/windows/build-installer.sh
#
# Run from Git Bash (as CI does) with Inno Setup 6.3+ installed. The version is
# read from lib/build_info.dart exactly as packaging/linux/build-deb.sh reads
# it, so the two cannot drift.
#
# MicrosoftEdgeWebview2Setup.exe is Microsoft's ~2 MB Evergreen bootstrapper.
# Microsoft permits packaging it with an app; it is fetched by CI from
# https://go.microsoft.com/fwlink/p/?LinkId=2124703 and its Authenticode
# signature is checked there. Never commit it.
set -euo pipefail

repo="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
bundle="${BUNDLE:-$repo/build/windows/x64/runner/Release}"
bootstrapper="${BOOTSTRAPPER:-$repo/packaging/windows/MicrosoftEdgeWebview2Setup.exe}"
version="$(sed -n "s/^const String kAppVersion = '\(.*\)';/\1/p" "$repo/lib/build_info.dart")"
[ -n "$version" ] || { echo "cannot read kAppVersion" >&2; exit 1; }
out="$repo/dist"

[ -f "$bundle/dndreader.exe" ] || { echo "no release bundle at $bundle (run: flutter build windows --release)" >&2; exit 1; }
[ -f "$bootstrapper" ] || { echo "missing WebView2 bootstrapper: $bootstrapper" >&2; exit 1; }

iscc="${ISCC:-}"
if [ -z "$iscc" ]; then
  if command -v iscc >/dev/null 2>&1; then
    iscc="iscc"
  elif [ -x "/c/Program Files (x86)/Inno Setup 6/ISCC.exe" ]; then
    iscc="/c/Program Files (x86)/Inno Setup 6/ISCC.exe"
  else
    echo "Inno Setup compiler (ISCC.exe) not found" >&2; exit 1
  fi
fi

# Third-party licence notices shipped beside the app. BSD-3 requires the
# copyright notice to accompany binary redistribution.
stage="$(mktemp -d)"
trap 'rm -rf "$stage"' EXIT
lic="$stage/licenses"
mkdir -p "$lic"
plugin="$repo/windows/flutter/ephemeral/.plugin_symlinks/webview_flutter_windows"
[ -f "$plugin/LICENSE" ] || { echo "missing $plugin/LICENSE (run flutter build windows first)" >&2; exit 1; }
cp "$plugin/LICENSE" "$lic/webview_flutter_windows-LICENSE.txt"
cat > "$lic/README.txt" <<'TXT'
Third-party notices

webview_flutter_windows-LICENSE.txt   BSD-3-Clause, the WebView2 plugin
Flutter, pdfrx, PDFium and the other packages' licences are listed in the app:
Menu > About DNDReader > View licenses.
The Microsoft Edge WebView2 Runtime is Microsoft's and is not part of this package.
TXT

mkdir -p "$out"
# MSYS_NO_PATHCONV: stop Git Bash rewriting the /D switches into paths.
MSYS_NO_PATHCONV=1 "$iscc" \
  "/DAppVersion=$version" \
  "/DBundleDir=$(cygpath -w "$bundle" 2>/dev/null || echo "$bundle")" \
  "/DOutputDir=$(cygpath -w "$out" 2>/dev/null || echo "$out")" \
  "/DBootstrapper=$(cygpath -w "$bootstrapper" 2>/dev/null || echo "$bootstrapper")" \
  "/DLicensesDir=$(cygpath -w "$lic" 2>/dev/null || echo "$lic")" \
  "$(cygpath -w "$repo/packaging/windows/dndreader.iss" 2>/dev/null || echo "$repo/packaging/windows/dndreader.iss")"

echo "built: $out/DNDReader-$version-setup-x64.exe"
