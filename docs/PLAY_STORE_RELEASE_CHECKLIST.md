# NoteNest — Play Store release checklist

State as of this audit. Nothing is ticked that was not actually verified, and
"verified by reading" is distinguished from "verified by running".

## Build and signing

| Item | State | Evidence |
|---|---|---|
| Application ID | **done** — `com.notenest.app` | `android/app/build.gradle.kts`. Was `com.example.notenest`, which Play rejects |
| `namespace` matches | done | same file; `MainActivity.kt` moved to `com/notenest/app/` and the old package deleted |
| Firebase registered for the new ID | **done** | `google-services.json` contains `com.notenest.app` |
| Version | `1.0.0+1` | `pubspec.yaml` |
| Upload keystore exists | **done** | created with the Android Studio JDK's `keytool`, RSA 2048, 10,000 days |
| `key.properties` | **done** | four values; written by a script that never printed the password |
| Keystore kept out of git | **verified** | `git status` after the commit listed neither `key.properties` nor the `.jks`; `.gitignore` carries `**/key.properties`, `**/*.jks`, `**/*.keystore`, `**/*.p12`, `**/*.pepk` |
| Keystore backed up off this laptop | **UNKNOWN** | only the owner can confirm. Lose it and the app can never be updated |
| Release does not fall back to debug signing | **done this audit** (NN-04) | a missing key now throws; `-PallowDebugSigning=true` is the deliberate opt-out |
| Release APK builds | **was passing** before this audit's changes | `app-release.apk`, 84.5 MB |
| Release AAB built | **NOT RUN** | `flutter build appbundle --release` |
| Release build tested on a real device | **NOT RUN** | the single most important unrun check |
| `minSdk` / `targetSdk` | Flutter defaults | **unverified against Play's current target-API requirement** — check the Play Console, which states the current minimum |
| Code shrinking | off, deliberately | R8 removes reflection-reached classes (sqflite's channel, Syncfusion's viewer, firebase_auth's providers). Keep rules were never written or tested, and a release-only crash is the worst class of bug |
| APK size | 84.5 MB | three ABIs in one file. An AAB cuts this to roughly a third per device, which is reason enough to ship the AAB |

## Icon, splash, appearance

| Item | State |
|---|---|
| Adaptive icon | **done** — `mipmap-anydpi-v26` + 108dp foregrounds at five densities + background colour |
| Legacy and round icons | done, five densities each |
| Manifest label | **done** — `NoteNest` (was `notenest`) |
| Native splash colour | done — the icon's yellow, so there is no white flash |
| Web icons and favicon | done |
| Icon legibility at 48 px | **verified by rendering** — the fold and the highlighted line both survive |

## Policy — the blockers

| Requirement | State | What it needs |
|---|---|---|
| **Privacy policy URL** | **MISSING — blocker** | Host one. Contents are specified in `PRIVACY_DATA_INVENTORY.md`. GitHub Pages is free and sufficient |
| **In-app account deletion** | **done this audit** (NN-05) | Profile → Delete account. Also needs a **web deletion request page**, which Play asks for alongside the in-app route |
| **Data Safety form** | not filled | answers are tabulated in `PRIVACY_DATA_INVENTORY.md` |
| **UGC: report content** | **MISSING — blocker** | the app has chat; Play requires an in-app way to report a message |
| **UGC: block a user** | **MISSING — blocker** | and a way to block the person who sent it |
| **UGC: a content policy** | missing | a short acceptable-use statement, shown or linked |
| Content rating questionnaire | not done | the chat feature changes the answers; fill it after the UGC work |
| Target audience | not set | must be 13+. The app is not designed for children and should not say it is |
| Ads declaration | none — correct | no advertising SDK exists |
| App access for reviewers | **needed** | the reviewer cannot see sharing, groups or chat without an account. Provide a test cloud account and password in the Play Console's App Access section, or the review stalls |
| Third-party licences | **partly** | the two bundled fonts ship with their OFL files. Flutter package licences are not surfaced anywhere in the app — a "Licences" entry using `showLicensePage` would close this |

### What the UGC work actually requires

Scoped here so it is not vague. Not implemented; this is the specification.

1. **Block** — a per-person list held locally. A blocked person's messages are
   hidden, their shares do not reach the inbox, and a direct chat with them
   cannot be opened. Local is enough and needs no new rules.
2. **Report** — on a message and on a thread. Writes to a new `reports`
   collection: reporter uid, reported uid, chat id, message id, a copy of the
   text, a reason, a timestamp. Rules: `create` only, by a signed-in user whose
   own uid is the reporter; **no read, no update, no delete** by anyone,
   because only the owner reads it in the console.
3. **A visible route for the owner to act** — at minimum a support email in the
   listing and a stated response time.
4. **An acceptable-use line** in the privacy policy or beside the chat.

Until 1 and 2 exist, a student being harassed can only leave the group. That is
both a policy failure and a real one.

## Listing

| Item | State |
|---|---|
| App name | NoteNest |
| Short and full description | not written |
| Screenshots (phone, at least 2) | not taken — take them after the real-device test, from the release build |
| Feature graphic 1024×500 | not made |
| Category | Education |
| Contact email | **must be a real monitored address** |
| What claims the listing may make | only what exists. **Teacher assignments do not exist.** Scheduled reminders are not implemented as real notifications |

## Order of work

1. Run every BLOCKED check in `TEST_PLAN.md` §1. Nothing below matters until the
   code compiles and the 188 tests pass.
2. Test §5 (group chat) and §7 (sign-in with a pre-audit account). Those two
   rule and password changes are the ones that could break a working app.
3. Install the release APK on a real phone and work through §8.
4. Build and test the AAB.
5. Write and host the privacy policy.
6. Build block and report.
7. Turn on App Check and a Firestore usage alert.
8. Fill the Data Safety form and the content rating.
9. Screenshots, descriptions, test account for reviewers.
10. Internal testing track first — not production.

## Honest verdict

**NOT READY**, and not close on the policy side.

The engineering is in decent shape: the critical directory leak is closed, the
password hashing is a recognised algorithm with its implementation verified
against a reference, account deletion exists, and the release cannot be signed
with a debug key by accident any more.

What stands between this and a responsible public release is not more code
quality. It is that nothing in this audit has been compiled, that there is no
privacy policy, and that an app where students message each other ships without
a way to report or block anybody.
