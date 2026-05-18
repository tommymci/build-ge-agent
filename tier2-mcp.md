# Tier 2 — GE agent backed by an MCP server

For agents whose tools are exposed as a **Model Context Protocol (MCP) server** rather than a plain OpenAPI REST API. ~30–60 minutes total assuming the MCP server is already deployed and reachable over HTTPS.

## When to use this guide

- You already have (or are about to build) an MCP server — Streamable HTTP transport — that exposes one or more tools.
- The MCP server is reachable over HTTPS from Google's network.
- You want the agent to live in GE / Agentspace, not on Vertex AI Agent Engine (Tier 3).

If you have a plain REST API instead, use [tier2-openapi.md](tier2-openapi.md). If you don't have an MCP server yet, see "Building the MCP server" below.

## Reality check — what's API-driven vs UI-driven

As of v1alpha (December 2025), the Discovery Engine public API support for MCP is **almost** complete but with a few sharp edges:

| Step | Public API? | How we do it |
|---|---|---|
| Create engine (workspace) | ✅ Yes | [create-engine.sh](create-engine.sh) |
| Register MCP server (FEDERATED mode) | ✅ Yes | [register-mcp-tool.sh](register-mcp-tool.sh) `--mode FEDERATED` (default). UI also works. |
| Register MCP server (ACTIONS mode — for direct tool-calling) | ⚠️ Yes, **but** typically blocked by org policy `discoveryengine.managed.disableCustomMcpServerConnector`. Admin must set Not Enforced first. | [register-mcp-tool.sh](register-mcp-tool.sh) `--mode ACTIONS` |
| Attach data store to engine | ✅ Yes — PATCH engine.dataStoreIds | curl PATCH (see below) |
| Create agent (low-code) | ⚠️ API works but agent stays in `state: PRIVATE` indefinitely; no public publish method. UI builder's Save/Publish click is the only known way to flip to ENABLED. | UI for now |
| Create agent (Tier 3 — ADK on Vertex AI Agent Engine) | ✅ Yes | tier3 (separate skill) |

**Practical recipe:** create engine + register MCP via API, then build the agent in the GE visual builder. That hybrid is the working pattern until Google fixes the publish gap.

### Connector modes — important

| Mode | What it does | Where it appears in the agent builder |
|---|---|---|
| **FEDERATED** | Agent treats MCP as a search corpus; GE sends natural-language queries | Knowledge section |
| **ACTIONS** | Agent calls each MCP tool individually with structured params | Tools section |

For "Bring me Apple's stock price" use cases, **ACTIONS** is what you want — precise tool invocation. The UI's "Custom MCP Server" form defaults to FEDERATED. To get ACTIONS you must:
1. Get the org admin to set `disableCustomMcpServerConnector` to Not Enforced (persistently).
2. Use the API with `--mode ACTIONS`.

## Full pipeline

```
[Your MCP server]   ←  HTTPS + OAuth  ←   [Gemini Enterprise agent]
       ↑                                          ↑
   you build/host this                       lives in a GE engine
```

Three things to set up, in order:

1. **MCP server** with OAuth front (so GE can authenticate)
2. **GE engine** (the workspace that holds the agent)
3. **Agent** in that engine, with the MCP server attached as a tool

## Step 0 — building the MCP server (skip if you already have one)

GE requires the MCP server to support **OAuth 2.0 client_credentials** (Authorization URL + Token URL + Client ID + Secret). Most off-the-shelf MCP servers (Alpha Vantage, SEC EDGAR, GitHub MCP, etc.) use API-key auth, so you typically need a thin OAuth front.

**Cheapest path: Cloudflare Workers**, two Workers behind one OAuth proxy:

- **Worker A** — OAuth-proxy: handles `/oauth/token`, issues short-lived JWTs, forwards `/mcp/*` to Worker B via service binding.
- **Worker B** — MCP server: `cloudflare/ai/demos/remote-mcp-authless` template, registers tools, calls upstream API with the API key.

A worked example of this two-Worker setup lives at `~/Project/Gemini Enterprise Agent/ge-mcp-oauth-proxy/` and `~/Project/Gemini Enterprise Agent/alphavantage-mcp/` — clone the structure for new MCP integrations.

Whatever you use, end with these six values you'll paste into GE later:

