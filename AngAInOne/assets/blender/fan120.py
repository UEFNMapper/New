"""Exemple de référence : ventilateur 120 mm « AngaTV » (cadre, pales vrillées, moyeu, anneau RGB)."""
import math, sys, os
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from common import *

reset()
S = 10  # 1 unité = 1 stud ; ventilateur de 12 studs de côté, 2.5 d'épaisseur

frame = box((1.2 * S, 1.2 * S, 0.25 * S), (0, 0, 0.125 * S), bevel_width=0.12 * S, segments=6)
boolean(frame, cylinder(0.56 * S, 1 * S, (0, 0, 0.125 * S), vertices=96))
for x, y in ((0.5, 0.5), (-0.5, 0.5), (0.5, -0.5), (-0.5, -0.5)):
    boolean(frame, cylinder(0.045 * S, 1 * S, (x * S, y * S, 0.125 * S), vertices=24))
tag(frame, "Frame", "SmoothPlastic", "16181E")

hub = cylinder(0.2 * S, 0.2 * S, (0, 0, 0.125 * S), vertices=64, bevel_width=0.03 * S)
tag(hub, "Hub", "Metal", "9AA0AC")

blades = []
for i in range(9):
    bpy.ops.mesh.primitive_plane_add(size=1)
    p = active()
    p.scale = (0.36 * S, 0.2 * S, 1); bpy.ops.object.transform_apply(scale=True)
    bpy.ops.object.mode_set(mode="EDIT"); bpy.ops.mesh.subdivide(number_cuts=6); bpy.ops.object.mode_set(mode="OBJECT")
    for v in p.data.vertices:
        x, y = v.co.x / S, v.co.y / S
        v.co.z = S * 0.08 * (y / 0.1) * (0.3 + x)
        v.co.y = S * (y + 0.12 * (x + 0.18) ** 2)
    p.location = (0.37 * S, 0, 0)
    bpy.ops.object.transform_apply(location=True)
    sol = p.modifiers.new("Solid", "SOLIDIFY"); sol.thickness = 0.02 * S
    apply_modifiers(p)
    p.rotation_euler = (0, 0, i * 2 * math.pi / 9)
    bpy.ops.object.transform_apply(rotation=True)
    p.location = (0, 0, 0.125 * S)
    smooth(p)
    blades.append(p)
rotor = join(blades)
bpy.context.scene.cursor.location = (0, 0, 0.125 * S)
bpy.ops.object.origin_set(type="ORIGIN_CURSOR")
tag(rotor, "Blades", "SmoothPlastic", "2A2D38", spin=True)

bpy.ops.mesh.primitive_torus_add(major_radius=0.575 * S, minor_radius=0.018 * S, major_segments=96, minor_segments=10,
                                 location=(0, 0, 0.23 * S))
tag(active(), "Ring", "Neon", "8B7CFF")

finish("Fan120")
