#!/usr/bin/env python3
"""Curate downloaded packs into assets/models/<SpeciesId>/ and write MANIFEST.json,
LICENSES.md, contact_sheet.png and src/shared/Config/Models.luau."""
import os, re, json, shutil, sys, subprocess
import numpy as np
import trimesh

SRC = "/home/user/tools/models_src"
PROJ = "/home/user/New/steal-a-kaiju"
OUT = os.path.join(PROJ, "assets/models")
TARGET_HEIGHT = 4.5  # studs at stage 1

PACKS = {
    "ultimatemonsters": {"name": "Quaternius Ultimate Monsters", "url": "https://quaternius.com/packs/ultimatemonsters.html", "license": "CC0 1.0", "licenseFile": "ultimatemonsters/License.txt"},
    "cutemonsters": {"name": "Quaternius Cute Monsters", "url": "https://quaternius.com/packs/cutemonsters.html", "license": "CC0 1.0", "licenseFile": None},
    "animateddinosaurs": {"name": "Quaternius Animated Dinosaurs", "url": "https://quaternius.com/packs/animateddinosaurs.html", "license": "CC0 1.0", "licenseFile": "animateddinosaurs/License.txt"},
    "animatedmonster": {"name": "Quaternius Animated Monsters", "url": "https://quaternius.com/packs/animatedmonster.html", "license": "CC0 1.0", "licenseFile": "animatedmonster/License.txt"},
    "animatedmech": {"name": "Quaternius Animated Mechs", "url": "https://quaternius.com/packs/animatedmech.html", "license": "CC0 1.0", "licenseFile": "animatedmech/License.txt"},
    "animatedrobot": {"name": "Quaternius Animated Robot", "url": "https://quaternius.com/packs/animatedrobot.html", "license": "CC0 1.0", "licenseFile": "animatedrobot/License.txt"},
    "ultimateanimatedanimals": {"name": "Quaternius Ultimate Animated Animals", "url": "https://quaternius.com/packs/ultimateanimatedanimals.html", "license": "CC0 1.0", "licenseFile": "ultimateanimatedanimals/License.txt"},
    "cutefish": {"name": "Quaternius Cute Fish", "url": "https://quaternius.com/packs/cutefish.html", "license": "CC0 1.0", "licenseFile": "cutefish/License.txt"},
    "ultimatefood": {"name": "Quaternius Ultimate Food", "url": "https://quaternius.com/packs/ultimatefood.html", "license": "CC0 1.0", "licenseFile": "ultimatefood/License.txt"},
    "sushirestaurantkit": {"name": "Quaternius Sushi Restaurant Kit", "url": "https://quaternius.com/packs/sushirestaurantkit.html", "license": "CC0 1.0", "licenseFile": None},
}
ATTRIB = "Quaternius (quaternius.com) — CC0, attribution not required but appreciated"

# Per species: pack, model name, files (relative to pack dir), quality, note.
#   fbx     : rigged/animated FBX to import in Studio (None when the source is glTF only)
#   tex     : texture PNG(s) the FBX needs (None = colours embedded / flat materials)
#   preview : self-contained glTF/GLB used for the contact sheet + measurements
def UM(cat, name):  # Ultimate Monsters
    return dict(pack="ultimatemonsters", model=f"{cat}/{name}", fbx=f"ultimatemonsters/{cat}/FBX/{name}.fbx", tex=[f"ultimatemonsters/{cat}/glTF/Atlas_Monsters.png"], preview=f"ultimatemonsters/{cat}/glTF/{name}.gltf")
def CM(name):  # Cute Monsters
    return dict(pack="cutemonsters", model=name, fbx=f"cutemonsters/FBX/{name}.fbx", tex=[f"cutemonsters/Textures/{name}_Texture.png"], preview=f"cutemonsters/glTF/{name}.gltf")
def DINO(name):
    return dict(pack="animateddinosaurs", model=name, fbx=f"animateddinosaurs/FBX/{name}.fbx", tex=None, preview=f"_glb/animateddinosaurs/{name}.glb")
