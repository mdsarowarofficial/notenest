

def blank(s, x, y, w, label, size=15, dark=False, lw=None):
    """A label followed by a dotted underline to be filled in by hand."""
    pal = N if dark else L
    lw = lw if lw is not None else len(label) * size * 0.0098 + 0.15
    text(s, x, y, lw, 0.3, label, size, pal["inkSoft"], anchor=MSO_ANCHOR.BOTTOM)
    c = s.shapes.add_connector(MSO_CONNECTOR.STRAIGHT, Inches(x + lw), Inches(y + 0.29), Inches(x + w), Inches(y + 0.29))
    c.line.color.rgb = C("8A90A6")
    c.line.width = Pt(1.5)
    c.line.dash_style = MSO_LINE.ROUND_DOT


def arrow(s, x1, y1, x2, y2, color):
    c = s.shapes.add_connector(MSO_CONNECTOR.STRAIGHT, Inches(x1), Inches(y1), Inches(x2), Inches(y2))
    c.line.color.rgb = C(color)
    c.line.width = Pt(2)
    c.line.dash_style = MSO_LINE.DASH
    ln = c.line._get_or_add_ln()
    ns = "http://schemas.openxmlformats.org/drawingml/2006/main"
    for tag in ("headEnd", "tailEnd"):
        etree.SubElement(ln, f"{{{ns}}}{tag}").set("type", "triangle")
    return c


def card(s, x, y, w, h, title, body, tint="tintPen", deep="penDeep", size=17, tsize=13, dark=False):
    pal = N if dark else L
    rect(s, x, y, w, h, pal[tint], radius=0.2)
    rect(s, x, y + 0.2, 0.07, h - 0.4, pal[deep])
    if title:
        text(s, x + 0.3, y + 0.12, w - 0.5, 0.25, title, tsize, pal[deep], True)
        text(s, x + 0.3, y + 0.42, w - 0.5, h - 0.5, body, size, pal["ink"])
    else:
        text(s, x + 0.3, y, w - 0.5, h, body, size, pal["ink"], anchor=MSO_ANCHOR.MIDDLE)


def new(n, dark=False):
    s = prs.slides.add_slide(BLANK)
    background(s, N["ground"] if dark else L["ground"])
    return s


# ---- 1 title
s = new(1, True)
s.shapes.add_picture(glow(BUILD + r"\glow1.png"), Inches(-2.2), Inches(0.6), Inches(8.5), Inches(6.4))
rect(s, 0.8, 1.2, 0.55, 0.07, N["pen"])
text(s, 0.8, 1.37, 6, 0.3, "FINAL-YEAR PROJECT", 13, N["penDeep"], True)
s.shapes.add_picture(ICON, Inches(0.8), Inches(1.85), Inches(1.15), Inches(1.15))
rect(s, 2.2, 1.85, 4.2, 1.15, N["hi"], radius=0.14)
text(s, 2.45, 1.85, 3.9, 1.15, "NoteNest", 54, "1B1E2B", font=HEAD, anchor=MSO_ANCHOR.MIDDLE)
text(s, 0.8, 3.35, 7.2, 1.0, "Everything you study, in one place — and it works offline.", 26, N["ink"])
text(s, 0.8, 4.65, 6, 0.4, AUTHOR, 22, N["ink"], True)
blank(s, 0.8, 5.25, 3.5, "Student ID", dark=True)
blank(s, 4.5, 5.25, 3.5, "Department", dark=True)
blank(s, 0.8, 5.85, 3.5, "Supervisor", dark=True)
blank(s, 4.5, 5.85, 3.5, "Submission date", dark=True)
pic = s.shapes.add_picture(GIFS + r"\opening.gif", Inches(8.6), Inches(0.55), Inches(3.5), Inches(6.22))
pic.line.color.rgb = C(N["rule"])
pic.line.width = Pt(1)
rail(s, 1, True)
notes(s, "Good morning. This is NoteNest, my final-year project. Its idea fits in one sentence: everything you study, in one place, and it works offline. "
         "The icon beside the name is the real launcher icon from the Android project. The animation on the right is the app's own opening: the page arrives, "
         "the corner folds, the line you meant to revise is marked, and the app opens underneath. I built it alone, and I will walk you through the real application.")
