from PIL import Image
D = r"C:\project\notenest\deck"
w, h, pad = 640, 360, 14
s = Image.new("RGB", (3 * (w + pad) + pad, 4 * (h + pad) + pad), (60, 62, 74))
for i in range(12):
    im = Image.open(rf"{D}\build\render\Slide{i + 1}.PNG").convert("RGB").resize((w, h), Image.LANCZOS)
    s.paste(im, (pad + (i % 3) * (w + pad), pad + (i // 3) * (h + pad)))
s.save(rf"{D}\contact_sheet_deck.png")
