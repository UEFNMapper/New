"""MicArm — bras articulé de streaming (≈165 studs) : pince de bureau, bras parallélogramme à ressorts
apparents, articulations à molettes, suspension anti-choc à cordons, micro broadcast (grille en vrai
maillage), bague LED « ON AIR » rouge, filtre anti-pop sur col de cygne, câble XLR avec attaches.

ATTENTION placement : la pince enserre un plateau de 20 studs. z = 0 = DESSUS du bureau, le bord du
bureau est en y = +8 (repère de modélisation, avant rotation) ; la mâchoire inférieure descend à z ≈ −36.
Modélisé façade (côté streamer) vers −Y puis tourné à l'export."""
from room_common import *

reset()
X = Vector((1, 0, 0))
arm, steel, red, cable_parts = [], [], [], []

# ---------------------------------------------------------------- pince (autour du bord du bureau)
EDGE = 8.0
arm.append(rbox((16, 26, 4.0), (0, EDGE - 11, 2.0), r=1.2, seg=3))           # mâchoire haute
arm.append(rbox((16, 5, 44), (0, EDGE + 2.5, -18), r=1.4, seg=3))             # dos
arm.append(rbox((16, 22, 4.0), (0, EDGE - 9, -26), r=1.2, seg=3))             # mâchoire basse
arm.append(rbox((13, 20, 0.8), (0, EDGE - 11, 0.4), r=0.3, seg=2))            # (patin sous mâchoire haute)
# vis de serrage + plateau de pression + poignée en T
steel.append(cyl(1.3, 16, (0, EDGE - 12, -36), verts=16))
arm.append(cyl(5.0, 1.8, (0, EDGE - 12, -21.8), verts=32, bev=0.5))
arm.append(cyl(2.6, 4.0, (0, EDGE - 12, -39.5), verts=24, bev=0.6))
steel.append(cyl(0.9, 16, (-8, EDGE - 12, -37.5), rot=(0, math.pi / 2, 0), verts=12))
for sx in (-1, 1):
    arm.append(uvsphere(1.6, (sx * 8, EDGE - 12, -37.5), 16, 8))

# ---------------------------------------------------------------- colonne pivotante
P0 = Vector((0, EDGE - 11, 34))
arm.append(cyl(5.2, 6, (P0.x, P0.y, 4), verts=40, bev=1.0))                   # embase
steel.append(cyl(2.8, 24, (P0.x, P0.y, 9), verts=32))                         # fût inox
arm.append(cyl(3.6, 4.5, (P0.x, P0.y, 16), verts=32, bev=0.6))               # bague de blocage
arm.append(cyl(1.2, 5, (0, P0.y, 18.2), rot=(0, math.pi / 2, 0), verts=12))   # vis de blocage
arm.append(uvsphere(2.0, (5.4, P0.y, 18.2), 16, 8, scale=(0.8, 1, 1)))


def knob(p, side=1):
    """Molette de tension moletée sur l'axe X."""
    star = [((3.4 if i % 2 else 3.0) * math.cos(TAU * i / 24), (3.4 if i % 2 else 3.0) * math.sin(TAU * i / 24))
            for i in range(24)]
    k = extrude(star, 0, 2.6, "Knob", angle=30)
    bevel_all(k, 0.3, 2, angle=50)
    xf(k, rot=(0, side * math.pi / 2, 0))
    return xf(k, loc=p + X * side * 8.2)


def joint(p, width=15, r=4.6):
    arm.append(cyl(r, width, p - X * width / 2, rot=(0, math.pi / 2, 0), verts=40, bev=0.8))
    steel.append(cyl(r * 0.45, width + 1.2, p - X * (width + 1.2) / 2, rot=(0, math.pi / 2, 0), verts=24, bev=0.3))
    arm.append(knob(p, 1))


