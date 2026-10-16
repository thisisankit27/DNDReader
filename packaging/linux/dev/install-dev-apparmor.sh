#!/usr/bin/env bash
# Installs an AppArmor profile that lets a *development build* of DNDReader create
# user namespaces, so its browser sandbox can start on Ubuntu 24.04+.
#
#   sudo packaging/linux/dev/install-dev-apparmor.sh [BUNDLE_DIR]
#
# BUNDLE_DIR defaults to build/linux/x64/release/bundle (relative to the repo).
# REQUIRES ROOT. Review before running. It does exactly three things:
#   1. writes  /etc/apparmor.d/dndreader-dev      (a profile for BUNDLE_DIR/dndreader)
#   2. loads it with apparmor_parser -r
#   3. prints how to verify
# Undo with:  sudo packaging/linux/dev/uninstall-dev-apparmor.sh
#
# Rebuilding does not require re-running this: the profile is bound to the path.
set -euo pipefail

if [[ $EUID -ne 0 ]]; then
  echo "This script must run as root (it writes /etc/apparmor.d and loads a profile)." >&2
  echo "Review it, then: sudo $0 ${1:-}" >&2
  exit 1
fi

here="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
repo="$(cd "$here/../../.." && pwd)"
bundle="$(readlink -f "${1:-$repo/build/linux/x64/release/bundle}")"
exe="$bundle/dndreader"
profile="dndreader-dev"
target="/etc/apparmor.d/$profile"

if [[ ! -x "$exe" ]]; then
  echo "No executable at $exe — build first (flutter build linux --release)." >&2
  exit 1
fi
# AppArmor treats these characters in a path as pattern syntax / quoting.
if [[ "$exe" =~ [\*\?\[\]\{\}\^\"\\,] || "$exe" == *$'\n'* ]]; then
  echo "Refusing: the path contains characters AppArmor treats as patterns: $exe" >&2
  exit 1
fi
command -v apparmor_parser >/dev/null || { echo "apparmor_parser not found." >&2; exit 1; }

tmp="$(mktemp)"
trap 'rm -f "$tmp"' EXIT
cat >"$tmp" <<PROFILE
# Development profile for DNDReader — installed by install-dev-apparmor.sh.
# abi/4.0, not abi/5.0: see the comment in packaging/linux/apparmor/dndreader
# (the shipped profile this mirrors) — userns rules need 4.0, nothing here
# needs 5.0, and 4.0 is what Ubuntu 24.04 actually has.
abi <abi/4.0>,
include <tunables/global>

# Declared for the same reason as in the shipped profile: AppArmor 4.x rejects an
# undeclared @{exec_path}, and 4.x is what Ubuntu 24.04 ships.
@{exec_path} = "$exe"

profile $profile @{exec_path} flags=(unconfined) {
  userns,
  @{exec_path} mr,
}
PROFILE

# Validate before touching /etc.
apparmor_parser -Q -K -o /dev/null "$tmp"

install -m 0644 "$tmp" "$target"
apparmor_parser -r "$target"

cat <<MSG
Installed $target for:
  $exe

Verify (as your normal user, from a normal terminal — not a snap-confined one):
  systemd-run --user --collect --unit=dndreader-check "$exe" &
  # then, while it runs and a PDF is open, each renderer should show:
  #   grep -E 'Seccomp|NoNewPrivs' /proc/<renderer-pid>/status      # Seccomp: 2
  cat /proc/\$(pgrep -nx dndreader)/attr/current                    # dndreader-dev (unconfined)

Remove with: sudo $here/uninstall-dev-apparmor.sh
MSG
