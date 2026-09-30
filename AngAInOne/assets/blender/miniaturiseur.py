"""Miniaturiseur — capsule « Mode Intervention » d'AngAInOne (portail de départ, Ø 30 studs, échelle joueur).

Socle sculpté (chanfreins, ouïes radiales, marche d'accès), sol en tuiles hexagonales, anneau néon
violet, 3 pylônes incurvés à canal lumineux et émetteurs, armature de dôme vitré OUVERTE à l'avant,
couronne émettrice, faisceau `Beam` en champ de force (pièce séparée : le jeu peut l'animer / le
masquer), petit pupitre de commande avec `Screen` (SurfaceGui), gaine de câbles.
Modélisé entrée vers −Y puis tourné à l'export (entrée = −Z Roblox)."""
from room_common import *

reset()
shell, dark, hexm, metal, glass, glow, red = [], [], [], [], [], [], []
RB, HB = 15.0, 2.5            # rayon / hauteur du socle
DC = Vector((0, 0, HB))       # centre de la sphère du dôme
RD = 13.6
FRONT = -math.pi / 2          # entrée vers −Y

# ---------------------------------------------------------------- socle
base = lathe([(0, 2.3), (9.7, 2.3), (9.9, 2.5), (11.5, 2.5), (11.5, 2.22), (12.5, 2.22), (12.5, 2.5), (13.3, 2.5),
              (13.6, 2.35), (14.7, 1.85), (15.1, 1.45), (15.2, 1.2), (15.2, 0.35), (15.0, 0.0), (0, 0)], 96, "Base", angle=35)
vents = []
for i in range(30):
    a = TAU * i / 30
    if abs(math.atan2(math.sin(a - FRONT), math.cos(a - FRONT))) < 0.45:
        continue                                     # pas d'ouïes derrière la marche
    v = rbox((1.6, 0.45, 0.55), (0, 0, 0), r=0.18, seg=2)
    xf(v, rot=(0, 0, a + math.pi / 2))
    xf(v, loc=(15.2 * math.cos(a), 15.2 * math.sin(a), 0.8))
    vents.append(v)
boolean_diff(base, vents)
shell.append(base)
dark.append(lathe([(14.8, 0.4), (14.8, 1.2), (14.6, 1.2), (14.6, 0.4)], 96, "VentBack"))
glow.append(lathe([(11.55, 2.24), (12.45, 2.24), (12.45, 2.4), (11.55, 2.4)], 96, "Ring"))
# jonc de lumière au pied du socle
glow.append(torus(15.05, 0.12, (0, 0, 0.18), maj=128, mnr=6))
# joints de panneaux sur la couronne du socle
for i in range(6):
    a = TAU * i / 6 + math.pi / 6
    g = rbox((1.8, 0.12, 0.2), (0, 0, 0), r=0.0)
    xf(g, rot=(math.radians(-24), 0, a + math.pi / 2))
    xf(g, loc=(14.1 * math.cos(a), 14.1 * math.sin(a), 2.18))
    dark.append(g)

# sol hexagonal (tuiles en léger relief)
S = 1.05
for q in range(-10, 11):
    for r in range(-10, 11):
        x = S * 1.5 * q
        y = S * math.sqrt(3) * (r + q / 2)
        if math.hypot(x, y) < 9.2:
            hx = [(x + (S - 0.08) * math.cos(TAU * k / 6), y + (S - 0.08) * math.sin(TAU * k / 6)) for k in range(6)]
            t = extrude(hx, 2.28, 2.52 if (q + r) % 5 else 2.56, "Hex", angle=30)
            hexm.append(t)
# tuiles lumineuses au centre (cible de spawn)
glow.append(lathe([(0, 2.3), (1.2, 2.3), (1.2, 2.6), (0, 2.6)], 6, "Core"))

# marche d'accès
step = rbox((9.5, 4.0, 1.25), (0, -15.6, 0.625), r=0.35, seg=3)
shell.append(step)
glow.append(rbox((8.4, 0.2, 0.14), (0, -17.55, 1.2), r=0.05, seg=1))

# ---------------------------------------------------------------- armature du dôme + verre (ouvert à l'avant)
def sph(a, e, rr=RD):
    return DC + Vector((rr * math.cos(e) * math.cos(a), rr * math.cos(e) * math.sin(a), rr * math.sin(e)))


E_TOP = math.acos(3.0 / RD)
open_half = math.radians(62)
rib_angles = [FRONT + open_half + (TAU - 2 * open_half) * k / 8 for k in range(9)]
for a in rib_angles:
    pts = [sph(a, E_TOP * k / 24) for k in range(25)]
    metal.append(sweep(pts, 0.2, 8, name="Rib"))
for e in (math.radians(28), math.radians(55)):
    pts = [sph(rib_angles[0] + (rib_angles[-1] - rib_angles[0]) * k / 60, e) for k in range(61)]
    metal.append(sweep(pts, 0.14, 6, name="Hoop"))
for a0, a1 in zip(rib_angles, rib_angles[1:]):
    g = grid_surface(lambda u, v, a0=a0, a1=a1: sph(a0 + (a1 - a0) * u, E_TOP * v, RD - 0.12), 6, 10, name="Pane")
    glass.append(g)
