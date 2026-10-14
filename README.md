# NoteNest

An academic note-management app for university students, written in Flutter.
Final-year project.

Notes live on the device and work with no connection. A cloud account is an
extra that unlocks sharing, group chat and teacher assignments — connecting one
cannot break anything that already worked, and disconnecting cannot take a
single note with it.

---

## What it does

**On the device, with no account and no connection**

- Notes filed under subjects, with tags, topics and a study status
  (New → Read → Review → Mastered)
- Photos, PDFs and voice recordings attached to a note
- Exams and quizzes with a countdown, a revision queue ordered by what you have
  not mastered, and a daily target
- A month calendar of what is due
- **Cover page generator** — assignment, lab report, project, thesis or
  presentation, in five templates, with the university picked from a bundled
  directory of 10,248 institutions in 200 countries
- **Convert** between Word and PDF, both directions
- Share a note as a `.notenest` file through WhatsApp, Telegram or anything else
  on the phone, and import one the same way
- A Shared inbox that keeps the sender's name on every borrowed note

**With a cloud account**

- Study groups and class groups, joined with a six-character code
- Send a note to one person by their exact email address, with an Accept step
- Group chat and one-to-one chat, with read receipts and typing
- Post a note into a conversation — everyone sees it at once, and each person
  decides separately whether to keep it

---

## Running it

Flutter 3.47 or newer.

```bash
flutter pub get
flutter run
```

On the web, always pin the port:

```bash
flutter run -d chrome --web-port=5000
```

The port matters. A browser keeps the local database per origin, so a different
port is a different database and accounts appear to vanish.

### Firebase

The cloud half needs a Firebase project of your own. Without one the app still
runs; the Cloud screen explains itself and everything on the device keeps
working.

```bash
dart pub global activate flutterfire_cli
flutterfire configure        # tick android AND web
firebase deploy --only firestore:rules
```

`flutterfire configure` writes `lib/firebase_options.dart` and
`android/app/google-services.json`, both specific to your project.

---

## How it is put together

```
lib/
  models/      pure Dart — no Flutter, no Firebase, no database. All tested.
  data/        repositories, the database, the one file that touches Firebase
  screens/     one folder per area
  widgets/     shared pieces
  theme/       the design language
test/          188 tests, all against models/ and the pure logic in data/
firestore.rules   the security rules — see below
```

Three rules the codebase sticks to:

**`models/` imports nothing heavy.** Not Firebase, not sqflite, not the
database. That is what makes 188 tests runnable without an emulator, a network
or a device.

**Exactly one file imports Firebase** — `lib/data/cloud_service.dart`. Every
method in it checks that Firebase actually started before using it, because
`FirebaseAuth.instance` throws if it is read too early and one such read on a
startup path takes down the whole app for somebody who only wanted to write a
note. Startup is also bounded by a timeout: on a connection that cannot reach
Google at all, `Firebase.initializeApp` does not fail, it waits — and an
unbounded wait before the first frame is a white screen.

**No state-management package.** Repositories are `ChangeNotifier` singletons
and screens use `ListenableBuilder`. One fewer dependency to explain.

### The security rules are the only defence

There is no server code — the Spark plan has no Cloud Functions — so
`firestore.rules` is not a second line behind a trusted backend. It *is* the
line. Every write comes from a client somebody could replace.

Three worth reading:

```
incoming().email == request.auth.token.email.lower()
```
A profile's address is taken from the signed-in token, never from what the
client typed, so nobody can register under a classmate's address.

```
request.resource.data.memberUids == resource.data.memberUids.concat([request.auth.uid])
```
Joining a group adds exactly one uid — your own. Not "contains". *Equals.* A
joiner cannot bring a friend, drop anybody, or rename the group in the same
write.

```
allow update: if false;     // on joinCodes
```
Join codes are unique because the rules make them so. Firestore applies
`create` only when a document does not exist, so two phones racing for the same
code do not both win — the second is refused and the app tries another. No
read-then-write, no window between checking and taking.

### Why cover pages are drawn rather than typeset

`dart_pdf` has no OpenType shaping engine
([dart_pdf#198](https://github.com/DavBfr/dart_pdf/issues/198)), so Bengali
conjuncts break. The cover is laid out as Flutter widgets, captured through
`RepaintBoundary` at 200 DPI and embedded as a full-page image.

The cost is honest and worth stating: the text in the PDF is **not selectable
or searchable**. The benefit is that Bengali is correct, and that the preview on
screen *is* the output rather than an approximation of it.

---

## What is not finished

Kept current on purpose. A project that claims more than it does is worse than
one that says where it stops.

**Not built**
- Teacher assignments with deadlines and submissions
- Photos and voice messages inside chat
- Scheduled reminders. The setup question records your revision plan and says
  so; it does not promise an alert, because there is none

**Deliberately not built**
- **Push notifications.** Sending one to another person needs either a Cloud
  Function (paid) or the sending key inside the app — and anyone who unpacked
  the APK could then push anything to everyone. Messages arrive live while the
  app is open
- **Photos and PDFs through the cloud beyond 700 KB.** Firebase Storage needs a
  billing account, so attachments travel inside the Firestore document, which is
  capped at 1 MB. The app says before sending which files will not fit
- **Group ownership transfer.** An owner who leaves strands the group, and
  saying so is more honest than a half-built handover

**Not yet verified**
- Groups, sharing and chat have only been run with one account
- Voice recording has never run on Android
- Release signing still uses debug keys

---

## Tests

```bash
flutter analyze
flutter test
```

188 tests, over the models and the pure logic: study ordering, exam countdowns
and DST, cover-page layout, the `.notenest` file format and its refusals,
university search ranking, join codes, chat addressing and read receipts,
semester numbering, and the size budget for sharing.

Every one of them runs without a device, a network or a Firebase project.
