#!/bin/bash
# Build the app.
#   ./build.sh dev  apk          test APK for Android (dev database)
#   ./build.sh prod appbundle    Play Store file (live, asks PROD)
#   ./build.sh prod apk          live APK (asks PROD)
#   ./build.sh dev|prod ios      iPhone build (after Apple account setup)
set -e
cd "$(dirname "$0")"
ENV="$1"; KIND="${2:-apk}"
case "$ENV" in dev|prod) ;; *) echo "Use: ./build.sh dev|prod apk|appbundle|ios"; exit 1 ;; esac
if [ "$ENV" = "prod" ]; then
  printf "\n\033[1;41m  LIVE BUILD: uses the real database  \033[0m\n"
  read -r -p "Type PROD to build for LIVE: " ANS
  [ "$ANS" = "PROD" ] || { echo "Cancelled."; exit 1; }
fi
case "$KIND" in
  apk)       flutter build apk --flavor "$ENV" --release ;;
  appbundle) flutter build appbundle --flavor "$ENV" --release ;;
  ios)       flutter build ipa --flavor "$ENV" --release ;;
  *) echo "Unknown: $KIND (use apk, appbundle or ios)"; exit 1 ;;
esac
echo "Built: $KIND ($ENV)"
