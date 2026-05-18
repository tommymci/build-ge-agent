# Gemini Enterprise License Dashboard — Setup

A standalone Google Apps Script web app that shows GE license usage with reclaim flags.
**No GCP infra, no service account, no Cloud Run.** Runs as you, uses your existing GE access.

## What it does

- Daily trigger pulls `userLicenses` from the Discovery Engine API
- Caches a compact copy in Script Properties (chunked, handles growth)
- Serves a sortable/filterable HTML dashboard at a domain-restricted URL
- Flags `ASSIGNED` users idle > 30 days as **reclaim** candidates (red), >14d as **watch** (amber), and assigned-but-never-used

Read-only against GE — the code issues only GET requests; it never modifies licenses.

## Prerequisites

- You have Gemini Enterprise admin/read access (you can already see the license page in console)
- Files in this folder: `Code.gs`, `appsscript.json`

## One-time setup (~5 minutes)

### 1. Create the Apps Script project
- Go to **https://script.google.com** → **New project**
- Rename it (top-left): **Gemini Enterprise License Dashboard**

### 2. Paste the code
- Delete the default `Code.gs` contents → paste all of **`Code.gs`** from this folder
- **Check the config** at the top of `Code.gs`:
  - `PROJECT` — set to the GCP project hosting your GE workspace (default: `solutionday-cloudsummit`)
  - `IDLE_RECLAIM_DAYS` / `IDLE_WATCH_DAYS` / `LICENSE_CAP` — adjust if needed

### 3. Set the manifest
- Click the ⚙️ **Project Settings** → tick **"Show appsscript.json manifest file in editor"**
- Back in the editor, open `appsscript.json` → replace its contents with **`appsscript.json`** from this folder
- This declares the OAuth scopes (external request + cloud-platform) and web-app access = DOMAIN

### 4. First run + authorize
- In the editor, select function **`refreshData`** in the dropdown → click **Run**
- Google prompts for authorization → review scopes → **Allow**
  - (You'll see "external requests" and "Google Cloud" scopes — that's the API call)
- Check the execution log: should say it fetched ~120 users with no error

### 5. Add the daily trigger
- Left sidebar → **Triggers** (alarm clock icon) → **+ Add Trigger**
- Function: **`refreshData`**
- Event source: **Time-driven** → **Day timer** → **7am to 8am** (HKT, set in manifest timezone)
- Save

### 6. Deploy as Web App
- Top-right **Deploy** → **New deployment**
- Type: **Web app**
- Description: `GE License Dashboard`
- Execute as: **Me** (your account — this is what gives it GE access)
- Who has access: **Anyone within [your-domain].com** (PII-safe, domain-restricted)
- **Deploy** → copy the **Web app URL**

### 7. Open it
- Paste the Web app URL in your browser
- First load triggers an initial data pull if the daily trigger hasn't run yet
- Bookmark it. Review "from time to time" — it's day-fresh, page loads are instant (reads cache, not live API)

## Using the dashboard

- **KPIs**: assigned/cap, reclaim count, watch count, never-used count
- **Sort**: click any column header (click again to reverse)
- **Filter**: buttons for All / Reclaim / Watch / Active / Never used / No license
- **Copy reclaim emails**: button copies all reclaim-candidate emails to clipboard — paste into your next license-cleanup batch

## Live deployment (keep this URL stable)

- **Project (hkmci.com):** `1BF_GPBfk-Zsd_0Ou_rLD2oHKwUcE43vjE0nuyVEciPfTNxS4iN6qKTBS`
- **Production deployment ID:** `AKfycbyjbpjKd3zePWwvIoYdk-8YMmt7qrQght0sasbgr-CICedTO-GvqttZg7UbEqdtNb26iA`
- **Dashboard URL (bookmark, never changes):**
  `https://script.google.com/macros/s/AKfycbyjbpjKd3zePWwvIoYdk-8YMmt7qrQght0sasbgr-CICedTO-GvqttZg7UbEqdtNb26iA/exec`

## Updating the code later — KEEP THE SAME URL

⚠️ **Never use "New deployment" / `clasp deploy` with no args** — that mints a *new* URL.
Always update the **existing** deployment so the bookmarked URL keeps working:

**Via clasp (recommended — one command):**
```bash
cd build-ge-agent-skill/license-dashboard/clasp-project
cp ../Code.gs ./Code.gs && cp ../appsscript.json ./appsscript.json
clasp push --force
bash ../redeploy.sh        # redeploys the SAME deployment ID -> same URL
```

**Via the editor:** Deploy → **Manage deployments** → pick the existing "GE License Dashboard" → **Edit (pencil)** → Version: **New version** → **Deploy**. Same URL stays valid. (Do NOT click "New deployment".)

## Notes & limits

- **Data freshness**: day-fresh (daily trigger). Want it fresher? Add a second hourly trigger, or lower friction by running `refreshData` manually.
- **Script Properties limit**: 9 KB/value, 500 KB total. The code chunks data across keys, so it scales to thousands of users.
- **Access**: domain-restricted via the manifest + deployment setting. Don't change "Who has access" to "Anyone" — this is PII.
- **If you leave / lose GE access**: the script runs as you, so it would stop working. For a durable org-owned tool you'd need the GCP + service-account path (requires a `discoveryengine.viewer` IAM grant on the GE project by that project's admin).
- **Read-only**: the script contains zero license-write calls. Safe to audit — it's ~150 lines.

## Alternative: on-demand local snapshot (no setup)

If you just want a one-off snapshot without standing this up, `gen-dashboard.sh` in this folder generates the same HTML locally from your terminal (`bash gen-dashboard.sh PROJECT_ID`). No hosting, no schedule — run it whenever.
