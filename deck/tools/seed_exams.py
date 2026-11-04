from pw import run
EXAMS = [("Exam", "11/12/2026", 1, "Database Systems midterm"),
         ("Quiz", "10/31/2026", 2, "Operating Systems quiz 2"),
         ("Assignment", "11/05/2026", 0, "Software Engineering project report")]
def f(a):
    for n,(kind, date, subj, name) in enumerate(EXAMS):
        if n:
            a.tap("Add a date", exact=True) if any(i["l"]=="Add a date" for i in a.items()) else a.tap("Add", exact=False)
            a.page.wait_for_timeout(2800)
            a.tap(kind, exact=True); a.page.wait_for_timeout(300)
            a.tap_xy(195, 414); a.page.wait_for_timeout(2300)
            if any(i["l"] == "Switch to input" for i in a.items()):
                a.tap("Switch to input", exact=True); a.page.wait_for_timeout(1200)
            a.type(date); a.tap("OK", exact=True); a.page.wait_for_timeout(1500)
            a.tap_xy(195, 502); a.page.wait_for_timeout(1300)
        a.tap_xy(100, 550 if n==0 else 502+48*subj); a.page.wait_for_timeout(600)
        a.tap_xy(195, 735); a.type(name); a.page.wait_for_timeout(300)
        a.shot("_e4") if n==0 else None
        a.tap("Save", exact=True); a.page.wait_for_timeout(2500)
        print("saved", name); a.show() if n==0 else None
run(f)
