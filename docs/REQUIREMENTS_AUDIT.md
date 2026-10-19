# Requirements audit — 19 Oct 2026

Source: `NoteNest_Claude_Code_Requirements.txt`. That brief assumes a server
stack (Socket.IO, SQL ORM, Redis, cron, email provider). NoteNest is a Flutter
app with local SQLite (`sqflite`) and Firebase (Auth + Firestore, Spark plan,
**no server code, no Cloud Functions**). Items that need a server are listed as
not done rather than faked.

## Done in this pass
| Requirement | Change |
|---|---|
| §10 To-do list | `tasks` table (DB v8, additive migration, nothing dropped), `Task` model, repository CRUD scoped by `user_id`, `TasksPage` (search, status/priority/course filters, sort by due), `TasksCard` on Today for students and teachers, quick add. Overdue is computed, never stored. |
| §3.1 Timestamps | Day headings (Today / Yesterday / date) between messages; 12-hour times (`8:35 PM`). Times come from Firestore server timestamps and are shown in local time. |
| §16 Greeting | Morning < 12:00, afternoon < 17:00, evening < 21:00, night after. |

## Already present (not rebuilt)
Firestore rules enforce thread membership, block checks, own-receipt-only,
email lookup via `emailIndex` (no listing), reports/blocks, account deletion;
auth with Google sign-in, verified email, password-reset email (Firebase);
courses are `subjects` with semesters; exams/calendar with reminders shown on
open; soft-delete Trash.

## Not done — and why
- **Socket.IO, adapters, presence, rate limiting, OTP storage/hashing, push,
  scheduled inactivity jobs, email notifications**: need a backend. Firebase
  Auth already provides throttled login and emailed reset links; real push
  needs FCM + Cloud Functions (Blaze plan) — a decision for the owner.
- **Message-request workflow (§4.2)**: DONE in a later pass — see below.
  open a DM unless blocked. Doing this properly means a `requests` collection
- **Hide a conversation from my list (§3.3)**: needs a per-user hidden set
  (new Firestore field + rule). Not started.
- **In-app notification centre / settings (§9)**: no store exists; depends on
  the same backend decision. Task reminders are shown on Today only.
- **Course cards dashboard, course-aware Today/Notes, course archive,
  course-linked file attachments (§5)**: not started this pass; the data
  model already supports it (`subject_id` on notes, exams, tasks).
- **Cover page footer (§11.3)**: cover generator exists in
  `lib/screens/cover`; footer not added this pass.

## Verification
`flutter analyze`: clean. `flutter test`: 207 pass (7 new). Debug APK build:
see session notes. DB migration v7→v8 was **not** run against a real upgraded
database (no sqflite FFI test harness in the project) — verify on a device
with an existing install. Not tested: UI on a device, Firestore emulator
(rules unchanged).

## Message requests (added later)
`dmRequests/{dm_a_b}`: one document per pair (id = chat address), so
duplicates and simultaneous requests cannot exist. States pending / accepted /
declined. Rules: sender creates as themselves, `pending` only, text 1–500, not
if the recipient blocked them; only the recipient can answer (and can change a
decline to accept later); sender cannot edit, reset, re-send or delete a
declined request; a **new** direct chat can only be created once the request is
`accepted`. Existing conversations keep working (their rule path is update).
App: "Message request" sheet, Message requests page (waiting / sent / declined),
banner on the Chats list; every "message this person" button uses it.
Tests: 31 rules tests pass (6 new), 209 Flutter tests pass.
Limits: group members must also request (no group exemption); a user can still
send requests to many people (no server to rate-limit); the intro text is shown
on the request, not copied into the chat. **Rules must be published by you
before the app version that needs them ships**, otherwise requests fail.

## Final implementation pass (19 Oct 2026)
- Course cards on Today (code, name, note count, open tasks); tap opens Notes
  filtered to that course through the shell's single active-course value.
- Remove a conversation from my list: long-press a person's chat, confirm. Local
  to this device/account; nothing is deleted for anyone; it reappears when a new
  message arrives.
- Notification centre: bell with unread badge on Today; lists waiting message
  requests, unanswered shared notes, overdue/due-today tasks, exam reminders;
  mark all read; per-category switches. Derived from live data, not a second
  store. **In-app only** — no push, no email, no inactivity reminders (need a
  backend/FCM).
- Cover page: small "NoteNest" footer in its own row at the foot of every
  template.
- Not done: per-course file attachments (existing note PDF/image attachments
  unchanged), course soft-delete beyond the existing archive flag, rate limits
  and OTP (Firebase Auth handles login throttling and reset email).
Totals: flutter analyze clean, 212 Flutter tests, 31 rules tests, debug APK builds.

## Course area and to-do polish (DB v9)
- Course page (notes, tasks, files in one place); All courses page with search,
  semester filter, restore of archived courses.
- Course files: PDF/Word/PowerPoint/Excel/text/images, 25 MB cap, extension +
  content-signature check, duplicate refusal, stored in the app folder, deleted
  with the row. PDFs open in-app; others open through the share sheet.
- Tasks: "in progress" state, sort by priority.
- Migration v8→v9 is additive (new table, one new column with a default).
- Not run on a real upgraded database or a phone yet.
Totals: analyze clean, 216 Flutter tests, 31 rules tests, debug APK builds.

## Server work — what is needed
See the chat reply: Firebase Blaze plan + Cloud Functions + FCM + email
provider; list in order of value.