def segment(A, B, spring_side_up=True):
    d = (B - A).normalized()
    n = d.cross(X).normalized()            # perpendiculaire dans le plan du bras
    if n.z < 0:
        n = -n
    L = (B - A).length
    for sx in (-3.3, 3.3):                 # deux longerons
        arm.append(box_between(A + X * sx + d * 3, B + X * sx - d * 3, 2.2, 3.4, r=0.6, seg=2))
    # biellette du parallélogramme (tige fine sous les longerons)
    steel.append(cyl_between(A - n * 3.6 + d * 4, B - n * 3.6 - d * 4, 0.8, 12))
    for sx in (-1, 1):
        steel.append(cyl_between(A - n * 3.6 + d * 4 + X * sx * 0.2, A - n * 3.6 + d * 4 + X * sx * 3.2, 1.0, 12))
    # ressorts apparents de chaque côté, avec crochets et pattes d'ancrage
    for sx in (-6.4, 6.4):
        s0 = A + d * (L * 0.12) + n * 2.2 + X * sx
        s1 = A + d * (L * 0.62) + n * 2.2 + X * sx
        steel.append(spring_between(s0, s1, 1.35, 0.32, 16, sides=6))
        steel.append(cyl_between(s1, A + d * (L * 0.82) + n * 1.0 + X * sx, 0.35, 8))
        steel.append(cyl_between(A + d * (L * 0.82) + n * 1.0 + X * sx, A + d * (L * 0.82) + n * 1.0 + X * sx * 0.55, 0.6, 8))
        steel.append(cyl_between(s0, s0 - n * 1.6 + X * (-sx * 0.3), 0.5, 8))
    return d, n


P1 = P0 + Vector((0, -26, 70))
P2 = P1 + Vector((0, -74, 30))
joint(P0 + Vector((0, 0, 1.5)), width=10, r=5.2)
joint(P1)
joint(P2, width=12, r=4.2)
segment(P0 + Vector((0, 0, 1.5)), P1)
d2, n2 = segment(P1, P2)
arm.append(cyl(3.6, 4, (P0.x, P0.y, P0.z - 6.5), verts=32, bev=0.6))         # fourche de la colonne

# ---------------------------------------------------------------- tête : fourche + micro broadcast
H0 = P2 + Vector((0, -3, -3))
MIC_C = H0 + Vector((0, -10, -21))                                            # centre du micro
AX = Vector((0, -0.55, 0.835)).normalized()                                   # axe du micro (capsule vers le haut/avant)

mic_body, foam, grille = [], [], []
# corps (profil tourné) : culot XLR, fût, gorge, collerette
body_prof = [(0, -2), (3.2, -2), (4.0, -1.6), (5.8, -1.0), (6.3, 0.0), (6.4, 10), (6.1, 10.6), (6.1, 11.6), (6.4, 12.2),
             (6.4, 21.5), (7.0, 22.2), (7.2, 23.4), (6.8, 24.0)]
mb = lathe(body_prof, 48, "MicBody", angle=40)
# grille : dôme + cylindre en treillis (vrai maillage), mousse sombre dedans
gr_prof = [(7.0, 24.0), (7.0, 32.0)] + [(7.0 * math.cos(a), 32.0 + 7.0 * math.sin(a)) for a in
                                       [math.pi / 2 * k / 6 for k in range(1, 7)]]
gr = lathe(gr_prof[:-1] + [(0.01, 39.0)], 28, "Grille", angle=60)
wireframe(gr, 0.28)
fm = lathe([(6.5, 24.0), (6.5, 32.0), (5.6, 35.5), (3.5, 37.8), (0, 38.5)], 32, "Foam", angle=60)
ring_on = lathe([(7.25, 22.3), (7.35, 22.8), (7.35, 23.3), (7.25, 23.7), (6.9, 23.7), (6.9, 22.3)], 48, "OnAir")
# texte « ON AIR » sur le fût (néon rouge), enroulé
txt = text_mesh("ON AIR", 2.6, 0.5, res=2)
xf(txt, rot=(0, 0, -math.pi / 2))          # lecture le long de l'axe
xf(txt, rot=(math.pi / 2, 0, 0))
xf(txt, scale=(1, -1, 1))
bm = bmesh.new(); bm.from_mesh(txt.data); bmesh.ops.reverse_faces(bm, faces=bm.faces); bm.to_mesh(txt.data); bm.free()
xf(txt, loc=(0, -0.3, 16.5))
xf(txt, rot=(0, 0, math.pi / 2))
slice_x(txt, 0.5, -3, 3, axis=1)
for v in txt.data.vertices:  # enroulement autour de l'axe Z du micro, face vers +X
    x, y, z = v.co
    a = y / 6.4
    rr = 6.2 + (x - 0.0)
    v.co = (rr * math.cos(a), rr * math.sin(a), z)
