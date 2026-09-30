"""Mug — tasse en céramique AngaTV (Ø 40, h 45) : émail blanc, intérieur rouge, logo « A » en relief, café."""
from room_common import *

reset()
R, H = 20.0, 45.0

# --- coque extérieure (émail blanc) : pied creux, léger galbe, lèvre arrondie
outer = chain(
    [(0, 1.2), (13.5, 1.2)],
    qbez((13.5, 1.2), (14.6, 1.2), (15.2, 0.0), 3),       # gorge du pied
    [(17.2, 0.0)],
    qbez((17.2, 0.0), (19.7, 0.1), (19.85, 2.6), 5),      # talon arrondi
    cbez((19.85, 2.6), (20.3, 14), (20.3, 32), (20.0, 42.6), 10),  # galbe
    arc(18.9, 43.6, 1.1, -0.3, math.pi * 0.95, 8),        # lèvre ronde
    [(17.8, 42.8), (17.8, 41.0)],
)
shell = lathe(outer, 72, "Shell", angle=50)

# --- intérieur émaillé rouge
inner = chain(
    [(17.72, 43.4)],
    cbez((17.72, 43.4), (17.7, 30), (17.6, 10), (15.5, 5.6), 10),
    qbez((15.5, 5.6), (13.0, 4.1), (0.0, 4.0), 5),
)
glaze = lathe(inner, 72, "Glaze", angle=60)

# --- anse : ruban ovale balayé le long d'un « C »
path = catmull([(19.4, 0, 37.5), (25.5, 0, 38.2), (31.5, 0, 33.5), (32.5, 0, 24.0), (29.0, 0, 14.5), (22.5, 0, 10.5),
                (19.4, 0, 10.6)], 10)
handle = sweep(path, 2.6, 16, name="Handle", angle=70)
xf(handle, scale=(1, 1.45, 1))   # section ovale : plus large que épaisse
# congés de raccord avec le corps
for z in (37.4, 10.7):
    j = uvsphere(2.9, (20.6, 0, z), 20, 10, scale=(0.75, 1.3, 1.1))
    handle = join([handle, j])
body = tagj([shell, handle], "Body", "SmoothPlastic", "F2F2F5")

# --- café : surface avec ménisque + crème plus claire sur le bord
coffee = lathe(chain([(0, 37.6)], qbez((0, 37.6), (14, 37.6), (17.4, 38.0), 5), [(17.75, 38.7), (17.75, 36.0), (0, 36.0)]),
               72, "Coffee", angle=60)
tag(coffee, "Coffee", "SmoothPlastic", "3B2416")
crema = lathe([(15.6, 37.72), (16.9, 37.86), (17.55, 38.25), (17.5, 38.05), (16.8, 37.7), (15.6, 37.66)], 72, "Crema")
tag(crema, "Crema", "SmoothPlastic", "9C6B43")

# --- logo AngaTV : « A » en relief biseauté, enroulé sur la face avant (−Y)
logo = text_mesh("A", 24, 1.7, bevel_d=0.4, res=4)
xf(logo, rot=(math.pi / 2, 0, 0))            # texte debout : x = abscisse, -y = épaisseur
xf(logo, scale=(1, -1, 1))                    # épaisseur vers +y (vers l'extérieur avant enroulement)
bm = bmesh.new(); bm.from_mesh(logo.data); bmesh.ops.reverse_faces(bm, faces=bm.faces); bm.to_mesh(logo.data); bm.free()
xf(logo, loc=(0, -0.6, 25.5))
slice_x(logo, 0.8, -12, 12)
wrap_cylinder(logo, 20.2)
# wordmark « ANGATV » sous le A (plus fin)
word = text_mesh("ANGATV", 5.2, 0.9, bevel_d=0.12, res=2)
xf(word, rot=(math.pi / 2, 0, 0))
xf(word, scale=(1, -1, 1))
bm = bmesh.new(); bm.from_mesh(word.data); bmesh.ops.reverse_faces(bm, faces=bm.faces); bm.to_mesh(word.data); bm.free()
xf(word, loc=(0, -0.4, 11.0))
slice_x(word, 0.8, -12, 12)
wrap_cylinder(word, 20.2)
tagj([glaze, logo, word], "RedGlaze", "SmoothPlastic", "E53E3E")

done("Mug", direction=(-0.35, -1.0, 0.75))
