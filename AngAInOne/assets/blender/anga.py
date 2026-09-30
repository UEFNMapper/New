"""Anga — la mascotte d'AngaTV / de l'app AngAInOne, 6 studs de haut, debout, regarde vers -Y.
Style « jouet » chibi (grosse tête) d'après assets/branding/anga_portrait.png : houppe blonde en pointes,
barbe courte et moustache blondes, grand sourire bouche ouverte, yeux-points, joues roses, gros nez,
t-shirt rouge avec le logo « A » en relief sur la poitrine, pantalon noir, baskets.
Sert au compagnon (mini-Anga sur son drone AioDrone) et à l'Anga géant du lobby : détails nets de près."""
from char_common import *

new_scene()
kit = Kit()

SKIN, HAIR, BEARD = "F2C9A8", "F0C24F", "D2A24A"
SHIRT, LOGO, PANTS, DARK = "E53E3E", "FFD3DA", "24242B", "1B1B2F"
WHITE, MOUTH, TONGUE, BLUSH = "FFFFFF", "5E1C24", "EE7F8B", "F29A9A"

# ---------------------------------------------------------------------------------------------
# Tête (grosse, chibi) : centre HC, rayons R * HS
# ---------------------------------------------------------------------------------------------
HZ, R = 4.3, 1.15
HC = V((0, 0, HZ))
HS = (1.0, 0.93, 1.05)


def dirn(p):
    """Direction normalisée (repère de la tête, ellipsoïde ramené à une sphère)."""
    q = p - HC
    return V((q.x / HS[0], q.y / HS[1], q.z / HS[2])).normalized()


head = qsphere(R, HC, HS, level=4, name="Head")
# mâchoire un peu plus large (visage « carré-rond » du portrait), crâne légèrement plus étroit
deform(head, lambda p: V((p.x * (1 + 0.07 * smoothstep(HZ + 0.4, HZ - 0.7, p.z)), p.y, p.z)))
kit.add("Skin", "SmoothPlastic", SKIN, head)
tree = bvh(head)


def on_face(x, z, lift=0.0):
    loc, nrm = surface_point(tree, x, z)
    return loc - V((0, lift, 0)), nrm


# oreilles
for sx in (-1, 1):
    ear = qsphere(0.26, (sx * R * 0.99, 0.08, HZ + 0.02), (0.55, 0.75, 1.1), level=3, name="Ear")
    inner = qsphere(0.13, (sx * R * 1.08, 0.02, HZ + 0.02), (0.4, 0.6, 1.0), level=2, name="EarIn")
    kit.add("Skin", "SmoothPlastic", SKIN, ear)
    kit.add("Blush", "SmoothPlastic", BLUSH, inner)

# nez (gros, rond, un peu vers le bas)
n0, _ = on_face(0, HZ + 0.05)
n1, _ = on_face(0, HZ - 0.12)
nose = sweep([n0 + V((0, 0.05, 0)), n1 + V((0, -0.2, 0))], [0.12, 0.2], ring=16, samples=4, name="Nose")
kit.add("Skin", "SmoothPlastic", SKIN, nose)

# yeux-points (ovales noirs + reflet) et sourcils levés (joyeux)
for sx in (-1, 1):
    loc, nrm = on_face(sx * 0.4, HZ + 0.2)
    eye = qsphere(0.105, loc + V((0, 0.02, 0)), (0.85, 0.45, 1.25), level=3, name="Eye")
    kit.add("Dark", "SmoothPlastic", DARK, eye)
    kit.add("White", "SmoothPlastic", WHITE,
            qsphere(0.035, loc + V((-0.03 * sx - 0.01, -0.035, 0.05)), (1, 0.5, 1), level=2, name="Shine"))
    b = [on_face(sx * x, HZ + z)[0] + V((0, -0.04, 0)) for x, z in ((0.17, 0.53), (0.39, 0.6), (0.62, 0.5))]
    kit.add("Hair", "SmoothPlastic", HAIR, sweep(b, [0.05, 0.075, 0.045], ring=10, flat=(1, 0.6), name="Brow"))

# joues roses
for sx in (-1, 1):
    pts = [(0.17 * math.cos(2 * math.pi * i / 32), 0.11 * math.sin(2 * math.pi * i / 32)) for i in range(32)]
    kit.add("Blush", "SmoothPlastic", BLUSH,
            patch(pts, tree, (sx * 0.64, -10, HZ - 0.08), (1, 0, 0), (0, 0, 1), (0, 1, 0), lift=0.0,
                  thickness=0.02, cuts=2, name="Cheek"))

# ---------------------------------------------------------------------------------------------
# Bouche grande ouverte (forme en D : bord haut qui remonte aux coins, bas arrondi)
# ---------------------------------------------------------------------------------------------
MZ, MW, MH = HZ - 0.36, 0.86, 0.46