transition(s, "fade")

# ---- 2 problem
s = new(2)
heading(s, 2, "THE PROBLEM", "Exam week should be for studying.")
text(s, 0.8, 2.75, 5.2, 0.9, "Handwritten notes, typed notes, slides as PDFs, whiteboard photos, a recording — all for one lecture.", 17, L["inkSoft"])
srcs = [("Camera roll", "tintWarm", "warmDeep"), ("Chat apps", "tintRed", "redDeep"), ("Downloads folder", "tintPen", "penDeep"), ("Paper", "tintMint", "mintDeep")]
for i, (t, tint, deep) in enumerate(srcs):
    xx = 0.8 + (0.35 if i % 2 else 0)
    rect(s, xx, 3.75 + i * 0.82, 3.3, 0.66, L[tint], radius=0.2)
    text(s, xx + 0.3, 3.75 + i * 0.82, 2.8, 0.66, t, 19, L[deep], True, anchor=MSO_ANCHOR.MIDDLE)
rect(s, 4.85, 4.9, 0.9, 0.62, L["pen"], shape=MSO_SHAPE.RIGHT_ARROW)
rect(s, 6.2, 2.2, 6.3, 3.75, L["pen"], radius=0.4)
text(s, 6.7, 2.6, 5.3, 1.7, "None of these four places knows the items belong to the same lecture.", 28, "FFFFFF", font=HEAD)
text(s, 6.7, 4.5, 5.3, 1.0, "So exam week is spent searching instead of studying.", 21, L["penPale"])
rect(s, 6.7, 5.45, 1.3, 0.12, L["hi"], radius=0.06)
blank(s, 6.2, 6.3, 6.3, "[statistic — to be cited]", size=15)
rail(s, 2)
notes(s, "A student's material for one lecture is scattered: handwritten and typed notes, slides as PDFs, photos of the whiteboard, sometimes a recording. "
         "They end up in the camera roll, in chat apps, in a downloads folder and on paper. None of those four places knows the items belong to the same lecture. "
         "So exam week is spent searching instead of studying. I have deliberately not put a survey figure here; there is a blank where a cited statistic can go.")
transition(s, "push")

# ---- 3 solution
s = new(3)
heading(s, 3, "THE SOLUTION", "One notebook, even offline.")
for i, (t, tint, deep) in enumerate([("Semester", "tintWarm", "warmDeep"), ("Course", "tintMint", "mintDeep"), ("Note", "tintPen", "penDeep")]):
    rect(s, 0.8 + i * 1.95, 2.9, 1.55, 0.6, L[tint], radius=0.18)
    text(s, 0.8 + i * 1.95, 2.9, 1.55, 0.6, t, 18, L[deep], True, align=PP_ALIGN.CENTER, anchor=MSO_ANCHOR.MIDDLE)
    if i < 2:
        text(s, 2.4 + i * 1.95, 2.9, 0.35, 0.6, "›", 26, L["inkMeta"], align=PP_ALIGN.CENTER, anchor=MSO_ANCHOR.MIDDLE)
text(s, 0.8, 3.7, 6.2, 0.7, "Every note belongs to a course, every course to a semester. No connection needed.", 17, L["inkSoft"])
text(s, 0.8, 4.55, 6, 0.3, "WHAT MAKES IT DIFFERENT", 13, L["penDeep"], True)
card(s, 0.8, 4.95, 6.2, 0.8, None, "Organised by the academic calendar, not by folders", "tintPen", "pen")
card(s, 0.8, 5.9, 6.2, 0.8, None, "The device is the source of truth, not a server", "tintMint", "mintDeep")
phone(s, "06_today", 8.6, 0.7, 6.0)
rail(s, 3)
notes(s, "The idea is one app where every note belongs to a course and every course belongs to a semester, and the whole notebook works with no connection. "
         "Two things make it different from the apps students use now. First, it is organised by the academic calendar rather than by folders, so the home screen is built around today, "
         "this semester and the next exam. Second, the phone is the source of truth, not a server, so being offline is the normal state and not a failure. "
         "This is the Today screen, running on real data.")
