"""GamingChair — fauteuil gaming premium (≈600 studs : énorme, vu depuis le bureau des joueurs miniaturisés).

Assise baquet et dossier racing en mousse rembourrée (volumes fusionnés par remaillage voxel puis
lissés), capitonnage à canaux (creux + points de couture), panneaux latéraux violets AngAInOne,
passepoil rouge AngaTV le long des coutures, fentes de harnais, logo brodé, coussin lombaire,
accoudoirs 4D, mécanisme basculant avec leviers, vérin à soufflet télescopique, piétement étoile
alu 5 branches, roulettes doubles.
Modélisé façade (avant de l'assise) vers −Y puis tourné à l'export."""
from room_common import *

reset()
fab_black, fab_purple, piping, stitch, plastic, rubber, metal = [], [], [], [], [], [], []

# ================================================================ ASSISE (baquet)
SEAT_Y = -10.0
pan = rbox((200, 225, 34), (0, SEAT_Y, 246), r=15, seg=4)
bol = [sweep([(sx * 101, SEAT_Y - 108, 254), (sx * 103, SEAT_Y - 40, 262), (sx * 104, SEAT_Y + 100, 268)], 25, 24)
       for sx in (-1, 1)]
roll = cyl(19, 196, (-98, SEAT_Y - 106, 247), rot=(0, math.pi / 2, 0), verts=32)
seat = join([pan, roll] + bol)
remesh(seat, 6.0, smooth_iter=6, smooth_factor=0.8)

# canaux de capitonnage : on « pince » la mousse le long de lignes transversales
CH_Y = [SEAT_Y - 62, SEAT_Y - 22, SEAT_Y + 18, SEAT_Y + 58]
for v in seat.data.vertices:
    x, y, z = v.co
    if abs(x) < 74 and z > 255:
        for cy in CH_Y:
            d = abs(y - cy)
            if d < 6:
                v.co.z -= 3.2 * (1 - (d / 6) ** 2) * min(1, (74 - abs(x)) / 8)
seat.data.update()
decimate(seat, 0.55)
shade(seat, 60)
for sx in (-1, 1):
    bisect(seat, (sx * 74, 0, 0), (1, 0, 0))
seat_side = split_faces(seat, lambda c, n: abs(c.x) > 74 and c.z > 236, "SeatSide")
fab_black.append(seat)
fab_purple.append(seat_side)

srf = Surface([seat, seat_side])
for sx in (-1, 1):
    pts = srf.path([(sx * 74, y, 400) for y in [SEAT_Y - 118 + k * 4 for k in range(59)]], (0, 0, -1), 0.4)
    if len(pts) > 3:
        piping.append(sweep(pts, 1.7, 10, name="Piping"))
for cy in CH_Y:
    for k in range(22):
        x0 = -66 + k * 6.3
        p = srf.path([(x0, cy - 5.2, 400), (x0 + 3.0, cy - 5.2, 400)], (0, 0, -1), 0.5)
        q = srf.path([(x0, cy + 5.2, 400), (x0 + 3.0, cy + 5.2, 400)], (0, 0, -1), 0.5)
        for pr in (p, q):
            if len(pr) == 2:
                stitch.append(cyl_between(pr[0], pr[1], 0.6, 4))

# ================================================================ DOSSIER (construit debout, puis incliné)
LEAN = math.radians(-13)
B0 = Vector((0, SEAT_Y + 104, 258))
back = rbox((196, 50, 290), (0, 0, 145), r=18, seg=4)
wings = [sweep([(sx * 94, -14, 6), (sx * 99, -24, 120), (sx * 101, -18, 230)], 25, 24) for sx in (-1, 1)]
shoulders = [sweep([(sx * 104, -6, 222), (sx * 104, -4, 282)], 22, 20) for sx in (-1, 1)]
head = rbox((158, 46, 90), (0, 2, 318), r=22, seg=4)
neck = rbox((150, 44, 40), (0, 0, 280), r=14, seg=3)
backrest = join([back, head, neck] + wings + shoulders)
remesh(backrest, 6.0, smooth_iter=6, smooth_factor=0.8)
# canaux horizontaux sur le devant
CH_Z = [62, 112, 162, 212]
for v in backrest.data.vertices:
    x, y, z = v.co
    if abs(x) < 70 and y < -20:
        for cz in CH_Z:
            d = abs(z - cz)
            if d < 6:
                v.co.y += 3.2 * (1 - (d / 6) ** 2) * min(1, (70 - abs(x)) / 8)
