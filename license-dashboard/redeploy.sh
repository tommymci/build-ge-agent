#!/usr/bin/env bash
# redeploy.sh — push code + update the SAME web app deployment (URL never changes).
#
# Run from license-dashboard/ or anywhere; it cd's into clasp-project.
# Requires clasp logged in as the project owner (tommy.shum@hkmci.com).

set -euo pipefail

# The fixed production deployment ID. Updating THIS deployment keeps the URL:
#   https://script.google.com/macros/s/<ID>/exec
DEPLOYMENT_ID="AKfycbyjbpjKd3zePWwvIoYdk-8YMmt7qrQght0sasbgr-CICedTO-GvqttZg7UbEqdtNb26iA"

HERE="$(cd "$(dirname "$0")" && pwd)"
PROJ="$HERE/clasp-project"

if [ ! -d "$PROJ" ]; then
  echo "ERROR: $PROJ not found. This folder is gitignored — re-create with:" >&2
  echo "  clasp clone $DEPLOYMENT_ID   (or clasp create) then copy Code.gs + appsscript.json" >&2
  exit 1
fi

# sync canonical source into the clasp folder
cp "$HERE/Code.gs" "$PROJ/Code.gs"
cp "$HERE/appsscript.json" "$PROJ/appsscript.json"

cd "$PROJ"
echo "Pushing code..."
clasp push --force
echo "Updating deployment $DEPLOYMENT_ID (same URL)..."
clasp deploy -i "$DEPLOYMENT_ID" --description "GE License Dashboard $(date +%Y-%m-%d)"
echo ""
echo "Done. URL unchanged:"
echo "  https://script.google.com/macros/s/$DEPLOYMENT_ID/exec"
