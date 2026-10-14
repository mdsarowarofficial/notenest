# NoteNest — pre-release production audit

Audited commit: `dcfe428` ("Soft Depth design pass, People tab, and release
signing") plus the unpushed icon and opening-animation work.

Auditor's standing: I wrote most of this code. Nothing below is accepted
because I wrote it; where my own earlier reasoning was wrong, the finding says
so and names the comment that was wrong.

## What I could and could not verify

This matters more than anything else in the report, so it is first.

The audit environment has **no Dart SDK**. `flutter analyze`, `flutter test`,
`flutter build` and the Firebase Emulator Suite could not be executed. Every
check that needs them is marked **BLOCKED**, not PASS, and the fixes below are
reasoned and statically checked but **not compiled**.

| Check | Status | Note |
|---|---|---|
| Static structural check (`check.py`) | **PASS** | 24 known findings before, 26 after; the 2 new are the known `attachment_store` conditional-export false positive, which every file using that class produces |
| PBKDF2 implementation correctness | **PASS** | Transcribed to Python and compared against `hashlib.pbkdf2_hmac` across 6 vectors including Bengali input and an empty password — all identical |
| Firestore rule reasoning | **PASS (by reading)** | Each rule re-derived against an attacker who has replaced the client. Not executed against the emulator |
| `flutter pub get` | **PASS** (owner ran it) | no new packages, as intended |
| `dart format --set-exit-if-changed` | **NOT RUN** | |
| `flutter analyze` | **PASS after one fix** (owner ran it) | found `unawaited_return_in_try_block` at `cloud_service.dart:402` — a real defect I introduced in the NN-01 fix, recorded as NN-13 and fixed |
| `flutter test` (190 tests) | **PASS** (owner ran it) | 190, not 188 — my `grep` count was low. All passed, including every auth test, which is the first evidence that the PBKDF2 change did not break verification |
| Firestore rules unit tests | **BLOCKED** | needs Node + emulator, neither installed |
| Android debug build | **BLOCKED** | no Android SDK |
| Android release AAB | **BLOCKED** | no Android SDK, and the signing key is correctly not here |
| Multi-account authorization test | **NOT RUN** | needs two live accounts on a device |
| Real-device release test | **NOT RUN** | needs the phone |

Everything marked BLOCKED has to be run by the project owner. The commands are
in `TEST_PLAN.md`.

## Findings

Severity follows the brief. "Confirmed" means I can point at the line.

---

### NN-01 · CRITICAL · Confirmed vulnerability · Any signed-in user could page through the entire user directory

**Where** `firestore.rules`, `/users/{userId}`:

```
allow list: if signedIn() && request.query.limit <= 20;
```

**Evidence** A Firestore rule cannot see *which field* a query filters on —
only `request.query.limit`. The comment above that line argued the exposure was
limited because "the only thing exposed is a name against an address the caller
already knew". That is false, and it was my own comment. The rule constrains
the page size, not the query. A signed-in attacker could ask for twenty users
ordered by any field and walk a cursor through the collection.

**Impact** Full disclosure of every registered account: display name, email
address and institution. For a student app that is a classmate directory handed
to anyone who registers.

**Reproduction** Sign in as any account. Issue
`users.orderBy('email').limit(20).get()`, then repeat with `startAfter` on the
last document. No filter on your own uid is needed; the rule permits it.

**Fix applied** `allow list: if false`. Finding a classmate now goes through a
new `/emailIndex/{address}` collection where the folded address *is* the
document name, so a lookup is a `get` of a document you can already spell.
`CloudService.findByEmail` reads the index and then the profile.
`_writeEmailIndex` is called on account creation and on every sign in, so
accounts that pre-date the index become findable again the first time they open
the app.

**Residual** Someone can still test one address at a time and learn whether it
is registered, receiving a uid and no name. That is a deliberate trade and is
disclosed in `SECURITY_REVIEW.md`.

**Test added** None automated — rules tests need the emulator (BLOCKED). The
manual two-account procedure is in `TEST_PLAN.md` §4.

---

### NN-02 · HIGH · Confirmed weakness · Passwords hashed with one round of SHA-256

**Where** `lib/data/auth_repository.dart`:

```dart
static String _hash(String password, String salt) =>
    sha256.convert(utf8.encode('$salt::$password')).toString();
```

**Evidence** Salted, but a single round of a hash designed to be fast. Commodity
hardware tries billions of SHA-256 candidates per second.

**Impact** Anyone who obtains the device database — an unlocked phone, an
extracted backup — recovers passwords for every local account in a short time.
People reuse passwords, so the loss is not limited to NoteNest.

**Fix applied** PBKDF2-HMAC-SHA256, 120,000 rounds, 32-byte output, stored as
`pbkdf2$<rounds>$<base64url>` so the cost is recorded with the hash and can be
raised later without locking anyone out. `crypto` was already a dependency, so
no new package. Old rows are detected by the absence of the `pbkdf2$` prefix,
verified with the legacy function, and **transparently rewritten in the new
form on the next successful sign in**. Nobody is asked to reset anything.
Comparison is constant-time.

**Test added / result** `pbkdf2_check.py` transcribes the Dart literally and
compares it with Python's `hashlib.pbkdf2_hmac` over six vectors (1, 2, 1000,
4096, 50 and 777 rounds; Bengali password and salt; empty password; 200-char
password), plus the stored-format round trip at the shipped 120,000 rounds, plus
a check that base64url output can never contain the `$` that `_verify` splits
on. **All PASS.**

