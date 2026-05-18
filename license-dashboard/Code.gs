/**
 * Gemini Enterprise License Dashboard
 *
 * Apps Script standalone project. Runs as the deploying user (who must have
 * Gemini Enterprise admin/read access on the target GCP project).
 *
 * - refreshData()  : daily trigger. Pulls userLicenses from Discovery Engine,
 *                     compacts, stores chunked in Script Properties.
 * - doGet()        : Web App. Reads cached Properties, renders a sortable,
 *                     filterable HTML dashboard with reclaim flags.
 *
 * No Sheet, no service account, no GCP infra. Read-only against GE (GET only).
 */

// ---- CONFIG ----
var PROJECT = 'solutionday-cloudsummit';
var STORE = 'projects/' + PROJECT + '/locations/global/userStores/default_user_store';
var PROP_PREFIX = 'gelic_chunk_';
var META_KEY = 'gelic_meta';
var CHUNK_SIZE = 8000;          // < 9KB Script Property per-value limit
var IDLE_RECLAIM_DAYS = 30;     // ASSIGNED + idle > this  -> reclaim (red)
var IDLE_WATCH_DAYS = 14;       // ASSIGNED + idle > this  -> watch  (amber)
var LICENSE_CAP = 50;

/**
 * Daily trigger entrypoint. Fetch + cache.
 */
function refreshData() {
  var token = ScriptApp.getOAuthToken();
  var recs = [];
  var pageToken = '';
  do {
    var url = 'https://discoveryengine.googleapis.com/v1alpha/' + STORE +
              '/userLicenses?pageSize=1000' + (pageToken ? '&pageToken=' + pageToken : '');
    var resp = UrlFetchApp.fetch(url, {
      method: 'get',
      headers: { Authorization: 'Bearer ' + token, 'X-Goog-User-Project': PROJECT },
      muteHttpExceptions: true
    });
    var body = resp.getContentText();
    if (resp.getResponseCode() !== 200) {
      throw new Error('API ' + resp.getResponseCode() + ': ' + body.slice(0, 500));
    }
    var data = JSON.parse(body);
    (data.userLicenses || []).forEach(function (u) {
      var state = u.licenseAssignmentState || '';
      recs.push({
        e: u.userPrincipal || '',
        s: state,
        a: state === 'ASSIGNED' ? (u.updateTime || '').slice(0, 10) : '',
        l: (u.lastLoginTime || '').slice(0, 10)
      });
    });
    pageToken = data.nextPageToken || '';
  } while (pageToken);

  var json = JSON.stringify(recs);
  var props = PropertiesService.getScriptProperties();

  // wipe old chunks
  var existing = props.getProperties();
  Object.keys(existing).forEach(function (k) {
    if (k.indexOf(PROP_PREFIX) === 0) props.deleteProperty(k);
  });

  var n = 0;
  for (var i = 0; i < json.length; i += CHUNK_SIZE) {
    props.setProperty(PROP_PREFIX + n, json.substring(i, i + CHUNK_SIZE));
    n++;
  }
  props.setProperty(META_KEY, JSON.stringify({
    chunks: n,
    count: recs.length,
    updated: new Date().toISOString()
  }));
  return { count: recs.length, chunks: n };
}

/**
 * Read cached records back from chunked Script Properties.
 */
function loadData() {
  var props = PropertiesService.getScriptProperties();
  var meta = JSON.parse(props.getProperty(META_KEY) || '{"chunks":0,"count":0}');
  var json = '';
  for (var i = 0; i < meta.chunks; i++) {
    json += props.getProperty(PROP_PREFIX + i) || '';
  }
  return { recs: json ? JSON.parse(json) : [], meta: meta };
}

/**
 * Run this ONCE from the editor to install the daily scheduler.
 * Removes any existing refreshData triggers, then creates a fresh one
 * that runs at ~midnight Hong Kong time every day.
 *
 * Hour is interpreted in the project timezone (Asia/Hong_Kong, set in
 * appsscript.json), so atHour(0) = 00:00 HKT. Apps Script day-timers fire
 * within ~1h of the target, i.e. roughly 00:00-01:00 HKT nightly.
 */
