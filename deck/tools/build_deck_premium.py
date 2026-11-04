"""Builds deck/NoteNest_Presentation_Premium.pptx: same 12 slides and notes as NoteNest_Presentation.pptx,
redrawn as a black / white / highlighter-yellow editorial deck with a different transition on every slide.
Run with the Python 3.12 that has python-pptx, lxml and Pillow (see memory deck-2026-10-24).
"""
import os
from lxml import etree
from PIL import Image
from pptx import Presentation
from pptx.util import Inches, Pt
from pptx.dml.color import RGBColor
from pptx.enum.shapes import MSO_SHAPE, MSO_CONNECTOR
from pptx.enum.text import PP_ALIGN, MSO_ANCHOR
from pptx.enum.dml import MSO_LINE

from assets import phone_frame

D = r"C:\project\notenest\deck"
SHOTS, BUILD, GIFS = D + r"\shots", D + r"\build", D + r"\gifs"
SRC = D + r"\NoteNest_Presentation.pptx"
OUT = D + r"\NoteNest_Presentation_Premium.pptx"
AUTHOR = "Md. Sarowar Hossain"
ICON = "C:/project/notenest/android/app/src/main/res/mipmap-xxxhdpi/ic_launcher.png"

K, K2, KLINE = "0B0C10", "16181F", "2C2F3B"
W, Y = "FFFFFF", "FFD84D"
GREY_D, GREY_L, LINE_L = "A3A8B8", "5A5F70", "D9DBE3"
HEAD, BODY = "Cambria", "Calibri"
TOTAL = 12

prs = Presentation()
prs.slide_width, prs.slide_height = Inches(13.333), Inches(7.5)
BLANK = prs.slide_layouts[6]


def C(h):
    return RGBColor.from_string(h)


def rect(s, x, y, w, h, fill=None, radius=None, line=None, lw=1.0, shape=None):
    shp = s.shapes.add_shape(shape or (MSO_SHAPE.ROUNDED_RECTANGLE if radius else MSO_SHAPE.RECTANGLE),
                             Inches(x), Inches(y), Inches(w), Inches(h))
    if radius and shape is None:
        shp.adjustments[0] = min(0.5, radius / min(w, h))
    if fill:
        shp.fill.solid()
        shp.fill.fore_color.rgb = C(fill)
    else:
        shp.fill.background()
    if line:
        shp.line.color.rgb = C(line)
        shp.line.width = Pt(lw)
    else:
        shp.line.fill.background()
    shp.shadow.inherit = False
    return shp


def text(s, x, y, w, h, t, size=16, color=K, bold=False, font=BODY, align=PP_ALIGN.LEFT,
         anchor=MSO_ANCHOR.TOP, space_after=0, italic=False, spc=None, ls=None):
    tb = s.shapes.add_textbox(Inches(x), Inches(y), Inches(w), Inches(h))
    tf = tb.text_frame
    tf.word_wrap = True
    tf.margin_left = tf.margin_right = tf.margin_top = tf.margin_bottom = 0
    tf.vertical_anchor = anchor
    for i, ln in enumerate(t if isinstance(t, list) else [t]):
        p = tf.paragraphs[0] if i == 0 else tf.add_paragraph()
        p.alignment = align
        p.space_after = Pt(space_after)
        if ls:
            p.line_spacing = ls
        r = p.add_run()
        r.text = ln
        r.font.size, r.font.bold, r.font.italic, r.font.name = Pt(size), bold, italic, font
        r.font.color.rgb = C(color)
        if spc:
            r._r.get_or_add_rPr().set("spc", str(spc))
    return tb


def hair(s, x1, y1, x2, y2, color, w=0.75, dash=None):
    c = s.shapes.add_connector(MSO_CONNECTOR.STRAIGHT, Inches(x1), Inches(y1), Inches(x2), Inches(y2))
    c.line.color.rgb = C(color)
    c.line.width = Pt(w)
    if dash:
        c.line.dash_style = dash
    return c


