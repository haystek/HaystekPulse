// "Please update" settings (Firestore settings/app).
//
// After a release is LIVE in the store (reads the version from pubspec.yaml):
//   ./app_update.sh prod --released android
//   ./app_update.sh prod --released ios
//   ./app_update.sh prod --released both
//
// Other:
//   ./app_update.sh dev  --show
//   ./app_update.sh dev  --clear both            (nobody is asked to update)
//   ./app_update.sh dev  --set android 1.1.2+2   (a version by hand)
//   ./app_update.sh dev  --android-url "https://..." --ios-url "https://..."
//   ./app_update.sh dev  --message "text"
// prod always asks you to type PROD.
const fs = require("fs");
const path = require("path");
const readline = require("readline");

const KEYS = {
  dev: { file: "tools/dev-serviceAccount.json", project: "haystek-pulse-dev" },
  prod: { file: "tools/create_users/serviceAccount.json", project: "haystek-pulse" },
};
const FIELD = { android: ["latestAndroid"], ios: ["latestIos"], both: ["latestAndroid", "latestIos"] };
const VERSION = /^\d+(\.\d+)*(\+\d+)?$/;

const env = process.argv[2];
const args = process.argv.slice(3);
const usage = () => {
  console.log("Use: ./app_update.sh dev|prod --released android|ios|both");
  console.log("     ./app_update.sh dev|prod --show | --clear android|ios|both | --set android|ios|both 1.1.2+2");
  console.log('     ./app_update.sh dev|prod --android-url URL | --ios-url URL | --message "text"');
  process.exit(1);
};
if (!KEYS[env]) usage();

function pubspecVersion() {
  const m = fs.readFileSync("pubspec.yaml", "utf8").match(/^version:\s*(\S+)\s*$/m);
  if (!m || !VERSION.test(m[1])) { console.log("pubspec.yaml: version line not found (like version: 1.1.2+2)"); process.exit(1); }
  return m[1];
}

const update = {};
let show = false;
for (let i = 0; i < args.length; i++) {
  const a = args[i];
  const next = () => { if (i + 1 >= args.length) usage(); return args[++i]; };
  const which = () => { const w = next(); if (!FIELD[w]) usage(); return FIELD[w]; };
  if (a === "--show") show = true;
  else if (a === "--released") { const v = pubspecVersion(); for (const f of which()) update[f] = v; }
  else if (a === "--clear") { for (const f of which()) update[f] = ""; }
  else if (a === "--set") {
    const fields = which();
    const v = next().trim();
    if (!VERSION.test(v)) { console.log("Version must look like 1.1.2+2 or 1.1.2"); process.exit(1); }
    for (const f of fields) update[f] = v;
  }
  else if (a === "--android-url") update.androidUrl = next().trim();
  else if (a === "--ios-url") update.iosUrl = next().trim();
  else if (a === "--message") update.message = next().trim();
  else usage();
}
for (const k of ["androidUrl", "iosUrl"]) {
  if (update[k] && !/^https:\/\//.test(update[k])) { console.log(k + " must start with https://"); process.exit(1); }
}
if (!show && Object.keys(update).length === 0) usage();

const ask = (q) => new Promise((res) => {
  const rl = readline.createInterface({ input: process.stdin, output: process.stdout });
  rl.question(q, (ans) => { rl.close(); res(ans); });
});

(async () => {
  const admin = require("firebase-admin");
  const key = require(path.resolve(KEYS[env].file));
  if (key.project_id !== KEYS[env].project) { console.log("STOP: " + KEYS[env].file + " is for " + key.project_id); process.exit(1); }
  admin.initializeApp({ credential: admin.credential.cert(key) });
  const ref = admin.firestore().doc("settings/app");

  if (Object.keys(update).length > 0) {
    console.log((env === "prod" ? "\x1b[1;41m LIVE \x1b[0m " : "DEV ") + "settings/app will get:", update);
    if (env === "prod") {
      if (update.latestAndroid || update.latestIos) {
        console.log("Only do this when the new version is already LIVE in the store.");
      }
      const ans = await ask("Type PROD to change LIVE: ");
      if (ans !== "PROD") { console.log("Cancelled. Nothing changed."); process.exit(1); }
    }
    await ref.set(update, { merge: true });
    console.log("Saved.");
  }
  const now = (await ref.get()).data() || {};
  console.log(env.toUpperCase() + " settings/app now:", now);
  process.exit(0);
})().catch((e) => { console.log("ERROR: " + e.message); process.exit(1); });