# suspension : 2 anneaux intérieurs + 2 extérieurs + cordons croisés
inner_rings = [torus(6.9, 0.55, (0, 0, z), maj=48, mnr=8) for z in (5.0, 17.0)]
outer_rings = [torus(10.8, 0.8, (0, 0, z), maj=48, mnr=8) for z in (5.0, 17.0)]
cords = []
for z in (5.0, 17.0):
    for i in range(4):
        a0 = TAU * i / 4 + math.pi / 4
        a1 = a0 + math.pi / 3
        p0 = Vector((7.2 * math.cos(a0), 7.2 * math.sin(a0), z - 0.9))
        p1 = Vector((10.4 * math.cos(a1), 10.4 * math.sin(a1), z + 0.9))
        cords.append(cyl_between(p0, p1, 0.42, 8))
        p0 = Vector((7.2 * math.cos(a0), 7.2 * math.sin(a0), z + 0.9))
        p1 = Vector((10.4 * math.cos(a0 - math.pi / 3), 10.4 * math.sin(a0 - math.pi / 3), z - 0.9))
        cords.append(cyl_between(p0, p1, 0.42, 8))
frame_bars = [cyl_between((10.8 * math.cos(a), 10.8 * math.sin(a), 5.0), (10.8 * math.cos(a), 10.8 * math.sin(a), 17.0), 0.7, 10)
              for a in (math.pi * 0.25, math.pi * 1.25)]
yoke = [cyl_between((-11.4, 0, 11), (-15, 0, 11), 1.6, 16)]
# (tout le micro est construit le long de +Z puis orienté selon AX autour de MIC_C)
mic_group = [mb, gr, fm, ring_on, txt] + inner_rings + outer_rings + cords + frame_bars + yoke
q = AX.to_track_quat("Z", "X")
M = Matrix.Translation(MIC_C) @ q.to_matrix().to_4x4() @ Matrix.Translation((0, 0, -16))
for o in mic_group:
    o.data.transform(M)
    o.data.update()
mic_body = [mb] + outer_rings + frame_bars + yoke
steel_mic = [gr] + inner_rings
# liaison fourche → étrier de suspension
yoke_end = M @ Vector((-15, 0, 11))
# potence coudée : de l'articulation de tête jusqu'au flanc de la suspension
hang = catmull([P2 + Vector((-5, 0, 0)), P2 + Vector((-13, 0, -2)), Vector((yoke_end.x - 0.5, (P2.y + yoke_end.y) / 2, P2.z - 10)),
                yoke_end + Vector((-0.8, 0, 5)), yoke_end], 8)
arm.append(sweep(hang, 1.8, 16, name="Hanger"))
arm.append(knob(yoke_end + X * 7.4, -1))

# ---------------------------------------------------------------- filtre anti-pop sur col de cygne
cap_c = M @ Vector((0, 0, 44.5))
pop_n = AX
gq = pop_n.to_track_quat("Z", "Y")
pop_ring = torus(11.5, 0.9, (0, 0, 0), maj=64, mnr=10)
pop_ring2 = torus(11.5, 0.9, (0, 0, 1.6), maj=64, mnr=10)
pop_disc = cyl(11.3, 1.2, (0, 0, 0.2), verts=64)
pop_clip = rbox((4, 3.4, 4), (0, -12.8, 0.8), r=0.8, seg=2)
for o in (pop_ring, pop_ring2, pop_disc, pop_clip):
    o.data.transform(Matrix.Translation(cap_c) @ gq.to_matrix().to_4x4())
    o.data.update()
