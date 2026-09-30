# Modèles 3D d'AngAInOne

Les décors de la tour ne sont plus seulement des blocs : les pièces de PC, la chambre d'Anga et les
personnages sont de **vrais modèles 3D** (maillages détaillés : chanfreins, pales vrillées, ailettes,
câbles tressés…) modélisés en code avec **Blender** puis importés dans Roblox en **MeshParts**.

```
assets/blender/<famille>.py   script Blender (1 script = 1 ou plusieurs modèles)
assets/blender/common.py      outils partagés + conventions + export
assets/models/<Nom>.glb       modèle exporté (glTF binaire), prêt pour Roblox
assets/previews/<Nom>.png     rendu de contrôle (Cycles)
tools/upload_models.py        envoi sur Roblox (Open Cloud) → Config/ModelAssets.luau
src/server/World/ModelLibrary.luau   chargement en jeu, avec décor de secours
```

## Générer / régénérer un modèle

```bash
pip install bpy==4.2.0            # Blender en module Python (sans interface)
cd assets/blender && python3 fan120.py
```

Conventions (détail dans `common.py`) : 1 unité Blender = 1 stud ; origine au centre de la base ;
≤ 20 000 triangles par pièce (viser ≤ 8 000) ; ≤ 12 pièces par modèle ; chaque pièce s'appelle
`<Nom>__<MatériauRoblox>__<RRGGBB>[__Spin]` (le jeu applique le matériau et la couleur, et fait
tourner les pièces `__Spin` autour de leur axe Y).

## Mettre les modèles dans le jeu

**Automatique (recommandé)** — `tools/upload_models.py` envoie chaque `.glb` nouveau ou modifié et
écrit les IDs dans `src/shared/Config/ModelAssets.luau`. Il lit deux variables d'environnement :
`ROBLOX_API_KEY` (clé Open Cloud créée sur create.roblox.com → Open Cloud → API Keys, avec la
permission **Assets : lecture + écriture**) et `ROBLOX_CREATOR_ID` (ton ID utilisateur Roblox ; pour
un groupe, ajoute `ROBLOX_CREATOR_TYPE=Group`). Ne colle jamais la clé dans un fichier du dépôt.

```bash
python3 tools/upload_models.py --dry-run   # liste ce qui serait envoyé
python3 tools/upload_models.py
```

**Manuel (Studio)** — Fenêtre *Avatar → Importateur 3D* (ou *Fichier → Importer 3D*), choisir le
`.glb`, décocher « Ancrer » inutile (le jeu ancre tout), importer, puis clic droit sur le modèle →
*Enregistrer sur Roblox*. Copier l'ID de l'asset dans `ModelAssets.luau` (clé = nom du fichier).

Tant qu'un modèle n'a pas d'ID, le jeu construit son **décor de secours** en blocs : rien ne casse.

## Catalogue

Personnages : face avant vers −Y dans Blender. Planches : `previews/_sheet_*.png`.

| Clé | Famille | Utilisé dans | État |
|---|---|---|---|
| `Fan120` | Matériel PC | ventilateurs (façade, W4, W6) | ✅ |
| `Lagz` | Personnages | boss LAGZ (arène W7), couronne-chargement qui tourne | ✅ |
| `LagzHead` | Personnages | LAGZ qui sort des écrans (incidents, lobby) | ✅ |
| `LagzPortalCore` | Personnages | cœur du virus au centre de l'arène du boss | ✅ |
| `Sparky` | Personnages | sbire du monde 1 (alimentation) | ✅ |
| `PopUp` | Personnages | sbire du monde 2 (RAM), fenêtres de pub | ✅ |
| `Corrupto` | Personnages | sbire du monde 3 (SSD) | ✅ |
| `Dusty` | Personnages | sbire du monde 4 (refroidissement) | ✅ |
| `Minor` | Personnages | sbire du monde 5 (CPU) | ✅ |
| `Freezy` | Personnages | sbire du monde 6 (GPU) | ✅ |
| `VirusBug` | Personnages | ennemi virus qui patrouille | ✅ |
| `UsbKey` | Personnages | clé USB dorée à collectionner (origine au centre, embout vers +X) | ✅ |
| `BitCoin` | Personnages | orbe « Bit » à collectionner (origine au centre, puce qui tourne) | ✅ |
| `Pickaxe` | Personnages | pioche géante du pendule (pivot en haut du manche, 31,65 studs au-dessus de la base) | ✅ |
| `GiantCursor` | Personnages | curseur-flèche géant | ✅ |
| `Hand` | Personnages | curseur-main géant | ✅ |
