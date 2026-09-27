"""Rendu des captures d'interface exportées par export_ui.luau.

Reproduit la mise en page Roblox (UDim2, AnchorPoint, UIListLayout,
UIGridLayout, UIPadding, UIScale, AutomaticSize, Rotation, UICorner, UIStroke,
UIGradient, TextScaled, CanvasGroup / ClipsDescendants) et dessine le tout
avec PIL. Les ViewportFrame sont rendus avec le lanceur de rayons.

Usage : python3 tools/render/render_ui.py [ui.json] [dossier] [fond.png] [capture]
"""

import json
import math
import os
import re
import sys

import numpy as np
from PIL import Image, ImageDraw, ImageFont

sys.path.insert(0, "tools/render")
from render import intersect, normalize  # noqa: E402

W, H = 1280, 720
FONT_DIR = "tools/render/fonts"
EMOJI_FONT = "/usr/share/fonts/truetype/noto/NotoColorEmoji.ttf"
_font_cache = {}
_emoji_cache = {}


# ---------------------------------------------------------------------------
# Texte
# ---------------------------------------------------------------------------

def font_for(family, size):
    size = max(4, int(size))
    fam = family or ""
    if "LuckiestGuy" in fam:
        key, path = "lg", os.path.join(FONT_DIR, "LuckiestGuy-Regular.ttf")
    elif "Bangers" in fam:
        key, path = "bg", os.path.join(FONT_DIR, "Bangers-Regular.ttf")
    elif "Fredoka" in fam:
        key, path = "fr", os.path.join(FONT_DIR, "Fredoka[wdth,wght].ttf")
    elif "Mono" in fam:
        key, path = "mono", "/usr/share/fonts/truetype/dejavu/DejaVuSansMono-Bold.ttf"
    else:
        key, path = "sans", "/usr/share/fonts/truetype/dejavu/DejaVuSans-Bold.ttf"
    ck = (key, size)
    if ck not in _font_cache:
        try:
            f = ImageFont.truetype(path, size)
            if key == "fr":
                try:
                    f.set_variation_by_axes([100, 600])
                except Exception:
                    pass
        except OSError:
            f = ImageFont.load_default()
        _font_cache[ck] = f
    return _font_cache[ck]


def is_emoji(ch):
    o = ord(ch)
    return (
        0x1F000 <= o <= 0x1FAFF
        or 0x2600 <= o <= 0x27BF
        or 0x2B00 <= o <= 0x2BFF
        or 0x1F900 <= o <= 0x1F9FF
        or o in (0x2B50, 0x2B55, 0x231A, 0x231B, 0x23F0, 0x23F3, 0x2705, 0x274C, 0x2728, 0x26A1, 0x2622, 0x269B)
    )


def emoji_image(ch, size):
    key = (ch, int(size))
    if key in _emoji_cache:
        return _emoji_cache[key]
    try:
        f = ImageFont.truetype(EMOJI_FONT, 109)
        im = Image.new("RGBA", (136, 128), (0, 0, 0, 0))
        ImageDraw.Draw(im).text((0, 0), ch, font=f, embedded_color=True)
        bbox = im.getbbox()
        if bbox:
            im = im.crop(bbox)
        s = max(1, int(size))
        ratio = s / max(im.height, 1)
        im = im.resize((max(1, int(im.width * ratio)), s), Image.LANCZOS)
    except Exception:
        im = None
    _emoji_cache[key] = im
    return im


def parse_rich(text, default_color):
    """Renvoie une liste de (texte, couleur) en interprétant <font color>."""
    runs = []
    pos = 0
    color_stack = [default_color]
    for m in re.finditer(r"<(/?)(\w+)([^>]*)>", text):
        if m.start() > pos:
            runs.append((text[pos:m.start()], color_stack[-1]))
        closing, tag, attrs = m.group(1), m.group(2).lower(), m.group(3)
        if tag == "font":
            if closing:
                if len(color_stack) > 1:
                    color_stack.pop()
            else:
                cm = re.search(r'color="#?([0-9A-Fa-f]{6})"', attrs)
                if cm:
                    h = cm.group(1)
                    color_stack.append((int(h[0:2], 16), int(h[2:4], 16), int(h[4:6], 16)))
                else:
                    color_stack.append(color_stack[-1])
        pos = m.end()
    if pos < len(text):
        runs.append((text[pos:], color_stack[-1]))
    return runs


