"""Briques graphiques pour l'icône, les miniatures et le trailer.

- kaiju(name, res, yaw) : rendu cartoon d'un kaiju (fond transparent, anticrénelé)
- scene(view, w, h)     : décor du jeu (rendu de tools/render/scene.json)
- title(...)            : texte façon Roblox (contour épais, ombre, dégradé)
Les rendus sont mis en cache dans tools/marketing/.cache.
"""

import json
import math
import os
import sys

import numpy as np
from PIL import Image, ImageDraw, ImageFilter, ImageFont

ROOT = os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
sys.path.insert(0, os.path.join(ROOT, "tools", "render"))
from render import intersect, normalize  # noqa: E402

CACHE = os.path.join(ROOT, "tools", "marketing", ".cache")
FONTS = os.path.join(ROOT, "tools", "render", "fonts")
os.makedirs(CACHE, exist_ok=True)

INK = (23, 16, 34)
_models = None
_scene = None


def font(size, face="LuckiestGuy-Regular.ttf"):
    return ImageFont.truetype(os.path.join(FONTS, face), size)


def models():
    global _models
    if _models is None:
        _models = json.load(open(os.path.join(ROOT, "tools", "render", "models.json")))
    return _models


def _render_parts(parts, res, cam_dir):
    pts = []
    for p in parts:
        c = np.array(p["cf"][0:3])
        pts.append(c + np.array(p["size"]) * 0.5)
        pts.append(c - np.array(p["size"]) * 0.5)
    pts = np.array(pts)
    lo, hi = pts.min(0), pts.max(0)
    center = (lo + hi) / 2
    radius = np.linalg.norm(hi - lo) / 2
    cam = center + cam_dir * radius * 3.0
    fwd = normalize(center - cam)
    right = normalize(np.cross(fwd, np.array([0, 1, 0])))
    up = np.cross(right, fwd)
    k = math.tan(math.radians(38) / 2)
    ys, xs = np.mgrid[0:res, 0:res]
    u = (xs + 0.5) / res * 2 - 1
    v = 1 - (ys + 0.5) / res * 2
    dirs = normalize(fwd + (u.reshape(-1, 1) * k) * right + (v.reshape(-1, 1) * k) * up)
    origins = np.tile(cam, (len(dirs), 1))
    best = np.full(len(dirs), np.inf)
    idx = np.full(len(dirs), -1)
    normal = np.zeros((len(dirs), 3))
    for i, p in enumerate(parts):
        t, nw = intersect(p, origins, dirs)
        closer = t < best
        best = np.where(closer, t, best)
        idx = np.where(closer, i, idx)
        normal = np.where(closer[:, None], nw, normal)
    light = normalize(np.array([0.5, 0.9, 0.6]) * np.array([np.sign(cam_dir[0]) or 1, 1, 1]))
    hitm = idx >= 0
    cols = np.array([p["color"] for p in parts])
    neon = np.array([p["neon"] for p in parts])
    img = np.zeros((len(dirs), 3))
    base = cols[idx[hitm]]
    lam = np.clip(normal[hitm] @ light, 0, 1)
    toon = np.where(lam > 0.5, 1.0, np.where(lam > 0.12, 0.8, 0.63))
    rim = np.clip(1 - np.abs((normal[hitm] * -dirs[hitm]).sum(1)), 0, 1) ** 3 * 0.3
    shade = base * toon[:, None] + rim[:, None]
    shade = np.where(neon[idx[hitm]][:, None], np.clip(base * 1.25 + 0.15, 0, 1), shade)
    img[hitm] = np.clip(shade, 0, 1)
    idx2 = idx.reshape(res, res)
    depth = np.where(np.isinf(best), 1e9, best).reshape(res, res)
    edge = np.zeros((res, res), bool)
    for dy, dx in ((0, 1), (1, 0)):
        b = np.roll(np.roll(idx2, dy, 0), dx, 1)
        db = np.roll(np.roll(depth, dy, 0), dx, 1)
        silhouette = (idx2 >= 0) != (b >= 0)
        jump = (np.abs(depth - db) > radius * 0.06) & ((idx2 >= 0) | (b >= 0))
        edge |= silhouette | jump
    # contour épais (dilatation) + silhouette élargie pour le contour extérieur
    th = max(1, res // 180)
    alpha = hitm.reshape(res, res)
    grow = alpha.copy()
    thick = edge.copy()
    for dy in range(-th, th + 1):
        for dx in range(-th, th + 1):
            if dy * dy + dx * dx <= th * th:
                grow |= np.roll(np.roll(alpha, dy, 0), dx, 1)
                thick |= np.roll(np.roll(edge, dy, 0), dx, 1)
    out = img.reshape(res, res, 3)
    out[thick] = np.array(INK) / 255
    rgba = np.zeros((res, res, 4))
    rgba[..., :3] = out
    rgba[..., 3] = grow.astype(float)
    return (rgba * 255).astype(np.uint8)


def kaiju(name, res=900, yaw=0.0, pitch=0.35):
    """Rendu RGBA recadré d'un modèle de models.json (yaw en degrés : 0 = trois-quarts face)."""
    path = os.path.join(CACHE, f"k_{name}_{res}_{int(yaw)}_{int(pitch * 100)}.png")
    if os.path.exists(path):
        return Image.open(path)
    a = math.radians(yaw)
    base = np.array([0.75, 0.0, -1.0])
    d = np.array([base[0] * math.cos(a) - base[2] * math.sin(a), 0, base[0] * math.sin(a) + base[2] * math.cos(a)])
    d = normalize(d) * math.cos(pitch)
    d[1] = math.sin(pitch)
    ss = res * 2
    arr = _render_parts(models()[name], ss, normalize(d))
    im = Image.fromarray(arr, "RGBA").resize((res, res), Image.LANCZOS)
    im = im.crop(im.getbbox())
    im.save(path)
    return im


def scene(view, w=1920, h=1080):
    path = os.path.join(CACHE, f"s_{view.replace(':', '_')}_{w}x{h}.png")
    if os.path.exists(path):
        return Image.open(path).convert("RGB")
    global _scene
    import render_scene as RS

    if _scene is None:
        _scene = json.load(open(os.path.join(ROOT, "tools", "render", "scene.json")))
    RS.W, RS.H = w, h
    im = Image.fromarray(RS.render(_scene, view))
    im.save(path)
    return im


def ui(name):
    return Image.open(os.path.join(ROOT, "docs", "previews", "ui", name + ".png")).convert("RGB")


def lerp(a, b, t):
    return a + (b - a) * t


def title(text, size, fill_top=(255, 236, 90), fill_bot=(255, 150, 20), stroke=None, shadow=None, face="LuckiestGuy-Regular.ttf", tilt=0.0):
    """Texte cartoon : dégradé vertical, contour épais sombre, ombre portée. Renvoie une image RGBA."""
    f = font(size, face)
    stroke = stroke if stroke is not None else max(3, size // 9)
    shadow = shadow if shadow is not None else max(3, size // 10)
    l, t, r, b = f.getbbox(text)
    w, h = r - l + stroke * 2 + shadow + 8, b - t + stroke * 2 + shadow + 8
    ox, oy = -l + stroke + 4, -t + stroke + 4
    mask = Image.new("L", (w, h), 0)
    ImageDraw.Draw(mask).text((ox, oy), text, font=f, fill=255)
    outline = Image.new("L", (w, h), 0)
    ImageDraw.Draw(outline).text((ox, oy), text, font=f, fill=255, stroke_width=stroke, stroke_fill=255)
    out = Image.new("RGBA", (w, h), (0, 0, 0, 0))
    sh = Image.new("RGBA", (w, h), INK + (255,))
    out.paste(sh, (shadow, shadow), outline)
    out.paste(Image.new("RGBA", (w, h), INK + (255,)), (0, 0), outline)
    grad = Image.new("RGBA", (w, h))
    top_px, bot_px = oy + (t - t), h - stroke - shadow
    g = np.zeros((h, w, 4), np.uint8)
    for y in range(h):
        k = min(1, max(0, (y - top_px) / max(1, bot_px - top_px)))
        g[y, :, :3] = [int(lerp(fill_top[i], fill_bot[i], k)) for i in range(3)]
        g[y, :, 3] = 255
    grad = Image.fromarray(g, "RGBA")
    out.paste(grad, (0, 0), mask)
    # reflet en haut des lettres
    hl = mask.crop((0, 0, w, h)).point(lambda p: p)
    band = Image.new("L", (w, h), 0)
    ImageDraw.Draw(band).rectangle([0, 0, w, oy + (b - t) * 0.33], fill=70)
    shine = Image.new("RGBA", (w, h), (255, 255, 255, 255))
    out.paste(shine, (0, 0), Image.fromarray((np.array(hl, float) * np.array(band, float) / 255).astype(np.uint8)))
    if tilt:
        out = out.rotate(tilt, resample=Image.BICUBIC, expand=True)
    return out


def starburst(size, color=(255, 214, 60), rays=18, alpha=90, center=None, spin=0.0):
    w, h = size
    cx, cy = center or (w / 2, h / 2)
    im = Image.new("RGBA", size, (0, 0, 0, 0))
    d = ImageDraw.Draw(im)
    R = math.hypot(w, h)
    for i in range(rays):
        a0 = spin + i * 2 * math.pi / rays
        a1 = a0 + math.pi / rays
        d.polygon([(cx, cy), (cx + math.cos(a0) * R, cy + math.sin(a0) * R), (cx + math.cos(a1) * R, cy + math.sin(a1) * R)], fill=color + (alpha,))
    return im


def glow(im, radius=30, color=(255, 230, 120), strength=1.0):
    """Halo coloré autour d'une image RGBA."""
    a = im.split()[3]
    pad = radius * 2
    big = Image.new("L", (im.width + pad * 2, im.height + pad * 2), 0)
    big.paste(a, (pad, pad))
    big = big.filter(ImageFilter.GaussianBlur(radius)).point(lambda p: min(255, int(p * 1.6 * strength)))
    g = Image.new("RGBA", big.size, color + (0,))
    g.putalpha(big)
    g.alpha_composite(im, (pad, pad))
    return g, pad


def drop_shadow(im, offset=(14, 18), blur=10, opacity=150):
    a = im.split()[3].point(lambda p: p * opacity // 255)
    pad = blur * 3
    sh = Image.new("RGBA", (im.width + pad * 2 + abs(offset[0]), im.height + pad * 2 + abs(offset[1])), (0, 0, 0, 0))
    black = Image.new("RGBA", im.size, INK + (255,))
    layer = Image.new("L", sh.size, 0)
    layer.paste(a, (pad + offset[0], pad + offset[1]))
    layer = layer.filter(ImageFilter.GaussianBlur(blur))
    shadow = Image.new("RGBA", sh.size, INK + (0,))
    shadow.putalpha(layer)
    shadow.alpha_composite(im, (pad, pad))
    return shadow, pad


def paste_center(canvas, im, cx, cy):
    canvas.alpha_composite(im, (int(cx - im.width / 2), int(cy - im.height / 2)))


def fit(im, height=None, width=None):
    if height:
        return im.resize((max(1, int(im.width * height / im.height)), int(height)), Image.LANCZOS)
    return im.resize((int(width), max(1, int(im.height * width / im.width))), Image.LANCZOS)


def vignette(size, strength=0.55):
    w, h = size
    ys, xs = np.mgrid[0:h, 0:w]
    d = np.sqrt(((xs - w / 2) / (w / 2)) ** 2 + ((ys - h / 2) / (h / 2)) ** 2)
    a = np.clip((d - 0.55) / 0.9, 0, 1) ** 1.5 * strength
    v = np.zeros((h, w, 4), np.uint8)
    v[..., :3] = INK
    v[..., 3] = (a * 255).astype(np.uint8)
    return Image.fromarray(v, "RGBA")
