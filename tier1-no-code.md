# Tier 1 — No-code GE agent

For agents that only need an LLM + Google connectors (Drive, Gmail, Calendar, web search). No terminal beyond engine discovery. ~15 minutes from idea to working agent.

## When to use Tier 1

- Document Q&A over a Drive folder
- Summarizing emails or calendar events
- FAQ bot grounded in a few reference docs
- Brainstorming / writing assistant with org-specific instructions
- Any agent whose entire job is "read these sources, follow these instructions, answer questions"

If the agent needs to **write data back** to an external system (e.g., create a Jira ticket, update a CRM record), use [Tier 2](tier2-openapi.md) instead.

## Step-by-step

### 1. Open Gemini Enterprise

Sign in to your org's GE workspace. Click **+ New agent** (sidebar bottom-left).

### 2. Skip the AI builder

The first screen offers an AI Agent Designer that auto-generates an agent from a description. **Click "Proceed to Builder"** in the dark bar — manual setup is faster and more controllable.

### 3. Fill in the agent details

In the right panel:

| Field | What to write |
|---|---|
| **Name** | Short, branded — e.g. "HR Policy Bot", "Sales Playbook Assistant" |
| **Description** | One line a colleague would understand: "Answers HR policy questions using the employee handbook." Affects how it shows in the sidebar gallery. |
| **Instructions** | The system prompt. See recipes below for templates. Keep under 500 words. |
| **Model** | `Gemini 2.5 Pro` for nuanced reasoning; `Gemini 2.5 Flash` if speed/cost matters. |
| **Connectors** | Toggle **Google Search** if it should browse the web. |
| **Knowledge** | Add **Data sources** — Drive folder, specific docs, or pre-indexed datastores. This is the agent's grounded knowledge. |
| **Personalization → Starter prompts** | 3 example questions the user can click. Big quality-of-life win. |

### 4. Click "Create"

Agent appears under **Your agents** in the sidebar within a few seconds.

### 5. Test

Click the agent in the sidebar. Try the starter prompts and a few free-form questions. Iterate on the **Instructions** field if behavior is off.

### 6. Share with the team (optional)

By default an agent is private to its creator. To share with everyone in your GE workspace:

- In the agent edit view, find **Sharing** (some tenants surface this differently)
- Set scope to **All users in workspace** (or the equivalent your tier supports)
- Save

## Recipes

### Recipe A — HR FAQ Bot

```
Name:         HR Policy Assistant
Description:  Answers HR policy questions for [Company Name] employees.
Model:        Gemini 2.5 Pro
Connectors:   (none — purely grounded in docs)
Knowledge:    [Drive folder with HR handbook, leave policy, benefits docs]

Instructions:
You are an HR policy assistant for [Company Name]. Your role:

1. Answer policy questions using ONLY the documents in your knowledge sources.
2. If a question is outside HR scope or not in the docs, say so politely and redirect them to hr@[company].com.
3. Quote the specific document and section you used. E.g. "According to Employee Handbook §3.2: …"
4. Never invent policy. If unclear, say "Please confirm with HR."
5. Be concise — bullet points where useful, full sentences for nuance.

Tone: professional, warm, not corporate-speak.

Starter prompts:
- "How many days of annual leave do I get in my first year?"
- "What's the policy on remote work?"
- "How do I claim medical reimbursement?"
```

### Recipe B — Inbox Triage

```
Name:         Daily Inbox Brief
Description:  Summarizes my last 24h of email and flags items needing action.
Model:        Gemini 2.5 Flash    (speed > nuance for this use)
Connectors:   Gmail, Calendar
Knowledge:    (none)

Instructions:
You help the user start their day. When asked, do this:

1. Read emails from the last 24 hours (Gmail tool).
2. Group into: 🔴 Needs reply today / 🟡 FYI from team / 🟢 Newsletters & low-priority.
3. For each "Needs reply" item, suggest a 1-sentence draft.
4. Pull today's calendar (Calendar tool) and flag any prep needed (e.g. "11am 1:1 with Sarah — last sync was 2 weeks ago, you said you'd update her on project X").
5. Output as a clean markdown brief, no preamble.

If the user asks anything else, just answer normally using the available tools.

Starter prompts:
- "Brief me on my morning"
- "Anything I should reply to right away?"
- "What do I need to prep for my 11am?"
```

### Recipe C — Doc Q&A

```
Name:         [Project Name] Knowledge Base
Description:  Answers questions about [project] using our internal docs.
Model:        Gemini 2.5 Pro
Connectors:   (optional: Google Search if external context helps)
Knowledge:    [Drive folder with all project docs, design specs, runbooks]

Instructions:
You are a search-and-summarize assistant for the [Project Name] team. When asked a question:

1. Search your knowledge sources (the project Drive folder).
2. Synthesize an answer from the most relevant 1-3 documents.
3. ALWAYS link the source documents used. Format: "Based on [Doc Title]: …"
4. If multiple docs disagree, surface the conflict — don't pick one silently.
5. If you don't find anything relevant, say so. Don't fabricate.

When the user asks "what changed recently?" or "what's the latest on X?", look at document modified dates.

Starter prompts:
- "What's the architecture of [system X]?"
- "What's the runbook for [incident Y]?"
- "What did we decide about [topic Z]?"
```

## Things to know

- **Knowledge sources are indexed asynchronously.** A freshly added Drive folder may take a few minutes before the agent can search it.
- **Don't put everything in one agent.** Five small focused agents > one giant one. Easier to maintain instructions, easier for users to discover.
- **Iterate the instruction live.** Edit instructions, save, ask the agent the same question again — no rebuild needed.
- **Pin agents users will use daily.** They click ⭐ / 📌 in the sidebar.

## Done. No deploy, no terminal, no GCP IAM.

If this isn't enough power, escalate to [Tier 2](tier2-openapi.md).