function setupTrigger() {
  ScriptApp.getProjectTriggers().forEach(function (t) {
    if (t.getHandlerFunction() === 'refreshData') ScriptApp.deleteTrigger(t);
  });
  ScriptApp.newTrigger('refreshData')
    .timeBased()
    .atHour(0)            // midnight, project timezone (HKT)
    .everyDays(1)
    .create();
  // prime the cache immediately so the dashboard isn't empty before first nightly run
  refreshData();
  return 'Daily trigger installed (≈00:00 HKT) and data primed.';
}

/**
 * Web App entrypoint.
 */
function doGet() {
  var loaded = loadData();
  // If never refreshed yet, do a first pull synchronously.
  if (!loaded.meta.updated) {
    refreshData();
    loaded = loadData();
  }
  var html = renderHtml(loaded.recs, loaded.meta);
  return HtmlService.createHtmlOutput(html)
    .setTitle('Gemini Enterprise — License Dashboard')
    .setFaviconUrl('https://upload.wikimedia.org/wikipedia/commons/thumb/1/1d/Google_Gemini_icon_2025.svg/500px-Google_Gemini_icon_2025.svg.png')
    .addMetaTag('viewport', 'width=device-width, initial-scale=1');
}

function daysBetween(dateStr) {
  if (!dateStr) return null;
  var d = new Date(dateStr + 'T00:00:00Z');
  if (isNaN(d.getTime())) return null;
  return Math.floor((Date.now() - d.getTime()) / 86400000);
}

