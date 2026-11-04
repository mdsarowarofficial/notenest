from pw import run
from seed_notes import NOTES

def open_note(a, title):
    for _ in range(6):
        c = [i for i in a.items() if title in i["l"] and i["r"] == "button" and i["b"][3] < 200]
        if c:
            x, y, w, h = c[0]["b"]
            if 100 < y + h / 2 < 720:
                a.tap_xy(x + w / 2, y + h / 2); return
        a.page.mouse.move(195, 500); a.page.mouse.wheel(0, 350); a.page.wait_for_timeout(500)
    raise SystemExit("cannot find " + title)

def fill(a, title, lines):
    open_note(a, title); a.page.wait_for_timeout(2500)
    a.tap("Edit", exact=True); a.page.wait_for_timeout(2500)
    a.tap_xy(195, 445); a.page.wait_for_timeout(300)
    a.page.keyboard.press("Control+A"); a.page.keyboard.press("Delete")
    a.type("- " + lines[0])
    for l in lines[1:]:
        a.page.keyboard.press("Enter"); a.type(l)
    a.page.wait_for_timeout(900)
    a.tap("Done", exact=True); a.page.wait_for_timeout(2200)
    a.tap("Back", exact=True); a.page.wait_for_timeout(1800)
    a.page.mouse.move(195, 400); a.page.mouse.wheel(0, -3000); a.page.wait_for_timeout(500)
    print("filled", title)

def f(a):
    for subj, title, topic, lines in NOTES:
        fill(a, title, lines)
    a.shot("_n8")
if __name__ == "__main__": run(f)
