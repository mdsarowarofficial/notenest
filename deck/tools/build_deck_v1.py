"""Builds deck/NoteNest_Presentation.pptx from deck/shots/ and deck/gifs/.

Any screenshot named in SLOTS that exists in deck/shots/ is used automatically,
so dropping a phone capture (09_attachments.png, 17_people.png ...) in the
folder and re-running this script replaces the fallback.
"""
import os
import copy
from lxml import etree
from PIL import Image, ImageDraw, ImageFilter
from pptx import Presentation
from pptx.util import Inches, Pt, Emu
from pptx.dml.color import RGBColor
from pptx.enum.shapes import MSO_SHAPE, MSO_CONNECTOR
from pptx.enum.text import PP_ALIGN, MSO_ANCHOR

from assets import phone_frame

D = r"C:\project\notenest\deck"
SHOTS, BUILD, GIFS = D + r"\shots", D + r"\build", D + r"\gifs"
OUT = D + r"\NoteNest_Presentation.pptx"
AUTHOR = "Md Sarowar"

# ---- tokens from lib/theme/nest_theme.dart
def C(h):
    return RGBColor.from_string(h.lstrip("#").upper())

L = dict(ground="F6F7FB", card="FFFFFF", rule="E4E7F0", ink="1B1E2B", inkSoft="5A6076", inkMeta="8A90A6",
         pen="4A5BD4", penDeep="35469E", penPale="CBD2F7", hi="FFD84D", tintPen="E8EBFC", tintMint="DFF6EC",
         mintDeep="0E7A5A", tintWarm="FFF3CF", warmDeep="9A7400", tintRed="FFE3E6", redDeep="B01A2A")
N = dict(ground="0E1016", paper="12141C", card="181B26", rule="2A2E3D", ink="ECEEF5", inkSoft="B4B9CC",
         pen="6676E8", penDeep="AEB8FA", hi="FFD84D", tintPen="262C55", tintMint="12352B", mintDeep="5FD3A3",
         tintWarm="3B3215", warmDeep="F6CD54", tintRed="3D1C23", redDeep="FF8A9B")
HEAD, BODY = "Segoe UI Semibold", "Segoe UI"

prs = Presentation()
prs.slide_width, prs.slide_height = Inches(13.333), Inches(7.5)
BLANK = prs.slide_layouts[6]
TOTAL = 12


def rect(s, x, y, w, h, fill, radius=None, line=None, shape=None):
    shp = s.shapes.add_shape(shape or (MSO_SHAPE.ROUNDED_RECTANGLE if radius else MSO_SHAPE.RECTANGLE),
                             Inches(x), Inches(y), Inches(w), Inches(h))
    if radius and shp.shape_type is not None and shape is None:
        shp.adjustments[0] = min(0.5, radius / min(w, h))
    shp.fill.solid()
    shp.fill.fore_color.rgb = C(fill)
    if line:
        shp.line.color.rgb = C(line)
        shp.line.width = Pt(1)
    else:
        shp.line.fill.background()
    shp.shadow.inherit = False
    return shp


def text(s, x, y, w, h, t, size=18, color="1B1E2B", bold=False, font=BODY, align=PP_ALIGN.LEFT,
         anchor=MSO_ANCHOR.TOP, space_after=0):
    tb = s.shapes.add_textbox(Inches(x), Inches(y), Inches(w), Inches(h))
    tf = tb.text_frame
    tf.word_wrap = True
    tf.margin_left = tf.margin_right = tf.margin_top = tf.margin_bottom = 0
    tf.vertical_anchor = anchor
    lines = t if isinstance(t, list) else [t]
    for i, ln in enumerate(lines):
        p = tf.paragraphs[0] if i == 0 else tf.add_paragraph()
        p.alignment = align
        p.space_after = Pt(space_after)
        r = p.add_run()
        r.text = ln
        r.font.size = Pt(size)
        r.font.bold = bold
        r.font.name = font
        r.font.color.rgb = C(color)
    return tb


def background(s, color):
    bg = s.background.fill
    bg.solid()
    bg.fore_color.rgb = C(color)


def notes(s, t):
    s.notes_slide.notes_text_frame.text = t


