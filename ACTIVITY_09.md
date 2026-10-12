# Activity 09 — Documents: cover pages, and PDF ↔ Word

Not on the original Gantt. Added at the student's request, alongside Activity
10's cloud work, as the two offline features of the five asked for.

## How to install

```powershell
cd C:\project\notenest
# unzip over the project, overwriting
flutter pub get      # pubspec.yaml changed — four new packages
flutter analyze
flutter test
flutter run -d chrome
```

Four packages are added. Nothing outside `lib`, `test` and `pubspec.yaml`
changed: **no Android manifest edit, no Gradle edit.**

| Package | What for |
|---|---|
| `pdf: ^3.13.1` | writes the PDF file |
| `archive: ^4.5.1` | a .docx is a zip; this opens and seals it |
| `xml: ^7.0.1` | reads `word/document.xml` |
| `syncfusion_flutter_pdf: ^35.1.37` | pulls the text out of a PDF |

The last one was already in the project as a dependency of
`syncfusion_flutter_pdfviewer`, at that exact version, so it resolves without
moving anything. It is named now only because this code imports it directly.

Reach both screens from the drawer: **Cover page** and **Convert a file**.

## The decision this activity turns on

The obvious way to make a PDF in Flutter is to let the `pdf` package draw the
text. That was tried first and abandoned, because **it cannot set Bengali.**

