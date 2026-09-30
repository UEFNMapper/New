"""
common.py — outils partagés pour modéliser les assets 3D d'AngAInOne avec Blender (bpy 4.2).

Chaque script de modèle (assets/blender/<famille>.py) fait :
    from common import *
    reset()
    ... construit des objets avec les helpers ...
    finish("NomDuModele", preview=True)   # exporte assets/models/NomDuModele.glb + un rendu de contrôle

CONVENTIONS (lues en jeu par src/server/World/ModelLibrary.luau) :
- 1 unité Blender = 1 stud Roblox. Z Blender = haut ; l'export glTF convertit en Y-up.
- Chaque objet du modèle devient une MeshPart. Son NOM encode le rendu Roblox :
      <Nom>__<Matériau>__<RRGGBB>        ex. "Frame__SmoothPlastic__1A1C22", "Ring__Neon__8B7CFF"
  Matériaux Roblox valides : SmoothPlastic, Plastic, Metal, DiamondPlate, Glass, Neon, Foil, Fabric,
  Granite, Marble, Wood, Concrete, Ice, ForceField, CorrodedMetal, Pebble.
  Suffixe optionnel "__Spin" : pièce qui tourne en jeu (pales de ventilateur, rotor) — son origine
  doit être sur l'axe de rotation et l'axe = Z Blender (donc Y Roblox) sauf mention contraire.
- ≤ 20 000 triangles par objet (limite Roblox), viser ≤ 8 000 ; ≤ 12 objets par modèle.
- Origine du modèle = centre de la base (le modèle est posé sur le sol en z = 0).
"""
import bpy, bmesh, math, os
from mathutils import Vector, Matrix

HERE = os.path.dirname(os.path.abspath(__file__))
MODELS = os.path.join(HERE, "..", "models")
PREVIEWS = os.path.join(HERE, "..", "previews")
VALID = {"SmoothPlastic", "Plastic", "Metal", "DiamondPlate", "Glass", "Neon", "Foil", "Fabric",
         "Granite", "Marble", "Wood", "Concrete", "Ice", "ForceField", "CorrodedMetal", "Pebble"}


def reset():
    bpy.ops.wm.read_factory_settings(use_empty=True)


def hex_rgb(h):
    h = h.lstrip("#")
    srgb = [int(h[i:i + 2], 16) / 255 for i in (0, 2, 4)]
    # couleur linéaire pour Blender
    return tuple(((c + 0.055) / 1.055) ** 2.4 if c > 0.04045 else c / 12.92 for c in srgb)


_mats = {}


def material(roblox_material, hex_color):
    """Matériau Blender (pour l'aperçu) correspondant au couple Roblox (matériau, couleur)."""
    key = (roblox_material, hex_color.upper())
    if key in _mats:
        return _mats[key]
    m = bpy.data.materials.new(f"{roblox_material}_{hex_color}")
    m.use_nodes = True
    b = m.node_tree.nodes["Principled BSDF"]
    col = hex_rgb(hex_color)
    b.inputs["Base Color"].default_value = (*col, 1)
    b.inputs["Metallic"].default_value = 1.0 if roblox_material in ("Metal", "DiamondPlate", "Foil", "CorrodedMetal") else 0.0
    b.inputs["Roughness"].default_value = {"Metal": 0.3, "Foil": 0.15, "Glass": 0.05, "SmoothPlastic": 0.35,
                                          "Neon": 0.2, "Fabric": 0.9}.get(roblox_material, 0.5)
    if roblox_material == "Neon":
        b.inputs["Emission Color"].default_value = (*col, 1)
        b.inputs["Emission Strength"].default_value = 6
    if roblox_material == "Glass":
        b.inputs["Transmission Weight"].default_value = 0.9
    _mats[key] = m
    return m


def tag(obj, name, roblox_material, hex_color, spin=False):
    """Nomme l'objet selon la convention et lui donne le matériau d'aperçu."""
    assert roblox_material in VALID, roblox_material
    obj.name = f"{name}__{roblox_material}__{hex_color.upper()}" + ("__Spin" if spin else "")
    obj.data.materials.clear()
    obj.data.materials.append(material(roblox_material, hex_color))
    return obj


def active():
    return bpy.context.view_layer.objects.active


def apply_modifiers(obj):
    bpy.context.view_layer.objects.active = obj
    for m in list(obj.modifiers):
        bpy.ops.object.modifier_apply(modifier=m.name)


def bevel(obj, width, segments=3, angle=35):
    m = obj.modifiers.new("Bevel", "BEVEL")
    m.width = width
    m.segments = segments
    m.limit_method = "ANGLE"
    m.angle_limit = math.radians(angle)
    return m


def smooth(obj, angle=35):
    bpy.context.view_layer.objects.active = obj
    obj.select_set(True)
    bpy.ops.object.shade_smooth_by_angle(angle=math.radians(angle))


def box(size, location=(0, 0, 0), bevel_width=0.0, segments=3):
    bpy.ops.mesh.primitive_cube_add(size=1, location=location)
    o = active()
    o.scale = size
    bpy.ops.object.transform_apply(scale=True)
    if bevel_width > 0:
        bevel(o, bevel_width, segments)
        apply_modifiers(o)
    smooth(o)
    return o