def transition(s, kind):
    ns = "http://schemas.openxmlformats.org/presentationml/2006/main"
    tr = etree.SubElement(s._element, f"{{{ns}}}transition")
    tr.set("spd", "med")
    etree.SubElement(tr, f"{{{ns}}}{kind}" if kind == "fade" else f"{{{ns}}}push").set(*(("thruBlk", "0") if kind == "fade" else ("dir", "l")))
    # the schema wants transition before timing/extLst; there are neither here
    return tr


def rail(s, n, dark=False):
    pal = N if dark else L
    x0, w, gap = 0.8, 11.73, 0.06
    seg = (w - gap * (TOTAL - 1)) / TOTAL
    for i in range(TOTAL):
        rect(s, x0 + i * (seg + gap), 7.2, seg, 0.045, pal["pen"] if i < n else pal["rule"], radius=0.02)
    text(s, 11.53, 6.9, 1.0, 0.22, f"{n:02d} / {TOTAL}", 11, pal["inkSoft"] if dark else L["inkMeta"], align=PP_ALIGN.RIGHT)


def heading(s, n, label, title, dark=False):
    pal = N if dark else L
    rect(s, 0.8, 0.55, 0.55, 0.07, pal["pen"])
    text(s, 0.8, 0.72, 6, 0.3, f"{n:02d}  ·  {label}", 13, pal["penDeep"] if dark else L["penDeep"], True)
    text(s, 0.8, 1.1, 5.3, 1.5, title, 36, pal["ink"], font=HEAD)


def cards(s, lines, y=3.05, w=4.9, dark=False):
    pal = N if dark else L
    tints = [("tintPen", "pen"), ("tintMint", "mintDeep"), ("tintWarm", "warmDeep"), ("tintRed", "redDeep")]
    for i, ln in enumerate(lines):
        t, d = tints[i % 4]
        yy = y + i * 0.98
        rect(s, 0.8, yy, w, 0.82, pal[t], radius=0.2)
        rect(s, 0.8, yy + 0.2, 0.07, 0.42, pal[d])
        text(s, 1.1, yy, w - 0.5, 0.82, ln, 18, pal["ink"], anchor=MSO_ANCHOR.MIDDLE)


# ---------------------------------------------------------------- phones
def shot_path(name):
    p = os.path.join(SHOTS, name + ".png")
    return p if os.path.exists(p) else None


def first(*names):
    for n in names:
        if shot_path(n):
            return n
    return None


def phone(s, name, x, y, body_h, crop_h=None, shadow=True, dark_body=False):
    """Place a framed screenshot; (x, y) is the top-left of the phone body."""
    src = shot_path(name)
    out = os.path.join(BUILD, f"phone_{name}{'_c' if crop_h else ''}.png")
    size, pad = phone_frame(src, out, crop_h=crop_h, shadow=shadow)
    body_px = size[1] - 2 * pad
    k = body_h / body_px
    pic = s.shapes.add_picture(out, Inches(x - pad * k), Inches(y - pad * k), Inches(size[0] * k), Inches(size[1] * k))
    return dict(x=x, y=y, w=(size[0] - 2 * pad) * k, h=body_h)


def badge(s, n, cx, cy, d=0.34, fill="4A5BD4"):
    o = rect(s, cx - d / 2, cy - d / 2, d, d, fill, shape=MSO_SHAPE.OVAL)
    o.line.color.rgb = C("FFFFFF")
    o.line.width = Pt(1.5)
    tf = o.text_frame
    tf.margin_left = tf.margin_right = tf.margin_top = tf.margin_bottom = 0
    tf.vertical_anchor = MSO_ANCHOR.MIDDLE
    p = tf.paragraphs[0]
    p.alignment = PP_ALIGN.CENTER
    r = p.add_run()
    r.text = str(n)
    r.font.size, r.font.bold, r.font.name = Pt(13), True, BODY
    r.font.color.rgb = C("FFFFFF")


