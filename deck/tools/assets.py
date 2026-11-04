"""Phone frame, opening GIF and spacing GIF for the NoteNest deck."""
from PIL import Image, ImageDraw, ImageFilter, ImageFont

D = r"C:\project\notenest\deck"
PEN, PEN_DEEP, HI = (74, 91, 212), (53, 70, 158), (255, 216, 77)
GROUND = (246, 247, 251)


# ------------------------------------------------------------ phone frame
def phone_frame(src, out, screen_w=600, bezel=16, shadow=True, crop_h=None, body=(24, 26, 36)):
    """Wrap a screenshot in a phone body with a soft drop shadow.

    Drop any new screenshot in deck/shots/ and call this on it.
    Returns (size, pad): pad is the transparent margin that holds the shadow.
    """
    im = Image.open(src).convert("RGB")
    if crop_h:
        im = im.crop((0, 0, im.width, crop_h))
    sh = round(im.height * screen_w / im.width)
    im = im.resize((screen_w, sh), Image.LANCZOS)
    r_out, r_in = 62, 62 - bezel
    W, H = screen_w + 2 * bezel, sh + 2 * bezel
    pad = 90
    canvas = Image.new("RGBA", (W + 2 * pad, H + 2 * pad), (0, 0, 0, 0))
    if shadow:
        s = Image.new("RGBA", canvas.size, (0, 0, 0, 0))
        ImageDraw.Draw(s).rounded_rectangle((pad, pad + 26, pad + W, pad + 26 + H), r_out, fill=(27, 30, 43, 120))
        canvas = Image.alpha_composite(canvas, s.filter(ImageFilter.GaussianBlur(30)))
    d = ImageDraw.Draw(canvas)
    d.rounded_rectangle((pad, pad, pad + W, pad + H), r_out, fill=body + (255,))
    d.rounded_rectangle((pad + 2, pad + 2, pad + W - 2, pad + H - 2), r_out - 2, outline=(70, 74, 92, 255), width=2)
    mask = Image.new("L", im.size, 0)
    ImageDraw.Draw(mask).rounded_rectangle((0, 0, im.width, im.height), r_in, fill=255)
    canvas.paste(im, (pad + bezel, pad + bezel), mask)
    canvas.save(out)
    return canvas.size, pad


# ------------------------------------------------------------ opening GIF
def _span(t, a, b, curve):
    return curve(min(1, max(0, (t - a) / (b - a))))


def ease_out(x):
    return 1 - (1 - x) ** 3


def ease_in(x):
    return x ** 3


def opening_frame(t, W, H, under, S=2):
    """One frame of lib/widgets/nest_opening.dart's _FoldPainter at time t (0..1)."""
    w2, h2 = W * S, H * S
    leaving = _span(t, .80, 1.0, ease_in)
    base = under.resize((w2, h2), Image.LANCZOS).convert("RGBA")
    if leaving >= 1:
        return base.resize((W, H), Image.LANCZOS).convert("RGB")
    layer = Image.new("RGBA", (w2, h2), HI + (255,))
    shown = _span(t, .06, .40, ease_out)
    if shown > 0:
        grow = 1 + leaving * .22
        box = min(w2, h2) * .54 * grow
        w, h = box * .591, box * .708
        left, top = (w2 - w) / 2, (h2 - h) / 2
        sc = .86 + shown * .14
        cx, cy = w2 / 2, h2 / 2

        def P(x, y):
            return (cx + (x - cx) * sc, cy + (y - cy) * sc)

        content = Image.new("RGBA", (w2, h2), (0, 0, 0, 0))
        cd = ImageDraw.Draw(content)
        x0, y0 = P(left, top)
        x1, y1 = P(left + w, top + h)
        rad = box * .083 * sc
        cd.rounded_rectangle((x0, y0, x1, y1), rad, fill=PEN + (255,))
        marked = _span(t, .62, .84, ease_out)
        lh = h * .0765
        a = P(left + w * .155, top + h - h * .415 - lh)
        b = P(left + w * .155 + w * .60 * marked, top + h - h * .415)
        if marked > 0.02:
            cd.rounded_rectangle((a[0], a[1], max(b[0], a[0] + 2), b[1]), lh * sc / 2, fill=HI + (255,))
        lh2 = h * .053
        a = P(left + w * .155, top + h - h * .265 - lh2)
        b = P(left + w * .155 + w * .40, top + h - h * .265)
        cd.rounded_rectangle((a[0], a[1], b[0], b[1]), lh2 * sc / 2, fill=(170, 180, 236, 255))
        folded = _span(t, .34, .68, ease_out)
        if folded > 0.01:
            leg = w * .43 * folded
            c = (left + w, top)
            tri = [P(*c), P(c[0], c[1] + leg), P(c[0] - leg, c[1])]
            off = box * .006 * sc
            sh = Image.new("RGBA", (w2, h2), (0, 0, 0, 0))
            ImageDraw.Draw(sh).polygon([(x - off, y + off) for x, y in tri], fill=(46, 58, 150, 255))
            sh = sh.filter(ImageFilter.GaussianBlur(box * .022 * sc / 2))
            content = Image.alpha_composite(content, sh)
            ImageDraw.Draw(content).polygon(tri, fill=(255, 255, 255, 255))
        # everything inside the page is clipped to the page's rounded outline
        clip = Image.new("L", (w2, h2), 0)
        ImageDraw.Draw(clip).rounded_rectangle((x0, y0, x1, y1), rad, fill=255)
        alpha = Image.composite(content.getchannel("A"), Image.new("L", (w2, h2), 0), clip)
        content.putalpha(alpha)
        layer = Image.alpha_composite(layer, content)
    layer.putalpha(layer.getchannel("A").point(lambda v: int(v * (1 - leaving))))
    return Image.alpha_composite(base, layer).resize((W, H), Image.LANCZOS).convert("RGB")


