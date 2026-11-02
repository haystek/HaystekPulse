// Replaces ALL entry codes in one go: deletes every old employee code
// (entry_codes) and every old admin code (admin_codes), then adds the new
// ones. Hashed exactly the way the app checks them (SHA-256 of the code
// in CAPITALS, spaces removed).
//
//   node set_codes.js HST_EMP HST_ADM     employee code, then admin code
//   node set_codes.js list                show what is in Firestore now
//
// People who already joined are not affected.
// Put this file in tools/create_users (it uses the same serviceAccount.json).
// Never push serviceAccount.json to GitHub.

const crypto = require('crypto');
const path = require('path');
const admin = require('firebase-admin');

admin.initializeApp({
  credential: admin.credential.cert(require(path.join(__dirname, 'serviceAccount.json'))),
});
const db = admin.firestore();

const clean = (c) => (c || '').trim().toUpperCase().replace(/\s+/g, '');
const hash = (c) => crypto.createHash('sha256').update(c).digest('hex');

async function list() {
  for (const col of ['entry_codes', 'admin_codes']) {
    const snap = await db.collection(col).get();
    console.log(`${col}: ${snap.size}`);
    snap.forEach((d) => console.log(`  ${d.id} (length ${d.id.length})`));
  }
}

async function wipe(col) {
  const snap = await db.collection(col).get();
  const batch = db.batch();
  snap.forEach((d) => batch.delete(d.ref));
  await batch.commit();
  console.log(`Deleted ${snap.size} old code(s) from ${col}`);
}

(async () => {
  const [a, b] = process.argv.slice(2);
  if (a === 'list') return list();

  const emp = clean(a);
  const adm = clean(b);
  if (!emp || !adm) {
    console.log('Usage: node set_codes.js EMPLOYEE_CODE ADMIN_CODE   or   node set_codes.js list');
    process.exit(1);
  }
  if (emp === adm) {
    console.log('The employee and admin codes must be different.');
    process.exit(1);
  }

  await wipe('entry_codes');
  await wipe('admin_codes');
  await db.collection('entry_codes').doc(hash(emp)).set({ role: 'employee' });
  await db.collection('admin_codes').doc(hash(adm)).set({ role: 'admin' });
  console.log(`Employee code: ${emp}  ->  entry_codes/${hash(emp)}`);
  console.log(`Admin code:    ${adm}  ->  admin_codes/${hash(adm)}`);
  console.log('');
  await list();
})().catch((e) => {
  console.error(e.message);
  process.exit(1);
});
