# Activity 10, part 2b-1 — Chat

Builds on B2a. A conversation's membership is decided by the group, so the
group had to be real before any of this could be.

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

⚠️ `lib/firebase_options.dart` is not in this zip and must not be.

## 🛑 Republish the security rules

`firestore.rules` has a whole new section. Without it, opening a chat gives
`permission-denied` — the catch-all deny at the end of the file is doing its
job.

Console → `notenest` → **Build → Firestore Database → Rules** → select all,
delete, paste the new file, **Publish**.

## New files (3)

| File | What it is |
|---|---|
| `lib/models/chat.dart` | Threads, messages, read receipts, typing. No Firebase import — 21 unit tests. |
| `lib/screens/chat/chats_page.dart` | Every conversation, groups then people. |
| `lib/screens/chat/chat_page.dart` | One conversation: bubbles, note posts, the composer. |

## Changed files (6)

| File | Change |
|---|---|
| `lib/data/cloud_service.dart` | Messages, read receipts, throttled typing, blob loading. |
| `firestore.rules` | `chats`, its `messages` and its `blobs`. Catch-all deny still last. |
| `lib/screens/groups/group_detail.dart` | Tapping a member opens a conversation with them. |
| `lib/screens/share/cloud_send_sheet.dart` | Sending to a group is gone from here — see below. |
| `lib/data/note_repository.dart` | A Chats drawer link. |
| `lib/screens/shell/home_shell.dart` | Routes it. |
| `test/widget_test.dart` | 21 more tests. |

## The correction you asked for

You said a note posted to a group should not need accepting, and you were
right. I had conflated two different things.

**Posting a note to a group** and **putting a note in somebody's notebook** are
not the same act. Posting shows it to people who are already in the room.
Putting it in their notebook creates a subject, writes a note and keeps files
on their device — somebody else writing in your book.

So they are now separate:

| | |
|---|---|
| Post a note in a group chat | Everybody sees it at once. No accepting. |
| **Save to my notes** on that post | Each person decides for themselves. |
| Send to one person by email | Still has Accept, because you share no room. |

Being in the group *is* the permission to see. The tap is only for keeping.

Sending to a whole group has therefore been removed from the one-to-one send
sheet. Two routes to the same thing means people take the wrong one.

## Friends, and why there is no friend list

There is no friend request in NoteNest, and that is the design rather than
something missing. **Being in a group together is the connection.** Open a
group, tap somebody in the member list, and you are talking to them.

This is how Slack and Discord work, and it buys three things: no requests to
send, no requests to accept, and no collection of pending friendships to keep
in step with reality.

There is one way in from outside a group, and it exists because the first
version did not have it and that was a hole: somebody could send you a note out
of the blue and you had no way to answer them. So **Chats → Message someone**
takes an exact email address, the same lookup sending a note uses. The same
button sits on a waiting note in the Shared inbox, next to the sender's name.

Being honest about what that costs: anybody who knows your address can now
start a conversation with you, not only send you a note. That is the same
surface sharing already had — an exact address, no browsing, no directory — so
it opens nothing that was closed. It is not the same as "nobody outside your
groups can reach you", which is what this document said before, and that
sentence was wrong.

## Four things worth defending in the viva

**Both people compute the same address, so there is no "start a conversation".**
A direct thread lives at `dm_<a>_<b>` with the two uids sorted. Whoever opens
it first, both ends compute the same string and land in the same place. Without
that, two people could end up in two separate threads that each only one of
them could see — and the bug would look like "my messages are not arriving".

The sort is also what makes it checkable. The rule rebuilds the address from
the members in the document and refuses anything that does not match:

```
chatId == 'dm_' + incoming().memberUids[0] + '_' + incoming().memberUids[1]
```

**The rules read the address, not the document, and that is because of
batching.** A batched write is checked against the state *before* the batch.
The first message in a new group thread arrives in the same batch as the thread
document it would depend on — so a rule that had to read that document would
refuse the very first message anybody ever sent. Reading `grp_` off the front
of the id needs nothing that is not already in the request.

**A typing flag is never cleared; it expires.** The writer sets a timestamp and
the reader ignores anything older than six seconds. A phone that loses signal
mid-word never gets to clear its flag, and the alternative design leaves
"typing…" on everybody's screen for good. Expiry by age needs nothing from the
writer, which is the point.

**A typing flag is written at most once every three seconds.** Not a polish
detail: every one of those is a document write and the free Firestore allowance
is twenty thousand a day. On each keystroke, one conversation would spend an
afternoon's worth. There is a constant for it with the arithmetic written down
beside it.

Alongside that, two rules worth pointing at:

```
request.resource.data.readAt.diff(resource.data.get('readAt', {}))
  .affectedKeys().hasOnly([request.auth.uid])
```

You may only ever stamp *your own* read receipt, and only your own typing flag.
Without it one member could mark a conversation read for everybody, or leave
somebody else showing as typing permanently.

And a posted note's payload lives in a `blobs` subcollection rather than in the
message. A note can run to several hundred kilobytes; in the message, scrolling
back through a term's conversation would download every note anybody ever
posted, for a reader who may want none of them. The message carries the title,
the subject and the file count — enough to decide — and the weight is fetched
by whoever presses Save.

## Where it stands

**Implemented**
- A conversation for every group, there from the moment the group exists
- One-to-one conversations, started from a group's member list, from a waiting
  note in the Shared inbox, or by email from **Chats → Message someone**
- Text messages, newest at the bottom, capped at the last 120
- Posting a note into a conversation, visible to everyone with no Accept
- **Save to my notes** on each posted note, which runs the same importer as a
  `.notenest` file — right subject, author's name kept
- A note already in your notebook shows "In your notes" instead, and that
  survives closing the app because it is read off the notes themselves
- Read receipts: a thread is bold until you open it, and your own message
  never makes it bold
- Typing, throttled and self-expiring
- Security rules for threads, messages and payloads

**Partial**
- Files travel with a posted note only when the whole thing fits in 700 KB.
  Over that, the text posts and a line says what was left behind
- "Save to my notes" matches on title and sender. Two different notes with the
  same title from the same person would look like one
- The conversation list shows groups and people in two sections rather than one
  list in time order. Merging them would mean waiting on every group's
  document before anything could be drawn
- Only the last 120 messages load. There is no "load older"

**Planned**
- B2b-2: photos and voice messages, both squeezed under the same 700 KB
- B2c: teacher assignments with a deadline, and student submissions

**Not planned, and why**
- **Push notifications.** Sending one to another person needs either a Cloud
  Function (billing) or the sending key inside the app — and anyone who
  unpacked the APK could then send anything to everyone. Messages arrive live
  while the app is open; closed, they wait.
- **Delete or edit a message.** Editing would let the words above somebody's
  reply change after they replied to them. The rules refuse both.

## How to check it worked

Two accounts again. Second one in a private window.

1. Both accounts in the same group (B2a's steps)
2. A: **Chats** → the group → type something → Send
3. B: **Chats** → the group is **bold** with a dot → open it → the message is
   there, and the bold is gone
4. Console → **Firestore → Data** → `chats` → `grp_<groupId>` → a `messages`
   subcollection, and a `readAt` map with both uids
5. A: in the conversation, tap the note icon → pick a note → post it
6. B: sees it immediately, **with no Accept** → **Save to my notes** → it is in
   B's notebook under the right subject with A's name on it
7. B: open the group → **Members** → tap A → a conversation with A alone
8. Console → `chats` → a document named `dm_<uid>_<uid>`, the two uids in
   alphabetical order

If step 2 fails with a permission message, the rules were not republished.
