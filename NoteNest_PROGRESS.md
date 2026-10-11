# NoteNest — project handover

Give this file **together with a zip of the repo** and the whole project can be
picked up from a cold start. The zip is the truth about the code; this file is
everything the code cannot say.

Last updated: 11 October 2026, after Activity 06.

---

## 1. The project

- **NoteNest** — a Flutter academic note-management app, final-year university
  project. Owner: Md. Sarowar Hossain ("Zakaria"), GitHub `mdsarowarhossain`.
- Repo lives at `C:\project\notenest` on Windows, pushed to GitHub.
- Planned against an **8-week / 56-day Gantt chart** with 11 activities
  (`NoteNest_8_Week_Gantt_Chart_with_Days.docx`). Section 5 below tracks it.

## 2. How to work with me on this — read this first

These are the owner's standing rules. Breaking them wastes a session.

1. **Never ask him to hand-edit code.** His words: *"ami code a hatt dite
   chacchi na kothay prb hole amk file dibe new kore ami replace kore dibo."*
   Ship **complete replacement files**, or a zip. Never a diff, never "add this
   line at line 47".
2. **One activity at a time, in Gantt order.** He works through the plan in
   sequence and wants each activity finished and verified before the next.
3. **Reply in Bengali** (he writes Banglish). Code, file names and commands in
   English.
4. **No dummy data, ever.** His words: *"kono dummy kisu rakhbe na"* — only
   genuinely implemented features ship. Every document and slide must keep an
   honest Implemented / Partial / Planned split.
5. **He verifies by running `flutter analyze` and `flutter test`** and pasting
   the output. Always ask for it after shipping. That loop has caught real bugs
   (see section 7).

## 3. Architecture — the decisions already made

Do not re-litigate these without a reason; they are load-bearing.

- **Local database: `sqflite`** (he chose it explicitly over Isar). Web uses
  `sqflite_common_ffi_web`.
- **Repository pattern, no state-management package.** No Provider, Riverpod or
  Bloc. `AuthRepository` and `NoteRepository` are singletons extending
  `ChangeNotifier`; screens read them through `ListenableBuilder`. Screens never
  touch SQL.
- **Versioned schema with real migrations** in `lib/data/app_database.dart`.
  Currently **v4**. One `if (from < n)` step per version, never a wipe. Note the
  v4 step is guarded with `from >= 3` because `_createAttachments` already
  creates the new column for installs coming from v2.
- **Soft delete** (`deleted_at`) for notes, with a Trash screen.
  `ON DELETE CASCADE` users→subjects→notes→attachments;
  `ON DELETE SET NULL` subjects→notes.
- **Attachments store the file name only**, never an absolute path — the app's
  documents directory changes between installs. Files are copied into the app's
  own `attachments` folder. The web build has a stub that reports attachments as
  unsupported rather than failing to compile (`attachment_store.dart` does a
  conditional export).
- **Subject colour is a palette index** (`color_index`), not an RGB value.
- **Passwords**: random 16-byte salt + SHA-256 of `'$salt::$password'`. This is
  documented as a limitation — bcrypt/Argon2 would be correct for production and
  the report says so.
- **All artwork is `CustomPainter`.** There are no image assets in the project.

### Design language — "Ballpoint & Highlighter"

Tokens live in `lib/theme/nest_theme.dart`.

| Role | Value |
|---|---|
| pen (primary) | `#243E8C` |
| penDeep | `#16295F` |
| highlight | `#FFE45E` |
| redPen (important/destructive) | `#D62839` |
| mint (done/synced) | `#1F8A6B` |
| paper / paperDeep | `#EDEFF3` / `#E1E6EE` |
| ink / inkSoft / inkFaint | `#151A24` / `#5B667A` / `#98A2B3` |
| rule | `#DCE1E9` |
| subject tabs | `FFE45E, FF9BB3, 7ED9A6, 7EC4F2, B9A6F2, FFB067` |

Use `NestColor.o(color, opacity)` rather than `withOpacity` (deprecated).
Uppercase micro-labels use the `nestEyebrow` text style.

