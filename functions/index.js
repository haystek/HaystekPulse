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
  const items = codes.map((c) => `<li>${esc(c)}</li>`).join("");
  const empty = '<li style="grid-column:1/-1;font:500 14px Inter,sans-serif;letter-spacing:0;color:#5F6A84">No codes right now. Please refresh in a minute.</li>';
  return `<!doctype html><html lang="en"><head><meta charset="utf-8">
<meta name="viewport" content="width=device-width,initial-scale=1">
<meta name="robots" content="noindex,nofollow">
<title>Pulse Codes</title>
<link href="https://fonts.googleapis.com/css2?family=Inter:wght@400;500;600;700&display=swap" rel="stylesheet">
<style>
:root{--blue:#2453D6;--ink:#0E1A3A;--muted:#5F6A84;--line:#E3E8F1;--tint:#EEF3FF}
*{box-sizing:border-box}body{margin:0;background:#fff;font-family:Inter,system-ui,sans-serif;color:var(--ink)}
.wrap{max-width:720px;margin:0 auto;padding:28px 16px 40px}
.top{display:flex;align-items:center;gap:12px}
.badge{width:46px;height:46px;border-radius:15px;background:linear-gradient(135deg,#0B1B4D,#14328F 55%,#2453D6);display:flex;align-items:center;justify-content:center}
h1{font-size:22px;margin:0;font-weight:700;letter-spacing:-.02em}
.sub{color:var(--muted);font-size:14px;margin-top:2px}
.how{margin:20px 0 18px;background:var(--tint);border-radius:16px;padding:14px 16px;font-size:14px;line-height:1.6}
.how b{font-weight:600}
ul{list-style:none;padding:0;margin:0;display:grid;grid-template-columns:repeat(auto-fill,minmax(130px,1fr));gap:10px}
li{border:1.5px solid var(--line);border-radius:14px;padding:14px 8px;text-align:center;font:600 20px ui-monospace,Menlo,Consolas,monospace;letter-spacing:.14em;color:var(--blue)}
.note{margin-top:18px;color:#8E97AB;font-size:12.5px;line-height:1.5}
</style></head><body><div class="wrap">
<div class="top"><div class="badge"><svg width="22" height="22" viewBox="0 0 24 24" fill="none" stroke="#fff" stroke-width="2" stroke-linecap="round" stroke-linejoin="round"><circle cx="8" cy="15" r="4"/><path d="M10.8 12.2L20 3M16 7l3 3"/></svg></div>
<div><h1>Haystek Pulse – Join codes</h1><div class="sub">For Haystek employees only</div></div></div>
<div class="how"><b>How to join:</b> pick <b>any one</b> code below and enter it in the Haystek Pulse app.<br>
Each code works only once. If the app says it's used, pick another one.<br>
Nobody knows which code you picked.</div>
<ul>${items || empty}</ul>
<div class="note">This list updates by itself when a code is used. Please don't share these codes outside Haystek.</div>
</div>
<div id="more" style="display:none;position:fixed;inset:0;z-index:10;background:rgba(14,26,58,.28);-webkit-backdrop-filter:blur(6px);backdrop-filter:blur(6px);align-items:center;justify-content:center;padding:16px"><div style="background:#fff;border-radius:24px;padding:26px 22px;max-width:340px;width:100%;text-align:center;box-shadow:0 24px 60px -20px rgba(14,26,58,.45)"><div style="width:56px;height:56px;border-radius:18px;margin:0 auto 14px;background:linear-gradient(135deg,#0B1B4D,#14328F 55%,#2453D6);display:flex;align-items:center;justify-content:center"><svg width="26" height="26" viewBox="0 0 24 24" fill="none" stroke="#fff" stroke-width="2.2" stroke-linecap="round" stroke-linejoin="round"><path d="M21 12a9 9 0 1 1-3-6.7"/><path d="M21 3v6h-6"/></svg></div><div style="font:600 19px Inter,sans-serif;color:#0E1A3A">Codes may have changed</div><div style="font:400 14px/1.45 Inter,sans-serif;color:#5F6A84;margin:6px 0 18px">Tap to see the latest codes.</div><button id="mb" style="width:100%;height:48px;border:0;border-radius:24px;background:#2453D6;color:#fff;font:600 15.5px Inter,sans-serif;cursor:pointer">Refresh codes</button></div></div>
<script>(function(){var v=${Number(version) || 0},start=Date.now(),LIMIT=600000,more=document.getElementById("more"),seen=true,lastFrame=Date.now();
(function loop(){lastFrame=Date.now();requestAnimationFrame(loop)})();
function onScreen(){return seen&&document.visibilityState==="visible"&&window.innerWidth>0&&window.innerHeight>0&&Date.now()-lastFrame<3000}
function ask(){fetch(location.pathname+(location.search?location.search+"&v=1":"?v=1"),{cache:"no-store"}).then(function(r){return r.json()})
.then(function(d){if(d&&d.v!==v)location.reload()}).catch(function(){})}
function tick(){if(Date.now()-start>LIMIT){more.style.display="flex";return}
if(onScreen())ask()}
setInterval(tick,10000);
document.getElementById("mb").onclick=function(){location.reload()};
document.addEventListener("visibilitychange",function(){setTimeout(function(){if(onScreen()&&Date.now()-start<=LIMIT)ask()},500)});
if("IntersectionObserver" in window){new IntersectionObserver(function(e){seen=e[0].isIntersecting}).observe(document.querySelector(".wrap"))}})();</script>
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
    await topUp();
    const snap = await db.collection("join_codes").where("active", "==", true).get();
    const codes = snap.docs
      .sort((a, b) => (a.get("slot") ?? 99) - (b.get("slot") ?? 99))
      .map((d) => d.get("code"));
    res.status(200).type("html").send(codesPage(codes, await currentVersion()));
  }
);
