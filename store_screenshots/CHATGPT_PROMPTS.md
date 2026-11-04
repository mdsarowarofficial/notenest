# NoteNest — Play Store screenshot prompts for ChatGPT

All screenshots are real, taken from the signed release build on a 1080×1920
emulator with a made-up student ("Nadia Rahman", "Demo University"). No real
person, email or university appears in any of them.

## How to use (Banglish)

1. Prothome **Step 1-er "Style brief"** ta ChatGPT-te paste korun. Eta pura
   conversation-er jonno brand rules.
2. Tarpor protita image-er jonno: oi screenshot file **attach** korun ar niche
   tar prompt paste korun.
3. Output chai **1080×1920 px (9:16)**, PNG. Play Store-e kom-pokkhe 2-ta,
   beshi hole 8-ta phone screenshot dewa jay. Shobcheye bhalo 6-8-ta bachai kora
   (suggestion niche).
4. **Bhul pakar jaygay:** ChatGPT kokhono kokhono app-er bhetorer lekha bigre
   dey. Prottek ta generate howar por zoom kore app-er lekha original-er sathe
   milan. Bhul thakle **Fallback prompt** (Step 4) bebohar korun: ChatGPT shudhu
   background + headline banabe, ar apni original screenshot Canva-te boshiye
   nebe. Eta shobcheye nirapod.
5. **Bangla lekha** ChatGPT-r image-e proyi bhul hoy. Bangla headline Canva-te
   likhe nin.

Suggested order for the Play listing (best first): 01, 08, 03, 04, 05, 07, 10, 13. (Play allows up to 8 phone screenshots.)

---

## Step 1 — Style brief (paste this first, once)

```
I am making Google Play Store screenshots for an Android app called "NoteNest",
a study notebook for university students. I will attach one real app screenshot
at a time. For each one, build a polished Play Store promotional image from it.

OUTPUT FORMAT
- Portrait 1080 x 1920 px, 9:16, PNG, sharp, no watermark.

BRAND
- Mood: friendly, clear, student-focused, calm and confident. Like a well-made
  notebook: paper, pens, highlighters. Never childish, never corporate-cold.
- Primary colour: indigo #4A5BD4. Deep indigo #35469E. Pale indigo #CBD2F7.
- Accent: highlighter yellow #FFD84D (used for emphasis and underlines).
- Support: mint #17A47A, soft red #C42A42, pink #FF8FA3.
- Soft tints for backgrounds: pen tint #E8EBFC, warm cream #FFF3CF,
  mint tint #DFF6EC, rose tint #FFE3E6, page grey #F6F7FB.
- Text ink: #1B1E2B on light backgrounds, white on indigo backgrounds.
- Dark theme backdrop: #0E1016 with card colour #181B26 and indigo #6676E8.
- Headline font look: Outfit (geometric, bold). Body look: Plus Jakarta Sans.
  Use a similar clean geometric sans-serif if you cannot match them.
- Visual motif (use sparingly, as faint decoration): spiral notebook binding,
  a pen, a yellow highlighter stroke, sticky notes, a ruler, a paperclip, a
  pink notebook. Flat, soft-shadow illustration style, rounded corners.

LAYOUT
- Headline in the top 20% of the image, left-aligned or centred, max 6 words,
  large and bold, with ONE key word underlined by a hand-drawn yellow
  highlighter stroke.
- Optional one-line subheadline under it, smaller, max 10 words.
- A modern generic Android phone (thin bezels, rounded corners, no brand, no
  logo, no notch text) showing the attached screenshot, large, centred, taking
  about 70% of the image height, slightly cropped by the bottom edge for a
  confident feel. Soft realistic shadow. Straight-on, no tilt.
- Plenty of breathing space. Nothing overlaps the screenshot's important text.

STRICT RULES
- The attached screenshot must appear EXACTLY as given. Do not redraw,
  re-type, translate, crop out, blur or alter any text, icon, number or colour
  inside the phone screen. Keep every pixel of the app UI faithful.
- No people, no faces, no real brands, no Apple or Google logos, no store
  badges, no star ratings, no download counts, no prices, no claims such as
  "#1" or "best".
- Only the headline text I give you. Spell it exactly. No extra words.
- Keep it consistent across the whole set: same fonts, same phone style, same
  headline position, only the background colour and motif change.

Reply "ready" and wait for the first screenshot.
```

---

## Step 2 — One prompt per screenshot

Attach the named file, then paste its prompt.

### 01 — `01_today_light.png`  (the hero image, use first)

