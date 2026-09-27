"""Icône, miniatures et trailer de la page Roblox.

Usage : python3 tools/marketing/make.py [icon] [thumbs] [trailer]   (tout par défaut)
Sorties : docs/marketing/icon.png (512×512), thumbnail_*.png (1920×1080), trailer.mp4 (1080p, 30 s)
Les visuels viennent du jeu : modèles des kaijus (models.json), décor (scene.json),
icônes Fluent (assets/icons, MIT) et musique/sons originaux (assets/audio).
Prérequis : numpy, Pillow, soundfile, imageio-ffmpeg (pip install imageio-ffmpeg).
"""

import math
import os
import random
import subprocess
import sys
import wave

import numpy as np
from PIL import Image, ImageDraw, ImageEnhance, ImageFilter, ImageOps

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import art  # noqa: E402
from art import INK  # noqa: E402

ROOT = art.ROOT
OUT = os.path.join(ROOT, "docs", "marketing")
os.makedirs(OUT, exist_ok=True)
W, H = 1920, 1080

_icons = {}


def icon(name, size):
    key = (name, size)
    if key not in _icons:
        im = Image.open(os.path.join(ROOT, "assets", "icons", name + ".png")).convert("RGBA")
        _icons[key] = im.resize((size, size), Image.LANCZOS)
    return _icons[key]


def gradient(size, top, bot):
    w, h = size
    t = np.linspace(0, 1, h)[:, None]
    g = np.zeros((h, w, 3))
    for i in range(3):
        g[..., i] = top[i] * (1 - t) + bot[i] * t
    return Image.fromarray(g.astype(np.uint8), "RGB").convert("RGBA")


def radial(size, inner, outer, center=None, radius=None):
    w, h = size
    cx, cy = center or (w / 2, h / 2)
    r = radius or max(w, h) * 0.75
    ys, xs = np.mgrid[0:h, 0:w]
    d = np.clip(np.sqrt((xs - cx) ** 2 + (ys - cy) ** 2) / r, 0, 1)[..., None]
    g = np.array(inner) * (1 - d) + np.array(outer) * d
    return Image.fromarray(g.astype(np.uint8), "RGB").convert("RGBA")


def backdrop(view, blur=2.5, dark=0.78, size=(W, H)):
    im = art.scene(view).resize(size, Image.LANCZOS)
    if blur:
        im = im.filter(ImageFilter.GaussianBlur(blur))
    im = ImageEnhance.Brightness(im).enhance(dark)
    im = ImageEnhance.Color(im).enhance(1.25)
    return im.convert("RGBA")


def kaiju(name, height, yaw=0):
    # un seul angle de rendu par kaiju ; yaw < 0 = regard vers la gauche (miroir)
    im = art.fit(art.kaiju(name, 900), height=height)
    return ImageOps.mirror(im) if yaw < 0 else im


def with_shadow(im, blur=12, offset=(16, 20)):
    return art.drop_shadow(im, offset=offset, blur=blur, opacity=170)


def place(canvas, im, cx, cy, shadow=True, anchor="center"):
    if shadow:
        im, pad = with_shadow(im)
    else:
        pad = 0
    x = cx - im.width / 2 if anchor == "center" else cx - pad
    y = cy - im.height / 2 if anchor == "center" else cy - im.height + pad
    canvas.alpha_composite(im, (int(x), int(y)))