def arrow(s, x1, y1, x2, y2, color):
    c = hair(s, x1, y1, x2, y2, color, 2, MSO_LINE.DASH)
    ln = c.line._get_or_add_ln()
    ns = "http://schemas.openxmlformats.org/drawingml/2006/main"
    etree.SubElement(ln, f"{{{ns}}}tailEnd").set("type", "triangle")


def blank(s, x, y, w, label, size=15, color=GREY_L, line=GREY_L, lw=None, stacked=False):
    """A label followed by a dotted underline to be filled in by hand."""
    lw = lw if lw is not None else len(label) * size * 0.0068 + 0.2
    if stacked:
        text(s, x, y, w, 0.3, label, size, color, anchor=MSO_ANCHOR.BOTTOM)
        lw, y = 0, y + 0.3
    else:
        text(s, x, y, lw, 0.3, label, size, color, anchor=MSO_ANCHOR.BOTTOM)
    hair(s, x + lw, y + 0.29, x + w, y + 0.29, line, 1.5, MSO_LINE.ROUND_DOT)


def new(bg):
    s = prs.slides.add_slide(BLANK)
    s.background.fill.solid()
    s.background.fill.fore_color.rgb = C(bg)
    return s


def chrome(s, n, label, dark, page_dark=None):
    """Section label top-left, page count top-right. page_dark: the right edge sits on a dark panel."""
    page_dark = dark if page_dark is None else page_dark
    text(s, 0.7, 0.45, 7, 0.3, f"{n:02d}  —  {label}", 12, Y if dark else K, True, spc=200)
    text(s, 11.3, 0.45, 1.35, 0.3, f"{n:02d} / {TOTAL}", 12, GREY_D if page_dark else GREY_L, align=PP_ALIGN.RIGHT)


def title(s, t, dark, w=11.9, y=0.95, size=44):
    text(s, 0.7, y, w, 1.3, t, size, W if dark else K, True, HEAD, ls=0.95)


def notes_from_source(n_slides):
    src = Presentation(SRC)
    for i, sl in enumerate(prs.slides):
        sl.notes_slide.notes_text_frame.text = src.slides[i].notes_slide.notes_text_frame.text


def transition(s, tag, **attrs):
    ns = "http://schemas.openxmlformats.org/presentationml/2006/main"
    tr = etree.SubElement(s._element, f"{{{ns}}}transition")
    tr.set("spd", "med")
    el = etree.SubElement(tr, f"{{{ns}}}{tag}")
    for k, v in attrs.items():
        el.set(k, v)


# ---------------------------------------------------------------- phones
def shot_path(name):
    p = os.path.join(SHOTS, name + ".png")
    return p if os.path.exists(p) else None


def phone_w(name, body_h):
    im = Image.open(shot_path(name))
    return (600 + 32) / (round(im.height * 600 / im.width) + 32) * body_h


def phone(s, name, x, y, body_h):
    """Framed screenshot; (x, y) is the top-left of the phone body."""
    out = os.path.join(BUILD, f"phone_{name}.png")
    size, pad = phone_frame(shot_path(name), out, shadow=True)
    k = body_h / (size[1] - 2 * pad)
    s.shapes.add_picture(out, Inches(x - pad * k), Inches(y - pad * k), Inches(size[0] * k), Inches(size[1] * k))
    return phone_w(name, body_h)


def row(s, names, x, y, body_h, step_frac=0.9, drop=0.28):
    """Staggered, overlapping phones; the leftmost ends up in front."""
    xs, cur = [], x
    for n in names:
        xs.append(cur)
        cur += phone_w(n, body_h) * step_frac
    for i in reversed(range(len(names))):
        phone(s, names[i], xs[i], y + i * drop, body_h)


# ================================================================ 1 title
s = new(K)
for d in (7.6, 5.4):
    cx, cy = 10.6, 3.75
    rect(s, cx - d / 2, cy - d / 2, d, d, None, line=KLINE, lw=1, shape=MSO_SHAPE.OVAL)
