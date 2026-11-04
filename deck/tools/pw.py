"""Drive the NoteNest web build (port 5000) in a long-lived Chrome over CDP."""
import sys
from playwright.sync_api import sync_playwright

URL = "http://127.0.0.1:5000/"
SHOTS = r"C:\project\notenest\deck\shots"

class App:
    def __init__(self, p):
        self.b = p.chromium.connect_over_cdp("http://127.0.0.1:9222")
        self.ctx = self.b.contexts[0]
        self.page = next((pg for pg in self.ctx.pages if "127.0.0.1:5000" in pg.url), None)
        fresh = self.page is None
        if fresh:
            self.page = self.ctx.pages[0] if self.ctx.pages else self.ctx.new_page()
        self.cdp = self.ctx.new_cdp_session(self.page)
        self.cdp.send("Emulation.setDeviceMetricsOverride",
                      {"width": 390, "height": 844, "deviceScaleFactor": 2, "mobile": True})
        if fresh:
            self.goto()

    def goto(self):
        self.page.goto(URL)
        self.page.wait_for_selector("flt-glass-pane", state="attached", timeout=60000)
        self.page.wait_for_timeout(7000)
        self.sem()

    def sem(self):
        ph = self.page.locator("flt-semantics-placeholder")
        if ph.count():
            ph.evaluate("e => e.click()")
            self.page.wait_for_timeout(800)

    def items(self):
        return self.page.evaluate(r"""() => [...document.querySelectorAll('flt-semantics')].map(e => ({
          r: e.getAttribute('role'), l: (e.getAttribute('aria-label') || e.innerText || '').split('\n')[0],
          v: e.value || '',
          b: (b=>[Math.round(b.x),Math.round(b.y),Math.round(b.width),Math.round(b.height)])(e.getBoundingClientRect())
        })).filter(x => x.l || x.v)""")

    def show(self, only_leaf=True):
        seen = set()
        for i in self.items():
            if i["b"][2] >= 380 and i["b"][3] >= 800: continue
            k = (i["l"], tuple(i["b"]))
            if k in seen: continue
            seen.add(k)
            print(i["r"], "|", i["l"][:60], "|", i["v"][:30], "|", i["b"])

    def tap(self, label, nth=0, exact=False):
        c = [i for i in self.items() if (i["l"] == label if exact else label.lower() in i["l"].lower())
             and not (i["b"][2] >= 380 and i["b"][3] >= 500)]
        c.sort(key=lambda i: i["b"][2] * i["b"][3])
        if not c: raise SystemExit(f"no control labelled {label!r}")
        x, y, w, h = c[nth]["b"]
        self.tap_xy(x + w / 2, y + h / 2)

    def tap_xy(self, x, y):
        self.page.mouse.move(x, y)
        self.page.wait_for_timeout(120)
        self.page.mouse.click(x, y)
        self.page.wait_for_timeout(700)

    def type(self, text, delay=15):
        self.page.keyboard.insert_text(text)
        self.page.wait_for_timeout(300)

    def shot(self, name):
        self.page.mouse.move(2, 420)
        self.page.wait_for_timeout(700)
        self.page.screenshot(path=SHOTS + "/" + name + ".png")
        print("saved", name)

def run(fn):
    with sync_playwright() as p:
        a = App(p)
        fn(a)

if __name__ == "__main__":
    run(lambda a: (a.show(), a.shot("_probe")))
