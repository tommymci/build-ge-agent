#!/usr/bin/env bash
# create-engine.sh — create a new Gemini Enterprise (Agentspace) engine via API.
#
# Usage:
#   ./create-engine.sh \
#     --project PROJECT_ID \
#     --display-name "MC GE Agents" \
#     [--engine-id mc-ge-agents]    \   # optional, auto-derived from display-name if omitted
#     [--company-name "Master Concept"] \   # optional, shown in UI
#     [--dry-run]
#
# What it creates: a SEARCH-type engine with the Agentspace LLM add-on enabled
# and Gemini 3 Pro/Flash model selection — this is the standard shape for
# every "Agentspace - <Name>" / "gemini-enterprise-*" engine in the Google demo
# org. The engine becomes a Gemini Enterprise workspace where agents can live.
#
# Prerequisites:
#   - gcloud installed + authenticated (`gcloud auth login` and `gcloud auth application-default login`)
#   - Discovery Engine API enabled on the target project
#   - Caller has roles/discoveryengine.admin (or equivalent) on the project
#
# Output: the engine resource path, which you can plug into other skill scripts.

set -euo pipefail

PROJECT=""
DISPLAY_NAME=""
ENGINE_ID=""
COMPANY_NAME=""
DRY_RUN=false

while [[ $# -gt 0 ]]; do
  case "$1" in
    --project)        PROJECT="$2"; shift 2 ;;
    --display-name)   DISPLAY_NAME="$2"; shift 2 ;;
    --engine-id)      ENGINE_ID="$2"; shift 2 ;;
    --company-name)   COMPANY_NAME="$2"; shift 2 ;;
    --dry-run)        DRY_RUN=true; shift ;;
    -h|--help)
      sed -n '2,18p' "$0" | sed 's/^# *//'
      exit 0 ;;
    *) echo "Unknown arg: $1" >&2; exit 1 ;;
  esac
done

for v in PROJECT DISPLAY_NAME; do
  if [[ -z "${!v}" ]]; then
    echo "ERROR: --${v,,} is required (use --help)" >&2
    exit 1
  fi
done

# Auto-derive engine_id from display-name: lowercase, alnum + hyphens, max 50 chars
if [[ -z "$ENGINE_ID" ]]; then
  ENGINE_ID=$(echo "$DISPLAY_NAME" \
    | tr '[:upper:]' '[:lower:]' \
    | sed -E 's/[^a-z0-9]+/-/g; s/^-+//; s/-+$//' \
    | cut -c1-50)
fi

# Discovery Engine appends a timestamp suffix automatically when we POST.
# The actual engine_id becomes "${ENGINE_ID}_<timestamp>" in the response.

TOKEN=$(gcloud auth print-access-token)

PAYLOAD=$(python3 -c "
import json
p = {
  'displayName': '''$DISPLAY_NAME''',
  'solutionType': 'SOLUTION_TYPE_SEARCH',
  'industryVertical': 'GENERIC',
  'searchEngineConfig': {
    'searchTier': 'SEARCH_TIER_ENTERPRISE',
    'searchAddOns': ['SEARCH_ADD_ON_LLM'],
  },
  'appType': 'APP_TYPE_INTRANET',
}
if '''$COMPANY_NAME''':
  p['commonConfig'] = {'companyName': '''$COMPANY_NAME'''}
print(json.dumps(p, indent=2))
")

URL="https://discoveryengine.googleapis.com/v1alpha/projects/${PROJECT}/locations/global/collections/default_collection/engines?engineId=${ENGINE_ID}"

if [[ "$DRY_RUN" == "true" ]]; then
  echo "=== DRY RUN — would POST to: ==="
  echo "$URL"
  echo "=== Payload: ==="
  echo "$PAYLOAD"
  exit 0
fi

echo "Creating engine '$DISPLAY_NAME' (id=$ENGINE_ID) in project $PROJECT..."

RESP=$(curl -s -X POST \
  -H "Authorization: Bearer $TOKEN" \
  -H "X-Goog-User-Project: $PROJECT" \
  -H "Content-Type: application/json" \
  -d "$PAYLOAD" \
  "$URL")

# The create returns a long-running operation. We poll until done.
OP_NAME=$(echo "$RESP" | python3 -c "import sys,json; print(json.load(sys.stdin).get('name',''))" 2>/dev/null || echo "")

if [[ -z "$OP_NAME" ]]; then
  echo "❌ No operation returned. Response:"
  echo "$RESP" | python3 -m json.tool
  exit 1
fi

echo "Operation: $OP_NAME"
echo "Polling..."

# Engine path we *expect* to see if creation succeeds. Discovery Engine is
# inconsistent here: operations sometimes vanish before we poll them, so we
# also fall back to GET on the engine resource directly.
EXPECTED_ENGINE="projects/${PROJECT}/locations/global/collections/default_collection/engines/${ENGINE_ID}"

succeed() {
  local resource="$1"
  echo "✅ Engine created: $resource"
  echo ""
  echo "Next steps:"
  echo "  • Register an MCP server: see tier2-mcp.md (UI walkthrough — MCP isn't yet in v1alpha API)"
  echo "  • Register an OpenAPI tool: see tier2-openapi.md"
  echo "  • Cloud Console: https://console.cloud.google.com/gen-app-builder/engines?project=$PROJECT"
  echo ""
  echo "  export GE_ENGINE_RESOURCE='$resource'"
  exit 0
}

for i in $(seq 1 40); do  # ~2 minutes max
  sleep 3
  OP=$(curl -s -H "Authorization: Bearer $TOKEN" -H "X-Goog-User-Project: $PROJECT" \
    "https://discoveryengine.googleapis.com/v1alpha/$OP_NAME")
  DONE=$(echo "$OP" | python3 -c "import sys,json; d=json.load(sys.stdin); print(d.get('done',False))" 2>/dev/null || echo "false")

  if [[ "$DONE" == "True" ]]; then
    ERR=$(echo "$OP" | python3 -c "import sys,json; d=json.load(sys.stdin); e=d.get('error'); print(json.dumps(e)) if e else print('')")
    if [[ -n "$ERR" ]]; then
      echo "❌ Operation failed:"
      echo "$ERR" | python3 -m json.tool
      exit 1
    fi
    RESOURCE=$(echo "$OP" | python3 -c "import sys,json; d=json.load(sys.stdin); print(d.get('response',{}).get('name',''))")
    succeed "${RESOURCE:-$EXPECTED_ENGINE}"
  fi

  # Fallback: operation 404 means it completed and was garbage-collected.
  # Check the engine resource directly.
  if echo "$OP" | grep -q '"code": 404'; then
    ENG=$(curl -s -H "Authorization: Bearer $TOKEN" -H "X-Goog-User-Project: $PROJECT" \
      "https://discoveryengine.googleapis.com/v1alpha/$EXPECTED_ENGINE")
    if echo "$ENG" | grep -q '"displayName"'; then
      succeed "$EXPECTED_ENGINE"
    fi
  fi

  echo "  ...still creating ($i)"
done

echo "❌ Operation didn't complete in ~2 min. Check status manually:"
echo "  curl -H \"Authorization: Bearer \$(gcloud auth print-access-token)\" \\"
echo "       -H \"X-Goog-User-Project: $PROJECT\" \\"
echo "       https://discoveryengine.googleapis.com/v1alpha/$EXPECTED_ENGINE"
exit 1