**Unmeasured, and he must measure it** 120,000 rounds of HMAC-SHA256 in Dart
costs real time on a phone, and I could not measure it. If sign-in feels slow,
lower `_pbkdf2Rounds` — it is one constant and old hashes keep working because
the round count travels with each hash.

---

### NN-03 · HIGH · Confirmed defect · Signing out did not clear the previous account's data from memory

**Where** `lib/data/auth_repository.dart` `signOut()`, and
`lib/screens/profile/profile_page.dart:154`.

**Evidence** `signOut()` cleared the session and nothing else.
`NoteRepository.clear()` — which empties the cached notes, subjects and exams —
was called by the profile screen immediately afterwards, and by nothing else.
Searching the tree, `profile_page.dart` was the only caller.

**Impact** In the shipped UI the window is small: the login screen draws no
notes, and signing in calls `load()`. But the invariant lived in a *caller*
rather than in the thing being signed out of, so the first sign-out path added
anywhere else would leak one account's notes into the next session with no
warning. Classified HIGH for that reason rather than for a demonstrated leak;
it is a latent cross-account exposure, not a confirmed one.

**Fix applied** `AuthRepository` gained `addSignOutHook`, run inside
`signOut()`. `NoteRepository`'s private constructor registers `clear`. The
rows leave memory because the account left, not because a button remembered.
The profile screen's own call is left in place and is now redundant.

---

### NN-04 · HIGH · Confirmed defect · A release build with no key silently used the debug key

**Where** `android/app/build.gradle.kts` (code I added earlier this session).

**Evidence** `signingConfig = if (hasReleaseKey) … else signingConfigs.getByName("debug")`.
My comment claimed this was safe because the Play Store would reject such a
build. The brief's rule 515 says the opposite and is right.

**Impact** A debug-signed APK installs, runs and looks finished. It is signed
with a key shared by every Flutter project in existence, so anyone can forge an
update to it. Discovering this at the store is late; discovering it after
handing the APK to classmates is worse.

**Fix applied** A release build with no `android/key.properties` now throws a
`GradleException` naming both remedies. A deliberately unsigned build is still
possible but must be asked for out loud: `-PallowDebugSigning=true`, which also
logs a warning saying the artifact must not be given to anyone.

---

### NN-05 · HIGH · Product/policy blocker · No way to delete an account

**Where** Nowhere — searched; `deleteAccount` did not exist in any form. (An
earlier note of mine described it as "dead code that needs exposing"; that was
wrong, there was no code.)

