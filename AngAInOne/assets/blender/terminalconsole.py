"""TerminalConsole — borne « antivirus » des salles sûres (≈9 studs, échelle joueur).

Socle chanfreiné, colonne sculptée évasée, pupitre-clavier incliné (touches en relief), écran incliné
dans un boîtier (`Screen` = dalle seule, face −Z Roblox), écusson antivirus lumineux, liserés néon
couleur du monde (Neon 8B7CFF : le jeu les recolore), gaines annelées vers le sol et le boîtier,
ouïes arrière, LED d'état.
Modélisée façade vers −Y puis tournée à l'export."""
from room_common import *

reset()
body, dark, metal, trim, red = [], [], [], [], []


def rr3(w, d, r, z, dy=0.0, n=4):
    return [(x, y + dy, z) for x, y in rounded_rect(w, d, r, n)]


# ---------------------------------------------------------------- socle + colonne
plinth = loft([rr3(5.0, 4.0, 0.7, 0.0), rr3(5.4, 4.4, 0.8, 0.12), rr3(5.4, 4.4, 0.8, 0.42), rr3(4.9, 3.9, 0.6, 0.62)],
              "Plinth", angle=35)
body.append(plinth)
metal.append(loft([rr3(4.6, 3.6, 0.5, 0.6), rr3(4.6, 3.6, 0.5, 0.7), rr3(4.3, 3.3, 0.45, 0.72)], "Plate", angle=35))
COL = [(2.9, 2.1, 0.55, 0.7, 0.1), (2.3, 1.6, 0.45, 2.4, 0.15), (2.3, 1.6, 0.45, 3.4, 0.15), (3.6, 2.0, 0.5, 4.3, 0.0),
       (4.9, 2.4, 0.5, 4.75, -0.1)]
col = loft([rr3(w, d, r, z, dy, 6) for w, d, r, z, dy in COL], "Column", angle=40)
body.append(col)
# liserés néon posés exactement sur les arêtes avant arrondies de la colonne
c45 = math.cos(math.pi / 4)
for sx in (-1, 1):
    pts = [(sx * (w / 2 - r + r * c45), dy - (d / 2 - r + r * c45), z) for w, d, r, z, dy in COL[:-1]]
    pts = [pts[0]] + catmull(pts, 6)[1:]
    trim.append(sweep(pts, 0.05, 6, name="Edge"))
trim.append(sweep([(x, y, 0.64) for x, y in rounded_rect(4.95, 3.95, 0.62, 4)], 0.045, 6, closed=True, name="PlinthLine"))

# écusson antivirus (bouclier + coche) sur l'avant de la colonne
shield = [(0, 0.62), (0.5, 0.5), (0.52, 0.05), (0.38, -0.3), (0, -0.6), (-0.38, -0.3), (-0.52, 0.05), (-0.5, 0.5)]
sh = extrude(shield, 0, 0.08, "Shield", angle=30)
xf(sh, rot=(math.pi / 2, 0, 0))
xf(sh, loc=(0, -0.62, 2.9))
trim.append(sh)
check = sweep([(-0.22, -0.72, 2.92), (-0.05, -0.72, 2.74), (0.25, -0.72, 3.12)], 0.06, 6, name="Check")
dark.append(check)

# ---------------------------------------------------------------- pupitre clavier incliné
TILT = math.radians(18)
DECK = Matrix.Translation((0, -0.35, 4.95)) @ Matrix.Rotation(TILT, 4, "X")
deck = rbox((5.0, 2.5, 0.32), (0, 0, 0), r=0.12, seg=2)
deck.data.transform(DECK)
body.append(deck)
# touches (grille + espace) en relief
keys = []
for row in range(4):
    n = 12 if row < 3 else 1
    for k in range(n):
        w = 0.28 if row < 3 else 2.2
        x = -1.9 + k * 0.345 + (0.1 if row == 1 else 0.0) + (0.16 if row == 2 else 0.0) if row < 3 else 0.0
        kk = rbox((w, 0.28, 0.12), (x, 0.55 - row * 0.36, 0.2), r=0.04, seg=1)
        kk.data.transform(DECK)
        keys.append(kk)