clip_p = Matrix.Translation(cap_c) @ gq.to_matrix().to_4x4() @ Vector((0, -14.5, 0.8))
gp = catmull([clip_p, clip_p + Vector((-3, 7, 1)), P2 + Vector((-8, -6, 3)), P2 + Vector((-7.5, 2, 1))], 12)
goose = sweep(gp, 1.1, 12, name="Goose", braid=0.14, braid_freq=4.5)
arm.append(cyl_between(P2 + Vector((-7.5, 2, 1)), P2 + Vector((-7.5, 2, -3)), 1.8, 16))

# ---------------------------------------------------------------- câble XLR le long du bras + attaches rouges
xlr_start = M @ Vector((0, 0, -3.5))
route = [xlr_start, xlr_start + Vector((0, 6, -4)), P2 + Vector((5.5, 6, -6)), P2 + Vector((5.5, 2, -2)),
         P1 + (P2 - P1) * 0.5 + Vector((5.5, 0, -4.2)), P1 + Vector((5.5, 3, -4)), P1 + Vector((5.5, 0, -8)),
         P0 + (P1 - P0) * 0.5 + Vector((5.5, 3.5, -1.5)), P0 + Vector((5.5, 4.5, 2)), P0 + Vector((5.5, 6, -14)),
         Vector((5.5, EDGE - 4, 4.8)), Vector((5.5, EDGE + 6, 4)), Vector((5.5, EDGE + 12, -6))]
cable_parts.append(sweep(catmull(route, 10), 0.9, 10, name="XLR"))
cable_parts.append(cyl_between(xlr_start, xlr_start + (xlr_start - MIC_C).normalized() * -0.1 + Vector((0, 3, -3)), 1.6, 16))
for f in (0.3, 0.7):
    for A_, B_ in ((P0, P1), (P1, P2)):
        c = A_ + (B_ - A_) * f
        d = (B_ - A_).normalized()
        tie = torus(2.2, 0.5, (0, 0, 0), maj=20, mnr=6)
        tie.data.transform(Matrix.Translation(c + Vector((3.8, 0, -1.8 if B_ is P1 else -2.2))) @
                           d.to_track_quat("Z", "Y").to_matrix().to_4x4())
        red.append(tie)

tagj(arm + [pop_ring, pop_ring2, pop_clip], "Arm", "SmoothPlastic", "16181E")
tagj(steel + [goose], "Steel", "Metal", "B8BEC8")
tagj(mic_body, "MicBody", "Metal", "2A2D38")
tagj(steel_mic, "Grille", "Metal", "C9CED6")
tagj([fm], "Foam", "Fabric", "16181E")
tagj(cords + red, "Cords", "SmoothPlastic", "E53E3E")
tagj([ring_on, txt], "OnAir", "Neon", "E53E3E")
tagj([pop_disc], "PopFilter", "Glass", "22252E")
tagj(cable_parts, "Cable", "Fabric", "22252E")


def desk_prop():
    bpy.ops.mesh.primitive_cube_add(size=1, location=(0, EDGE - 400, -10))
    d = active(); d.scale = (800, 800, 20)
    m = bpy.data.materials.new("DeskProp"); m.use_nodes = True
    m.node_tree.nodes["Principled BSDF"].inputs["Base Color"].default_value = (*hex_rgb("3B2A1E"), 1)
    m.node_tree.nodes["Principled BSDF"].inputs["Roughness"].default_value = 0.5
    d.data.materials.append(m)
    # le repère est tourné de 180° à l'export
    d.location = (0, -(EDGE - 400), -10)


done("MicArm", clip_floor=False, direction=(1.0, -0.55, 0.3), lens=50, floor=None, props=desk_prop, key=1.6, target=(0, -50, 80), margin=-0.5)
