from pw import run
def f(a):
    a.tap_xy(28, 28); a.page.wait_for_timeout(2000)
    a.tap("Settings", exact=True); a.page.wait_for_timeout(2500)
    a.page.mouse.move(195, 400); a.page.mouse.wheel(0, -2000); a.page.wait_for_timeout(600)
    a.tap("Semesters and courses", exact=False); a.page.wait_for_timeout(2500)
    a.shot("12b_semesters")
run(f)