transition(s, "push")

# ---- 4 features
s = new(4)
heading(s, 4, "KEY FEATURES", "What it does.", tw=6)
feats = ["Notes filed under courses", "Photos, PDFs and voice on one note", "Search that reaches inside PDF text", "Spaced revision",
         "Exam countdown and to-dos", "Cover-page generator", "Word and PDF conversion", "Share a note with a classmate",
         "Group chat and classes", "Backup to your own Google Drive", "PIN and fingerprint lock", "Bangla and English, light and dark"]
tints = [("tintPen", "pen"), ("tintMint", "mintDeep"), ("tintWarm", "warmDeep"), ("tintRed", "redDeep")]
for i, f in enumerate(feats):
    col, r = i // 6, i % 6
    t, d = tints[r % 4]
    x, y = 0.8 + col * 3.6, 2.0 + r * 0.78
    rect(s, x, y, 3.45, 0.66, L[t], radius=0.18)
    rect(s, x, y + 0.15, 0.06, 0.36, L[d])
    text(s, x + 0.25, y, 3.1, 0.66, f, 15, L["ink"], anchor=MSO_ANCHOR.MIDDLE)
row(s, [first("07_notes_list"), first("15_exams"), first("14_review")], 8.1, 0.65, 3.0, step_frac=0.82, drop=0.2, badges=False)
s.shapes.add_picture(GIFS + r"\spacing.gif", Inches(8.1), Inches(4.6), Inches(4.4), Inches(4.4 * 330 / 1000))
text(s, 8.1, 6.15, 4.4, 0.3, "Spaced revision: 1, 3, 7, 14, then 30 days", 14, L["inkSoft"])
rail(s, 4)
notes(s, "Here is everything the app does, in plain language. Notes are filed under courses. A note can carry photos, PDFs and voice recordings, and search reaches inside the text of a PDF. "
         "Revision is spaced: the animation below the phones shows the gap growing, one day, three, seven, fourteen and thirty, and a note you forget goes back to one day. "
         "There is an exam countdown and a to-do page, a cover-page generator, Word and PDF conversion, and you can share a note with a classmate. "
         "Classes and group chat are there too. Backup goes to the student's own Google Drive, there is a PIN and fingerprint lock, and the app speaks Bangla and English in light and dark.")
transition(s, "push")

# ---- 5 walkthrough
s = new(5)
heading(s, 5, "HOW IT WORKS", "Five screens, start to finish.", tw=11)
steps = ["Sign in", "Degree setup", "Today", "Note editor, with attach bar", "Review"]
for i, st in enumerate(steps):
    badge(s, i + 1, 1.0, 2.45 + i * 0.85, d=0.38)
    text(s, 1.35, 2.2 + i * 0.85, 2.2, 0.5, st, 17, L["ink"], True, anchor=MSO_ANCHOR.MIDDLE)
row(s, [first("01_login"), first("04_setup_degree"), first("06_today"), first("08_editor"), first("14_review")], 3.65, 2.0, 3.5, step_frac=0.88, drop=0.25)
rail(s, 5)
notes(s, "This is the journey, and the numbers match the badges under each phone. One: sign in. Two: tell the app about your degree once, and it works out the semester. "
         "Three: the Today screen. Four: the note editor, with the photo, PDF, voice and dictation buttons along the bottom, which is where attachments are added. "
         "Five: the review screen, where a note you are about to forget comes back. Everything on these screens is real data from the running app.")
transition(s, "push")

