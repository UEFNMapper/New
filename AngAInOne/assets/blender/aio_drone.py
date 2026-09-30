"""AioDrone — l'aéroglisseur de l'app AngAInOne sur lequel mini-Anga suit le joueur (compagnon).
Disque volant arrondi gris Fluent (#2B2B2B / #C5C5C5), anneau néon violet #8B7CFF tout autour, pont supérieur
antidérapant où se tient Anga, badge avant avec le logo « A » de l'app en néon, lueur néon dessous et
4 petits rotors carénés (pièces __Spin, axe vertical). ~2,6 studs de diamètre, face avant vers -Y
(comme les personnages), origine au centre de la base."""
from char_common import *

new_scene()
kit = Kit()

DECK, SHELL, ACCENT, GLOW, BLADE = "2B2B2B", "C5C5C5", "8B7CFF", "B9B0FF", "E6E6EA"
RD = 1.0          # rayon du disque
ZB = 0.18         # dessous du disque (sous : lueur)
ZT = 0.52         # dessus du pont

# --- coque : galet arrondi (profil de révolution), gris clair
hull = lathe([(0.0, ZB - 0.02), (0.55, ZB - 0.02), (0.82, ZB + 0.02), (RD - 0.02, ZB + 0.1), (RD + 0.06, ZB + 0.2),
              (RD + 0.06, ZT - 0.12), (RD - 0.02, ZT - 0.04), (RD - 0.12, ZT - 0.01), (0.0, ZT - 0.01)],
             segments=72)
shade(hull, flat_angle=None)
kit.add("Shell", "SmoothPlastic", SHELL, hull)

# --- pont supérieur gris foncé (légèrement bombé) avec rainures concentriques
deck = lathe([(0.0, ZT - 0.02), (RD - 0.16, ZT - 0.02), (RD - 0.13, ZT + 0.01), (RD - 0.16, ZT + 0.04),
              (0.0, ZT + 0.05)], segments=96)
grooves = [torus(r, 0.012, (0, 0, ZT + 0.045), major=96, minor=6) for r in (0.32, 0.56)]
kit.add("Deck", "SmoothPlastic", DECK, deck, grooves)

# --- anneau néon violet (tout le tour) + fin liseré sur le pont
ring = torus(RD + 0.08, 0.055, (0, 0, (ZB + ZT) / 2 + 0.02), major=96, minor=10)
inlay = torus(RD - 0.2, 0.022, (0, 0, ZT + 0.04), major=96, minor=8)
kit.add("Ring", "Neon", ACCENT, ring, inlay)

# --- dessous : moteur central (dôme) et lueur de sustentation
dome = lathe([(0.0, ZB - 0.14), (0.3, ZB - 0.12), (0.46, ZB - 0.04), (0.5, ZB), (0.0, ZB)], segments=64)
kit.add("Deck", "SmoothPlastic", DECK, dome)
glow = torus(0.36, 0.05, (0, 0, ZB - 0.09), major=64, minor=10)
core = qsphere(0.2, (0, 0, ZB - 0.12), (1, 1, 0.45), level=3, name="Core")
kit.add("Glow", "Neon", GLOW, glow, core)

# --- badge avant (-Y) avec le logo « A » de l'app en néon
BY = -(RD + 0.06)
badge = rbox((0.56, 0.14, 0.32), (0, BY - 0.02, (ZB + ZT) / 2 + 0.03), radius=0.07, segments=4)
kit.add("Deck", "SmoothPlastic", DECK, badge)


