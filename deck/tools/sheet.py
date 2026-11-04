import glob, os
from PIL import Image, ImageDraw, ImageFont
S = r"C:\project\notenest\deck\shots"
files = sorted(f for f in glob.glob(S + "/*.png") if not os.path.basename(f).startswith("_"))
w, h, pad, cols = 260, 563, 16, 6
rows = (len(files) + cols - 1) // cols
sheet = Image.new("RGB", (cols * (w + pad) + pad, rows * (h + pad + 30) + pad), (40, 42, 54))
d = ImageDraw.Draw(sheet)
for i, f in enumerate(files):
    im = Image.open(f).convert("RGB"); im.thumbnail((w, h))
    x = pad + (i % cols) * (w + pad); y = pad + (i // cols) * (h + pad + 30)
    sheet.paste(im, (x, y + 24)); d.text((x, y + 4), os.path.basename(f)[:34], fill=(255, 255, 255))
sheet.save(r"C:\project\notenest\deck\contact_sheet_shots.png"); print(len(files), "shots")