# ---- 6 users
s = new(6)
heading(s, 6, "TARGET USERS", "Who it is for.")
card(s, 0.8, 2.3, 6.4, 1.15, "PRIMARY", "University students who take notes on a phone and study for scheduled exams.", "tintPen", "penDeep")
card(s, 0.8, 3.6, 6.4, 1.15, "SECONDARY", "Teachers, through the class feature.", "tintMint", "mintDeep")
card(s, 0.8, 4.9, 6.4, 1.15, "WHY THESE USERS", "The app is built around semesters and exams, which only matter to people on an academic calendar.", "tintWarm", "warmDeep")
blank(s, 0.8, 6.3, 6.4, "[number of students — to be cited from UGC / university statistics]", size=14)
phone(s, "12b_semesters", 8.9, 0.7, 5.8)
rail(s, 6)
notes(s, "The primary user is a university student who takes notes on a phone and studies for scheduled exams. The secondary user is a teacher, who can run a class from the same app. "
         "I chose these users because the app is built around semesters and exams, and those only matter to people on an academic calendar. The phone shows the semester page. "
         "I have left the market size blank on purpose: the number of students should be cited from the University Grants Commission or university statistics, and I will not guess it.")
transition(s, "push")

# ---- 7 technology
s = new(7)
heading(s, 7, "TECHNOLOGY", "How it is built.", tw=6)
rect(s, 0.8, 2.0, 5.3, 3.7, L["tintPen"], radius=0.3)
text(s, 1.1, 2.15, 4.6, 0.3, "ON THE STUDENT'S PHONE", 13, L["penDeep"], True)
rect(s, 1.1, 2.6, 4.7, 1.05, L["card"], radius=0.2, line=L["rule"])
text(s, 1.35, 2.6, 4.3, 1.05, ["Flutter and Dart", "One codebase"], 18, L["ink"], anchor=MSO_ANCHOR.MIDDLE)
rect(s, 1.1, 3.85, 4.7, 1.6, L["tintMint"], radius=0.2)
rect(s, 1.1, 4.05, 0.07, 1.2, L["mintDeep"])
text(s, 1.4, 3.95, 4.3, 0.4, "SQLite through sqflite", 18, L["mintDeep"], True)
text(s, 1.4, 4.4, 4.3, 1.0, ["12 tables · schema version 14", "Foreign keys on", "The source of truth"], 15, L["ink"])
rect(s, 8.5, 2.0, 4.0, 2.0, L["tintWarm"], radius=0.25)
text(s, 8.75, 2.12, 3.6, 0.35, "Firebase · free Spark plan", 17, L["warmDeep"], True)
text(s, 8.75, 2.55, 3.6, 1.4, ["Authentication", "Firestore", "Cloud Messaging", "Optional: the app opens without it"], 15, L["ink"])
rect(s, 8.5, 4.2, 4.0, 1.5, L["card"], radius=0.25, line=L["rule"])
text(s, 8.75, 4.32, 3.6, 0.35, "The student's own Google Drive", 16, L["penDeep"], True)
text(s, 8.75, 4.75, 3.6, 0.9, ["Attachments and backup", "drive.file scope only"], 15, L["ink"])
arrow(s, 6.2, 3.0, 8.4, 3.0, L["warmDeep"])
text(s, 6.2, 2.55, 2.2, 0.4, "accounts, chat, classes", 13, L["inkSoft"], align=PP_ALIGN.CENTER)
arrow(s, 6.2, 4.95, 8.4, 4.95, L["penDeep"])
text(s, 6.2, 4.5, 2.2, 0.4, "files, backup", 13, L["inkSoft"], align=PP_ALIGN.CENTER)
rect(s, 0.8, 5.95, 11.7, 0.8, L["tintRed"], radius=0.2)
rect(s, 0.8, 6.15, 0.07, 0.4, L["redDeep"])
text(s, 1.1, 5.95, 11.2, 0.8, "There is no server of our own, so the Firestore security rules carry all of the authorisation.", 18, L["ink"], True, anchor=MSO_ANCHOR.MIDDLE)
rail(s, 7)
notes(s, "NoteNest is written in Flutter and Dart, one codebase. On the phone there is a SQLite database through sqflite: twelve tables, schema version fourteen, foreign keys switched on. "
         "That database is the source of truth. Firebase on the free Spark plan is optional: Authentication, Firestore and Cloud Messaging carry accounts, chat and classes, and the app opens normally when it cannot be reached. "
         "Files go to the student's own Google Drive, using the drive.file scope. The point to remember is that there is no server of our own. "
         "That means the Firestore security rules carry all of the authorisation, which is why I wrote a test suite for them.")
