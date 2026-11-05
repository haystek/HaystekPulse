/**
 * Haystek Pulse: automatic notifications.
 * 15 minutes before the Weekly Pulse opens, tell all employees.
 * Live time: Friday 5:45 PM (India time). For testing, change the time
 * in Cloud Scheduler (the next deploy sets it back to this time).
 */

const { onSchedule } = require("firebase-functions/v2/scheduler");
const admin = require("firebase-admin");

admin.initializeApp();

exports.pulseHeadsUp = onSchedule(
  {
    // minute hour day-of-month month day-of-week (5 = Friday)
    schedule: "45 19 * * 1",
    timeZone: "Asia/Kolkata",
    region: "asia-south1",
  },
  async () => {
    const title = "Weekly Pulse opens in 15 minutes 💙";
    const body = "Take a minute to rate your week when it opens.";

    await admin.messaging().send({
      topic: "employees",
      notification: { title, body },
      data: { type: "pulse_soon" },
      android: {
        priority: "high",
        notification: {
          channelId: "haystek_alerts",
          icon: "ic_notification",
        },
      },
      apns: {
        payload: { aps: { sound: "default" } },
      },
    });

    console.log("Weekly Pulse heads-up sent to employees.");
  }
);

// ---------------------------------------------------------------------------
// One-time join codes.
// join_codes/{SHA-256 of the code} = { code, slot, active, createdAt, usedAt? }
// topUpCodes: when a code is used, only its place gets a new code.
// codes: the "Pulse Codes" page for Zoho People. Opens only with ?k=SECRET.
//   The open page asks "did anything change?" every 10 seconds (1 tiny read)
//   and reloads only when a code was used. Paused when the tab is hidden.
// Nothing here knows who used a code: only "active" and the time.
// ---------------------------------------------------------------------------

const { onDocumentUpdated } = require("firebase-functions/v2/firestore");
const { onRequest } = require("firebase-functions/v2/https");
const { defineSecret } = require("firebase-functions/params");
const crypto = require("crypto");

const db = admin.firestore();
const REGION = "asia-south1";
const PAGE_KEY = defineSecret("CODES_PAGE_KEY");
const FRAME_PARENTS =
  "'self' https://*.zoho.com https://*.zoho.in https://*.zohopeople.com https://*.zohopeople.in";

const ACTIVE_CODES = 20;
const CODE_LENGTH = 6;
const LETTERS = "23456789ABCDEFGHJKMNPQRSTUVWXYZ";
const VERSION_DOC = db.doc("meta/join_codes");

const sha256 = (text) =>
  crypto.createHash("sha256").update(text, "utf8").digest("hex");

function newCode() {
  let c = "";
  for (let i = 0; i < CODE_LENGTH; i++) {
    c += LETTERS[crypto.randomInt(LETTERS.length)];
  }
  return c;
}

async function topUp() {
  const col = db.collection("join_codes");
  const active = await col.where("active", "==", true).get();
  const taken = new Set();
  const noSlot = [];
  active.docs.forEach((d) => {
    const s = d.get("slot");
    if (Number.isInteger(s) && s >= 0 && s < ACTIVE_CODES && !taken.has(s)) {
      taken.add(s);
    } else {
      noSlot.push(d);
    }
  });
  const free = [];
  for (let s = 0; s < ACTIVE_CODES; s++) if (!taken.has(s)) free.push(s);
  let changed = false;
  for (const d of noSlot) {
    const s = free.shift();
    if (s === undefined) break;
    await d.ref.update({ slot: s });
    changed = true;
  }
  let tries = 0;
  while (free.length > 0 && tries < ACTIVE_CODES * 3) {
    tries++;
    const code = newCode();
    try {
      await col.doc(sha256(code)).create({
        code,
        slot: free[0],
        active: true,
        createdAt: admin.firestore.FieldValue.serverTimestamp(),
      });
      free.shift();
      changed = true;
    } catch (e) {
      if (e.code !== 6) throw e;
    }
  }
  if (changed) await bumpVersion();
  return changed ? null : active.docs;
}

async function bumpVersion() {
  await VERSION_DOC.set(
    { version: admin.firestore.FieldValue.increment(1) },
    { merge: true }
  );
}

async function currentVersion() {
  const v = (await VERSION_DOC.get()).get("version");
  return Number.isInteger(v) ? v : 0;
}

exports.topUpCodes = onDocumentUpdated(
  { document: "join_codes/{id}", region: REGION },
  async (event) => {
    const before = event.data.before.data();
    const after = event.data.after.data();
    if (before.active === true && after.active === false) {
      await bumpVersion();
      await topUp();
    }
  }
);

