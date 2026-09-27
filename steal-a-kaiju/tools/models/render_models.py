#!/usr/bin/env python3
"""Tiny software renderer for previewing glTF/GLB/OBJ models with trimesh + PIL.

Usage:
  render_models.py OUT.png [--cell 256] [--cols 8] [--yaw 35] [--pitch 20] LABEL=PATH [LABEL=PATH ...]
  render_models.py OUT.png --spec spec.json      # [{"label":..., "path":..., "sub":...}, ...]

Painter's algorithm (faces sorted back-to-front), flat shading, colours from
vertex colours / material base colour / sampled base texture.
"""
import sys, os, json, math, argparse
import numpy as np
import trimesh
from PIL import Image, ImageDraw, ImageFont

FONT_DIRS = ["/home/user/New/steal-a-kaiju/tools/render/fonts", "/usr/share/fonts/truetype/dejavu"]


def load_font(size):
    for d in FONT_DIRS:
        if os.path.isdir(d):
            for f in sorted(os.listdir(d)):
                if f.lower().endswith((".ttf", ".otf")) and ("Bold" in f or "bold" in f):
                    try:
                        return ImageFont.truetype(os.path.join(d, f), size)
                    except Exception:
                        pass
            for f in sorted(os.listdir(d)):
                if f.lower().endswith((".ttf", ".otf")):
                    try:
                        return ImageFont.truetype(os.path.join(d, f), size)
                    except Exception:
                        pass
    return ImageFont.load_default()


def face_colors(mesh):
    """Return (n_faces, 3) uint8 colours for a trimesh mesh."""
    n = len(mesh.faces)
    default = np.full((n, 3), 200, dtype=np.uint8)
    vis = mesh.visual
    try:
        kind = vis.kind
    except Exception:
        return default
    try:
        if kind == "texture":
            mat = vis.material
            img = getattr(mat, "baseColorTexture", None) or getattr(mat, "image", None)
            uv = getattr(vis, "uv", None)
            if img is not None and uv is not None and len(uv) == len(mesh.vertices):
                img = img.convert("RGBA")
                w, h = img.size
                px = np.asarray(img)
                # sample at face-centroid uv
                fuv = uv[mesh.faces].mean(axis=1)
                u = np.mod(fuv[:, 0], 1.0)
                v = np.mod(fuv[:, 1], 1.0)
                xi = np.clip((u * (w - 1)).astype(int), 0, w - 1)
                yi = np.clip(((1.0 - v) * (h - 1)).astype(int), 0, h - 1)
                cols = px[yi, xi, :3]
                fac = getattr(mat, "baseColorFactor", None)
                if fac is not None:
                    fac = np.asarray(fac, dtype=float)[:3]
                    if fac.max() > 1.0:
                        fac = fac / 255.0
                    cols = (cols * fac).clip(0, 255)
                return cols.astype(np.uint8)
            # no image: fall back to base colour factor / main colour
            fac = getattr(mat, "baseColorFactor", None)
            if fac is None:
                fac = getattr(mat, "main_color", None)
            if fac is not None:
                fac = np.asarray(fac, dtype=float)[:3]
                if fac.max() > 1.0:
                    fac = fac / 255.0
                fac = np.power(fac, 1 / 2.2) * 255  # glTF factors are linear -> sRGB for display
                return np.tile(fac.clip(0, 255).astype(np.uint8), (n, 1))
            return default
        if kind == "vertex":
            vc = np.asarray(vis.vertex_colors)[:, :3]
            return vc[mesh.faces].mean(axis=1).astype(np.uint8)
        if kind == "face":
            return np.asarray(vis.face_colors)[:, :3].astype(np.uint8)
    except Exception as e:
        print("  colour fallback:", e, file=sys.stderr)
    return default


def collect(path):
    """Load a file and return list of (vertices(world), faces, face_colors)."""
    out = []
    scene = trimesh.load(path, force="scene", process=False)
    if isinstance(scene, trimesh.Trimesh):
        scene = trimesh.Scene(scene)
    for node in scene.graph.nodes_geometry:
        T, gname = scene.graph[node]
        mesh = scene.geometry[gname]
        if not isinstance(mesh, trimesh.Trimesh) or len(mesh.faces) == 0:
            continue
        v = trimesh.transform_points(mesh.vertices, T)
        out.append((v, np.asarray(mesh.faces), face_colors(mesh)))
    return out


