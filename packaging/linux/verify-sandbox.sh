#!/usr/bin/env bash
# Reports whether the running DNDReader's embedded-browser processes are
# sandboxed. Needs no root. Run it while the search panel is open:
#
#   1. start dndreader, open a PDF, select text, press Ctrl+E
#   2. packaging/linux/verify-sandbox.sh
#
# PASS requires: at least one renderer, each with seccomp mode 2 (filter) and
# its own user, pid and net namespaces (different from the main process).
set -u
main="$(pgrep -x dndreader | head -1 || true)"
[ -n "$main" ] || { echo "dndreader is not running"; exit 2; }
echo "main pid $main   AppArmor label: $(cat /proc/$main/attr/current 2>/dev/null || echo '?')"
echo "kernel.apparmor_restrict_unprivileged_userns=$(sysctl -n kernel.apparmor_restrict_unprivileged_userns 2>/dev/null || echo n/a)"

ns() { readlink "/proc/$1/ns/$2" 2>/dev/null || echo "?"; }
fail=0; renderers=0
while read -r pid; do
  [ -r "/proc/$pid/cmdline" ] || continue
  cmd="$(tr '\0' ' ' <"/proc/$pid/cmdline")"
  case "$cmd" in *--type=renderer*) ;; *) continue;; esac
  renderers=$((renderers + 1))
  seccomp="$(awk '/^Seccomp:/{print $2}' "/proc/$pid/status")"
  same=""
  for n in user pid net; do
    [ "$(ns "$pid" $n)" = "$(ns "$main" $n)" ] && same="$same $n"
  done
  verdict=ok
  if [ "$seccomp" != 2 ] || [ -n "$same" ]; then verdict=FAIL; fail=1; fi
  echo "renderer $pid  seccomp=$seccomp  shares-with-main:[${same# }]  $verdict"
done < <(pgrep -x dndreader)

if [ "$renderers" -eq 0 ]; then
  echo "no renderer processes: the search panel has not been opened, or the sandbox could not start (fail closed)."
  exit 3
fi
[ "$fail" -eq 0 ] && echo "PASS: $renderers renderer(s) sandboxed" || { echo "FAIL: at least one renderer is not sandboxed"; exit 1; }