def mouth_outline(w, h, n=40):
    pts = []
    for i in range(n + 1):  # bord haut, de gauche à droite
        x = -w / 2 + w * i / n
        pts.append((x, 0.07 * (2 * x / w) ** 2 - 0.02 * (1 - (2 * x / w) ** 2)))
    for i in range(1, n):  # bas arrondi, de droite à gauche
        a = math.pi * i / n
        x = w / 2 * math.cos(a)
        pts.append((x, -h * math.sin(a) ** 0.85 + 0.07 * (2 * x / w) ** 2 * (1 - math.sin(a))))
    return pts


def in_mouth(x, z, grow=0.0):
    """Le point (x, z) de face est-il dans la bouche (agrandie de `grow`) ?"""
    u = x / (MW / 2 + grow)
    if abs(u) >= 1:
        return False
    top = MZ + 0.07 * u * u + grow
    bottom = MZ - (MH + grow) * math.sqrt(max(0.0, 1 - u * u)) ** 0.85
    return bottom < z < top


mouth = patch(mouth_outline(MW, MH), tree, (0, -10, MZ), (1, 0, 0), (0, 0, 1), (0, 1, 0), lift=-0.02,
              thickness=0.06, cuts=3, name="Mouth")
kit.add("Mouth", "SmoothPlastic", MOUTH, mouth)
tongue_pts = [(0.25 * math.cos(2 * math.pi * i / 32), 0.13 * math.sin(2 * math.pi * i / 32)) for i in range(32)]
tongue = patch(tongue_pts, tree, (0.02, -10, MZ - MH + 0.14), (1, 0, 0), (0, 0, 1), (0, 1, 0), lift=0.02,
               thickness=0.04, cuts=2, name="Tongue")
kit.add("Tongue", "SmoothPlastic", TONGUE, tongue)
teeth_pts = []
for i in range(25):
    x = -0.36 + 0.72 * i / 24
    teeth_pts.append((x, 0.06 * (x / 0.43) ** 2 - 0.03))
for i in range(25):
    x = 0.36 - 0.72 * i / 24
    teeth_pts.append((x, 0.06 * (x / 0.43) ** 2 - 0.13 + 0.03 * (x / 0.36) ** 2))
teeth = patch(teeth_pts, tree, (0, -10, MZ), (1, 0, 0), (0, 0, 1), (0, 1, 0), lift=0.02, thickness=0.04,
              cuts=2, name="Teeth")
kit.add("White", "SmoothPlastic", WHITE, teeth)


# ---------------------------------------------------------------------------------------------
# Coques (cheveux, barbe) : sphère FERMÉE autour de la tête. Hors de la zone, la coque plonge sous la
# peau : le bord visible est l'intersection avec la tête, donc une courbe lisse (pas d'escalier).
# ---------------------------------------------------------------------------------------------
def shell(zone, height, soft=0.06, level=5, name="Shell"):
    """zone(d, co) > 0 dans la zone (distance approx.) ; height(d, co) = épaisseur au-dessus de la peau."""
    o = qsphere(R, HC, HS, level=level, name=name)
    deform(o, lambda p: V((p.x * (1 + 0.07 * smoothstep(HZ + 0.4, HZ - 0.7, p.z)), p.y, p.z)))
    hidden = set()
    for v in o.data.vertices:
        d = dirn(v.co)
        g = zone(d, v.co)
        s = smoothstep(-soft, soft, g)
        off = -0.12 + (height(d, v.co) + 0.12) * s
        if s <= 0.0:
            hidden.add(v.index)
        v.co = v.co + (v.co - HC).normalized() * off
    o.data.update()
    bm = bmesh.new(); bm.from_mesh(o.data)
    bm.verts.ensure_lookup_table()
    dead = [f for f in bm.faces if all(v.index in hidden for v in f.verts)]
    bmesh.ops.delete(bm, geom=dead, context="FACES")
    bm.to_mesh(o.data); bm.free()
    shade(o)
    return o


def spike(d, axis, amp, width_deg, power=1.6):
    c = math.cos(math.radians(width_deg))
    k = d.dot(V(axis).normalized())
    return amp * ((k - c) / (1 - c)) ** power if k > c else 0.0


# --- cheveux : casque de base (volume) ; les pointes de la houppe sont des mèches effilées à part
VOLUME = [
    ((0.1, -0.5, 0.86), 0.42, 45),     # houppe avant (gonflée)
    ((0.25, -0.1, 0.96), 0.22, 35),
    ((-0.25, 0.1, 0.96), 0.12, 35),
]


