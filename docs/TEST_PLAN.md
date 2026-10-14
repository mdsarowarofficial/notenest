# NoteNest — test plan

What is tested, what is not, and the exact commands. Results are recorded only
where a check actually ran; everything else says BLOCKED or NOT RUN.

## 1 · The checks the owner must run

These need the Flutter SDK, which the audit environment does not have. Run them
in order and stop at the first failure.

```powershell
cd C:\project\notenest
flutter pub get
```

```powershell
dart format --output=none --set-exit-if-changed .
```

```powershell
flutter analyze
```

```powershell
flutter test
```

```powershell
flutter build apk --release
```

Expected, after this audit's changes:

| Command | Expected | If it differs |
|---|---|---|
| `flutter pub get` | no new packages — nothing was added | a new package means a mistake; report it |
| `dart format` | may rewrite the files this audit touched | fine, commit the result |
| `flutter analyze` | **no issues** — one was found and fixed (NN-13) | report the full output |
| `flutter test` | **190 passing** — confirmed on 2026-10-14 | the auth tests are the ones at risk — see §2 |
| `flutter build apk --release` | builds, signed with the upload key | if it throws about a missing key, `android/key.properties` is gone |

Also confirm the new guard works as designed:

```powershell
Rename-Item C:\project\notenest\android\key.properties key.properties.off
flutter build apk --release
```

This **must fail** with "NoteNest release build has no signing key". Then:

```powershell
Rename-Item C:\project\notenest\android\key.properties.off key.properties
```

## 2 · Where the existing 188 tests are most likely to break

**Result on 2026-10-14: all 190 passed.** No test asserted on the hash format,
so the PBKDF2 change went through untouched. The paragraph below is kept
because it is still the thing to watch if the round count is ever changed.

The password change is the one that can break tests without breaking the app.
Any test that computes an expected hash, or that asserts on the stored value,
will now see `pbkdf2$120000$…` instead of a bare SHA-256 hex string.

If a test fails there, **do not weaken the assertion**. Send me the failure; the
correct fix is for the test to go through `signIn` rather than through the hash
format, because the format is now explicitly allowed to change.

## 3 · Sign-in latency — measure this

PBKDF2 at 120,000 rounds is deliberately slow and I could not measure it on a
phone. On the real device, time the gap between pressing Sign in and the app
opening.

| Measured | Verdict |
|---|---|
| under ~0.8 s | good, leave it |
| 0.8–2 s | acceptable; consider 60,000 |
| over 2 s | lower `_pbkdf2Rounds` in `lib/data/auth_repository.dart` |

Old hashes keep working at any setting, because each hash carries the round
count it was made with.

## 4 · Multi-account authorization — NOT RUN, needs two accounts

Needs account **A**, account **B**, and ideally **C** who is in no group.
Everything here is a manual test on a real build; none of it is automated,
because Firestore rules tests need the emulator and Node, neither of which is
installed in the audit environment.

| # | Test | Expected |
|---|---|---|
| 4.1 | A searches for B's exact address in "Message someone" | B is found |
| 4.2 | A searches for an address nobody registered | "not found", no crash |
| 4.3 | A searches with the wrong case / trailing space | still found — the address is folded |
| 4.4 | **B signs out, A signs in on the same phone** | A sees only A's notes, subjects and exams. Nothing of B's appears anywhere, including the Today list |
| 4.5 | A sends a note to B | arrives in B's inbox under A's name |
| 4.6 | B accepts, then both open the inbox | neither sees it as pending |
| 4.7 | C (in no group) is given a group's join code | C joins |
| 4.8 | C taps join **again** with the same code | refused — this is NN-06 |
| 4.9 | A leaves a group, then opens Chats | the group thread is gone from A's list |
| 4.10 | A renames a group they do not own | refused |

Accounts created for this must be test accounts. Do not use them afterwards for
real coursework — 4.4 and the deletion tests destroy data on purpose.

## 5 · Group chat after the rules change — run this before anything else

NN-07 removed `kind` and `groupId` from the fields a chat update may change.
The reasoning is that the app writes the same values every time, so they never
appear as changes — but that reasoning is untested.

| # | Test | Expected |
|---|---|---|
| 5.1 | Open an **existing** group thread and send a message | sends; no permission error |
| 5.2 | Make a **new** group and send its first message | the thread is created and the message lands |
| 5.3 | Open a direct chat and send a message | sends |
| 5.4 | Start a **new** direct chat with someone never messaged before | thread created, message lands |
| 5.5 | Watch the other phone while 5.1 is typed | typing indicator appears, then the message |