def MECH(name):
    return dict(pack="animatedmech", model=f"Textured/{name}", fbx=f"animatedmech/Textured/FBX/{name}.fbx", tex=[f"animatedmech/Textured/Textures/{name}_Texture.png"], preview=f"animatedmech/Textured/glTF/{name}.gltf")
def ANIMAL(name):
    return dict(pack="ultimateanimatedanimals", model=name, fbx=f"ultimateanimatedanimals/FBX/{name}.fbx", tex=None, preview=f"ultimateanimatedanimals/glTF/{name}.gltf")
def FISH(name):
    return dict(pack="cutefish", model=name, fbx=f"cutefish/FBX/{name}.fbx", tex=None, preview=f"_glb/cutefish/{name}.glb")
def FOOD(name):
    return dict(pack="ultimatefood", model=name, fbx=f"ultimatefood/FBX/{name}.fbx", tex=None, preview=f"_glb/ultimatefood/{name}.glb")
def SUSHI(name):
    return dict(pack="sushirestaurantkit", model=f"Food/{name}", fbx=None, tex=None, preview=f"sushirestaurantkit/Food/glTF/{name}.gltf")

PICKS = {
    # COMMON
    "Toastzilla": dict(**FOOD("Bread_Slice"), quality="ok", note="Static toast slice prop (no rig, no animation): exact food, but eyes/legs must stay procedural or be animated by the client (Squash)."),
    "Gloop": dict(**UM("Blob", "GreenBlob"), quality="good", note="Green blob with big eyes; antenna accessory stays procedural."),
    "Pinchy": dict(**CM("Crab"), quality="good", note="Cute red crab blob with claws (Idle/Walk/Bite/Jump clips)."),
    "DinoNugget": dict(**UM("Big", "Dino"), quality="ok", note="Chubby cartoon dino (pink in texture): tint to nugget orange via MeshPart.Color or swap atlas colours."),
    "Wormzy": dict(**FISH("Worm"), quality="good", note="Pink worm (bait model from Cute Fish), tiny: scale up. Has a Swim/Idle rig."),
    "Pigeonator": dict(**UM("Flying", "Pigeon"), quality="good", note="Flying pigeon monster with wings (Idle/Flying clips)."),
    # RARE
    "Sharkapillar": dict(**FISH("Shark"), quality="ok", note="Cute big-eyed shark; no caterpillar legs (add procedural legs if wanted)."),
    "Croissantosaurus": dict(**FOOD("Croissant"), quality="ok", note="Static croissant prop (no rig): exact food, eyes/spikes stay procedural."),
    "Frostodon": dict(**UM("Big", "Yeti"), quality="ok", note="Ice-themed yeti (biped, not quadruped) with white fur + blue face; horn/spikes procedural."),
    "ThunderSquid": dict(**UM("Flying", "Squidle"), quality="good", note="Flying squid monster; tint yellow, bolt accessory procedural."),
    "Kebabzilla": dict(**FOOD("Corndog"), quality="fallback", note="No kebab/döner model in any CC0 pack; closest skewered food is a corn dog. Keep the procedural model."),
    "BeepBoop": dict(pack="animatedrobot", model="Robot", fbx="animatedrobot/FBX/Robot.fbx", tex=None, preview="_glb/animatedrobot/Robot.glb", quality="good", note="Small orange robot with visor and antenna; 14 clips (Idle, Walking, Running, Dance, Wave...)."),
    # EPIC
    "SushiRex": dict(**SUSHI("Food_SalmonNigiri"), quality="fallback", note="Only a static salmon nigiri exists (no sushi dinosaur); glTF with embedded atlas. Keep the procedural rex unless you rig it."),
    "Robotank": dict(**MECH("George"), quality="good", note="Walker mech with twin guns (Idle/Walk/Run/Shoot clips); textured, olive green."),
    "Magmadillo": dict(**DINO("Stegosaurus"), quality="ok", note="Quadruped with back plates reading as magma plates; flat-colour materials (dark), tint/glow accent procedural."),
    "Bananadon": dict(**DINO("Parasaurolophus"), quality="ok", note="Biped dinosaur with a curved banana-like crest; tint yellow."),
    "Crabzooka": dict(**CM("Crab"), quality="ok", note="Same Cute Monsters crab as Pinchy, tinted grey/orange; cannon accessory procedural."),
    "Pizzapocalypse": dict(**FOOD("Pizza"), quality="ok", note="Static whole pizza prop (no rig): exact food, face/legs procedural."),
    # LEGENDARY
    "Rexplosion": dict(**DINO("Trex"), quality="good", note="Animated T-Rex, dark green (Idle/Walk/Run/Attack/Jump); large file units (15 tall) so Scale is small."),
    "KawaiiKraken": dict(**CM("Cthulhu"), quality="ok", note="Cute tentacled Cthulhu head; tint pink, bow/blush procedural."),
    "ThunderGoose": dict(**UM("Blob", "Chicken"), quality="ok", note="Round orange chicken monster (closest goose); bolt/glow procedural."),
    "Donutron": dict(**FOOD("Donut1"), quality="ok", note="Static pink-frosted donut with sprinkles (exact colours): visor/eyes procedural."),
    "Drakonda": dict(pack="animatedmonster", model="Dragon", fbx="animatedmonster/FBX/Dragon.fbx", tex=None, preview="_glb/animatedmonster/Dragon.glb", quality="good", note="Red winged dragon (Flying/Attack/Hit clips) — has legs unlike the flavour text, but the best dragon in the packs."),
    # MYTHIC
    "Kaijumbo": dict(**ANIMAL("Bull"), quality="ok", note="Big horned quadruped (horns ~ tusks); tint blue-grey, crown procedural. Idle/Walk/Gallop/Headbutt clips."),
    "Nebulodon": dict(**DINO("Velociraptor"), quality="ok", note="Sleek raptor; tint deep purple, stars/glow procedural."),
    "Hydroblob": dict(**UM("Blob", "Fish"), quality="good", note="Blue blob-fish with fins: water blob; crown procedural."),
    "Crabageddon": dict(**CM("Crab"), quality="ok", note="Cute Monsters crab again, tinted near-black with red claws; spikes/crown/glow procedural."),
    # CELESTIAL
    "SolarisRex": dict(**DINO("Trex"), quality="ok", note="Same T-Rex as Rexplosion, tinted orange/gold; halo procedural."),
    "LunarSquid": dict(**UM("Flying", "Hywirl"), quality="ok", note="Pale violet flying tentacle creature; halo/stars procedural."),
    "CosmoGoose": dict(**UM("Big", "Birb"), quality="ok", note="Big blue bird biped with wings and beak; tint dark violet, halo/stars procedural."),
    # SECRETS
    "SharktoastSupreme": dict(**FISH("GoblinShark"), quality="fallback", note="Toothy goblin shark for 'breakfast has teeth' — no toast; keep the procedural toast+fin unless you want a shark."),
    "CroissantKraken": dict(**UM("Flying", "Squidle"), quality="ok", note="Same Squidle as ThunderSquid, tinted croissant gold; crown procedural."),
    "NuclearPigeon": dict(**UM("Blob", "Pigeon"), quality="good", note="Pigeon blob monster; tint radioactive green, glow/bolt/crown procedural."),
    "OmegaSushiMech": dict(**MECH("Leela"), quality="good", note="White/orange mech (Idle/Walk/Run/Shoot); matches the sushi colours."),
    "InfiniteBlob": dict(**UM("Blob", "PinkBlob"), quality="good", note="Purple blob with eyes; halo/stars procedural."),
    "KingKaiju": dict(**UM("Big", "Demon"), quality="ok", note="Red horned demon boss (biped, spiky, winged); tint black/gold, crown/halo procedural."),
}