def row(s, names, x, y, body_h, step_frac=0.9, drop=0.28, dark=False):
    """Staggered, slightly overlapping phones, leftmost in front, numbered 1, 2, 3."""
    names = [n for n in names if n]
    # place right-to-left so the leftmost ends up on top
    lefts, cur = [], x
    for i, n in enumerate(names):
        im = Image.open(shot_path(n))
        w = (600 + 32) / (round(im.height * 600 / im.width) + 32) * body_h
        lefts.append((cur, w))
        cur += w * step_frac
    boxes = [None] * len(names)
    for i in reversed(range(len(names))):
        lx, w = lefts[i]
        boxes[i] = phone(s, names[i], lx, y + i * drop, body_h)
    for i, b in enumerate(boxes):
        badge(s, i + 1, b["x"] + min(b["w"] * 0.5, b["w"] * step_frac * 0.5), b["y"] + b["h"] + 0.26,
              fill=N["pen"] if dark else L["pen"])
    return boxes


def glow(path, w=1600, h=1200, color=(102, 118, 232)):
    im = Image.new("RGBA", (w, h), (0, 0, 0, 0))
    ImageDraw.Draw(im).ellipse((w * .15, h * .15, w * .85, h * .85), fill=color + (150,))
    im = im.filter(ImageFilter.GaussianBlur(170))
    im.save(path)
    return path


# ================================================================ slides
def new(n, dark=False, trans="push"):
    s = prs.slides.add_slide(BLANK)
    background(s, N["ground"] if dark else L["ground"])
    return s


# ---- 1 title
s = new(1, True)
g = glow(BUILD + r"\glow1.png")
s.shapes.add_picture(g, Inches(-2.2), Inches(0.6), Inches(8.5), Inches(6.4))
rect(s, 0.8, 1.55, 0.55, 0.07, N["pen"])
text(s, 0.8, 1.72, 6, 0.3, "FINAL-YEAR PROJECT", 13, N["penDeep"], True)
rect(s, 0.72, 2.2, 5.15, 1.15, N["hi"], radius=0.14)
text(s, 0.95, 2.2, 5.0, 1.15, "NoteNest", 60, "1B1E2B", font=HEAD, anchor=MSO_ANCHOR.MIDDLE)
text(s, 0.8, 3.7, 5.8, 1.0, "Notes, filed by course. Revision that finds you.", 24, N["ink"])
text(s, 0.8, 5.55, 5, 0.4, AUTHOR, 20, N["ink"], True)
text(s, 0.8, 5.95, 5, 0.4, "Supervisor review · 2026", 15, N["inkSoft"])
pic = s.shapes.add_picture(GIFS + r"\opening.gif", Inches(8.6), Inches(0.55), Inches(3.5), Inches(6.22))
pic.line.color.rgb = C(N["rule"])
pic.line.width = Pt(1)
rail(s, 1, True)
notes(s, "Good morning. This is NoteNest, my final-year project: a notebook for students that files every note under its course "
         "and brings back the ones you are about to forget. The animation on the right is the app's own opening, drawn the same way "
         "as in the code: the page arrives, the corner folds, the line you meant to revise is marked, and the app opens underneath. "
         "I will walk through the real application, screen by screen, starting where a student starts: the sign-in screen.")
transition(s, "fade")

# ---- 2 problem
s = new(2)
heading(s, 2, "THE PROBLEM AND THE IDEA", "Exam week should be for studying.")
srcs = [("Camera roll", "tintWarm", "warmDeep"), ("Chat apps", "tintRed", "redDeep"), ("Downloads", "tintPen", "penDeep"), ("Paper", "tintMint", "mintDeep")]
for i, (t, tint, deep) in enumerate(srcs):
    xx = 0.8 + (0.35 if i % 2 else 0)
    rect(s, xx, 3.0 + i * 0.95, 3.2, 0.74, L[tint], radius=0.2)
    text(s, xx + 0.3, 3.0 + i * 0.95, 2.7, 0.74, t, 20, L[deep], True, anchor=MSO_ANCHOR.MIDDLE)
a = rect(s, 4.75, 4.45, 1.0, 0.7, L["pen"], shape=MSO_SHAPE.RIGHT_ARROW)
rect(s, 6.2, 2.85, 6.3, 3.75, L["pen"], radius=0.4)
text(s, 6.7, 3.25, 5.4, 0.9, "NoteNest", 44, "FFFFFF", font=HEAD)
text(s, 6.7, 4.35, 5.4, 1.6, ["Organised by course.", "Works with no connection."], 24, L["penPale"], space_after=8)
rect(s, 6.7, 5.75, 1.3, 0.12, L["hi"], radius=0.06)
rail(s, 2)
notes(s, "A student's material is scattered. Photos of the board are in the camera roll, slides arrive in chat apps, PDFs sit in downloads, "
         "and some of it is still on paper. So exam week is spent searching instead of studying. NoteNest puts all of it in one place, "
         "organised by course, and it works with no connection at all.")
