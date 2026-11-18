#!/usr/bin/env bash
set -euo pipefail
if (( $# != 7 )); then
  printf '%s\n' "Usage: $0 JDK_HOME BUILD_TOOLS_DIR ANDROID_JAR ANDROID_NATIVE_DIR KEYSTORE KEY_ALIAS OUTPUT_APK" >&2
  exit 2
fi
jdk="$(realpath -- "$1")"
B="$(realpath -- "$2")"
P="$(realpath -- "$3")"
native="$(realpath -- "$4")"
KEY="$(realpath -- "$5")"
ALIAS="$6"
output="$(realpath -m -- "$7")"
if [[ -v PYRATE_KEYPASS_FILE ]]; then
  PYRATE_KEYPASS_FILE="$(realpath -- "$PYRATE_KEYPASS_FILE")"
fi
export JAVA_HOME="$jdk"
export PATH="$jdk/bin:$PATH"
cd -- "$(dirname -- "$0")"
min_api="$(python3 - <<'PY'
from xml.etree import ElementTree
uses_sdk = ElementTree.parse("AndroidManifest.xml").getroot().find("uses-sdk")
value = uses_sdk.get("{http://schemas.android.com/apk/res/android}minSdkVersion", "") if uses_sdk is not None else ""
if not value.isascii() or not value.isdecimal():
    raise SystemExit("Manifest must specify a numeric minSdkVersion")
print(value)
PY
)"
out="$(mktemp -d)"
trap 'rm -rf -- "$out"' EXIT
mkdir -p "$out/classes" "$out/dex" "$out/generated" "$(dirname -- "$output")"

"$B/aapt2" compile --dir res -o "$out/resources.zip"
"$B/aapt2" link -I "$P" --manifest AndroidManifest.xml --java "$out/generated" \
  -A assets -0 wav -0 mp3 -o "$out/base.apk" "$out/resources.zip"
find src "$out/generated" -name '*.java' -print0 |
  sort -z | xargs -0 javac -encoding UTF-8 --release 11 -classpath "$P" -d "$out/classes"
jar --create --file "$out/classes.jar" -C "$out/classes" .
"$B/d8" --release --min-api "$min_api" --lib "$P" --output "$out/dex" "$out/classes.jar"
cp "$out/base.apk" "$out/unaligned.apk"
(
  cd "$out/dex"
  shopt -s nullglob
  dex_files=(classes*.dex)
  (( ${#dex_files[@]} > 0 ))
  zip -q -X ../unaligned.apk "${dex_files[@]}"
)
python3 package.py "$out/unaligned.apk" "$native"
"$B/zipalign" -P 16 -f 4 "$out/unaligned.apk" "$out/aligned.apk"
if [[ -v PYRATE_KEYPASS_FILE ]]; then set -- --ks-pass "file:$PYRATE_KEYPASS_FILE"; else set --; fi
"$B/apksigner" sign --ks "$KEY" --ks-key-alias "$ALIAS" "$@" --v4-signing-enabled false --out "$output" "$out/aligned.apk"

unzip -tq "$output"
"$B/aapt2" dump badging "$output"
"$B/apksigner" verify --min-sdk-version "$min_api" --max-sdk-version 36 --verbose --print-certs "$output"
"$B/zipalign" -c -P 16 4 "$output"
python3 tests/check-dex.py "$output" "$min_api"
"$B/dexdump" -f "$output" > "$out/dexdump.txt"
launcher="$("$B/aapt2" dump badging "$output" | sed -n "s/^launchable-activity: name='\([^']*\)'.*/\1/p")"
[[ -n "$launcher" && "$launcher" != *$'\n'* ]]
descriptor="L$(printf '%s' "$launcher" | tr . /);"
grep -F -m 1 "Class descriptor  : '$descriptor'" "$out/dexdump.txt"
sha256sum "$output"

