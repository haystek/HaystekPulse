// Adds, lists or removes the employee entry code(s) in Firestore,
// exactly the way the app checks them (SHA-256 of the code in CAPITALS).
//
//   node entry_code.js add HSTLGN      add a code
//   node entry_code.js check HSTLGN    is this code in Firestore?
//   node entry_code.js remove HSTLGN   remove a code (old code stops working)
//   node entry_code.js list            how many codes are active
//
// Put this file in the create_users folder (it uses the same
// serviceAccount.json). Never push serviceAccount.json to GitHub.

const crypto = require('crypto');
const path = require('path');
const admin = require('firebase-admin');

admin.initializeApp({
  credential: admin.credential.cert(require(path.join(__dirname, 'serviceAccount.json'))),
});
const db = admin.firestore();

const [cmd, raw] = process.argv.slice(2);
const code = (raw || '').trim().toUpperCase().replace(/\s+/g, '');
const hash = crypto.createHash('sha256').update(code).digest('hex');
const ref = db.collection('entry_codes').doc(hash);

(async () => {
  if (cmd === 'list') {
    const snap = await db.collection('entry_codes').get();
    console.log(`${snap.size} entry code(s) in Firestore:`);
    snap.forEach((d) => console.log(`  [${d.id}] (length ${d.id.length})`));
    return;
  }
  if (!code) {
    console.log('Usage: node entry_code.js add|check|remove CODE   or   node entry_code.js list');
    process.exit(1);
  }
  if (cmd === 'add') {
    await ref.set({ role: 'employee' });
    console.log(`Added ${code}  ->  entry_codes/${hash}`);
  } else if (cmd === 'check') {
    const d = await ref.get();
    console.log(d.exists ? `${code} is ACTIVE` : `${code} is NOT in Firestore`);
  } else if (cmd === 'remove') {
    await ref.delete();
    console.log(`Removed ${code}`);
  } else {
    console.log('Unknown command. Use add, check, remove or list.');
  }
})().catch((e) => {
  console.error(e.message);
  process.exit(1);
});
