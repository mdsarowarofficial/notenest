# Activity 05 — Search & Study Workflow

Gantt Week 4–5 (8 days). No new packages, no Android files, no emulator —
this one runs in Chrome.

## How to install

Unzip over `C:\project\notenest`, letting it overwrite. That replaces `lib\`
and `test\`. Nothing else changes, so **no `flutter pub get` is needed**.

```powershell
cd C:\project\notenest
flutter analyze
flutter test
flutter run -d chrome
```

## New files (5)

| File | What it is |
|---|---|
| `lib/models/note_query.dart` | The query as one immutable value: words, filters, sort order. Holds the matching and ordering rules, and the tag normalization. |
| `lib/screens/search/search_page.dart` | The search screen behind the toolbar icon. Debounced, queries the database, shows the matching line from each note. |
| `lib/widgets/nest_query_bar.dart` | The filter chip strip plus the sort menu. |
| `lib/widgets/nest_tags.dart` | Tag chips (read-only) and the tag entry field for the editor. |
| `ACTIVITY_05.md` | This file. |

## Changed files (7)

| File | Change |
|---|---|
| `lib/data/note_repository.dart` | `searchNotes()` (SQL), `queryNotes()` (in-memory), `allTags()`, `topTags()`, `noteCountForTag()`, `updateTags()`, recent-search history, and per-status / per-type counts. |
| `lib/models/note.dart` | `NoteType.label`, so a chip can say "Written" while the database still stores `text`. |
| `lib/screens/notes/notes_page.dart` | Now stateful. Filter bar, sort, result count, and a "no match" card that names the filters in force. |
| `lib/screens/notes/note_editor.dart` | A TAGS field, with the tags already in use offered underneath. |
| `lib/screens/notes/note_detail.dart` | Shows the note's tags; tapping one opens search narrowed to that tag. |
| `lib/screens/home/today_page.dart` | A "Search your N notes" row on the landing screen. |
| `lib/screens/shell/home_shell.dart` | The toolbar search icon now opens the search screen. |
| `test/widget_test.dart` | 15 unit tests over the search, filter, sort and tag rules, plus a fix to the old stepper test (see below). |

## The stepper test

The stepper widget test that shipped with Activity 02 was asserting that each
step title appears on screen exactly once. That stopped being true when the
stepper gained its heading: the step the student is on has its title drawn
twice — once on the rail, once as the heading above it. The widget is correct;
the assertion was stale, and nothing had run `flutter test` since.

It now asserts what is actually true — the current step's title twice, the
others once — and a second test runs the same stepper with `showHeader: false`
to prove the duplicate comes from the heading and not from the rail drawing the
current step twice. That is the part worth pinning down, because a rail that
double-drew a step would be a real bug hiding behind the same symptom.

## What this activity delivers

**Requirement 6.1 — Search.** Typing runs a real SQL query against the whole
notebook, not a filter over the list already on screen, so a note is found by
a word buried in its body. The words are split and **every** word must appear
somewhere in the title, body, topic or tags, so `join normal` narrows rather
than widens, and the order typed does not matter.

**Requirement 6.2 — Filter and sort.** Important, kind (Written / Photo /
PDF), revision status (New / Read / Review / Mastered) and tag, in any
combination, with four sort orders. The subject still comes from the drawer.

**Requirement 6.3 — Tags.** Tags are normalized to one form — lower-cased,
trimmed, no commas, the `#` a student types stripped off — so `#DBMS` and
`dbms ` are one tag and not three.

## Notes on the design, for the report

- **Two paths, one question.** The Notes tab filters the list already in
  memory so a chip responds instantly; search queries SQLite so it can reach
  every note. Both answer the same `NoteQuery` object, which is why the
  matching and ordering rules live in the model and not in either screen.
- **No schema change.** The `tags` column and the two indexes on `notes` were
  already in place from Activity 04, so the database version stays at 3 and
  an installed app keeps its data.
- **LIKE is escaped.** `%` and `_` are wildcards in SQL LIKE, so a search for
  "50%" would have matched everything. Each needle escapes them and every
  LIKE declares its escape character.
- **Tag matching is exact.** Tags for one note live in a single comma-joined
  column, so the needle and the column are both padded with commas before the
  LIKE — otherwise the tag `db` would match `dbms`.
- **Voice is not offered as a filter.** Lecture recording is Activity 06, so a
  Voice chip could only ever return nothing.

## Known limitation

Search is `LIKE`-based, which is linear in the number of notes. That is the
right choice at this size and it needs no extra table. If the notebook grows
to thousands of notes, the next step would be SQLite's FTS5 virtual table,
kept in step with `notes` by triggers.
