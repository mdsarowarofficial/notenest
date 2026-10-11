# Activity 07 — Sharing & Collaboration

Gantt Week 6–7 (9 days). Gantt deliverables: sharing, permissions, study
groups, note requests, Shared Note Inbox.

## How to install

```powershell
cd C:\project\notenest
# unzip over the project, overwriting
flutter pub get      # pubspec.yaml changed — one new package
flutter analyze
flutter test
flutter run -d chrome
```

`pubspec.yaml` adds **`share_plus: ^13.3.1`**. Nothing else outside `lib`
changed — no Android manifest edit this time.

## The decision this activity turns on

Real sharing between two phones needs a server, and NoteNest has none until
Activity 09. Rather than build screens that pretend, sharing is done the way
students already share everything else: **a file sent through an app they
already have.**

Export a note → it goes into the Android share sheet → WhatsApp, Messenger,
email, Bluetooth, anything → the classmate saves the file → Import in NoteNest
→ it lands in their notebook with the sender's name still on it.

That is not a stand-in for the real thing. It genuinely works today, offline,
with no account and no API key, and it covers four of the five Gantt items.

## New files (6)

| File | What it is |
|---|---|
| `lib/models/note_bundle.dart` | The exchange format: a note packed into one JSON file, attachments and all. Pure Dart, unit-tested. |
| `lib/data/share_service.dart` | The file and the operating system — writes the bundle into the share sheet, reads one back from the file picker. |
| `lib/screens/share/share_note_sheet.dart` | What leaves the phone: subject, files, size, and what the sender is asking for. |
| `lib/screens/share/import_page.dart` | Shows the whole note before anything is written. |
| `lib/screens/share/request_note_sheet.dart` | Writes a note request and hands it to the share sheet. |
| `ACTIVITY_07.md` | This file. |

## Changed files (9)

| File | Change |
|---|---|
| `lib/data/app_database.dart` | Schema v5: `shared_by`, `shared_at`, `share_policy` on `notes`, plus an index for the inbox. |
| `lib/models/note.dart` | Those three fields, `isShared`, and the `SharePolicy` enum. |
| `lib/data/note_repository.dart` | `packForSharing`, `importBundle`, `inboxNotes`, `sharers`. |
| `lib/data/attachment_store_io.dart` + `_web.dart` | `readBytes`, so a photo can travel inside a shared note. |
| `lib/screens/shared/shared_page.dart` | The Shared tab is now the inbox, grouped by sender. |
| `lib/screens/notes/note_detail.dart` | A Share button, and a banner naming who a borrowed note came from. |
| `lib/screens/shell/home_shell.dart` | The three drawer links do something now. |
| `pubspec.yaml` | `share_plus`. |
| `test/widget_test.dart` | 16 more tests over the bundle format (51 in total). |

## Three things worth defending in the viva

**No database ids travel.** The sender's `subject_id` 4 is somebody else's
subject 4, or nobody's. The subject goes by name and code instead, and on
import it is matched against the receiver's own subjects by code — so a
classmate's CSE112 lands in *your* CSE112 rather than creating a second one.
Only if there is no match is a subject created.

**Everything arriving is untrusted.** The file came off another student's phone
and may have been edited, truncated, or produced by something that is not
NoteNest at all. `NoteBundle.decode` checks the format name, the version, the
sizes and every field, and refuses the file with a readable reason rather than
letting bad data into the database. The attachment name gets specific
attention: it is reduced to its last path segment, so a name like
`../../../etc/passwd` arrives as `passwd`, and the extension is stripped to
plain letters and digits. There are tests for exactly these.

**A permission that cannot be enforced is labelled as a request.** The sender
chooses "free to edit and pass on" or "please keep as reference", and it
travels with the note and shows on the receiver's copy. The share screen says
in as many words that NoteNest cannot enforce it — once the file is sent, the
copy belongs to whoever has it. A label that looks like a lock but is not one
is worse than no label.

## Study groups are not built, and the app says so

Sending one note works without a server because the file travels through an app
the student already has. A group does not: it has to live somewhere both phones
can reach, so that everyone sees the same members and the same notes. There is
nowhere to put it until cloud sync exists.

So the drawer's **Study groups** link opens a short explanation of exactly that,
with a button through to Note requests, instead of a dead screen or a "coming
soon" toast. This is the one Gantt item of the five that is genuinely deferred,
and it is deferred to Activity 09 where it belongs.

## A correction carried over from Activity 06

The dictation screen used to say the words were recognised on the device "so
nothing is sent anywhere". That was wrong, and it has been reworded.

The recogniser does belong to the device, but on Android and in the browser it
normally passes the audio on to the platform's speech service — Google's, in
practice. Only an installed **offline language pack** keeps it local, and
Bengali packs are not on every phone. Recording is unaffected: that writes a
file and touches no network.

It is worth stating in the report as a privacy limitation rather than leaving
it implied. An app that handles a student's lecture audio should say where that
audio goes, and "the recogniser is on the device" is not the same claim as "the
audio stays on the device".

## Known limitations

- **The receiver has to find the file.** NoteNest does not register itself as a
  handler for `.notenest` files, so a note cannot be opened straight from
  WhatsApp — it is saved, then picked through Import. Registering an Android
  intent filter would remove that step and is a small, well-understood change.
- **Sharing is one note at a time.** No "share this whole subject" yet.
- **Nothing is synced.** Two copies of a note drift apart the moment either
  side edits. There is no merge, because there is nothing to merge through.
- **Attachments do not travel from the browser build.** Chrome has no file
  storage for them, so a note shared from Chrome carries only its text. The
  share screen shows a file count of zero there, which is accurate.
- **A large note makes a large file.** A note with several photographed pages
  can run to several megabytes, so the share screen shows the size before
  sending and lets the student send the text alone.
