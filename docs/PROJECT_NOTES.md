# Haystek Pulse – Project Notes (as of 19 Nov 2026)

Give this file to Claude at the start of any new chat: "Read this first."

## 1. Basics
- Flutter + Firebase app. Mac path: `/Users/haystek/haystek_pulse`, current branch `branch5`, repo `haystek/HaystekPulse` (private).
- Branches: branch3 pushed (c4da0b7); branch4 = UI polish, pushed (926b064); branch5 = HR/Ops switch + all work since, pushed (latest de349a8, 19 Nov).
- Flavors: `dev` → Firebase `haystek-pulse-dev`, `prod` → `haystek-pulse` (LIVE).
- One bundle ID for both: `com.haystek.haystekPulse`, Apple Team `T6LJAQ4AL7`, App Store Apple ID `6833529873`.
- Firebase account: mobileapp@haystek.com (Owner). shivakumar.t@haystek.com is also Owner. Billing account `01CFFA-F4B1B1-1B6168` "My Billing Account" (Haystek org, INR). Blaze plan. Since 19 Nov: company Visa card = Primary, old Mastercard = Backup (remove after the first company-card payment); organisation verification done (key person: Aarthi Ma'am, role "Other" – Business Development & Operations Manager); budget ₹500/month, alerts only (50/90/100%, email), covers haystek-pulse + haystek-pulse-dev. Linked projects: haystek-pulse, haystek-pulse-dev, My First Project (empty default).
- Company (for Google/Apple forms, as on the GST certificate): HAYSTEK TECHNOLOGIES PRIVATE LIMITED (Private Limited Company), HNO 1-53, Plot 27, Sagacity Heights, Third Floor, Kavuri Hills, Hyderabad, Telangana 500081. Keep the GST certificate PDF for proof requests.
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
- 19 Nov – **Billing done**: company card Primary (old card Backup), organisation verification successful, ₹500 budget alert (alerts only, DEV + LIVE). Current usage ₹0 (free tier).
- 19 Nov – **DEV build 12** (1.0.0+12) uploaded from Xcode (TestFlight Internal Only), shared with Ma'am. Build 11 also uploaded. Xcode needed the Apple account added (Settings → Apple Accounts) – `flutter build ipa` shows "No Accounts / No signing certificate" at the IPA step; the archive is fine, upload from Xcode (Organizer → Distribute App → TestFlight Internal Only).
- 19 Nov – **Admin home tips** (9, top to bottom: Search, All weeks, Pick a week (explains the coloured bar), This week at a glance, Answers, What people said, Suggestion Box, Broadcast, Your profile). Admin home list builds all parts (`cacheExtent: 3000`) so tips reach them. Broadcast tab built only when opened (its tip no longer shows on Weekly Pulse).
- 19 Nov – **Tips engine** (`app_tour.dart`): after the last tip / Skip the page scrolls back smoothly; tall items scroll to the top first; the tip card goes on the side with more room, else sits at the bottom (never off screen).
- 19 Nov – **Welcome tip 3** highlights the whole "Admin? Sign in with work email" line.
- 19 Nov – **Create admin account – design E**: admin code first in a dark blue card with 6 boxes (dots until Show), then name/email/password in one card, one hint line; footer hidden on this screen; fields scroll above the keyboard (`_kbRoom`, 160).
- 19 Nov – **HR switch fixes**: admin password checked inside the box (temporary second Firebase app "admin_check", no loading screen on a wrong password); box shows the admin email, empty/wrong password shakes + message, "Forgot password?" sends a reset link, box scrolls with the keyboard. Admin Sign out removes the saved admin password (next Switch to Admin asks again). Deleted admin → "This admin account no longer exists…" and the switch is removed (`dual-admin-gone`).
- 19 Nov – Admin home **account card** (design C) on HR/Ops phones only: "You are in Admin [⇄ Employee]" / "You are in Employee [⇄ Admin]" (`RoleToggle` in `dual_role_screens.dart`, on both home screens).
- 19 Nov – Small fixes: Suggestion Box "13 suggestions / newest first" on two lines; broadcast with no comments shows admins "No comments yet. Employees' comments will show here."; Also join as Employee picture cards wider.
- 18 Nov – **Demo data** (memory only, `DemoData.on = true`): office-related suggestions (13), Pulse comments (12), employee answers (8 weeks) + comments + suggestions, broadcasts (7) with comments; threads match each status; anonymous replies ask for the name ("If you're comfortable, please share your name…"); this week's sample answers are ADDED to real ones (`DemoData.withReal`).
- 18 Nov – Pulse chat header: status left, "Said Okay" pill right. New broadcast form: full title wraps, "From the suggestion (name not shared)", no remove (x).
- 18 Nov – Help & Privacy redesign (employee + admin Q&A), privacy policy matched to the app and deployed to DEV + LIVE, profile grey background, text size by screen width, delete screen fits small phones. Errors TTL policy on `expireAt` serving on DEV + LIVE.
- 18–19 Nov – **DEV wiped several times** for clean tests (`wipedev.js`: all logins, employees, devices, sessions, vaults, user_state, test data; keeps entry/join codes, admin codes, settings). Single person: `deluser.js email [--yes]` (login + employees record only).
- 18 Nov – iPhone upload error "x86_64 / Missing 64-bit" (objective_c.framework built for the simulator): fix = `flutter clean`, `pub get`, `pod install`, rebuild; check before upload with `lipo -info …/objective_c.framework/objective_c` (must say arm64). "dev couldn't be removed" error = Xcode had the archive open: quit Xcode, `rm -rf build/ios` (sudo if needed).
- 17 Nov – **HR/Ops: Admin + Employee on one phone** (admin first, Ma'am approved). branch5.
  - Admin Profile → "Also join as Employee": screen with only the recovery code / entry code (no admin password), then works like a normal employee sign-in.
  - Employee Profile → "Switch to Admin" (only on that phone): first time asks the admin password once, then one tap. Admin Profile → "Switch to Employee". Admin Sign out → straight to the employee side. Short loading screen while switching (no "Welcome back" screen).
  - Admin email + password + uid kept ONLY on the phone (Keychain / Keystore, `lib/services/dual_role.dart`). Nothing in Firebase, no rules change, so the anonymous employee account can't be linked to the admin.
  - Employee Delete account → also removes the saved admin sign-in. Employees have no Sign out button (only Delete account).
  - Notifications: the HR phone stays in both sides' groups; when switching, the token is kept (`NotificationService.pause()`). Broadcast is sent to `'employees' in topics && !('me_<adminUid>' in topics)`, so the sender's own phone doesn't get it; if that send fails, it goes to `employees` as before.
  - Files: `dual_role.dart`, `dual_role_screens.dart` (new); `auth_service.dart` (switchSignOut, joinAsEmployee, switchToAdmin, switchToEmployee, switchingSides), `auth_gate.dart`, `notification_service.dart`, `push_sender*.dart`, `broadcast_service.dart`, `profile_screen.dart`.
  - New wording (needs Ma'am's OK): "Also join as Employee" / "Use this phone as an employee too", "Switch to Employee" / "Open your employee side on this phone", "Switch to Admin" / "Open your admin side on this phone", join screen "Use this phone as an employee too. Enter your recovery code or entry code, like any employee.", password box "Enter it once. It's kept only on this phone, so next time you can switch without typing.", sign-out box (admin, HR phone) "You'll go to your employee side on this phone."
- 17 Nov – **UI polish** on the iPhone 17 Pro Max simulator (branch4).
  - Font is now **Inter** everywhere. Text: titles #111827, small text dark grey 80% (0xCC0E1A3A), letterSpacing 0. `PulseTextScaler` sizes text by phone width (0.96–1.10). Tall phones (> 880) get a bigger intro.
  - Status colours (`FeedbackStatus.color`): New amber, Under Review purple, Planned teal, In Progress blue, Implemented green, Noted pink.
  - Employee lists (Home "Your feedback" + My Feedback Suggestions / Weekly Pulse): design A "Inbox" in one white panel – type + coloured status, message, "Anonymous / With your name · date", "Admin replied" on its own line (`lib/widgets/employee_inbox.dart`, employee only).
  - Admin lists (Home "What people said", Suggestion Box, All, Search): design 3a "Ticket" – grey strip (👤 name or 🔒 Anonymous, time, arrow), message, status + mood chip (`lib/widgets/list_card.dart`, admin only). No employee ID anywhere; search hints "Words or name" / "Search words or name" (search by ID still works).
  - Conversation (admin + employee): top card = Ticket; replies as cards ("You" / name / "Admin", time); status change as a thin line "Moved to X · time".
  - Broadcast: ticket header, collapses like the suggestion chat (also while typing); New broadcast from a suggestion fills Title with the suggestion text; the "From a suggestion" box shows while writing but is not sent.
  - Mark as Implemented box: two equal options with icons (no emoji), darker text. All weeks: darker, bolder text. Admin dates "Nov 16–20, 2026".
  - Employee Profile: version line fixed at the bottom (13). Admin Profile: picture card + chips, icons instead of emoji.
  - Rate tiles centred; Send-as on one row; list items fade in.
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
- UI: Figtree font (Inter since 17 Nov); sticky home top bar; same colour inside/outside status chips; My Feedback cards (colour bar, label, chip, 2-line message, "Admin replied"); Suggestion Box "SB2" design (intro, 4 tappable examples, composer at bottom, Anonymous / With my name pills); slide (Cupertino) transitions on both phones; app ignores phone font size, bold text and dark mode.
- LIVE: test data deleted, settings added, rules/indexes/functions same as DEV. Privacy policy updated (phone ID line, contact mobileapp@haystek.com) and deployed to both projects. Artifact cleanup policy 1 day (asia-south1).
- Store answers prepared: Apple – Device ID + User ID, App Functionality, linked to user, no tracking. Google Play – Device or other IDs, App functionality, not shared.
- Firebase moved to mobileapp@haystek.com (Owner + billing admin + CLI login).
- Other docs/designs: Employee Screens doc (https://claude.ai/artifact/Np5QWXNv1qxYUuULJoDYuq), design canvas (https://claude.ai/artifact/VYEjTcZKnzwepT7MAU1yUc), Word copy of the employee doc.
- People: Ma'am (Isha / Operations Director) reviews the docs; Sir (Rakesh) approved the new sign-up idea.

## 4. Open / later

### Pending now (19 Nov)
- [ ] Ma'am's feedback on DEV build 12 → fix one by one.
- [ ] Ma'am's OK on new wording: account card ("You are in", "Switching…"), password box messages + "Forgot password?", "This admin account no longer exists…", admin home tips (9), Create admin account card, "Employees' comments will show here.", sample data texts, Help & Privacy admin answers.
- [ ] Weekly Pulse to open **Friday 6:00 PM** (later, DEV then LIVE): `settings/pulse` + `pulseHeadsUp` schedule `"45 17 * * 5"` (Asia/Kolkata) in `functions/index.js`, deploy.
- [ ] Check APNs key on the LIVE project (DEV has it – checked 19 Nov).
- [ ] "No employees yet" text: change to "No employee has joined yet / Answers show here once people join." (as in the doc)? Decide.
- [ ] Add `android/.kotlin/` to `.gitignore`.
- [ ] Confirm Android double back to close works (`DoubleBackToClose` already in auth_gate).
- [ ] Test on simulators (iPhone SE, iPhone 16); `flutter clean` before the next iPhone build afterwards.
- [ ] Remove the old card after the first company-card payment; tell Aarthi Ma'am to approve a bank OTP/e-mandate message if one comes.

### Pending before (16 Nov)
- [ ] **pulseHeadsUp time is wrong**: code says Monday 7:45 PM (`"45 19 * * 1"`, comment wrongly says Friday 5:45 PM). DEV Pulse opens Monday 12:22 PM → set `schedule: "7 12 * * 1"`, fix the comment, deploy DEV (`firebase deploy --only functions:pulseHeadsUp --project haystek-pulse-dev`), commit. LIVE: same, after the LIVE open time is decided (and a clear yes).
- [x] TestFlight builds 7–12 uploaded (latest 12, 19 Nov).
- [ ] Share the Android APK (build 12) with Android testers.
- [ ] Reply as admin to Sir's / Ma'am's suggestions in the app; change a status once; send one Broadcast.
- [ ] Collect their comments (Employee + Admin sheets) and make the changes.
- [ ] Some doc images still blurry (only small copies): Suggestion 3 (sent), Weekly Pulse 2, 3, 7, Profile tips. Need new phone screenshots.

### Notifications: move sending to the server (before LIVE, after Sir/Ma'am test)
Today every build (DEV + LIVE) packs a Google service account key (`assets/fcm_sender_dev.json` / `assets/fcm_sender.json`, listed in pubspec.yaml, read by `lib/services/push_sender_io.dart`). Anyone with the APK/IPA can take it and send notifications to everyone. Keys are not in git (.gitignore lines 48, 62); never `git add -f` them (a pushed key was auto-disabled before = all notifications stop).
All 8 notifications use it: new suggestion (feedback_service:136), Pulse comment (pulse_service:381), Pulse answer (pulse_service:394), employee reply (feedback_service:361), admin reply / status (feedback_service:257, 379), Pulse open (pulse_service:411), Remind (pulse_service:438), new broadcast (broadcast_service:135). Sent from employee AND admin phones.
Plan (separate git branch, DEV first, ₹0 cost, ~2–3 h):
- [ ] Add a `sendPush` Cloud Function (checks who is asking: employees only notify admins about their own items; only admins notify everyone). No key needed on the server (built-in permission, like pulseHeadsUp).
- [ ] Change `push_sender_io.dart` to call the function (add `cloud_functions` package). Screens don't change.
- [ ] Test all 8 notifications on Android + iPhone.
- [ ] Remove the 2 key lines from pubspec.yaml and the files from assets/ (keep a safe copy until the end).
- [ ] New TestFlight / APK; Sir and Ma'am update (check App Store Connect → Testers "Installed").
- [ ] Only then delete the old keys: Google Cloud → IAM & Admin → Service accounts → account = `client_email` → Keys → Key ID = `private_key_id` → Delete (DEV, then LIVE).
Until then: keep one safe copy of the key files outside the project (password manager / private company Drive), never in git/chat/email.

### Google Cloud / Firebase account
- [x] Budget alert ₹500, alerts only, DEV + LIVE (19 Nov). Was planned: ₹1,000 (Billing → Budgets & alerts → edit the existing budget). Email only, nothing stops. Don't use service spend caps (they stop Functions = no join codes / notifications).
- [x] Company verification – done 19 Nov (successful).
- [x] Company card added and Primary (19 Nov); old card is Backup. Remove the old card after the first company-card payment (early Dec, only if there is a charge). Was: waiting for Ma'am. Cardholder adds it (OTP / e-mandate, online + international on), make it Primary, only then remove the current card. RBI: auto-charges without OTP up to the bank's mandate limit. Never leave the account without a card; never unlink billing.
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

### B2. Full test on DEV (before release)
Employee:
- [ ] Join with entry code → Save recovery code screen.
- [ ] New phone: sign in with recovery code; old phone shows "Your account moved".
- [ ] Reinstall on the same phone → Welcome back (Android + iPhone).
- [ ] Delete account → join again with a new code.
- [ ] Suggestion: Anonymous and With my name.
- [ ] Weekly Pulse: starting soon, open, answered, missed; Okay / Difficult ask for a comment.
- [ ] Chat: employee and admin replies; notifications both ways (app open and closed).
- [ ] Broadcast: receive + comment.
- [ ] Profile, Help & Privacy, Update screen.
- [ ] Recovery code field: dash after 5, max 10; "No account found…" vs "…It looks like K7M2P-X9F4R…".
Admin:
- [ ] Sign up with admin code → verify email.
- [ ] Change statuses → "Moved to …" in the employee chat.
- [ ] Remind button, All weeks, comments + filters.
- [ ] Reset admin code: old code stops working, new one works.
Notifications:
- [ ] 15-minute "Weekly Pulse opens" arrives at the right time (pulseHeadsUp schedule matches settings/pulse).

LIVE is the same code but a separate database and setup (own settings, APNs key, join codes, admin code; functions and rules deployed separately), so do the short LIVE test in C.

### C. LIVE Firebase (haystek-pulse) – only after a clear yes
- [ ] Rules, indexes, functions same as DEV (deploy commands below).
- [ ] Admin code ready for HR (admins see it in Profile → Admin code).
- [ ] APNs key uploaded in the LIVE Firebase project (iOS notifications).
- [ ] `settings/pulse` set for real weeks, and `pulseHeadsUp` schedule = 15 minutes before that open time (deploy functions to LIVE).
- [ ] Firestore daily backups on.
- [ ] `settings/app`: `latestAndroid`, `latestIos`, `iosUrl` (https://apps.apple.com/app/id6833529873), `message`.
- [ ] Privacy policy live: https://haystek-pulse.web.app/privacy.html (check the link works).
- [ ] Short LIVE test (~20 min, prod build): join with a LIVE entry code, send a suggestion, reply as a LIVE admin, notifications arrive on iPhone + Android. Then delete the LIVE test accounts and data (after a clear yes).

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
1. `sed -i '' 's/^version: 1\.0\.0+[0-9]*$/version: 1.0.0+9/' pubspec.yaml` (raise the number each time; 1–8 used; next DEV = 9, PROD later = 10+)
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

---

<!-- PULSE-TRACKER START -->

## Haystek Pulse – Pending work (updated 17 Nov 2026, night)

Send this whole file at the start of every new chat.
Tick `[x]` when done.

---

### Done on 17 Nov 2026 (branch4 + branch5, not built yet)

- [x] UI polish on the 17 Pro Max: Inter font, darker text, status colours, employee Inbox cards, admin Ticket cards, reply cards, no employee ID (details in section 3)
- [x] HR/Ops: Admin + Employee on one phone, switch from Profile, own broadcast skipped (details in section 3)
- [x] branch4 pushed (926b064), branch5 pushed (dc1387b)

---

### Tomorrow (18 Nov)

1. [x] Test the HR switch on DEV (iPhone `--release --flavor dev`): Also join as Employee → Switch to Admin (password once) → Switch to Admin again (no typing) → Switch to Employee → Admin Sign out (goes to employee). Broadcast: other phone gets it, this phone doesn't.
2. [x] TestFlight **DEV build 9** (then 10, 11, 12): `version: 1.0.0+9`, `kSlowStart = false`, `flutter build ipa --release --flavor dev`, upload, What to Test "DEV build (test data) – HR/Ops switch. Do not release.", Internal Testing only.
3. [x] Check the APNs key is uploaded in the **DEV** Firebase project (Cloud Messaging), so notifications work on TestFlight.
4. [x] Send Ma'am the update (HR switch) + ask her OK on the new wording.
5. [ ] `doubleback.js` (Android: press back twice to close).
6. [x] Commit + push.

---

### Done on 16 Nov 2026 (TestFlight build 8, version 1.0.0+8)

- [x] Start-up: dark-blue splash held until Home is ready, no loader flash
- [x] Fix: Home → loader → Home flicker (auth_gate shows loader only when no data yet)
- [x] Weekly Pulse card no reload when settings arrive again
- [x] Shimmer instead of loaders on Home (Pulse card, Broadcast line, Your feedback)
- [x] Test mode (`kSlowStart`) is OFF – must stay `false` for every build
- [x] Red "No internet connection" bar on every screen (also catches Wi-Fi without internet)
- [x] iPhone: "Done" bar above the keyboard on every screen
- [x] iPhone: swipe back on entry code, recovery code, admin and "account moved" screens
- [x] Welcome-flow screens slide in / out like real pages
- [x] Recovery code field: dash after 5, max 10, error messages
- [x] TestFlight build 8 uploaded, build 6 expired, group informed
- [x] LIVE launch checklist made (section below)

---

### Tomorrow – first: check

- [ ] Send: `docs/PROJECT_NOTES.md`, `firebase.json`, `ls -R public/`, `firestore.rules`
- [ ] Update `PROJECT_NOTES.md` with 16 Nov work
- [ ] Check privacy page (data collected, how stored, account deletion, contact email) – already deployed
- [ ] Check hosting pages and Firestore rules; write them into the notes
- [ ] Fill placeholders in the LIVE checklist below (device name, scheduler region)

---

### App work (in this order)

1. [x] **Text styles + responsive** – same for employee AND admin (17 Nov: Inter, PulseTextScaler, darker text; tablets not checked)
   - First run the 3 greps (font sizes, font weights, `lib/theme/app_theme.dart`)
   - 8 styles (Figtree): Title 24/700, Heading 20/700, Subheading 16/600, Body 15/400, Body bold 15/600, Small 13/400, Label 11/600 caps, Button 15/600 (final numbers after the grep)
   - Responsive: base width ~390, scale 90%–115%; tablets: content centred, not stretched
   - Same header (height, back button, title, padding) and same footer button (~52 high) everywhere
   - Go screen by screen. Employee: Welcome, Home, Weekly Pulse, Suggestion, Your feedback, Broadcast, Profile. Admin: Admin home, feedback list + detail, reply, Broadcast, Settings, Profile
2. [ ] **Test on simulators** – small (iPhone SE), medium (iPhone 16/17), big (Pro Max, done 17 Nov), optional iPad
   ```
   xcrun simctl list devices available | grep -E "iPhone|iPad"
   open -a Simulator
   flutter run --flavor dev -d "<simulator name>"
   ```
   Screenshot: Cmd + S (saved to Desktop)
3. [x] **"Anonymous" / "With your name" label** on every employee feedback (Home list + See all), so old weeks can be checked (Ma'am)
4. [ ] **First-time tip on Home** (optional): "Tap a card to open it. Swipe up to leave the app." (from Ma'am's "how do I come out")
5. [ ] **Android: press back twice to close** on Employee Home + Admin Home – `doubleback.js` ready, not run yet
6. [x] **HR / Ops: Employee + Admin in one app** – built 17 Nov, tested and polished 18–19 Nov (account card on home, password check in the box). Old ideas below were the first draft:
   - Join as employee and sign in as admin with work email, in either order (Profile)
   - Switch between Employee and Admin anytime, no logout
   - Get both employee and admin notifications; tapping opens the right side
   - Own broadcast/reminder: they also get it as employee (or skip the sender – decide)
7. [x] **TestFlight build 9** (version `1.0.0+9`, DEV) – check `kSlowStart = false` first. PROD build later = 10+.
8. [ ] Optional: Android 12 splash logo card same size as loader card
9. [ ] Optional later: pull down to refresh on Home and lists

---

### Feedback from testers

- [ ] Reply to Ma'am's test suggestion "Better Wi-Fi in the conference room" from admin, status In progress, check she gets the notification
- [ ] Collect Sir's feedback on build 8, add here, reply as admin
- [ ] Blurry doc images – new phone screenshots: Suggestion 3, Weekly Pulse 2/3/7, Profile tips

---

### Before LIVE (details + commands in the LIVE checklist below)

- [ ] sendPush server function → remove fcm_sender files from app → testers update → delete old keys
- [ ] App Check + restrict API keys
- [ ] LIVE: rules, indexes, functions, hosting deployed
- [ ] `pulseHeadsUp` reminder time = LIVE open time (`functions/index.js`, e.g. `"7 12 * * 1"`)
- [ ] APNs key on LIVE project; Android release SHA keys on LIVE project
- [ ] LIVE data: admin accounts, entry code, `settings/pulse`, `settings/app`
- [ ] Daily backup **7 days**, turn on at launch (≈ ₹2/month)
- [ ] Remove `debug_slow.dart` fully
- [ ] Prod build test on real phones; store builds (appbundle + ipa, flavor prod)
- [ ] Android signing key backed up safely
- [ ] Delete account works on LIVE
- [ ] Store listings: texts, screenshots, privacy forms, age rating, reviewer demo login, Apple encryption question, Play account type, Ma'am approval
- [ ] Launch day: short LIVE test, staged release, employee guide, admin guide, support person
- [ ] After launch: error log daily (week 1), usage check, delete unused DEV scheduler jobs (free 3 jobs per billing account), employee leaves → deactivate same day, rollback plan via `settings/app`

---

### Waiting on Ma'am

- [x] Company card added and Primary (19 Nov)
- [x] Company verification – done 19 Nov (was due 13 Feb 2027)
- [x] HR / Ops switch: Ma'am approved admin-first (built 17 Nov)
- [ ] OK on the new wording for the HR switch (list in section 3)
- [ ] OK on the new look (employee Inbox cards, admin Ticket cards)

---

### Decisions made

- Daily backup: keep **7 days** (covers weekends; each copy has ALL data)
- Backups only for LIVE, not DEV; turn on at launch
- Extra scheduler jobs ≈ ₹8/month each; clean DEV jobs after launch
- Expected Firebase cost: ₹0–50/month; Apple + Play accounts already paid (Apple $99 renews yearly)
- FCM key stays in the app until the sendPush server change
- Only Ma'am's suggested text changes; no new wording unless asked
- HR/Ops switch: admin first; admin sign-in kept only on the phone (not Firebase); Delete account removes it; own broadcast skipped
- Employee and admin cards are separate code: `employee_inbox.dart` (employee) vs `list_card.dart` (admin) – never share them
- DEV builds may go to TestFlight Internal Testing only (same bundle ID as PROD) – never pick a DEV build for App Store review

---

### Rules (always)

- DEV first. LIVE only after a clear yes. Never delete LIVE data without confirming.
- Never push key files; never `git add -f` them. Repo stays private.
- No passwords, admin codes or card numbers in docs or chat.
- Never submit a DEV build to the App Store.
- Before every build: `grep "kSlowStart =" lib/debug_slow.dart` must say `false`.

---

## Haystek Pulse – LIVE launch checklist

DEV project: `haystek-pulse-dev`  ·  LIVE project: `haystek-pulse`
Rule: do everything on DEV first. Touch LIVE only after a clear yes.
Never put passwords, admin codes, card numbers or key files in this file or in git.

Tick each box `[x]` when done, with the date.

---

### 0. Before anything (every time)

- [ ] On the right branch and everything committed
  ```
  cd /Users/haystek/haystek_pulse
  git status --short
  git branch --show-current
  ```
- [ ] Test mode is OFF (must say `false`)
  ```
  grep "kSlowStart =" lib/debug_slow.dart
  ```
- [ ] No errors
  ```
  flutter analyze lib | grep "error •" ; echo "--- no lines above = no errors"
  ```
- [ ] Key files are NOT in git (each line must print the file name = ignored)
  ```
  git check-ignore serviceAccount.json assets/fcm_sender.json assets/fcm_sender_dev.json tools/dev-serviceAccount.json tools/create_users/serviceAccount.json reset_test_data.js AuthKey_B348XC2G9K.p8
  ```
  Never `git add -f` these files.

---

### 1. Security (before LIVE)

- [ ] **sendPush server function** – notifications sent from the server, not the app (plan in PROJECT_NOTES.md → Notification server plan)
- [ ] Remove the `fcm_sender` files from `pubspec.yaml` assets and from the app
- [ ] Testers updated to the new build
- [ ] Delete the old FCM sender keys (only after the 3 steps above)
  https://console.cloud.google.com/iam-admin/serviceaccounts?project=haystek-pulse
  https://console.cloud.google.com/iam-admin/serviceaccounts?project=haystek-pulse-dev
- [ ] **App Check** turned on (needs a small app change – ask Claude for the script)
  Console: Firebase → App Check → register Android (Play Integrity) and iOS (App Attest / DeviceCheck)
- [ ] **Restrict API keys** to the app only
  https://console.cloud.google.com/apis/credentials?project=haystek-pulse
  Android key → Android apps → package `com.haystek.haystek_pulse` + release SHA-1
  iOS key → iOS apps → bundle ID

---

### 2. LIVE Firebase setup (same as DEV)

- [ ] Check which project the commands use
  ```
  firebase projects:list
  ```
- [ ] **Firestore rules** on LIVE
  ```
  firebase deploy --only firestore:rules --project haystek-pulse
  ```
- [ ] **Firestore indexes** on LIVE
  ```
  firebase deploy --only firestore:indexes --project haystek-pulse
  ```
- [ ] **Cloud Functions** on LIVE
  ```
  firebase deploy --only functions --project haystek-pulse
  firebase functions:list --project haystek-pulse
  ```
- [ ] **Reminder time** (`pulseHeadsUp`) matches the LIVE open time
  Edit the schedule in `functions/index.js` (example: `"7 12 * * 1"` = Monday 12:07), then deploy functions again.
- [ ] **Hosting** (join page, privacy page) on LIVE
  ```
  firebase deploy --only hosting --project haystek-pulse
  ```
  Open the privacy page and the join page in a browser and check they load.
- [ ] **iPhone notifications**: APNs key uploaded to the LIVE project
  Firebase → Project settings → Cloud Messaging → Apple app configuration → APNs Authentication Key
- [ ] **Android release SHA keys** added to the LIVE project
  ```
  cd android && ./gradlew signingReport && cd ..
  ```
  Also copy the SHA-1 / SHA-256 from Play Console → App integrity → App signing.
  Add both in Firebase → Project settings → Android app → Add fingerprint.
- [ ] **Billing**: Blaze plan on, budget alert on
  https://console.cloud.google.com/billing
- [ ] **Daily backup – keep 7 days** (turn on at launch, before real data)
  ```
  gcloud firestore backups schedules create --database='(default)' --recurrence=daily --retention=7d --project=haystek-pulse
  gcloud firestore backups schedules list --database='(default)' --project=haystek-pulse
  ```

---

### 3. LIVE data to create

- [ ] **Admin accounts** on LIVE (work email)
- [ ] **Entry code** for LIVE (the real code for employees – share only inside the company)
- [ ] **`settings/pulse`** on LIVE: openDay, openHour, openMinute, openDays
- [ ] **`settings/app`** on LIVE: minimum version for the "Please update" screen
- [ ] **No test data** on LIVE

---

### 4. The app

- [ ] Remove `lib/debug_slow.dart` and its uses fully (ask Claude for the script)
- [ ] Version number set in `pubspec.yaml` (e.g. `1.0.0+10`)
  ```
  grep "^version:" pubspec.yaml
  ```
- [ ] **Prod build test** on real phones (talks to LIVE)
  ```
  flutter run --release --flavor prod -d <device>
  ```
  Test: join with entry code, Weekly Pulse, suggestion, admin reply, notification, broadcast, delete account.
- [ ] **Android store build**
  ```
  flutter build appbundle --flavor prod --release
  open build/app/outputs/bundle/
  ```
- [ ] **iPhone store build**
  ```
  flutter build ipa --flavor prod
  open build/ios/archive/Runner.xcarchive
  ```
  Xcode → Distribute App → App Store Connect → Upload
- [ ] **Android signing key** (keystore + password) backed up safely (password manager / company drive). If lost, the app can never be updated.
- [ ] **Delete account** works on LIVE (Profile → Delete account)

---

### 5. Store listings

- [ ] App name, short description, full description, keywords (App Store)
- [ ] Screenshots: iPhone 6.9" and 6.5"; Android phone (2+); Play feature graphic 1024×500; icon 512×512
- [ ] **Privacy policy link** (already deployed – check it covers: data collected, how stored, account deletion, contact email)
- [ ] Support email / link
- [ ] Apple **App Privacy** form + Google **Data safety** form (honest answers: feedback, device ID, no ads, anonymous unless "With my name")
- [ ] Age rating questionnaire (both stores)
- [ ] **Reviewer demo login** on LIVE (entry code / test account for Apple and Google)
- [ ] Apple **encryption question** (standard encryption → exempt; confirm)
- [ ] Play Console account type checked (organization = no 14-day closed test needed)
- [ ] **Ma'am approves** privacy text and store descriptions before submitting
- [ ] Never submit a DEV build to the App Store

---

### 6. Launch day

- [ ] **Short LIVE test** (PROJECT_NOTES.md → test checklist)
- [ ] Daily backup ON (section 2)
- [ ] **Staged release**: 10–20 employees first, then everyone
  Play Console → Production → staged rollout %
  App Store → Phased release
- [ ] **Employee guide** sent: store link + entry code + how to join + save recovery code
- [ ] **Admin guide**: how to reply, broadcast, change open time, reset a phone
- [ ] **Support person** decided (who employees contact)

---

### 7. After launch

- [ ] Week 1: check the error log every day
- [ ] Week 1: check Firebase usage is inside the free amounts
  https://console.firebase.google.com/project/haystek-pulse/usage
- [ ] Delete DEV scheduler jobs not needed any more (free 3 jobs are per billing account, shared by DEV + LIVE)
  ```
  firebase functions:list --project haystek-pulse-dev
  gcloud billing projects describe haystek-pulse-dev
  gcloud billing projects describe haystek-pulse
  ```
- [ ] Employee leaves → deactivate the same day
- [ ] If a release breaks: keep the last good build ready; raise the minimum version in `settings/app` to force the fixed build

---

### 8. Waiting on Ma'am

- [x] Company card added as **primary** on billing (19 Nov)
- [x] Company verification – done 19 Nov (was due **13 Feb 2027**)

---

### Costs (for reference)

| Item | Free | Expected |
|---|---|---|
| Firestore | 50K reads/day, 20K writes/day, 1 GB | ₹0 |
| Auth | 50K users/month | ₹0 |
| Notifications (FCM) | unlimited | ₹0 |
| Cloud Functions | 2M calls/month | ₹0 |
| Cloud Scheduler | 3 jobs per billing account | ₹0 (≈ ₹8 per extra job/month) |
| Hosting | 10 GB, 360 MB/day | ₹0 |
| Daily backup (7 days) | – | ≈ ₹2/month |
| Apple Developer | – | paid, $99 renews yearly |
| Google Play | – | paid (one time) |

<!-- PULSE-TRACKER END -->
