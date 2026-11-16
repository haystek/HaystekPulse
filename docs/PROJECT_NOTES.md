# Haystek Pulse – Project Notes (as of 16 Nov 2026)

Give this file to Claude at the start of any new chat: "Read this first."

## 1. Basics
- Flutter + Firebase app. Mac path: `/Users/haystek/haystek_pulse`, branch `branch3`, repo `haystek/HaystekPulse` (private).
- Flavors: `dev` → Firebase `haystek-pulse-dev`, `prod` → `haystek-pulse` (LIVE).
- One bundle ID for both: `com.haystek.haystekPulse`, Apple Team `T6LJAQ4AL7`, App Store Apple ID `6833529873`.
- Firebase account: mobileapp@haystek.com (Owner). shivakumar.t@haystek.com is also Owner. Billing account `01CFFA-F4B1B1-1B6168` "My Billing Account" (Haystek org, INR). Blaze plan. Linked projects: haystek-pulse, haystek-pulse-dev, My First Project (empty default).
- Company (for Google/Apple forms): HAYSTEK TECHNOLOGIES PRIVATE LIMITED, No. 1-53, Plot No. 27, Phase-I, Third Floor, Kavuri Hills, Madhapur, Shaikpet, Hyderabad, Telangana 500081.
- Functions (same in DEV and LIVE, asia-south1, 256 MB, nodejs24):
  - `codes` (https): gives join codes to the Zoho Pulse Codes page.
  - `topUpCodes` (Firestore update trigger): a used join code is replaced by a new one (keeps 20).
  - `pulseHeadsUp` (scheduled, the only timed job): sends "Weekly Pulse opens in 15 minutes 💙 / Take a minute to rate your week when it opens." to topic `employees`, and "Weekly Pulse opens in 15 minutes / Employees are being reminded now. Responses will show on your dashboard." to topic `management`. Time is fixed in `functions/index.js` (`schedule:`), NOT linked to the app's Weekly Pulse settings: when admin changes the open time, change this line too and deploy. Website edit (Cloud Scheduler → Edit → Frequency) works for quick tests but the next deploy resets it.
- Weekly Pulse open time: Firestore `settings/pulse` → `openDay` (1 = Monday), `openHour`, `openMinute`, `openDays`. DEV on 16 Nov: Monday 12:22 PM, open 5 days.
- Read-only check of pulse settings + job time: `checkpulse.js` (LIVE key path not found yet; find with `ls *.json tools/*.json tools/*/*.json`).
- Hosting folder `hosting/` (privacy.html, join.html, index.html). Privacy contact: mobileapp@haystek.com.
- Settings: Firestore `settings/app` → `latestAndroid`, `latestIos`, `iosUrl`, `message`.

## 2. How we work
- Simple English, short steps. Changes come as patch scripts (`node "$(ls -t ~/Downloads/NAME*.js | head -1)"`), then `flutter analyze … | grep "error •"`.
- Commit messages: plain, no extra attribution lines.
- DEV first. LIVE only after a clear yes. Never delete LIVE data without confirming.
- Never push: serviceAccount.json, fcm_sender*.json, tools/dev-serviceAccount.json, tools/create_users/serviceAccount.json, reset_test_data.js, functions/node_modules, .firebase/, the APNs .p8 key.
- Never unlink billing. Never send a DEV build to the App Store.