def measure(runs, family, size):
    f = font_for(family, size)
    width = 0
    for txt, _ in runs:
        for ch in txt:
            if is_emoji(ch):
                width += size * 1.05
            elif ch == "️":
                continue
            else:
                width += f.getlength(ch)
    return width, size * 1.15


def to_chars(runs):
    out = []
    for txt, col in runs:
        for ch in txt:
            if ch != "\ufe0f":
                out.append((ch, col))
    return out


def char_width(ch, f, size):
    return size * 1.05 if is_emoji(ch) else f.getlength(ch)


def wrap_lines(chars, family, size, width, wrapped):
    f = font_for(family, size)
    if not wrapped:
        return [chars]
    lines, line, word = [], [], []
    line_w = 0.0
    word_w = 0.0
    for ch, col in chars + [(" ", None)]:
        if ch == " ":
            space = f.getlength(" ")
            if line and line_w + space + word_w > width:
                lines.append(line)
                line, line_w = list(word), word_w
            else:
                if line:
                    line.append((" ", word[0][1] if word else None))
                    line_w += space
                line.extend(word)
                line_w += word_w
            word, word_w = [], 0.0
        elif ch == "\n":
            line.extend(word)
            lines.append(line)
            line, word, line_w, word_w = [], [], 0.0, 0.0
        else:
            word.append((ch, col))
            word_w += char_width(ch, f, size)
    if line:
        lines.append(line)
    return lines or [[]]


def lines_size(lines, family, size):
    f = font_for(family, size)
    width = max((sum(char_width(ch, f, size) for ch, _ in ln) for ln in lines), default=0)
    return width, size * 1.15 * len(lines)


def draw_text(layer, rect, node, stroke, scale, gradient):
    text = node.get("text") or ""
    if not text:
        return
    x, y, w, h = rect
    color = tuple(node.get("textColor") or (0, 0, 0))
    alpha = int(255 * (1 - (node.get("textT") or 0)))
    if alpha <= 0:
        return
    chars = to_chars(parse_rich(text, color))
    family = node.get("font")
    wrapped = bool(node.get("wrapped"))
    if node.get("textScaled"):
        max_size = node.get("_maxText", 100) * scale
        lo, hi = 4, int(max(4, min(max_size, h)))
        size = lo
        while lo <= hi:
            mid = (lo + hi) // 2
            ls = wrap_lines(chars, family, mid, w, wrapped)
            tw, th = lines_size(ls, family, mid)
            if tw <= w * 1.01 and th <= h * 1.02:
                size = mid
                lo = mid + 1
            else:
                hi = mid - 1
    else:
        size = (node.get("textSize") or 14) * scale
    lines = wrap_lines(chars, family, size, w, wrapped)
    tw, th = lines_size(lines, family, size)
    xa = node.get("xAlign") or "Center"
    ya = node.get("yAlign") or "Center"
    ty = y if ya == "Top" else (y + h - th if ya == "Bottom" else y + (h - th) / 2)
    f = font_for(family, size)
    target = Image.new("RGBA", layer.size, (0, 0, 0, 0))
    d = ImageDraw.Draw(target)
    sw = int(round((stroke["thickness"] if stroke else 0) * scale))
    sc = tuple(stroke["color"]) if stroke else (0, 0, 0)
    for ln in lines:
        lw = sum(char_width(ch, f, size) for ch, _ in ln)
        cx = x if xa == "Left" else (x + w - lw if xa == "Right" else x + (w - lw) / 2)
        for ch, col in ln:
            if is_emoji(ch):
                im = emoji_image(ch, size * 0.95)
                if im is not None:
                    target.alpha_composite(im, (int(cx), int(ty + size * 0.08)))
            else:
                c = tuple(col) if col else color
                d.text((cx, ty), ch, font=f, fill=c + (alpha,), stroke_width=sw, stroke_fill=sc + (alpha,))
            cx += char_width(ch, f, size)
        ty += size * 1.15
    if gradient is not None:
        arr = np.array(target).astype(float)
        grad = gradient_image((int(x), int(y), int(w), int(h)), gradient, layer.size)
        mask = arr[:, :, 3] > 0
        arr[mask, :3] = arr[mask, :3] * grad[mask, :3] / 255.0
        target = Image.fromarray(arr.astype(np.uint8))
    layer.alpha_composite(target)


