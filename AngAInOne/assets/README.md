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
python3 tools/upload_models.py             # modèles 3D → ModelAssets.luau
python3 tools/upload_models.py --portrait  # portrait d'Anga (Decal) → Branding.AngaImageId
```

## Vérifier un placement sans Studio

`python3 tools/model_bounds.py` écrit `assets/models/bounds.json` (boîte de chaque noeud-maillage de
chaque `.glb`, à régénérer après avoir modifié un modèle). Les tests Lune s'en servent pour **simuler les
modèles importés** (`tests/lib/FakeModels.luau`, `tests/lib/IsolatedTower.luau`) : `tests/placement.spec.luau`
contrôle chaque pose (dans la tour, `Fit` / `Height` respectés, objets au sol sur leur support, radiateur
debout, barrettes au ras du slot…), `lune run tests/tools/PlacementReport.luau` détaille chaque pose, et
`lune run tests/tools/ExportMap.luau tour.json --models` + `render_top.py` / `render_iso.py` dessinent
la tour avec les modèles. Deux options de `ModelLibrary.Place` évitent de dépendre de l'orientation du
fichier : `Fit` (boîte cible dans les axes du modèle, échelle uniforme) et `Height` (hauteur MONDE une
fois le modèle tourné : un ventilateur modélisé à plat puis dressé mesure bien `Height`).

Le fichier `assets/models/manifest.json` (commité) mémorise l'ID et l'empreinte de chaque modèle
envoyé : relancer le script ne renvoie que les `.glb` modifiés, en mettant à jour l'asset existant.

**Manuel (Studio)** — Fenêtre *Avatar → Importateur 3D* (ou *Fichier → Importer 3D*), choisir le
`.glb`, décocher « Ancrer » inutile (le jeu ancre tout), importer, puis clic droit sur le modèle →
*Enregistrer sur Roblox*. Copier l'ID de l'asset dans `ModelAssets.luau` (clé = nom du fichier).

**Placer un modèle en jeu** : `ModelLibrary.Place(clé, cframe, parent, { Fit = Vector3.new(l, h, p) }, secours)`
— `Fit` = boîte cible dans les axes du modèle (échelle uniforme), plus sûr que `Scale`. Les modèles
exportés couchés sont redressés au chargement (table `ORIENT` de `ModelLibrary`). Option
`Spin = false | "Hide"` : pièces tournantes figées ou retirées (objet animé, pales mortelles devant).

Tant qu'un modèle n'a pas d'ID, le jeu construit son **décor de secours** en blocs : rien ne casse.

## Catalogue

Personnages : face avant vers −Y dans Blender. Chambre d'Anga : façade vers +Y Blender (= LookVector −Z Roblox). Planches : `previews/_sheet_*.png`.

| Clé | Famille | Utilisé dans | État |
|---|---|---|---|
| `Fan120` | Matériel PC | ventilateurs (façade, W4, W6) | ✅ |
| `Fan140` | Matériel PC | ventilateurs 140 (façade, monde refroidissement) | ✅ |
| `GpuCard` | Matériel PC | carte graphique triple ventilo (monde GPU ; redressée au chargement) | ✅ |
| `RamStick` | Matériel PC | barrette DDR5 RGB (monde RAM) | ✅ |
| `CpuCooler` | Matériel PC | ventirad double tour (monde CPU ; modélisé couché, redressé au chargement) | ✅ |
| `AioRadiator` | Matériel PC | radiateur 360 + 3 ventilos (monde refroidissement) | ✅ |
| `PumpReservoir` | Matériel PC | pompe + réservoir lumineux (monde refroidissement) | ✅ |
| `Psu` | Matériel PC | alimentation ATX modulaire (monde alimentation) | ✅ |
| `Capacitor` | Matériel PC | condensateur électrolytique (carte mère) | ✅ |
| `CapacitorBig` | Matériel PC | gros condensateur orange (alimentation, carte mère) | ✅ |
| `Choke` | Matériel PC | self de puissance (VRM) | ✅ |
| `ChokeRow` | Matériel PC | rangée de 6 selfs (VRM autour du socket) | ✅ |
| `M2Ssd` | Matériel PC | SSD M.2 2280 + dissipateur masquable (monde SSD) | ✅ |
| `SataSsd` | Matériel PC | SSD 2,5" alu brossé (monde SSD) | ✅ |
| `VrmHeatsink` | Matériel PC | dissipateur VRM en L (carte mère) | ✅ |
| `ChipsetHeatsink` | Matériel PC | dissipateur chipset logo RGB (carte mère) | ✅ |
| `CpuChip` | Matériel PC | processeur avec IHS gravé (monde CPU) | ✅ |
| `CpuSocket` | Matériel PC | socket LGA + levier (monde CPU) | ✅ |
| `NpuChip` | Matériel PC | puce IA à circuits lumineux (monde IA) | ✅ |
| `CableBraided24` | Matériel PC | nappe ATX 24 broches gainée (alimentation → carte mère) | ✅ |
| `CableSleeved8` | Matériel PC | câble PCIe 8 broches gainé (GPU, parois) | ✅ |
| `PcieSlot` | Matériel PC | slot PCIe x16 blindé (carte mère) | ✅ |
| `DimmSlot` | Matériel PC | slot DDR5 à loquets (carte mère) | ✅ |
| `IoShield` | Matériel PC | panneau I/O arrière (arrière carte mère) | ✅ |
| `CaseFrame` | Matériel PC | pilier d'angle alu + passe-câbles (parois de la tour) | ✅ |
| `Keyboard` | Chambre d'Anga | clavier TKL sur le bureau (touches praticables) | ✅ |
| `Mouse` | Chambre d'Anga | souris gaming à droite du clavier | ✅ |
| `Monitor` | Chambre d'Anga | écran incurvé 32" (SurfaceGui sur `Screen`) | ✅ |
| `MicArm` | Chambre d'Anga | bras micro pincé au bord arrière du bureau (pince 40 studs sous le plateau) | ✅ |
| `Mug` | Chambre d'Anga | mug AngaTV sur le bureau | ✅ |
| `DeskLamp` | Chambre d'Anga | lampe d'architecte sur le bureau | ✅ |
| `Headset` | Chambre d'Anga | casque sur son support, sur le bureau | ✅ |
| `GamingChair` | Chambre d'Anga | fauteuil gaming au sol devant le bureau | ✅ |
| `Desk` | Chambre d'Anga | bureau du lobby (plateau à 720, tapis XXL) | ✅ |
| `Miniaturiseur` | Chambre d'Anga | portail de départ « Mode Intervention » (`Beam` séparé) | ✅ |
| `TerminalConsole` | Chambre d'Anga | borne antivirus des salles sûres (`Screen`, néon recolorable) | ✅ |
| `WebcamLight` | Chambre d'Anga | ring light + webcam sur le bureau | ✅ |
| `Speaker` | Chambre d'Anga | enceintes de bureau (paire) | ✅ |
| `ArcadeCabinet` | Chambre d'Anga | borne d'arcade du lobby (`Screen`) | ✅ |
| `ShopKiosk` | Chambre d'Anga | kiosque boutique du lobby (`Screen`) | ✅ |
| `Plant` | Chambre d'Anga | succulente en pot sur le bureau | ✅ |
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
| `Anga` | Personnages | la mascotte (6 studs, t-shirt rouge logo « A ») : compagnon mini-Anga côté client (`ReplicatedStorage.ClientModels`) et Anga géant du lobby | ✅ |
| `AioDrone` | Personnages | aéroglisseur de l'app sous mini-Anga : anneau néon `8B7CFF`, logo « A », 4 rotors `__Spin` (pièce `Deck` = pont où il se tient) | ✅ |
