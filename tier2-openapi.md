# Tier 2 — GE agent with an OpenAPI tool

For agents that need to call your own API or an external system. ~30-60 minutes total. The agent itself still lives in GE (no ADK, no Vertex AI Agent Engine deploy). Your API can live anywhere reachable by HTTPS.

## When to use Tier 2

- "Look up customer status in our CRM"
- "Create a Jira / monday.com / Asana ticket for me"
- "Get yesterday's metrics from our internal dashboard"
- "Search our product catalog by SKU"
- Anything where the agent needs **structured data from a system the LLM can't reach on its own**

If your tool needs lots of custom Python logic that doesn't naturally fit behind a REST endpoint (constraint solvers, ML models, multi-step pipelines), consider Tier 3 instead.

## What you'll do

1. Decide what your tool will do — one clear operation per endpoint
2. Stand up an HTTPS endpoint (existing API, or a small new one)
3. Write a minimal OpenAPI 3.0 spec
4. Add the tool to a GE agent (UI or API)
5. Test in chat

## Step 1 — design your tool

Write down the smallest useful endpoint. Examples:

- `GET /customer/{customer_id}` → returns name, status, tier
- `POST /tickets` → body: `{title, description, priority}`, returns `{ticket_id, url}`
- `GET /metrics?from=YYYY-MM-DD&to=YYYY-MM-DD` → returns aggregate counts

**Rules of thumb:**
- One verb per endpoint. Don't make `/do_thing` that does 5 different things based on a flag.
- Return JSON only.
- Keep request shapes small and obvious — agent LLMs do best with 1-5 string/number fields, not deeply nested objects.

## Step 2 — host it

Pick whichever you're already comfortable with:

| Hosting | When |
|---|---|
| Existing internal API | Easiest if you already have one |
| Cloud Run | Cloud-native, auto HTTPS, simple deploy |
| Cloud Functions | One-shot serverless functions |
| Anywhere with HTTPS | Heroku, Railway, your own server, etc. |
| ngrok'd localhost | **Dev only**, for quick iteration before committing to hosting |

Auth options to think about:
- **API key in header** — simplest, fine for internal use
- **OAuth client credentials** — if your API is shared with external systems
- **Service account JWT** — if you control both ends

## Step 3 — write the OpenAPI spec

Minimal example (`openapi.yaml`):

```yaml
openapi: 3.0.3
info:
  title: Customer Lookup API
  version: 1.0.0
  description: Look up customers by ID.

servers:
  - url: https://api.your-company.com/v1

paths:
  /customer/{customer_id}:
    get:
      operationId: getCustomer
      summary: Get a customer's profile and account status
      description: Use this when the user asks about a specific customer by ID. Returns name, tier, account status, and last login.
      parameters:
        - name: customer_id
          in: path
          required: true
          schema:
            type: string
          description: The customer's ID, usually starts with "C-".
      responses:
        '200':
          description: Customer found
          content:
            application/json:
              schema:
                type: object
                properties:
                  id:        { type: string }
                  name:      { type: string }
                  tier:      { type: string, enum: [free, pro, enterprise] }
                  status:    { type: string, enum: [active, suspended, churned] }
                  last_login: { type: string, format: date-time }
        '404':
          description: Customer not found

components:
  securitySchemes:
    api_key:
      type: apiKey
      in: header
      name: X-API-Key

security:
  - api_key: []
```

**Key things the LLM needs:**
- A clear `description` on each operation — this is what tells the agent **when** to call it
- Meaningful `operationId` — the agent's tool name
- Tight parameter descriptions — the LLM extracts arg values from the user's natural-language request

## Step 4 — register the tool with GE

### Option A — via the GE UI (easiest)

1. Open GE → **+ New agent** → **Proceed to Builder**
2. Fill in name, instructions, model (see [tier1-no-code.md](tier1-no-code.md))
3. In the right panel, find **Tools** or **Connectors** → **Add OpenAPI tool**
4. Paste your `openapi.yaml` (or upload). Provide the auth credentials.
5. **Click Create**

The agent now has the tool available.

### Option B — via API (scriptable, repeatable)

Use [register-openapi-tool.sh](register-openapi-tool.sh):

```bash
bash register-openapi-tool.sh \
  --engine "$GE_ENGINE_RESOURCE" \
  --name "Customer Lookup Agent" \
  --description "Looks up customer info" \
  --instruction "When the user asks about a customer, call getCustomer with the ID." \
  --openapi ./openapi.yaml
```

(The script generates the right `adkAgentDefinition` with `openApiToolDefinition` JSON shape and POSTs it.)

## Step 5 — test

In GE chat with your new agent, try the natural-language version of what should trigger your tool:

- "Look up customer C-12345"
- "What's the status of customer C-99?"

The agent should:
1. Recognize it needs to call the tool
2. Extract `customer_id` from the prompt
3. Call your endpoint
4. Synthesize the JSON response into a clean reply

If it doesn't call your tool, sharpen the operation `description` field — that's the #1 cause of misses.

## Notes & limits

- **Network reachability**: GE calls your API from Google's servers. Your API must be **publicly reachable HTTPS** (or behind a Google-accessible VPN connector). Pure-localhost won't work — use ngrok for dev iteration.
- **Latency**: Each tool call adds round-trip time. Aim for sub-2s endpoint responses.
- **Idempotency**: Mark non-idempotent operations clearly in the description. The agent may retry on errors.
- **Rate limits**: Add them; agents can hammer endpoints in a loop if instructed wrong.
- **Logging**: Log every request from GE — useful when debugging "why didn't it call my tool?"

## What this can't do

- Long-running operations (>30s). For those, return a job ID and poll.
- Streaming responses to the user mid-operation. The tool returns once.
- Maintaining state across calls — keep your API stateless or store in your own DB.

If any of those are required, escalate to Tier 3.
