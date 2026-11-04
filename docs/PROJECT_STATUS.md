# NoteNest — project status and hand-off

Last updated 2026-11-04. Version **1.0.2+6** (`pubspec.yaml`). Read this first if
you have just pulled the repository.

## What the app is

Flutter app for university students: notes, exams, planner, cover pages,
Word/PDF conversion, classes, chat, Google Drive backup. English and Bangla,
light and dark. Notes live on the phone (SQLite); a cloud account (Firebase) is
optional and adds sharing, chat and classes. Package `com.notenest.app`.

## State

| Area | State |
|---|---|
| Code | Complete for version 1. `flutter analyze` clean, 283 tests pass |
| Firebase project | `notenest-740b5` (Spark plan). Email/Password and Google sign-in enabled. Firestore rules published. Crashlytics enabled |
| Google Cloud | Drive API enabled; `drive.file` scope on the OAuth consent screen; app "In production" |
| Release build | `flutter build appbundle --release` gives `build/app/outputs/bundle/release/app-release.aab`. Needs the upload key (not in git, see below) |
| Verified on emulator with a real Google account | Google sign-in, Drive backup and restore, offline sign-in/sign-up messages, setup flow, notes, release APK with 4000 random events and no crash |
| Not yet tested by anyone | Chat, message requests, classes and assignments, report/block, account deletion, fingerprint lock (all need two real accounts or a real phone) |
| Push notifications | Deliberately **off** (`PushService.enabled = false`). Needs Blaze plan, `firebase deploy --only functions`, a two-phone test. Do not mention push in the store listing |
| Play Store | Not published. See "Next steps" |

## Things that are NOT in git, on purpose

* `android/key.properties` and `android/upload-keystore.jks`: the Play upload
  key. Without them `flutter build appbundle --release` fails (by design, it
  never falls back to the debug key). Ask the owner for them; they must be
  backed up off the owner's laptop.
* `android/local.properties`, build output, `.dart_tool/`.
* `photo/` and anything in `deck/shots` marked PRIVATE: contain real people's
  details. The repository is public.

## Decisions already made (do not re-open without a reason)

* **Crash reporting:** Firebase Crashlytics only (free, same Firebase project).
  Collection is off in debug builds and on web. No Sentry.
* **No product analytics** (no PostHog, no Firebase Analytics). The privacy
  policy promises "no ads, no analytics, no trackers"; the only thing that
  leaves the phone unasked is a crash report.
* **Android auto-backup is off** (`allowBackup=false`). Backup is the user's own
  Google Drive backup, offered once after the first manual backup.
* **Reminders** use inexact alarms (no exact-alarm permission needed).
* **Publishing** goes through a friend's Play Console account; the owner is
  invited as a user (never share the friend's password).
* The privacy policy and the data inventory must change whenever data handling
  changes: `docs/privacy-policy.html`, `docs/PRIVACY_DATA_INVENTORY.md`.

## Next steps (in order)

1. Owner is invited to the friend's Play Console as a user.
2. Test the untested cloud features with two accounts (list above).
3. Fill the Play Console from `docs/PLAY_CONSOLE_ANSWERS.md` (listing text in
   English and Bangla, Data safety, content rating, App access, deletion URL).
   Create two test accounts (student, teacher) for the reviewer first.
4. Make the screenshots: raw 1080×1920 screenshots and ChatGPT prompts are in
   `store_screenshots/` (`CHATGPT_PROMPTS.md`). Feature graphic 1024×500.
5. Upload the AAB to **Internal testing**. Accept Play App Signing.
6. Copy the **Play app-signing SHA-1** (Play Console → App integrity) into
   Firebase (Project settings → Your apps → Add fingerprint), download the new
   `google-services.json` into `android/app/`, bump the build number, rebuild,
   upload again. Without this Google sign-in fails in the Play-installed app.
7. Check whether a closed test (testers × days) is required for the account
   type, then Closed testing, then Production.
8. Back up the keystore and `key.properties` somewhere safe.

Optional later: official Google logo on the Google button, restore offered
before setup on a new phone, Firebase App Check, push notifications, classes
and chat screenshots.

## Where things are

* `docs/PLAY_STORE_RELEASE_CHECKLIST.md` — release checklist (current).
* `docs/PLAY_CONSOLE_ANSWERS.md` — text to paste into the Play Console.
* `docs/PRIVACY_DATA_INVENTORY.md`, `docs/privacy-policy.html` — data handling.
  Policy URL: `https://mdsarowarofficial.github.io/notenest/privacy-policy.html`.
* `docs/MODERATION.md` — how to handle reports in the Firebase console.
* `docs/PUSH_SETUP.md` — how to turn push on (not for version 1).
* `firestore.rules` and `firestore-tests/` — rules and their tests (`npm test`).
* `store_screenshots/` — store screenshots made from the release build with a
  made-up student ("Nadia Rahman").
* `deck/` — project presentation files.

## Useful commands

```
flutter analyze
flutter test
flutter build appbundle --release      # needs the upload key
cd firestore-tests && npm test         # rules tests
```
