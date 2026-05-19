#!/usr/bin/env bash
# gen-dashboard.sh — generate a self-contained GE license review dashboard (HTML).
#
# Usage:
#   ./gen-dashboard.sh PROJECT_ID [OUTPUT_HTML]
#   ./gen-dashboard.sh solutionday-cloudsummit
#   ./gen-dashboard.sh solutionday-cloudsummit /tmp/ge-licenses.html
#
# Pulls all userLicenses from the Discovery Engine API and writes a single
# HTML file with a sortable, filterable table. No server needed — open in a browser.
#
# Requires: gcloud (authenticated), curl, python3 (stdlib only).

set -euo pipefail

PROJECT="${1:-}"
OUT="${2:-ge-licenses.html}"

if [[ -z "$PROJECT" || "$PROJECT" == "--help" || "$PROJECT" == "-h" ]]; then
  sed -n '2,13p' "$0" | sed 's/^# *//'
  exit 0
fi

TOKEN=$(gcloud auth print-access-token)
STORE="projects/$PROJECT/locations/global/userStores/default_user_store"
BASE="https://discoveryengine.googleapis.com/v1alpha/${STORE}/userLicenses"

WORK=$(mktemp -d)
PAGE=""
i=0
while : ; do
  URL="${BASE}?pageSize=1000"
  [ -n "$PAGE" ] && URL="${URL}&pageToken=${PAGE}"
  curl -s -H "Authorization: Bearer $TOKEN" -H "X-Goog-User-Project: $PROJECT" "$URL" > "$WORK/p_$i.json"
  PAGE=$(python3 -c "import json;print(json.load(open('$WORK/p_$i.json')).get('nextPageToken',''))" 2>/dev/null || echo "")
  i=$((i+1))
  [ -z "$PAGE" ] && break
  [ "$i" -gt 100 ] && break
done

python3 - "$WORK" "$PROJECT" "$OUT" <<'PYEOF'
import sys, json, glob, os, datetime

work, project, out = sys.argv[1], sys.argv[2], sys.argv[3]

rows = []
for f in sorted(glob.glob(os.path.join(work, "p_*.json"))):
    try:
        d = json.load(open(f))
    except Exception:
        continue
    rows.extend(d.get("userLicenses", []))

now = datetime.datetime.now(datetime.timezone.utc)

def days_idle(ts):
    if not ts:
        return None
    try:
        t = datetime.datetime.fromisoformat(ts.replace("Z", "+00:00"))
        return (now - t).days
    except Exception:
        return None

recs = []
for u in rows:
    email = u.get("userPrincipal", "?")
    state = u.get("licenseAssignmentState", "?")
    last = u.get("lastLoginTime", "") or ""
    assigned_date = (u.get("updateTime", "") or "")[:10] if state == "ASSIGNED" else ""
    di = days_idle(last)
    # classification (matches Code.gs)
    if state == "ASSIGNED" and di is not None and di > 30:
        flag = "reclaim"
    elif state == "ASSIGNED" and di is not None and di > 14:
        flag = "watch"
    elif state == "ASSIGNED" and last == "":
        flag = "neverused"
    elif state == "ASSIGNED":
        flag = "active"
    else:
        flag = "unlicensed"
    recs.append({
        "email": email, "state": state, "assigned": assigned_date,
        "last": last[:10], "idle": di if di is not None else "",
        "flag": flag,
    })

assigned = sum(1 for r in recs if r["state"] == "ASSIGNED")
active = sum(1 for r in recs if r["flag"] == "active")
inactive = assigned - active   # assigned but not actively used (reclaim+watch+neverused)
generated = (now + datetime.timedelta(hours=8)).strftime("%Y-%m-%d %H:%M") + " HKT"

data_json = json.dumps(recs)

_SVG = 'viewBox="0 0 24 24" width="20" height="20" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round" stroke-linejoin="round"'
I_USERS = '<svg ' + _SVG + '><path d="M16 21v-2a4 4 0 0 0-4-4H6a4 4 0 0 0-4 4v2"/><circle cx="9" cy="7" r="4"/><path d="M22 21v-2a4 4 0 0 0-3-3.87"/><path d="M16 3.13a4 4 0 0 1 0 7.75"/></svg>'
I_ALERT = '<svg ' + _SVG + '><path d="m21.73 18-8-14a2 2 0 0 0-3.48 0l-8 14A2 2 0 0 0 4 21h16a2 2 0 0 0 1.73-3Z"/><path d="M12 9v4"/><path d="M12 17h.01"/></svg>'
I_CLOCK = '<svg ' + _SVG + '><circle cx="12" cy="12" r="10"/><polyline points="12 6 12 12 16 14"/></svg>'
I_EYEOFF = '<svg ' + _SVG + '><path d="M9.88 9.88a3 3 0 1 0 4.24 4.24"/><path d="M10.73 5.08A10.43 10.43 0 0 1 12 5c7 0 10 7 10 7a13.16 13.16 0 0 1-1.67 2.68"/><path d="M6.61 6.61A13.526 13.526 0 0 0 2 12s3 7 10 7a9.74 9.74 0 0 0 5.39-1.61"/><line x1="2" x2="22" y1="2" y2="22"/></svg>'
I_COPY = '<svg viewBox="0 0 24 24" width="15" height="15" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round" stroke-linejoin="round" style="vertical-align:-2px;margin-right:6px"><rect width="14" height="14" x="8" y="8" rx="2"/><path d="M4 16c-1.1 0-2-.9-2-2V4c0-1.1.9-2 2-2h10c1.1 0 2 .9 2 2"/></svg>'