def hair_height(d, co):
    h = 0.07 + 0.1 * smoothstep(0.0, 0.8, d.z)
    for axis, amp, w in VOLUME:
        h += spike(d, axis, amp, w, power=1.3)
    # petites vagues de mèches
    h += 0.025 * math.sin(9 * math.atan2(d.x, -d.y) + 4 * d.z)
    return h


def hair_zone(d, co):
    line = 0.3 + 0.28 * (-d.y) if d.y < 0 else 0.3 - 0.8 * d.y
    # tempes : descend devant les oreilles (rejoint les favoris de la barbe)
    line -= 0.18 * smoothstep(0.7, 0.95, abs(d.x)) * smoothstep(0.3, -0.2, d.y)
    return d.z - line


hair = shell(hair_zone, hair_height, level=5, name="Hair")
kit.add("Hair", "SmoothPlastic", HAIR, hair)

# mèches en pointe (houppe relevée, pointe haute côté +X, comme le portrait)
TUFTS = [  # (départ sur le crâne : direction), direction de la pointe, longueur, rayon
    ((0.15, -0.6, 0.78), (0.2, 0.35, 1.0), 0.9, 0.5),        # grosse houppe avant, peignée en arrière
    ((0.42, -0.35, 0.84), (0.55, 0.0, 1.0), 1.0, 0.34),      # mèche relevée en pointe, côté +X
    ((-0.2, -0.55, 0.8), (-0.15, 0.7, 0.8), 0.7, 0.44),
    ((-0.5, -0.3, 0.8), (-0.6, 0.75, 0.4), 0.55, 0.36),
    ((0.05, 0.25, 0.96), (0.0, 1.0, 0.2), 0.5, 0.4),
    ((0.55, 0.0, 0.83), (0.55, 0.85, 0.2), 0.5, 0.34),
]
htree = bvh(hair)
tufts = []
for base, tip, length, radius in TUFTS:
    b = V(base).normalized()
    start = HC + V((b.x * R * HS[0], b.y * R * HS[1], b.z * R * HS[2])) * 2.2
    loc, nrm = raycast(htree, start, HC - start)
    if loc is None:
        continue
    t = V(tip).normalized()
    p0 = loc - nrm * radius * 0.6
    p1 = loc + (nrm * 0.55 + t * 0.45).normalized() * length * 0.5
    p2 = loc + (nrm * 0.12 + t * 0.88).normalized() * length
    tufts.append(sweep([p0, p1, p2], [radius, radius * 0.72, 0.05], ring=16, samples=6, flat=(1, 0.75),
                       name="Tuft"))
kit.add("Hair", "SmoothPlastic", HAIR, tufts)


# --- barbe courte : mâchoire, menton, favoris, trou de la bouche ; moustache par-dessus
def mouth_gap(co):
    """> 0 hors de la bouche (distance approx. en studs, agrandie de 0,04)."""
    a, b = MW / 2 + 0.04, MH / 2 + 0.05
    zc = MZ - MH / 2 + 0.02
    return (math.sqrt((co.x / a) ** 2 + ((co.z - zc) / b) ** 2) - 1) * min(a, b)


def beard_zone(d, co):
    line = -0.44 + 0.6 * abs(d.x) ** 3
    g = line - d.z
    g = min(g, 0.3 - d.y)
    if co.y < 0:
        g = min(g, mouth_gap(co) * 1.5)
    return g


def beard_height(d, co):
    chin = 0.12 * smoothstep(-0.35, -0.95, d.z) * max(0.0, -d.y)
    return 0.07 + chin + 0.018 * noise.noise(co * 7.0)


beard = shell(beard_zone, beard_height, soft=0.05, level=5, name="Beard")
m0 = on_face(-0.46, MZ + 0.06, 0.09)[0]
m1 = on_face(-0.22, MZ + 0.14, 0.12)[0]
m2 = on_face(0.0, MZ + 0.12, 0.12)[0]
m3 = on_face(0.22, MZ + 0.14, 0.12)[0]
m4 = on_face(0.46, MZ + 0.06, 0.09)[0]
stache = sweep([m0, m1, m2, m3, m4], [0.05, 0.1, 0.09, 0.1, 0.05], ring=12, samples=5, flat=(1, 0.7),
               name="Stache")
kit.add("Beard", "SmoothPlastic", BEARD, beard, stache)

# ---------------------------------------------------------------------------------------------
# Corps : t-shirt rouge (bedon), logo « A », bras, pantalon, baskets
# ---------------------------------------------------------------------------------------------
neck = sweep([V((0, 0.05, 2.9)), V((0, 0.05, 3.5))], 0.42, ring=20, name="Neck")
kit.add("Skin", "SmoothPlastic", SKIN, neck)