# ---------------------------------------------------------------------------
# Formes
# ---------------------------------------------------------------------------

def gradient_image(rect, grad, size):
    x, y, w, h = rect
    W_, H_ = size
    ys, xs = np.mgrid[0:H_, 0:W_]
    angle = math.radians(grad.get("gradRotation") or 0)
    dx, dy = math.cos(angle), math.sin(angle)
    cx, cy = x + w / 2, y + h / 2
    half = abs(w / 2 * dx) + abs(h / 2 * dy) + 1e-6
    t = ((xs - cx) * dx + (ys - cy) * dy) / (2 * half) + 0.5
    off = grad.get("offset") or [0, 0]
    t = t - (off[0] * dx + off[1] * dy)
    t = np.clip(t, 0, 1)
    out = np.full((H_, W_, 4), 255.0)
    colors = grad.get("colors")
    if colors:
        times = [k[0] for k in colors]
        for c in range(3):
            out[:, :, c] = np.interp(t, times, [k[1][c] for k in colors])
    transp = grad.get("transp")
    if transp:
        times = [k[0] for k in transp]
        out[:, :, 3] = 255 * (1 - np.interp(t, times, [k[1] for k in transp]))
    return out


def rounded_mask(size, rect, radius):
    m = Image.new("L", size, 0)
    x, y, w, h = rect
    if w <= 0 or h <= 0:
        return m
    ImageDraw.Draw(m).rounded_rectangle([x, y, x + w - 1, y + h - 1], radius=max(0, min(radius, w / 2, h / 2)), fill=255)
    return m


def fill_shape(layer, rect, radius, color, alpha, gradient):
    size = layer.size
    mask = rounded_mask(size, rect, radius)
    if gradient is not None:
        g = gradient_image(rect, gradient, size)
        g[:, :, 0] = g[:, :, 0] * color[0] / 255
        g[:, :, 1] = g[:, :, 1] * color[1] / 255
        g[:, :, 2] = g[:, :, 2] * color[2] / 255
        g[:, :, 3] = g[:, :, 3] * (alpha / 255) * (np.array(mask) / 255)
        layer.alpha_composite(Image.fromarray(g.astype(np.uint8)))
    else:
        solid = Image.new("RGBA", size, tuple(color) + (int(alpha),))
        m = Image.fromarray((np.array(mask).astype(float) * alpha / 255).astype(np.uint8))
        layer.paste(solid, (0, 0), m) if False else layer.alpha_composite(Image.composite(solid, Image.new("RGBA", size, (0, 0, 0, 0)), m))


def stroke_shape(layer, rect, radius, stroke, scale):
    t = max(1, int(round(stroke["thickness"] * scale)))
    x, y, w, h = rect
    col = tuple(stroke["color"]) + (int(255 * (1 - (stroke.get("transparency") or 0))),)
    d = ImageDraw.Draw(layer)
    d.rounded_rectangle([x - t / 2, y - t / 2, x + w - 1 + t / 2, y + h - 1 + t / 2], radius=max(0, min(radius + t / 2, (w + t) / 2, (h + t) / 2)), outline=col, width=t)


# ---------------------------------------------------------------------------
# Viewport 3D
# ---------------------------------------------------------------------------