pic = s.shapes.add_picture(GIFS + r"\opening.gif", Inches(9.0), Inches(0.9), Inches(3.2), Inches(3.2 * 6.22 / 3.5))
pic.line.color.rgb = C(KLINE)
pic.line.width = Pt(1)
s.shapes.add_picture(ICON, Inches(0.7), Inches(0.75), Inches(0.62), Inches(0.62))
text(s, 1.55, 0.75, 5, 0.62, "FINAL-YEAR PROJECT", 12, Y, True, spc=200, anchor=MSO_ANCHOR.MIDDLE)
text(s, 0.7, 1.75, 7.8, 1.6, "NoteNest", 96, W, True, HEAD)
text(s, 0.7, 3.55, 7.0, 1.2, "Everything you study, in one place — and it works offline.", 28, Y, False, HEAD, italic=True, ls=1.0)
text(s, 0.7, 4.95, 6, 0.4, AUTHOR, 22, W, True)
hair(s, 0.7, 5.5, 8.0, 5.5, KLINE)
blank(s, 0.7, 5.65, 3.4, "Student ID", color=GREY_D, line=GREY_D)
blank(s, 4.6, 5.65, 3.4, "Department", color=GREY_D, line=GREY_D)
blank(s, 0.7, 6.25, 3.4, "Supervisor", color=GREY_D, line=GREY_D)
blank(s, 4.6, 6.25, 3.4, "Submission date", color=GREY_D, line=GREY_D)
transition(s, "fade", thruBlk="1")

# ================================================================ 2 problem
s = new(W)
rect(s, 7.6, 0, 5.733, 7.5, K)
chrome(s, 2, "THE PROBLEM", False, True)
title(s, "Exam week should be for studying.", False, w=6.5, size=44)
text(s, 0.7, 3.3, 6.0, 1.0, "Handwritten notes, typed notes, slides as PDFs, whiteboard photos, a recording — all for one lecture.", 17, GREY_L)
pills = [("Camera roll", "FFF3CF", 0.7, 4.55, -3), ("Chat apps", "FFE3E6", 3.5, 4.75, 2),
         ("Downloads folder", "E8EBFC", 0.95, 5.45, 3), ("Paper", "DFF6EC", 3.75, 5.6, -2)]
for t, fill, x, y, rot in pills:
    p = rect(s, x, y, 2.55, 0.58, fill, radius=0.29)
    p.rotation = rot
    tf = p.text_frame
    tf.margin_left = tf.margin_right = 0
    tf.vertical_anchor = MSO_ANCHOR.MIDDLE
    para = tf.paragraphs[0]
    para.alignment = PP_ALIGN.CENTER
    r = para.add_run()
    r.text = t
    r.font.size, r.font.bold, r.font.name = Pt(17), True, BODY
    r.font.color.rgb = C(K)
blank(s, 0.7, 6.55, 6.4, "[statistic — to be cited]", size=14, stacked=False)
text(s, 8.2, 1.3, 4.6, 3.3, "None of these four places knows the items belong to the same lecture.", 30, W, True, HEAD, ls=1.0)
text(s, 8.2, 4.7, 4.6, 1.3, "So exam week is spent searching instead of studying.", 20, Y, False, HEAD, italic=True)
transition(s, "cover", dir="l")

# ================================================================ 3 solution
s = new(K)
chrome(s, 3, "THE SOLUTION", True)
rect(s, 7.8, 0.55, 6.4, 6.4, Y, shape=MSO_SHAPE.OVAL)
phone(s, "06_today", 9.55, 0.85, 5.8)
title(s, "One notebook, even offline.", True, w=6.8)
for i, (word, x, w) in enumerate([("Semester", 0.7, 1.8), ("Course", 3.15, 1.5), ("Note", 5.3, 1.2)]):
    text(s, x, 2.7, w, 0.6, word, 30, W, False, HEAD, italic=True)
    if i < 2:
        text(s, x + w + 0.02, 2.7, 0.5, 0.6, "→", 26, Y, font=BODY)
