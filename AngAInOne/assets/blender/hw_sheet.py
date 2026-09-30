"""Planche contact des modèles « matériel PC » → assets/previews/_sheet_hardware.png (Pillow)."""
import os
from PIL import Image, ImageDraw, ImageFont

HERE = os.path.dirname(os.path.abspath(__file__))
PREV = os.path.join(HERE, "..", "previews")
KEYS = ["Fan140", "GpuCard", "RamStick", "CpuCooler", "AioRadiator", "PumpReservoir", "Psu", "Capacitor",
        "CapacitorBig", "Choke", "ChokeRow", "M2Ssd", "SataSsd", "VrmHeatsink", "ChipsetHeatsink", "CpuChip",
        "CpuSocket", "NpuChip", "CableBraided24", "CableSleeved8", "PcieSlot", "DimmSlot", "IoShield", "CaseFrame"]
COLS, TW, TH = 5, 384, 288
keys = [k for k in KEYS if os.path.exists(os.path.join(PREV, f"{k}.png"))]
rows = (len(keys) + COLS - 1) // COLS
sheet = Image.new("RGB", (COLS * TW, rows * (TH + 26)), (12, 13, 18))
d = ImageDraw.Draw(sheet)
try:
    font = ImageFont.truetype("/usr/share/fonts/truetype/dejavu/DejaVuSans-Bold.ttf", 17)
except OSError:
    font = ImageFont.load_default()
for i, k in enumerate(keys):
    im = Image.open(os.path.join(PREV, f"{k}.png")).convert("RGB").resize((TW, TH), Image.LANCZOS)
    x, y = (i % COLS) * TW, (i // COLS) * (TH + 26)
    sheet.paste(im, (x, y + 26))
    d.text((x + 8, y + 4), k, fill=(200, 196, 255), font=font)
out = os.path.join(PREV, "_sheet_hardware.png")
sheet.save(out, optimize=True)
print(out, len(keys), "modèles")
