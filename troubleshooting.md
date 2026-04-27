# Troubleshooting — common GE agent issues

Real failures we've hit, and the fixes.

## "I created the agent but it doesn't appear in the GE sidebar"

**Most common cause:** registered to the wrong engine. There are usually multiple Discovery Engine engines on a project (each user/team often has their own). The displayName is what counts.

**Fix:**
```bash
bash find-engine.sh
```
Match the engine's `DISPLAY_NAME` to the workspace name shown at the top of your GE browser tab. Re-register against the correct engine.

If you're sure the engine is right:

- Hard-refresh GE (Cmd+Shift+R) — the sidebar caches aggressively
- Click ">" next to **Agents** to expand the full list — your agent may not be pinned
- Check **Library** in the sidebar — sometimes new agents land there before main view
- The agent may need `sharingConfig.scope: ALL_USERS` to be visible to others; without it, only the creator sees it

## "Permission denied — Discovery Engine API"

```
403: Discovery Engine API has not been used in project XXX before or it is disabled.
```

**Fix:** enable the API on the project:

```bash
gcloud services enable discoveryengine.googleapis.com --project=PROJECT_ID
```

If that fails with "permission denied to enable", you don't have `serviceusage.services.enable`. Ask the project owner.

## "401 / 403 when calling Discovery Engine"

Your gcloud isn't authenticated for the right project, or your token doesn't include the API quota project.

**Fix:**
```bash
gcloud auth login
gcloud auth application-default login
gcloud config set project YOUR_PROJECT_ID

# When using curl directly, add the X-Goog-User-Project header:
curl -H "X-Goog-User-Project: YOUR_PROJECT_ID" -H "Authorization: Bearer $(gcloud auth print-access-token)" ...
```

## "Cross-project: 403 on reasoningEngines.get"

You hit this if the GE engine is on Project A but the Vertex AI Agent Engine you're trying to use is on Project B.

```
PERMISSION_DENIED: Permission 'aiplatform.reasoningEngines.get' denied on resource ...
```

**Fix:** grant the GE service agent access to Project B:

```bash
# Get the GE project number (the project hosting the GE engine)
GE_PROJECT_NUMBER=$(gcloud projects describe GE_PROJECT_ID --format="value(projectNumber)")

# Grant on the Vertex AI project
gcloud projects add-iam-policy-binding VERTEX_PROJECT_ID \
  --member="serviceAccount:service-${GE_PROJECT_NUMBER}@gcp-sa-discoveryengine.iam.gserviceaccount.com" \
  --role="roles/aiplatform.user"
```

Wait ~30 seconds for the binding to propagate.

## "GE chat says: Something went wrong while answering your question."

This is the catch-all for any agent-side error. To debug:

1. If the agent is an ADK agent on Vertex AI Agent Engine, check its logs:
   ```bash
   # For Cloud Run-hosted webhook tools:
   gcloud run services logs read SERVICE_NAME --project=PROJECT --region=REGION --limit=20
   ```
2. Look for `403`, `404`, missing API errors, or stale resource references (e.g., the agent's code points at a deleted reasoning engine).
3. Cold-start delay: the FIRST invocation after deploy can take 30-60s while the container warms. Try once more.

## "Sheets API 403: The caller does not have permission"

You're trying to create a Google Sheet from a Cloud Run service account or Vertex AI agent. **This is almost always a Workspace org policy issue**, not GCP IAM.

**Fix options (in increasing order of effort):**

1. **Just don't use Sheets**: download the data as XLSX from your agent and have users drag it into Drive — Google Sheets opens it natively, all formatting preserved. Zero auth setup.
2. **Domain-wide delegation**: ask your Workspace admin to authorize a service account to impersonate users. The SA can then create files in users' Drives. ~1 hour of admin time.
3. **Shared Drive**: create a shared Drive, add the SA as member, write all sheets there. Workspace feature.

Option 1 is the right call 95% of the time.

## "NEXT_PUBLIC_* env var is empty in my Next.js bundle (Cloud Run frontend)"

If you have a Next.js frontend deployed via Cloud Run with a Dockerfile and use `NEXT_PUBLIC_*` env vars:

**Don't shadow them with Docker `ARG` + `ENV`.** This pattern fails:

```dockerfile
# BAD — sets ENV to empty when ARG isn't passed, overrides .env.production
ARG NEXT_PUBLIC_API_BASE
ENV NEXT_PUBLIC_API_BASE=$NEXT_PUBLIC_API_BASE
```

**Fix:** remove those lines and put your value in `.env.production` at the project root. Next.js reads it automatically during `next build`.

```bash
# .env.production
NEXT_PUBLIC_API_BASE=https://my-api.example.com
```

## "Found my engine via UI but the URL has /cid/UUID, not /engines/ID"

The URL `vertexaisearch.cloud.google.com/home/cid/<UUID>/r/agents` shows your **Workspace customer ID (CID)**, not your engine ID. The CID is org-level; one Workspace can have many engines.

**Fix:** ignore the URL. Use `find-engine.sh` to enumerate engines and pick by displayName.

## "I deployed to Vertex AI Agent Engine, registered the agent, but it errors on every chat"

Common with cross-project setups. The chain to verify:

1. The Agent Engine's resource path is correct in your registration body
2. The GE service agent has `aiplatform.user` on the Agent Engine's project (see "Cross-project" above)
3. The Vertex AI API is enabled on the Agent Engine's project
4. `gcloud auth application-default login` was run on the deployer's machine

If all four pass and it still fails: pull the Agent Engine logs via Cloud Logging filtered by `resource.type="aiplatform.googleapis.com/ReasoningEngine"`.

## "How do I delete an agent?"

```bash
TOKEN=$(gcloud auth print-access-token)
PROJECT_ID="your-ge-project"
curl -s -X DELETE \
  -H "Authorization: Bearer $TOKEN" \
  -H "X-Goog-User-Project: $PROJECT_ID" \
  "https://discoveryengine.googleapis.com/v1alpha/projects/$PROJECT_ID/locations/global/collections/default_collection/engines/ENGINE_ID/assistants/default_assistant/agents/AGENT_ID"
```

## Still stuck?

- Check the Agent Engine playground in Cloud Console — it isolates problems to either the agent itself or the GE plumbing
- Compare against a working built-in agent (Deep Research, etc.) — read its API record to see what fields are populated
- Open an issue / ping the team
