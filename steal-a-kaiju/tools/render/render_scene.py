"""Rendu d'une scène complète exportée par export_scene.luau (aperçu du jeu).

Usage : python3 tools/render/render_scene.py [scene.json] [sortie.png] [vue]
vue : island (défaut) | crater | wide
"""

import json
import math
import sys

import numpy as np
from PIL import Image

sys.path.insert(0, "tools/render")
from render import intersect, normalize  # noqa: E402

W, H = 1280, 720


def vertical_cylinder(x, y, z, height, radius, color):
    # Cylindre Roblox : axe X ; rotation de 90° autour de Z pour le mettre debout
    return {
        "shape": "Cylinder",
        "size": [height, radius * 2, radius * 2],
        "cf": [x, y, z, 0, -1, 0, 1, 0, 0, 0, 0, 1],
        "color": color,
        "neon": False,
        "transparency": 0,
    }


def terrain(layout_radius=250):
    parts = []
    water = [0.12, 0.62, 0.78]
    sand = [0.94, 0.84, 0.63]
    grass = [0.38, 0.75, 0.35]
    parts.append({"shape": "Block", "size": [4000, 1, 4000], "cf": [0, -6.5, 0, 1, 0, 0, 0, 1, 0, 0, 0, 1], "color": water, "neon": False, "transparency": 0})
    parts.append(vertical_cylinder(0, -2.8, 0, 4, 132, sand))
    parts.append(vertical_cylinder(0, -1.6, 0, 2, 122, grass))
    for i in range(8):
        a = i / 8 * math.pi * 2
        x, z = math.sin(a) * layout_radius, math.cos(a) * layout_radius
        parts.append(vertical_cylinder(x, -2.8, z, 4, 92, sand))
        parts.append(vertical_cylinder(x, -1.6, z, 2, 84, grass))
    basalt = [0.2, 0.16, 0.2]
    for i in range(15):
        r = 240 - i * 15
        y = -20 + i * 14
        parts.append(vertical_cylinder(-120, y, 720, 16, r, sand if i < 4 else basalt))
    return parts


def camera_for(scene, view):
    focus = np.array(scene["focus"], dtype=float)
    look = np.array(scene["look"], dtype=float)
    look[1] = 0
    look = look / np.linalg.norm(look)
    side = np.cross(look, [0, 1, 0])
    if view == "crater":
        target = np.array([0.0, 0.0, 0.0])
        cam = target + np.array([60.0, 70.0, 110.0])
        return cam, target, 55
    if view == "wide":
        target = np.array([0.0, 0.0, 0.0])
        cam = focus - look * 120 + np.array([0, 260.0, 0]) + side * 80
        return cam, target, 60
    target = focus + look * 5
    cam = focus - look * 95 + side * 55 + np.array([0, 58.0, 0])
    return cam, target, 55


def render(scene, view="island"):
    parts = [p for p in scene["parts"] if p["transparency"] < 0.6] + terrain()
    cam, target, fov_deg = camera_for(scene, view)
    fwd = normalize(target - cam)
    right = normalize(np.cross(fwd, np.array([0, 1, 0])))
    up = np.cross(right, fwd)
    k = math.tan(math.radians(fov_deg) / 2)
    aspect = W / H
    ys, xs = np.mgrid[0:H, 0:W]
    u = ((xs + 0.5) / W * 2 - 1) * aspect
    v = 1 - (ys + 0.5) / H * 2
    dirs = normalize(fwd + (u.reshape(-1, 1) * k) * right + (v.reshape(-1, 1) * k) * up)
    n = len(dirs)
    best = np.full(n, np.inf)
    idx = np.full(n, -1)
    normal = np.zeros((n, 3))
    cam_row = cam.reshape(1, 3)

    for i, p in enumerate(parts):
        c = np.array(p["cf"][0:3])
        radius = np.linalg.norm(np.array(p["size"])) / 2
        rel = c - cam
        depth = rel @ fwd
        if depth + radius <= 0.1:
            continue
        # boîte écran de la sphère englobante
        if depth > radius:
            sx = (rel @ right) / (depth * k * aspect)
            sy = (rel @ up) / (depth * k)
            rx = radius / (depth * k * aspect) * 1.15
            ry = radius / (depth * k) * 1.15
            px0 = int(max(0, math.floor(((sx - rx) + 1) / 2 * W) - 2))
            px1 = int(min(W, math.ceil(((sx + rx) + 1) / 2 * W) + 2))
            py0 = int(max(0, math.floor((1 - (sy + ry)) / 2 * H) - 2))
            py1 = int(min(H, math.ceil((1 - (sy - ry)) / 2 * H) + 2))
            if px1 <= px0 or py1 <= py0:
                continue
            rows = np.arange(py0, py1)
            cols = np.arange(px0, px1)
            sub = (rows[:, None] * W + cols[None, :]).reshape(-1)
        else:
            sub = np.arange(n)
        t, nw = intersect(p, np.repeat(cam_row, len(sub), 0), dirs[sub])
        closer = t < best[sub]
        if closer.any():
            sel = sub[closer]
            best[sel] = t[closer]
            idx[sel] = i
            normal[sel] = nw[closer]

    light = normalize(np.array([0.45, 0.85, -0.35]))
    img = np.zeros((n, 3))
    sky_top = np.array([0.45, 0.62, 0.95])
    sky_bot = np.array([0.95, 0.86, 0.9])
    tt = (ys.reshape(-1) / H)[:, None]
    img[:] = sky_top * (1 - tt) + sky_bot * tt
    hit = idx >= 0
    cols_arr = np.array([p["color"] for p in parts])
    neon = np.array([p["neon"] for p in parts])
    base = cols_arr[idx[hit]]
    lam = np.clip(normal[hit] @ light, 0, 1)
    toon = np.where(lam > 0.55, 1.0, np.where(lam > 0.15, 0.8, 0.62))
    shade = base * toon[:, None]
    # brume atmosphérique
    fog = np.clip((best[hit] - 250) / 1400, 0, 0.75)[:, None]
    shade = shade * (1 - fog) + np.array([0.85, 0.82, 0.95]) * fog
    shade = np.where(neon[idx[hit]][:, None], np.clip(base * 1.3 + 0.2, 0, 1), shade)
    img[hit] = np.clip(shade, 0, 1)
    idx2 = idx.reshape(H, W)
    depth = np.where(np.isinf(best), 1e9, best).reshape(H, W)
    edge = np.zeros((H, W), bool)
    for dy, dx in ((0, 1), (1, 0)):
        b = np.roll(np.roll(idx2, dy, 0), dx, 1)
        db = np.roll(np.roll(depth, dy, 0), dx, 1)
        near = np.minimum(depth, db) < 400
        edge |= ((idx2 != b) & near & (np.abs(depth - db) > 0.02 * np.minimum(depth, db) + 0.3)) | ((idx2 >= 0) != (b >= 0))
    out = img.reshape(H, W, 3)
    out[edge] = out[edge] * 0.25 + np.array([0.09, 0.06, 0.13]) * 0.75
    return (out * 255).astype(np.uint8)


def main():
    src = sys.argv[1] if len(sys.argv) > 1 else "tools/render/scene.json"
    dst = sys.argv[2] if len(sys.argv) > 2 else "tools/render/scene.png"
    view = sys.argv[3] if len(sys.argv) > 3 else "island"
    scene = json.load(open(src))
    Image.fromarray(render(scene, view)).save(dst)
    print("écrit", dst)


if __name__ == "__main__":
    main()