transition(s, "push")

# ---- 8 comparison
s = new(8)
heading(s, 8, "COMPARED WITH WHAT EXISTS", "Compared with what exists.", tw=11)
cols = [(0.8, 1.9, "PRODUCT"), (2.8, 3.3, "DOES WELL"), (6.2, 6.3, "WHY IT DOES NOT SOLVE THIS")]
for x, w, t in cols:
    text(s, x + 0.2, 1.8, w, 0.3, t, 13, L["penDeep"], True)
rows = [("Google Keep", "Fast, simple notes with colour and labels", "Organised by colour and label, with no idea of a course or an exam."),
        ("Evernote", "Powerful search, built for professional work", "Made for professional work; the free plan has limits."),
        ("Notion", "Flexible pages and databases", "Built online-first; working offline is limited."),
        ("Google Classroom", "Teachers post work, students hand it in", "A teacher's tool, not a notebook for the student's own notes."),
        ("Paper notebook", "No battery, no signal", "Cannot be searched, and holds no PDF or recording.")]
for i, (a, b, c) in enumerate(rows):
    y = 2.15 + i * 0.8
    rect(s, 0.8, y, 11.7, 0.72, L["card"], radius=0.14, line=L["rule"])
    text(s, 1.0, y, 1.8, 0.72, a, 15, L["ink"], True, anchor=MSO_ANCHOR.MIDDLE)
    text(s, 3.0, y, 3.1, 0.72, b, 14, L["inkSoft"], anchor=MSO_ANCHOR.MIDDLE)
    text(s, 6.4, y, 5.9, 0.72, c, 14, L["ink"], anchor=MSO_ANCHOR.MIDDLE)
for i, t in enumerate(["Organised by the academic calendar", "Offline is the normal state, not a failure"]):
    x = 0.8 + i * 5.95
    rect(s, x, 6.25, 5.75, 0.5, L["pen"], radius=0.15)
    text(s, x + 0.2, 6.25, 5.4, 0.5, f"{i + 1}   {t}", 15, "FFFFFF", True, anchor=MSO_ANCHOR.MIDDLE)
rail(s, 8)
notes(s, "I compared NoteNest with what a student could use today, and I describe only what these products publicly do. Google Keep is quick and simple, but it is organised by colour and label and has no idea of a course or an exam. "
         "Evernote is built for professional work and its free plan has limits. Notion is flexible but built online first, and working offline is limited. "
         "Google Classroom is a teacher's tool, not a notebook for the student's own notes. A paper notebook needs no signal, but it cannot be searched and holds no PDF or recording. "
         "NoteNest's two differences are at the bottom: it is organised by the academic calendar, and offline is the normal state, not a failure.")
transition(s, "push")

