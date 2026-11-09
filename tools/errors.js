// Show the latest error notes from the app (read only).
//   ./errors.sh dev        newest 20 from DEV
//   ./errors.sh prod       newest 20 from LIVE
//   ./errors.sh prod 50    newest 50
const path = require("path");
const KEYS = {
  dev: { file: "tools/dev-serviceAccount.json", project: "haystek-pulse-dev" },
  prod: { file: "tools/create_users/serviceAccount.json", project: "haystek-pulse" },
};
const env = process.argv[2];
const count = Math.min(Number(process.argv[3]) || 20, 200);
if (!KEYS[env]) { console.log("Use: ./errors.sh dev|prod [how many]"); process.exit(1); }
(async () => {
  const admin = require("firebase-admin");
  const key = require(path.resolve(KEYS[env].file));
  if (key.project_id !== KEYS[env].project) { console.log("STOP: wrong key file"); process.exit(1); }
  admin.initializeApp({ credential: admin.credential.cert(key) });
  const snap = await admin.firestore().collection("errors").orderBy("at", "desc").limit(count).get();
  if (snap.empty) { console.log(env.toUpperCase() + ": no errors. 🎉"); process.exit(0); }
  console.log(env.toUpperCase() + ": newest " + snap.size + " errors\n");
  for (const d of snap.docs) {
    const e = d.data();
    const when = e.at ? e.at.toDate().toLocaleString("en-IN", { timeZone: "Asia/Kolkata" }) : "?";
    console.log("── " + when + " · " + e.platform + " · v" + e.version);
    console.log("   " + e.error);
    const firstOwn = (e.where || "").split("\n").find((l) => l.includes("package:haystek_pulse")) || (e.where || "").split("\n")[0] || "";
    console.log("   at " + firstOwn.trim() + "\n");
  }
  process.exit(0);
})().catch((err) => { console.log("ERROR: " + err.message); process.exit(1); });
