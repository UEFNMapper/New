"""Mouse — souris gaming ergonomique droitière (≈70 × 40 × 25 studs).

Coque sculptée (surface paramétrique : bosse de paume, dévers vers la droite, creux du pouce),
joints de boutons gravés, molette crantée dans sa fente, 2 boutons latéraux, nervures de grip,
bandes RGB latérales + logo « A » néon, patins, câble tressé avec manchon.
Modélisée façade (côté utilisateur, paume) vers −Y, boutons vers +Y, puis tournée à l'export."""
from room_common import *

reset()
L = 70.0
Z0 = 1.3  # jonction coque / semelle
W_KEYS = [(0, 31), (0.2, 36.5), (0.42, 39.5), (0.62, 37.5), (0.82, 34.5), (1, 33.5)]
H_KEYS = [(0, 12.5), (0.18, 19.5), (0.38, 22.8), (0.55, 20.8), (0.75, 15.8), (1, 12.0)]


def ef(t):
    """Arrondi des extrémités (super-ellipse), plus carré à l'avant (boutons)."""
    k = 2.4 if t < 0.5 else 3.6
    return max(0.0, 1 - abs(2 * t - 1) ** k) ** (1 / k)


def S(t, th, out=0.0):
    """Point de la coque : t ∈ [0,1] arrière→avant, th ∈ [0,π] côté droit→dessus→côté gauche."""
    e = ef(t)
    a = cr1(W_KEYS, t) / 2 * (0.25 + 0.75 * e)
    h = cr1(H_KEYS, t) * (0.2 + 0.8 * e)
    c, s = math.cos(th), math.sin(th)
    p = 2.7
    x = a * math.copysign(abs(c) ** (2 / p), c)
    z = h * abs(s) ** (2 / p)
    zr = z / h
    # dévers ergonomique : sommet décalé vers la droite
    x += 2.4 * s ** 3 * math.sin(math.pi * min(1, t * 1.2))
    # creux du pouce (côté gauche) et évasement du repose-pouce
    g = math.exp(-((t - 0.5) / 0.2) ** 2)
    if c < 0:
        x *= 1 - 0.11 * g * math.exp(-((zr - 0.45) / 0.2) ** 2) + 0.05 * g * math.exp(-((zr - 0.08) / 0.1) ** 2)
    y = -L / 2 + L * t
    n = Vector((x / max(a, 1e-3) * 0.6, 0, z / max(h, 1e-3) * 0.6 + 0.2)).normalized()
    return Vector((x, y, Z0 + z)) + n * out


def ts(v):  # abscisse resserrée aux extrémités
    return (1 - math.cos(math.pi * v)) / 2


def shell_fn(u, v):
    t = ts(v)
    if u <= 0.84:
        return S(t, math.pi * u / 0.84)
    # dessous plat (corde) de gauche à droite
    k = (u - 0.84) / 0.16
    pl, pr = S(t, math.pi), S(t, 0)
    return pl.lerp(pr, k)


shell = grid_surface(shell_fn, 64, 56, closed_u=True, name="Shell", angle=50)
# fermeture des deux bouts (éventails minuscules : ef → 0)
bm = bmesh.new(); bm.from_mesh(shell.data)
bm.verts.ensure_lookup_table()
bmesh.ops.remove_doubles(bm, verts=bm.verts, dist=0.02)
bmesh.ops.holes_fill(bm, edges=bm.edges, sides=0)
bmesh.ops.recalc_face_normals(bm, faces=bm.faces)
bm.to_mesh(shell.data); bm.free()
shade(shell, 50)

# --- boutons gauche/droit : coques séparées posées sur la coque (le lèvre qui plonge forme le joint)
tb = 0.57
ty = 0.79


def gap(t):
    """Demi-écart angulaire entre les deux boutons (s'élargit autour de la molette)."""
    return 0.035 + 0.15 * math.exp(-((t - ty) / 0.07) ** 4)


buttons = []
for side in (-1, 1):
    def bfn(u, v, side=side):
        t = tb + (0.985 - tb) * u
        g = gap(t)
        th_in, th_out = math.pi / 2 - side * g, math.pi / 2 - side * (math.pi / 2 - 0.5)
        th = th_in + (th_out - th_in) * v
        e = min(1, 9 * u, 14 * (1 - u)) * min(1, 12 * v, 10 * (1 - v))
        e = math.sin(e * math.pi / 2)
        return S(t, th, -0.35 + 0.55 * e)
    buttons.append(grid_surface(bfn, 40, 26, name="Btn", angle=50))

# --- fente de molette
wy = -L / 2 + L * ty
top_w = S(ty, math.pi / 2).z
boolean_diff(shell, rbox((5.0, 11.5, 12), (0, wy, top_w + 2), r=1.2, seg=3))
shell_obj = shell

# molette crantée (pneu caoutchouc) + moyeu
star = [((4.55 if i % 2 == 0 else 4.2) * math.cos(TAU * i / 60), (4.55 if i % 2 == 0 else 4.2) * math.sin(TAU * i / 60))
        for i in range(60)]