text(s, 0.7, 3.6, 6.4, 0.8, "Every note belongs to a course, every course to a semester. No connection needed.", 17, GREY_D)
text(s, 0.7, 4.5, 6, 0.3, "WHAT MAKES IT DIFFERENT", 12, Y, True, spc=200)
for i, t in enumerate(["Organised by the academic calendar, not by folders", "The device is the source of truth, not a server"]):
    y = 4.9 + i * 0.85
    hair(s, 0.7, y, 7.1, y, KLINE)
    text(s, 0.7, y + 0.1, 0.7, 0.6, f"0{i + 1}", 22, Y, False, HEAD, anchor=MSO_ANCHOR.MIDDLE)
    text(s, 1.5, y + 0.1, 5.6, 0.6, t, 18, W, anchor=MSO_ANCHOR.MIDDLE)
hair(s, 0.7, 6.6, 7.1, 6.6, KLINE)
transition(s, "split", orient="vert", dir="out")

# ================================================================ 4 features
s = new(W)
rect(s, 8.3, 0, 5.033, 7.5, K)
chrome(s, 4, "KEY FEATURES", False, True)
title(s, "What it does.", False, w=7)
feats = ["Notes filed under courses", "Photos, PDFs and voice on one note", "Search that reaches inside PDF text", "Spaced revision",
         "Exam countdown and to-dos", "Cover-page generator", "Word and PDF conversion", "Share a note with a classmate",
         "Group chat and classes", "Backup to your own Google Drive", "PIN and fingerprint lock", "Bangla and English, light and dark"]
for i, f in enumerate(feats):
    col, r = i // 6, i % 6
    x, y = 0.7 + col * 3.75, 2.15 + r * 0.74
    hair(s, x, y, x + 3.5, y, LINE_L)
    text(s, x, y + 0.08, 0.5, 0.58, f"{i + 1:02d}", 15, GREY_L, True, HEAD, anchor=MSO_ANCHOR.MIDDLE)
    text(s, x + 0.55, y + 0.08, 2.95, 0.58, f, 16, K, anchor=MSO_ANCHOR.MIDDLE)
hair(s, 0.7, 6.59, 4.2, 6.59, LINE_L)
hair(s, 4.45, 6.59, 7.95, 6.59, LINE_L)
row(s, ["07_notes_list", "15_exams", "14_review"], 8.75, 0.8, 3.4, step_frac=0.82, drop=0.15)
rect(s, 8.75, 4.95, 4.05, 1.4, "F6F7FB", radius=0.15)
s.shapes.add_picture(GIFS + r"\spacing.gif", Inches(8.85), Inches(5.0), Inches(3.85), Inches(3.85 * 330 / 1000))
text(s, 8.75, 6.55, 4.05, 0.3, "Spaced revision: 1, 3, 7, 14, then 30 days", 14, GREY_D)
transition(s, "wipe", dir="r")

# ================================================================ 5 walkthrough
s = new(K)
chrome(s, 5, "HOW IT WORKS", True)
title(s, "Five screens, start to finish.", True)
steps = ["Sign in", "Degree setup", "Today", "Note editor, with attach bar", "Review"]
names = ["01_login", "04_setup_degree", "06_today", "08_editor", "14_review"]
for i, (st, nm) in enumerate(zip(steps, names)):
    cx = 0.7 + i * 2.45
    text(s, cx, 1.95, 1.2, 0.7, f"{i + 1}", 44, Y, False, HEAD, italic=True)
    text(s, cx, 2.75, 2.2, 0.6, st, 16, W, True)
    phone(s, nm, cx, 3.6, 4.7)
transition(s, "push", dir="u")

# ================================================================ 6 users
s = new(W)
rect(s, 8.4, 0, 4.933, 7.5, Y)
chrome(s, 6, "TARGET USERS", False, False)
title(s, "Who it is for.", False, w=7)
rows6 = [("PRIMARY", "University students who take notes on a phone and study for scheduled exams."),
         ("SECONDARY", "Teachers, through the class feature."),
         ("WHY THESE USERS", "The app is built around semesters and exams, which only matter to people on an academic calendar.")]