backrest.data.update()
# fentes de harnais (racing)
slots = []
for sx in (-1, 1):
    s_ = extrude(rounded_rect(24, 44, 11, 6), -60, 60, "Slot")
    xf(s_, rot=(math.pi / 2, 0, 0))
    xf(s_, loc=(sx * 52, 0, 300))
    slots.append(s_)
decimate(backrest, 0.55)
boolean_diff(backrest, slots)
shade(backrest, 60)
for sx in (-1, 1):
    bisect(backrest, (sx * 70, 0, 0), (1, 0, 0))
back_side = split_faces(backrest, lambda c, n: abs(c.x) > 70 and c.z < 300, "BackSide")

# passepoils + coutures + logo, dans le repère debout
bsrf = Surface([backrest, back_side])
back_bits_pipe, back_bits_stitch, back_logo = [], [], []
for sx in (-1, 1):
    pts = bsrf.path([(sx * 70, -200, z) for z in [4 + k * 4 for k in range(74)]], (0, 1, 0), 0.4)
    if len(pts) > 3:
        back_bits_pipe.append(sweep(pts, 1.7, 10, name="Piping"))
for cz in CH_Z:
    for k in range(21):
        x0 = -63 + k * 6.3
        for dz in (-5.2, 5.2):
            pr = bsrf.path([(x0, -200, cz + dz), (x0 + 3.0, -200, cz + dz)], (0, 1, 0), 0.5)
            if len(pr) == 2:
                back_bits_stitch.append(cyl_between(pr[0], pr[1], 0.6, 4))
hit, nor = bsrf.hit((0, -200, 342), (0, 1, 0))
logo = text_mesh("A", 30, 2.2, bevel_d=0.4, res=3)
xf(logo, rot=(math.pi / 2, 0, 0))
xf(logo, loc=(0, hit.y + 1.2, 342))
wordmark = text_mesh("AngAInOne", 9, 1.4, bevel_d=0.2, res=2)
xf(wordmark, rot=(math.pi / 2, 0, 0))
h2, _ = bsrf.hit((0, -200, 244), (0, 1, 0))
xf(wordmark, loc=(0, h2.y + 0.6, 244 - 3))
back_logo += [logo]
back_word = [wordmark]
# coussin lombaire (tissu noir, liseré violet)
lum = rbox((150, 26, 46), (0, 0, 0), r=12, seg=4)
remesh(lum, 3.0, smooth_iter=4, smooth_factor=0.8)
hl, _ = bsrf.hit((0, -200, 92), (0, 1, 0))
xf(lum, loc=(0, hl.y - 10, 92))
lum_band = torus(0.5, 1.2, (0, 0, 0), maj=8, mnr=6)  # (remplacé ci-dessous par une sangle)
bpy.data.objects.remove(lum_band)
strap = rbox((196, 3, 7), (0, hl.y + 1.5, 100), r=1.2, seg=2)

group_back = [backrest, back_side, lum, strap] + back_bits_pipe + back_bits_stitch + back_logo + back_word
M = Matrix.Translation(B0) @ Matrix.Rotation(LEAN, 4, "X")
for o in group_back:
    o.data.transform(M); o.data.update()
fab_black += [backrest, lum]
fab_purple += [back_side]
piping += back_bits_pipe + back_logo
stitch += back_bits_stitch + back_word
plastic.append(strap)

# ================================================================ MÉCANISME + VÉRIN
plastic.append(rbox((130, 150, 18), (0, SEAT_Y + 10, 215), r=5, seg=3))
plastic.append(rbox((80, 60, 16), (0, SEAT_Y + 10, 199), r=4, seg=3))
# levier de hauteur (palette à droite) + molette de tension à l'avant
plastic.append(box_between((62, SEAT_Y + 20, 212), (112, SEAT_Y - 15, 216), 6, 3, r=1.2))
plastic.append(rbox((20, 30, 5), (118, SEAT_Y - 26, 216), r=2.4, seg=3, rot=(0, 0, 0.6)))
plastic.append(cyl(12, 22, (0, SEAT_Y - 60, 198), rot=(-math.pi / 2, 0, 0), verts=32, bev=2))
plastic.append(cyl(7, 70, (0, SEAT_Y - 80, 198), rot=(-math.pi / 2, 0, 0), verts=24, bev=1))
metal.append(cyl(12.5, 30, (0, 0, 175), verts=40))                         # tige chromée
bell = lathe([(21, 92), (21.5, 110), (19.5, 112), (19.5, 126), (20.5, 128), (18.0, 130), (18.0, 146), (19.0, 148),
              (16.5, 150), (16.5, 166), (17.5, 168), (13.4, 172), (13.4, 176), (0, 176)], 48, "Sleeve", angle=35)
