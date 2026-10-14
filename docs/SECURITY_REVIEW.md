# NoteNest — security review

Written against commit `dcfe428` plus this audit's changes. Where a conclusion
rests on reading rather than on running something, it says so.

## The shape of the problem

There is **no server code**. The project is on Firebase's free Spark plan, which
has no Cloud Functions, so there is no trusted middle layer between the app and
the database. `firestore.rules` is not a second line of defence behind a
backend — it *is* the defence.

Everything else follows from that. The app is a client, a client can be
replaced, and a replaced client can send any request a signed-in account is
permitted to send. Every claim below about what an attacker cannot do is a
claim about the rules file, never about the app's screens.

## Threat model

| Actor | What they have | What they want |
|---|---|---|
| Unauthenticated stranger | the public app | anything at all |
| Any registered student | a real account, and a replaced client | other students' notes; the user directory |
| A group member | legitimate access to one group | the rest of the group's private data; to break the group |
| Someone holding the phone | an unlocked device | the local database; the signed-in session |
| Someone holding a backup | the device database file, offline | the password hashes |

The actor that matters most is the second: a classmate who registers normally
and then talks to Firestore directly. Everything they can do is defined entirely
by the rules file.

## Authentication

Two identity systems, deliberately:

* **Device account** — row in local `users`, password hashed on the phone. Works
  with no network. This is what owns every note.
* **Cloud account** — Firebase Authentication. Only needed for sharing, groups
  and chat.

They were two separate accounts earlier in the project's life, which confused
everyone including me; they are now unified, with `adoptCloudAccount` binding an
existing device account to a cloud sign-in and `rekeyPassword` bringing the
device password back in line after an email reset.

**`rekeyPassword` has no current-password check, on purpose.** Someone who has
just reset by email does not know the old password and cannot be asked for it.
What makes it safe is not a check inside the method but the single place it is
called from: Firebase has already verified the person against the one copy of
the truth that does not live on this phone. If a second caller is ever added,
this reasoning must be re-made rather than assumed.

### Passwords

Fixed in this audit (NN-02). Was one round of salted SHA-256; is now
PBKDF2-HMAC-SHA256 at 120,000 rounds, stored as `pbkdf2$<rounds>$<base64url>`.

* The algorithm was **verified** against Python's `hashlib.pbkdf2_hmac` over six
  vectors including Bengali text and an empty password. All matched.
* Old hashes are detected by the missing prefix, verified with the legacy
  function, and rewritten in the new form at the next successful sign in.
* Comparison is constant-time.
* The cost travels with each hash, so it can be raised later without locking
  anyone out.

Not Argon2id. Argon2 needs a package this project does not have, and adding a
cryptography dependency during a pre-release audit is a bigger risk than the
difference between a well-configured PBKDF2 and Argon2id for a local-device
threat model. PBKDF2-HMAC-SHA256 is NIST SP 800-132. No custom cryptography was
written: HMAC comes from the `crypto` package and the construction is standard.

### What is not protected

* **The local database is not encrypted.** Someone with the unlocked phone can
  read every note by reading the SQLite file. Making this better means a
  passphrase-derived key for the database (SQLCipher) and losing offline
  recovery when the passphrase is forgotten. Not done, and not claimed.
* **There is no end-to-end encryption anywhere.** Shared notes and chat messages
  are plaintext in Firestore, readable by anyone with project console access —
  which today means the project owner. The app must not claim otherwise.

## Authorization

### Firestore, collection by collection

Each entry says what an attacker can still do, not only what they cannot.

**`/users/{uid}`** — `get` by uid for any signed-in account. Needed so a shared
note can show who sent it. uids are random, so this is not enumerable in
practice. `list` is now **closed** (NN-01); it previously permitted paging
through the whole directory. Update is limited to name, institution and role,
with uid and email pinned to their stored values. Delete is self-only, added for
account deletion.

**`/emailIndex/{address}`** — new. The folded address is the document name, so a
lookup is a `get`. `list` is closed. A write is only permitted when the document
name equals the address on the caller's own token **and that token says the
address is verified**, so nobody can point someone else's address at their uid
and collect their shared notes.
*Still possible:* one guess at a time tells a caller whether an address is
registered. They get a uid and no name. That is the price of a lookup that is
not a query, and it is a far smaller surface than the directory it replaced.

**`/groups/{groupId}`** — members only, read and write. Firestore refuses a
query it cannot prove stays inside the rule, so the app's `array-contains` on
`memberUids` is what makes the read legal at all, not merely how the right rows
are found. Joining is pinned to "the list before, plus exactly my uid", now with
a not-already-a-member check and a 60-member ceiling (NN-06). Leaving is the
mirror. Only the owner may rename or remove people — remove, never add — and the
join code and `kind` cannot be changed by anyone.

**`/joinCodes/{code}`** — `get` only; `list` is closed, because a listable code
table is the opposite of a join code. `update` is `false`, and that single line
is what makes codes unique: Firestore applies `create` only when the document
does not exist, so two clients racing for one code do not both win. No
read-then-write, no window.

