"""Planche contact des personnages / objets : assets/previews/_sheet_characters.png (Pillow)."""
import os
from PIL import Image, ImageDraw, ImageFont

HERE = os.path.dirname(os.path.abspath(__file__))
PREV = os.path.join(HERE, "..", "previews")
NAMES = ["Lagz", "LagzHead", "LagzPortalCore", "Sparky", "PopUp",
         "Corrupto", "Dusty", "Minor", "Freezy", "VirusBug",
         "UsbKey", "BitCoin", "Pickaxe", "GiantCursor", "Hand"]
COLS, TW, TH, LAB = 5, 384, 288, 30

rows = (len(NAMES) + COLS - 1) // COLS
sheet = Image.new("RGB", (COLS * TW, rows * (TH + LAB)), (14, 15, 20))
draw = ImageDraw.Draw(sheet)
try:
    font = ImageFont.truetype("DejaVuSans-Bold.ttf", 18)
except OSError:
    font = ImageFont.load_default()
for i, n in enumerate(NAMES):
    x, y = (i % COLS) * TW, (i // COLS) * (TH + LAB)
    p = os.path.join(PREV, f"{n}.png")
    if os.path.exists(p):
        im = Image.open(p).convert("RGB").resize((TW, TH), Image.LANCZOS)
        sheet.paste(im, (x, y + LAB))
    draw.text((x + 10, y + 5), n, fill=(233, 216, 253), font=font)
out = os.path.join(PREV, "_sheet_characters.png")
sheet.save(out)
print(out)
