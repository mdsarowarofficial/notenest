# NoteNest — privacy and data inventory

What the app actually collects, where it goes, and what happens to it. Built by
reading the code and the manifest, not from a template. The Play Data Safety
form should be filled in from this file, and nothing in it should be claimed
unless it is here.

## Permissions the app asks for

From `android/app/src/main/AndroidManifest.xml` — the complete list:

| Permission | Why it is there | Optional |
|---|---|---|
| `INTERNET` | the cloud account, sharing, chat; also the device speech recogniser, which sends audio to Google unless an offline language pack is installed | no |
| `RECORD_AUDIO` | voice notes and dictation | the phone is asked at first use; `uses-feature required="false"` means a device with no microphone can still install |

Nothing else. No location, no contacts, no storage-wide access, no phone state.

## Data that stays on the device

Held in SQLite (`notenest.db`) and in the app's private files directory.
**Never uploaded unless the student deliberately shares a note.**

| What | Where | Notes |
|---|---|---|
| Name, email address, institution | `users` | the device account |
| Password | `users` | PBKDF2-HMAC-SHA256, 120,000 rounds, per-row salt. Never stored or transmitted in the clear |
| Notes: title, body, tags, topic, status | `notes` | the substance of the app |
| Subjects, exams, reminders | `subjects`, `exams` | |
| Attachments: photos, PDFs, voice recordings | `attachments` + files on disk | files are in the app's private directory |
| Settings, semester, cover-page draft, recent searches | `user_settings`, `app_settings` | |

The database is **not encrypted**. Anyone with the unlocked phone can read it.

## Data sent to Firebase

Only when the student creates a cloud account. The app works without one.

| Collection | Fields | Who can read it |
|---|---|---|
| `users/{uid}` | uid, name, email, role, institution, timestamps | any signed-in NoteNest user who knows the uid |
| `emailIndex/{address}` | uid | any signed-in user who types that exact address |
| `groups/{id}` | name, subject, kind, owner, member uids, join code | members of that group |
| `joinCodes/{code}` | group id, name, owner | any signed-in user holding the code |
| `shares/{id}` | sender, recipient, title, message, group name, **the whole note as a payload** (up to 700 KB) | the two people only |
| `chats/{id}` | last message text, sender name, read receipts, typing flags, member uids | participants |
| `chats/{id}/messages` | text, sender uid and name, kind, thumbnail | participants |
| `chats/{id}/blobs` | a posted note's payload | participants |

**The email address is taken from the Firebase token, not from what the client
typed**, so nobody can register under someone else's address.

### Who else can see it

* **Google**, as the operator of Firebase.
* **The project owner**, through the Firebase console. Every note shared, every
  message sent, is readable there. This is inherent to the architecture and
  must be in the privacy policy.
* **Nobody else.** There is no analytics SDK, no advertising SDK, no crash
  reporter and no third-party tracker — verified against `pubspec.yaml`, where
  the only network dependencies are `firebase_core`, `firebase_auth` and
  `cloud_firestore`.

### Data sent to Google outside Firebase

Dictation uses `speech_to_text`, which hands audio to the **device's own**
recognition service. On most Android phones that is Google's, and it is sent to
Google's servers unless an offline language pack is installed. This is the
platform's behaviour, not something NoteNest chooses, and it must be disclosed.

## Retention and deletion

| Item | On account deletion |
|---|---|
| Everything local — notes, subjects, exams, attachments, settings | **deleted** (cascade from the `users` row; attachment files deleted separately) |
| `users/{uid}` | **deleted** |
| `emailIndex/{address}` | **deleted**, so the address can be registered again |
| Firebase Authentication user | **deleted** |
| Messages already sent | **kept**, in the recipients' threads, under the name they were sent with |
| Notes already shared and accepted | **kept**, in the recipients' notebooks |
| Group membership | the uid stays in the group's member list; the app shows a former member |

The last three are disclosed in the deletion dialog before the student confirms,
and they must be disclosed in the Data Safety form too. The reason is honest and
should be given honestly: deleting them would mean reaching into other people's
data, and on the Spark plan there is no server-side job that could do it safely.

## Data Safety form — the answers this evidence supports

| Question | Answer |
|---|---|
| Does the app collect or share user data? | **Yes** |
| Is data encrypted in transit? | **Yes** — Firebase is HTTPS throughout |
| Is data encrypted at rest? | **No** on the device; at rest in Google's infrastructure for Firebase |
| Can users request deletion? | **Yes, from inside the app**: Profile → Delete account |
| Personal info — name | collected, not shared, **required**, for account function |
| Personal info — email | collected, not shared, **required**, for account function |
| Personal info — user IDs | collected, not shared, required |
| Photos | collected only if attached; **stays on the device** unless a note is shared |
| Audio | collected only if recorded; same |
| Files and documents | collected only if attached; same |
| Messages — in-app | collected, **shared with the people in the conversation** |
| Location, contacts, financial, health | **none** |
| Third-party advertising or analytics | **none** |
| Data used for tracking | **no** |

## Privacy policy — still to be written and hosted

**This is a release blocker.** Play requires a reachable URL. It can be a GitHub
Pages page, which is free. The policy must state, at minimum:

1. Who runs the app and how to reach them.
2. That a name, an email address and whatever the student writes are collected.
3. That notes stay on the phone unless the student shares one.
4. That Firebase (Google) processes the cloud data, with a link to Google's
   policy.
5. That the project owner can read shared content through the console.
6. That dictation may send audio to the device's recognition service.
7. How to delete the account, and precisely what survives it.
8. That the app is not aimed at children under 13.

Point 5 is the one most likely to be left out and the one least honest to omit.
