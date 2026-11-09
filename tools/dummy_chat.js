// DEV ONLY: dummy chat messages to test "Show older messages".
//   ./dummy_chat.sh                 list the newest 10 entries (pick one)
//   ./dummy_chat.sh add <id> [n]    add n old dummy messages (default 60)
//   ./dummy_chat.sh clear <id>      remove the dummy messages again
const path = require("path");
const crypto = require("crypto");

const KEY_FILE = "tools/dev-serviceAccount.json";
const PROJECT = "haystek-pulse-dev";
// Same key as lib/services/text_crypto.dart (AES-256-GCM, "enc1:").
const AES_KEY = Buffer.from("pGnltKvOTLjl0WwLwcI9iB/oQWd0u4SzPndtKHv5i20=", "base64");

function encrypt(plain) {
  const iv = crypto.randomBytes(12);
  const c = crypto.createCipheriv("aes-256-gcm", AES_KEY, iv);
  const body = Buffer.concat([c.update(plain, "utf8"), c.final()]);
  return "enc1:" + Buffer.concat([iv, body, c.getAuthTag()]).toString("base64");
}
function decrypt(v) {
  if (typeof v !== "string" || !v.startsWith("enc1:")) return v || "";
  try {
    const d = Buffer.from(v.slice(5), "base64");
    const dc = crypto.createDecipheriv("aes-256-gcm", AES_KEY, d.subarray(0, 12));
    dc.setAuthTag(d.subarray(d.length - 16));
    return Buffer.concat([dc.update(d.subarray(12, d.length - 16)), dc.final()]).toString("utf8");
  } catch (_) { return "(could not open)"; }
}
const ist = (t) => t ? t.toDate().toLocaleString("en-IN", { timeZone: "Asia/Kolkata" }) : "?";

(async () => {
  const admin = require("firebase-admin");
  const key = require(path.resolve(KEY_FILE));
  if (key.project_id !== PROJECT) { console.log("STOP: this is only for DEV"); process.exit(1); }
  admin.initializeApp({ credential: admin.credential.cert(key) });
  const db = admin.firestore();
  const [cmd, id, nArg] = process.argv.slice(2);

  if (!cmd) {
    const snap = await db.collection("feedback").orderBy("createdAt", "desc").limit(10).get();
    console.log("DEV: newest entries (copy an id)\n");
    for (const d of snap.docs) {
      const e = d.data();
      const count = (await d.ref.collection("messages").count().get()).data().count;
      console.log(d.id + "  · " + ist(e.createdAt) + " · " + count + " messages");
      console.log("   " + decrypt(e.text).replace(/\s+/g, " ").slice(0, 60) + "\n");
    }
    process.exit(0);
  }

  if (!id) { console.log("Use: ./dummy_chat.sh add|clear <id> [n]"); process.exit(1); }
  const ref = db.collection("feedback").doc(id);
  if (!(await ref.get()).exists) { console.log("STOP: no entry with id " + id); process.exit(1); }
  const msgs = ref.collection("messages");

  if (cmd === "add") {
    const n = Math.min(Math.max(Number(nArg) || 60, 1), 300);
    // Put them before the oldest real message, 10 minutes apart.
    const oldest = await msgs.orderBy("createdAt").limit(1).get();
    const end = oldest.empty ? Date.now() : oldest.docs[0].data().createdAt.toMillis();
    const start = end - 60 * 60 * 1000 - n * 10 * 60 * 1000;
    let batch = db.batch(), inBatch = 0;
    for (let i = 1; i <= n; i++) {
      batch.set(msgs.doc(), {
        from: i % 2 ? "e" : "m",
        text: encrypt("Dummy " + i),
        createdAt: admin.firestore.Timestamp.fromMillis(start + i * 10 * 60 * 1000),
        dummy: true,
      });
      if (++inBatch === 400) { await batch.commit(); batch = db.batch(); inBatch = 0; }
    }
    if (inBatch) await batch.commit();
    console.log("Added " + n + " dummy messages (Dummy 1 = oldest, Dummy " + n + " = newest dummy).");
  } else if (cmd === "clear") {
    const snap = await msgs.where("dummy", "==", true).get();
    let batch = db.batch(), inBatch = 0;
    for (const d of snap.docs) {
      batch.delete(d.ref);
      if (++inBatch === 400) { await batch.commit(); batch = db.batch(); inBatch = 0; }
    }
    if (inBatch) await batch.commit();
    console.log("Removed " + snap.size + " dummy messages. Real messages untouched.");
  } else {
    console.log("Use: ./dummy_chat.sh | add <id> [n] | clear <id>");
  }
  process.exit(0);
})().catch((err) => { console.log("ERROR: " + err.message); process.exit(1); });