SPECIES_ORDER = ["Toastzilla", "Gloop", "Pinchy", "DinoNugget", "Wormzy", "Pigeonator", "Sharkapillar", "Croissantosaurus", "Frostodon", "ThunderSquid", "Kebabzilla", "BeepBoop", "SushiRex", "Robotank", "Magmadillo", "Bananadon", "Crabzooka", "Pizzapocalypse", "Rexplosion", "KawaiiKraken", "ThunderGoose", "Donutron", "Drakonda", "Kaijumbo", "Nebulodon", "Hydroblob", "Crabageddon", "SolarisRex", "LunarSquid", "CosmoGoose", "SharktoastSupreme", "CroissantKraken", "NuclearPigeon", "OmegaSushiMech", "InfiniteBlob", "KingKaiju"]

# check against Kaijus.luau
kaijus_src = open(os.path.join(PROJ, "src/shared/Config/Kaijus.luau")).read()
ids = re.findall(r'^\s*(?:S|Secret)\("([A-Za-z]+)"', kaijus_src, re.M)
assert set(ids) == set(SPECIES_ORDER) == set(PICKS), (set(ids) ^ set(SPECIES_ORDER), set(ids) ^ set(PICKS))


def anim_names(fbx_path):
    if not fbx_path:
        return []
    d = open(fbx_path, "rb").read()
    names = set()
    for m in re.findall(rb"([A-Za-z_|0-9 ]+)\x00\x01AnimStack", d):
        n = m.decode(errors="ignore").split("|")[-1].strip()
        if n:
            names.add(n)
    return sorted(names)