function renderHtml(recs, meta) {
  var enriched = recs.map(function (r) {
    var idle = daysBetween(r.l);
    var flag;
    if (r.s === 'ASSIGNED' && idle !== null && idle > IDLE_RECLAIM_DAYS) flag = 'reclaim';
    else if (r.s === 'ASSIGNED' && idle !== null && idle > IDLE_WATCH_DAYS) flag = 'watch';
    else if (r.s === 'ASSIGNED' && r.l === '') flag = 'neverused';
    else if (r.s === 'ASSIGNED') flag = 'active';
    else flag = 'unlicensed';
    return {
      email: r.e,
      state: r.s,
      assigned: r.a || '',
      last: r.l || '',
      idle: idle === null ? '' : idle,
      flag: flag
    };
  });

  var assigned = enriched.filter(function (x) { return x.state === 'ASSIGNED'; }).length;
  var reclaim = enriched.filter(function (x) { return x.flag === 'reclaim'; }).length;
  var watch = enriched.filter(function (x) { return x.flag === 'watch'; }).length;
  var never = enriched.filter(function (x) { return x.flag === 'neverused'; }).length;
  var updated = meta.updated ? new Date(meta.updated).toLocaleString('en-GB', { timeZone: 'Asia/Hong_Kong' }) + ' HKT' : 'never';

  var dataJson = JSON.stringify(enriched);

  var I_USERS = '<svg viewBox="0 0 24 24" width="20" height="20" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round" stroke-linejoin="round"><path d="M16 21v-2a4 4 0 0 0-4-4H6a4 4 0 0 0-4 4v2"/><circle cx="9" cy="7" r="4"/><path d="M22 21v-2a4 4 0 0 0-3-3.87"/><path d="M16 3.13a4 4 0 0 1 0 7.75"/></svg>';
  var I_ALERT = '<svg viewBox="0 0 24 24" width="20" height="20" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round" stroke-linejoin="round"><path d="m21.73 18-8-14a2 2 0 0 0-3.48 0l-8 14A2 2 0 0 0 4 21h16a2 2 0 0 0 1.73-3Z"/><path d="M12 9v4"/><path d="M12 17h.01"/></svg>';
  var I_CLOCK = '<svg viewBox="0 0 24 24" width="20" height="20" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round" stroke-linejoin="round"><circle cx="12" cy="12" r="10"/><polyline points="12 6 12 12 16 14"/></svg>';
  var I_EYEOFF = '<svg viewBox="0 0 24 24" width="20" height="20" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round" stroke-linejoin="round"><path d="M9.88 9.88a3 3 0 1 0 4.24 4.24"/><path d="M10.73 5.08A10.43 10.43 0 0 1 12 5c7 0 10 7 10 7a13.16 13.16 0 0 1-1.67 2.68"/><path d="M6.61 6.61A13.526 13.526 0 0 0 2 12s3 7 10 7a9.74 9.74 0 0 0 5.39-1.61"/><line x1="2" x2="22" y1="2" y2="22"/></svg>';
  var I_COPY = '<svg viewBox="0 0 24 24" width="15" height="15" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round" stroke-linejoin="round" style="vertical-align:-2px;margin-right:6px"><rect width="14" height="14" x="8" y="8" rx="2"/><path d="M4 16c-1.1 0-2-.9-2-2V4c0-1.1.9-2 2-2h10c1.1 0 2 .9 2 2"/></svg>';

  return [
'<!DOCTYPE html><html><head><meta charset="utf-8">',
'<meta name="viewport" content="width=device-width,initial-scale=1">',
'<title>Gemini Enterprise — License Dashboard</title>',
'<link rel="icon" type="image/png" href="https://upload.wikimedia.org/wikipedia/commons/thumb/1/1d/Google_Gemini_icon_2025.svg/500px-Google_Gemini_icon_2025.svg.png">',
'<style>',
'*{box-sizing:border-box;margin:0;padding:0}',
'body{font-family:-apple-system,BlinkMacSystemFont,"Segoe UI",Roboto,sans-serif;background:#0d1117;color:#e6edf3;padding:24px}',
'h1{font-size:20px;margin-bottom:4px}.sub{color:#8b949e;font-size:13px;margin-bottom:20px}',
'.kpis{display:flex;gap:12px;flex-wrap:wrap;margin-bottom:18px}',
'.kpi{background:#161b22;border:1px solid #30363d;border-radius:10px;padding:14px 18px;min-width:150px;flex:1 1 150px;display:flex;align-items:center;gap:14px}',
'.kpi .ic{color:#8b949e;flex-shrink:0}',
'.kpi .n{font-size:24px;font-weight:700;line-height:1}.kpi .l{font-size:11px;color:#8b949e;text-transform:uppercase;letter-spacing:.05em;margin-top:5px}',
'.kpi.red .ic{color:#f85149}.kpi.amber .ic{color:#d29922}.kpi.blue .ic{color:#58a6ff}',
'.bar{display:flex;gap:8px;flex-wrap:wrap;margin-bottom:14px;align-items:center}',
'.bar button{background:#161b22;border:1px solid #30363d;color:#e6edf3;padding:8px 14px;border-radius:6px;cursor:pointer;font-size:13px}',
'.bar button.active{background:#1f6feb;border-color:#1f6feb}',
'.copybtn{background:#238636;border-color:#238636;color:#fff;margin-left:auto;display:inline-flex;align-items:center}',
'.tablewrap{overflow-x:auto;-webkit-overflow-scrolling:touch;border:1px solid #21262d;border-radius:8px}',
'table{width:100%;border-collapse:collapse;font-size:13px;min-width:520px}',
'th,td{text-align:left;padding:10px 12px;border-bottom:1px solid #21262d;white-space:nowrap}',
'th{background:#161b22;cursor:pointer;user-select:none;position:sticky;top:0}th:hover{color:#58a6ff}',
'tr.reclaim{background:#f8514915}tr.watch{background:#d2992212}tr.neverused{background:#1f6feb12}',
'.pill{display:inline-block;padding:3px 9px;border-radius:10px;font-size:11px;font-weight:600}',
'.pill.reclaim{background:#f8514933;color:#ff7b72}.pill.watch{background:#d2992233;color:#e3b341}',
'.pill.active{background:#23863633;color:#3fb950}.pill.neverused{background:#1f6feb33;color:#58a6ff}',
'.pill.unlicensed{background:#30363d;color:#8b949e}',
'td.email{font-family:ui-monospace,Menlo,monospace;font-size:12px}',
'@media(max-width:640px){',
'body{padding:14px}h1{font-size:17px}.sub{font-size:12px;margin-bottom:16px}',
'.kpi{flex:1 1 calc(50% - 6px);min-width:0;padding:12px 14px;gap:10px}',
'.kpi .n{font-size:20px}',
'.copybtn{margin-left:0;width:100%;justify-content:center}',
'.bar button{flex:1 1 auto}',
'}',
'</style></head><body>',
'<h1><img src="https://upload.wikimedia.org/wikipedia/commons/thumb/1/1d/Google_Gemini_icon_2025.svg/500px-Google_Gemini_icon_2025.svg.png" alt="" style="height:24px;width:24px;vertical-align:-5px;margin-right:9px">Gemini Enterprise — License Dashboard</h1>',
'<div class="sub">Project <b>' + PROJECT + '</b> &middot; refreshed <b>' + updated + '</b> &middot; reclaim threshold: idle &gt; ' + IDLE_RECLAIM_DAYS + 'd</div>',
'<div class="kpis">',
'<div class="kpi"><span class="ic">' + I_USERS + '</span><div><div class="n">' + assigned + ' / ' + LICENSE_CAP + '</div><div class="l">Assigned</div></div></div>',
'<div class="kpi red"><span class="ic">' + I_ALERT + '</span><div><div class="n">' + reclaim + '</div><div class="l">Reclaim &gt;' + IDLE_RECLAIM_DAYS + 'd idle</div></div></div>',
'<div class="kpi amber"><span class="ic">' + I_CLOCK + '</span><div><div class="n">' + watch + '</div><div class="l">Watch &gt;' + IDLE_WATCH_DAYS + 'd idle</div></div></div>',
'<div class="kpi blue"><span class="ic">' + I_EYEOFF + '</span><div><div class="n">' + never + '</div><div class="l">Never used</div></div></div>',
'</div>',
'<div class="bar">',
'<button data-f="all" class="active">All</button>',
'<button data-f="reclaim">Reclaim</button>',
'<button data-f="watch">Watch</button>',
'<button data-f="active">Active</button>',
'<button data-f="neverused">Never used</button>',
'<button data-f="unlicensed">No license</button>',
'<button class="copybtn" id="copy">' + I_COPY + 'Copy reclaim emails</button>',
'</div>',
'<div class="tablewrap"><table id="t"><thead><tr>',
'<th data-k="email">Email</th>',
'<th data-k="state">License</th><th data-k="assigned">Date assigned</th>',
'<th data-k="last">Last login</th><th data-k="idle">Days idle</th>',
'<th data-k="flag">Category</th></tr></thead><tbody></tbody></table></div>',
'<script>',
'var DATA=' + dataJson + ';',
'var sortK="idle",dir=-1,filt="all";var tb=document.querySelector("#t tbody");',
'function render(){var rows=DATA.filter(function(r){return filt==="all"||r.flag===filt;});',
'rows.sort(function(a,b){var x=a[sortK],y=b[sortK];',
'if(sortK==="idle"){x=x===""?-1:+x;y=y===""?-1:+y;}',
'return x<y?-1*dir:x>y?dir:0;});',
'tb.innerHTML=rows.map(function(r){return "<tr class=\\""+r.flag+"\\"><td class=\\"email\\">"+r.email+',
'"</td><td>"+r.state+"</td><td>"+(r.assigned||"\\u2014")+"</td><td>"+(r.last||"\\u2014")+',
'"</td><td>"+(r.idle===""?"\\u2014":r.idle)+"</td><td><span class=\\"pill "+r.flag+"\\">"+r.flag+"</span></td></tr>";}).join("");}',
'document.querySelectorAll("th").forEach(function(th){th.onclick=function(){var k=th.dataset.k;if(sortK===k)dir*=-1;else{sortK=k;dir=1;}render();};});',
'document.querySelectorAll(".bar button[data-f]").forEach(function(b){b.onclick=function(){',
'document.querySelectorAll(".bar button[data-f]").forEach(function(x){x.classList.remove("active");});',
'b.classList.add("active");filt=b.dataset.f;render();};});',
'document.querySelector("#copy").onclick=function(){var e=DATA.filter(function(r){return r.flag==="reclaim";}).map(function(r){return r.email;});',
'var ta=document.createElement("textarea");ta.value=e.join("\\n");document.body.appendChild(ta);ta.select();document.execCommand("copy");document.body.removeChild(ta);',
'alert("Copied "+e.length+" reclaim emails");};',
'render();',
'</script></body></html>'
  ].join('');
}