def cylinder(radius, depth, location=(0, 0, 0), vertices=48, bevel_width=0.0, rotation=(0, 0, 0)):
    bpy.ops.mesh.primitive_cylinder_add(vertices=vertices, radius=radius, depth=depth, location=location, rotation=rotation)
    o = active()
    if bevel_width > 0:
        bevel(o, bevel_width, 3)
        apply_modifiers(o)
    smooth(o)
    return o


def boolean(obj, cutter, operation="DIFFERENCE"):
    m = obj.modifiers.new("Bool", "BOOLEAN")
    m.object = cutter
    m.operation = operation
    apply_modifiers(obj)
    bpy.data.objects.remove(cutter)
    return obj


def join(objs, name=None):
    bpy.ops.object.select_all(action="DESELECT")
    for o in objs:
        o.select_set(True)
    bpy.context.view_layer.objects.active = objs[0]
    bpy.ops.object.join()
    o = active()
    if name:
        o.name = name
    return o


def tube(points, radius, segments=16, name="Tube"):
    """Câble / tube lisse le long d'une liste de points (courbe de Bézier + profil rond)."""
    curve = bpy.data.curves.new(name, "CURVE")
    curve.dimensions = "3D"
    spline = curve.splines.new("BEZIER")
    spline.bezier_points.add(len(points) - 1)
    for p, co in zip(spline.bezier_points, points):
        p.co = co
        p.handle_left_type = p.handle_right_type = "AUTO"
    curve.bevel_depth = radius
    curve.bevel_resolution = max(2, segments // 4)
    curve.resolution_u = 12
    obj = bpy.data.objects.new(name, curve)
    bpy.context.collection.objects.link(obj)
    bpy.context.view_layer.objects.active = obj
    obj.select_set(True)
    bpy.ops.object.convert(target="MESH")
    smooth(active())
    return active()


def triangles(obj):
    return sum(len(p.vertices) - 2 for p in obj.data.polygons)


def finish(model_name, preview=True, camera=(1.6, -2.0, 1.3), samples=32):
    """Applique tout, vérifie les budgets, exporte le .glb et rend un aperçu."""
    meshes = [o for o in bpy.data.objects if o.type == "MESH" and o.visible_get()]
    total = 0
    for o in meshes:
        # Normales pondérées : ombrage net des surfaces dures (après booléens et biseaux).
        wn = o.modifiers.new("WeightedNormal", "WEIGHTED_NORMAL")
        wn.keep_sharp = True
        wn.mode = "FACE_AREA"
        apply_modifiers(o)
        t = triangles(o)
        total += t
        assert t <= 20000, f"{o.name}: {t} triangles (> 20 000)"
        assert "__" in o.name, f"objet sans convention de nom : {o.name}"
    assert len(meshes) <= 12, f"{len(meshes)} objets (> 12)"
    bpy.ops.object.select_all(action="DESELECT")
    for o in meshes:
        o.select_set(True)
    os.makedirs(MODELS, exist_ok=True)
    path = os.path.join(MODELS, f"{model_name}.glb")
    bpy.ops.export_scene.gltf(filepath=path, export_format="GLB", use_selection=True, export_apply=True)
    print(f"[{model_name}] {len(meshes)} pièces, {total} triangles -> {path}")
    if preview:
        render_preview(model_name, meshes, camera, samples)
    return total


def render_preview(model_name, meshes, camera, samples):
    scene = bpy.context.scene
    # cadre la caméra sur la boîte englobante
    mins = Vector((1e9, 1e9, 1e9)); maxs = Vector((-1e9, -1e9, -1e9))
    for o in meshes:
        for v in o.bound_box:
            w = o.matrix_world @ Vector(v)
            mins = Vector(map(min, mins, w)); maxs = Vector(map(max, maxs, w))
    center = (mins + maxs) / 2
    radius = (maxs - mins).length / 2 or 1
    target = bpy.data.objects.new("Target", None)
    target.location = center
    bpy.context.collection.objects.link(target)
    direction = Vector(camera).normalized()
    bpy.ops.object.camera_add(location=center + direction * radius * 3.2)
    cam = active()
    cam.data.lens = 50
    c = cam.constraints.new("TRACK_TO"); c.target = target
    scene.camera = cam
    for loc, energy in (((1, -1, 1.5), 900), ((-1.5, 0.5, 1), 350), ((0, 1.5, 0.5), 250)):
        bpy.ops.object.light_add(type="AREA", location=center + Vector(loc) * radius * 3)
        light = active(); light.data.energy = energy * radius * radius / 4; light.data.size = radius * 2
        t = light.constraints.new("TRACK_TO"); t.target = target
    world = bpy.data.worlds.new("World"); scene.world = world; world.use_nodes = True
    world.node_tree.nodes["Background"].inputs[0].default_value = (0.02, 0.022, 0.03, 1)
    scene.render.engine = "CYCLES"; scene.cycles.samples = samples; scene.cycles.device = "CPU"
    scene.render.resolution_x = 640; scene.render.resolution_y = 480
    scene.view_settings.view_transform = "AgX"
    os.makedirs(PREVIEWS, exist_ok=True)
    scene.render.filepath = os.path.join(PREVIEWS, f"{model_name}.png")
    bpy.ops.render.render(write_still=True)