for i, (lab, body) in enumerate(rows6):
    y = 2.2 + i * 1.3
    hair(s, 0.7, y, 7.7, y, LINE_L)
    text(s, 0.7, y + 0.2, 2.2, 0.3, lab, 12, GREY_L, True, spc=200)
    text(s, 3.0, y + 0.15, 4.7, 1.1, body, 20, K, False, HEAD)
hair(s, 0.7, 6.1, 7.7, 6.1, LINE_L)
blank(s, 0.7, 6.3, 7.0, "[number of students — to be cited from UGC / university statistics]", size=14, stacked=True)
pw = phone_w("12b_semesters", 5.8)
phone(s, "12b_semesters", 8.4 + (4.933 - pw) / 2, 0.85, 5.8)
transition(s, "pull", dir="l")

# ================================================================ 7 technology
s = new(K)
chrome(s, 7, "TECHNOLOGY", True)
title(s, "How it is built.", True, w=7)
rect(s, 0.7, 2.0, 5.2, 3.7, None, radius=0.2, line=KLINE, lw=1.25)
text(s, 1.0, 2.2, 4.6, 0.3, "ON THE STUDENT'S PHONE", 12, Y, True, spc=200)
rect(s, 1.0, 2.7, 4.6, 1.05, K2, radius=0.15)
text(s, 1.3, 2.7, 4.0, 1.05, ["Flutter and Dart", "One codebase"], 18, W, anchor=MSO_ANCHOR.MIDDLE)
rect(s, 1.0, 3.95, 4.6, 1.55, Y, radius=0.15)
text(s, 1.3, 4.05, 4.1, 0.4, "SQLite through sqflite", 20, K, True, HEAD)
text(s, 1.3, 4.5, 4.1, 0.95, ["12 tables · schema version 14", "Foreign keys on", "The source of truth"], 15, K)
rect(s, 8.4, 2.0, 4.2, 2.05, None, radius=0.15, line=KLINE, lw=1.25)
text(s, 8.7, 2.15, 3.7, 0.4, "Firebase · free Spark plan", 18, Y, True, HEAD)
text(s, 8.7, 2.65, 3.7, 1.35, ["Authentication", "Firestore", "Cloud Messaging", "Optional: the app opens without it"], 15, W)
rect(s, 8.4, 4.3, 4.2, 1.4, None, radius=0.15, line=KLINE, lw=1.25)
text(s, 8.7, 4.43, 3.7, 0.4, "The student's own Google Drive", 17, Y, True, HEAD)
text(s, 8.7, 4.9, 3.7, 0.7, ["Attachments and backup", "drive.file scope only"], 15, W)
arrow(s, 6.05, 3.15, 8.25, 3.15, Y)
text(s, 6.0, 2.7, 2.3, 0.35, "accounts, chat, classes", 14, GREY_D, align=PP_ALIGN.CENTER)
arrow(s, 6.05, 5.0, 8.25, 5.0, Y)
text(s, 6.0, 4.55, 2.3, 0.35, "files, backup", 14, GREY_D, align=PP_ALIGN.CENTER)
rect(s, 0.7, 6.0, 11.9, 0.85, Y, radius=0.12)
text(s, 1.0, 6.0, 11.3, 0.85, "There is no server of our own, so the Firestore security rules carry all of the authorisation.", 18, K, True, anchor=MSO_ANCHOR.MIDDLE)
transition(s, "zoom", dir="in")

# ================================================================ 8 comparison
s = new(W)
chrome(s, 8, "COMPARED WITH WHAT EXISTS", False)
title(s, "Compared with what exists.", False)
for x, t in [(0.7, "PRODUCT"), (3.1, "DOES WELL"), (6.9, "WHY IT DOES NOT SOLVE THIS")]:
    text(s, x, 1.85, 5, 0.3, t, 12, GREY_L, True, spc=200)