def render_viewport(node, w, h):
    parts = node.get("parts") or []
    cam = node.get("camera")
    w, h = int(w), int(h)
    if not parts or not cam or w < 4 or h < 4:
        return None
    c = cam["cf"]
    pos = np.array(c[0:3])
    R = np.array(c[3:12]).reshape(3, 3)
    right, up, back = R[:, 0], R[:, 1], R[:, 2]
    fwd = -back
    k = math.tan(math.radians(cam["fov"]) / 2)
    aspect = w / h
    ys, xs = np.mgrid[0:h, 0:w]
    u = ((xs + 0.5) / w * 2 - 1) * aspect
    v = 1 - (ys + 0.5) / h * 2
    dirs = normalize(fwd + (u.reshape(-1, 1) * k) * right + (v.reshape(-1, 1) * k) * up)
    n = len(dirs)
    origins = np.tile(pos, (n, 1))
    best = np.full(n, np.inf)
    idx = np.full(n, -1)
    normal = np.zeros((n, 3))
    for i, p in enumerate(parts):
        t, nw = intersect(p, origins, dirs)
        closer = t < best
        best = np.where(closer, t, best)
        idx = np.where(closer, i, idx)
        normal = np.where(closer[:, None], nw, normal)
    light = normalize(np.array([0.6, 1.0, 0.5]))
    out = np.zeros((n, 4))
    hit = idx >= 0
    cols = np.array([p["color"] for p in parts])
    neon = np.array([p["neon"] for p in parts])
    base = cols[idx[hit]]
    lam = np.clip(normal[hit] @ light, 0, 1)
    toon = np.where(lam > 0.5, 1.0, np.where(lam > 0.15, 0.8, 0.62))
    shade = np.where(neon[idx[hit]][:, None], np.clip(base * 1.3 + 0.15, 0, 1), base * toon[:, None])
    if node.get("silhouette"):
        shade = np.full_like(shade, 0.09)
    out[hit, :3] = shade
    out[hit, 3] = 1
    img = out.reshape(h, w, 4)
    idx2 = idx.reshape(h, w)
    edge = np.zeros((h, w), bool)
    for dy, dx in ((0, 1), (1, 0)):
        b = np.roll(np.roll(idx2, dy, 0), dx, 1)
        edge |= (idx2 >= 0) & ((idx2 != b))
    img[edge, :3] = img[edge, :3] * 0.3
    return Image.fromarray((img * 255).astype(np.uint8))


# ---------------------------------------------------------------------------
# Mise en page
# ---------------------------------------------------------------------------

MOD = {"UICorner", "UIStroke", "UIGradient", "UIScale", "UIPadding", "UIListLayout", "UIGridLayout", "UITextSizeConstraint", "UIAspectRatioConstraint", "UISizeConstraint", "UIFlexItem", "UIPageLayout"}
GUI = {"Frame", "TextLabel", "TextButton", "TextBox", "ScrollingFrame", "CanvasGroup", "ViewportFrame", "ImageLabel", "ImageButton"}


def mods(node):
    m = {"strokes": []}
    for c in node["children"]:
        cls = c["class"]
        if cls == "UICorner":
            r = c.get("radius") or [0, 8]
            m["corner"] = r
        elif cls == "UIStroke":
            m["strokes"].append(c)
        elif cls == "UIGradient":
            m["gradient"] = c
        elif cls == "UIScale":
            m["scale"] = c.get("scale", 1)
        elif cls == "UIPadding":
            m["pad"] = c.get("pad")
        elif cls == "UIListLayout":
            m["list"] = c
        elif cls == "UIGridLayout":
            m["grid"] = c
        elif cls == "UITextSizeConstraint":
            m["maxText"] = c.get("maxText", 100)
    return m


def udim_size(node, pw, ph, scale):
    s = node.get("size") or [0, 0, 0, 0]
    return pw * s[0] + s[1] * scale, ph * s[2] + s[3] * scale


def auto_width(node, m, scale, w, h):
    """Largeur automatique (AutomaticSize X) : texte ou somme des enfants."""
    auto = node.get("autoSize") or "None"
    if auto not in ("X", "XY"):
        return w
    if node["class"] in ("TextLabel", "TextButton") and node.get("text"):
        size = (node.get("textSize") or 14) * scale
        tw, _ = measure(parse_rich(node["text"], (0, 0, 0)), node.get("font"), size)
        pad = m.get("pad") or [0, 0, 0, 0]
        return max(w, tw + (pad[0] + pad[1]) * scale + 2)
    total = 0
    pad = m.get("pad") or [0, 0, 0, 0]
    lst = m.get("list")
    kids = [c for c in node["children"] if c["class"] in GUI and c.get("visible") is not False]
    for c in kids:
        cm = mods(c)
        cw, ch = udim_size(c, 0, h, scale)
        cw = auto_width(c, cm, scale, cw, ch)
        total = total + cw if lst and lst.get("dir") == "Horizontal" else max(total, cw)
    if lst and lst.get("dir") == "Horizontal" and kids:
        total += (lst.get("padding") or 0) * scale * (len(kids) - 1)
    return max(w, total + (pad[0] + pad[1]) * scale)


