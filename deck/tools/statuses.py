from pw import run
from fill_bodies import open_note
S = [("UML diagram types","Read"),("Software testing levels","Review"),("Normalization 1NF","Review"),
     ("SQL joins","Read"),("Process scheduling","Review"),("Deadlock conditions","Mastered"),("TCP three-way","Read")]
def f(a):
    a.tap("Notes Notes", exact=True); a.page.wait_for_timeout(2000)
    for t, st in S:
        open_note(a, t); a.page.wait_for_timeout(2500)
        a.tap(st, exact=True); a.page.wait_for_timeout(1200)
        a.tap("Back", exact=True); a.page.wait_for_timeout(1800)
        a.page.mouse.move(195, 400); a.page.mouse.wheel(0, -3000); a.page.wait_for_timeout(400)
        print(t, st)
    a.tap("Today Today", exact=True); a.page.wait_for_timeout(2500); a.shot("_h4"); a.show()
run(f)