## 4. Environment facts

- Flutter 3.47.x, Dart 3.13. Android SDK 36, Gradle 9.3.1.
- Emulator AVD is named **`Pixel_Flutter`** (API 36).
- **`adb` is not on PATH.** Session-only fix:
  `$env:Path += ";$env:LOCALAPPDATA\Android\Sdk\platform-tools"`
- **The emulator often does not appear in `flutter devices`.** Fix order:
  `adb kill-server` → `adb start-server` → relaunch the emulator from Android
  Studio's Device Manager (more reliable than the CLI) → `flutter devices`.
- **Windows Smart App Control** has blocked Android CLI tools before
  (`os error 4551`). Suspect it if a tool runs but reaches nothing.
- For recording to capture sound, the emulator needs
  **Extended controls → Microphone → "Virtual microphone uses host audio input"**.
- Chrome is the fast path for everything except attachments and recording.

## 5. Gantt progress — 46 of 56 days

| # | Activity | Days | Status |
|---|---|---|---|
| 01 | Requirements & Research | 6 | ✅ Done |
| 02 | System & UX Design | 10 | ✅ Done |
| 03 | Core Flutter Foundation | 12 | ✅ Done — auth, profile, subjects, local DB |
| 04 | Note Management | 12 | ✅ Done — text notes, CRUD, camera capture, PDF |
| 05 | Search & Study Workflow | 8 | ✅ Done — search, filters, sort, tags, status |
| 06 | Voice & Smart Notes | 10 | ✅ Code complete — **not yet run on a device** |
| 07 | Sharing & Collaboration | 9 | ⬜ Next |
| 08 | Exam & Productivity | 7 | ⬜ |
| 09 | Cloud, Offline & Security | 8 | 🟡 Partial — offline and account security done, no cloud |
| 10 | Integration & Testing | 9 | 🟡 Partial — 34 unit/widget tests exist |
| 11 | Deployment & Finalization | 4 | ⬜ |

### What is genuinely built

Auth with validation and session restore · profile and semester setup · subjects
with colour tabs · text notes with 2-second autosave · photo capture with
cropping · PDF attach and view · image viewer · Trash with restore and
permanent delete · full-text search across title/body/topic/tags · filters by
subject, type, status, important and tag · four sort orders · tags with
normalization and suggestions · recent-search history · lecture recording with
a live level meter · playback with seek · live dictation with auto-restart ·
rule-based transcript structuring.

### Deliberately not built (say so honestly)

Cloud sync · sharing, study groups, note requests (the drawer links exist and
say "not built yet") · Exam Mode countdown (the screen exists, dates are not
stored) · voice-note search (audio is not transcribed after the fact).

## 6. Activity 06 — the parts worth remembering

Three packages were added: `record ^7.1.2`, `audioplayers ^6.8.1`,
`speech_to_text ^7.5.0`. The Dart floor in `pubspec.yaml` was raised from 3.0.0
to 3.6.0 — left lower, pub silently resolves them to old versions with a
different API.

`android/app/src/main/AndroidManifest.xml` gained `RECORD_AUDIO`, `INTERNET`,
an optional-microphone `uses-feature`, and — easy to miss — a `<queries>` entry
for `android.speech.RecognitionService`. Without that last one, Android 11+
hides the recogniser from the app entirely and dictation reports that none
exists on a phone that plainly has one.

**Recording and dictation are separate choices, not two steps.** The Android
recogniser reads only the live microphone, cannot transcribe a saved file, and
both want the microphone at once. So the student picks before the lecture. This
is the question most likely to come up in the viva.

**The recogniser is restarted deliberately.** Android ends a session after about
five seconds of silence with no way to change it. `lib/data/dictation.dart`
treats each session as a piece of a longer dictation and restarts it, keeping
the text. The screen shows a restart counter, because a word spoken during a
handover is lost and a counter is more honest than silence.

