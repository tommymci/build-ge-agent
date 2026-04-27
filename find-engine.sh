#!/usr/bin/env bash
# find-engine.sh — discover your Gemini Enterprise engine resource path.
#
# Usage:
#   ./find-engine.sh                    # scan ALL projects you have access to
#   ./find-engine.sh PROJECT_ID         # scan one specific project
#   ./find-engine.sh --help
#
# Prints, for each engine found:
#   ENGINE_ID | DISPLAY_NAME | SOLUTION_TYPE | RESOURCE_PATH
#
# Authenticates as your current gcloud user.
# Requires: gcloud, curl, python3 (stdlib only).

set -euo pipefail

if [[ "${1:-}" == "--help" || "${1:-}" == "-h" ]]; then
  sed -n '2,11p' "$0" | sed 's/^# *//'
  exit 0
fi

if ! command -v gcloud >/dev/null 2>&1; then
  echo "ERROR: gcloud CLI not found. Install: https://cloud.google.com/sdk/docs/install" >&2
  exit 1
fi

if ! gcloud auth print-access-token >/dev/null 2>&1; then
  echo "ERROR: gcloud not authenticated. Run: gcloud auth login" >&2
  exit 1
fi

TOKEN=$(gcloud auth print-access-token)
TARGET_PROJECT="${1:-}"

scan_project() {
  local proj="$1"
  local resp
  resp=$(curl -s \
    -H "Authorization: Bearer $TOKEN" \
    -H "X-Goog-User-Project: $proj" \
    "https://discoveryengine.googleapis.com/v1alpha/projects/$proj/locations/global/collections/default_collection/engines" 2>/dev/null) || return 0

  echo "$resp" | python3 -c "
import sys, json
try:
    d = json.load(sys.stdin)
except Exception:
    sys.exit(0)
if 'error' in d:
    sys.exit(0)
proj = '$proj'
for e in d.get('engines', []):
    eid = e.get('name','').rsplit('/',1)[-1]
    sol = e.get('solutionType','?').replace('SOLUTION_TYPE_','')
    disp = e.get('displayName','?')
    name = e.get('name','')
    print(f'{proj} | {eid[:45]:45} | {sol:8} | {disp:40} | {name}')
"
}

if [[ -n "$TARGET_PROJECT" ]]; then
  echo "Scanning $TARGET_PROJECT..."
  echo "PROJECT | ENGINE_ID | TYPE | DISPLAY_NAME | RESOURCE_PATH"
  echo "----------------------------------------------------------------"
  scan_project "$TARGET_PROJECT"
  echo ""
  echo "Copy the RESOURCE_PATH of your workspace and:"
  echo "  export GE_ENGINE_RESOURCE='<paste here>'"
  exit 0
fi

echo "No project specified — scanning all projects you have access to..."
echo "(This can take a minute. To skip, run: $0 PROJECT_ID)"
echo ""
echo "PROJECT | ENGINE_ID | TYPE | DISPLAY_NAME | RESOURCE_PATH"
echo "----------------------------------------------------------------"

PROJECTS=$(gcloud projects list --format="value(projectId)" 2>/dev/null)
COUNT=0
for proj in $PROJECTS; do
  output=$(scan_project "$proj")
  if [[ -n "$output" ]]; then
    echo "$output"
    COUNT=$((COUNT + 1))
  fi
done

echo ""
if [[ "$COUNT" -eq 0 ]]; then
  echo "No engines found. Either:"
  echo "  1. You don't have GE access on any of your projects."
  echo "  2. Your GE workspace is on a project you can't list (ask your admin)."
  echo "  3. The Discovery Engine API isn't enabled on the projects scanned."
  exit 1
fi

echo "Found engines on $COUNT project(s)."
echo "Copy the RESOURCE_PATH of YOUR workspace (match by DISPLAY_NAME) and:"
echo "  export GE_ENGINE_RESOURCE='<paste here>'"