| Field | Example |
|---|---|
| MCP Server URL | `https://your-proxy.workers.dev/mcp` |
| Authorization URL | `https://your-proxy.workers.dev/oauth/authorize` |
| Token URL | `https://your-proxy.workers.dev/oauth/token` |
| Authorization URL Parameters | (usually blank) |
| Client ID | `ge-mcp-client` (you choose) |
| Client Secret | `openssl rand -hex 32` (you generate) |

Smoke-test with curl before continuing. Token round-trip + an MCP `initialize` POST should both succeed.

## Step 1 — create or pick a GE engine

```bash
# Pick an existing engine
bash ~/.claude/skills/build-ge-agent/find-engine.sh [PROJECT_ID]

# Or create a new one
bash ~/.claude/skills/build-ge-agent/create-engine.sh \
  --project YOUR_PROJECT \
  --display-name "Your Workspace Name" \
  --company-name "Your Org"
```

`create-engine.sh` echoes the engine resource path on success — save it:

```bash
export GE_ENGINE_RESOURCE='projects/.../engines/your-engine-id'
```

**Workspace ↔ engine binding gotcha:** the GE app URL `vertexaisearch.cloud.google.com/home/cid/<UUID>/r/...` shows the user's *workspace* customer-ID, not an engine. One workspace cid is bound to one specific engine — usually the first one provisioned for that user. New engines you create via API are NOT auto-visible in the user's existing GE workspace. Two workarounds when this bites you:

1. Build the agent in whatever engine the user's workspace IS bound to (often the org's older "Agentspace" engine), and attach your MCP data store there via PATCH on `engine.dataStoreIds`.
2. Have the workspace re-bound to the new engine — that's a Workspace-admin operation, not in the public API.

In practice: if you've created a fresh engine but the user can't see it in their GE app, fall back to (1).

## Step 2 — register the MCP server

### Option A — API (preferred when policy allows)

```bash
bash ~/.claude/skills/build-ge-agent/register-mcp-tool.sh \
  --project YOUR_PROJECT \
  --collection-id alphavantage-mcp \
  --display-name "Alpha Vantage MCP" \
  --mcp-url "https://...workers.dev/mcp" \
  --auth-url "https://...workers.dev/oauth/authorize" \
  --token-url "https://...workers.dev/oauth/token" \
  --client-id "ge-mcp-client" \
  --client-secret "<your secret>" \
  --description "What the MCP does and when to use it" \
  --mode FEDERATED   # or ACTIONS — see "Connector modes" above
```

If you get `"Operation denied by org policy: constraints/discoveryengine.managed.disableCustomMcpServerConnector"`, the org admin needs to set that constraint to **Not Enforced** at the project level. See troubleshooting.md.

### Option B — GE UI

In Cloud Console: **Apps → your engine → Connected data stores → + New data store → Third-party sources → Custom MCP Server (Preview)**. Three-step wizard (Source → Data → Configuration). The Configuration step has the OAuth fields. The UI defaults the connector to FEDERATED mode — you can't pick ACTIONS from the UI as of Dec 2025.

### Step 2.5 — attach the resulting data store to your engine

The connector creation produces a separate collection with one dataStore inside it. To make it visible to agents in *your* engine, the dataStore must be in `engine.dataStoreIds`. The UI does this automatically when you register from inside the engine view; if you used the API, PATCH it yourself:

```bash
TOKEN=$(gcloud auth print-access-token)
PROJECT="your-project"
ENGINE_ID="your-engine-id"
NEW_DATASTORE_ID="alphavantage-mcp_<timestamp>_mcp_data"   # find via /collections/.../dataStores list

# Read existing dataStoreIds, append, PATCH
EXISTING=$(curl -s -H "Authorization: Bearer $TOKEN" -H "X-Goog-User-Project: $PROJECT" \
  "https://discoveryengine.googleapis.com/v1alpha/projects/$PROJECT/locations/global/collections/default_collection/engines/$ENGINE_ID" \
  | python3 -c "import json,sys; print(json.dumps(json.load(sys.stdin).get('dataStoreIds', [])))")
NEW_LIST=$(python3 -c "import json; ids=json.loads('$EXISTING'); ids.append('$NEW_DATASTORE_ID'); print(json.dumps({'dataStoreIds': ids}))")

curl -X PATCH -H "Authorization: Bearer $TOKEN" -H "X-Goog-User-Project: $PROJECT" \
  -H "Content-Type: application/json" -d "$NEW_LIST" \
  "https://discoveryengine.googleapis.com/v1alpha/projects/$PROJECT/locations/global/collections/default_collection/engines/$ENGINE_ID?updateMask=dataStoreIds"
```

