# NoteNest — system and design review

Read of the whole tree at `7898af2`: 38 screens, 14 shared widgets, 27,196
lines of Dart.

The question was two things — are the features right, and why does it look
basic. The second has a single answer that explains most of it, so that comes
first.

---

## 1. The app has no typeface

`lib/theme/nest_theme.dart`:

```dart
class NestFont {
  static const String? display = null;   // suggestion: 'Fraunces'
  static const String? body = null;      // suggestion: 'Manrope'
  static const String? mono = null;      // suggestion: 'IBM Plex Mono'
}
```

Three font slots were designed into the system, wired through every text style
— and **all three are null**. `google_fonts` is commented out in
`pubspec.yaml`. There are no font files in `assets/`.

So every word in NoteNest is drawn in the platform default: Roboto on Android,
whatever the browser decides on web. The error in your last run —

```
Failed to load font Roboto at https://fonts.gstatic.com/...
```

— is the same hole from the other side: on web it could not even fetch the
fallback.

**This is the main reason it reads as basic.** Typography carries most of the
impression an interface makes. Colour, spacing and the hand-drawn marks here
are already considered; they are being delivered in the typeface of a settings
screen.

The fix is small and the change is large: bundle the families as assets, fill
the three constants. Bundled rather than downloaded, so it works offline and
cannot fail the way it just did.

| Slot | Carries | Family | Why |
|---|---|---|---|
| `display` | Screen titles, the wordmark, cover pages | **Fraunces** | A serif with real character, variable optical sizing. Gives the "ballpoint and paper" idea a voice |
| `body` | Everything you read | **Manrope** | Geometric, open, excellent at 13–15px where this app lives |
| `mono` | Eyebrow labels, codes, counts | **IBM Plex Mono** | Already assumed by `nestEyebrow`; the join code and countdown need it |

Roughly 900 KB for the weights actually used. One change, every screen.

---

## 2. Everything is flat on flat

Five `BoxShadow` in 27,000 lines. Cards are white on `#EDEFF3` with a 1px
border, and that is the entire depth model.

A border says "here is a boundary". A shadow says "this is above that". The
app currently never says the second thing, so a card, a sheet and a dialog all
sit at the same visual level and nothing feels picked up or put down.

What it needs is not drop shadows everywhere — it needs **two or three defined
elevation levels** used consistently: the page, things resting on it, and
things floating over it (sheets, the nav bar, the FAB). Soft, large-radius,
low-opacity, tinted with the ink colour rather than black.

---

## 3. Motion is only entrances

`RiseIn` on load, and animated custom painters. What is missing is motion that
*explains*:

- **Page transitions are Material's default slide.** Opening a note from a list
  should grow from the tile it came from
- **No shared element** between a subject chip and its notes, or a cover
  thumbnail and the full page
- **Nothing acknowledges a tap** beyond the stock ripple
- **State changes cut rather than cross-fade** — a note moving from Review to
  Mastered just changes

A splash animation, which you asked about, belongs at the end of this list
rather than the start. An app that animates once at launch and then moves like
a form is more jarring than one that never animates.

---

## 4. Where the features are, and what is wrong with it

```
Bottom nav   Today · Notes · (+) · Shared · Exam
Drawer       Cloud account · Cover page · Convert a file · Shared inbox
             · Chats · Groups · Note requests · Trash
```

**Cover page and Convert are the two features no other notes app has, and both
are buried in a hamburger menu.** They are what make NoteNest a *student's*
app rather than a notepad — and they sit below "Cloud account", behind a
gesture most people never make. Anybody demonstrating this app has to go
hunting for its best idea.

**"Shared" is a bottom tab and "Shared inbox" is a drawer link to the same
screen.** The drawer entry sets `_tab = 2`. Two doors into one room, and the
drawer one looks like it leads somewhere else.

**Chats and Groups are two entries for one idea.** The Chats screen already
lists every group. Groups only adds making and joining — which belongs inside
Chats, not beside it.

**"Note requests" is a drawer item of its own** for something that is part of
sharing.

**The drawer is eight flat items of four different kinds** — an account
setting, two tools, four social things and a bin. It has `SUBJECTS` and
`WORKSPACE` headings, which is good, but everything after the subjects is one
undifferentiated list.

### What it should be

```
Bottom nav   Today · Notes · Tools · People · Exam
             with the centre + for capture, as now

Tools        Cover page · Convert · (later: anything else that makes a file)
People       Chats, with groups inside it; the Shared inbox as a tab;
             requests folded in
Drawer       Subjects, profile, cloud account, trash, settings — and nothing
             that is a feature
```

The principle: **the drawer is for places, the nav bar is for work.** Right
now half the work is in the drawer.

---

## 5. Flows that cost more steps than they are worth

**Making a cover page** is the longest journey in the app: drawer → Cover page
→ a form of 17 fields → template → density → frame → signature style → accent.
Every one of those is a good control and together they are a wall. It needs a
first screen that asks four things (kind, course, title, your name) and makes a
usable page, with everything else behind "Customise".

**Sharing one note has two different buttons** in the same sheet — "Send as a
file" and "Send inside NoteNest" — and the difference between them is a
paragraph of text. The sheet should ask *who* first, then decide the route
itself.

**Setup is three steps before the first note.** Semester, subjects, revision
plan. The revision plan does nothing yet (now honestly labelled). Subjects
could be added at the moment the first note needs one.

**A note's status moves New → Read → Review → Mastered**, which is the best
idea in the app, and the only place it is visible is a small chip. It deserves
to be the thing the Today screen is built around.

---

## 6. What is good and should not be touched

Worth saying, because a rebuild tends to throw these out:

- **The colour system.** Ballpoint blue, highlighter yellow, red pen, mint —
  a real idea, consistently applied, and not a Material palette
- **The hand-drawn marks.** `nest_marks.dart`, the countdown ring, the level
  meter, the wordmark — all `CustomPainter`, all specific to this app
- **The writing.** Empty states and error messages say what happened and what
  to do. That is rarer than good visuals and harder to get back once lost
- **`models/` has no Flutter imports**, which is why 188 tests run with no
  device. A redesign must not drag UI concerns into it

---

## 7. The order I would do it in

Ranked by what a person notices in the first ten seconds.

| | Change | Effort | Visible |
|---|---|---|---|
| 1 | **Three typefaces** | ~1 hour | Enormous — every screen |
| 2 | **Elevation and shadow system** | ~2 hours | Large |
| 3 | **Nav: Tools and People tabs** | ~3 hours | Large — the app stops hiding its best features |
| 4 | **Today screen rebuilt around study status** | ~4 hours | Large |
| 5 | **Cover form: simple first, customise after** | ~4 hours | Medium, but it is the demo feature |
| 6 | **Page and shared-element transitions** | ~3 hours | Medium |
| 7 | **Launcher icon and splash** | ~2 hours | First impression |
| 8 | **Splash animation** | ~3 hours | The polish you asked for — last, so it matches |

Items 1 and 2 together are an afternoon and change the whole impression. Item
3 is the one that makes the app *make sense*. The animation is worth doing and
is worth doing **last**, because a premium launch animation in front of a flat
app reads as a costume.

---

## 8. One thing I cannot do from here

I have read every screen's code, so this review is sound on structure,
placement, flow and the system. It is weaker on anything that has to be *seen*
— real spacing on a real device, how the colours sit together at size, whether
a screen feels crowded.

Screenshots of Today, Notes, a note being read, the cover form and a chat would
sharpen the visual half considerably. Not required to start — items 1, 2 and 3
are right regardless.