transition(s, "push")

# ---- 3 getting in
s = new(3)
heading(s, 3, "GETTING IN", "Sign in with email or Google.")
cards(s, ["Email and password", "Or one tap with Google", "An account works offline too"], y=3.1)
row(s, [first("01_login"), first("02_register"), first("03_google_login_button", "03_google")], 6.4, 0.85, 4.4)
rail(s, 3)
notes(s, "Phone one is the sign-in screen. Phone two is creating an account: the password checklist ticks as you type, and there is a switch for the cloud. "
         "Phone three is the same screen on the Android phone, with the Continue with Google button. An account works offline too. "
         "The notebook lives on the phone, and the cloud account is an extra for sharing, chat and classes.")
transition(s, "push")

# ---- 4 setup
s = new(4)
heading(s, 4, "SETTING UP, ONCE", "Tell it your degree once.")
cards(s, ["Start and finish dates", "It works out your semester", "Courses keep their semester"], y=3.1)
row(s, [first("04_setup_degree"), first("05_add_course")], 6.8, 0.8, 5.35, step_frac=1.0, drop=0.3)
rail(s, 4)
notes(s, "Phone one is the degree sheet. The student says how the year is divided, when the degree started and roughly when it finishes, and the app works out "
         "which semester today falls in: here, semester five of eight. Phone two is adding the first course. A course is stamped with the semester it was made in, "
         "so when a semester ends it becomes history by itself.")
transition(s, "push")

# ---- 5 today (callouts)
s = new(5)
heading(s, 5, "TODAY", "Today, at a glance.")
text(s, 0.8, 3.1, 4.3, 1.2, "Tap any card to go straight in.", 18, L["inkSoft"])
CROP = 2150
bx, by, bh = 5.6, 0.7, 6.1
b = phone(s, "06_today_tall", bx, by, bh, crop_h=CROP)
marks = [("Revision card", 0.151), ("Course row", 0.292), ("To-do card", 0.496), ("Tools", 0.842), ("Timer", 0.941)]
for i, (lab, fy) in enumerate(marks):
    dx, dy = b["x"] + b["w"] * 0.9, b["y"] + 0.12 + (b["h"] - 0.24) * fy
    lx, ly = 8.6, 1.35 + i * 1.1
    c = s.shapes.add_connector(MSO_CONNECTOR.STRAIGHT, Inches(dx), Inches(dy), Inches(lx - 0.12), Inches(ly + 0.2))
    c.line.color.rgb = C(L["pen"])
    c.line.width = Pt(1.25)
    badge(s, i + 1, dx, dy, d=0.3)
    badge(s, i + 1, lx + 0.15, ly + 0.2, d=0.3)
    text(s, lx + 0.45, ly, 3.6, 0.4, lab, 20, L["ink"], True, anchor=MSO_ANCHOR.MIDDLE)
rail(s, 5)
notes(s, "This is the home screen with real data in it. One: the revision card says how many notes are due today and opens the review. "
         "Two: the course row, one card per course with its note count. Three: today's to-do list, on the same screen. "
         "Four: the tools, a cover page for assignments and a Word and PDF converter. Five: the study timer, a 25-minute focus session.")
transition(s, "push")

# ---- 6 writing
s = new(6)
heading(s, 6, "WRITING A NOTE", "Write it. File it. Mark it.")
cards(s, ["Title, course, topic, tags", "Bold, highlight, lists", "New, Read, Review, Mastered"], y=3.1)
row(s, [first("07_notes_list"), first("08_editor"), first("08b_note_view")], 6.9, 0.8, 4.6)
rail(s, 6)
notes(s, "Phone one is the Notes tab, filtered by course, with the newest first. Phone two is the editor: a title, the course, a topic, tags, "
         "and a formatting bar for bold, highlight, headings and lists. It saves as you type. Phone three is the note as you read it back, "
         "with the study status: New, Read, Review or Mastered. That status is what drives revision.")
