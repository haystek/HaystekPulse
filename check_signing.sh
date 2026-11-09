#!/bin/bash
# Checks which key signed the Android builds.
#   dev  builds must use the debug key (never the Play Store key)
#   prod builds must use the Play Store upload key
#
#   ./check_signing.sh              check every build found
#   ./check_signing.sh dev apk      check one build (build.sh does this)
cd "$(dirname "$0")"

norm() { tr -d ':' | tr 'A-F' 'a-f'; }

PW=$(grep '^storePassword=' android/key.properties 2>/dev/null | cut -d= -f2-)
ALIAS=$(grep '^keyAlias=' android/key.properties 2>/dev/null | cut -d= -f2-)
UPLOAD=$(keytool -list -v -keystore android/app/upload-keystore.jks -alias "${ALIAS:-upload}" -storepass "$PW" 2>/dev/null | awk '/SHA256:/{print $2; exit}' | norm)
DEBUG=$(keytool -list -v -keystore "$HOME/.android/debug.keystore" -alias androiddebugkey -storepass android 2>/dev/null | awk '/SHA256:/{print $2; exit}' | norm)
[ -n "$UPLOAD" ] || { echo "STOP: cannot read the upload key (android/app/upload-keystore.jks)"; exit 1; }
[ -n "$DEBUG" ] || { echo "STOP: cannot read the debug key (~/.android/debug.keystore)"; exit 1; }

SDK="${ANDROID_HOME:-$HOME/Library/Android/sdk}"
APKSIGNER=$(ls "$SDK"/build-tools/*/apksigner 2>/dev/null | sort -V | tail -1)

signer_of() {
  case "$1" in
    *.apk)
      [ -n "$APKSIGNER" ] || { echo "no-apksigner"; return; }
      "$APKSIGNER" verify --print-certs "$1" 2>/dev/null | awk -F': ' '/SHA-256 digest/{print $NF; exit}' | norm ;;
    *.aab)
      keytool -printcert -jarfile "$1" 2>/dev/null | awk '/SHA256:/{print $2; exit}' | norm ;;
  esac
}

FAIL=0; FOUND=0
check() {
  local env="$1" file="$2"
  [ -f "$file" ] || return 0
  FOUND=1
  local fp; fp=$(signer_of "$file")
  local who="UNKNOWN key"
  [ "$fp" = "$DEBUG" ] && who="debug key"
  [ "$fp" = "$UPLOAD" ] && who="Play Store upload key"
  [ "$fp" = "no-apksigner" ] && who="(apksigner not found, cannot check APK)"
  local want="debug key"; [ "$env" = "prod" ] && want="Play Store upload key"
  if [ "$who" = "$want" ]; then
    echo "PASS  $env  $(basename "$file")  -> $who"
  else
    echo "FAIL  $env  $(basename "$file")  -> $who (must be: $want)"
    FAIL=1
  fi
}

OUT=build/app/outputs
apk()    { echo "$OUT/flutter-apk/app-$1-release.apk"; }
bundle() { echo "$OUT/bundle/$1Release/app-$1-release.aab"; }

if [ -n "$1" ]; then
  case "$2" in
    apk) check "$1" "$(apk "$1")" ;;
    appbundle) check "$1" "$(bundle "$1")" ;;
    *) echo "Use: ./check_signing.sh [dev|prod apk|appbundle]"; exit 1 ;;
  esac
else
  for e in dev prod; do check "$e" "$(apk "$e")"; check "$e" "$(bundle "$e")"; done
fi

[ "$FOUND" = 1 ] || { echo "No release builds found. Build first: ./build.sh dev apk"; exit 1; }
exit $FAIL