```
Use the attached screenshot (the Today home screen).
Background: smooth gradient from indigo #4A5BD4 (top) to deep indigo #35469E
(bottom), with a faint spiral-notebook binding along the left edge and a few
low-opacity paper-grain details.
Headline (white, bold): "Your whole study day, in one place"
Underline the words "study day" with a hand-drawn yellow #FFD84D highlighter
stroke.
Subheadline (pale indigo #CBD2F7): "Courses, to-dos and revision at a glance."
Decoration: a small yellow sticky note and a pen peeking from the top-right
corner, very subtle.
Follow the Style brief exactly. Do not alter the screenshot.
```

### 02 — `02_notes_list.png`

```
Use the attached screenshot (the All notes list with subject filters).
Background: warm cream #FFF3CF with faint ruled notebook lines and a thin red
margin line on the left, like a notebook page.
Headline (ink #1B1E2B, bold): "Every note, neatly filed"
Underline "neatly filed" with a yellow highlighter stroke.
Subheadline: "Filter by subject, tag or status."
Decoration: a yellow highlighter and a pink paperclip in a top corner, subtle.
Follow the Style brief. Do not alter the screenshot.
```

### 03 — `03_note_detail.png`

```
Use the attached screenshot (a note with a heading, bullets and a checklist).
Background: pen tint #E8EBFC with a few soft indigo circles and a hand-drawn
indigo pen scribble in one corner.
Headline (ink, bold): "Write it. Tick it. Master it."
Underline "Master it." with a yellow highlighter stroke.
Subheadline: "Headings, lists and checklists in every note."
Decoration: a small mint checkmark badge near the headline, flat style.
Follow the Style brief. Do not alter the screenshot.
```

### 04 — `04_exam_countdown.png`  (alternative: `04b_exam_revision_order.png`)

```
Use the attached screenshot (Exam mode with a 14-day countdown).
Background: rose tint #FFE3E6 with a soft large circle in pink #FF8FA3 behind
the phone and tiny calendar-page shapes.
Headline (ink, bold): "Count down to every exam"
Underline "every exam" with a yellow highlighter stroke.
Subheadline: "Know exactly what to revise first."
Decoration: a flat red-pen circle drawn around a date, subtle.
Follow the Style brief. Do not alter the screenshot.
```

### 05 — `05_cover_page_preview.png`  (and `05b_cover_styles.png` as a second image)

```
Use the attached screenshot (a generated assignment cover page).
Background: pale indigo #CBD2F7 to white soft gradient, with a faint stack of
paper sheets behind the phone.
Headline (ink, bold): "Cover pages in seconds"
Underline "seconds" with a yellow highlighter stroke.
Subheadline: "Assignments, lab reports, projects and theses."
Follow the Style brief. Do not alter the screenshot.
```

For `05b_cover_styles.png` use the same prompt but headline:
`"Pick a look you like"` (underline "look") and subheadline
`"Five styles, your colours."`

### 06 — `06_convert.png`

```
Use the attached screenshot (Convert a file: PDF to Word and Word to PDF).
Background: mint tint #DFF6EC with soft mint #17A47A shapes, and two small flat
document icons (one marked PDF, one marked DOC) with a double arrow between
them, low contrast, at the top-right.
Headline (ink, bold): "Word and PDF, both ways"
Underline "both ways" with a yellow highlighter stroke.
Subheadline: "Convert right on your phone."
Follow the Style brief. Do not alter the screenshot.
```

### 07 — `07_drawer_subjects.png`

```
Use the attached screenshot (the side drawer with subjects and semester).
Background: indigo #4A5BD4 with large soft pale-indigo circles and a spiral
binding along the left edge.
Headline (white, bold): "Organised by subject and semester"
Underline "subject" with a yellow highlighter stroke.
Subheadline (pale indigo): "Colour-coded tabs, just like a real notebook."
Follow the Style brief. Do not alter the screenshot.
```

### 08 — `08_todo_planner.png`  (strong second image)

```
Use the attached screenshot (the weekly to-do list).
Background: page grey #F6F7FB with a big soft yellow #FFD84D circle behind the
phone and tiny floating checkmarks in indigo.
Headline (ink, bold): "Plan your week, tick it off"
Underline "tick it off" with a yellow highlighter stroke.
Subheadline: "A to-do list built around your courses."
Follow the Style brief. Do not alter the screenshot.
```

### 09 — `09_study_timer.png`