plastic.append(bell)

# ================================================================ PIÉTEMENT ÉTOILE + ROULETTES
metal.append(lathe([(0, 58), (34, 58), (37, 62), (37, 90), (33, 95), (22, 97), (0, 97)], 48, "Hub", angle=35))
arm0 = []
for k in range(13):
    f = k / 12
    s = 28 + f * 138
    w = 40 - 14 * f
    hgt = 36 - 12 * f
    zc = 80 - 16 * f
    sec = [(s, x, zc + z) for x, z in rounded_rect(w, hgt, min(w, hgt) * 0.42, 5)]
    arm0.append([(p[0], p[1], p[2]) for p in sec])
arm_proto = loft(arm0, "Arm", angle=35)
boss = cyl(17, 22, (166, 0, 54), verts=40, bev=4)
cap = lathe([(0, 76), (15.0, 76), (16.0, 77.2), (15.4, 78.4), (0, 79)], 32, "Cap")
xf(cap, loc=(166, 0, 0))
arm_proto = join([arm_proto, boss, cap])
for i in range(5):
    a = TAU * i / 5 + math.pi / 2
    o = dup(arm_proto)
    xf(o, rot=(0, 0, a))
    metal.append(o)
    # roulette double : chape + 2 roues + tige
    cx, cy = 166 * math.cos(a), 166 * math.sin(a)
    yaw = a + 0.7 * math.sin(i * 2.3)
    fork = rbox((34, 44, 24), (0, 0, 0), r=9, seg=4)
    boolean_diff(fork, rbox((22, 60, 30), (0, 0, -14), r=2, seg=1))
    xf(fork, loc=(0, 8, 40))
    stem = cyl(4.5, 16, (0, 0, 44), verts=16)
    parts_r, parts_p = [], [fork, stem]
    for sxw in (-1, 1):
        wheel = lathe([(0, -5), (14, -5), (19.5, -4.6), (21.6, -3.2), (22.2, 0), (21.6, 3.2), (19.5, 4.6), (14, 5), (0, 5)],
                      40, "Wheel", angle=40)
        hubc = lathe([(0, 5.0), (12, 5.0), (12.6, 5.6), (11, 6.2), (0, 6.3)], 32, "HubCap")
        for o2 in (wheel, hubc):
            xf(o2, scale=(1, 1, sxw))
            xf(o2, rot=(0, math.pi / 2, 0))
            xf(o2, loc=(sxw * 12.5, 12, 22.2))
        parts_r.append(wheel); parts_p.append(hubc)
    for o2 in parts_r + parts_p:
        xf(o2, rot=(0, 0, yaw))
        xf(o2, loc=(cx, cy, 0))
    rubber += parts_r
    plastic += parts_p
bpy.data.objects.remove(arm_proto)

# ================================================================ ACCOUDOIRS 4D
for sx in (-1, 1):
    plastic.append(box_between((sx * 55, SEAT_Y + 30, 212), (sx * 140, SEAT_Y + 30, 212), 22, 12, r=3))
    plastic.append(rbox((20, 30, 130), (sx * 142, SEAT_Y + 30, 272), r=5, seg=3))
    plastic.append(rbox((13, 24, 70), (sx * 142, SEAT_Y + 30, 360 - 44), r=3, seg=3))
    plastic.append(rbox((8, 10, 16), (sx * 142, SEAT_Y + 13, 318), r=2.5, seg=3))    # bouton de réglage
    pad = rbox((42, 118, 16), (sx * 142, SEAT_Y + 20, 352), r=7, seg=4)
    rubber.append(pad)
    # rainures antidérapantes sur la manchette
    for k in range(5):
        stitch.append(rbox((30, 1.2, 1.0), (sx * 142, SEAT_Y - 12 + k * 14, 360.2), r=0.4, seg=1))

tagj(fab_black, "Upholstery", "Fabric", "16181E")
tagj(fab_purple, "SidePanels", "Fabric", "8B7CFF")
tagj(piping, "Piping", "SmoothPlastic", "E53E3E")
tagj(stitch, "Stitching", "SmoothPlastic", "8B7CFF")
tagj(plastic, "Plastic", "SmoothPlastic", "16181E")
tagj(rubber, "Rubber", "Plastic", "22252E")
tagj(metal, "Base", "Metal", "B8BEC8")

done("GamingChair", direction=(1.0, -1.2, 0.45), lens=50)