**Structuring is rules, not AI.** `lib/models/transcript.dart` holds cue lists
(`important`, `remember`, `for the exam` → Key points; `first`, `next`,
`finally` → bullets). Nothing leaves the device. The limit is real and stated:
a sentence with no cue gets no key point.

## 7. Bugs already found and fixed — do not reintroduce

- **Negative blur radius crash** in `nest_nav_bar.dart`: `Curves.easeOutBack`
  overshoots below zero, and an appearing `boxShadow` interpolated to a negative
  blur. Fixed by keeping the shadow always present and animating only its alpha.
- **`FilePicker.platform` undefined**: file_picker 13 removed it. The call is
  `FilePicker.pickFile(...)`.
- **Spiral rings read as loading spinners** in the drawer. Redrawn as a diagonal
  wire crossing the strip. He was told plainly the ornament has no function and
  offered its removal; he said leave it for now.
- **The editor could undo an attachment.** `note_editor` held the note copy it
  opened with; attaching a photo, PDF or recording changes the note's `type`
  behind its back, and the next autosave wrote the stale copy back. It now
  re-reads the row before saving over it.
- **Dictating into an open note could lose the transcript** — same stale-copy
  cause. The editor reloads when the transcript editor reports it saved.
- **Bottom-sheet and record-screen overflow on short screens.** The capture
  sheet is now `isScrollControlled` with its own scroll view; the record screen
  centres when there is room and scrolls when there is not. `Spacer()` in a
  fixed `Column` was the cause.
- **A stale widget test.** The stepper test assumed each step title appears
  once; the current step's title is drawn twice (rail + heading). The test was
  wrong, not the widget. A second test with `showHeader: false` now pins down
  that the duplicate comes from the heading.

## 8. Open items — start here next session

1. **Run Activity 06 on a device.** Nothing in it has been exercised yet.
   - `flutter analyze` and `flutter test` output after the last three file
     replacements (`dictation.dart`, `capture_sheet.dart`, `record_page.dart`).
   - Chrome: dictation, transcript editor, the five-option capture sheet.
   - Emulator: recording, the level meter, playback, the v3→v4 migration keeping
     existing notes.
2. **Two errors seen in the Activity 05 build, unexplained.** Check whether they
   survive into the new build:
   - `A RenderFlex overflowed by 38 / 35 pixels on the bottom` — screen unknown.
   - `Assertion failed: ...text_engine/text_editing.dart:1346:7` — no stack
     trace captured. Ask for the full error block.
3. **Then Activity 07 — Sharing & Collaboration** (9 days): sharing,
   permissions, study groups, note requests, Shared Note Inbox. The drawer
   already has the three links wired to a "not built yet" toast, so the entry
   points exist.

## 9. Documents already produced

Kept outside the repo, regenerate or update rather than starting over:

- `NoteNest_Project_Proposal_9_Month.docx` — includes a use case diagram in
  Workflow and an activity diagram in Methodology
- `NoteNest_Project_Proposal_Cover.docx` — cover, Gantt and phase tables
- `NoteNest_Requirement_Specification.pdf` — 8 pages
- `NoteNest_Presentation.pptx` — 21 slides
- `NoteNest_Presentation_10_Slides.pptx` — 10 slides, with both diagrams and a
  Tools & Technologies slide
- `NoteNest_Presentation_Speech.docx` — per-slide speech, about 5m30s
- `ACTIVITY_05.md`, `ACTIVITY_06.md` — in the repo, per-activity notes written
  for the report

## 10. A note on verifying code without a Dart SDK

The assistant's sandbox has no Dart SDK and cannot download one. Code shipped
from there is checked by: a bracket-balance and import scanner, a
constructor-named-argument checker, a repository-member checker, and — for pure
logic such as `transcript.dart` and `note_query.dart` — porting the logic to
Python and running the shipped unit-test expectations against it. Plugin APIs
are confirmed against pub.dev API docs before use, because guessing them is what
caused the `FilePicker` error. This is why the `flutter analyze` output from the
owner's machine matters: it is the only real compiler in the loop.