pad = rbox((0.9, 0.9, 0.06), (1.95, 0.0, 0.19), r=0.2, seg=2)   # pavé tactile
pad.data.transform(DECK)
dark += keys + [pad]
fr = rbox((4.9, 0.06, 0.06), (0, -1.23, 0.1), r=0.02, seg=1)
fr.data.transform(DECK)
trim.append(fr)

# ---------------------------------------------------------------- boîtier d'écran incliné + Screen
LEAN = math.radians(-14)
SCR = Matrix.Translation((0, 0.95, 7.05)) @ Matrix.Rotation(LEAN, 4, "X")
housing = rbox((5.3, 0.5, 3.5), (0, 0, 0), r=0.18, seg=3)
back_bulge = rbox((3.6, 0.6, 2.3), (0, 0.45, -0.1), r=0.28, seg=3)
vents = [rbox((0.12, 0.3, 1.2), (-1.2 + k * 0.3, 0.78, 0.1), r=0.04, seg=1) for k in range(9)]
boolean_diff(back_bulge, vents)
for o in (housing, back_bulge):
    o.data.transform(SCR)
body += [housing, back_bulge]
R3 = SCR.to_3x3()
scr = screen_part(4.8, 3.0, SCR @ Vector((0, -0.26, 0.05)), R3 @ Vector((0, -1, 0)), R3 @ Vector((0, 0, 1)))
bez = [rbox((4.95, 0.04, 0.05), (0, -0.265, 1.62), r=0.015, seg=1), rbox((4.95, 0.04, 0.05), (0, -0.265, -1.52), r=0.015, seg=1)]
for o in bez:
    o.data.transform(SCR)
trim += bez
ledp = cyl(0.07, 0.05, (2.3, -0.29, -1.62), rot=(math.pi / 2, 0, 0), verts=10)
ledp.data.transform(SCR)
red.append(ledp)
# ailerons latéraux du boîtier, avec liseré néon
for sx in (-1, 1):
    fin = extrude([(0, -1.9), (0.5, -1.6), (0.55, 1.5), (0.1, 1.95), (-0.25, 1.7), (-0.2, -1.6)], -0.12, 0.12, "Fin", angle=30)
    bevel_all(fin, 0.05, 2, angle=40)
    fin.data.transform(Matrix(((0, 0, 1, 0), (1, 0, 0, 0), (0, 1, 0, 0), (0, 0, 0, 1))))  # profil → plan YZ, épaisseur → X
    fin.data.transform(SCR @ Matrix.Translation((sx * 2.72, 0.1, 0)))
    body.append(fin)
    ln = sweep([(0, -0.5, -1.55), (0, -0.52, 1.5)], 0.035, 6, name="FinLine")
    ln.data.transform(SCR @ Matrix.Translation((sx * 2.72, 0.0, 0)))
    trim.append(ln)
# col de liaison pupitre → boîtier
body.append(box_between(Vector((0, 0.7, 4.8)), SCR @ Vector((0, 0.5, -1.2)), 1.4, 0.8, r=0.25, seg=2))

# ---------------------------------------------------------------- gaines annelées
for sx, top in ((-1, False), (1, False), (0.45, True)):
    if top:
        pts = catmull([(0.6, 1.9, 0.72), (0.9, 2.4, 2.5), (0.9, 2.0, 5.5), SCR @ Vector((0.9, 0.7, -0.4))], 8)
    else:
        pts = catmull([(sx * 1.4, 2.0, 0.5), (sx * 1.6, 2.6, 0.45), (sx * 1.8, 3.4, 0.25), (sx * 2.0, 3.9, -0.3)], 8)
    metal.append(sweep(pts, 0.2, 10, name="Conduit", braid=0.16, braid_freq=14.0))
    metal.append(cyl_between(pts[0], Vector(pts[0]) + (Vector(pts[1]) - Vector(pts[0])).normalized() * 0.3, 0.27, 12))

tagj(body, "Body", "SmoothPlastic", "22252E")
tagj(dark, "Keys", "SmoothPlastic", "16181E")
tagj(metal, "Metal", "Metal", "2A2D38")
tagj(trim, "Trim", "Neon", "8B7CFF")
tagj(red, "Status", "Neon", "E53E3E")

done("TerminalConsole", direction=(0.9, -1.2, 0.6), lens=50)
