# build-ge-agent

A Claude Code skill for designing, building, and registering Gemini Enterprise (Agentspace) agents — without slogging through Google's docs every time.

Covers the two paths most people actually need:

- **Tier 1 — no-code:** agents that use only the LLM + Google connectors (Drive, Gmail, Calendar, web search). Built entirely in the GE web UI.
- **Tier 2 — OpenAPI tool:** agents that call your own API or external system. You expose an HTTPS endpoint with an OpenAPI spec; GE calls it.

For Tier 3 (full ADK + Vertex AI Agent Engine) the skill points at a working private reference but doesn't itself walk you through deploy/IAM/etc.

## Install (Claude Code users)

```bash
git clone git@github.com:tommymci/build-ge-agent.git ~/.claude/skills/build-ge-agent
```

Then in any Claude Code session, type:

```
/build-ge-agent
```

Or just ask: *"help me build a Gemini Enterprise agent"* — Claude will pick up the skill via its description.

## Update

```bash
cd ~/.claude/skills/build-ge-agent && git pull
```

## Use without Claude Code

The skill is just Markdown + bash scripts. Read [SKILL.md](SKILL.md) as a standalone playbook. The decision tree, recipes, and troubleshooting all work without auto-loading.

## What's inside

| File | What it is |
|---|---|
| [SKILL.md](SKILL.md) | Entry point. Tier-selector decision tree + connect-to-GE walkthrough. |
| [tier1-no-code.md](tier1-no-code.md) | UI walkthrough + 3 recipes (HR FAQ, inbox triage, doc Q&A). |
| [tier2-openapi.md](tier2-openapi.md) | OpenAPI spec template, hosting options, registration paths. |
| [find-engine.sh](find-engine.sh) | Bash script. Lists Discovery Engine engines you can access; helps you find your GE workspace's engine resource path. |
| [register-openapi-tool.sh](register-openapi-tool.sh) | Bash script. POSTs an agent registration with an OpenAPI tool to the Discovery Engine API. Has `--dry-run`. |
| [troubleshooting.md](troubleshooting.md) | Common failures + fixes (cross-project IAM, "agent doesn't appear in sidebar", Sheets API 403, etc.). |

## Requirements

- `gcloud` CLI authenticated as a user with access to your GE workspace's GCP project
- `python3` (stdlib only — `pyyaml` optional, only for YAML OpenAPI specs)
- `curl`

## Contributing

PRs welcome. Common improvements that would help:

- More Tier 1 recipes (department-specific bots, code review assistants, etc.)
- Tier 2 OpenAPI spec templates for popular SaaS (Jira, monday.com, Salesforce)
- Tier 3 walkthrough (the missing piece — currently just links to a private reference)
- Auth recipes for service-account-based API tools

## License

MIT