def measure(path):
    s = trimesh.load(path, force="scene", process=False)
    lo, hi = s.bounds
    return lo, hi


shutil.rmtree(OUT, ignore_errors=True)
os.makedirs(OUT)
manifest = {}
sheet_items = []
for sid in SPECIES_ORDER:
    p = PICKS[sid]
    dst = os.path.join(OUT, sid)
    os.makedirs(dst)
    files = []
    primary = None
    if p["fbx"]:
        src = os.path.join(SRC, p["fbx"])
        name = os.path.basename(src)
        shutil.copy2(src, os.path.join(dst, name)); files.append(name); primary = name; fmt = "fbx"
        for t in p["tex"] or []:
            tn = os.path.basename(t)
            shutil.copy2(os.path.join(SRC, t), os.path.join(dst, tn)); files.append(tn)
    # preview / alternative import (self-contained glTF or GLB)
    prev_src = os.path.join(SRC, p["preview"])
    prev_name = os.path.basename(prev_src)
    if prev_name.endswith(".gltf"):
        prev_name = prev_name  # embedded buffers + textures (data URIs)
    shutil.copy2(prev_src, os.path.join(dst, prev_name)); files.append(prev_name)
    if primary is None:
        primary = prev_name; fmt = "gltf" if prev_name.endswith(".gltf") else "glb"
    lo, hi = measure(prev_src)
    height = float(hi[1] - lo[1])
    scale = TARGET_HEIGHT / height
    off = [float(-(lo[0] + hi[0]) / 2), float(-lo[1]), float(-(lo[2] + hi[2]) / 2)]
    total = sum(os.path.getsize(os.path.join(dst, f)) for f in files)
    assert total < 20 * 1024 * 1024, (sid, total)
    pk = PACKS[p["pack"]]
    anims = anim_names(os.path.join(SRC, p["fbx"]) if p["fbx"] else None)
    manifest[sid] = {
        "file": primary,
        "format": fmt,
        "files": files,
        "preview": os.path.basename(prev_src),
        "textures": [os.path.basename(t) for t in (p["tex"] or [])] if p["fbx"] else ["embedded in glTF"],
        "source": pk["url"],
        "pack": pk["name"],
        "model": p["model"],
        "license": pk["license"],
        "attribution": ATTRIB,
        "animations": anims,
        "notes": p["note"],
        "scaleHint": round(height, 3),
        "boundsMin": [round(float(x), 3) for x in lo],
        "boundsMax": [round(float(x), 3) for x in hi],
        "suggestedScale": round(scale, 4),
        "suggestedOffset": [round(x, 3) for x in off],
        "matchQuality": p["quality"],
        "bytes": total,
    }
    sheet_items.append({"label": f"{sid}", "path": prev_src, "sub": f"{p['model']} [{p['quality']}] h={height:.2f}"})
    print(f"{sid:20s} {p['pack']:24s} {p['model']:26s} {p['quality']:8s} h={height:6.2f} anims={len(anims)} {total/1024:.0f}KB")

json.dump(manifest, open(os.path.join(OUT, "MANIFEST.json"), "w"), indent=2)

