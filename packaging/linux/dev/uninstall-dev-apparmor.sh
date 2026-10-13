#!/usr/bin/env bash
# Removes the development AppArmor profile installed by install-dev-apparmor.sh.
# REQUIRES ROOT:  sudo packaging/linux/dev/uninstall-dev-apparmor.sh
set -euo pipefail
if [[ $EUID -ne 0 ]]; then
  echo "This script must run as root." >&2
  exit 1
fi
target="/etc/apparmor.d/dndreader-dev"
if [[ -f "$target" ]]; then
  apparmor_parser -R "$target" || true
  rm -f "$target"
  echo "Removed $target"
else
  echo "Nothing to remove ($target not present)."
fi