const esc = (s) =>
  String(s).replace(/[&<>"']/g, (ch) =>
    ({ "&": "&amp;", "<": "&lt;", ">": "&gt;", '"': "&quot;", "'": "&#39;" })[ch]);

function codesPage(codes, version) {
  const items = codes
    .map((c) => `<li><button class="code" data-code="${esc(c)}" title="Tap to copy">${esc(c)}<span class="cp">Copy</span></button></li>`)
    .join("");
  const empty = '<li class="none">No codes right now. Please refresh in a minute.</li>';
  return `<!doctype html><html lang="en"><head><meta charset="utf-8">
<meta name="viewport" content="width=device-width,initial-scale=1">
<meta name="robots" content="noindex,nofollow">
<title>Pulse Codes</title>
<link href="https://fonts.googleapis.com/css2?family=Lato:wght@400;700&display=swap" rel="stylesheet">
<style>
:root{--accent:#E8572A;--accent-soft:#FFF4EF;--ink:#2D3036;--muted:#6B7078;--line:#E3E5E8;--bg:#F5F6F8}
*{box-sizing:border-box}
html,body{margin:0;background:var(--bg);color:var(--ink);font-family:Lato,"Segoe UI",Roboto,Helvetica,Arial,sans-serif;-webkit-text-size-adjust:100%}
.wrap{max-width:980px;margin:0 auto;padding:20px 16px 32px}
.panel{background:#fff;border:1px solid var(--line);border-radius:8px;box-shadow:0 1px 2px rgba(0,0,0,.04)}
.head{display:flex;align-items:center;justify-content:space-between;gap:12px;padding:16px 20px;border-bottom:1px solid var(--line);flex-wrap:wrap}
.head h1{margin:0;font-size:18px;font-weight:700}
.head p{margin:2px 0 0;font-size:13px;color:var(--muted)}
.live{display:inline-flex;align-items:center;gap:6px;font-size:12px;color:var(--muted);background:var(--bg);border:1px solid var(--line);border-radius:999px;padding:4px 10px;white-space:nowrap}
.live i{width:8px;height:8px;border-radius:50%;background:#2E9E5B;box-shadow:0 0 0 3px rgba(46,158,91,.15)}
.body{padding:18px 20px 20px}
.how{background:var(--accent-soft);border-left:3px solid var(--accent);border-radius:4px;padding:12px 14px;font-size:14px;line-height:1.6;margin-bottom:18px}
.how b{font-weight:700}
ul{list-style:none;padding:0;margin:0;display:grid;grid-template-columns:repeat(auto-fill,minmax(150px,1fr));gap:10px}
.code{position:relative;width:100%;background:#fff;border:1px solid var(--line);border-radius:6px;padding:16px 8px;cursor:pointer;
  font:700 19px/1 ui-monospace,SFMono-Regular,Menlo,Consolas,monospace;letter-spacing:.16em;color:var(--ink);transition:border-color .15s,box-shadow .15s}
.code:hover,.code:focus-visible{border-color:var(--accent);box-shadow:0 0 0 3px rgba(232,87,42,.12);outline:none}
.cp{position:absolute;right:6px;top:5px;font:700 10px Lato,sans-serif;letter-spacing:.04em;color:var(--accent);opacity:0;transition:opacity .15s}
.code:hover .cp{opacity:1}
.none{grid-column:1/-1;text-align:center;color:var(--muted);font-size:14px;padding:24px}
.note{margin-top:16px;font-size:12.5px;color:var(--muted);line-height:1.5}
.toast{position:fixed;left:50%;bottom:24px;transform:translateX(-50%) translateY(20px);background:var(--ink);color:#fff;font-size:13px;padding:9px 16px;border-radius:6px;opacity:0;transition:all .2s;pointer-events:none;z-index:20}
.toast.on{opacity:1;transform:translateX(-50%) translateY(0)}
#more{display:none;position:fixed;inset:0;z-index:10;background:rgba(45,48,54,.35);-webkit-backdrop-filter:blur(5px);backdrop-filter:blur(5px);align-items:center;justify-content:center;padding:16px}
#more .box{background:#fff;border-radius:8px;padding:24px 20px;max-width:340px;width:100%;text-align:center;box-shadow:0 20px 50px -20px rgba(0,0,0,.4)}
#more .ic{width:48px;height:48px;border-radius:50%;margin:0 auto 12px;background:var(--accent-soft);display:flex;align-items:center;justify-content:center}
#more h2{margin:0;font-size:17px;font-weight:700}
#more p{margin:6px 0 18px;font-size:14px;color:var(--muted);line-height:1.45}
#mb{width:100%;height:42px;border:0;border-radius:6px;background:var(--accent);color:#fff;font:700 14.5px Lato,sans-serif;cursor:pointer}
#mb:hover{filter:brightness(.95)}
@media (max-width:520px){
  .wrap{padding:12px 10px 24px}
  .head,.body{padding-left:14px;padding-right:14px}
  ul{grid-template-columns:repeat(2,1fr);gap:8px}
  .code{font-size:17px;padding:15px 4px;letter-spacing:.12em}
  .cp{display:none}
  .how{font-size:13.5px}
}
</style></head><body><div class="wrap"><div class="panel">
<div class="head"><div><h1>Pulse Codes</h1><p>Haystek employees only</p></div><span class="live"><i></i>Updates automatically</span></div>
<div class="body">
<div class="how"><b>How to join:</b> pick <b>any one</b> code and enter it in the Haystek Pulse app. Each code works only once. If the app says it's used, pick another one. Nobody knows which code you picked.</div>
<ul>${items || empty}</ul>
<div class="note">Tap a code to copy it. Please don't share these codes outside Haystek.</div>
</div></div></div>
<div class="toast" id="toast">Code copied</div>
<div id="more"><div class="box"><div class="ic"><svg width="22" height="22" viewBox="0 0 24 24" fill="none" stroke="#E8572A" stroke-width="2.2" stroke-linecap="round" stroke-linejoin="round"><path d="M21 12a9 9 0 1 1-3-6.7"/><path d="M21 3v6h-6"/></svg></div><h2>Still there?</h2><p>Tap Refresh to see the latest codes.</p><button id="mb">Refresh</button></div></div>
<script>(function(){var v=${Number(version) || 0},start=Date.now(),LIMIT=300000,more=document.getElementById("more"),seen=true,lastFrame=Date.now();
(function loop(){lastFrame=Date.now();requestAnimationFrame(loop)})();
function onScreen(){return seen&&document.visibilityState==="visible"&&window.innerWidth>0&&window.innerHeight>0&&Date.now()-lastFrame<3000}
function ask(){fetch(location.pathname+(location.search?location.search+"&v=1":"?v=1"),{cache:"no-store"}).then(function(r){return r.json()})
.then(function(d){if(d&&d.v!==v)location.reload()}).catch(function(){})}
function tick(){if(Date.now()-start>LIMIT){more.style.display="flex";return}
if(onScreen())ask()}
setInterval(tick,10000);
document.getElementById("mb").onclick=function(){location.reload()};
document.addEventListener("visibilitychange",function(){setTimeout(function(){if(onScreen()&&Date.now()-start<=LIMIT)ask()},500)});
if("IntersectionObserver" in window){new IntersectionObserver(function(e){seen=e[0].isIntersecting}).observe(document.querySelector(".wrap"))}
var toast=document.getElementById("toast"),tt;
function copy(t){var ok=false;try{var a=document.createElement("textarea");a.value=t;a.setAttribute("readonly","");a.style.position="fixed";a.style.opacity="0";document.body.appendChild(a);a.select();ok=document.execCommand("copy");document.body.removeChild(a)}catch(e){}
if(!ok&&navigator.clipboard){navigator.clipboard.writeText(t).catch(function(){})}
toast.textContent="Code "+t+" copied";toast.classList.add("on");clearTimeout(tt);tt=setTimeout(function(){toast.classList.remove("on")},1600)}
document.querySelectorAll(".code").forEach(function(b){b.onclick=function(){copy(b.getAttribute("data-code"))}});})();</script>
</body></html>`;
}

exports.codes = onRequest(
  { region: REGION, secrets: [PAGE_KEY], maxInstances: 2, invoker: "public" },
  async (req, res) => {
    res.set("Cache-Control", "no-store");
    res.set("Content-Security-Policy", `frame-ancestors ${FRAME_PARENTS}`);
    res.set("Referrer-Policy", "no-referrer");
    const key = String(req.query.k || req.path.split("/").filter(Boolean).pop() || "");
    const secret = PAGE_KEY.value();
    const ok = key.length === secret.length &&
      crypto.timingSafeEqual(Buffer.from(key), Buffer.from(secret));
    if (!ok) {
      res.status(404).send("Not found");
      return;
    }
    if (req.query.v === "1") {
      res.status(200).json({ v: await currentVersion() });
      return;
    }
    const cached = await topUp();
    const docs = cached || (await db.collection("join_codes").where("active", "==", true).get()).docs;
    const codes = docs
      .sort((a, b) => (a.get("slot") ?? 99) - (b.get("slot") ?? 99))
      .map((d) => d.get("code"));
    res.status(200).type("html").send(codesPage(codes, await currentVersion()));
  }
);
