#!/usr/bin/env bash
# register-mcp-tool.sh — register a Custom MCP Server in Gemini Enterprise
# as a Data Connector. Fully API-driven.
#
# This is what the GE UI's "Connected data stores → Create data store →
# Custom MCP Server" flow does behind the scenes. Reverse-engineered Dec 2025.
#
# Two connector modes supported:
#   --mode FEDERATED  (default — agent treats MCP as a federated search source)
#   --mode ACTIONS    (agent calls MCP tools directly with structured params —
#                      requires the org policy
#                      `discoveryengine.managed.disableCustomMcpServerConnector`
#                      to be Not Enforced. UI registrations land in FEDERATED.)
#
# Usage:
#   ./register-mcp-tool.sh \
#     --project PROJECT_ID \
#     --collection-id alphavantage-mcp        \   # short id, becomes the collection
#     --display-name "Alpha Vantage MCP"      \
#     --mcp-url "https://...workers.dev/mcp"  \
#     --auth-url "https://...workers.dev/oauth/authorize" \
#     --token-url "https://...workers.dev/oauth/token" \
#     --client-id "ge-mcp-client" \
#     --client-secret "<paste>" \
#     [--auth-params ""] \
#     [--scopes ""] \
#     [--description "What the server does, helps agents pick it"] \
#     [--dry-run]
#
# After this completes, attach the resulting collection's dataStore to a GE
# agent (see tier2-mcp.md Step 3). The dataStore lives at:
#   projects/{p}/locations/global/collections/{collection-id}/dataStores/...

set -euo pipefail

PROJECT=""
COLLECTION_ID=""
DISPLAY_NAME=""
MCP_URL=""
AUTH_URL=""
TOKEN_URL=""
CLIENT_ID=""
CLIENT_SECRET=""
AUTH_PARAMS=""
SCOPES=""
DESCRIPTION=""
MODE="FEDERATED"
DRY_RUN=false

while [[ $# -gt 0 ]]; do
  case "$1" in
    --project)         PROJECT="$2"; shift 2 ;;
    --collection-id)   COLLECTION_ID="$2"; shift 2 ;;
    --display-name)    DISPLAY_NAME="$2"; shift 2 ;;
    --mcp-url)         MCP_URL="$2"; shift 2 ;;
    --auth-url)        AUTH_URL="$2"; shift 2 ;;
    --token-url)       TOKEN_URL="$2"; shift 2 ;;
    --client-id)       CLIENT_ID="$2"; shift 2 ;;
    --client-secret)   CLIENT_SECRET="$2"; shift 2 ;;
    --auth-params)     AUTH_PARAMS="$2"; shift 2 ;;
    --scopes)          SCOPES="$2"; shift 2 ;;
    --description)     DESCRIPTION="$2"; shift 2 ;;
    --mode)            MODE="$2"; shift 2 ;;
    --dry-run)         DRY_RUN=true; shift ;;
    -h|--help)
      sed -n '2,30p' "$0" | sed 's/^# *//'
      exit 0 ;;
    *) echo "Unknown arg: $1" >&2; exit 1 ;;
  esac
done

if [[ "$MODE" != "FEDERATED" && "$MODE" != "ACTIONS" ]]; then
  echo "ERROR: --mode must be FEDERATED or ACTIONS (got: $MODE)" >&2
  exit 1
fi

for v in PROJECT COLLECTION_ID DISPLAY_NAME MCP_URL AUTH_URL TOKEN_URL CLIENT_ID CLIENT_SECRET; do
  if [[ -z "${!v}" ]]; then
    echo "ERROR: --${v,,} is required (use --help)" >&2
    exit 1
  fi
done

TOKEN=$(gcloud auth print-access-token)

PAYLOAD=$(python3 -c "
import json
params = {
  'instance_uri': '''$MCP_URL''',
  'auth_uri':     '''$AUTH_URL''',
  'auth_uri_params': '''$AUTH_PARAMS''',
  'token_uri':    '''$TOKEN_URL''',
  'client_id':    '''$CLIENT_ID''',
  'client_secret':'''$CLIENT_SECRET''',
}
if '''$SCOPES''':      params['scopes'] = '''$SCOPES'''
if '''$DESCRIPTION''': params['mcp_server_description'] = '''$DESCRIPTION'''
print(json.dumps({
  'collectionId': '''$COLLECTION_ID''',
  'collectionDisplayName': '''$DISPLAY_NAME''',
  'dataConnector': {
    'dataSource': 'custom_mcp',
    'refreshInterval': '86400s',
    'connectorModes': ['$MODE'],
    'params': params,
  },
}, indent=2))
")

URL="https://discoveryengine.googleapis.com/v1alpha/projects/${PROJECT}/locations/global:setUpDataConnector"

if [[ "$DRY_RUN" == "true" ]]; then
  echo "=== DRY RUN ==="
  echo "POST $URL"
  echo "$PAYLOAD"
  exit 0
fi

echo "Registering MCP server '$DISPLAY_NAME' in project $PROJECT..."

RESP=$(curl -s -X POST \
  -H "Authorization: Bearer $TOKEN" \
  -H "X-Goog-User-Project: $PROJECT" \
  -H "Content-Type: application/json" \
  -d "$PAYLOAD" \
  "$URL")

if echo "$RESP" | grep -q '"error"'; then
  echo "❌ Failed:"
  echo "$RESP" | python3 -m json.tool
  exit 1
fi

DC_NAME=$(echo "$RESP" | python3 -c "import sys,json; d=json.load(sys.stdin); print(d.get('response',{}).get('name',''))")
STATE=$(echo "$RESP" | python3 -c "import sys,json; d=json.load(sys.stdin); print(d.get('response',{}).get('state',''))")

echo "✅ DataConnector created: $DC_NAME"
echo "   State: $STATE  (will become ACTIVE in ~1-2 min)"
echo ""
echo "The collection is at:"
echo "   projects/$PROJECT/locations/global/collections/$COLLECTION_ID"
echo ""
echo "Next steps:"
echo "  1. Wait for state ACTIVE (poll the resource above)."
echo "  2. Attach the connector's dataStore to your GE engine — see tier2-mcp.md Step 3."
echo ""
echo "  export GE_MCP_COLLECTION='projects/$PROJECT/locations/global/collections/$COLLECTION_ID'"
