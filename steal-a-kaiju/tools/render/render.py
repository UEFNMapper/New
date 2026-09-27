"""Rendu d'aperçu des kaijus (lancer de rayons numpy, style cartoon avec contour).

Usage : python3 tools/render/render.py [models.json] [sortie.png] [filtre]
Lit le JSON exporté par export_models.luau et produit une planche contact.
"""

import json
import math
import sys

import numpy as np
from PIL import Image, ImageDraw, ImageFont

RES = 220


def normalize(v):
    return v / np.linalg.norm(v, axis=-1, keepdims=True)


def intersect(part, origins, dirs):
    """Renvoie (t, normale_monde) pour chaque rayon ; t = inf si pas de contact."""
    c = part["cf"]
    pos = np.array(c[0:3])
    R = np.array(c[3:12]).reshape(3, 3)  # lignes
    o = (origins - pos) @ R  # R^T (o - pos) en ligne
    d = dirs @ R
    h = np.array(part["size"]) / 2.0
    n = len(dirs)
    t = np.full(n, np.inf)
    nl = np.zeros((n, 3))
    shape = part["shape"]

    if shape in ("Ellipsoid", "Ball"):
        if shape == "Ball":
            h = np.full(3, h.min())
        os_, ds = o / h, d / h
        a = (ds * ds).sum(1)
        b = 2 * (os_ * ds).sum(1)
        cc = (os_ * os_).sum(1) - 1
        disc = b * b - 4 * a * cc
        ok = disc >= 0
        sq = np.sqrt(np.where(ok, disc, 0))
        t0 = (-b - sq) / (2 * a)
        hit = ok & (t0 > 1e-4)
        t = np.where(hit, t0, np.inf)
        p = o + d * t0[:, None]
        nl = p / (h * h)
    elif shape == "Cylinder":
        r = min(h[1], h[2])
        # côté : y^2 + z^2 = r^2
        a = d[:, 1] ** 2 + d[:, 2] ** 2
        b = 2 * (o[:, 1] * d[:, 1] + o[:, 2] * d[:, 2])
        cc = o[:, 1] ** 2 + o[:, 2] ** 2 - r * r
        disc = b * b - 4 * a * cc
        ok = (disc >= 0) & (a > 1e-12)
        sq = np.sqrt(np.where(ok, disc, 0))
        t0 = (-b - sq) / (2 * np.where(a > 1e-12, a, 1))
        px = o[:, 0] + d[:, 0] * t0
        side = ok & (t0 > 1e-4) & (np.abs(px) <= h[0])
        t = np.where(side, t0, np.inf)
        p = o + d * t0[:, None]
        nl = np.stack([np.zeros(n), p[:, 1], p[:, 2]], 1)
        # bouchons
        for sgn in (-1, 1):
            with np.errstate(divide="ignore", invalid="ignore"):
                tc = (sgn * h[0] - o[:, 0]) / d[:, 0]
            pc = o + d * tc[:, None]
            capok = (tc > 1e-4) & (pc[:, 1] ** 2 + pc[:, 2] ** 2 <= r * r) & (tc < t)
            t = np.where(capok, tc, t)
            nl = np.where(capok[:, None], np.array([sgn, 0, 0]), nl)
    else:  # Block ou Wedge : intersection de demi-espaces convexes
        planes = [
            (np.array([1, 0, 0]), h[0]),
            (np.array([-1, 0, 0]), h[0]),
            (np.array([0, 1, 0]), h[1]),
            (np.array([0, -1, 0]), h[1]),
            (np.array([0, 0, 1]), h[2]),
            (np.array([0, 0, -1]), h[2]),
        ]
        if shape == "Wedge":
            planes = [pl for pl in planes if not (pl[0][1] == 1 or pl[0][2] == -1)]
            nrm = np.array([0, 1 / h[1], -1 / h[2]])
            ln = np.linalg.norm(nrm)
            planes.append((nrm / ln, 0.0))
        tmin = np.full(n, -np.inf)
        tmax = np.full(n, np.inf)
        nmin = np.zeros((n, 3))
        for normal, dist in planes:
            dn = d @ normal
            on = o @ normal
            with np.errstate(divide="ignore", invalid="ignore"):
                tp = (dist - on) / dn
            entering = dn < 0
            parallel_out = (np.abs(dn) < 1e-12) & (on > dist)
            upd = entering & (tp > tmin)
            tmin = np.where(upd, tp, tmin)
            nmin = np.where(upd[:, None], normal, nmin)
            ex = (dn > 0) & (tp < tmax)
            tmax = np.where(ex, tp, tmax)
            tmax = np.where(parallel_out, -np.inf, tmax)
        hit = (tmin <= tmax) & (tmin > 1e-4)
        t = np.where(hit, tmin, np.inf)
        nl = nmin
    nw = normalize(nl @ R.T + 1e-12)
    return t, nw