rows8 = [("Google Keep", "Fast, simple notes with colour and labels", "Organised by colour and label, with no idea of a course or an exam."),
         ("Evernote", "Powerful search, built for professional work", "Made for professional work; the free plan has limits."),
         ("Notion", "Flexible pages and databases", "Built online-first; working offline is limited."),
         ("Google Classroom", "Teachers post work, students hand it in", "A teacher's tool, not a notebook for the student's own notes."),
         ("Paper notebook", "No battery, no signal", "Cannot be searched, and holds no PDF or recording.")]
for i, (a, b, c) in enumerate(rows8):
    y = 2.25 + i * 0.74
    hair(s, 0.7, y, 12.6, y, LINE_L)
    text(s, 0.7, y, 2.3, 0.74, a, 19, K, True, HEAD, anchor=MSO_ANCHOR.MIDDLE)
    text(s, 3.1, y, 3.5, 0.74, b, 15, GREY_L, anchor=MSO_ANCHOR.MIDDLE)
    text(s, 6.9, y, 5.7, 0.74, c, 15, K, anchor=MSO_ANCHOR.MIDDLE)
hair(s, 0.7, 5.95, 12.6, 5.95, LINE_L)
rect(s, 0.7, 6.2, 11.9, 0.75, K, radius=0.12)
for i, t in enumerate(["Organised by the academic calendar", "Offline is the normal state, not a failure"]):
    x = 1.0 + i * 5.9
    text(s, x, 6.2, 0.4, 0.75, f"{i + 1}", 22, Y, False, HEAD, italic=True, anchor=MSO_ANCHOR.MIDDLE)
    text(s, x + 0.45, 6.2, 5.2, 0.75, t, 16, W, True, anchor=MSO_ANCHOR.MIDDLE)
transition(s, "wipe", dir="d")

# ================================================================ 9 cost
s = new(K)
chrome(s, 9, "COST AND SUSTAINABILITY", True)
title(s, "Free, and cheap to run.", True, w=7)
stm = ["Free to use: no advertising, no subscription.", "Firebase's free plan carries accounts, chat and classes.",
       "Attachments go to each student's own Google Drive, so the storage cost does not grow as users are added."]
ys, hs = [2.2, 3.35, 4.5], [1.15, 1.15, 1.55]
for i, (t, y, h) in enumerate(zip(stm, ys, hs)):
    hair(s, 0.7, y, 6.7, y, KLINE)
    text(s, 0.7, y + 0.15, 0.6, 0.5, f"0{i + 1}", 20, Y, False, HEAD)
    text(s, 1.4, y + 0.15, 5.3, h - 0.2, t, 20, W, False, HEAD)
hair(s, 0.7, 6.05, 6.7, 6.05, KLINE)
rect(s, 7.3, 1.9, 5.3, 2.6, None, radius=0.15, line=KLINE, lw=1.25)
text(s, 7.6, 2.1, 4.8, 0.3, "THE REAL LIMITS OF THE FREE (SPARK) PLAN", 12, Y, True, spc=100)
text(s, 7.6, 2.6, 4.8, 1.85, ["No Cloud Storage.", "No Cloud Functions; the push-notification function in the project needs the paid plan.", "Daily Firestore quotas."],
     16, W, space_after=8)
rect(s, 7.3, 4.7, 5.3, 2.15, Y, radius=0.15)
text(s, 7.6, 4.9, 4.8, 0.3, "IF IT EVER OUTGREW THE FREE PLAN", 12, "3A3300", True, spc=100)
text(s, 7.6, 5.35, 4.8, 0.6, "The next step would be the paid Blaze plan.", 18, K, True, HEAD)
blank(s, 7.6, 6.15, 4.8, "Estimated monthly cost", size=15, color="3A3300", line=K)
transition(s, "cover", dir="u")

