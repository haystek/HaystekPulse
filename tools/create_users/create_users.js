// Creates Haystek Pulse logins from a sheet, in one go.
//
//   node create_users.js employees.csv
//
// employees.csv has one row per person:
//   name,employeeId,email,role        (role = employee or management)
//
// For each row it:
//   1. creates the Firebase login (email + password Welcome@123),
//   2. adds the person to the `employees` collection
//      (doc ID = their login UID, the same as the app expects),
//   3. writes the result to logins.csv (opens in Excel).
//
// Safe to run again: people who already have a login are not changed
// and their password is NOT reset. They show as "Already existed".
//
// Needs serviceAccount.json in this folder
// (Firebase console → Project settings → Service accounts →
// Generate new private key). Never push it to GitHub.

const fs = require('fs');
const path = require('path');
const admin = require('firebase-admin');

const PASSWORD = 'Welcome@123';

const input = process.argv[2];
if (!input) {
  console.log('Usage: node create_users.js employees.csv');
  process.exit(1);
}

admin.initializeApp({
  credential: admin.credential.cert(require('./serviceAccount.json')),
});
const auth = admin.auth();
const db = admin.firestore();

/** Reads a simple CSV (commas, optional quotes) into objects. */
function readCsv(file) {
  const lines = fs
    .readFileSync(file, 'utf8')
    .replace(/^﻿/, '') // Excel adds this at the start
    .split(/\r?\n/)
    .filter((l) => l.trim() !== '');
  const split = (line) =>
    (line.match(/("([^"]|"")*"|[^,]*)(,|$)/g) || [])
      .map((c) => c.replace(/,$/, '').replace(/^"|"$/g, '').replace(/""/g, '"').trim())
      .slice(0, -1);
  const head = split(lines[0]).map((h) => h.toLowerCase());
  return lines.slice(1).map((line, i) => {
    const cells = split(line);
    const row = { line: i + 2 };
    head.forEach((h, j) => (row[h] = cells[j] || ''));
    return row;
  });
}

const csvCell = (v) => `"${String(v ?? '').replace(/"/g, '""')}"`;

async function main() {
  const rows = readCsv(input);
  const out = [['Name', 'Employee ID', 'Email', 'Password', 'Role', 'Result']];
  let created = 0, existed = 0, failed = 0;

  for (const r of rows) {
    const name = r.name;
    const employeeId = (r.employeeid || '').toUpperCase();
    const email = (r.email || '').toLowerCase();
    const role = (r.role || 'employee').toLowerCase();
    const type = role.startsWith('m') ? 'm' : 'e';
    const roleLabel = type === 'm' ? 'Management' : 'Employee';

    if (!name || !email.includes('@')) {
      out.push([name, employeeId, email, '', roleLabel, `Skipped: row ${r.line} needs a name and email`]);
      failed++;
      continue;
    }

    try {
      let user;
      let isNew = false;
      try {
        user = await auth.getUserByEmail(email);
      } catch (e) {
        if (e.code !== 'auth/user-not-found') throw e;
        user = await auth.createUser({
          email,
          password: PASSWORD,
          displayName: name,
        });
        isNew = true;
      }

      // The app reads: employeeId, name, type, mustChangePassword, active.
      const doc = db.collection('employees').doc(user.uid);
      const snap = await doc.get();
      if (!snap.exists) {
        await doc.set({
          employeeId,
          name,
          type,
          mustChangePassword: true,
          active: true,
          email,
          createdAt: admin.firestore.FieldValue.serverTimestamp(),
        });
      }

      if (isNew) {
        created++;
        out.push([name, employeeId, email, PASSWORD, roleLabel, 'Created']);
        console.log(`✓ ${email}`);
      } else {
        existed++;
        out.push([name, employeeId, email, '(unchanged)', roleLabel,
          snap.exists ? 'Already existed' : 'Login existed, added to app']);
        console.log(`• ${email} already existed`);
      }
    } catch (e) {
      failed++;
      out.push([name, employeeId, email, '', roleLabel, `Failed: ${e.message}`]);
      console.log(`✗ ${email}: ${e.message}`);
    }
  }

  const file = path.join(__dirname, 'logins.csv');
  fs.writeFileSync(file, '﻿' + out.map((r) => r.map(csvCell).join(',')).join('\r\n'));
  console.log(`\nDone. Created ${created}, already existed ${existed}, failed ${failed}.`);
  console.log(`Sheet: ${file}`);
}

main().then(() => process.exit(0)).catch((e) => {
  console.error(e);
  process.exit(1);
});