# ---------- LICENSES.md ----------
used = sorted({PICKS[s]["pack"] for s in SPECIES_ORDER})
lines = ["# Licences des modèles 3D (assets/models/)", "",
         "Tous les modèles proviennent de packs **CC0 1.0 (domaine public)** de Quaternius",
         "(https://quaternius.com — « A library of hundreds of free Low Poly 3D Models, using the CC0 License »).",
         "Aucune attribution n'est exigée ; elle est appréciée : *« 3D models by Quaternius »*.", "",
         "| Pack | Page | Licence | Espèces |", "|---|---|---|---|"]
for pk in used:
    sp = [s for s in SPECIES_ORDER if PICKS[s]["pack"] == pk]
    lines.append(f"| {PACKS[pk]['name']} | {PACKS[pk]['url']} | {PACKS[pk]['license']} | {', '.join(sp)} |")
lines += ["", "## Texte de licence fourni dans les packs", ""]
seen = set()
for pk in used:
    lf = PACKS[pk]["licenseFile"]
    if lf and os.path.exists(os.path.join(SRC, lf)):
        txt = open(os.path.join(SRC, lf)).read().strip()
        if txt in seen:
            continue
        seen.add(txt)
        lines += [f"### {PACKS[pk]['name']} (`License.txt`)", "", "```", txt, "```", ""]
    else:
        lines += [f"### {PACKS[pk]['name']}", "", f"Pas de fichier License.txt dans le dossier Google Drive ; la page {PACKS[pk]['url']} indique « License CC0 ».", ""]
lines += ["## Effets visuels (assets/vfx/)", "",
          "- Kenney Particle Pack 1.1 — https://kenney.nl/assets/particle-pack — CC0 1.0",
          "- Kenney Smoke Particles — https://kenney.nl/assets/smoke-particles — CC0 1.0",
          "- Sprites générés par `tools/models/curate_vfx.py` (circle, bubble, skull, confetti, radioactive, drip, bolt, leaf) — CC0 1.0", ""]
open(os.path.join(OUT, "LICENSES.md"), "w").write("\n".join(lines))

# ---------- contact sheet ----------
spec = "/tmp/models_spec.json"
json.dump(sheet_items, open(spec, "w"))
subprocess.run([sys.executable, "/home/user/tools/render_models.py", os.path.join(OUT, "contact_sheet.png"), "--spec", spec, "--cell", "256", "--cols", "6"], check=True, stdout=subprocess.DEVNULL)

# ---------- Models.luau ----------
def lua_num(x):
    s = f"{x:.4f}".rstrip("0").rstrip(".")
    return "0" if s in ("", "-0", "-") else s

