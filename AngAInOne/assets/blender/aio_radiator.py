"""AioRadiator — radiateur 360 de watercooling : faisceau réel (tubes plats + ailettes ondulées en zigzag,
en géométrie), flasques latérales, boîtes à eau sculptées, raccords nickelés, 2 durites gainées qui
s'éloignent, 3 ventilateurs 120 dessous en aspiration (rotors __Spin, axe Z) : la grille d'ailettes
est sur le dessus, bien visible."""
from hw_common import *

reset()
CX = 46.0                 # demi-longueur du faisceau
CY = 14.2                 # demi-largeur utile
FAN_S, FAN_D, BORE = 30.0, 6.4, 14.1
Z0, Z1 = FAN_D, FAN_D + 7.0   # faisceau AU-DESSUS des ventilateurs (montage « pull ») : la grille se voit
FANS = (-30.5, 0.0, 30.5)

# ------------------------------------------------------------------ faisceau : tubes plats + ailettes zigzag
tubes_y = [-13.5 + 1.5 * i for i in range(19)]
body = []
for y in tubes_y:
    body.append(rbox((2 * CX, 0.36, Z1 - Z0 - 0.3), (0, y, (Z0 + Z1) / 2)))
bm = bmesh.new()
TH = 0.09  # épaisseur de la tôle ondulée (le dessus du zigzag se voit d'en haut)
for ya, yb in zip(tubes_y[:-1], tubes_y[1:]):
    y0, y1 = ya + 0.2, yb - 0.2
    n = int(2 * CX / 0.9)
    pts = [Vector((-CX + k * 2 * CX / n, y0 if k % 2 == 0 else y1)) for k in range(n + 1)]
    L, R = [], []
    for k, p in enumerate(pts):
        q = pts[min(k + 1, n)] - pts[max(k - 1, 0)]
        nr = Vector((-q.y, q.x)).normalized() * TH / 2
        L.append(p + nr); R.append(p - nr)
    ring = [(L, Z1 - 0.12), (R, Z1 - 0.12), (R, Z0 + 0.12), (L, Z0 + 0.12)]
    vs = [[bm.verts.new((v.x, v.y, z)) for v in side] for side, z in ring]
    for a in range(4):  # 4 nappes : gauche, dessus, droite, dessous
        A, B = vs[a], vs[(a + 1) % 4]
        for k in range(n):
            bm.faces.new((A[k], A[k + 1], B[k + 1], B[k]))
bmesh.ops.recalc_face_normals(bm, faces=bm.faces)
fins = obj_from_bm(bm, "Fins")
tag(fins, "Fins", "Metal", ALU_DARK)

# flasques latérales (profil en U) avec trous de fixation des ventilateurs
for sy in (-1, 1):
    fl = rbox((2 * CX + 0.6, 1.1, Z1 - Z0), (0, sy * 14.85, (Z0 + Z1) / 2), r=0.12, seg=2)
    cut = [rbox((2 * CX - 4, 0.6, Z1 - Z0 - 1.6), (0, sy * 15.45, (Z0 + Z1) / 2))]
    for fx in FANS:
        for dx in (-12.75, 12.75):
            for zz in (Z1, Z0):
                cut.append(rcyl(0.32, 1.2, (fx + dx, sy * 14.6, zz), verts=12))
    bool_op(fl, cut)
    body.append(fl)

# boîtes à eau (end tanks) sculptées
for sx in (-1, 1):
    x0 = sx * (CX + 5.2)
    out = crect(10.4, 33.0, 2.2, (x0, 0))
    mid = crect(10.4, 33.0, 2.2, (x0, 0))
    top = crect(8.6, 30.6, 1.6, (x0 - sx * 0.6, 0))
    tank = loft([(out, Z0 - 0.2), (mid, Z0 + 6.6), (top, Z0 + 8.2)])
    cut = [rprism([(x0 + sx * 2.4 - 0.25, -12), (x0 + sx * 2.4 + 0.25, -12), (x0 + sx * 2.4 + 0.25, 12),
                   (x0 + sx * 2.4 - 0.25, 12)], Z0 + 7.9, Z0 + 9)]
    for k in range(5):  # nervures sur la face d'extrémité
        z = Z0 + 1.4 + k * 1.1
        cut.append(prism_x([(-10, z), (10, z), (10.6, z + 0.4), (-10.6, z + 0.4)], x0 + sx * 5.0 - 0.3, x0 + sx * 5.0 + 0.3)
                   if sx > 0 else prism_x([(-10, z), (10, z), (10.6, z + 0.4), (-10.6, z + 0.4)],
                                          x0 - 5.0 - 0.3, x0 - 5.0 + 0.3))
    bool_op(tank, cut)
    bev(tank, 0.15, 2, 30)
    body.append(tank)