# ================================================================ 10 security
s = new(W)
rect(s, 8.4, 0, 4.933, 7.5, K)
chrome(s, 10, "SECURITY AND PRIVACY", False, True)
title(s, "Security and privacy.", False, w=7)
sec = [("PASSWORDS", "Never stored. Only a salted PBKDF2-HMAC-SHA256 hash, 120,000 rounds."),
       ("ACCOUNTS APART", "Every row of study data carries its owner, and every query filters on it. Two accounts on one phone cannot see each other."),
       ("GOOGLE DRIVE", "drive.file: the app sees only files it created. The rest of the Drive is invisible."),
       ("AUDIT", "My own code, audited before release: nine findings fixed, including a user-directory leak and the weak password hash."),
       ("PLAY REQUIREMENTS", "A privacy policy is published and account deletion is built in.")]
for i, (lab, body) in enumerate(sec):
    y = 1.9 + i * 0.97
    hair(s, 0.7, y, 7.9, y, LINE_L)
    text(s, 0.7, y + 0.15, 2.0, 0.3, lab, 12, GREY_L, True, spc=100)
    text(s, 2.8, y + 0.12, 4.9, 0.85, body, 15, K)
hair(s, 0.7, 6.75, 7.9, 6.75, LINE_L)
row(s, ["20_lock", "19_settings"], 8.85, 0.85, 4.3, step_frac=0.95, drop=0.35)
transition(s, "split", orient="horz", dir="in")

# ================================================================ 11 status
s = new(K)
chrome(s, 11, "WHERE IT STANDS", True)
title(s, "Where it stands, and what is next.", True)
tiles = [("50,152", "lines of Dart in 141 files"), ("283", "automated tests, all passing"),
         ("12 · v14", "tables · schema version"), ("9", "audit findings fixed")]
for i, (big, small) in enumerate(tiles):
    x = 0.7 + i * 3.0
    hair(s, x, 2.0, x + 2.75, 2.0, KLINE)
    text(s, x, 2.1, 2.8, 0.9, big, 48, Y, False, HEAD)
    text(s, x, 3.05, 2.75, 0.4, small, 14, GREY_D)
cols = [(0.7, 3.7, "STATUS", ["Built, signed with an upload key, version 1.0.2. Not yet published on the Play Store."]),
        (4.75, 3.9, "NOT DONE YET", ["Notes do not sync between phones.", "Android only.", "No field testing with real users.",
                                     "The 34 Firestore rules tests are run by hand, not automatically."]),
        (9.0, 3.6, "ROADMAP", ["Sync notes between devices", "Run the rules tests automatically", "Publish on Google Play", "An iOS build",
                               "Measure performance and accessibility"])]
for x, w, lab, items in cols:
    text(s, x, 4.0, w, 0.3, lab, 12, Y, True, spc=200)
    hair(s, x, 4.4, x + w, 4.4, KLINE)
    text(s, x, 4.55, w, 2.4, items, 15, W, space_after=6)
transition(s, "push", dir="l")

# ================================================================ 12 conclusion
s = new(Y)
chrome(s, 12, "CONCLUSION AND CONTACT", False)
text(s, 0.7, 1.3, 6.6, 2.3, "NoteNest keeps a student's work in one place, organised by course, and it works whether or not there is a signal.", 28, K, True, HEAD, ls=1.0)
text(s, 0.7, 3.65, 6.5, 1.2, "Thank you", 72, K, False, HEAD, italic=True)
for i, lab in enumerate(["Email", "Phone", "GitHub"]):
    blank(s, 0.7, 5.0 + i * 0.5, 6.2, lab, size=15, color=K, line=K, lw=0.9)
text(s, 0.7, 6.65, 6.6, 0.35, "Designed and built by Md. Sarowar Hossain", 16, "3A3300")
row(s, ["22_dark", "22b_dark_exam", "20_lock"], 7.4, 1.2, 4.4, step_frac=0.85, drop=0.3)
transition(s, "fade", thruBlk="1")

notes_from_source(TOTAL)
prs.save(OUT)
print("saved", OUT)
