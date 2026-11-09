#!/bin/bash
# Deploy rules, functions and pages.
#   ./deploy.sh dev  [all|rules|functions|hosting]
#   ./deploy.sh prod [all|rules|functions|hosting]   (asks you to type PROD)
set -e
cd "$(dirname "$0")"
ENV="$1"; WHAT="${2:-all}"
case "$ENV" in
  dev)  PROJECT=haystek-pulse-dev ;;
  prod) PROJECT=haystek-pulse ;;
  *) echo "Use: ./deploy.sh dev|prod [all|rules|functions|hosting]"; exit 1 ;;
esac
case "$WHAT" in
  all)       ONLY="firestore:rules,functions,hosting" ;;
  rules)     ONLY="firestore:rules" ;;
  functions) ONLY="functions" ;;
  hosting)   ONLY="hosting" ;;
  *) echo "Unknown: $WHAT (use all, rules, functions or hosting)"; exit 1 ;;
esac
if [ "$ENV" = "prod" ]; then
  printf "\n\033[1;41m  LIVE: haystek-pulse (real employees and data)  \033[0m\n"
  if [ -n "$(git status --porcelain)" ]; then
    printf "\033[1;33mYou have changes that are not committed. Live should get only saved work.\033[0m\n"
  fi
  printf "Did you test this on DEV first?\n"
  read -r -p "Type PROD to deploy $WHAT to LIVE: " ANS
  [ "$ANS" = "PROD" ] || { echo "Cancelled. Nothing was deployed."; exit 1; }
fi
printf "\n\033[1;32mDeploying $WHAT to $ENV ($PROJECT)\033[0m\n"
firebase deploy --only "$ONLY" --project "$PROJECT"
echo "Done: $WHAT -> $ENV"
