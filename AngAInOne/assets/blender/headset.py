"""Headset — casque gaming posé sur son support (≈90 studs).

Support : socle lesté tourné avec anneau RGB, mât alu, berceau caoutchouc.
Casque : arceau alu + bandeau de suspension en tissu (coutures violettes), glissières crantées,
fourches, coques ovales avec anneau RGB et logo « A » rouge, coussinets similicuir épais,
micro-perche flexible avec LED rouge de sourdine, câble.
Modélisé façade vers −Y (micro vers l'avant) puis tourné à l'export."""
from room_common import *

reset()
black, metal, fabric, stitch, glow, redled, logo, rubber = [], [], [], [], [], [], [], []
ZC = 57.5            # centre des arcs (arceau / berceau)
CUP_X, CUP_Z = 26.0, 35.0

# ---------------------------------------------------------------- support
base = lathe([(0, 0), (16.5, 0), (17.3, 0.6), (17.4, 2.2), (16.6, 3.6), (14.0, 4.4), (6, 5.0), (0, 5.0)], 72, "Base")
black.append(base)
glow.append(torus(16.9, 0.45, (0, 0, 2.3), maj=96, mnr=8))
metal.append(lathe([(0, 4.9), (4.2, 4.9), (4.6, 5.4), (3.4, 7.2), (2.4, 8.2), (0, 8.2)], 40, "Foot"))
post = cyl(2.3, ZC + 17.2 - 1.5 - 7.5, (0, 0, 7.5), verts=32)
metal.append(post)
cradle_pts = [(17.2 * math.cos(a), 0, ZC + 17.2 * math.sin(a)) for a in
              [math.radians(40 + 100 * k / 30) for k in range(31)]]
cr = sweep(cradle_pts, 1.8, 16, name="Cradle")
xf(cr, scale=(1, 2.4, 1))
metal.append(cr)
pad_pts = [(19.05 * math.cos(a), 0, ZC + 19.05 * math.sin(a)) for a in [math.radians(55 + 70 * k / 24) for k in range(25)]]
rp = sweep(pad_pts, 0.45, 12, name="Rubber")
xf(rp, scale=(1, 7.0, 1))
rubber.append(rp)

# ---------------------------------------------------------------- arceau + bandeau
BAND_R = 22.2
band_pts = [(BAND_R * math.cos(a), 0, ZC + BAND_R * math.sin(a)) for a in [math.pi * k / 48 for k in range(49)]]
band = sweep(band_pts, 0.9, 12, name="Band")
xf(band, scale=(1, 2.6, 1))
metal.append(band)
# bandeau de suspension (tissu) et ses attaches
PAD_R = 20.1
sus_pts = [(PAD_R * math.cos(a), 0, ZC + PAD_R * math.sin(a)) for a in [math.radians(28 + 124 * k / 40) for k in range(41)]]
sus = sweep(sus_pts, 1.0, 16, name="Pad")
xf(sus, scale=(1, 3.1, 1))
fabric.append(sus)
for sx in (-1, 1):
    a = math.radians(90 - sx * 62)
    p_in = Vector((PAD_R * math.cos(a), 0, ZC + PAD_R * math.sin(a)))
    p_out = Vector((BAND_R * math.cos(a + sx * 0.05), 0, ZC + BAND_R * math.sin(a + sx * 0.05)))
    black.append(box_between(p_in, p_out, 1.4, 6.8, r=0.5, seg=2))
# coutures : tirets le long des deux bords du bandeau
for yy in (-2.35, 2.35):
    for k in range(34):
        a = math.radians(33 + 114 * k / 33)
        p = Vector(((PAD_R + 0.95) * math.cos(a), yy, ZC + (PAD_R + 0.95) * math.sin(a)))
        t = Vector((-math.sin(a), 0, math.cos(a)))
        stitch.append(cyl_between(p - t * 0.55, p + t * 0.55, 0.16, 6))
# logo AngaTV embossé sur le dessus de l'arceau
lg = text_mesh("AngaTV", 2.4, 0.35, res=2)
xf(lg, loc=(0, 0, ZC + BAND_R + 0.75))
logo.append(lg)