# ---- 9 cost
s = new(9)
heading(s, 9, "COST AND SUSTAINABILITY", "Free, and cheap to run.")
card(s, 0.8, 3.0, 5.9, 0.9, None, "Free to use: no advertising, no subscription.", "tintMint", "mintDeep", size=16)
card(s, 0.8, 4.05, 5.9, 0.9, None, "Firebase's free plan carries accounts, chat and classes.", "tintPen", "pen", size=16)
card(s, 0.8, 5.1, 5.9, 1.2, None, "Attachments go to each student's own Google Drive, so the storage cost does not grow as users are added.", "tintWarm", "warmDeep", size=16)
rect(s, 7.1, 1.0, 5.4, 3.0, L["card"], radius=0.25, line=L["rule"])
text(s, 7.4, 1.15, 4.8, 0.3, "THE REAL LIMITS OF THE FREE (SPARK) PLAN", 13, L["redDeep"], True)
text(s, 7.4, 1.6, 4.9, 2.3, ["No Cloud Storage.", "No Cloud Functions; the push-notification function in the project needs the paid plan.", "Daily Firestore quotas."], 16, L["ink"], space_after=8)
rect(s, 7.1, 4.2, 5.4, 2.1, L["tintPen"], radius=0.25)
text(s, 7.4, 4.35, 4.8, 0.3, "IF IT EVER OUTGREW THE FREE PLAN", 13, L["penDeep"], True)
text(s, 7.4, 4.75, 4.8, 0.7, "The next step would be the paid Blaze plan.", 16, L["ink"])
blank(s, 7.4, 5.65, 4.8, "Estimated monthly cost", size=15)
rail(s, 9)
notes(s, "This slide is about engineering, not revenue. The app is free, with no advertising and no subscription. It is designed to cost almost nothing to run: Firebase's free plan carries accounts, chat and classes, "
         "and attachments go to each student's own Google Drive rather than to storage I pay for, so the storage cost does not grow as users are added. "
         "The free Spark plan has real limits: no Cloud Storage, no Cloud Functions, and daily Firestore quotas. If the app ever outgrew it, the next step would be the paid Blaze plan. "
         "I have left the cost blank because I have not measured it and will not estimate it.")
transition(s, "push")

# ---- 10 security
s = new(10)
heading(s, 10, "SECURITY AND PRIVACY", "Security and privacy.", tw=7)
sec = [("Passwords", "Never stored. Only a salted PBKDF2-HMAC-SHA256 hash, 120,000 rounds.", "tintPen", "penDeep"),
       ("Accounts apart", "Study data carries its owner, and every query filters on it. Two accounts on one phone cannot see each other.", "tintMint", "mintDeep"),
       ("Google Drive", "drive.file: the app sees only files it created. The rest of the Drive is invisible.", "tintWarm", "warmDeep"),
       ("Audit", "My own code was audited before release: nine findings fixed, including a user-directory leak and the weak password hash.", "tintRed", "redDeep"),
       ("Play requirements", "A privacy policy is published and account deletion is built in.", "tintPen", "penDeep")]
for i, (t, b, tint, deep) in enumerate(sec):
    card(s, 0.8, 1.9 + i * 0.97, 6.7, 0.87, t.upper(), b, tint, deep, size=14, tsize=11)
row(s, [first("20_lock"), first("19_settings")], 8.1, 0.8, 4.3, step_frac=0.95, drop=0.35, badges=False)
rail(s, 10)
notes(s, "Passwords are never stored. Only a salted PBKDF2-HMAC-SHA256 hash is kept, at 120,000 rounds, with a different salt for every account. "
         "Two accounts on one phone cannot see each other: every row of study data carries its owner, and every query filters on it. "
         "The Google Drive permission is drive.file, which means the app sees only the files it created, and the rest of the student's Drive is invisible. "
         "Before release I audited my own code and fixed nine findings, among them a leak of the user directory and the weak password hash. "
         "A privacy policy is published and account deletion is built in, as Google Play requires. The phones show the PIN lock and Settings.")
transition(s, "push")

