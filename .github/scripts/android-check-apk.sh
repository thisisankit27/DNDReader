#!/usr/bin/env bash
# Gates for a release APK of one ABI (arm64-v8a): what it contains, how big it is, whether it is safe on
# 16 KB-page devices. Fails loudly; prints what it checked so the log is evidence, not a green tick.
#
#   android-check-apk.sh <apk> <max-size-bytes>
set -euo pipefail

apk=${1:?apk}
max=${2:?max size in bytes}
sdk=${ANDROID_HOME:-${ANDROID_SDK_ROOT:-$HOME/Android/Sdk}}

fail() { echo "FAIL: $*" >&2; exit 1; }

# 1. Size budget (the APK file; Play's download size is smaller because it compresses the stored libraries).
size=$(stat -c %s "$apk")
echo "size: $size bytes (budget $max)"
[ "$size" -le "$max" ] || fail "APK is $size bytes, over the $max budget"

# 2. Native libraries: exactly the expected set. Nothing CEF-, WebView2- or Chromium-shaped may ship: the
#    system WebView is already on the phone.
mapfile -t libs < <(unzip -Z1 "$apk" | grep '^lib/' | sort)
printf 'native libraries:\n'; printf '  %s\n' "${libs[@]}"
for l in "${libs[@]}"; do
  case "$l" in
    *cef*|*CEF*|*webview2*|*WebView2*|*chromium*) fail "unexpected browser engine library: $l" ;;
  esac
done
expected=$'lib/arm64-v8a/libapp.so\nlib/arm64-v8a/libdartjni.so\nlib/arm64-v8a/libdatastore_shared_counter.so\nlib/arm64-v8a/libflutter.so\nlib/arm64-v8a/libpdfium.so'
actual=$(printf '%s\n' "${libs[@]}")
[ "$actual" = "$expected" ] || fail $'the native library set changed; expected:\n'"$expected"$'\ngot:\n'"$actual"$'\nReview the new library (size, licence, alignment) and update this list on purpose.'

# 3. 16 KB page size: every LOAD segment aligned to at least 0x4000, and stored libraries zip-aligned to 16 KB.
tmp=$(mktemp -d); trap 'rm -rf "$tmp"' EXIT
unzip -q "$apk" 'lib/*' -d "$tmp"
for so in "$tmp"/lib/*/*.so; do
  while read -r align; do
    [ $((align)) -ge $((0x4000)) ] || fail "$(basename "$so") has a LOAD segment aligned to $align (< 0x4000)"
  done < <(readelf -lW "$so" | awk '$1=="LOAD"{print $NF}')
  echo "  16 KB ELF alignment ok: $(basename "$so")"
done
zipalign=$(ls "$sdk"/build-tools/*/zipalign 2>/dev/null | sort -V | tail -1 || true)
if [ -n "$zipalign" ]; then
  "$zipalign" -c -P 16 -v 4 "$apk" | grep -E 'lib/.*\.so|Verification' | sed 's/^/  /'
  "$zipalign" -c -P 16 4 "$apk" || fail "stored libraries are not 16 KB zip-aligned"
else
  echo "  (zipalign not found; zip alignment not checked)"
fi

# 4. Permissions: INTERNET only (an owner decision; a new one is a one-way door). The one other name in the
#    merged manifest, <applicationId>.DYNAMIC_RECEIVER_NOT_EXPORTED_PERMISSION, is declared by AndroidX for the app's
#    own broadcast receivers (signature-protected, grants nothing to anyone else); it is allowed by exact name.
aapt2=$(ls "$sdk"/build-tools/*/aapt2 2>/dev/null | sort -V | tail -1 || true)
[ -n "$aapt2" ] || fail "aapt2 not found under $sdk/build-tools"
pkg=$("$aapt2" dump packagename "$apk")
perms=$("$aapt2" dump permissions "$apk" | grep -E '^uses-permission' | sed -E "s/.*name='([^']+)'.*/\1/" \
  | grep -vxF "$pkg.DYNAMIC_RECEIVER_NOT_EXPORTED_PERMISSION" | sort)
echo "permissions (besides AndroidX's own $pkg.DYNAMIC_RECEIVER_NOT_EXPORTED_PERMISSION):"; printf '  %s\n' $perms
[ "$perms" = "android.permission.INTERNET" ] || fail "permissions are not exactly INTERNET: $perms"

echo "OK"
