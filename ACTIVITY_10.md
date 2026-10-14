# Activity 10, part 1 — The cloud account

Gantt Week 8. Gantt deliverables: cloud sync, accounts, security.

This is the foundation the rest of Activity 10 stands on: a real Firebase
account, a profile document, and security rules to replace test mode. Chat,
groups, app-to-app sharing and teacher assignments arrive in part 2, on top of
exactly this.

## How to install

```powershell
cd C:\project\notenest
# unzip over the project, overwriting
flutter pub get
flutter analyze
flutter test
flutter run -d chrome --web-port=5000
```

**No new packages.** `firebase_core`, `firebase_auth` and `cloud_firestore`
were added in the last step and are already in `pubspec.yaml`. Nothing outside
`lib`, `test` and the new `firestore.rules` changed: no Gradle edit, no
manifest edit.

⚠️ **`lib/firebase_options.dart` is not in this zip and must not be.** That
file is generated from your own Firebase project by `flutterfire configure`
and holds your keys. Extracting over the project leaves it exactly as it is.

## The rule this part is built on

**The cloud is an extra. It is never a requirement.**

NoteNest worked entirely on the device for nine activities, and it still does.
Notes, subjects, exams, cover pages and conversions do not touch Firebase at
all. If Firebase cannot start — no configuration, no connection, a project
that was deleted — the app opens normally and one screen explains itself.

That is not a sentiment, it is the shape of the code. `CloudService.start()`
catches everything and records why; every method after it begins by checking
`isReady` rather than assuming. `FirebaseAuth.instance` throws if it is read
before `Firebase.initializeApp` has succeeded, and a single such read on a
startup path would take the whole app down for a student who only wanted to
write a note.

## New files (4)

| File | What it is |
|---|---|
| `lib/models/cloud_profile.dart` | The profile, the email rules, and the wording of every Firebase error. No Firebase import — 9 unit tests on it. |
| `lib/data/cloud_service.dart` | The only file that talks to Firebase. |
| `lib/screens/cloud/cloud_page.dart` | Connect, sign in, see what it unlocks, disconnect. |
| `firestore.rules` | The real security rules, to paste into the console. |

## Changed files (4)

| File | Change |
|---|---|
| `lib/main.dart` | Starts Firebase before the first frame. It cannot fail the launch. |
| `lib/data/note_repository.dart` | A "Cloud account" drawer link; the dead `isSynced` stub removed. |
| `lib/screens/shell/home_shell.dart` | The drawer's sync dot now means something: it watches the real cloud state. |
| `test/widget_test.dart` | 11 more tests — **137 in total**. |

## 🛑 One thing you must do in the console

The rules in `firestore.rules` are not applied by installing this zip —
Firestore rules live in the project, not in the app.

1. [console.firebase.google.com](https://console.firebase.google.com) →
   `notenest` → **Build → Firestore Database → Rules**
2. Select everything in the editor and delete it
3. Paste the whole contents of `firestore.rules`
4. **Publish**

Until you do, the database is in test mode: **anyone at all can read and write
every document.** That is fine while nothing real is stored and it is not
something to hand in.

## Three things worth defending in the viva

**The address is taken from the token, not from the form.** In the create rule:

```
incoming().email == request.auth.token.email.lower()
```

Firebase already knows which address was verified at sign-up. Trusting the
client's copy instead would let anyone register themselves under a classmate's
address and receive the notes meant for them. The rule compares against what
the token says, so that cannot happen whatever the app sends.

**Searching is capped, and the cap is explained rather than hidden.** A profile
lookup is an exact match on the folded address, and `list` requires
`request.query.limit <= 20`. A directory anyone can page through is the user
table leaked. It is worth being straight that this raises the cost of a bulk
dump rather than making one impossible — many small queries still work — and
that what is exposed is a name against an address the caller already knew.

**Every Firebase error code is translated into an instruction.** Firebase's own
messages are written for developers; `describeAuthError` rewrites each one for
the person holding the phone, and each says what to *do*. The one worth having
is `operation-not-allowed`, which in practice always means a switch in the
console that nobody remembers:

> Email and password sign-in is switched off in the Firebase console. Turn it
> on under Authentication → Sign-in method.

There is a test asserting that each known code produces a message, and that an
unknown one still produces a sentence rather than a bare code.

## Two accounts, and why

The app now has a device account and a cloud account, and they are separate on
purpose.

The device account is what opens the app. It owns the notes, it works with no
connection, and it has never needed a server. The cloud account is what other
people can reach: it is how a classmate finds you and how a teacher's
assignment knows where to go.

Keeping them apart means connecting to the cloud cannot break anything that
already worked, and disconnecting cannot take a single note with it. The
connect form pre-fills your name and address from the device account, so in
practice it is one password and two taps.

## How to check it actually worked

Not from the app — from the console, which is the only place that can prove
a write really landed.

1. Drawer → **Cloud account** → **Create** → the name and email are already
   filled in → type a password → **Student** → **Create cloud account**
2. Console → **Authentication → Users** — your email is listed, with a UID
3. Console → **Firestore Database → Data** — a `users` collection, one
   document named with that same UID, holding `name`, `email` (lowercased),
   `role`, `institution`
4. Close the app and open it again — the drawer still shows connected

If step 2 works but step 3 does not, the rules are published and the write was
refused: check that you created the account *after* publishing, or re-read the
`users` rules. If neither works, the screen shows what Firebase said.

## Known limitations

- **Nothing syncs yet.** This is an account and a profile. Notes stay on the
  device; the features that use the cloud come in part 2.
- **No password reset, no email verification.** Both are a few lines on top of
  this, and neither is needed to prove the foundation works.
- **Timestamps come from the phone's clock,** not from Firestore's server.
  For a profile that is harmless. Chat messages in part 2 will need
  `FieldValue.serverTimestamp()`, because a message ordered by a wrong clock
  appears in the wrong place in the conversation.
- **One cloud account per device.** Switching accounts means disconnecting
  first.
- **`permission-denied` after publishing the rules is expected** for anything
  outside `users`. The catch-all deny at the end of the file is deliberate:
  a collection nobody has thought about should not be writable because nobody
  has thought about it.