transition(s, "push")

# ---- 7 more than text
s = new(7)
heading(s, 7, "MORE THAN TEXT", "Photo, PDF and voice. On the note.")
rich = [first("09_attachments"), first("10_pdf_viewer"), first("11_search")]
if all(rich):
    cards(s, ["Attached to the note itself", "PDF text is read on the phone", "Search finds words inside slides"], y=3.1)
    row(s, rich, 6.9, 0.8, 4.6)
else:
    cards(s, ["Attached to the note itself", "PDF text is read on the phone", "Search finds words inside slides"], y=3.1)
    b = phone(s, "08_editor", 7.2, 0.75, 5.7)
    for i, (lab, fx, fy) in enumerate([("Photo", .30, .886), ("PDF", .76, .886), ("Voice", .30, .952), ("Dictation", .76, .952)]):
        badge(s, i + 1, b["x"] + b["w"] * fx, b["y"] + b["h"] * fy, d=0.3)
        rect(s, 10.45, 1.35 + i * 0.95, 2.2, 0.62, L["tintPen"], radius=0.18)
        text(s, 10.75, 1.35 + i * 0.95, 1.8, 0.62, f"{i + 1}   {lab}", 18, L["penDeep"], True, anchor=MSO_ANCHOR.MIDDLE)
rail(s, 7)
notes(s, "A note is not only text. At the bottom of the editor are the four ways to add more: photograph a page of handwriting, add a PDF, record the lecture, "
         "or dictate and let it become text. The photo, the PDF and the voice recording live on the note itself, not in a separate gallery. "
         "PDF text is extracted on the phone, so the search finds words printed inside a slide, not only words you typed.")
transition(s, "push")

# ---- 8 courses
s = new(8)
heading(s, 8, "COURSES AND SEMESTERS", "Each semester becomes history.")
cards(s, ["Courses filed by semester", "Finished terms close themselves", "Files sit with their course"], y=3.1)
row(s, [first("12_courses"), first("12b_semesters"), first("13_course_files")], 6.9 if first("13_course_files") else 6.8, 0.8,
    4.6 if first("13_course_files") else 5.35, step_frac=0.9 if first("13_course_files") else 1.0)
rail(s, 8)
notes(s, "Phone one is the course list: every course with its code, note count and semester. Phone two is the semester page, which shows the degree, "
         "semester five of eight, and the four courses that belong to it. When a semester finishes it becomes history by itself and its courses move under it. "
         "Files that belong to a course, like slides and past papers, sit with that course.")
transition(s, "push")

# ---- 9 revision
s = new(9)
heading(s, 9, "REVISION THAT WORKS", "A few notes a day.")
text(s, 0.8, 3.0, 5.0, 1.0, ["Forgot: back to 1 day.", "Got it: the gap grows."], 20, L["ink"], space_after=10)
rect(s, 0.8, 3.95, 5.6, 0.8, L["tintMint"], radius=0.2)
text(s, 1.1, 3.95, 5.2, 0.8, "1, 3, 7, 14, then 30 days", 20, L["mintDeep"], True, anchor=MSO_ANCHOR.MIDDLE)
g = s.shapes.add_picture(GIFS + r"\spacing.gif", Inches(0.8), Inches(4.95), Inches(5.9), Inches(5.9 * 330 / 1000))
phone(s, "14_review", 8.3, 0.75, 5.8)
badge(s, 1, 8.3 + 1.4, 0.75 + 5.8 + 0.28)
rail(s, 9)
notes(s, "This is the Review today screen. The app shows the title and asks you to remember what the note says, then you show it and answer honestly: "
         "Forgot, Hard or Got it. Each button says when the note will come back. Forgot puts it back to one day. Got it makes the gap longer: "
         "one day, then three, seven, fourteen and thirty, and after that the note counts as mastered. The animation shows the gaps growing. "
         "So revision is a few notes a day, each one just before you would forget it.")
transition(s, "push")

