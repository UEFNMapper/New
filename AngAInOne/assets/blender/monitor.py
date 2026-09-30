"""Monitor — écran gaming incurvé 32" (dalle 260 × 150 studs, rayon 1800R) sur pied sculpté.

- `Screen__SmoothPlastic__0B0C10` : surface d'affichage SEULE (fine coque incurvée propre, face −Z Roblox),
  pour la SurfaceGui du jeu.
- bordures fines, menton avec logo AngaTV, coque arrière bombée avec ouïes, anneau RGB autour de la
  fixation VESA, pied alu en V, colonne avec passe-câble traversant, câble qui y passe.
Modélisé façade vers −Y puis tourné (façade exportée vers +Y Blender = −Z Roblox)."""
from room_common import *

reset()
PW, PH = 260.0, 150.0      # dalle (bordures comprises)
Z_BOT = 36.0               # bas de la dalle au-dessus du bureau
R = 660.0                  # rayon de courbure (≈1800R à cette échelle)
BEZ, CHIN = 2.4, 7.0


def bend(o):
    """Courbe un objet modélisé à plat (x = abscisse le long de l'écran, y = profondeur vers l'arrière)."""
    for v in o.data.vertices:
        x, y, z = v.co
        a = x / R
        r = R + y
        v.co = (r * math.sin(a), -R + r * math.cos(a), z)
    o.data.update()
    return o


def flat_part(o, step=6.0):
    slice_x(o, step, -PW / 2 - 5, PW / 2 + 5)
    return bend(o)


zc = Z_BOT + PH / 2
# --- coque avant/arrière de la dalle (6 d'épaisseur, arêtes arrondies)
panel = rbox((PW, 6.0, PH), (0, 3.0, zc), r=1.6, seg=4)
# ouïes d'aération hautes sur la face arrière (fentes gravées)
vents = [rbox((1.3, 3, 16), (x, 6.2, Z_BOT + PH - 16), r=0.5, seg=2) for x in
         [-110 + i * 4 for i in range(12)] + [66 + i * 4 for i in range(12)]]
boolean_diff(panel, vents)
flat_part(panel)

# --- bosse arrière (électronique) très arrondie, avec ouïes
bump = rbox((170, 16, 104), (0, 11.0, zc - 12), r=7.5, seg=5)
slots = [rbox((58, 3.0, 1.6), (sx * 45, 19.3, zc + 18 - i * 4.2), r=0.6, seg=2) for sx in (-1, 1) for i in range(6)]
boolean_diff(bump, slots)
flat_part(bump)

# --- lèvre de bordure (léger relief autour de la dalle)
sw, sh = PW - 2 * BEZ, PH - BEZ - CHIN
sz = Z_BOT + CHIN + sh / 2
lip_parts = []
for (w, h, x, z) in ((sw + 1.6, 0.8, 0, sz + sh / 2 + 0.4), (sw + 1.6, 0.8, 0, sz - sh / 2 - 0.4),
                     (0.8, sh, -sw / 2 - 0.4, sz), (0.8, sh, sw / 2 + 0.4, sz)):
    lip_parts.append(rbox((w, 0.7, h), (x, -0.25, z), r=0.3, seg=2))
lip = join(lip_parts)
flat_part(lip, 4.0)

# --- DALLE (Screen) : coque fine incurvée, une seule pièce propre
scr = box((sw, 0.3, sh), (0, -0.1, sz))
flat_part(scr, 260 / 40)
tag(scr, "Screen", "SmoothPlastic", "0B0C10")
scr.data.name = scr.name

# --- menton : logo AngaTV en relief métal + LED d'alimentation
logo = text_mesh("AngaTV", 4.0, 0.5, bevel_d=0.08, res=2)
xf(logo, rot=(math.pi / 2, 0, 0))
xf(logo, loc=(0, 0.05, Z_BOT + CHIN / 2 - 1.4))
led = cyl(0.55, 0.6, (PW / 2 - 12, 0.3, Z_BOT + CHIN / 2), rot=(math.pi / 2, 0, 0), verts=12)
bend(logo); bend(led)

# --- fixation VESA + anneau RGB à l'arrière
back_y = 19.0 - R * (1 - math.cos(0))   # centre : pas de flèche
mount = cyl(15, 7, (0, 18.5, zc - 18), rot=(-math.pi / 2, 0, 0), verts=48, bev=1.2)
ring = torus(24, 1.1, (0, 20.3, zc - 18), rot=(math.pi / 2, 0, 0), maj=96, mnr=10)
# gorge sombre qui porte l'anneau lumineux
ring_bezel = torus(24, 2.4, (0, 0, 0), rot=(math.pi / 2, 0, 0), maj=96, mnr=10)
xf(ring_bezel, scale=(1, 0.45, 1))
xf(ring_bezel, loc=(0, 19.2, zc - 18))

# --- pied : colonne sculptée (section arrondie qui s'affine) + tête de fixation
def rr3(w, d, r, z, y, n=5):
    return [(x, yy + y, z) for x, yy in rounded_rect(w, d, r, n)]


neck_secs = [rr3(40, 12, 5.0, 2.5, 50), rr3(34, 11, 4.8, 30, 46.5), rr3(28, 10, 4.4, 70, 40.5),
             rr3(25, 9.5, 4.2, zc - 6, 34.5)]
neck = loft(neck_secs, "Neck", angle=35)
subsurf(neck, 1)
hole = extrude(rounded_rect(15, 20, 6.0, 6), -10, 10, "Hole")
xf(hole, rot=(math.pi / 2, 0, 0))
xf(hole, loc=(0, 44, 42))
xf(hole, rot=None)
boolean_diff(neck, hole)
head = rbox((26, 16, 26), (0, 27.5, zc - 18), r=4, seg=4)
hinge = cyl(5.0, 25, (-12.5, 30, zc - 18), rot=(0, math.pi / 2, 0), verts=32, bev=1.0)

# pied en V (plaque alu biseautée)
V = catmull([(0, 58), (40, 38), (95, -10), (104, -24), (96, -30), (82, -24), (30, 10), (0, 22), (-30, 10), (-82, -24),
             (-96, -30), (-104, -24), (-95, -10), (-40, 38)], 6, closed=True)
V = [(x, y) for x, y, *_ in V]
foot = extrude(V, 0.0, 3.4, "Foot", angle=35)
bevel_all(foot, 1.1, 3, angle=40)
pads = [cyl(4.0, 0.6, (sx * 92, -21, -0.001), verts=24) for sx in (-1, 1)] + [cyl(4.0, 0.6, (0, 50, -0.001), verts=24)]

# --- câble (DisplayPort) : sort de la bosse, passe dans le passe-câble, file sur le bureau
cable = sweep(catmull([(-8, 21.5, zc - 42), (-6, 36, zc - 55), (0, 44, 62), (0, 44, 42), (0, 45, 24), (4, 62, 6),
                       (10, 80, 1.3), (22, 100, 1.3)], 10), 1.4, 12, name="Cable")
plug = rbox((7, 5, 9), (-8, 20.5, zc - 40), r=1.2, seg=2)

tagj([panel, bump, lip, plug, cable], "Housing", "SmoothPlastic", "16181E")
tagj([mount, ring_bezel, head, pads[0], pads[1], pads[2]], "Mount", "SmoothPlastic", "22252E")
tagj([neck, foot, hinge, logo], "Stand", "Metal", "B8BEC8")
tagj([ring, led], "Glow", "Neon", "8B7CFF")

done("Monitor", direction=(1.25, 0.55, 0.42), lens=50)