wheel = extrude(star, -1.9, 1.9, "Wheel", angle=25)
bevel_all(wheel, 0.25, 2, angle=60)
xf(wheel, rot=(0, math.pi / 2, 0))
xf(wheel, loc=(0, wy, top_w + 1.2 - 4.55))

# --- semelle : empreinte extrudée + patins PTFE
foot = []
for i in range(56):
    t = ts(i / 55)
    foot.append((S(t, 0).x, S(t, 0).y))
for i in range(55, -1, -1):
    t = ts(i / 55)
    foot.append((S(t, math.pi).x, S(t, math.pi).y))
fp = []
for p in foot:
    if not fp or (Vector(p) - Vector(fp[-1])).length > 0.05:
        fp.append(p)
if (Vector(fp[0]) - Vector(fp[-1])).length < 0.05:
    fp.pop()
fp = [(x * 0.975, y * 0.985) for x, y in fp]
base = extrude(fp, 0.35, Z0 + 0.05, "Base", angle=40)
bevel_all(base, 0.3, 2, angle=40)
skates = [rbox((22, 3.0, 0.5), (0, -L / 2 + 6, 0.25), r=0.2, seg=2), rbox((20, 3.0, 0.5), (0, L / 2 - 6, 0.25), r=0.2, seg=2)]

# --- boutons latéraux (pouce)
side_btns = []
for t0, t1 in ((0.47, 0.60), (0.615, 0.75)):
    th0, th1 = math.pi - 0.78, math.pi - 0.46

    def btn(u, v, t0=t0, t1=t1, th0=th0, th1=th1):
        # bosse à bords adoucis qui épouse la coque (sort de 1,1 stud)
        e = min(1, 5 * u, 5 * (1 - u)) * min(1, 4 * v, 4 * (1 - v))
        e = math.sin(e * math.pi / 2)
        return S(t0 + (t1 - t0) * u, th0 + (th1 - th0) * v, -0.2 + 1.3 * e)
    b = grid_surface(btn, 20, 8, name="SideBtn", angle=55)
    side_btns.append(b)

# --- nervures de grip caoutchouc sur les deux flancs
ribs = []
for th in (0.2, 0.34, 0.48, 0.62):
    for side_th, t0, t1 in ((th, 0.2, 0.62), (math.pi - th + 0.08, 0.16, 0.42)):
        pts = [S(t0 + (t1 - t0) * k / 20, side_th, 0.05) for k in range(21)]
        ribs.append(sweep(pts, 0.36, 8, name="Rib", angle=70, radius_fn=lambda f: 0.36 * min(1, 6 * f, 6 * (1 - f)) + 0.05))

# --- RGB : bandes latérales basses + logo sur la paume
glow = []
for th in (0.07, math.pi - 0.07):
    pts = [S(0.08 + 0.84 * k / 40, th, 0.02) for k in range(41)]
    glow.append(sweep(pts, 0.5, 8, name="Strip", angle=70, radius_fn=lambda f: 0.5 * min(1, 8 * f, 8 * (1 - f)) + 0.05))
tl = 0.3
p_logo = S(tl, math.pi / 2)
slope = math.atan2(S(tl + 0.02, math.pi / 2).z - S(tl - 0.02, math.pi / 2).z, L * 0.04)
logo = text_mesh("A", 9.0, 1.2, bevel_d=0.15, res=3)
xf(logo, loc=(0, 0, -0.9))
xf(logo, rot=(slope, 0, 0))
xf(logo, loc=(p_logo.x - 0.2, p_logo.y, p_logo.z))
glow.append(logo)

# --- câble tressé : manchon souple + tresse qui file vers l'avant
front = Vector((0.0, L / 2 - 0.6, Z0 + 3.2))
relief = sweep([front + Vector((0, k * 1.2, -0.03 * k * k)) for k in range(7)], 1.8, 16, name="Relief",
               radius_fn=lambda f: 1.9 - 0.8 * f)
cable = sweep(catmull([front + Vector((0, 6.5, -0.9)), (0, L / 2 + 14, 1.3), (3, L / 2 + 26, 1.05), (12, L / 2 + 38, 1.05),
                       (16, L / 2 + 52, 1.05)], 10), 1.05, 12, name="Cable", braid=0.08, braid_freq=2.4)

tagj([shell_obj] + buttons, "Shell", "SmoothPlastic", "16181E")
tagj([base] + side_btns + [relief], "Base", "SmoothPlastic", "2A2D38")
tagj(ribs + [wheel], "Grip", "Plastic", "22252E")
tagj(skates, "Skates", "SmoothPlastic", "F2F2F5")
tagj(glow, "Glow", "Neon", "8B7CFF")
tagj([cable], "Cable", "Fabric", "22252E")

done("Mouse", direction=(-1.0, 0.55, 0.75), lens=55)