**If 5.1 or 5.2 fails with a permissions error, that is NN-07.** Send me the
error; the fix is to re-admit the two fields and pin them with an
unchanged-value comparison instead.

## 6 · Account deletion — NOT RUN, destroys data by design

Use a throwaway account.

| # | Test | Expected |
|---|---|---|
| 6.1 | Profile → Delete account, wrong password | refused, nothing deleted |
| 6.2 | Correct password, DELETE not typed | the delete button stays disabled |
| 6.3 | Both correct, confirm | returns to the login screen |
| 6.4 | Sign in again with the same address | "no account found" |
| 6.5 | From **another** account, search that address | not found |
| 6.6 | Firebase console → Authentication | the user is gone |
| 6.7 | Firestore → `users` and `emailIndex` | both documents are gone |
| 6.8 | Register again with the **same** address | works — nothing is left holding it |
| 6.9 | A note that account had shared, in the recipient's notebook | still there, as the dialog promised |
| 6.10 | Device storage after deletion | attachment files are gone, not just their rows |

6.10 is the one most likely to be wrong, because files are deleted separately
from rows. Check the app's files directory before and after.

## 7 · Migration and data preservation — NOT RUN

| # | Test | Expected |
|---|---|---|
| 7.1 | Install over an existing install that has notes | every note survives; the schema migrates |
| 7.2 | Sign in with an account created **before** this audit | works first time |
| 7.3 | Sign out and in again with that account | works — the hash was rewritten as PBKDF2 on 7.2 |
| 7.4 | Change that account's password | accepted, and the old password stops working |

7.2 and 7.3 are the transparent upgrade in NN-02. If 7.2 fails, the legacy
verification path is wrong and **nobody can sign in** — test it before anything
else that matters.

## 8 · Release-only behaviour — NOT RUN

Release builds differ from debug: AOT compilation, tree-shaken icons, a real
signature. These are the places that break only in release.

| # | Test | Why this one |
|---|---|---|
| 8.1 | App opens to the fold animation, then Today | AOT startup |
| 8.2 | Write a note, force-close the app, reopen | sqflite reaches its platform channel by reflection |
| 8.3 | Sign in to the cloud | `firebase_auth` provider classes, likewise |
| 8.4 | Open a PDF | Syncfusion viewer, likewise |
| 8.5 | Make a cover page and export the PDF | fonts and image rendering |
| 8.6 | Record a voice note; take a photo | runtime permissions |
| 8.7 | Turn off wi-fi and mobile data, open the app | opens offline; local notes work; the cloud says it is unavailable rather than hanging |

8.7 covers the 5-second timeout around `Firebase.initializeApp`, which exists
because that call **hangs** rather than throwing when there is no route to
Google — found the hard way earlier in this project.

## 9 · What is not tested at all

Stated plainly, because an untested area that nobody names is the one that
ships broken.

* **Firestore rules have no automated tests.** Everything in §4, §5 and §6 is
  manual. Automating them needs Node and the Firebase Emulator Suite.
* **No widget tests for the screens rebuilt in the design pass.** The 190
  existing tests are model and logic tests; `grep` shows none of them construct
  `NoteTile`, `NoteRow`, `TodayPage`, `PeoplePage` or `NestEmptyState`.
* **No integration tests.** There is no `integration_test/` directory.
* **Accessibility is unmeasured.** Contrast pairs were chosen to clear 4.5:1 by
  construction, not by measurement; screen-reader behaviour has never been
  tried.
* **Performance is unmeasured.** No profiling run exists. Startup time, list
  jank and memory are all unknown numbers, and the 84.5 MB APK is an observed
  fact rather than an analysed one.
* **The opening animation has never run.** It was written, and its geometry was
  checked by porting the painter's arithmetic to Python and rendering a
  filmstrip — which proves the shapes, not that Flutter draws them.
* **Nothing in §10 has been run**, and the Google sheet cannot be reached from a
  test at all. See below.

## 10 · Signing in with Google — NOT RUN, needs a device and the console

Added after the audit. **None of this has been run**, and some of it cannot be:
the account sheet is drawn by Android's Credential Manager, which does not exist
in a widget test and does not exist on the machine this was written on. What
*was* checked here is the arithmetic underneath it — the password rules for an
account that has no password, and which proof each half of a deletion asks for —
by porting both to Python and running 23 cases. That proves the decisions, not
that Google answers the phone.

