# Brief commun des agents « mondes » (phase 2)

Tu construis un ou plusieurs mondes du deathrun **AngAInOne** (tour PC géante, Roblox, Luau `--!strict`).
Réponds en français ; identifiants en anglais, commentaires en français.

## À lire d'abord
- `docs/SCENARIO.md` (§4 incidents, §5 ton monde, §7 difficulté), `docs/ROADMAP.md` (contrats).
- `src/shared/Config/Tower.luau` (mondes, TrapKinds + attributs de chaque piège).
- `src/server/World/Tower/Common.luau` : en-tête = géométrie fixe (entrée, porte de la salle du
  terminal, volumes réservés) + `WorldContext` (Stage, Checkpoint, Coin, UsbKey, Trap, Hazard,
  Platform, Infected, Cleaned, Lamp, Void, Entrance, TerminalRoom). `Tower/Legacy.luau` = ancien
  parcours (anneau répétitif) que tu REMPLACES dans ton monde.
- `src/client/Controllers/Traps/*.luau` + `TrapController.luau` : comment chaque piège est animé
  (attributs, marqueurs invisibles de TabRain / Cursor, `Holes` de FirewallWall, Spinner Count/Ring/PadSize…).
- `tests/tower.spec.luau` (graphe de sauts, budgets, attributs requis, code couleur) et `tests/traps.spec.luau`.
- `src/server/World/ModelLibrary.luau` + `assets/README.md` : vrais modèles 3D.

## Ce qu'on attend
- Un parcours **unique** par monde, qui raconte le composant (voir SCENARIO §5) : on doit
  reconnaître le composant, pas un anneau générique. 5 étapes : 1 idée par étape (étapes 1–4), la 5ᵉ
  combine ; checkpoints `FirstStage(n) .. TerminalStage(n)-1` via `ctx.Checkpoint`, plateformes de
  l'étape s dans `ctx.Stage(s)`. Le parcours part de `ctx.Entry` et finit devant `ctx.Terminal.Door`.
- Les **pièges signature** du monde (les nouveaux en priorité), variés, jamais deux étapes pareilles.
  Difficulté : écarts ≤ 6,5 studs, fenêtres sûres ≥ 1,2 s (monde 1) → ≥ 0,8 s (monde 7) ; monde 1 =
  tutoriel. Ce qui tue est rouge/magenta et non solide ; les plateformes sûres sont lisibles.
- **Scénario dans le décor** : versions `ctx.Infected(...)` (glitch violet, pubs flottantes, néons
  rouges d'alerte, composant terne) et `ctx.Cleaned(...)` (composant qui brille, ventilos, RGB propre).
  L'incident vedette du monde doit avoir un vrai impact sur ton parcours (ex. Powered en BLACKOUT,
  Corrupt en CORRUPTION, Heat/Wind en SURCHAUFFE, pièges figés en FREEZE = fenêtre de passage).
- 3–6 Bits par étape, **3 clés USB** (`ctx.UsbKey(pos, i)`) sur des chemins facultatifs difficiles.
- Le **sbire** du monde près du terminal (modèle 3D, voir ci-dessous).

## Décor : VRAIS modèles 3D (demande explicite du client : « arrête le low poly »)
Le décor visible utilise `ModelLibrary.Place(key, cframe, parent, { Scale = ..., Collide = false }, fallback)`.
Des agents modélisent en parallèle (Blender → .glb) ces clés ; utilise-les là où elles ont du sens :
- Matériel : `Fan120`, `Fan140`, `GpuCard`, `RamStick`, `CpuCooler`, `AioRadiator`, `PumpReservoir`, `Psu`,
  `Capacitor`, `CapacitorBig`, `Choke`, `ChokeRow`, `M2Ssd`, `SataSsd`, `VrmHeatsink`, `ChipsetHeatsink`,
  `CpuChip`, `CpuSocket`, `NpuChip`, `CableBraided24`, `CableSleeved8`, `PcieSlot`, `DimmSlot`, `IoShield`, `CaseFrame`.
- Personnages/objets : `Lagz`, `LagzHead`, `Sparky`, `PopUp`, `Corrupto`, `Dusty`, `Minor`, `Freezy`, `VirusBug`,
  `UsbKey`, `BitCoin`, `Pickaxe`, `GiantCursor`, `Hand`, `LagzPortalCore`.
Origine = centre de la base, 1 stud = 1 unité ; tailles de référence dans `assets/README.md` quand elles
y sont (sinon utilise `Scale`). **Le `fallback` est obligatoire** : une fonction qui construit une
version soignée en primitives (c'est ce qu'on voit tant que les modèles ne sont pas importés, et ce que
les tests Lune construisent). **Le gameplay ne dépend jamais d'un modèle** : plateformes, murs et pièges
restent des parts primitives (solides, lisibles) ; les modèles sont l'habillage (composants géants
autour/sous le parcours, sbire, détails). Tu peux habiller une plateforme primitive avec un modèle
non collidable posé dessus/autour.

## Règles de travail
- Tu ne modifies QUE tes fichiers `src/server/World/Tower/Worlds/W{n}.luau` (et des fichiers nouveaux
  `Worlds/W{n}*.luau` si besoin). Ne touche pas `Common.luau`, `Legacy.luau`, `Lobby`, `Shell`, le
  client, ni les tests existants ; si un outil manque dans Common, écris-le localement et signale-le.
- Budgets de TON monde : ≤ 900 BaseParts, ≤ 9 lumières (la tour entière ≤ 8000 / ≤ 90).
- Vérifie : `./scripts/verify.sh` (stylua deux fois avant), tout doit être vert, notamment le graphe
  de sauts de `tower.spec`. Rendus de contrôle : `lune run tests/tools/ExportMap.luau` puis
  `python3 tests/tools/render_iso.py --center x,y,z --radius r` (voir `--help`) ; regarde les images
  (Read) et itère jusqu'à ce que ce soit beau et lisible. Joue mentalement chaque étape.
- Ne commite pas. Rapport final concis (français) : parcours étape par étape, pièges utilisés,
  incident, clés USB, modèles utilisés, budgets (parts/lumières), limites connues.