html = """<!DOCTYPE html><html lang="en"><head><meta charset="utf-8">
<meta name="viewport" content="width=device-width,initial-scale=1">
<title>Gemini Enterprise — License Dashboard</title>
<link rel="icon" type="image/png" href="https://upload.wikimedia.org/wikipedia/commons/thumb/1/1d/Google_Gemini_icon_2025.svg/500px-Google_Gemini_icon_2025.svg.png">
<style>
 *{box-sizing:border-box;margin:0;padding:0}
 body{font-family:-apple-system,BlinkMacSystemFont,"Segoe UI",Roboto,sans-serif;background:#0d1117;color:#e6edf3;padding:24px}
 h1{font-size:20px;margin-bottom:4px}
 .sub{color:#8b949e;font-size:13px;margin-bottom:20px}
 .kpis{display:flex;gap:12px;flex-wrap:wrap;margin-bottom:18px}
 .kpi{background:#161b22;border:1px solid #30363d;border-radius:10px;padding:14px 18px;min-width:150px;flex:1 1 150px;display:flex;align-items:center;gap:14px}
 .kpi .ic{color:#8b949e;flex-shrink:0}
 .kpi .n{font-size:24px;font-weight:700;line-height:1}
 .kpi .l{font-size:11px;color:#8b949e;text-transform:uppercase;letter-spacing:.05em;margin-top:5px}
 .kpi.red .ic{color:#f85149}.kpi.amber .ic{color:#d29922}.kpi.blue .ic{color:#58a6ff}.kpi.green .ic{color:#3fb950}
 .bar{display:flex;gap:8px;flex-wrap:wrap;margin-bottom:14px;align-items:center}
 .bar button{background:#161b22;border:1px solid #30363d;color:#e6edf3;padding:8px 14px;border-radius:6px;cursor:pointer;font-size:13px}
 .bar button.active{background:#1f6feb;border-color:#1f6feb}
 .copybtn{background:#238636;border-color:#238636;color:#fff;margin-left:auto;display:inline-flex;align-items:center}
 .tablewrap{overflow-x:auto;-webkit-overflow-scrolling:touch;border:1px solid #21262d;border-radius:8px}
 table{width:100%;border-collapse:collapse;font-size:13px;min-width:520px}
 th,td{text-align:left;padding:10px 12px;border-bottom:1px solid #21262d;white-space:nowrap}
 th{background:#161b22;cursor:pointer;user-select:none;position:sticky;top:0}
 th:hover{color:#58a6ff}
 tr.reclaim{background:#f8514915}tr.watch{background:#d2992212}tr.neverused{background:#1f6feb12}
 tr.grp{cursor:pointer;background:#1c2128}tr.grp:hover{background:#22272e}
 tr.grp td{font-weight:700;font-size:13px;border-bottom:1px solid #30363d}
 .caret{display:inline-block;width:16px;color:#8b949e}.cnt{color:#8b949e;font-weight:400;margin-left:4px}
 .pill{display:inline-block;padding:3px 9px;border-radius:10px;font-size:11px;font-weight:600}
 .pill.reclaim{background:#f8514933;color:#ff7b72}
 .pill.watch{background:#d2992233;color:#e3b341}
 .pill.active{background:#23863633;color:#3fb950}
 .pill.neverused{background:#1f6feb33;color:#58a6ff}
 .pill.unlicensed{background:#30363d;color:#8b949e}
 td.email{font-family:ui-monospace,SFMono-Regular,Menlo,monospace;font-size:12px}
 @media(max-width:640px){
  body{padding:14px}h1{font-size:17px}.sub{font-size:12px;margin-bottom:16px}
  .kpi{flex:1 1 calc(50% - 6px);min-width:0;padding:12px 14px;gap:10px}
  .kpi .n{font-size:20px}
  .copybtn{margin-left:0;width:100%;justify-content:center}
  .bar button{flex:1 1 auto}
 }
</style></head><body>
<h1><img src="https://upload.wikimedia.org/wikipedia/commons/thumb/1/1d/Google_Gemini_icon_2025.svg/500px-Google_Gemini_icon_2025.svg.png" alt="" style="height:24px;width:24px;vertical-align:-5px;margin-right:9px">Gemini Enterprise — License Dashboard</h1>
<div class="sub">Project <b>@@PROJECT@@</b> · Last Update: <b>@@GENERATED@@</b> · snapshot — regenerate to refresh</div>
<div class="kpis">
 <div class="kpi"><span class="ic">@@I_USERS@@</span><div><div class="n">@@ASSIGNED@@ / 50</div><div class="l">License Quota</div></div></div>
 <div class="kpi green"><span class="ic">@@I_CLOCK@@</span><div><div class="n">@@ACTIVE@@</div><div class="l">Active (&le;14d idle)</div></div></div>
 <div class="kpi red"><span class="ic">@@I_ALERT@@</span><div><div class="n">@@INACTIVE@@</div><div class="l">Inactive (reclaim-able)</div></div></div>
</div>
<div class="bar">
 <button class="copybtn" id="copy">@@I_COPY@@Copy reclaim emails</button>
</div>
<div class="tablewrap"><table id="t">
<thead><tr>
 <th data-k="email">Email</th>
 <th data-k="assigned">Date assigned</th>
 <th data-k="last">Last login</th><th data-k="idle">Days idle</th>
</tr></thead><tbody></tbody></table></div>
<script>
const DATA = @@DATA_JSON@@;
let sortK="idle", sortDir=-1;
const collapsed={withlic:false,nolic:true};
const tb=document.querySelector("#t tbody");
const grp=r=>r.flag==="unlicensed"?"nolic":"withlic";
const esc=s=>String(s).replace(/[&<>]/g,c=>({"&":"&amp;","<":"&lt;",">":"&gt;"}[c]));
function sortRows(a){return a.slice().sort((p,q)=>{let x=p[sortK],y=q[sortK];
 if(sortK==="idle"){x=x===""?1e9:+x;y=y===""?1e9:+y;}
 return x<y?-1*sortDir:x>y?1*sortDir:0;});}
function render(){
 const g={withlic:[],nolic:[]};DATA.forEach(r=>g[grp(r)].push(r));
 let out="";
 [["withlic","With License"],["nolic","No License"]].forEach(G=>{
  const k=G[0],lbl=G[1],rows=g[k],col=collapsed[k];
  out+=`<tr class="grp" data-g="${k}"><td colspan="4"><span class="caret">${col?"▶":"▼"}</span>${lbl}<span class="cnt">(${rows.length})</span></td></tr>`;
  if(!col)sortRows(rows).forEach(r=>{const ul=r.flag==="unlicensed";out+=`<tr class="${r.flag}"><td class="email">${esc(r.email)}</td><td>${ul?"—":(r.assigned||"—")}</td><td>${r.last||"—"}</td><td>${ul?"—":(r.idle===""?'<span class="pill neverused">never</span>':`<span class="pill ${r.flag}">${r.idle}d</span>`)}</td></tr>`;});
 });
 tb.innerHTML=out;
 document.querySelectorAll("tr.grp").forEach(tr=>tr.onclick=()=>{const k=tr.getAttribute("data-g");collapsed[k]=!collapsed[k];render();});
}
document.querySelectorAll("th").forEach(th=>th.onclick=()=>{
 const k=th.dataset.k; if(sortK===k)sortDir*=-1;else{sortK=k;sortDir=1;} render();});
document.querySelector("#copy").onclick=()=>{
 const e=DATA.filter(r=>r.flag==="reclaim").map(r=>r.email).join("\\n");
 const ta=document.createElement("textarea");ta.value=e;document.body.appendChild(ta);ta.select();document.execCommand("copy");document.body.removeChild(ta);
 alert("Copied "+DATA.filter(r=>r.flag==="reclaim").length+" reclaim emails");};
render();
</script></body></html>"""

for tok, val in [
    ("@@PROJECT@@", project), ("@@GENERATED@@", generated),
    ("@@ASSIGNED@@", str(assigned)), ("@@ACTIVE@@", str(active)),
    ("@@INACTIVE@@", str(inactive)),
    ("@@I_USERS@@", I_USERS), ("@@I_ALERT@@", I_ALERT),
    ("@@I_CLOCK@@", I_CLOCK), ("@@I_EYEOFF@@", I_EYEOFF),
    ("@@I_COPY@@", I_COPY),
    ("@@DATA_JSON@@", data_json),
]:
    html = html.replace(tok, val)

with open(out, "w") as f:
    f.write(html)

print(f"Wrote {out}")
print(f"  Assigned: {assigned}/50 | Reclaim(>30d idle): {reclaim} | Watch(15-30d): {watch} | Never-used: {never}")
print(f"  Open it:  open {out}")
PYEOF

rm -rf "$WORK"