**Impact** Google Play requires an app that lets a person create an account to
offer deletion **from inside the app**. Without it the listing is rejected.

**Fix applied**
* `AuthRepository.deleteAccount({password})` — re-verifies the password, deletes
  the `users` row. Subjects, notes, exams, settings and attachment rows go with
  it through `ON DELETE CASCADE`, which works because `app_database.dart` sets
  `PRAGMA foreign_keys = ON` in `onConfigure` (verified).
* `AuthRepository.attachmentFileNamesForCurrentUser()` — files on disk are not
  rows and do not cascade, so the names are read **before** the rows go.
* `CloudService.deleteCloudAccount({password})` — reauthenticates, deletes
  `emailIndex/{address}`, then `users/{uid}`, then the Firebase Auth user, in
  that order (the last one removes the permission to do the first two).
* `firestore.rules` — `users` now allows `delete: if isSelf(userId)`;
  `emailIndex` allows the owner to delete their own entry.
* A confirmation dialog that requires the password **and** the typed word
  DELETE, and that states what does not get deleted.

**Residual, and disclosed in the dialog** Messages already sent and notes
already accepted stay in the recipients' copies under the name they were sent
with. Deleting those would mean editing other people's data, and on the Spark
plan there is no server-side job that could do it safely. This must also be
stated in the Play Data Safety form.

---

### NN-06 · MEDIUM · Confirmed defect · A group member could inflate the member list without limit

**Where** `firestore.rules`, the join rule on `/groups/{groupId}`.

**Evidence** The rule required
`memberUids == resource.data.memberUids.concat([request.auth.uid])` but never
checked that the caller was *not already* a member. Sending the same join
repeatedly appends the same uid each time.

**Impact** Denial of service on a shared document. Every member downloads the
array on every read, and at the 1 MiB document ceiling the group becomes
unwritable — nobody can join, leave, or rename it again. Roughly 30,000
repetitions of a 28-byte uid.

**Fix applied** `&& !(request.auth.uid in resource.data.memberUids)` and
`&& request.resource.data.memberUids.size() <= 60`.

---

### NN-07 · MEDIUM · Confirmed defect · A chat thread could be re-pointed at another group

**Where** `firestore.rules`, the update rule on `/chats/{chatId}`, which listed
`kind` and `groupId` among the fields any thread participant may change.

**Impact** Authorization is derived from the chat **id**, not from these fields,
so this is not an access-control break. It is an integrity one: a member could
rewrite which group a thread claims to belong to, and the app reads `groupId`
when presenting a thread.

**Fix applied** Both removed from the allowed set. A write that leaves them
unchanged does not appear in `changedKeys()` at all, so the app's existing
merge still works; a write that changes them is refused.

**Needs live verification** This is the one rule change that could break a
working feature if the app ever writes a *different* value for those fields.
`TEST_PLAN.md` §5 has the group-chat test that proves it.

---

### NN-08 · MEDIUM · Confirmed risk · Shares accumulated for ever and could fill the project

**Where** `firestore.rules`, `/shares/{shareId}`: `allow delete: if false`.

**Evidence** A share carries a payload of up to 700 KB (enforced at
`textWithin(incoming().payload, 716800)`). Nothing could ever remove one.

**Impact** The Spark plan gives the whole project 1 GiB. About 1,500 shares
fill it, after which **nobody can send anything**. Ordinary use reaches that
slowly; a malicious client reaches it deliberately.

**Fix applied** Either party may delete a share once it has been answered
(`state != 'pending'`), so normal use stops accumulating.

**Residual, not fixed** A deliberate flood is still possible. Rules cannot rate
limit, and Cloud Functions need the Blaze plan. The mitigations available are
Firebase App Check and a budget alert; see `SECURITY_REVIEW.md`.

---

### NN-09 · MEDIUM · Defence in depth · Local mutations found their row by id alone