def make_opening(under_path, out, W=540, H=960):
    under = Image.open(under_path).convert("RGB")
    sc = max(W / under.width, H / under.height)
    under = under.resize((round(under.width * sc), round(under.height * sc)), Image.LANCZOS).crop((0, 0, W, H))
    n = 44  # 44 frames x 40 ms = 1760 ms, matching the 1750 ms controller
    frames = [opening_frame(i / (n - 1), W, H, under) for i in range(n)]
    dur = [40] * n
    dur[-1] = 1800
    pal = [f.quantize(256, method=Image.MEDIANCUT, dither=Image.NONE) for f in frames]
    pal[0].save(out, save_all=True, append_images=pal[1:], duration=dur, loop=0, disposal=1)
    return n


# ------------------------------------------------------------ spacing GIF
GAPS = [1, 3, 7, 14, 30]  # lib/models/review_schedule.dart: reviewGaps


def make_spacing(out, W=1000, H=330):
    S = 2

    def font(n, p="segoeui"):
        return ImageFont.truetype(rf"C:\Windows\Fonts\{p}.ttf", n * S)

    fb, fs, ft = font(28, "seguisb"), font(24), font(21)
    base = 262 * S
    slot = (W - 140) * S / len(GAPS)

    def draw(prog):
        im = Image.new("RGB", (W * S, H * S), GROUND)
        d = ImageDraw.Draw(im)
        d.text((70 * S, 16 * S), "Days between reviews", font=fb, fill=(27, 30, 43))
        d.rounded_rectangle((70 * S, base, (W - 70) * S, base + 4 * S), 2 * S, fill=(228, 231, 240))
        for i, g in enumerate(GAPS):
            cx = 70 * S + slot * (i + .5)
            full = 14 * S + 150 * S * (g / 30)
            f = min(1, max(0, prog - i))
            hgt = full * f
            on = prog >= i + 1
            if f > 0:
                d.rounded_rectangle((cx - 42 * S, base - hgt, cx + 42 * S, base), 12 * S, fill=PEN if on else (150, 162, 232))
                t = f"+{g} day" + ("s" if g > 1 else "")
                tw = d.textlength(t, font=fs)
                d.text((cx - tw / 2, base - hgt - 36 * S), t, font=fs, fill=PEN_DEEP)
            r = 12 * S if on else 8 * S
            d.ellipse((cx - r, base + 2 * S - r + 2 * S, cx + r, base + 2 * S + r + 2 * S), fill=HI if on else (255, 255, 255), outline=PEN, width=3 * S)
            lab = f"review {i + 1}"
            lw = d.textlength(lab, font=ft)
            d.text((cx - lw / 2, base + 26 * S), lab, font=ft, fill=(90, 96, 118))
        if prog >= len(GAPS):
            t = "Mastered"
            tw = d.textlength(t, font=fs)
            d.rounded_rectangle(((W - 70) * S - tw - 36 * S, 14 * S, (W - 70) * S, 56 * S), 21 * S, fill=(223, 246, 236))
            d.text(((W - 70) * S - tw - 18 * S, 18 * S), t, font=fs, fill=(14, 122, 90))
        return im.resize((W, H), Image.LANCZOS)

    frames, dur = [draw(0)], [900]
    for i in range(len(GAPS)):
        for k in range(1, 7):
            frames.append(draw(i + k / 6))
            dur.append(70)
        dur[-1] = 650
    dur[-1] = 2600
    pal = [fr.quantize(256, method=Image.MEDIANCUT, dither=Image.NONE) for fr in frames]
    pal[0].save(out, save_all=True, append_images=pal[1:], duration=dur, loop=0, disposal=1)
    return len(frames)


if __name__ == "__main__":
    print("opening frames", make_opening(D + r"\shots\06_today.png", D + r"\gifs\opening.gif"))
    print("spacing frames", make_spacing(D + r"\gifs\spacing.gif"))
