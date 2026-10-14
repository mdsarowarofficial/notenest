# NoteNest — handling reports

Students report a message, a conversation or a shared note from inside the app.
Each report is one document in Firestore at `reports/{id}`. Nobody can read
reports from the app; you read them in the Firebase console. Google Play
expects reported content to be reviewed and acted on, so check regularly —
daily while the app is new.

## Reading reports

Firebase console → **Firestore Database → Data → `reports`**.

| Field | Meaning |
|---|---|
| `reporterUid` | who reported (never shown to the reported person) |
| `targetUid` | who was reported |
| `reason` | `harassment`, `inappropriate`, `spam` or `other` |
| `details` | what the reporter typed, if anything |
| `messageText` | a copy of the reported text, taken when the report was made |
| `chatId`, `messageId` | where the message is: `chats/{chatId}/messages/{messageId}` |
| `shareId` | the shared note, if the report was about one (it may already be gone) |
| `createdAt` | milliseconds since 1970 |

To see who someone is, open `users/{targetUid}`.

## Acting on a report

Choose the smallest step that fixes the problem.

1. **Nothing wrong** — delete the report document.
2. **One bad message** — delete it in the console at
   `chats/{chatId}/messages/{messageId}`. The app cannot delete messages; the
   console can, because it bypasses the rules.
3. **Repeated or serious abuse** — Firebase console → **Authentication →
   Users** → find `targetUid` → **Disable account**. A disabled account cannot
   sign in. Delete their bad messages as in step 2.
4. **Illegal content** (threats, sexual content involving minors, etc.) —
   disable the account at once, keep the report, and report it to the
   authorities where required. Do not delete the evidence until you know you
   no longer need it.

Then delete the report, or keep it for your own record of repeat offenders.

## What the student already did for themselves

When reporting, the student is offered "Also block", on by default. Blocking
hides the person's messages and shared notes from them and, in private
conversations, the rules stop the blocked person sending anything at all. So
a report is not the student's only protection — but it is the only one that
protects everybody else.