**Where** `lib/data/note_repository.dart` — ten `update`/`delete` statements
with `where: 'id = ?'` on `notes`, `subjects`, `exams` and `attachments`.

**Evidence and honest scope** Every id reached these through a list that had
already been filtered to the signed-in account, so **no cross-account write is
reachable in the shipped app**. This is a defence-in-depth finding, not a
confirmed vulnerability, and it is recorded as one.

**Why fix it anyway** The safety was a property of the callers, not of the
statements; combined with NN-03 (stale cached objects after a sign out) the
two together are how such a bug actually arrives.

**Fix applied** All ten now carry `AND user_id = ?`. `attachments` has no
`user_id` of its own and is scoped through its note:
`id = ? AND note_id IN (SELECT id FROM notes WHERE user_id = ?)`.

---

### NN-10 · MEDIUM · Confirmed defect in my own tooling · The static checker was blind to part of every file

**Where** `check.py`, the unused-import rule.

**Evidence** The import-stripping regex was `^\s*(?:import|export)[^;]*;`.
`\s*` matches newlines and there is no word boundary after the keyword, so the
line

```dart
important: repo.importantUnrevisedCount,
```

matched as a directive, and `[^;]*` then consumed **1,575 characters** to the
next semicolon — deleting an entire `build` method before any rule looked at it.

**Impact** Every check that reads the stripped body was blind to that region.
It also produced two false "unused import" findings, which I had been carrying
in the baseline as accepted noise.

**Fix applied** The pattern now requires the directive form: keyword,
whitespace, then a quote. The two false findings disappeared and the
previously-invisible region came back clean.

---

### NN-11 · INFORMATIONAL · A student can promote themselves to teacher

**Where** `firestore.rules`, `/users/{userId}` update: `role in ['student', 'teacher']`.

Nothing in the app currently grants a teacher any privilege, so there is nothing
to escalate to **today**. It is recorded because the teacher-assignment feature
is planned, and the day a rule trusts `role` is the day this becomes a real
privilege escalation. Assignment rules must derive authority from group
ownership, not from a self-asserted field.

---

### NN-13 · MEDIUM · Confirmed defect · A catch block that caught nothing

**Where** `lib/data/cloud_service.dart:402`, in `findByEmail` — code I wrote
earlier in this same audit, for the NN-01 fix.

**Evidence** `flutter analyze` reported `unawaited_return_in_try_block`. The
line was `return profileFor(uid);` inside a `try { } on FirebaseException`.
A returned-but-not-awaited future leaves the try block before it completes, so
the handler below it never runs for anything that future throws.

**Impact** Small in practice, because `profileFor` has its own handler and
throws `CloudException` rather than `FirebaseException`. But the handler read
as protection it did not provide, and the day `profileFor` let a raw
`FirebaseException` past, it would have escaped to the UI uncaught.

**Fix applied** `return await profileFor(uid);`.

**Worth noting** This is exactly why "BLOCKED" is not "PASS". The audit's
reasoning did not find this; the analyzer found it in twelve seconds.

---

### NN-12 · INFORMATIONAL · 190 tests in a single file

`test/widget_test.dart` holds all 190. Splitting them is a large diff with no
behavioural gain, so it was not done during a pre-release audit. Noted for later.

## Added after the audit · Google sign-in (Stage 1)

Not a finding — new work, recorded here because an audit document that stops
describing the thing it audited is worse than none.

**What was added.** `lib/data/google_identity.dart` (the only file that imports
`google_sign_in`), `CloudService.signInWithGoogle`,
`AuthRepository.signInWithVerifiedEmail`, a Google button on both auth screens,
and `google_sign_in: ^7.2.0` in `pubspec.yaml`.

**Three defects this created and fixed in the same breath**, each of which
would otherwise have shipped:

