#!/usr/bin/env bash
# register-openapi-tool.sh — create a GE agent with an OpenAPI tool.
#
# Usage:
#   ./register-openapi-tool.sh \
#     --engine "projects/.../engines/<ENGINE_ID>" \
#     --name "Customer Lookup Agent" \
#     --description "Looks up customer info" \
#     --instruction "When user asks about a customer, call getCustomer with the ID." \
#     --openapi ./openapi.yaml \
#     [--auth-header "X-API-Key: secret123"] \
#     [--shared-with-all-users] \
#     [--dry-run]
#
# Requires: gcloud, curl, python3 (stdlib + PyYAML if --openapi is YAML; for JSON specs no extra deps).

set -euo pipefail

ENGINE=""
NAME=""
DESCRIPTION=""
INSTRUCTION=""
OPENAPI_FILE=""
AUTH_HEADER=""
SHARE_ALL=false
DRY_RUN=false

while [[ $# -gt 0 ]]; do
  case "$1" in
    --engine)         ENGINE="$2"; shift 2 ;;
    --name)           NAME="$2"; shift 2 ;;
    --description)    DESCRIPTION="$2"; shift 2 ;;
    --instruction)    INSTRUCTION="$2"; shift 2 ;;
    --openapi)        OPENAPI_FILE="$2"; shift 2 ;;
    --auth-header)    AUTH_HEADER="$2"; shift 2 ;;
    --shared-with-all-users) SHARE_ALL=true; shift ;;
    --dry-run)        DRY_RUN=true; shift ;;
    -h|--help)
      sed -n '2,17p' "$0" | sed 's/^# *//'
      exit 0 ;;
    *) echo "Unknown arg: $1" >&2; exit 1 ;;
  esac
done

for v in ENGINE NAME DESCRIPTION INSTRUCTION OPENAPI_FILE; do
  if [[ -z "${!v}" ]]; then
    echo "ERROR: --${v,,} is required (use --help)" >&2
    exit 1
  fi
done

if [[ ! -f "$OPENAPI_FILE" ]]; then
  echo "ERROR: OpenAPI file not found: $OPENAPI_FILE" >&2
  exit 1
fi

PROJECT_ID=$(echo "$ENGINE" | sed -E 's|projects/([^/]+)/.*|\1|')

OPENAPI_JSON=$(python3 -c "
import sys, json
content = open('$OPENAPI_FILE').read()
if '$OPENAPI_FILE'.endswith(('.yaml', '.yml')):
    try:
        import yaml
        spec = yaml.safe_load(content)
    except ImportError:
        sys.stderr.write('ERROR: PyYAML required for YAML specs. pip install pyyaml — or convert to JSON.\n')
        sys.exit(1)
else:
    spec = json.loads(content)
print(json.dumps(spec))
")

PAYLOAD=$(python3 -c "
import json
spec = json.loads('''$OPENAPI_JSON''')
agent = {
    'displayName': '''$NAME''',
    'description': '''$DESCRIPTION''',
    'icon': {'content': ''},
    'adkAgentDefinition': {
        'toolSettings': {
            'toolDescription': '''$INSTRUCTION''',
        },
        'inlineAgentDefinition': {
            'instruction': '''$INSTRUCTION''',
            'tools': [{
                'openApiToolDefinition': {
                    'spec': spec,
                }
            }],
        },
    },
}
if '$SHARE_ALL' == 'true':
    agent['sharingConfig'] = {'scope': 'ALL_USERS'}
print(json.dumps(agent, indent=2))
")

URL="https://discoveryengine.googleapis.com/v1alpha/${ENGINE}/assistants/default_assistant/agents"

if [[ "$DRY_RUN" == "true" ]]; then
  echo "=== DRY RUN — would POST to: ==="
  echo "$URL"
  echo "=== Payload: ==="
  echo "$PAYLOAD"
  exit 0
fi

TOKEN=$(gcloud auth print-access-token)
RESP=$(curl -s -X POST \
  -H "Authorization: Bearer $TOKEN" \
  -H "X-Goog-User-Project: $PROJECT_ID" \
  -H "Content-Type: application/json" \
  -d "$PAYLOAD" \
  "$URL")

echo "$RESP" | python3 -m json.tool

NEW_ID=$(echo "$RESP" | python3 -c "import sys,json; d=json.load(sys.stdin); print(d.get('name','').rsplit('/',1)[-1])" 2>/dev/null || echo "")

if [[ -n "$NEW_ID" ]]; then
  echo ""
  echo "✅ Agent created. ID: $NEW_ID"
  echo "👉 Refresh your GE workspace tab and look in the sidebar."
else
  echo ""
  echo "❌ No agent ID in response — see error above."
  exit 1
fi
