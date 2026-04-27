---
name: build-ge-agent
description: Help the user design, build and register a Gemini Enterprise (Agentspace) agent. Use when the user wants to create a GE agent, build a Gemini agent, add an agent to Agentspace, or set up an internal AI assistant in Gemini Enterprise. Routes between Tier 1 (no-code via GE UI) and Tier 2 (OpenAPI/webhook tool) based on the agent's needs.
argument-hint: [one-sentence description of the agent's job]
user-invocable: true
---

# Build a Gemini Enterprise agent

This skill turns a vague idea ("I want a GE agent that does X") into a working, registered agent in someone's Gemini Enterprise workspace, in roughly 30 minutes — without any custom backend deployment for most cases.

## Use this skill when

- "Help me build a Gemini Enterprise agent"
- "I want to add an agent to Agentspace"
- "We need an internal AI assistant for [HR / sales / docs / etc.]"
- The user mentions Gemini Enterprise, Agentspace, or `discoveryengine.googleapis.com`

## Don't use this skill for

- Building an Anthropic Claude agent (different platform — defer to claude-api skill)
- Generic prompt engineering questions unrelated to GE
- Tier 3 (full ADK + Vertex AI Agent Engine) — see the "Tier 3" section at the bottom for a pointer to a working reference

## Step 1 — ask the user 3 questions

Before recommending anything, gather:

1. **What should the agent do?** (one sentence)
2. **Does it need to call an external system or API** (CRM, monday.com, internal ticketing, custom data source) — yes/no?
3. **What GCP project hosts your Gemini Enterprise workspace?** (it's OK if they don't know — see Step 2)

If the user can't answer Q3, run [find-engine.sh](find-engine.sh) to discover their engine. See "Connect to your GE workspace" below.

## Step 2 — pick the tier

Based on their answer to Q2:

| User says | Recommend |
|---|---|
| "No external system, just docs / Drive / Gmail / Calendar / general knowledge" | **Tier 1** — see [tier1-no-code.md](tier1-no-code.md) |
| "Yes, it should call our [API / database / SaaS]" | **Tier 2** — see [tier2-openapi.md](tier2-openapi.md) |
| "It needs to run heavy custom logic / algorithms / multi-step reasoning loops" | **Tier 3** — see "Tier 3" section below |

**Default to Tier 1** if it's at all plausible. People over-engineer GE agents constantly. Most "complex" agents are really just LLM + a couple of connectors.

## Step 3 — connect to their GE workspace

For both Tier 1 and Tier 2 the user needs to know which GE engine is theirs. The engine is identified by a resource path like:

```
projects/{PROJECT_ID}/locations/global/collections/default_collection/engines/{ENGINE_ID}
```

If they already know it (because their admin told them, or they saw it in Cloud Console), great. Otherwise:

```bash
# In a terminal, with gcloud authenticated as them:
gcloud auth login                                     # if not already
gcloud auth application-default login                 # for SDK calls
bash ~/.claude/skills/build-ge-agent/find-engine.sh [PROJECT_ID]
```

The script lists every Discovery Engine engine they have access to, with display names. They pick theirs by matching the workspace name shown at the top of their GE browser tab. Output is the resource path they'll use in later steps.

If they don't even know which GCP project — run `find-engine.sh` with no arguments; it scans all projects they have IAM access to.

## Step 4 — execute the chosen tier

Hand off to the relevant guide:

- Tier 1 → [tier1-no-code.md](tier1-no-code.md) — recipe-based, no terminal needed beyond Step 3
- Tier 2 → [tier2-openapi.md](tier2-openapi.md) — write a tiny OpenAPI spec, register the tool, agent calls it

Both end with a working agent in the user's GE sidebar.

## Step 5 — when things go wrong

See [troubleshooting.md](troubleshooting.md). Covers the common failure modes: agent not appearing in sidebar, permission denied on Discovery Engine, cross-project IAM, "something went wrong" in chat.

## Tier 3 — full ADK + Agent Engine (out of scope here)

If the user genuinely needs Tier 3 (custom Python, constraint solvers, multi-tool agentic loops), the path is:

1. Write an ADK agent in Python — [github.com/google/adk-python](https://github.com/google/adk-python)
2. Deploy with `adk deploy agent_engine --project=… --region=…`
3. Register the deployed reasoning engine in GE via the same API call as Tier 2, but with `adkAgentDefinition` instead of an OpenAPI tool

A complete worked Tier 3 example exists privately (a school timetable builder with a CP-SAT constraint solver, CRUD tools, exports, and a companion Cloud Run web UI). The pattern: ADK agent in Python → `adk deploy agent_engine` → register the deployed reasoning engine in GE via the same `discoveryengine.googleapis.com` API used in Tier 2, but with `adkAgentDefinition.provisionedReasoningEngine` instead of an OpenAPI tool. **Tier 3 has real GCP-ops complexity** (cross-project IAM, OAuth scopes, Workspace policies). Budget a day, not 30 minutes.

If the user is sure they need Tier 3, tell them this skill doesn't cover it directly but the timetable repo is a complete worked example.

## Notes for Claude (the assistant running this skill)

- Be opinionated about Tier 1. Most users don't need Tier 2.
- Don't hand the user a wall of YAML/JSON — generate it for them based on Step 1 answers.
- After registering, **always** ask them to refresh their GE tab and look in the sidebar. Caching is a real source of "it didn't work" reports.
- Sharing scope: agents created via API default to `state: ENABLED`. To make them visible to all users in the workspace, also set `sharingConfig.scope: ALL_USERS` (this is what the built-in agents like Deep Research use).