def render(parts, size=256, yaw=35.0, pitch=20.0, bg=(240, 240, 245), up="y"):
    V = np.vstack([p[0] for p in parts])
    F = np.vstack([p[1] + off for p, off in zip(parts, np.cumsum([0] + [len(p[0]) for p in parts[:-1]]))])
    C = np.vstack([p[2] for p in parts])
    if up == "z":  # z-up sources: rotate so z becomes y
        V = V[:, [0, 2, 1]] * np.array([1, 1, -1])
    lo, hi = V.min(0), V.max(0)
    center = (lo + hi) / 2
    V = V - center
    # camera rotation: yaw about Y, then pitch about X
    ya, pa = math.radians(yaw), math.radians(pitch)
    Ry = np.array([[math.cos(ya), 0, math.sin(ya)], [0, 1, 0], [-math.sin(ya), 0, math.cos(ya)]])
    Rx = np.array([[1, 0, 0], [0, math.cos(pa), -math.sin(pa)], [0, math.sin(pa), math.cos(pa)]])
    R = Rx @ Ry
    Vc = V @ R.T  # camera space: x right, y up, z towards viewer
    ext = max(Vc[:, 0].max() - Vc[:, 0].min(), Vc[:, 1].max() - Vc[:, 1].min(), 1e-6)
    scale = (size * 0.86) / ext
    cx = (Vc[:, 0].max() + Vc[:, 0].min()) / 2
    cy = (Vc[:, 1].max() + Vc[:, 1].min()) / 2
    sx = (Vc[:, 0] - cx) * scale + size / 2
    sy = size / 2 - (Vc[:, 1] - cy) * scale
    # shading
    tri = Vc[F]
    nrm = np.cross(tri[:, 1] - tri[:, 0], tri[:, 2] - tri[:, 0])
    ln = np.linalg.norm(nrm, axis=1)
    ln[ln == 0] = 1
    nrm = nrm / ln[:, None]
    light = np.array([-0.4, 0.7, 0.6])
    light /= np.linalg.norm(light)
    lam = np.abs(nrm @ light)  # two-sided
    shade = 0.45 + 0.6 * lam
    cols = (C.astype(float) * shade[:, None]).clip(0, 255).astype(int)
    depth = tri[:, :, 2].mean(axis=1)
    order = np.argsort(depth)  # far first (small z = far)
    img = Image.new("RGB", (size, size), bg)
    d = ImageDraw.Draw(img)
    # ground shadow
    gy = size / 2 - (Vc[:, 1].min() - cy) * scale
    d.ellipse([size * 0.2, gy - size * 0.04, size * 0.8, gy + size * 0.04], fill=(215, 215, 222))
    for i in order:
        a, b, c = F[i]
        d.polygon([(sx[a], sy[a]), (sx[b], sy[b]), (sx[c], sy[c])], fill=tuple(cols[i]))
    return img


def contact_sheet(items, out, cell=256, cols=8, yaw=35, pitch=20, up="y"):
    rows = math.ceil(len(items) / cols)
    font = load_font(max(11, cell // 16))
    small = load_font(max(9, cell // 22))
    labelh = int(cell * 0.22)
    sheet = Image.new("RGB", (cols * cell, rows * (cell + labelh)), (30, 30, 36))
    for idx, it in enumerate(items):
        x = (idx % cols) * cell
        y = (idx // cols) * (cell + labelh)
        label, path, sub = it["label"], it.get("path"), it.get("sub", "")
        try:
            if path and os.path.exists(path):
                parts = collect(path)
                img = render(parts, size=cell, yaw=it.get("yaw", yaw), pitch=pitch, up=it.get("up", up))
                V = np.vstack([p[0] for p in parts])
                dims = V.max(0) - V.min(0)
                sub = sub or "h=%.2f w=%.2f d=%.2f" % (dims[1], dims[0], dims[2])
            else:
                img = Image.new("RGB", (cell, cell), (60, 60, 70))
                ImageDraw.Draw(img).text((10, cell // 2 - 8), "(no model)", fill=(200, 200, 200), font=font)
        except Exception as e:
            print("FAIL", label, path, e, file=sys.stderr)
            img = Image.new("RGB", (cell, cell), (90, 40, 40))
            ImageDraw.Draw(img).text((6, cell // 2 - 8), "load error", fill=(255, 200, 200), font=font)
        sheet.paste(img, (x, y))
        d = ImageDraw.Draw(sheet)
        d.text((x + 6, y + cell + 4), label, fill=(255, 255, 255), font=font)
        d.text((x + 6, y + cell + 4 + int(cell * 0.09)), sub[: 40], fill=(180, 180, 190), font=small)
        print("rendered", idx + 1, "/", len(items), label, flush=True)
    sheet.save(out)
    print("wrote", out, sheet.size)


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("out")
    ap.add_argument("--cell", type=int, default=256)
    ap.add_argument("--cols", type=int, default=8)
    ap.add_argument("--yaw", type=float, default=35)
    ap.add_argument("--pitch", type=float, default=20)
    ap.add_argument("--up", default="y")
    ap.add_argument("--spec")
    ap.add_argument("items", nargs="*")
    a = ap.parse_intermixed_args()
    items = []
    if a.spec:
        items = json.load(open(a.spec))
    for it in a.items:
        label, path = it.split("=", 1)
        items.append({"label": label, "path": path})
    contact_sheet(items, a.out, cell=a.cell, cols=a.cols, yaw=a.yaw, pitch=a.pitch, up=a.up)


if __name__ == "__main__":
    main()