| | What would have broken |
|---|---|
| 1 | "Change password" was offered to an account with no password, and asked for a current one that had never existed. The row is now hidden. |
| 2 | "Delete account" demanded a password a Google account never set, so a Google user **could not delete their own account** — the one thing Play requires this screen to do (see NN-05). Deletion now re-authenticates with Google instead. |
| 3 | The cloud half and the device half of a deletion can want *different* proof, because Firebase links a Google sign-in onto an address that already has a password. Each half is now asked separately; all four combinations are covered by the Python port and all pass. |

**What is verified, and how.** The password rules for a password-less account
and the deletion routing were ported to Python and run — 23 cases, all pass,
including that the stored marker cannot be produced by either hash function for
any input, so no password opens a Google row. The `google_sign_in` version-7 API
was confirmed against the package's own issue tracker rather than from memory,
which is how two things were caught: `GoogleSignInExceptionCode` is not exported
(so the code is compared by name, not by enum), and Credential Manager reports a
*cancellation* when a signing fingerprint is unregistered (so a cancel cannot be
silently swallowed).

**A second blind spot in my own tooling, in the same place as NN-10.** The
static checker reported no new findings for either new file, and it was wrong.
`flutter analyze` found a compile error the checker could not see:
`google_sign_in_button.dart` called `profile.role.key` without importing
`cloud_profile.dart`, where `key` lives on an **extension** rather than on the
enum. The checker's import-visibility rule scans for capitalised names, because
those are the types and constructors — so every extension member in the project
is invisible to it, and there are twenty-one extensions. This is the second time
in this audit that the real finding came from the compiler and not from my
reasoning, which is the argument for running both and for trusting neither
alone. The rule was left as it is; widening it to lowercase identifiers would
drown it in false positives, and the compiler already covers this class.

The same blind spot then showed its other face. With the import added, the
checker's companion rule reports `import looks unused ->
../../models/cloud_profile.dart` — for an import the file cannot compile
without. One rule missed a needed import and the other now calls it
unnecessary, from the same cause: neither can see an extension member. That
finding is therefore expected, and is recorded here so the next person does not
"fix" it by deleting the import and breaking the build.

**What is not verified.** None of it has been compiled or run. The Google sheet
cannot be reached from a test. Everything in `TEST_PLAN.md` §10 is NOT RUN.

## Release blockers still open

These are not fixed, and each one prevents a responsible public release.

| # | Blocker | Who can clear it |
|---|---|---|
| B-1 | Every BLOCKED check above is unrun. The fixes are uncompiled | Project owner, with the Flutter SDK |
| B-6 | **Google sign-in is untested on a device**, and it cannot work at all until both signing fingerprints are registered and `google-services.json` is re-downloaded. `TEST_PLAN.md` §10 | Owner, with the console and a phone |
| B-7 | The Google button carries **no Google logo**. Google's branding guidelines require their supplied asset, and an approximation of someone else's mark is worse than none — so it is words only for now. This must be settled before a Play listing | Owner — add the official asset |
| B-2 | **Privacy policy written, not yet hosted.** `docs/privacy-policy.html` (October 2026). Play needs a reachable URL | Owner: enable GitHub Pages on `/docs` |
| B-3 | **Report and block built (October 2026)**: hold a message, or the menu on a private chat or shared note. Blocking is enforced by the rules in private chats. Needs the updated rules deployed and a device test; reports are reviewed per `MODERATION.md` | Owner: deploy rules, test, review reports |
| B-4 | Release AAB never built or installed on a real device | Owner |
| B-5 | Teacher assignments are described in project documents and do not exist. If any store listing or report claims them, it is inaccurate | Owner — either build or stop claiming |

## Final decision

**NOT READY.**

Five real defects were found and fixed, one of them a critical directory
disclosure, and the fixes are reasoned and partly verified. But a release
decision cannot rest on reasoning alone: the code in this audit has never been
compiled, the 188 existing tests have not been run against it, and three Play
Store requirements (privacy policy, account-deletion disclosure in the Data
Safety form, UGC moderation) are not satisfied.

The honest next step is not "ship" — it is to run the BLOCKED checks, which is
one afternoon with the SDK, and then re-decide.