§10.0 is not a test. It is the precondition, and until it is ticked off, every
failure below is this list and not the code.

**10.0 · Console**

| # | Done? | Thing |
|---|---|---|
| a | | Google provider switched **on** in Firebase → Authentication → Sign-in method |
| b | | **Debug** keystore SHA-1 added to the `com.notenest.app` app |
| c | | **Upload** keystore SHA-1 added to the same app — `E0:CD:22:…:89:96` |
| d | | `google-services.json` re-downloaded **after** b and c |
| e | | That file contains an entry with `"client_type": 3` — the web OAuth client |

Check (d) and (e) together. Two or more `certificate_hash` lines means the
fingerprints landed; a `client_type` of 3 means the web client is there:

```powershell
Select-String -Path C:\project\notenest\android\app\google-services.json -Pattern "certificate_hash","client_type"
```

If `client_type: 3` is missing, sign-in fails with `serverClientId must be
provided on Android`. The fix is to re-download the file. The escape hatch, if
that cannot be done, is `GoogleAccounts.serverClientId` in
`lib/data/google_identity.dart`.

**10.1 · The happy paths**

| # | Test | Expected |
|---|---|---|
| 10.1 | Fresh install, Login → Continue with Google, pick an account | setup, then the notebook |
| 10.2 | Sign out, Continue with Google again | the account sheet **appears again** — it must not silently re-enter the account just left |
| 10.3 | Register screen → Continue with Google, same account | straight to the notebook, **not** back through setup |
| 10.4 | Force-close and reopen | still signed in, no sheet |
| 10.5 | Firestore → `users` | one document, with the Google account's name and address |
| 10.6 | Firestore → `emailIndex` | one document, named with the lowercased address |
| 10.7 | From a second account, search that address in "Message someone" | found |

**10.2 · The paths that had no right answer before this change**

These are the ones worth the time. Each of them used to end in a message about
a wrong password, on an account that has none.

| # | Test | Expected |
|---|---|---|
| 10.8 | Google account → Settings → ACCOUNT | **no** "Change password" row; a "Sign-in method · Google" row instead, with no chevron |
| 10.9 | Google account → Profile → Delete account | asks for **DELETE only**, no password field, and says Google will ask again |
| 10.10 | Confirm it, then close the Google sheet without choosing | "Nothing was deleted" — and the account still signs in afterwards |
| 10.11 | Confirm it and pick the account | Firebase user gone, `users` and `emailIndex` documents gone |
| 10.12 | Register with email+password **and** cloud; sign out; Continue with Google with the *same* address | signs in, the notes are still there, and Settings **still shows** "Change password" — the password was not taken away |
| 10.13 | After 10.12, Delete account | asks for the password **and** shows the Google sheet, because the two halves want different proof |
| 10.14 | Type a Google account's address into the **password** form and sign in | "This account signs in with Google…", not "that password does not match" |

10.12 and 10.13 are the pair most likely to be wrong, because they only happen
when Firebase links a Google sign-in onto an address that already had a
password — which it does by default, and which means the cloud half and the
device half genuinely disagree about what proof to ask for.

**10.3 · The failure that lies about itself**

| # | Test | Expected |
|---|---|---|
| 10.15 | Build a release APK **before** adding the upload SHA-1, then tap the button | it reports a *cancellation*, together with the notice about this build maybe not being registered |

10.15 is here deliberately. Credential Manager returns the same cancellation for
"the person tapped away" and "this build's signing fingerprint is not
registered" — the plugin's maintainer confirms this in flutter/flutter#171761.
Without that notice, a wrong fingerprint looks exactly like a button that does
nothing, for ever. **Do not delete the wording in `googleCancelledNotice`.**

## 11 · What Stage 1 deliberately does not do

Two things anyone would reasonably assume are now working, and are not:

* **Notes still do not sync between phones.** Signing in with Google on a second
  device brings the account across and nothing else — the same as the existing
  cloud sign-in, and the snackbar on that path says so out loud.
* **Nothing is in Drive.** `GoogleAccounts.authorizeDrive` is written and the
  scope is chosen (`drive.file`, which is non-sensitive), but **no code calls
  it**. Enabling the Drive API changes nothing until Stage 3.