The `pdf` package has no OpenType shaping engine. It draws one glyph per code
point, in the order they arrive. Bengali needs conjuncts formed and vowel
signs reordered before anything is drawn — so a word like বিশ্ববিদ্যালয় comes
out as disconnected pieces in the wrong order. This is not a bug to work
around; it is [a known, long-standing
limitation](https://github.com/DavBfr/dart_pdf/issues/198) of the package, and
it affects every Indic script.

For an app whose users write cover pages for Bangladeshi universities, a PDF
generator that mangles Bengali is not a feature.

**So the page is drawn by Flutter and photographed.** Flutter's text engine
shapes text properly — it is the same engine setting the Bengali on screen
correctly right now. The cover page is a widget, `PageRenderer` captures it at
200 DPI, and the PDF holds that image.

What this buys and what it costs, stated plainly:

- Bengali, English and any mix of the two come out exactly as they look on
  screen
- the preview **is** the output, so there is no second renderer to drift out of
  step with the first, and no "that is not what the preview showed"
- the text in the exported PDF **cannot be selected or searched**, because it
  is a picture of text
- the file is larger — a few hundred kilobytes for one page rather than a few
  tens

The app says the second point to the student, on the export screen, rather
than leaving them to discover it.

## New files (8)

| File | What it is |
|---|---|
| `lib/models/cover_spec.dart` | What goes on a cover page, and the rules for the gaps. No widgets, no PDF — 11 unit tests on it. |
| `lib/models/doc_text.dart` | `DocBlock`, the one shape PDF and Word both convert through, plus the docx XML reader and writer. 20 tests. |
| `lib/data/document_service.dart` | Picking, reading, building and sharing the files. |
| `lib/data/page_renderer.dart` | `PaperSheet` (a sheet of A4 laid out in points) and the capture, with the reasoning above written into it. |
| `lib/data/doc_paginator.dart` | Breaking a document into pages, measured with a real `TextPainter`. |
| `lib/screens/cover/cover_canvas.dart` | The cover page itself — four templates. This widget *is* the output. |
| `lib/screens/cover/cover_form.dart` | The sixteen fields under the preview. |
| `lib/screens/cover/cover_page.dart` | The screen: live preview, form, export. |
| `lib/screens/convert/convert_page.dart` | PDF → Word and Word → PDF. |
| `lib/screens/convert/doc_page_sheet.dart` | One page of a converted document. |

## Changed files (4)

| File | Change |
|---|---|
| `lib/data/note_repository.dart` | `coverDraft` / `saveCoverDraft`, and two new drawer links. No schema change — `user_settings` is already key and value. |
| `lib/screens/shell/home_shell.dart` | The two new drawer links open their screens. |
| `pubspec.yaml` | The four packages. |
| `test/widget_test.dart` | 36 more tests — **112 in total**, up from 76. |

## Four things worth defending in the viva

**The cover page is one model and four layouts, not one layout in four
colours.** Template and colour are separate controls, because they are
separate decisions: a department that hands out a format wants Classic, and
the colour is whatever prints. Classic is centred with a double rule and two
columns at the foot — what most departments in Bangladesh expect. Ruled puts
notebook lines behind the text and a highlighter swipe under the heading, which
is the app's own visual language carried onto paper. Crest draws a seal and
takes the institution's initials from its name. Minimal is left-aligned with
one rule.

**The form knows what it is asking about.** A lab report asks for an
"Experiment name" and an "Experiment No."; an assignment asks for a "Title"
and an "Assignment No."; a thesis has no number at all, so the field is hidden
rather than labelled with something invented. That lives in one place, on the
`CoverKind` enum, instead of in sixteen copies of a text field.

**Nothing is a gate.** A cover page with gaps still exports — the screen names
what is still empty and says you can write them in by hand. What the app will
not do is invent an institution or a date. The one thing it does carry over is
what does not change between assignments: the institution, department, your
name and your ID. The title, the number and the date are cleared, because
handing in last week's title by accident is a worse failure than retyping one
line.

**Both conversions go through one shape.** PDF → Word and Word → PDF would be
two converters and four behaviours to keep straight. Instead each format only
knows how to become a list of `DocBlock`s and how to be built from one. That
is why the structure guessing, the escaping and the pagination each exist once
and are each tested once.

## The guessing, and why it is conservative

A PDF stores glyphs at positions. It has no paragraphs, no headings, no lists —
those have to be guessed from the text that comes back out.

The guesses only fire when several signs agree. A line becomes a heading when
it is short, ends without punctuation, **and** is either all capitals or
numbered like `3.2 Methodology`. Anything else stays body text.

That is deliberately timid, and the reason is asymmetric cost: a sentence
wrongly promoted to a heading is a visible mistake in a document the student
hands in, while a heading left as body text is only a missed improvement.

The numbers on a numbered list are kept rather than renumbered, because the
text may refer to "step 3" and renumbering could contradict it.

## Known limitations

- **Tables keep their words but lose their shape.** Every paragraph inside a
  table is read as an ordinary paragraph. The alternative — skipping table
  contents — would silently drop a row of someone's data, which is worse than
  losing the gridlines.
- **Images, columns, footnotes, headers and colours are dropped.** A converter
  that claimed these and got them slightly wrong would be worse than one that
  says what it carries.
- **A scanned PDF cannot be converted.** It holds pictures of text, not text.
  The app detects this and says so, rather than handing back an empty Word
  file; reading words off a picture needs OCR, which is not in the project.
- **An old `.doc` is a different format from `.docx`** and is refused with that
  explanation. It is a binary format from before 2007, not a zip of XML.
- **Word → PDF holds each page as an image**, with the same trade as the cover
  page: Bengali survives, selectable text does not.
- **The exported `.docx` has no `styles.xml`.** Formatting is written directly
  onto each run instead, which always renders correctly but means Word's
  navigation pane will not list the headings.
- **Bullets travel as a `•` character, not as Word numbering.** Real list
  numbering needs a `numbering.xml` part; this writes the mark into the text,
  which looks right and does not auto-renumber.
- **Export needs the preview on screen.** Capturing works on a painted widget,
  so the cover preview is pinned above the form and the converter shows each
  page as it renders it. That is why pages flick past during a Word → PDF
  export: it is the work, not an animation.
- **No logo upload.** The Crest template draws a seal and puts the
  institution's initials in it; it cannot place a real university crest yet.
- **20 MB ceiling.** Everything is held in memory at once.

## What moved to the next step, and why

**Reminders** — the phone notification for an exam, left over from Activity 08
— is **not** in this zip, although the Gradle change for it is already applied
and building.

It needs `flutter_local_notifications`, which also needs three permissions and
two receivers in `AndroidManifest.xml`. Activity 10's Firebase work needs
manifest and Gradle changes of its own. Putting all the Android configuration
into one step means one install, and one place to look when something in the
build breaks — rather than two separate chances to break it, a week apart.

Everything in this zip is pure Dart. If `flutter analyze` is clean here, the
Android side is untouched and cannot be the cause.

## How this was checked without a Dart SDK

Same method as the previous activities, and it is worth stating because it is
the honest answer to "did you test it":

1. A Python static checker over every file, diffed against the last known-clean
   tree, so only *new* findings show up. It now also catches a field that is
   declared `final` but never set by the constructor — the bug that got through
   in Activity 08.
2. The pure logic — file naming, the missing-field rules, the structure
   guessing, the XML escaping — ported to Python and run against **the same
   expectations that are written in `test/widget_test.dart`**. 38 of them, all
   passing, before the zip was built.
3. Every package API confirmed against pub.dev before it was used, not from
   memory. That is how `flutter_local_notifications` turned out to take
   `initialize(settings:)` as a named parameter now, and how `PlatformFile` was
   confirmed to have no `bytes` property in `file_picker` 13.

What this cannot check is whether it compiles and whether it looks right. That
is what `flutter analyze` and your eyes are for.

---

# Activity 09b — University list, logo and watermark

Added after seeing a real cover page from City University: a reference sheet
with the university's logo in the corner, its mark as a watermark, and the
details set in panels.

## What is new

| | |
|---|---|
| **Framed template** | A fifth template, now the default — ruled double border, logo in the corner, course and title in panels, two balanced signature blocks, submission date at the foot. |
| **University list** | 10,248 institutions in 200 countries, searchable, carried in the app. "Find my university" fills the name. |
| **Your logo** | Picked once from your phone. It appears in the corner of every cover page and, faded, as the watermark. |
| **New fields** | Program, Batch, and the teacher's own institution — all three are on the reference sheet and were missing. |

## The question this raises, answered honestly

**"Why doesn't it set the logo automatically when I pick my university?"**

Because a university's logo is its trademark. The names in the list are facts
and can be carried in the app; ten thousand logos cannot, because shipping
them would be redistributing ten thousand marks without permission from any of
their owners. Pulling them from a logo service at run time is the same act
with an extra step, and it would need a connection.

So the logo is supplied once, by the student, from a file they already have.
That is the honest version, and it is also the better one:

- it works for **any** institution, including the ones no list has
- it is the real logo at full quality, not whatever a scraper found
- it works offline, like the rest of the app
- it is chosen once and then appears on every cover page without being asked for again

The app says this in the logo slot, in one sentence, rather than leaving the
student to wonder.

## Two deliberate departures from the reference sheet

**The signature blocks are a balanced pair, not staggered.** On the reference,
"Submitted to" sits higher than "Submitted by". It looks decorative on a screen
and reads as a misprint on paper, because nothing explains why one is lower.
They are set level, in two panels of equal height.

**Course and title live in separate panels.** The reference puts the course
code, the course title, the assignment number and the assignment name in two
boxes split by chance. Here the first panel answers "which subject" and the
second answers "which piece of work", so a marker's eye lands on the right line
first.

## How the search works, and why it is ranked

Ten thousand names are only usable if the obvious answer is first. Typing
"city" has to put **City University** at the top, not the forty-ninth entry
with "City" in the middle of its name.

`universityScore` grades each name: an exact match, then a name that opens with
what you typed, then one whose later word opens with it, then one that merely
contains it, and last a name where every word you typed matches the start of
some word — so "dhaka eng" finds Dhaka University of Engineering and
Technology. Ties go to your own country.

Your country is only a tie-break, never a filter: "University of Dhaka" still
wins outright on a better match even when the preference is set elsewhere.
There is a test that says so.

## Known limitations

- **No logo for universities that are not yours.** One logo is stored per
  account, which is right for a student and wrong for anyone making cover
  pages for several institutions.
- **The list is not every university.** New ones open each year. The picker
  says so and offers to use whatever was typed instead.
- **The watermark opacity is fixed** at seven per cent — low enough that text
  stays readable on a laser printer. It can be turned off, not dialled.
- **The logo is stored inside the account**, as base64 in the settings table.
  That keeps it with the account rather than in a file that can go missing, at
  the cost of a row of a few hundred kilobytes.

---

# Activity 09c — Layout and customization

Two things came back from looking at the first Framed pages: the signature
blocks should step down to the right the way the faculty templates do, and the
page felt empty.

## What changed

**Stepped signature blocks, and two other arrangements.** I had set them level
and argued that a stagger reads as a misprint. That was my taste against a
department's convention, and the convention wins — **Stepped is now the
default**. Level and Stacked are there too, because a convention is not a law.

**The page no longer floats in white space.** Three things were wrong:

- the logo had a row of its own across the top, costing about fifty points of
  height and leaving a band of nothing. It now sits over the masthead.
- the gaps were fixed, so a page with four filled fields and a page with twelve
  were set identically
- the signature blocks sat in the middle of the page instead of its lower third

Spacing is now a control — **Tight / Normal / Airy** — and every gap on the
page is multiplied by it. Tight at 0.68 and Airy at 1.34 are far enough apart
to be worth choosing between, and the same layout serves both.

## What "customize everything" turned into

| Control | What it does |
|---|---|
| **Template** | Five layouts: Framed, Classic, Ruled, Crest, Minimal |
| **Colour** | Six printing-safe accents, **plus a hue slider for any colour** |
| **Spacing** | Tight / Normal / Airy — multiplies every gap |
| **Signature blocks** | Stepped / Level / Stacked |
| **Border** | Dotted / Double / Hairline / Corners / None |
| **Logo** | Your own, in the corner of every template |
| **Watermark** | The same logo, faded, on or off |
| **Date** | Shown, or left blank to write in by hand |

The colour slider mixes the hue only; saturation and brightness are held at
values that print. That is deliberate, and worth defending: on a laser printer
a fully saturated colour comes out as a muddy stripe and a pale one disappears
into the paper. Every hue the slider can reach is one that will actually come
out. The choice is the whole wheel, and none of it is a trap.

## Where I stopped, and why

**There is no free drag-and-drop canvas** — no moving a block to an arbitrary
point, no rotating text, no stacking shapes.

That is a deliberate line, not a missing feature. A layout engine is a
different product from a cover page generator, and a half-built one is worse
than neither: every element gains a position that can be wrong, pages stop
being reliably printable, and the student ends up doing the typesetting they
came here to avoid. What is offered instead is a set of decisions that are
each meaningful and none of which can produce a broken page.

**Typeface choice is not in yet, and here is the honest trade.** Making it work
needs either a font file bundled with the app — about 1 to 2 MB per family, and
there is no way around that — or a download on first use, which would break the
one promise this screen makes, that it works offline. Both are real costs that
should be spent deliberately rather than slipped in. Say which you want and it
is a small change either way.

One thing worth noting for the report: because the PDF is a capture of what
Flutter drew, **any font that renders on screen renders in the PDF**, Bengali
included. A font added later needs no work at all on the PDF side.