def render(parts, res=RES):
    pts = []
    for p in parts:
        c = np.array(p["cf"][0:3])
        pts.append(c + np.array(p["size"]) * 0.5)
        pts.append(c - np.array(p["size"]) * 0.5)
    pts = np.array(pts)
    lo, hi = pts.min(0), pts.max(0)
    center = (lo + hi) / 2
    radius = np.linalg.norm(hi - lo) / 2
    cam_dir = normalize(np.array([0.75, 0.45, -1.0]))
    cam = center + cam_dir * radius * 3.2
    fwd = normalize(center - cam)
    right = normalize(np.cross(fwd, np.array([0, 1, 0])))
    up = np.cross(right, fwd)
    fov = math.radians(36)
    ys, xs = np.mgrid[0:res, 0:res]
    u = (xs + 0.5) / res * 2 - 1
    v = 1 - (ys + 0.5) / res * 2
    k = math.tan(fov / 2)
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
    light = normalize(np.array([0.5, 0.9, -0.4]))
    img = np.zeros((len(dirs), 3))
    bg_top, bg_bot = np.array([0.99, 0.95, 0.85]), np.array([0.93, 0.83, 0.68])
    img[:] = bg_top * (1 - (ys.reshape(-1) / res))[:, None] + bg_bot * (ys.reshape(-1) / res)[:, None]
    hitm = idx >= 0
    cols = np.array([p["color"] for p in parts])
    neon = np.array([p["neon"] for p in parts])
    base = cols[idx[hitm]]
    lam = np.clip(normal[hitm] @ light, 0, 1)
    toon = np.where(lam > 0.55, 1.0, np.where(lam > 0.15, 0.78, 0.6))
    rim = np.clip(1 - np.abs((normal[hitm] * -dirs[hitm]).sum(1)), 0, 1) ** 3 * 0.25
    shade = base * toon[:, None] + rim[:, None]
    shade = np.where(neon[idx[hitm]][:, None], np.clip(base * 1.25 + 0.15, 0, 1), shade)
    img[hitm] = np.clip(shade, 0, 1)
    # contour : changement d'objet ou saut de profondeur
    idx2 = idx.reshape(res, res)
    depth = np.where(np.isinf(best), 1e9, best).reshape(res, res)
    edge = np.zeros((res, res), bool)
    for dy, dx in ((0, 1), (1, 0)):
        a = idx2
        b = np.roll(np.roll(idx2, dy, 0), dx, 1)
        da = depth
        db = np.roll(np.roll(depth, dy, 0), dx, 1)
        silhouette = (a >= 0) != (b >= 0)
        jump = (np.abs(da - db) > radius * 0.08) & ((a >= 0) | (b >= 0))
        edge |= silhouette | jump
    out = img.reshape(res, res, 3)
    out[edge] = np.array([0.09, 0.06, 0.13])
    return (out * 255).astype(np.uint8)


def main():
    src = sys.argv[1] if len(sys.argv) > 1 else "tools/render/models.json"
    dst = sys.argv[2] if len(sys.argv) > 2 else "tools/render/preview.png"
    flt = sys.argv[3] if len(sys.argv) > 3 else None
    models = json.load(open(src))
    names = [k for k in models if not flt or flt in k]
    cols = 6
    rows = math.ceil(len(names) / cols)
    sheet = Image.new("RGB", (cols * RES, rows * (RES + 22)), (22, 16, 34))
    draw = ImageDraw.Draw(sheet)
    for i, name in enumerate(names):
        im = Image.fromarray(render(models[name]))
        x, y = (i % cols) * RES, (i // cols) * (RES + 22)
        sheet.paste(im, (x, y))
        draw.text((x + 6, y + RES + 4), name, fill=(255, 246, 222))
    sheet.save(dst)
    print("écrit", dst, len(names), "modèles")


if __name__ == "__main__":
    main()