def render_node(canvas, node, parent_rect, scale, forced_pos=None, viewports=None):
    cls = node["class"]
    if cls not in GUI and cls not in ("ScreenGui", "Folder", "PlayerGui"):
        return
    if node.get("visible") is False:
        return
    m = mods(node)
    px, py, pw, ph = parent_rect
    w, h = udim_size(node, pw, ph, scale)
    own = m.get("scale", 1)
    w *= own
    h *= own
    w = auto_width(node, m, scale * own, w, h)
    if forced_pos is not None:
        x, y = forced_pos
    else:
        pos = node.get("position") or [0, 0, 0, 0]
        anchor = node.get("anchor") or [0, 0]
        x = px + pw * pos[0] + pos[1] * scale - anchor[0] * w
        y = py + ph * pos[2] + pos[3] * scale - anchor[1] * h
    rect = (x, y, w, h)
    child_scale = scale * own
    rotation = node.get("rotation") or 0
    clip = cls in ("CanvasGroup", "ScrollingFrame") or node.get("clip")
    use_layer = abs(rotation) > 0.05 or clip
    target = Image.new("RGBA", canvas.size, (0, 0, 0, 0)) if use_layer else canvas

    radius = 0
    if "corner" in m:
        r = m["corner"]
        radius = min(w, h) * r[0] + r[1] * child_scale
    # fond
    default_bgT = 1 if cls in ("ScrollingFrame", "ViewportFrame") else 0
    bgT = node.get("bgT")
    if bgT is None:
        bgT = default_bgT
    grad = m.get("gradient")
    text_like = cls in ("TextLabel", "TextButton", "TextBox")
    if bgT < 1 and cls not in ("ScreenGui", "Folder", "PlayerGui"):
        color = node.get("bg") or [163, 162, 165]
        fill_shape(target, rect, radius, color, 255 * (1 - bgT), None if text_like and False else grad)
    if cls == "ViewportFrame" and viewports is not None:
        img = render_viewport(node, w, h)
        if img is not None:
            target.alpha_composite(img, (int(x), int(y)))
    # contours de bordure
    for s in m["strokes"]:
        if (s.get("mode") or "Contextual") == "Border" or not text_like:
            if (s.get("mode") or "") == "Border" or (not text_like):
                stroke_shape(target, rect, radius, s, child_scale)
    # texte
    if text_like:
        node["_maxText"] = m.get("maxText", 100)
        text_stroke = next((s for s in m["strokes"] if (s.get("mode") or "Contextual") != "Border"), None)
        draw_text(target, rect, node, text_stroke, child_scale, grad if text_like and bgT >= 1 else None)

    # enfants
    pad = m.get("pad") or [0, 0, 0, 0]
    inner = (x + pad[0] * child_scale, y + pad[2] * child_scale, w - (pad[0] + pad[1]) * child_scale, h - (pad[2] + pad[3]) * child_scale)
    kids = [c for c in node["children"] if c["class"] in GUI or c["class"] in ("ScreenGui", "Folder")]
    kids_sorted = sorted(enumerate(kids), key=lambda t: ((t[1].get("z") or 1), t[0]))
    positions = {}
    lst = m.get("list")
    grid = m.get("grid")
    if lst or grid:
        vis = [c for c in kids if c.get("visible") is not False]
        vis = sorted(enumerate(vis), key=lambda t: ((t[1].get("order") or 0), t[0]))
        vis = [c for _, c in vis]
        ix, iy, iw, ih = inner
        if grid:
            cell = grid.get("cell") or [0, 100, 0, 100]
            cp = grid.get("cellPad") or [0, 5, 0, 5]
            cw, ch = iw * cell[0] + cell[1] * child_scale, ih * cell[2] + cell[3] * child_scale
            gx, gy = cp[1] * child_scale, cp[3] * child_scale
            per_row = max(1, int((iw + gx) // (cw + gx)))
            row_w = per_row * cw + (per_row - 1) * gx
            start_x = ix + ((iw - row_w) / 2 if (grid.get("hAlign") == "Center") else 0)
            for i, c in enumerate(vis):
                r_, col = divmod(i, per_row)
                c["_forceSize"] = (cw, ch)
                positions[id(c)] = (start_x + col * (cw + gx), iy + r_ * (ch + gy))
        else:
            horizontal = lst.get("dir") == "Horizontal"
            gap = (lst.get("padding") or 0) * child_scale
            sizes = []
            for c in vis:
                cm = mods(c)
                cw, ch = udim_size(c, iw, ih, child_scale)
                cw *= cm.get("scale", 1)
                ch *= cm.get("scale", 1)
                cw = auto_width(c, cm, child_scale, cw, ch)
                sizes.append((cw, ch))
            total = sum(s[0] if horizontal else s[1] for s in sizes) + gap * max(0, len(vis) - 1)
            if horizontal:
                hal = lst.get("hAlign")
                cur = ix + ((iw - total) / 2 if hal == "Center" else (iw - total if hal == "Right" else 0))
                for c, (cw, ch) in zip(vis, sizes):
                    val = lst.get("vAlign")
                    cy = iy + ((ih - ch) / 2 if val == "Center" else (ih - ch if val == "Bottom" else 0))
                    positions[id(c)] = (cur, cy)
                    cur += cw + gap
            else:
                val = lst.get("vAlign")
                cur = iy + ((ih - total) / 2 if val == "Center" else (ih - total if val == "Bottom" else 0))
                for c, (cw, ch) in zip(vis, sizes):
                    hal = lst.get("hAlign")
                    cx = ix + ((iw - cw) / 2 if hal == "Center" else (iw - cw if hal == "Right" else 0))
                    positions[id(c)] = (cx, cur)
                    cur += ch + gap
    for _, c in kids_sorted:
        fs = c.pop("_forceSize", None)
        if fs is not None:
            saved = c.get("size")
            c["size"] = [0, fs[0] / child_scale, 0, fs[1] / child_scale]
            render_node(target, c, inner, child_scale, positions.get(id(c)), viewports)
            c["size"] = saved
        else:
            render_node(target, c, inner, child_scale, positions.get(id(c)), viewports)

    if use_layer:
        if clip:
            mask = rounded_mask(canvas.size, rect, radius if cls == "CanvasGroup" else 0)
            empty = Image.new("RGBA", canvas.size, (0, 0, 0, 0))
            target = Image.composite(target, empty, mask)
        if abs(rotation) > 0.05:
            cx, cy = x + w / 2, y + h / 2
            target = target.rotate(-rotation, resample=Image.BICUBIC, center=(cx, cy))
        canvas.alpha_composite(target)


def render_shot(tree, background=None):
    canvas = Image.new("RGBA", (W, H), (30, 30, 40, 255))
    if background and os.path.exists(background):
        bg = Image.open(background).convert("RGBA").resize((W, H))
        canvas.alpha_composite(bg)
    guis = [c for c in tree["children"] if c["class"] == "ScreenGui" and c.get("enabled") is not False]
    guis.sort(key=lambda g: g.get("displayOrder") or 0)
    for g in guis:
        if g.get("name") in ("Loading",):
            continue
        for c in sorted(enumerate(g["children"]), key=lambda t: ((t[1].get("z") or 1), t[0])):
            render_node(canvas, c[1], (0, 0, W, H), 1.0, None, True)
    return canvas.convert("RGB")


def main():
    src = sys.argv[1] if len(sys.argv) > 1 else "tools/render/ui.json"
    out_dir = sys.argv[2] if len(sys.argv) > 2 else "tools/render/ui"
    background = sys.argv[3] if len(sys.argv) > 3 else "docs/previews/island.png"
    only = sys.argv[4] if len(sys.argv) > 4 else None
    shots = json.load(open(src))
    os.makedirs(out_dir, exist_ok=True)
    for name, tree in shots.items():
        if only and name not in only.split(","):
            continue
        img = render_shot(tree, background)
        path = os.path.join(out_dir, name + ".png")
        img.save(path)
        print("écrit", path)


if __name__ == "__main__":
    main()