## Step 3 — create the agent

Two options:

### Option A — UI (easier first time)

In the same engine, click **+ New Agent** → **Proceed to Builder**:

- **Display name:** e.g. "Financial Markets Assistant"
- **Description:** what it does, end-user-friendly
- **Instruction:** the system prompt — be specific about *when* to call which MCP tool
- **Tools panel:** select the MCP tool you registered in Step 2
- **Model:** Gemini 2.5 Pro (or whatever's enabled)

Save. Refresh the GE workspace tab; the agent appears in the sidebar.

### Option B — API (scriptable for repeats)

Once the MCP tool is registered, you can create an agent referencing it via:

```bash
TOKEN=$(gcloud auth print-access-token)
PROJECT=$(echo "$GE_ENGINE_RESOURCE" | sed -E 's|projects/([^/]+)/.*|\1|')

curl -X POST \
  -H "Authorization: Bearer $TOKEN" \
  -H "X-Goog-User-Project: $PROJECT" \
  -H "Content-Type: application/json" \
  -d '{
    "displayName": "Financial Markets Assistant",
    "description": "Answers questions about stocks, fundamentals, and markets using live MCP-backed tools.",
    "lowCodeAgentDefinition": {
      "rootAgentId": "root_agent",
      "draftDisplayName": "Financial Markets Assistant",
      "draftDescription": "Answers questions about stocks, fundamentals, and markets.",
      "nodes": [{
        "id": "root_agent",
        "displayName": "Financial Markets Assistant",
        "llmAgentNode": {
          "model": "gemini-2.5-pro",
          "description": "Answers financial questions using MCP tools.",
          "instruction": "You are a financial markets assistant. Use the registered MCP tools to fetch live quotes, company fundamentals, and historical prices when the user asks. Always cite the data source.",
          "selectedTools": {
            "tool": [{"name": "<MCP_TOOL_NAME_FROM_STEP_2>"}]
          }
        }
      }]
    },
    "sharingConfig": {"scope": "ALL_USERS"}
  }' \
  "https://discoveryengine.googleapis.com/v1alpha/${GE_ENGINE_RESOURCE}/assistants/default_assistant/agents"
```

The exact field name to put inside `selectedTools.tool[].name` matches what you saw in the UI after Step 2 — usually a snake_case identifier or an opaque ID. Inspect with:

```bash
curl -H "Authorization: Bearer $TOKEN" -H "X-Goog-User-Project: $PROJECT" \
  "https://discoveryengine.googleapis.com/v1alpha/${GE_ENGINE_RESOURCE}/assistants/default_assistant/agents" \
  | python3 -m json.tool | grep -A2 selectedTools
```

Save the response — `name` is the new agent ID.

## Step 4 — test in chat

Refresh the GE workspace tab. Your new agent appears in the left sidebar.

Try questions that should trigger the MCP tools, e.g. for the Alpha Vantage example:

- "What's Apple's current stock price?"
- "Give me a fundamentals summary of Microsoft."
- "Find tickers for companies with 'electric' in the name."

If the agent answers from general knowledge instead of calling the tool, **sharpen the `instruction`** — list each tool by name and what triggers it. The LLM relies on natural-language matching between the instruction and the user's prompt.

## Common pitfalls

- **OAuth probe fails when registering:** GE's UI tries to fetch a token immediately. If the request shape is wrong (form-encoded vs JSON, scope mismatch), you'll see an inline error. Check the proxy's logs.
- **Agent appears but tool isn't called:** sharpen the instruction. The `description` on each MCP tool also matters — they're part of the prompt the LLM sees.
- **Same-account `*.workers.dev` 404 placeholder:** if your OAuth proxy is on Cloudflare Workers and forwards to another Cloudflare Worker on the same account, use a **service binding** instead of `fetch(url)`. The placeholder page is Cloudflare's loop guard.
- **MCP `Mcp-Session-Id` header missing:** make sure your OAuth proxy preserves response headers from the upstream MCP, otherwise sessions break.
- **Free-tier API quota in upstream:** quota errors often arrive as 200-OK JSON with a `Note` or `Information` field. Surface them as proper errors in your MCP tool.

## What this can't do (yet)

- Programmatic MCP-tool registration via the public API. You **must** click through the UI for Step 2.
- Streaming MCP tool responses surfaced incrementally to the user. Each tool call returns once.
- MCP servers that require non-OAuth auth (mTLS, custom headers without OAuth wrapper) — wrap them in an OAuth proxy first.