## 3. Done (latest first)
- 16 Nov: Recovery code screen: dash added by itself after 5 characters, max 10 (`_formatCode` in login_screen.dart, also used by Paste); shorter help text ("Enter your recovery code to restore your account. / Don't have it? Check Profile on your old phone."); new error `personal-code-not-found` → "No account found for this recovery code. Please check it and try again." (wrong format still shows "…It looks like K7M2P-X9F4R…"; delete-account wrong code unchanged).
- 16 Nov: Welcome tooltips back to the original text with Ma'am's change only: "New here? / Type the 6-letter entry code from Zoho to join.", "New phone? / Enter the recovery code you saved when you joined. Your account moves to this phone.", "Admin? / Sign in with your work email."
- 14 Nov: "Sign in with work email" (link + tip), Ma'am's comment. All 10 of Ma'am's Google Doc comments checked with `checkall.js` (35 checks pass).
- 13 Nov: Ma'am's text changes (intro, welcome, join, save code, home). "personal code" → "recovery code" in all on-screen text (same code everywhere). "office email" → "work email". Join button "Join Haystek Pulse". Empty chat: "Admin team reads and responds to every message. You will get a notification when they reply."
- TestFlight: builds 5 and 6 (DEV, "Haystek Pulse Dev") uploaded; build 7 next (recovery code fixes). Internal Testing group: Ma'am (Jigisha Reddy, App Store Connect role Customer Support, Haystek Pulse only) and Sir (PMO). They test as employees; we reply as admin from another phone (DEV admin code in Profile → Admin code).
- Android test APK: `flutter build apk --flavor dev --release` → share `build/app/outputs/flutter-apk/app-dev-release.apk` (not the debug one, not .sha1).
- DEV wiped again on 13 Nov (`devreset.js DELETE`: all logins + employees, sessions, devices; keeps admin code, join codes, settings, feedback).
- Docs: single sharp step images for the Suggestion Box (5) and Weekly Pulse (9) flows for the Google Doc (`single/` folder). Use full phone screenshots (Power + Volume down, 1080 px) for sharp images; Mac screen captures are ~600 px.
- Welcome back screen: small animations (badge pop, tick pop, pulse ring, floating chips, text fade-up).
- iPhone reinstall now works like Android: intro → Welcome back → tips → Home (`fresh_install.dart`, `showAgain`, login skips auto sign-in on fresh install).
- TestFlight builds 1.0.0 (3) and (4) uploaded; iOS tested OK. Next build number must be higher (5+).
- All weeks: empty state ("No employees yet", "No past weeks yet").
- Admin Profile: Admin code row (Show / Hide / Copy) + Reset admin code. Stored as `admin_codes/{SHA-256}` (sign-up check) + `admin_secret/current` (readable by active admins only). Rules deployed to DEV and LIVE. LIVE first code set (kept the original code; ask HR/admin, not written here).
- Chat top card: rating on its own line ("You said Difficult"), no progress bar, better empty text.
- DEV: all logins and employee records deleted for clean testing.
- Mac cleanup: Xcode caches + old emulators removed (kept Pixel_8_API_36, Pixel_Tablet_API_36, Pixel16KB).
- Documents: Employee Screens doc; Admin Screens doc (https://claude.ai/artifact/CErMjYeqLHA98z14dA3jq9); Release Checklist (https://claude.ai/artifact/PosMQFKDydHH3WHL1eUzmf); Weekly Pulse + Suggestion flow images.

### Earlier work (before 13 Nov)
- Branches: branch1 = old email-login version; branch2 = new sign-up; branch3 = current work.
- Sign-up (employees): no email, no name, no password. One-time **join codes** (Cloud Function keeps 20 active in `join_codes/{sha256}`, shown on the Pulse Codes page in Zoho; a used code changes to a new one). After joining, the app makes a **personal code** (shown once) = the login (hidden Firebase login from the code) and the key for the locked history. Old single entry code (`entry_codes`) no longer used.
- One account per phone: Android ANDROID_ID, iPhone random ID in Keychain → `devices/{SHA-256}` (deleted with the account). Same phone opens directly; new phone uses "I have my personal code"; "Your account moved to another phone" sign-out.
- Admins: office email (@haystek.com) + password + admin code, email verify screen (Step 2 of 3).
- Locked history (vault): PBKDF2-SHA256 + AES-256-GCM on the phone; my posts + Pulse answers. Feedback stored without uid; chat in `feedback/{id}/messages`.
- Anonymous by default; "With my name" per message (typed name, kept on the phone only). Admin sees "Name hidden" or the name.
- Weekly Pulse (Great / Good / Okay / Difficult; only Okay and Difficult have comments), Suggestion Box, Broadcast (everyone can see and discuss; push to topic), status flow Under Review → Planned → In Progress → Implemented / Noted; "Employee + everyone" on Implemented also posts a broadcast.
- Admin: Weekly Pulse home (open/closed, donut, What people said), All weeks + trend chart, Comments with search/filters, Remind people, quick replies, Suggestion list/search/chat, Broadcast, Profile.
- Delete my account, Help & Privacy (incl. "Does the app store anything about my phone?"), Update screen (Android + iOS), intro slides, first-time tips (welcome, home, profile).
- UI: Figtree font; sticky home top bar; same colour inside/outside status chips; My Feedback cards (colour bar, label, chip, 2-line message, "Admin replied"); Suggestion Box "SB2" design (intro, 4 tappable examples, composer at bottom, Anonymous / With my name pills); slide (Cupertino) transitions on both phones; app ignores phone font size, bold text and dark mode.
- LIVE: test data deleted, settings added, rules/indexes/functions same as DEV. Privacy policy updated (phone ID line, contact mobileapp@haystek.com) and deployed to both projects. Artifact cleanup policy 1 day (asia-south1).
- Store answers prepared: Apple – Device ID + User ID, App Functionality, linked to user, no tracking. Google Play – Device or other IDs, App functionality, not shared.
- Firebase moved to mobileapp@haystek.com (Owner + billing admin + CLI login).
- Other docs/designs: Employee Screens doc (https://claude.ai/artifact/Np5QWXNv1qxYUuULJoDYuq), design canvas (https://claude.ai/artifact/VYEjTcZKnzwepT7MAU1yUc), Word copy of the employee doc.
- People: Ma'am (Isha / Operations Director) reviews the docs; Sir (Rakesh) approved the new sign-up idea.

## 4. Open / later

### Pending now (16 Nov)
- [ ] **pulseHeadsUp time is wrong**: code says Monday 7:45 PM (`"45 19 * * 1"`, comment wrongly says Friday 5:45 PM). DEV Pulse opens Monday 12:22 PM → set `schedule: "7 12 * * 1"`, fix the comment, deploy DEV (`firebase deploy --only functions:pulseHeadsUp --project haystek-pulse-dev`), commit. LIVE: same, after the LIVE open time is decided (and a clear yes).
- [ ] Upload TestFlight build 7, add to the Internal Testing group.
- [ ] Share the Android APK with Android testers.
- [ ] Reply as admin to Sir's / Ma'am's suggestions in the app; change a status once; send one Broadcast.
- [ ] Collect their comments (Employee + Admin sheets) and make the changes.
- [ ] Some doc images still blurry (only small copies): Suggestion 3 (sent), Weekly Pulse 2, 3, 7, Profile tips. Need new phone screenshots.

### Google Cloud / Firebase account
- [ ] Budget alert → ₹1,000 (Billing → Budgets & alerts → edit the existing budget). Email only, nothing stops. Don't use service spend caps (they stop Functions = no join codes / notifications).
- [ ] Company verification (Billing → Verify): company name + address above + mobile OTP. Deadline **13 Feb 2027** (account can be suspended). Asked Ma'am before doing it.
- [ ] Company card: waiting for Ma'am. Cardholder adds it (OTP / e-mandate, online + international on), make it Primary, only then remove the current card. RBI: auto-charges without OTP up to the bank's mandate limit. Never leave the account without a card; never unlink billing.
- [ ] Firestore daily backups for LIVE (currently "Scheduled backups: Disabled").
- [ ] Keep mobileapp@haystek.com password with Ma'am/IT (safe place), company recovery phone/email, 2-step verification on both owner accounts.
- Start-up smoothness: splash → loader → Home flickers. Tried a fade (rejected) and a native splash (reverted). Ideas ready: branded native splash with the logo card at the loader's position (splash.png / splash_android12.png made), and/or a simple spinner instead of the full loader inside the app.
- Ma'am's suggestions on the employee sheet: sort into "before release" and "next update".
- Admin doc: update the admin code text (first code given to HR, admin resets it in Profile).
- Release decisions: countries (India only vs EU trader status), public vs unlisted, encryption answer.
- Encryption: app uses AES-256-GCM + PBKDF2 (standard algorithms). In App Store Connect pick "Standard encryption algorithms…". Do NOT add ITSAppUsesNonExemptEncryption=false. Confirm with Haystek legal before LIVE.
- Flutter upgrade (debugger EXC_BAD_ACCESS on iPhone is a known old-Flutter/Xcode issue; use `--release` meanwhile).
- Possible: add "Admin? Sign in with email" as a tip on the first screen.
- Ideas from the old plan, not built yet: stats designs (3 made, none chosen), Report a problem, Crashlytics (no Analytics), dark mode (last), app lock, polls, kudos, 👍 on broadcasts, multi-company (company ID).
- Before release (old list): `DemoData.on = false`, `pulseOpenEveryDay = false`, reset `settings/pulse` + scheduler, back up the Android keystore, review notes for Apple/Google with a test join code.
- Accounts for stores: Play Store – mobileapp@haystek.com; App Store – Haystek Technologies team (current tester account to switch to mobileapp later).

## 5. Release checklist (LIVE)

### A. Decisions first
- [ ] Ma'am's suggestions sorted: "before release" done, rest for next update.
- [ ] Countries: India only (no EU trader status needed) or EU too (declare trader in App Store Connect → Business).
- [ ] Store listing: public or unlisted.
- [ ] Encryption answer confirmed with Haystek legal ("Standard encryption algorithms…").

### B. App code
- [ ] `DemoData.on = false`, `pulseOpenEveryDay = false`.
- [ ] Launch image / splash replaced (Apple warns about the default one).
- [ ] Xcode: iPhone only (unless iPad wanted).
- [ ] Version in pubspec: `version: 1.0.0+N`, N higher than every TestFlight build (TestFlight and App Store share numbers).
- [ ] `flutter analyze` clean, tested on Android + iPhone (prod flavor) with a test join code.
- [ ] All work committed and pushed.

### C. LIVE Firebase (haystek-pulse) – only after a clear yes
- [ ] Rules, indexes, functions same as DEV (deploy commands below).
- [ ] Admin code ready for HR (admins see it in Profile → Admin code).
- [ ] APNs key uploaded in the LIVE Firebase project (iOS notifications).
- [ ] `settings/pulse` set for real weeks, and `pulseHeadsUp` schedule = 15 minutes before that open time (deploy functions to LIVE).
- [ ] Firestore daily backups on.
- [ ] `settings/app`: `latestAndroid`, `latestIos`, `iosUrl` (https://apps.apple.com/app/id6833529873), `message`.
- [ ] Privacy policy live: https://haystek-pulse.web.app/privacy.html (check the link works).

### D. Google Play
- [ ] Back up the Android upload keystore + key.properties (safe place, not GitHub).
- [ ] Data safety: Device or other IDs, App functionality, not shared; account deletion web link.
- [ ] Store listing: name, short + full description, screenshots, icon, privacy policy link.
- [ ] Upload the .aab to Internal testing first, then Production.

### E. App Store
- [ ] App Privacy: Device ID + User ID, App Functionality, linked to user, no tracking.
- [ ] Age rating (new social-media questions: messages + discussions = yes).
- [ ] Screenshots, description, keywords, support URL, privacy policy URL.
- [ ] Review notes: how to test (test join code, admin test account).
- [ ] Encryption question: "Standard encryption algorithms…".
- [ ] Submit for review.

### F. After release
- [ ] Update `settings/app.latestAndroid` / `latestIos` when a new version is live.
- [ ] Billing: company card (Primary) + ₹1,000 budget alert; company verification by 13 Feb 2027; then remove the old card; unlink "My First Project".
- [ ] Switch the TestFlight tester to mobileapp@haystek.com.

## 6. Commands

### Daily
- Android: `flutter run --flavor dev`
- iPhone: `flutter run --release --flavor dev -d 00008130-000621980ED1001C` (release mode avoids the debugger stop)
- Check code: `flutter analyze lib | grep "error •" ; echo "--- no lines above = no errors"`
- Save work: `git add -A && git commit -m "message" && git push`

### TestFlight (DEV build, internal testers only)
1. `sed -i '' 's/^version: 1\.0\.0+[0-9]*$/version: 1.0.0+7/' pubspec.yaml` (raise the number each time; 1–6 used)
2. `flutter build ipa --flavor dev` (no `-t`; takes ~25 min)
3. `open build/ios/archive/Runner.xcarchive`
4. Organizer → Distribute App → App Store Connect → Upload.
5. App Store Connect → TestFlight → Internal Testing group → add the build (and testers). New testers: Users and Access first (they accept), then add to the group. Ignore the App Store version page errors (those are for the real release).

### Android test APK (DEV)
- `flutter build apk --flavor dev --release` → `open build/app/outputs/flutter-apk/` → share `app-dev-release.apk`.

### Phone not showing new code
- Hot reload isn't enough after big edits: press **R** or run `flutter run --flavor dev` again (no uninstall needed).

### Check scripts (read only)
- `checkall.js`: all 10 of Ma'am's comments in the code.
- `checkpulse.js`: Weekly Pulse settings + notification job time.
- `devreset.js` (list) / `devreset.js DELETE`: DEV only, wipes logins + employees, sessions, devices.

### LIVE builds
- iPhone: `flutter build ipa --flavor prod` → `open build/ios/archive/Runner.xcarchive` → Distribute App → App Store Connect → Upload → submit in App Store Connect.
- Android: `flutter build appbundle --flavor prod` → upload `build/app/outputs/bundle/prodRelease/app-prod-release.aab` in Play Console.

### Firebase
- DEV rules: `firebase deploy --only firestore:rules --project haystek-pulse-dev`
- LIVE rules (after yes): `firebase deploy --only firestore:rules --project haystek-pulse`
- Indexes: `firebase deploy --only firestore:indexes --project <project>`
- Functions: `firebase deploy --only functions --project <project>` (one function: `--only functions:pulseHeadsUp`)
- List functions: `firebase functions:list --project <project>`
- Scheduler on the web: console.cloud.google.com/cloudscheduler?project=<project>
- Billing: console.cloud.google.com/billing → My Billing Account (Payment method, Budgets & alerts, Account management). Don't use "Change billing" on projects.
- Hosting (privacy page): `firebase deploy --only hosting --project <project>`

### Clean-up / fixes
- iPhone build stuck on Keychain: `security unlock-keychain`
- Mac low on space: delete `~/Library/Developer/Xcode/DerivedData/*` and old emulators in `~/.android/avd`.
- Undo unsaved changes: `git checkout -- .` (and `git clean -nd` to preview new files before `git clean -fd`).