# ---------------------------------------------------------------- glissières, fourches, coques
for sx in (-1, 1):
    x = sx * BAND_R
    # glissière crantée
    metal.append(rbox((1.4, 3.6, 12.0), (x, 0, ZC - 5.5), r=0.5, seg=2))
    for k in range(6):
        black.append(rbox((1.8, 3.9, 0.35), (x, 0, ZC - 1.5 - k * 1.5), r=0.1, seg=1))
    black.append(rbox((3.2, 5.0, 3.2), (x, 0, ZC - 12.2), r=1.0, seg=3))
    # fourche en U autour de la coque
    cx = sx * CUP_X
    fork = [(x + (cx - x) * min(1, k / 6) * 0 + sx * 2.6, 12.0 * math.cos(math.pi * k / 24),
             CUP_Z + 2.0 + 13.5 * math.sin(math.pi * k / 24)) for k in range(25)]
    fk = sweep(fork, 0.95, 12, name="Fork")
    xf(fk, scale=(1, 1, 1))
    black.append(fk)
    black.append(cyl_between((x, 0, ZC - 13.5), (x + sx * 2.6, 0, CUP_Z + 15.3), 1.1, 12))
    for yy in (-12, 12):
        metal.append(cyl_between((cx - sx * 3.6, yy * 0.97, CUP_Z + 2.0), (x + sx * 1.5, yy * 0.97, CUP_Z + 2.0), 1.0, 16))

    # coque (profil tourné le long de X, ovale)
    shell = lathe([(0, 0), (9.2, 0), (10.3, 0.8), (10.6, 2.5), (10.2, 5.2), (8.8, 7.2), (6.5, 8.2), (0, 8.4)], 64,
                  "Cup", angle=40)
    ring = torus(7.6, 0.5, (0, 0, 7.75), maj=64, mnr=8)
    plate = lathe([(0, 8.3), (6.6, 8.3), (6.9, 8.7), (6.4, 9.1), (0, 9.2)], 64, "Plate")
    a_logo = text_mesh("A", 7.5, 0.7, bevel_d=0.1, res=3)
    xf(a_logo, rot=(0, 0, sx * math.pi / 2))   # debout une fois la coque tournée
    xf(a_logo, loc=(0, 0, 8.95))
    cushion = lathe([(5.2, 0.2), (10.0, 0.2), (11.0, -0.8), (11.3, -2.6), (10.6, -4.4), (9.0, -5.2), (6.6, -5.2),
                     (5.2, -4.4), (4.6, -2.8), (4.8, -0.4)], 64, "Cushion", angle=60)
    grille = lathe([(0, -1.6), (5.0, -1.6), (5.0, 0.3), (0, 0.3)], 32, "Grille")
    for o in (shell, ring, plate, a_logo, cushion, grille):
        xf(o, scale=(1.22, 1, 1))  # ovale (X local → Z monde après rotation)
        o.data.transform(Matrix.Translation((cx - sx * 3.2, 0, CUP_Z)) @ Matrix.Rotation(sx * math.pi / 2, 4, "Y"))
        o.data.update()
    # (la rotation autour de Y met l'axe de révolution sur ±X ; l'ovale reste vertical)
    black.append(shell)
    glow.append(ring)
    metal.append(plate)
    logo.append(a_logo)
    fabric.append(cushion)
    black.append(grille)

# ---------------------------------------------------------------- micro-perche (côté gauche) + câble
lx = -CUP_X - 2.5
boom_pts = catmull([(lx, -6, CUP_Z - 6), (lx - 1.5, -12, CUP_Z - 10), (lx + 1.5, -20, CUP_Z - 12.5), (lx + 8, -27, CUP_Z - 12),
                    (lx + 13, -30, CUP_Z - 10)], 10)
boom = sweep(boom_pts, 0.75, 10, name="Boom", braid=0.1, braid_freq=6.0)
black.append(boom)
black.append(cyl_between((lx - 1.6, -6, CUP_Z - 6), (lx + 1.2, -6, CUP_Z - 6), 2.2, 24))
tip = Vector(boom_pts[-1])
tip_d = (Vector(boom_pts[-1]) - Vector(boom_pts[-3])).normalized()
foam = cyl_between(tip - tip_d * 0.5, tip + tip_d * 3.6, 1.35, 20, bevel_w=0.5)
fabric.append(foam)
redled.append(cyl_between(tip - tip_d * 1.2, tip - tip_d * 0.4, 1.0, 16))
cable = catmull([(-CUP_X + 1, 5, CUP_Z - 11), (-CUP_X + 3, 8, CUP_Z - 18), (-20, 10, 16), (-14, 12, 6), (-10, 18, 1.0),
                 (-6, 30, 0.8), (6, 36, 0.8)], 10)
black.append(sweep(cable, 0.8, 10, name="Cable", braid=0.06, braid_freq=3.0))

tagj(black, "Body", "SmoothPlastic", "16181E")
tagj(metal, "Metal", "Metal", "B8BEC8")
tagj(fabric, "Cushions", "Fabric", "22252E")
tagj(stitch, "Stitching", "SmoothPlastic", "8B7CFF")
tagj(glow, "Glow", "Neon", "8B7CFF")
tagj(redled, "MuteLed", "Neon", "E53E3E")
tagj(logo, "Logo", "SmoothPlastic", "E53E3E")
tagj(rubber, "Rubber", "Plastic", "22252E")

done("Headset", direction=(0.95, -1.1, 0.45), lens=50)
