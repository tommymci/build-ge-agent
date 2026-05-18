#!/usr/bin/env bash
# register-mcp-auth.sh — create a Discovery Engine Authorization resource
# holding the OAuth2 credentials for an MCP server. The agent then references
# this Authorization via AuthorizationConfig.agentAuthorization.
#
# This is half of the MCP-tool-registration story. As of v1alpha (Dec 2025)
# the *MCP server URL itself* still has to be wired up in the GE UI — the
# public API has no field for it. This script handles the OAuth half and is
# idempotent (re-running with the same --auth-id patches the existing one).
#
# Usage:
#   ./register-mcp-auth.sh \
#     --project PROJECT_ID \
#     --auth-id ge-mcp-alphavantage    \   # short id; becomes the resource id
#     --display-name "GE MCP — Alpha Vantage" \
#     --auth-url "https://...workers.dev/oauth/authorize" \
#     --token-url "https://...workers.dev/oauth/token" \
#     --client-id "ge-mcp-client" \
#     --client-secret "<paste>" \
#     [--dry-run]
#
# After this completes, you still need to:
#   1. In the GE UI, paste the MCP server URL (e.g. https://...workers.dev/mcp)
#      into the engine's Tools / MCP form. Pick this Authorization from the
#      auth dropdown if the UI offers one — otherwise re-paste the OAuth fields.
#   2. Create the agent (use create-agent.sh or the UI).

set -euo pipefail

PROJECT=""
AUTH_ID=""
DISPLAY_NAME=""
AUTH_URL=""
TOKEN_URL=""
CLIENT_ID=""
CLIENT_SECRET=""
DRY_RUN=false

while [[ $# -gt 0 ]]; do
  case "$1" in
    --project)        PROJECT="$2"; shift 2 ;;
    --auth-id)        AUTH_ID="$2"; shift 2 ;;
    --display-name)   DISPLAY_NAME="$2"; shift 2 ;;
    --auth-url)       AUTH_URL="$2"; shift 2 ;;
    --token-url)      TOKEN_URL="$2"; shift 2 ;;
    --client-id)      CLIENT_ID="$2"; shift 2 ;;
    --client-secret)  CLIENT_SECRET="$2"; shift 2 ;;
    --dry-run)        DRY_RUN=true; shift ;;
    -h|--help)
      sed -n '2,22p' "$0" | sed 's/^# *//'
      exit 0 ;;
    *) echo "Unknown arg: $1" >&2; exit 1 ;;
  esac
done

for v in PROJECT AUTH_ID DISPLAY_NAME AUTH_URL TOKEN_URL CLIENT_ID CLIENT_SECRET; do
  if [[ -z "${!v}" ]]; then
    echo "ERROR: --${v,,} is required (use --help)" >&2
    exit 1
  fi
done

TOKEN=$(gcloud auth print-access-token)

PAYLOAD=$(python3 -c "
import json
print(json.dumps({
  'displayName': '''$DISPLAY_NAME''',
  'serverSideOauth2': {
    'clientId':         '''$CLIENT_ID''',
    'clientSecret':     '''$CLIENT_SECRET''',
    'authorizationUri': '''$AUTH_URL''',
    'tokenUri':         '''$TOKEN_URL''',
  },
}, indent=2))
")

URL_CREATE="https://discoveryengine.googleapis.com/v1alpha/projects/${PROJECT}/locations/global/authorizations?authorizationId=${AUTH_ID}"
URL_PATCH="https://discoveryengine.googleapis.com/v1alpha/projects/${PROJECT}/locations/global/authorizations/${AUTH_ID}?updateMask=serverSideOauth2,displayName"

if [[ "$DRY_RUN" == "true" ]]; then
  echo "=== DRY RUN ==="
  echo "Create URL: $URL_CREATE"
  echo "Payload:"
  echo "$PAYLOAD"
  exit 0
fi

# Try create first
RESP=$(curl -s -X POST \
  -H "Authorization: Bearer $TOKEN" \
  -H "X-Goog-User-Project: $PROJECT" \
  -H "Content-Type: application/json" \
  -d "$PAYLOAD" \
  "$URL_CREATE")

if echo "$RESP" | grep -q '"code": 409\|already exists'; then
  echo "Authorization '${AUTH_ID}' already exists — patching..."
  RESP=$(curl -s -X PATCH \
    -H "Authorization: Bearer $TOKEN" \
    -H "X-Goog-User-Project: $PROJECT" \
    -H "Content-Type: application/json" \
    -d "$PAYLOAD" \
    "$URL_PATCH")
fi

NAME=$(echo "$RESP" | python3 -c "import sys,json; print(json.load(sys.stdin).get('name',''))" 2>/dev/null || echo "")

if [[ -z "$NAME" ]]; then
  echo "❌ Failed to create/patch Authorization. Response:"
  echo "$RESP" | python3 -m json.tool
  exit 1
fi

echo "✅ Authorization ready: $NAME"
echo ""
echo "Next steps:"
echo "  1. UI step (still required): in the GE engine's MCP tool form, paste the MCP server URL"
echo "     (e.g. https://...workers.dev/mcp). Pick this Authorization from the dropdown if offered."
echo "  2. Create the agent referencing this Authorization (see tier2-mcp.md Step 3)."
echo ""
echo "  export GE_MCP_AUTHORIZATION='$NAME'"