body = merge(body)
tag(body, "Body", "Metal", GRAPHITE_0)

# ------------------------------------------------------------------ raccords nickelés + durites gainées
nickel, hoses = [], []
XE = CX + 10.4
for sy in (-1, 1):
    y = sy * 7.0
    z = Z0 + 3.6
    # raccord à compression : embase hexagonale + bague moletée + olive
    nickel.append(rcyl(1.55, 0.9, (XE + 0.45, y, z), verts=6, rot=(0, math.pi / 2, 0), bevel_w=0.08))
    knurl = rcyl(1.45, 2.2, (XE + 2.0, y, z), verts=24, rot=(0, math.pi / 2, 0), bevel_w=0.12)
    nickel.append(knurl)
    nickel.append(rcyl(1.2, 0.8, (XE + 3.4, y, z), verts=32, rot=(0, math.pi / 2, 0), bevel_w=0.15))
    pts = [(XE + 3.2, y, z), (XE + 6.5, y, z + 0.3), (XE + 9.0, y * 1.2, z + 3.5), (XE + 8.5, y * 1.5, z + 9.0),
           (XE + 4.0, y * 1.7, z + 12.5), (XE - 1.5, y * 1.8, z + 13.2)]
    hoses.append(pipe(pts, 1.05, 16, 8, cap=True))
    # ferrule au bout libre
    nickel.append(rcyl(1.3, 1.6, (XE - 1.2, y * 1.8, z + 13.2), verts=32, rot=(0, math.pi / 2, 0), bevel_w=0.15))
# bouchon de remplissage sur l'autre boîte
nickel.append(rcyl(1.3, 0.6, (-CX - 5.8, 9.0, Z0 + 8.3), verts=6, bevel_w=0.08))
nickel.append(screw(0.9, 0.4, (-CX - 5.8, 9.0, Z0 + 8.55), slot="hex"))
# vis de ventilateurs (tête bombée) aux 4 coins de chaque ventilateur
for fx in FANS:
    for dx in (-12.75, 12.75):
        for dy in (-12.75, 12.75):
            nickel.append(screw(0.55, 0.35, (fx + dx, dy, -0.33), rot=(math.pi, 0, 0)))
tag(merge(nickel), "Fittings", "Metal", NICKEL)
tag(merge(hoses), "Hoses", "Fabric", GRAPHITE_0)

# plaque logo alu sur la boîte +X
plate = rprism(crect(6.0, 14.0, 1.2, (CX + 4.6, 0)), Z0 + 8.1, Z0 + 8.45)
bev(plate, 0.08, 1, 30)
logo = text_mesh("A", 4.4, 0.18, (CX + 4.6, 0, Z0 + 8.4), (0, 0, math.pi / 2))
tag(merge([plate, logo]), "Badge", "Metal", ALU)

# ------------------------------------------------------------------ 3 ventilateurs
frames, rings, pads = [], [], []
for i, fx in enumerate(FANS):
    fr = fan_frame(FAN_S, FAN_D, BORE, corner_r=1.8, flange=1.0, shroud=14.6, struts=4, motor_r=4.2, z0=0.0)
    xf(fr, (fx, 0, 0))
    frames.append(fr)
    rot = fan_rotor(13.7, 4.6, 9, 1.8, 5.9, sweep=0.55, ring=True, thick=0.16)
    rot.location.x += fx
    tag(rot, f"Rotor{i + 1}", "SmoothPlastic", GRAPHITE_2, spin=True)
    rings.append(lathe([(14.15, 0.1), (15.2, 0.1), (15.25, -0.08), (14.9, -0.18), (14.4, -0.18), (14.18, -0.08)],
                       72, (fx, 0, 0), closed=True))
    rings.append(lathe([(14.6, FAN_D * 0.45), (14.8, FAN_D * 0.45), (14.8, FAN_D * 0.55),
                        (14.6, FAN_D * 0.55)], 72, (fx, 0, 0), closed=True))
    p = fan_pads(FAN_S, FAN_D, BORE, 0.0, t=0.35)
    xf(p, (fx, 0, 0))
    pads.append(p)
tag(merge(frames), "FanFrames", "SmoothPlastic", GRAPHITE_0)
tag(merge(rings), "Argb", "Neon", "63B3ED")
tag(merge(pads), "Pads", "Plastic", "2A3F57")

done("AioRadiator", camera=(0.8, -1.3, 1.1))
qa_view("AioRadiator_grid", (0.3, -0.6, 1.0), zoom=3.0, target=(-20, 0, 12))
qa_view("AioRadiator_under", (0.5, -1.0, -0.9), zoom=1.2)
qa_view("AioRadiator_end", (1.2, -0.6, 0.5), zoom=2.2, target=(50, 0, 6))