**`/shares/{shareId}`** — readable by the two ends only. The sender uid is taken
from the token, so a note cannot arrive wearing a classmate's name. Only the
recipient may answer, and answering is the only permitted update, so a sender
cannot swap the payload after it was accepted. Deletion is now allowed for
either party, answered or not (NN-08, widened October 2026 so a sender can
withdraw a note and a deleted account can take its shares with it).

**`/chats/{chatId}`** — the thread kind is read from the id (`grp_…`, `dm_…`)
rather than from a field. That is not cleverness for its own sake: a batched
write is evaluated against the state *before* the batch, so a rule that had to
read the conversation document would refuse the very first message in a new
thread. Read receipts and typing flags are each pinned to the caller's own key,
so nobody can mark a thread read for everyone or leave someone else typing
forever. A direct thread's member list is frozen after creation and its address
must be the one those two uids compute. `kind` and `groupId` are no longer
changeable (NN-07).

**`/chats/{id}/messages`** and **`/blobs`** — sender pinned to the token; no
update and no delete, so the words above somebody's reply cannot change after
they replied to them. Length caps on every string.

**Everything else** — `match /{document=**} { allow read, write: if false; }`
last, so a collection added later is shut until someone opens it deliberately.

### Local database

Fixed in this audit (NN-09): all ten id-only mutations now carry
`AND user_id = ?`, and attachments are scoped through their note. No
cross-account write was reachable before the change; the fix moves the guarantee
from the callers into the statements.

## Known residual risks

Listed because an audit that reports only what it fixed is an advertisement.

1. **Storage exhaustion by a determined client.** Rules can cap the size of one
   document; they cannot cap how many. Someone could write shares, messages and
   blobs until the project's 1 GiB is gone, after which nobody can send
   anything. Cloud Functions could clean up, and Cloud Functions need Blaze.
   What is available on Spark: **Firebase App Check**, which makes it much
   harder to talk to the project from anything other than the real app, and a
   budget/usage alert so the owner finds out. Neither is turned on today.
2. **Enumeration by address, one guess at a time** (`/emailIndex`). Accepted,
   described above.
3. **A self-assigned `role` field** (NN-11). Harmless today; a privilege
   escalation the moment any rule trusts it.
4. **No encryption at rest, and no end-to-end encryption.** Stated above.
5. **The project owner can read everything** in the Firebase console. Normal for
   this architecture, and it belongs in the privacy policy rather than in a fix.
6. **Rules tests cover the main paths, not every path.** Fifteen emulator
   tests in `firestore-tests/` (October 2026) pair each real app write with the
   nearest forged one. Against the rules before that hardening, twelve failed.
   Anything not in those fifteen is still known only by reading.
7. **Joining needs the group id, not the code.** The join rule cannot see which
   code a person typed, so anyone who has learned a group's id — a former
   member, say — can add themselves back. Harmless while the app has no way to
   remove a member; it must be solved (a join request the owner approves, or a
   per-join proof document) before one is added.
8. **Anyone can open a direct conversation with any uid they have seen.**
   Without blocking (Play blocker B-3) there is no way to refuse one.

## October 2026 hardening

Found in a second audit and fixed in the app and the rules. The rules changes
are in `firestore.rules` and take effect only when deployed.

- **Device and cloud sessions were not tied together.** Signing out of the app
  left Firebase signed in, so the next person to sign in on the phone inherited
  the previous account's groups, inbox and chat. Sign-out now ends both;
  a cloud session on a different address from the device account is refused
  or dropped at startup.
- **Unverified addresses could be claimed.** `/emailIndex` writes now require
  `email_verified`, and password accounts are sent a confirmation link.
  Entries claimed before this by unverified accounts remain until removed in
  the console.
- **Owners could add people to groups.** The owner may now only remove members.
- **Join codes could point at any group.** A code's creator must own the group,
  checked with `getAfter` because the two are written in one batch.
- **Size limits could be bypassed with extra fields.** Every create now lists
  the fields it accepts (`keys().hasOnly`).
- **`system` messages and a forged "last message from"** are refused.
- **Pending shares could not be withdrawn,** including by an account being
  deleted. Either end may now delete a share; account deletion removes the
  account's shares and groups.

## Recommended next, in order

1. Run the BLOCKED checks. Reasoning is not verification.
2. Turn on **App Check** (Play Integrity). Free, and it is the single biggest
   reduction in what a replaced client can do.
3. Set a **Firestore usage alert** so storage exhaustion is noticed on the day.
4. Build reporting and blocking for chat before any public release — a Play
   requirement, and the only defence a student currently has against harassment
   is leaving the group.
5. Run `firestore-tests/` (`npm install && npm test`) before every rules
   deploy, and add a test with every rules change. It pins firebase-tools 13
   because that is the last line that runs on Java 17; on Java 21 it can move
   to the current release.
