# Activity 10, part 2a — Groups and sending a note inside the app

Gantt Week 8. Builds directly on part 1: the cloud account proved in the
console is what every row below belongs to.

Two of the four features from the plan are here — **study groups** and
**app-to-app note sharing with an Accept step**. Chat and teacher assignments
are part 2b, and both sit on the group this part creates.

## How to install

```powershell
cd C:\project\notenest
# unzip over the project, overwriting
flutter pub get
flutter analyze
flutter test
flutter run -d chrome --web-port=5000
```

**No new packages.** Nothing outside `lib`, `test` and `firestore.rules`
changed: no Gradle edit, no manifest edit.

⚠️ **`lib/firebase_options.dart` is not in this zip and must not be.** It is
generated from your own project and holds your keys. Extracting over the
project leaves it exactly as it is.

## 🛑 Republish the security rules

`firestore.rules` has grown three new collections. Until you publish it, every
one of them is denied by the catch-all at the end of the file, and the app will
say `permission-denied` the moment you make a group.

1. Console → `notenest` → **Build → Firestore Database → Rules**
2. Select everything, delete it
3. Paste the whole new `firestore.rules`
4. **Publish**

## New files (4)

| File | What it is |
|---|---|
| `lib/models/study_group.dart` | The group, the join code, membership arithmetic. No Firebase import — 13 unit tests. |
| `lib/models/note_share.dart` | One sent note, and the size budget that decides whether its files can travel. 9 unit tests. |
| `lib/screens/groups/groups_page.dart` | Your groups; making one; joining with a code. |
| `lib/screens/groups/group_detail.dart` | Members, the code, leaving, deleting. |
| `lib/screens/share/cloud_send_sheet.dart` | Sending a note to a person or a whole group. |

## Changed files (6)

| File | Change |
|---|---|
| `lib/data/cloud_service.dart` | Groups and shares. Still the only file that imports Firebase. |
| `firestore.rules` | `groups`, `joinCodes`, `shares`. Catch-all deny still last. |
| `lib/screens/shared/shared_page.dart` | Waiting shares appear as a band above the inbox you already had. |
| `lib/screens/share/share_note_sheet.dart` | A second button: send inside NoteNest instead of as a file. |
| `lib/data/note_repository.dart` | The Groups drawer link now goes somewhere. |
| `lib/screens/shell/home_shell.dart` | Routes it, and the old "groups need a server" dialog is gone — it is no longer true. |
| `test/widget_test.dart` | 22 more tests — **159 in total**. |

## The decision that shaped the rest: accepting a cloud note *is* importing

`NoteRepository.importBundle` and `NoteBundle.decode` were written in Activity
05 for `.notenest` files. A note sent through the cloud carries the same
`NoteBundle.encode()` JSON as its payload, so accepting one runs exactly that
code: the same subject-matching by code, the same reset to Unread, the same
attribution to whoever wrote it, and — this is the part worth defending — the
same refusals.

`decode` was already hardened because the file came from outside the app. A
note arriving over the network has passed through at least one more machine
than one arriving as a file, so if anything deserved the strict reader, it was
this. Reusing it meant writing no new parser, and no new parser means no second
set of holes.

There is one honest consequence: the Shared inbox has no idea which of its
notes arrived as a file and which arrived through the cloud, because by the
time it sees them there is no difference. That is the point, but it does mean
the inbox cannot show a "sent via NoteNest" badge without storing something it
currently does not.

## Three things worth defending in the viva

**Joining a group never reads the group.** A person holding a code is, by
definition, not yet a member, and the rule says members only. So the code is
looked up in a separate one-line collection that holds a name and an id, and
the join itself is an `arrayUnion` — the client never reads the member list at
all. The rule checks it on the server:

```
request.resource.data.memberUids == resource.data.memberUids.concat([request.auth.uid])
```

Not "contains". **Equals.** The list afterwards must be the list before plus
exactly this one uid, so a joiner cannot bring a friend, cannot drop anybody,
and cannot touch the name in the same write.

**Join codes are made unique by a rule, not by a check.** `joinCodes` allows
`create` and forbids `update`. Firestore applies `create` only when the
document does not exist, so two phones racing for the same code do not both
win: the second is refused and the app tries another. Checking first and then
writing would leave a window between the two; this has none, because the race
is settled where the data is.

**The alphabet a code is drawn from leaves out `O`, `0`, `I` and `1`.** A join
code's whole job is to be read off one screen and typed into another, often
across a room. Those four are the pairs people get wrong. Dropping them costs a
little space and removes the most common reason a correct code is rejected.
There is a test asserting they are absent.

## The limitation to say out loud: attachments

Firebase Storage — where a photo or a PDF properly belongs — needs a billing
account. This project is on the free Spark plan, so a file can only travel
inside the Firestore document itself, and a document is capped at **1 MB**.

So the app budgets **700 KB** of payload and tells you, *before* you press
send, which of the two things will happen:

- the files fit, and travel with the note
- they do not, and the text is sent while the files stay behind — with the
  count and the size named, and a pointer to the file route, which has no such
  limit

The 300 KB left under the cap is deliberate. The payload is not the only thing
in the document, and Firestore counts its own overhead in ways the app cannot
see. A budget that only just fitted in testing would start failing on a long
note with a long title — the worst kind of limit, one that holds until the day
it matters.

The same 700 KB is written into `firestore.rules`, so it holds even against a
client that has been edited.

## Where it stands

**Implemented**
- Make a study group; a teacher account can make a class
- Join by six-character code, with spaces and dashes ignored
- Member list with names, roles and who owns the group
- Leave a group; the owner deletes it instead, and the code is freed in the
  same batch
- Send a note to one person by their exact email address
- Send a note to every member of a group at once, as one batched write
- A waiting band at the top of the Shared inbox, with Accept and No thanks
- Accepting runs the existing importer, so the note lands under the right
  subject with the sender's name on it
- Security rules for all three new collections, with the catch-all deny intact

**Partial**
- Attachments travel only when they fit in 700 KB — see above
- The sender cannot see whether a note was accepted. The document records it;
  no screen reads it yet
- A member list is read one profile at a time and cached. Fine for a study
  group, slow for a class of eighty
- The owner can remove a member in the rules, but no screen offers it yet

**Planned (part 2b)**
- Chat, one to one and in a group
- Teacher assignments with a deadline, and student submissions
- Both hang off the group this part creates

**Not planned**
- Group ownership transfer. An owner who leaves the university strands the
  group, and saying so is more honest than a half-built handover
- Push notification when a note arrives. It needs Cloud Messaging and a server
  key; the inbox updates live while the app is open

## How to check it actually worked

You need two accounts. The second can be any other email — make it in a
private window, or sign out and back in.

1. Account A: **Groups → Make one** → a name → the group opens with a code
2. Console → **Firestore → Data** → a `groups` document with your uid alone in
   `memberUids`, and a `joinCodes` document named with the code itself
3. Account B: **Groups → Join** → type the code → the group appears
4. Console → the same `groups` document now has **two** uids, appended in order
5. Account A: open any note → **Share → Send inside NoteNest** → A group →
   pick it → Send
6. Console → a `shares` document with `state: "pending"` and a long `payload`
7. Account B: **Shared** tab → the note is waiting → **Accept**
8. Account B's notebook has the note, under the right subject, with A's name on
   it — and the `shares` document now reads `state: "accepted"`

If step 3 fails with a permission message, the rules were not republished.
That is the one step that is not in the zip.
