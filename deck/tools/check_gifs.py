from PIL import Image
D = r"C:\project\notenest\deck"
for n in ("opening", "spacing"):
    g = Image.open(rf"{D}\gifs\{n}.gif")
    print(n, "frames:", g.n_frames, "size:", g.size)
g = Image.open(rf"{D}\gifs\opening.gif")
s = Image.new("RGB", (270 * 6, 480))
for k, i in enumerate((4, 12, 20, 28, 34, 40)):
    g.seek(i)
    s.paste(g.convert("RGB").resize((270, 480)), (k * 270, 0))
s.save(rf"{D}\build\open_strip.png")
g = Image.open(rf"{D}\gifs\spacing.gif")
g.seek(g.n_frames - 1)
g.convert("RGB").save(rf"{D}\build\spacing_last.png")