L = []
L.append("""--!strict
-- Vrais modèles 3D des kaijus (pack assets/models/<Espèce>/, packs CC0 de Quaternius ;
-- voir assets/models/MANIFEST.json et LICENSES.md, aperçu : assets/models/contact_sheet.png).
--
-- Tant que MeshId == 0, le jeu construit le modèle procédural (KaijuBuilder). Dès qu'un
-- MeshId est renseigné, le client peut afficher le mesh importé à la place.
--
-- Champs :
--   MeshId     : identifiant du mesh uploadé (0 = pas encore importé).
--   TextureId  : identifiant de la texture (0 = pas de texture : couleurs plates du mesh).
--   Scale      : facteur pour que le kaiju fasse ~4,5 studs de haut au stade 1 (Baby),
--                calculé pour un import à l'échelle « 1 unité du fichier = 1 stud ».
--                Les stades suivants multiplient par Growth.Stages[i].Scale.
--   Offset     : décalage (studs, déjà multiplié par Scale) qui ramène le centre du mesh
--                au sol / au centre, si le fichier n'est pas déjà posé en (0,0,0).
--   Animations : identifiants des animations publiées (0 = pas encore publiée).
--   Source     : pack d'origine.  Quality : "good" | "ok" | "fallback" (voir MANIFEST.json ;
--                pour "fallback" mieux vaut garder le modèle procédural).
--
-- IMPORT DANS STUDIO (par espèce) --------------------------------------------------------
-- 1. Onglet Avatar → « 3D Importer » (ou Fichier → Import 3D…). Choisis le .fbx (ou le
--    .gltf/.glb) du dossier assets/models/<Espèce>/ ; la texture .png doit être dans le
--    même dossier (elle y est déjà).
-- 2. Dans le panneau d'import : « Scale Unit » = Studs (1 unité = 1 stud, sinon adapte
--    Scale), coche « Upload to Roblox » (indispensable pour obtenir un MeshId) et, pour les
--    modèles animés, garde « Import Animations » / « Rig type : Custom ». Valide.
-- 3. Un Model est inséré dans Workspace. Sélectionne son MeshPart (ou le premier s'il y en
--    a plusieurs) → Propriétés → « MeshId » = rbxassetid://NNNN : copie NNNN dans MeshId.
--    « TextureID » (ou SurfaceAppearance.ColorMap si un SurfaceAppearance a été créé)
--    donne TextureId. Sans texture (matériaux à couleurs plates), laisse 0 et vérifie
--    que les couleurs de sommets ont été importées (sinon MeshPart.Color = Primary).
-- 4. Animations : le rig importé contient un dossier « AnimSaves » (KeyframeSequences).
--    Ouvre Avatar → Animation Editor, sélectionne le rig, menu « … » → Load → choisis le
--    clip (ex. Idle, Walk — noms listés dans MANIFEST.json), puis « … » → « Publish to
--    Roblox » ; copie l'identifiant obtenu dans Animations.Idle / Animations.Walk.
--    (Alternative : « … » → Import → From FBX Animation, avec le même .fbx.)
-- 5. Supprime le Model de test du Workspace : le client instancie le mesh lui-même.
-- Les modèles « prop » (toast, croissant, donut, pizza, sushi, corn dog) n'ont ni rig ni
-- animation : laisse Animations à 0 ; le client garde ses animations procédurales.

export type ModelDef = {
	MeshId: number,
	TextureId: number,
	Scale: number,
	Offset: Vector3?,
	Animations: { Idle: number, Walk: number },
	Source: string,
	Quality: string,
}

local Defs: { [string]: ModelDef } = {""")
for sid in SPECIES_ORDER:
    m = manifest[sid]
    off = [round(x * m["suggestedScale"], 3) for x in m["suggestedOffset"]]
    if all(abs(o) < 0.05 for o in off):
        off_s = "nil"
    else:
        off_s = f"Vector3.new({lua_num(off[0])}, {lua_num(off[1])}, {lua_num(off[2])})"
    L.append(f"\t-- {m['pack']} / {m['model']} ({m['file']}, {m['scaleHint']} unités de haut)")
    L.append(f"\t{sid} = {{ MeshId = 0, TextureId = 0, Scale = {lua_num(m['suggestedScale'])}, Offset = {off_s}, Animations = {{ Idle = 0, Walk = 0 }}, Source = \"{m['pack']}\", Quality = \"{m['matchQuality']}\" }},")
L.append("""}

local Models = {}

--- Toutes les définitions (lecture seule), indexées par identifiant d'espèce.
Models.Defs = Defs

--- Définition pour une espèce, ou nil si aucun modèle n'est prévu.
function Models.Get(speciesId: string): ModelDef?
	return Defs[speciesId]
end

--- true si un mesh a été importé pour l'espèce (MeshId renseigné) : le client peut alors
--- afficher le vrai modèle au lieu du modèle procédural.
function Models.HasMesh(speciesId: string): boolean
	local def = Defs[speciesId]
	return def ~= nil and def.MeshId ~= 0
end

--- Identifiant d'animation publié pour l'espèce ("Idle" | "Walk"), ou nil.
function Models.AnimationId(speciesId: string, name: string): string?
	local def = Defs[speciesId]
	if def == nil then
		return nil
	end
	local id = def.Animations.Idle
	if name == "Walk" then
		id = def.Animations.Walk
	end
	if id == 0 then
		return nil
	end
	return "rbxassetid://" .. id
end

return Models
""")
open(os.path.join(PROJ, "src/shared/Config/Models.luau"), "w").write("\n".join(L))
print("done; total", sum(m["bytes"] for m in manifest.values()) / 1e6, "MB")