```
Use the attached screenshot (the study timer, 25:00).
Background: deep indigo #35469E with a faint large clock-face outline and tiny
sparkles.
Headline (white, bold): "Focus with a study timer"
Underline "Focus" with a yellow highlighter stroke.
Subheadline (pale indigo): "Short sessions, steady streaks."
Follow the Style brief. Do not alter the screenshot.
```

### 10 — `10_today_dark.png`  (dark mode)

```
Use the attached screenshot (the Today screen in dark mode).
Background: near-black #0E1016 with a soft indigo #6676E8 glow behind the phone
and a few tiny stars.
Headline (white, bold): "Easy on the eyes at night"
Underline "at night" with a yellow highlighter stroke.
Subheadline (grey-blue): "A full dark theme, one tap away."
Follow the Style brief. Do not alter the screenshot.
```

### 11 — `11_notes_dark.png`  (optional second dark image)

```
Use the attached screenshot (the All notes list in dark mode).
Background: near-black #0E1016 with a soft indigo #6676E8 glow and faint
spiral-binding rings along the left edge.
Headline (white, bold): "All your notes, one search away"
Underline "one search" with a yellow highlighter stroke.
Subheadline (grey-blue): "Find anything, even inside your PDFs."
Follow the Style brief. Do not alter the screenshot.
```

### 12 — `12_login_light.png`  (optional opener or closer)

```
Use the attached screenshot (the NoteNest sign-in screen).
Background: soft sky-to-pink pastel gradient matching the screenshot, with
faint stationery shapes (notebook, pen, ruler).
Headline (ink, bold): "Welcome to NoteNest"
Underline "NoteNest" with a yellow highlighter stroke.
Subheadline: "Write it. Photograph it. Record it. Revise it."
Follow the Style brief. Do not alter the screenshot.
```

### 13 — `12_today_bangla.png`  (and `13_exam_bangla.png` as a second one)

```
Use the attached screenshot (the Today screen in Bangla).
Background: warm cream #FFF3CF with a soft indigo shape behind the phone.
Headline (ink, bold): leave the headline area EMPTY. I will add the Bangla text
myself.
Keep a clean empty band at the top, 20% of the height, for a headline.
Follow the Style brief. Do not alter the screenshot.
```

Headline to add yourself in Canva: **এখন বাংলায়** with the subheadline
**ইংরেজি ও বাংলা, দুই ভাষাতেই।**

---

## Step 3 — Feature graphic (1024 × 500, required by Play)

Attach nothing, or attach `01_today_light.png` for reference.

```
Create a landscape 1024 x 500 px feature graphic for the Google Play listing of
"NoteNest", a study notebook app for university students.
Left half: the word "NoteNest" in large bold Outfit-style geometric sans-serif,
ink #1B1E2B on a yellow #FFD84D highlighter swipe, and below it the line
"Write it. Revise it. Ace it." in indigo #4A5BD4.
Right half: a modern generic Android phone, slightly cropped by the right edge,
showing the attached screenshot unchanged.
Background: indigo-to-deep-indigo gradient (#4A5BD4 to #35469E) OR cream
#FFF3CF; pick the one that gives the best contrast, and keep both text and
phone clearly readable.
Faint stationery decoration (pen, ruler, sticky note, paperclip) kept to the
edges. No people, no logos other than the NoteNest word, no store badges, no
ratings, no extra text.
Keep all important content inside the central 924 x 400 safe area.
```

---

## Step 4 — Fallback prompt (if ChatGPT keeps spoiling the app text)

```
Do NOT include any phone or app screenshot. Create only a 1080 x 1920 px
portrait background for a Play Store screenshot, following the Style brief
colours and motif, with this headline in the top 20%, exactly spelled:
"<HEADLINE HERE>"
(underline the key word with a yellow highlighter stroke) and the subheadline
"<SUBHEADLINE HERE>".
Leave the whole lower 75% of the image as clean empty background where I will
place a phone mockup myself.
```

Then in Canva (or Figma): add a free "Android phone mockup" frame, drop the
original screenshot in, and place it on the generated background. The app text
stays pixel-perfect.

---

## What these screenshots do not show

Classes, chat and sharing are not in this set because they need a second cloud
account and real people. If you want them, ask Claude to set up two demo
accounts and capture them later.

## Before you upload

* Check every final image at full size: spelling of the headline, nothing
  covering the app text, nothing that looks like a claim the app does not make.
* Keep the same look across all images.
* The screenshots must stay representative of the real app. Do not add features
  that are not in it (no AI, no scanning-to-text, no push notifications).