# ---- 10 exams and to-dos
s = new(10)
heading(s, 10, "EXAMS AND TO-DOS", "Count the days. Do the work.")
cards(s, ["Exam countdown, in days", "Notes still not mastered", "A to-do page for the week"], y=3.1)
row(s, [first("15_exams"), first("16_tasks")], 6.8, 0.8, 5.35, step_frac=1.0, drop=0.3)
rail(s, 10)
notes(s, "Phone one is exam mode. A date is added once, as an exam, a quiz or an assignment, and the ring counts the days down. "
         "Beside it the app says how many notes for that course are still not mastered, here none of two, and it lists them in the order to revise. "
         "Phone two is the to-do page: a week strip, today's list on ruled paper, and tasks that can be ticked off.")
transition(s, "push")

# ---- 11 people
s = new(11)
heading(s, 11, "CLASSMATES AND CLASSES", "Share a note. Run a class.")
cards(s, ["Send a note by exact email", "They accept. Your name stays", "Group chat, and teacher classes"], y=3.1)
row(s, [first("17_people", "17_people_PARTIAL_needs_cloud"), first("18_classes")], 7.6, 0.8, 5.35, step_frac=1.0, drop=0.3)
rail(s, 11)
notes(s, "The People tab is the cloud side, and it is optional. A student sends a note to a classmate by their exact email address. "
         "The other person has to accept it, and the sender's name stays on the note. There are group chats, and a teacher can run a class and post work. "
         "The screen shown is the People tab with no cloud account connected: it asks the student to connect one first, because everything here needs an account. "
         "Nothing else in the app depends on it.")
transition(s, "push")

# ---- 12 safety and status
s = new(12, True)
g = glow(BUILD + r"\glow12.png", color=(74, 91, 212))
s.shapes.add_picture(g, Inches(-1.5), Inches(0.5), Inches(8), Inches(6.5))
rect(s, 0.8, 0.55, 0.55, 0.07, N["pen"])
text(s, 0.8, 0.72, 6, 0.3, "12  ·  SAFETY, AND WHERE IT STANDS", 13, N["penDeep"], True)
safe = [first("19_settings"), first("20_lock"), first("21_drive_backup", "22_dark"), first("22_dark") if first("21_drive_backup") else None]
row(s, safe[:3] if not safe[3] else safe, 0.8, 1.25, 4.5, step_frac=0.9, drop=0.25, dark=True)
tiles = [("50,152", "lines of Dart in 141 files", "tintPen", "penDeep"), ("283", "automated tests, all passing", "tintMint", "mintDeep"),
         ("12", "tables, schema v14", "tintWarm", "warmDeep"), ("7", "security-audit findings fixed", "tintRed", "redDeep")]
for i, (big, small, t, d) in enumerate(tiles):
    x = 7.1 + (i % 2) * 2.95
    y = 1.25 + (i // 2) * 1.85
    rect(s, x, y, 2.75, 1.65, N[t], radius=0.28)
    text(s, x + 0.25, y + 0.16, 2.3, 0.8, big, 40, N[d], font=HEAD)
    text(s, x + 0.25, y + 1.0, 2.3, 0.6, small, 15, N["ink"])
rect(s, 7.1, 5.0, 5.7, 0.95, N["card"], radius=0.22, line=N["rule"])
text(s, 7.35, 5.0, 5.3, 0.95, "Not yet: sync between phones. Rules tested by hand. Android only. Unpublished.", 16, N["inkSoft"], anchor=MSO_ANCHOR.MIDDLE)
text(s, 7.1, 6.1, 5.7, 0.8, "Thank you", 40, N["ink"], font=HEAD)
rail(s, 12, True)
notes(s, "Safety first. Phone one is Settings. Phone two is the app lock: a four-digit PIN, and a fingerprint on phones that have one. "
         "Phone three is the dark theme. Backup goes to the student's own Google Drive. Now where it stands. About fifty thousand lines of Dart in 141 files, "
         "283 automated tests and all of them pass, a database of 12 tables at schema version 14, and the October security audit fixed seven findings. "
         "To be honest about the limits: notes do not sync between phones yet, the Firestore security rules were tested by hand and not by an automated suite, "
         "it is Android only, and it is not yet published. Thank you. I am happy to take questions.")
transition(s, "fade")

prs.save(OUT)
print("saved", OUT)