torso = rbox((1.95, 1.4, 1.75), (0, 0, 2.22), radius=0.62, segments=5)
subsurf(torso, 1)
# bedon : plus large en bas, ventre un peu en avant
deform(torso, lambda p: V((p.x * (0.93 + 0.1 * smoothstep(3.1, 1.8, p.z)),
                           p.y - 0.08 * smoothstep(3.0, 2.0, p.z) * max(0.0, -p.y), p.z)))
collar = torus(0.45, 0.07, (0, 0.03, 3.05), major=40, minor=10)
kit.add("Shirt", "SmoothPlastic", SHIRT, torso, collar)
ttree = bvh(torso)

# logo « A » en relief : deux jambages, un sommet arrondi, une barre (formes projetées sur le ventre)
LZ, LH = 2.3, 0.82


def quad(a, b, c, d, n=6):
    pts = []
    for p0, p1 in ((a, b), (b, c), (c, d), (d, a)):
        for i in range(n):
            t = i / n
            pts.append((p0[0] + (p1[0] - p0[0]) * t, p0[1] + (p1[1] - p0[1]) * t))
    return pts


half, top_w, stem = 0.42, 0.14, 0.2
strokes = [
    quad((-half, -LH / 2), (-half + stem, -LH / 2), (top_w / 2 + 0.02, LH / 2), (-top_w / 2 - 0.02, LH / 2)),
    quad((half - stem, -LH / 2), (half, -LH / 2), (top_w / 2 + 0.02, LH / 2), (-top_w / 2 - 0.02, LH / 2)),
    quad((-0.24, -0.16), (0.24, -0.16), (0.21, -0.02), (-0.21, -0.02)),
]
logo = [patch(s, ttree, (0, -10, LZ), (1, 0, 0), (0, 0, 1), (0, 1, 0), lift=0.0, thickness=0.06, cuts=3,
              name="Logo") for s in strokes]
kit.add("Logo", "SmoothPlastic", LOGO, logo)

# bras : manche courte rouge, bras nu, main ronde (légèrement écartés)
for sx in (-1, 1):
    sh = V((sx * 0.86, 0.02, 2.85))
    el = V((sx * 1.18, 0.0, 2.3))
    hand = V((sx * 1.26, -0.08, 1.62))
    sleeve = sweep([sh, sh + (el - sh) * 0.6], [0.36, 0.33], ring=20, samples=3, name="Sleeve")
    cuff = torus(0.31, 0.05, sh + (el - sh) * 0.6, rot=V((0, 0, 1)).rotation_difference(el - sh).to_euler(),
                 major=28, minor=8)
    kit.add("Shirt", "SmoothPlastic", SHIRT, sleeve, cuff)
    arm = sweep([sh + (el - sh) * 0.4, el, hand], [0.22, 0.21, 0.19], ring=16, samples=4, name="Arm")
    mitt = qsphere(0.25, hand + V((0, 0, -0.12)), (0.95, 0.85, 1.1), level=3, name="Hand")
    thumb = qsphere(0.1, hand + V((-sx * 0.1, -0.18, -0.02)), (1, 1, 1.3), level=2, name="Thumb")
    kit.add("Skin", "SmoothPlastic", SKIN, arm, mitt, thumb)

# pantalon noir : bassin + jambes courtes
hips = rbox((1.72, 1.25, 0.6), (0, 0.02, 1.42), radius=0.28, segments=4)
legs = [sweep([V((sx * 0.43, 0.02, 1.35)), V((sx * 0.45, 0.0, 0.42))], [0.4, 0.36], ring=20, samples=3,
              name="Leg") for sx in (-1, 1)]
kit.add("Pants", "SmoothPlastic", PANTS, hips, legs)

# baskets : dessus sombre, semelle blanche qui épouse la chaussure (tranche basse, un peu plus large)
for sx in (-1, 1):
    shoe = rbox((0.66, 0.98, 0.4), (sx * 0.46, -0.14, 0.28), radius=0.18, segments=4)
    toe = qsphere(0.34, (sx * 0.46, -0.5, 0.27), (0.97, 0.9, 0.62), level=3, name="Toe")
    deform(toe, lambda p: V((p.x, p.y, max(p.z, 0.08))))
    whole = join([copy(shoe), copy(toe)])
    sole = slab(whole, 0.0, 0.12)
    delete(whole)
    xf_matrix(sole, Matrix.Translation(V((sx * 0.46, -0.3, 0))) @ Matrix.Diagonal(V((1.05, 1.04, 1.0, 1.0)))
              @ Matrix.Translation(V((-sx * 0.46, 0.3, 0))))
    kit.add("Dark", "SmoothPlastic", DARK, shoe, toe)
    kit.add("White", "SmoothPlastic", WHITE, sole)

drop_to_ground(kit.objects())
kit.fit_height(6.0)
kit.build()
finish("Anga", camera=cam((0.75, -2.4, 0.85)), samples=64)
