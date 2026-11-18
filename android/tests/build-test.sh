#!/usr/bin/env bash
set -euo pipefail
if [[ $# -ne 7 ]]; then
  echo "Usage: $0 JDK_HOME BUILD_TOOLS_DIR ANDROID_JAR ANDROID_SOURCE_DIR KEYSTORE KEY_ALIAS OUTPUT_APK"
  exit 64
fi
export JAVA_HOME="$(realpath "$1")"
export PATH="$JAVA_HOME/bin:$PATH"
bt="$(realpath "$2")"; sdk="$(realpath "$3")"; root="$(realpath "$4")"; ks="$(realpath "$5")"; alias="$6"; apk="$(realpath -m "$7")"
temp="$(mktemp -d)"; trap 'rm -rf -- "$temp"' EXIT
mkdir -p "$temp/classes" "$temp/dex" "$temp/java"
"$bt/aapt2" compile --dir "$root/res" -o "$temp/r.zip"
"$bt/aapt2" link -I "$sdk" --manifest "$root/AndroidManifest.xml" --java "$temp/java" -o "$temp/unused.apk" "$temp/r.zip"
find "$root/src" "$temp/java" "$root/tests/Smoke.java" -name '*.java' -print0 | xargs -0 javac -encoding UTF-8 -source 8 -target 8 -classpath "$sdk" -d "$temp/classes"
"$bt/aapt2" link -I "$sdk" --manifest "$root/tests/AndroidManifest.xml" -o "$temp/test.apk"
"$bt/d8" --lib "$sdk" --min-api 29 --output "$temp/dex" "$temp/classes/com/bggg/simplepyrate/Smoke.class" "$temp/classes/com/bggg/simplepyrate/Smoke\$1.class"
zip -q -j "$temp/test.apk" "$temp/dex/classes.dex"
"$bt/zipalign" -f 4 "$temp/test.apk" "$temp/aligned.apk"
if [[ -v PYRATE_KEYPASS_FILE ]]; then set -- --ks-pass "file:$PYRATE_KEYPASS_FILE"; else set --; fi
"$bt/apksigner" sign --ks "$ks" --ks-key-alias "$alias" --v4-signing-enabled false "$@" --out "$apk" "$temp/aligned.apk"