# ---- 11 status
s = new(11)
heading(s, 11, "WHERE IT STANDS", "Where it stands, and what is next.", tw=5.6)
card(s, 0.8, 2.85, 5.9, 1.15, "STATUS", "Built, signed with an upload key, version 1.0.2. Not yet published on the Play Store.", "tintMint", "mintDeep", size=16)
card(s, 0.8, 4.15, 5.9, 2.5, "NOT DONE YET", "Notes do not sync between phones. Android only. No field testing with real users. The 34 Firestore rules tests run by hand, not automatically.", "tintWarm", "warmDeep", size=16)
tiles = [("50,152", "lines of Dart in 141 files", "tintPen", "penDeep"), ("283", "automated tests, all passing", "tintMint", "mintDeep"),
         ("12 · v14", "tables · schema version", "tintWarm", "warmDeep"), ("9", "audit findings fixed", "tintRed", "redDeep")]
for i, (big, small, t, d) in enumerate(tiles):
    x = 7.1 + (i % 2) * 2.75
    y = 0.7 + (i // 2) * 1.7
    rect(s, x, y, 2.6, 1.55, L[t], radius=0.28)
    text(s, x + 0.22, y + 0.12, 2.2, 0.7, big, 32, L[d], font=HEAD)
    text(s, x + 0.22, y + 0.88, 2.2, 0.6, small, 14, L["ink"])
rect(s, 7.1, 4.15, 5.35, 2.5, L["card"], radius=0.25, line=L["rule"])
text(s, 7.4, 4.28, 4.8, 0.3, "ROADMAP", 13, L["penDeep"], True)
text(s, 7.4, 4.65, 4.9, 1.95, ["Sync notes between devices", "Run the rules tests automatically", "Publish on Google Play", "An iOS build", "Measure performance and accessibility"], 16, L["ink"], space_after=4)
rail(s, 11)
notes(s, "Here is where it honestly stands. The code is about fifty thousand lines of Dart in 141 files, counted in the lib folder. There are 283 automated tests and all of them pass. "
         "The database has 12 tables at schema version 14, and the audit fixed nine findings. The app is built, signed with an upload key, at version 1.0.2, but it is not yet published on the Play Store. "
         "What is not done: notes do not sync between phones, it is Android only, and there has been no field testing with real users. "
         "The Firestore rules have 34 tests that run against a local emulator, but I run them by hand rather than automatically. "
         "Next: sync notes between devices, run the rules tests on every change, publish on Play, build for iOS, and measure performance and accessibility. I am not asking for funding.")
transition(s, "push")

# ---- 12 conclusion
s = new(12, True)
s.shapes.add_picture(glow(BUILD + r"\glow12.png", color=(74, 91, 212)), Inches(-1.5), Inches(0.5), Inches(8), Inches(6.5))
rect(s, 0.8, 0.55, 0.55, 0.07, N["pen"])
text(s, 0.8, 0.72, 6, 0.3, "12  ·  CONCLUSION AND CONTACT", 13, N["penDeep"], True)
text(s, 0.8, 1.3, 6.4, 2.2, "NoteNest keeps a student's work in one place, organised by course, and it works whether or not there is a signal.", 25, N["ink"], font=HEAD)
text(s, 0.8, 3.65, 6, 0.9, "Thank you", 44, N["hi"], font=HEAD)
blank(s, 0.8, 4.75, 6.2, "Email", dark=True, lw=0.9)
blank(s, 0.8, 5.25, 6.2, "Phone", dark=True, lw=0.9)
blank(s, 0.8, 5.75, 6.2, "GitHub", dark=True, lw=0.9)
text(s, 0.8, 6.3, 6.4, 0.35, "Designed and built by Md. Sarowar Hossain", 16, N["inkSoft"])
row(s, [first("22_dark"), first("22b_dark_exam"), first("20_lock")], 7.6, 0.9, 4.0, step_frac=0.85, drop=0.3, dark=True, badges=False)
rail(s, 12, True)
notes(s, "To close: NoteNest keeps a student's work in one place, organised by course, and it works whether or not there is a signal. "
         "The phones show the dark theme and the PIN lock. I designed and built it myself. Thank you, and I am happy to take questions.")
transition(s, "fade")

prs.save(OUT)
print("saved", OUT)