def a_logo(cx, cz, h, w, y, depth, name="Logo"):
    """« A » massif en 3 traits (comme sur le t-shirt d'Anga), face vers -Y."""
    half, stem, top = w / 2, w * 0.24, w * 0.16
    parts = []
    for pts in (
        [(-half, -h / 2), (-half + stem, -h / 2), (top / 2, h / 2), (-top / 2, h / 2)],
        [(half - stem, -h / 2), (half, -h / 2), (top / 2, h / 2), (-top / 2, h / 2)],
        [(-w * 0.29, -h * 0.2), (w * 0.29, -h * 0.2), (w * 0.25, -h * 0.03), (-w * 0.25, -h * 0.03)],
    ):
        bm = bmesh.new()
        verts = [bm.verts.new((cx + x, y, cz + z)) for x, z in pts]
        bm.faces.new(verts)
        ext = bmesh.ops.extrude_face_region(bm, geom=list(bm.faces))
        for v in [e for e in ext["geom"] if isinstance(e, bmesh.types.BMVert)]:
            v.co.y -= depth
        bmesh.ops.recalc_face_normals(bm, faces=bm.faces)
        me = bpy.data.meshes.new(name)
        bm.to_mesh(me); bm.free()
        o = bpy.data.objects.new(name, me)
        bpy.context.collection.objects.link(o)
        shade(o, flat_angle=40)
        parts.append(o)
    return parts


kit.add("Logo", "Neon", ACCENT, a_logo(0, (ZB + ZT) / 2 + 0.03, 0.2, 0.24, BY - 0.09, 0.025))
# petit « A » gravé sur le pont, devant les pieds d'Anga (lisible de face, vers -Y)
deck_logo = a_logo(0, 0, 0.26, 0.3, 0, 0.02)
for o in deck_logo:
    xf_matrix(o, Matrix.Translation(V((0, -0.62, ZT + 0.045))) @ Matrix.Rotation(-math.pi / 2, 4, "X"))
kit.add("Logo", "Neon", ACCENT, deck_logo)

# --- 4 rotors carénés aux diagonales (carénage gris clair, bras, pales qui tournent)
for k, ang in enumerate((45, 135, 225, 315)):
    a = math.radians(ang)
    c = V((math.cos(a) * (RD + 0.3), math.sin(a) * (RD + 0.3), ZT - 0.12))
    duct = lathe([(0.2, -0.07), (0.25, -0.07), (0.27, -0.03), (0.27, 0.05), (0.25, 0.08), (0.2, 0.08),
                  (0.2, -0.07)], segments=48, close_bottom=False, close_top=False)
    xf(duct, c)
    arm = sweep([V((math.cos(a) * (RD - 0.1), math.sin(a) * (RD - 0.1), ZT - 0.14)),
                 V((math.cos(a) * (RD + 0.1), math.sin(a) * (RD + 0.1), ZT - 0.12))], 0.055, ring=12, name="Arm")
    kit.add("Shell", "SmoothPlastic", SHELL, duct, arm)
    hub = qsphere(0.05, c + V((0, 0, 0.01)), (1, 1, 0.7), level=2, name="Hub")
    blades = []
    for b in range(3):
        ba = a + b * 2 * math.pi / 3
        d = V((math.cos(ba), math.sin(ba), 0))
        blades.append(sweep([c + d * 0.03, c + d * 0.1 + V((0, 0, 0.005)), c + d * 0.18], [0.035, 0.045, 0.028],
                            ring=8, samples=3, flat=(1, 0.25), twist=0.0, name="Blade", up=(0, 0, 1)))
    kit.add(f"Rotor{k + 1}", "SmoothPlastic", BLADE, hub, blades, spin=True, pivot=c)

# taille finale : 2,6 studs de diamètre hors tout (anneau et rotors compris)
objs = kit.objects()
xs = [v.co.x for o in objs for v in o.data.vertices]
k = 2.6 / (max(xs) - min(xs))
z0 = ground_check(objs)
m = Matrix.Scale(k, 4) @ Matrix.Translation(V((0, 0, -z0)))
for o in objs:
    xf_matrix(o, m)
for p in kit.parts.values():
    if p["pivot"] is not None:
        p["pivot"] = m @ V(p["pivot"])
kit.build()
finish("AioDrone", camera=cam((0.8, -2.2, 1.3)), samples=64)