def chip(text, size=64, fill=(255, 255, 255), bg=(255, 60, 90), pad=(40, 18)):
    t = art.title(text, size, fill, fill, stroke=max(3, size // 12), shadow=0)
    w, h = t.width + pad[0] * 2, t.height + pad[1] * 2
    im = Image.new("RGBA", (w + 12, h + 14), (0, 0, 0, 0))
    d = ImageDraw.Draw(im)
    d.rounded_rectangle([6, 10, w + 6, h + 10], radius=h // 2, fill=INK + (255,))
    d.rounded_rectangle([0, 0, w, h], radius=h // 2, fill=INK + (255,))
    d.rounded_rectangle([6, 6, w - 6, h - 6], radius=h // 2 - 6, fill=bg + (255,))
    im.alpha_composite(t, (pad[0], pad[1]))
    return im


# ----------------------------------------------------------------------------
# Icône 512×512
# ----------------------------------------------------------------------------

def make_icon():
    S = 1024
    c = radial((S, S), (255, 170, 40), (190, 40, 120), center=(S * 0.55, S * 0.45), radius=S * 0.8)
    c.alpha_composite(art.starburst((S, S), (255, 240, 150), 16, 70, center=(S * 0.55, S * 0.45)))
    # œufs en arrière-plan
    place(c, art.fit(art.kaiju("Egg_Secret", 900), height=250).rotate(-14, expand=True, resample=Image.BICUBIC), 165, 300)
    place(c, art.fit(art.kaiju("Egg_Legendary", 900), height=210).rotate(12, expand=True, resample=Image.BICUBIC), 880, 250)
    king, pad = art.glow(kaiju("KingKaiju", 820), 26, (255, 240, 170), 0.9)
    c.alpha_composite(king, (int(S * 0.52 - king.width / 2), int(S * 0.43 - king.height / 2)))
    t1 = art.title("STEAL A", 150, stroke=16, shadow=12)
    t2 = art.title("KAIJU!", 230, (255, 245, 120), (255, 120, 20), stroke=20, shadow=14)
    t1 = t1.rotate(4, expand=True, resample=Image.BICUBIC)
    t2 = t2.rotate(4, expand=True, resample=Image.BICUBIC)
    c.alpha_composite(t1, (int(S / 2 - t1.width / 2), 640))
    c.alpha_composite(t2, (int(S / 2 - t2.width / 2), 745))
    c = c.convert("RGB").resize((512, 512), Image.LANCZOS)
    c.save(os.path.join(OUT, "icon.png"))
    print("icône", flush=True)


# ----------------------------------------------------------------------------
# Miniatures 1920×1080
# ----------------------------------------------------------------------------

def thumb_main():
    c = backdrop("island", 3, 0.7)
    c.alpha_composite(art.starburst((W, H), (255, 220, 90), 20, 55, center=(W * 0.72, H * 0.5)))
    c.alpha_composite(art.vignette((W, H), 0.5))
    # météores dans le ciel
    for (x, y, s, r) in ((1260, 110, 150, 0), (1680, 60, 110, 0), (360, 70, 90, 0)):
        place(c, icon("meteor", s), x, y, shadow=False)
    king, _ = art.glow(kaiju("KingKaiju", 1000), 34, (255, 235, 150), 0.8)
    c.alpha_composite(king, (int(1420 - king.width / 2), int(H * 0.53 - king.height / 2)))
    place(c, kaiju("Pigeonator", 300, 30), 1830, 900)
    for (x, y, s, r) in ((1060, 300, 120, -15), (1100, 820, 110, 20), (1770, 420, 100, 10)):
        place(c, icon("cash", s).rotate(r, expand=True, resample=Image.BICUBIC), x, y)
    place(c, icon("egg_legendary", 150).rotate(-12, expand=True, resample=Image.BICUBIC), 980, 560)
    t1 = art.title("STEAL A", 200, stroke=20, shadow=16).rotate(3, expand=True, resample=Image.BICUBIC)
    t2 = art.title("KAIJU!", 330, (255, 245, 120), (255, 110, 20), stroke=26, shadow=20).rotate(3, expand=True, resample=Image.BICUBIC)
    c.alpha_composite(t1, (90, 110))
    c.alpha_composite(t2, (60, 300))
    tag = chip("HATCH • GROW • STEAL!", 64, bg=(255, 60, 110))
    c.alpha_composite(tag.rotate(3, expand=True, resample=Image.BICUBIC), (110, 700))
    place(c, kaiju("Toastzilla", 280, -20), 230, 960)
    place(c, kaiju("Gloop", 200, -10), 470, 990)
    c.convert("RGB").save(os.path.join(OUT, "thumbnail_1_main.png"))


def thumb_grow():
    c = backdrop("crater", 3, 0.72)
    c.alpha_composite(art.starburst((W, H), (140, 255, 140), 22, 45, center=(W * 0.5, H * 0.62)))
    c.alpha_composite(art.vignette((W, H), 0.45))
    stages = [("BABY", 190), ("TEEN", 290), ("ADULT", 430), ("TITAN", 640)]
    xs = [230, 580, 1010, 1540]
    base_y = 960
    for i, ((label, h), x) in enumerate(zip(stages, xs)):
        k = kaiju("Toastzilla", h, -15)
        place(c, k, x, base_y, anchor="bottom")
        lab = chip(label, 46, bg=[(120, 200, 255), (120, 220, 120), (255, 170, 40), (255, 70, 90)][i])
        c.alpha_composite(lab, (int(x - lab.width / 2), base_y - 10))
        if i < 3:
            arr = icon("arrow_right", 110)
            place(c, arr, (x + xs[i + 1]) / 2 + 20, base_y - 180, shadow=True)
    t = art.title("GROW THEM HUGE!", 170, (190, 255, 120), (40, 190, 60), stroke=18, shadow=14).rotate(2, expand=True, resample=Image.BICUBIC)
    c.alpha_composite(t, (int(W / 2 - t.width / 2), 40))
    place(c, icon("growth", 170), 150, 170)
    c.convert("RGB").save(os.path.join(OUT, "thumbnail_2_grow.png"))


def thumb_rampage():
    c = backdrop("island", 4, 0.62)
    red = Image.new("RGBA", (W, H), (255, 40, 40, 70))
    c.alpha_composite(red)
    c.alpha_composite(art.starburst((W, H), (255, 180, 60), 18, 70, center=(W * 0.62, H * 0.55)))
    c.alpha_composite(art.vignette((W, H), 0.6))
    mag, _ = art.glow(kaiju("Magmadillo", 820, 10), 30, (255, 150, 60), 0.9)
    c.alpha_composite(mag, (int(1250 - mag.width / 2), int(H * 0.56 - mag.height / 2)))
    for (x, y, s, r) in ((780, 820, 190, -10), (1700, 860, 170, 15), (1640, 250, 130, 0), (880, 330, 120, 20)):
        place(c, icon("smash", s).rotate(r, expand=True, resample=Image.BICUBIC), x, y, shadow=False)
    place(c, icon("rampage", 210).rotate(-8, expand=True, resample=Image.BICUBIC), 1000, 980)
    t = art.title("RAMPAGE!", 280, (255, 235, 110), (255, 60, 30), stroke=24, shadow=18).rotate(6, expand=True, resample=Image.BICUBIC)
    c.alpha_composite(t, (60, 170))
    sub = chip("SMASH THE TOY CITY!", 60, bg=(255, 90, 40))
    c.alpha_composite(sub.rotate(6, expand=True, resample=Image.BICUBIC), (120, 560))
    place(c, kaiju("Crabzooka", 300, -25), 330, 900)
    c.convert("RGB").save(os.path.join(OUT, "thumbnail_3_rampage.png"))


def thumb_worlds():
    c = Image.new("RGBA", (W, H), INK + (255,))
    names = [("world:Candy", "CANDY COAST", (255, 150, 210)), ("world:Frost", "FROST PEAKS", (150, 230, 255)),
             ("world:Volcano", "VOLCANO CORE", (255, 140, 50)), ("world:Cosmic", "COSMIC RIFT", (190, 130, 255))]
    n = len(names)
    slant = 160
    for i, (view, label, col) in enumerate(names):
        x0 = i * W / n
        bg = art.scene(view).resize((W, H), Image.LANCZOS)
        bg = ImageEnhance.Color(bg).enhance(1.3).convert("RGBA")
        # panneau incliné
        mask = Image.new("L", (W, H), 0)
        ImageDraw.Draw(mask).polygon([(x0 + slant / 2, 0), (x0 + W / n + slant / 2 + 6, 0), (x0 + W / n - slant / 2 + 6, H), (x0 - slant / 2, H)], fill=255)
        crop = bg.crop((int(W / 2 - W / n / 2 - 200), 0, int(W / 2 + W / n / 2 + 200), H)).resize((int(W / n + 400), H))
        layer = Image.new("RGBA", (W, H), (0, 0, 0, 0))
        layer.paste(crop, (int(x0 - 200), 0))
        c.paste(layer, (0, 0), mask)
        d = ImageDraw.Draw(c)
        d.line([(x0 - slant / 2, H), (x0 + slant / 2, 0)], fill=INK + (255,), width=16)
        lab = art.title(label, 64, (255, 255, 255), col, stroke=8, shadow=6)
        c.alpha_composite(lab, (int(x0 + W / n / 2 - lab.width / 2), 880))
    c.alpha_composite(art.vignette((W, H), 0.35))
    t = art.title("EXPLORE NEW WORLDS!", 150, stroke=16, shadow=12)
    c.alpha_composite(t, (int(W / 2 - t.width / 2), 50))
    place(c, kaiju("Frostodon", 330, -10), 700, 640)
    place(c, kaiju("CosmoGoose", 330, 20), 1480, 620)
    c.convert("RGB").save(os.path.join(OUT, "thumbnail_4_worlds.png"))


def make_thumbs():
    thumb_main()
    thumb_grow()
    thumb_rampage()
    thumb_worlds()
    print("miniatures", flush=True)


# ----------------------------------------------------------------------------
# Trailer (30 s, 1920×1080, 30 i/s, musique d'événement 140 BPM)
# ----------------------------------------------------------------------------

FPS = 30
BEAT = 60 / 140
BAR = BEAT * 4
DURATION = 30.0


def clamp(x, a=0.0, b=1.0):
    return max(a, min(b, x))


def ease_out_back(t, s=1.9):
    t = clamp(t) - 1
    return 1 + t * t * ((s + 1) * t + s)


def ease_out(t):
    return 1 - (1 - clamp(t)) ** 3


def ease_in_out(t):
    t = clamp(t)
    return t * t * (3 - 2 * t)


def kenburns(img, t, z0=1.0, z1=1.12, pan=(0, 0)):
    z = z0 + (z1 - z0) * ease_in_out(t)
    cw, ch = W / z, H / z
    cx = W / 2 + pan[0] * ease_in_out(t) * (W - cw) / 2
    cy = H / 2 + pan[1] * ease_in_out(t) * (H - ch) / 2
    box = (cx - cw / 2, cy - ch / 2, cx + cw / 2, cy + ch / 2)
    return img.resize((W, H), Image.BILINEAR, box=box).convert("RGBA")


_cache = {}


def cached(key, fn):
    if key not in _cache:
        _cache[key] = fn()
    return _cache[key]


def scaled(im, s):
    if abs(s - 1) < 0.01:
        return im
    return im.resize((max(1, int(im.width * s)), max(1, int(im.height * s))), Image.BILINEAR)


def pop_title(c, key, make, cx, cy, t_since, rot=0.0):
    if t_since < 0:
        return
    im = cached(key, make)
    s = ease_out_back(t_since / 0.35) if t_since < 0.35 else 1 + 0.025 * math.sin((t_since - 0.35) * 2 * math.pi / BEAT)
    im = scaled(im, max(0.02, s))
    if rot:
        im = im.rotate(rot, expand=True, resample=Image.BILINEAR)
    c.alpha_composite(im, (int(cx - im.width / 2), int(cy - im.height / 2)))


def headline(c, text, t, cy=150, size=120, top=(255, 236, 90), bot=(255, 150, 20), rot=2.0):
    pop_title(c, ("h", text, size), lambda: art.title(text, size, top, bot), W / 2, cy, t, rot)


def kz(name, h, yaw=0, glow=None):
    def build():
        im = kaiju(name, h, yaw)
        if glow:
            im, _ = art.glow(im, 26, glow, 0.8)
        sh, _ = with_shadow(im)
        return sh
    return cached(("k", name, h, yaw, glow), build)


def ic(name, s, shadow=True):
    def build():
        im = icon(name, s)
        return with_shadow(im, 8, (8, 10))[0] if shadow else im
    return cached(("i", name, s, shadow), build)


def put(c, im, cx, cy, s=1.0, rot=0.0, alpha=1.0):
    im = scaled(im, s)
    if rot:
        im = im.rotate(rot, expand=True, resample=Image.BILINEAR)
    if alpha < 1:
        im = im.copy()
        im.putalpha(im.split()[3].point(lambda p: int(p * alpha)))
    c.alpha_composite(im, (int(cx - im.width / 2), int(cy - im.height / 2)))


def bg(view, blur=0, dark=1.0):
    return cached(("bg", view, blur, dark), lambda: backdrop(view, blur, dark).convert("RGB"))


def spinburst(color, alpha, t, center=None, speed=0.25):
    # 36 étapes de rotation précalculées (symétrie des rayons)
    step = int((t * speed * 36) % 36)
    return cached(("burst", color, alpha, step, center), lambda: art.starburst((W, H), color, 18, alpha, center=center, spin=step / 36 * 2 * math.pi / 18))


# --- plans -------------------------------------------------------------------

def shot_meteor(t, d):
    c = kenburns(bg("horizon"), t / d, 1.0, 1.1, (0.2, 0.3))
    impact = 2.55
    if t < impact:
        k = ease_in_out(t / impact)
        x, y = 1750 - 900 * k, -120 + 760 * k
        for j in range(7):  # traînée
            kk = max(0, k - j * 0.035)
            put(c, ic("fire", 120 - j * 10, False), 1750 - 900 * kk + 40, -120 + 760 * kk - 40, 1.0, 0, 0.55 - j * 0.07)
        put(c, ic("meteor", 260), x, y, 0.5 + 0.9 * k, -20)
    else:
        u = t - impact
        put(c, ic("smash", 400, False), 850, 640, ease_out_back(u / 0.25) * (1 + u * 0.3), u * 40, clamp(1.4 - u * 1.2))
        headline(c, "METEORS DROP EGGS!", u - 0.1, 170)
    return c, (impact, 0.45)


def shot_hatch(t, d):
    c = kenburns(bg("crater", 2, 0.8), t / d, 1.05, 1.15)
    burst = 2.14
    c.alpha_composite(spinburst((255, 210, 80), 60 if t < burst else 110, t))
    if t < burst:
        wob = math.sin(t * 2 * math.pi / BEAT) * (6 + 10 * t / burst)
        land = ease_out_back(t / 0.3)
        put(c, kz("Egg_Legendary", 470), W / 2, 330 + 330 * land, 1.0, wob)
        if t > 1.7:
            put(c, ic("sparkles", 200, False), W / 2 + 150, 520, 1 + (t - 1.7), 0, 0.9)
    else:
        u = t - burst
        put(c, kz("SushiRex", 620, -10, (255, 240, 170)), W / 2, 640, ease_out_back(u / 0.35))
        put(c, cached("flash", lambda: Image.new("RGBA", (W, H), (255, 255, 255, 255))), W / 2, H / 2, 1, 0, clamp(1 - u / 0.3))
    headline(c, "HATCH KAIJUS!", t - 0.15, 150)
    return c, (burst, 0.4)


def shot_grow(t, d):
    c = cached("g_grow", lambda: radial((W, H), (120, 230, 150), (20, 110, 90)))
    c = c.copy()
    c.alpha_composite(spinburst((255, 255, 200), 55, t))
    steps = [("BABY", 230, (120, 200, 255)), ("TEEN", 360, (120, 220, 120)), ("ADULT", 540, (255, 170, 40)), ("TITAN", 780, (255, 70, 90))]
    i = min(3, int(t / (2 * BEAT)))
    u = t - i * 2 * BEAT
    label, h, col = steps[i]
    prev = steps[i - 1][1] if i > 0 else h * 0.6
    s = (prev + (h - prev) * ease_out_back(u / 0.3)) / h
    put(c, kz("Toastzilla", h, -15), W / 2, 1000 - h / 2 - 20, s)
    lab = cached(("chip", label), lambda: chip(label, 64, bg=col))
    put(c, lab, W / 2, 1000, ease_out_back(u / 0.25))
    headline(c, "GROW THEM INTO TITANS!", t - 0.1, 140, 110, (200, 255, 120), (40, 190, 60))
    return c, None


def shot_cash(t, d):
    c = kenburns(bg("island", 0, 0.9), t / d, 1.0, 1.18, (0.1, 0.4))
    rnd = random.Random(7)
    for j in range(18):
        t0 = j * 0.16
        u = t - t0
        if 0 <= u < 1.0:
            sx, sy = rnd.uniform(200, 1720), 1150
            k = ease_in_out(u)
            put(c, ic("cash", 130), sx + (W / 2 - sx) * k, sy + (330 - sy) * k, 1 - 0.4 * k, rnd.uniform(-30, 30))
        else:
            rnd.uniform(0, 1)
            rnd.uniform(0, 1)
    value = 120 * (48.3e6 / 120) ** ease_in_out(t / (d - 0.3))
    txt = "$" + (f"{value / 1e6:.1f}M" if value >= 1e6 else f"{value / 1e3:.1f}K" if value >= 1e3 else f"{value:.0f}")
    counter = art.title(txt, 150, (170, 255, 120), (40, 200, 70), stroke=16, shadow=12)
    pulse = 1 + 0.06 * max(0, math.cos((t % BEAT) / BEAT * math.pi))
    put(c, counter, W / 2, 330, pulse)
    headline(c, "EARN MILLIONS!", t - 0.1, 120, 110)
    return c, None


def shot_steal(t, d):
    c = kenburns(bg("wide", 1, 0.85), t / d, 1.1, 1.0, (-0.3, 0))
    k = ease_in_out(t / d)
    x = -250 + (W + 500) * k
    hop = abs(math.sin(t * 2 * math.pi / BEAT)) * 40
    put(c, kz("Kebabzilla", 420, 60), x, 650 - hop, 1, math.sin(t * 9) * 6)
    put(c, ic("thief", 300), x - 330, 760 - hop * 0.7, 1, math.sin(t * 9 + 1) * 8)
    blink = (int(t / BEAT) % 2) == 0
    if blink:
        edges = cached("edges", lambda: _edges())
        c.alpha_composite(edges)
        put(c, ic("alarm", 170), 1760, 190, 1, 0)
    headline(c, "STEAL YOUR FRIENDS' KAIJUS!", t - 0.1, 150, 100, (255, 240, 120), (255, 80, 60))
    return c, None


def _edges():
    e = Image.new("RGBA", (W, H), (0, 0, 0, 0))
    d = ImageDraw.Draw(e)
    th = 40
    for box in ([0, 0, W, th], [0, H - th, W, H], [0, 0, th, H], [W - th, 0, W, H]):
        d.rectangle(box, fill=(255, 40, 60, 150))
    return e


INVADERS = [("Crabzooka", 300, (-1, 0.55)), ("Gloop", 230, (1.1, 0.72)), ("Pigeonator", 250, (-0.9, 0.85)), ("Hydroblob", 250, (1.0, 0.45))]


def shot_defend(t, d):
    c = kenburns(bg("island", 0, 0.85), t / d, 1.08, 1.16)
    for j, (name, h, (side, yf)) in enumerate(INVADERS):
        hit = BEAT * (2 + j * 1.5)
        k = ease_out(min(t, hit) / hit)
        x = W / 2 + side * (1100 - 520 * k)
        y = H * yf + math.sin(t * 12 + j) * 8
        if t < hit:
            put(c, kz(name, h, -side * 60), x, y)
            if t > hit - 0.25:
                put(c, ic("bonk", 260), x + 60, y - h / 2 - 20 + 0 * t, 1, 40 - 90 * ease_out((t - hit + 0.25) / 0.25))
        else:
            u = t - hit
            put(c, ic("smash", 260, False), x, y, ease_out_back(u / 0.2), 0, clamp(1 - u / 0.6))
            bonk = cached("bonktxt", lambda: art.title("BONK!", 90, (255, 255, 255), (255, 200, 60)))
            put(c, bonk, x, y - 80 - u * 120, 1, 0, clamp(1 - u / 0.7))
    headline(c, "DEFEND YOUR ISLAND!", t - 0.1, 140, 115, (150, 230, 255), (40, 130, 255))
    return c, None


def shot_rampage(t, d):
    beat_i = int(t / BEAT)
    u = t - beat_i * BEAT
    shake = (1 - clamp(u / 0.2)) * 22
    c = kenburns(bg("island", 1, 0.7), t / d, 1.1, 1.22)
    c.alpha_composite(cached("redtint", lambda: Image.new("RGBA", (W, H), (255, 50, 30, 60))))
    c.alpha_composite(spinburst((255, 170, 60), 60, t, (W * 0.5, H * 0.62)))
    jump = abs(math.sin(t * math.pi / BEAT)) * 70
    put(c, kz("Magmadillo", 700, 10, (255, 150, 60)), W / 2 + 180, 640 - jump, 1 + 0.05 * (1 - clamp(u / 0.15)))
    rnd = random.Random(beat_i)
    for _ in range(3):
        put(c, ic("smash", 170, False), rnd.uniform(300, 1650), rnd.uniform(600, 1000), ease_out_back(u / 0.2), rnd.uniform(-30, 30), clamp(1 - u / BEAT))
    pop_title(c, ("rampage",), lambda: art.title("RAMPAGE!", 230, (255, 235, 110), (255, 60, 30), stroke=22, shadow=16), W / 2 - 250, 250, t - 0.05, 6)
    if shake:
        off = (int(rnd.uniform(-shake, shake)), int(rnd.uniform(-shake, shake)))
        frame = Image.new("RGBA", (W, H), INK + (255,))
        frame.alpha_composite(c.resize((int(W * 1.04), int(H * 1.04)), Image.BILINEAR), (int(-W * 0.02) + off[0], int(-H * 0.02) + off[1]))
        c = frame
    return c, None


WORLDS = [("world:Candy", "CANDY COAST", (255, 150, 210), "KawaiiKraken"), ("world:Frost", "FROST PEAKS", (150, 230, 255), "Frostodon"),
          ("world:Volcano", "VOLCANO CORE", (255, 140, 50), "Magmadillo"), ("world:Cosmic", "COSMIC RIFT", (190, 130, 255), "CosmoGoose")]


def shot_worlds(t, d):
    i = min(3, int(t / (2 * BEAT)))
    u = t - i * 2 * BEAT
    view, label, col, kname = WORLDS[i]
    c = kenburns(bg(view, 0, 1.0), u / (2 * BEAT), 1.0, 1.1, ((-1) ** i * 0.4, 0.2))
    put(c, kz(kname, 380, 20), 1600 if i % 2 == 0 else 320, 780, ease_out_back(u / 0.3))
    pop_title(c, ("w", label), lambda: art.title(label, 150, (255, 255, 255), col), W / 2, 880, u, -2)
    headline(c, "EXPLORE NEW WORLDS", t - 0.05, 120, 90)
    return c, None


LINEUP = ["Pigeonator", "Donutron", "Crabzooka", "Pizzapocalypse", "NuclearPigeon", "OmegaSushiMech", "SharktoastSupreme", "Drakonda"]


def shot_logo(t, d):
    c = cached("g_logo", lambda: radial((W, H), (255, 160, 60), (120, 30, 140), center=(W / 2, H * 0.45)))
    c = c.copy()
    c.alpha_composite(spinburst((255, 240, 160), 70, t, (W / 2, H * 0.45)))
    # défilé de kaijus au premier plan
    for j, name in enumerate(LINEUP):
        x = (j * 260 + t * 420) % (W + 520) - 260
        put(c, kz(name, 240, 30), x, 1000 - abs(math.sin(t * 7 + j)) * 18)
    put(c, kz("KingKaiju", 560, 0, (255, 240, 170)), W / 2, 470 + 400 * (1 - ease_out_back(t / 0.45)))
    pop_title(c, ("logo1",), lambda: art.title("STEAL A KAIJU!", 190, stroke=20, shadow=16), W / 2, 170, t - 0.45, 2)
    if t > 1.1:
        play = cached("play", lambda: chip("PLAY NOW!", 80, bg=(70, 210, 90)))
        put(c, play, W / 2, 820, ease_out_back((t - 1.1) / 0.3) * (1 + 0.05 * math.sin(t * 2 * math.pi / BEAT)))
    return c, None


SHOTS = [
    (shot_meteor, 2 * BAR),
    (shot_hatch, 2 * BAR),
    (shot_grow, 2 * BAR),
    (shot_cash, 2 * BAR),
    (shot_steal, 2 * BAR),
    (shot_defend, 2 * BAR),
    (shot_rampage, 2 * BAR),
    (shot_worlds, 2 * BAR),
]
SHOTS.append((shot_logo, DURATION - sum(d for _, d in SHOTS)))


def timeline():
    t0 = 0.0
    out = []
    for fn, d in SHOTS:
        out.append((t0, fn, d))
        t0 += d
    return out


# --- son ----------------------------------------------------------------------

SR = 44100


def load(name):
    import soundfile as sf

    data, sr = sf.read(os.path.join(ROOT, "assets", "audio", name + ".ogg"), dtype="float32", always_2d=True)
    if data.shape[1] == 1:
        data = np.repeat(data, 2, 1)
    return data


def make_audio(path):
    n = int(DURATION * SR)
    mix = np.zeros((n, 2), np.float32)
    music = load("music_event")[:n] * 0.55
    fade_in, fade_out = int(0.2 * SR), int(1.5 * SR)
    music[:fade_in] *= np.linspace(0, 1, fade_in)[:, None]
    music[-fade_out:] *= np.linspace(1, 0, fade_out)[:, None]
    mix[: len(music)] += music

    def sfx(name, at, vol=0.8):
        s = load(name) * vol
        i = int(at * SR)
        j = min(n, i + len(s))
        mix[i:j] += s[: j - i]

    starts = {fn.__name__: t0 for t0, fn, _ in timeline()}
    sfx("meteor_whistle", 0.05, 0.6)
    sfx("meteor_impact", starts["shot_meteor"] + 2.55, 0.9)
    for k in range(4):
        sfx("egg_wobble", starts["shot_hatch"] + 0.3 + k * BEAT, 0.6)
    sfx("egg_crack", starts["shot_hatch"] + 1.75, 0.8)
    sfx("hatch_epic", starts["shot_hatch"] + 2.14, 0.8)
    for k in range(4):
        sfx("stage_up", starts["shot_grow"] + k * 2 * BEAT, 0.55)
    for k in range(8):
        sfx("coin_tick", starts["shot_cash"] + 0.2 + k * 0.3, 0.6)
    sfx("cash_collect", starts["shot_cash"] + 2.4, 0.8)
    sfx("steal_grab", starts["shot_steal"] + 0.1, 0.8)
    sfx("alarm", starts["shot_steal"] + 1.2, 0.35)
    for j in range(4):
        sfx("bonk", starts["shot_defend"] + BEAT * (2 + j * 1.5), 0.9)
    sfx("roar_big", starts["shot_rampage"], 0.7)
    for k in range(8):
        sfx("boss_stomp", starts["shot_rampage"] + k * BEAT, 0.45)
    for k in range(4):
        sfx("whoosh", starts["shot_worlds"] + k * 2 * BEAT, 0.7)
    sfx("hatch_legendary", starts["shot_logo"] + 0.4, 0.75)
    peak = np.abs(mix).max()
    if peak > 0.89:
        mix *= 0.89 / peak
    pcm = (np.clip(mix, -1, 1) * 32767).astype(np.int16)
    with wave.open(path, "wb") as w:
        w.setnchannels(2)
        w.setsampwidth(2)
        w.setframerate(SR)
        w.writeframes(pcm.tobytes())


# --- rendu vidéo ---------------------------------------------------------------

def frame_at(t, tl):
    for t0, fn, d in reversed(tl):
        if t >= t0:
            c, _ = fn(t - t0, d)
            # petit flash blanc à chaque coupe
            u = t - t0
            if u < 0.12 and t0 > 0:
                flash = cached("flashw", lambda: Image.new("RGBA", (W, H), (255, 255, 255, 255)))
                put(c, flash, W / 2, H / 2, 1, 0, 0.55 * (1 - u / 0.12))
            return c
    return None


def make_trailer(preview=False):
    import imageio_ffmpeg

    ff = imageio_ffmpeg.get_ffmpeg_exe()
    wav = os.path.join(art.CACHE, "trailer.wav")
    make_audio(wav)
    tl = timeline()
    if preview:
        for t0, fn, d in tl:
            for f in (0.15, 0.55, 0.9):
                frame_at(t0 + d * f, tl).convert("RGB").resize((960, 540)).save(os.path.join(art.CACHE, f"pv_{fn.__name__}_{int(f * 100)}.png"))
        print("aperçus dans", art.CACHE)
        return
    out = os.path.join(OUT, "trailer.mp4")
    cmd = [ff, "-y", "-loglevel", "error", "-f", "rawvideo", "-pix_fmt", "rgb24", "-s", f"{W}x{H}", "-r", str(FPS), "-i", "-",
           "-i", wav, "-c:v", "libx264", "-preset", "medium", "-crf", "20", "-pix_fmt", "yuv420p", "-c:a", "aac", "-b:a", "192k",
           "-shortest", "-movflags", "+faststart", out]
    p = subprocess.Popen(cmd, stdin=subprocess.PIPE)
    total = int(DURATION * FPS)
    for i in range(total):
        fr = frame_at(i / FPS, tl).convert("RGB")
        p.stdin.write(fr.tobytes())
        if i % 60 == 0:
            print(f"trailer {i}/{total}", flush=True)
    p.stdin.close()
    p.wait()
    print("trailer", out, flush=True)


if __name__ == "__main__":
    what = sys.argv[1:] or ["icon", "thumbs", "trailer"]
    if "icon" in what:
        make_icon()
    if "thumbs" in what:
        make_thumbs()
    if "preview" in what:
        make_trailer(preview=True)
    if "trailer" in what:
        make_trailer()