metal.append(torus(3.0, 0.35, DC + Vector((0, 0, RD * math.sin(E_TOP))), maj=48, mnr=10))
crown = lathe([(0, 0.6), (2.8, 0.6), (3.2, 0.2), (3.0, -0.4), (2.2, -0.7), (0, -0.7)], 48, "Crown")
xf(crown, loc=DC + Vector((0, 0, RD * math.sin(E_TOP))))
shell.append(crown)
glow.append(lathe([(0, -0.72), (1.8, -0.72), (1.8, -0.6), (0, -0.6)], 32, "Emitter"))
xf(glow[-1], loc=DC + Vector((0, 0, RD * math.sin(E_TOP))))

# ---------------------------------------------------------------- 3 pylônes incurvés
for a in (FRONT + open_half, FRONT - open_half, FRONT + math.pi):
    path = [sph(a, math.radians(0 + 52 * k / 16), RD + 1.0) for k in range(17)]
    tip_dir = (DC + Vector((0, 0, 9.5)) - path[-1]).normalized()
    path += [path[-1] + tip_dir * 1.2 * k for k in range(1, 4)]
    path[0] = path[0] + Vector((0, 0, -0.6))
    radial = Vector((math.cos(a), math.sin(a), 0))
    tang = Vector((-math.sin(a), math.cos(a), 0))
    secs = []
    for i, p in enumerate(path):
        f = i / (len(path) - 1)
        tg = (path[min(i + 1, len(path) - 1)] - path[max(i - 1, 0)]).normalized()
        n = tang.cross(tg).normalized()
        w, h = 2.4 - 1.1 * f, 1.7 - 0.7 * f
        secs.append([p + tang * x + n * y for x, y in rounded_rect(w, h, min(w, h) * 0.4, 3)])
    pyl = loft(secs, "Pylon", angle=40)
    shell.append(pyl)
    # canal lumineux sur la face intérieure
    ch = []
    for i, p in enumerate(path[1:-1]):
        f = (i + 1) / (len(path) - 1)
        tg = (path[min(i + 2, len(path) - 1)] - path[i]).normalized()
        n = tang.cross(tg).normalized()
        ch.append(p + n * (0.85 - 0.35 * f))
    glow.append(sweep(ch, 0.16, 6, name="Channel"))
    # griffe + émetteur à la pointe
    tip = path[-1]
    claw = lathe([(0, 0), (0.75, 0), (0.9, 0.5), (0.55, 1.1), (0, 1.2)], 16, "Claw")
    orient(claw, tip - tip_dir * 0.2, tip + tip_dir)
    metal.append(claw)
    glow.append(uvsphere(0.5, tip + tip_dir * 1.35, 16, 8))
    # sabot sur le socle
    metal.append(rbox((3.0, 3.0, 0.7), (0, 0, 0), r=0.25, seg=2))
    xf(metal[-1], rot=(0, 0, a))
    xf(metal[-1], loc=(14.3 * math.cos(a), 14.3 * math.sin(a), 2.0))

# ---------------------------------------------------------------- faisceau de miniaturisation
beam = lathe([(0, 2.6), (6.2, 2.6), (6.2, 3.0), (2.0, 16.0), (0, 16.2)], 48, "Beam", angle=60)

# ---------------------------------------------------------------- pupitre de commande + écran
CX, CY = 10.5, -18.0
ped = loft([[(CX + x, CY + y, z) for x, y in rounded_rect(w, d, 0.6, 3)] for w, d, z in
            ((3.2, 2.4, 0.0), (2.4, 1.8, 0.4), (1.9, 1.4, 3.4), (2.6, 2.0, 4.0))], "Pedestal", angle=40)
shell.append(ped)
head = rbox((4.2, 2.6, 0.5), (0, 0, 0), r=0.2, seg=2)
RX = Matrix.Rotation(math.radians(35), 3, "X")
scr = screen_part(3.6, 2.0, Vector((CX, CY - 0.1, 4.45)) + RX @ Vector((0, 0, 0.27)), RX @ Vector((0, 0, 1)),
                  RX @ Vector((0, 1, 0)), thick=0.06)
frame_n = rbox((3.9, 2.3, 0.05), (0, 0, 0.24), r=0.05, seg=1)
leds = [cyl(0.12, 0.1, (1.6 - k * 0.3, -1.12, 0.1), verts=8) for k in range(3)]
for o in [head, frame_n] + leds:
    xf(o, rot=(math.radians(35), 0, 0))
    xf(o, loc=(CX, CY - 0.1, 4.45))
dark.append(head)
glow.append(frame_n)
red += leds
# gaine de câbles du pupitre vers le socle
dark.append(sweep(catmull([(CX - 0.4, CY + 1.0, 0.35), (CX - 1.5, CY + 3.0, 0.3), (CX - 3.5, CY + 4.6, 0.3),
                           (9.2 * math.cos(-1.1), 9.2 * math.sin(-1.1) - 5.3, 0.3)], 8), 0.3, 8, name="Conduit",
                  braid=0.18, braid_freq=6.0))

tagj(shell, "Shell", "SmoothPlastic", "F2F2F5")
tagj(dark, "Dark", "SmoothPlastic", "16181E")
tagj(hexm, "Floor", "Metal", "2A2D38")
tagj(metal, "Frame", "Metal", "B8BEC8")
tagj(glass, "Dome", "Glass", "B9B0FF")
tagj(glow, "Glow", "Neon", "8B7CFF")
tagj(red, "Status", "Neon", "E53E3E")
tagj([beam], "Beam", "ForceField", "8B7CFF")

done("Miniaturiseur", direction=(0.75, -1.2, 0.8), lens=50)
