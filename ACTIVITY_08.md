# Activity 08 — Exam & Productivity

Gantt Week 7 (7 days). Gantt deliverables: Exam Mode, countdown, progress
tracking, reminders, academic calendar.

## How to install

```powershell
cd C:\project\notenest
# unzip over the project, overwriting
flutter analyze
flutter test
flutter run -d chrome
```

**No new packages this time** — `pubspec.yaml` is untouched, so `flutter pub
get` is not needed. Nothing outside `lib` and `test` changed either: no
manifest edit, no Gradle edit.

The database schema goes from **v5 to v6**. That happens by itself on first
launch; your existing notes, subjects and shared inbox are not touched.

## New files (5)

| File | What it is |
|---|---|
| `lib/models/exam.dart` | The exam, and the rule that decides what to revise first. Pure Dart, no database, no widgets — 25 unit tests sit on it. |
| `lib/screens/exam/exam_page.dart` | Exam Mode: the dial, the verdict, the progress bar, the revision queue, past dates. |
| `lib/screens/exam/exam_form.dart` | Add or edit a date — kind, day, subject, reminder, title. |
| `lib/screens/exam/calendar_page.dart` | The academic calendar, a month at a time. |
| `lib/widgets/nest_countdown_ring.dart` | The dial: days left in the middle, revision progress around the edge. |

## Changed files (6)

| File | Change |
|---|---|
| `lib/data/app_database.dart` | Schema v6: the `exams` table and its index, plus the migration step. |
| `lib/data/note_repository.dart` | The exams section — add, update, delete, `examsOn`, `revisionQueue`, `dueReminders`. |
| `lib/screens/home/today_page.dart` | Due reminders now appear on the landing screen, and the sub-line names the next date. |
| `lib/screens/shell/home_shell.dart` | Tapping a reminder on Today goes to Exam Mode. |
| `test/widget_test.dart` | 25 more tests — 76 in total. |
| `ACTIVITY_08.md` | This file. |

## The part worth defending in the viva

Everything else in this activity is bookkeeping. The feature is the **order the
revision queue comes out in**, and the reason it is worth defending is that it
is a judgement, not a calculation — so it is written down where it can be
argued with, in `revisionOrder`, and every step of it has a test.

The rule, in order:

1. **Starred notes first.** The student marked those themselves. An app
   guessing what matters should never outrank the student saying it.
2. **Then worst-first through the revision cycle:** Review, New, Read,
   Mastered. Review sits above New for the same reason as step 1 — "Review" is
   the student's own note to themselves that this one did not stick, which is a
   stronger signal than the app noticing a note was never opened.
3. **Then least recently opened,** with never-opened counting as longest ago,
   so nothing sits at the bottom of the list forever.
4. **Then oldest first,** purely so the order is stable and does not shuffle
   between builds. A list that reorders itself when nothing changed looks
   broken even when it is not.

**Mastered notes are kept, not dropped.** The day before an exam a student may
well want to skim them, and a list that silently hides work is worse than one
that puts it last. There is a test that says so.

The second judgement is `revisionVerdict`, the one line under the dial. It is
deliberately never congratulatory when it is not warranted: two days out with
most of the subject untouched says `10 left and the exam is today`, not
"keep going!". `dailyTarget` rounds **up** — ten notes over three days is four
a day, not 3.33 — because a target that is already behind by rounding is not a
target.

## A bug fixed on the way: countdowns and daylight saving

`daysUntil` first subtracted two local midnights and read `.inDays`. That
measures elapsed hours, so in a timezone that puts its clocks forward between
the two dates, a two-day gap is 47 hours and `inDays` rounds it down to **1** —
the countdown would be a day short, once a year, for anyone outside
Bangladesh.

It now compares the two dates as UTC days. There is a test using 8–10 March
2026, which is a clocks-forward window in several timezones.

Bangladesh has no daylight saving, so this would never have shown up in
testing here. It is in the report because "it does not affect our users" is not
the same as "it is not a bug".

## Reminders: what is built, and what is not

**Built.** You pick a lead time when you add a date — off, 1 day, 3 days or 1
week before. Once that window opens, the reminder appears at the top of the
Today screen, with the countdown and a tap through to Exam Mode. The lead is
stored as a **number of days**, not a timestamp, so moving the exam moves the
reminder with it instead of leaving a stale alarm pointing at a date that no
longer has anything on it. There is a test for that.

**Not built.** A notification that arrives on the phone **while NoteNest is
closed.** That needs `flutter_local_notifications`, which needs three changes
outside `lib`:

- `android/app/build.gradle.kts` — core library desugaring
  (`coreLibraryDesugaringEnabled` plus the `desugar_jdk_libs` dependency),
  which also pins the Java compatibility level
- `AndroidManifest.xml` — `POST_NOTIFICATIONS`, `SCHEDULE_EXACT_ALARM`,
  `RECEIVE_BOOT_COMPLETED`, and the plugin's receivers
- the `timezone` package, so a scheduled alarm survives a timezone change

I have not seen your `android/app/build.gradle.kts`, and a Gradle file is the
one place where a wrong guess costs an hour of build errors rather than a red
squiggle. **Send me that file and I will hand it back complete**, along with
the manifest and the scheduling code. It is a small, isolated change — the
reminder lead is already in the database and already has a rule for when it
fires.

The form says all of this to the student in one line, because a reminder
someone believes will wake their phone and does not is worse than no reminder
at all.

## Known limitations

- **One reminder per date.** No "remind me a week before *and* the night
  before". The column holds a single lead time.
- **No repeating dates.** A weekly lab report has to be added each week.
  The `kind` column is there, so a recurrence rule would hang off it cleanly.
- **The calendar shows at most three dots on a day.** A fourth mark in a cell
  that size is a smudge, not information; the day's full list is underneath.
- **The revision queue has no notion of how long a note takes.** Twenty notes
  is twenty notes, whether they are one line or six photographed pages, so
  `dailyTarget` is a count rather than an estimate of work.
- **Deleting a subject empties its exams rather than deleting them.** The
  `subject_id` foreign key is `ON DELETE SET NULL`, so the date survives as a
  whole-notebook one. That is deliberate — losing an exam date because a
  subject was tidied up would be worse — but it does mean the revision queue
  for it widens to everything.
