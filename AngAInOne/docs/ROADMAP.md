# AngAInOne v2 — « Opération Anti-Lag » · Feuille de route

Scénario : [`SCENARIO.md`](SCENARIO.md). Contrat de la tour : `src/shared/Config/Tower.luau`.

## To-do list

### Phase 0 — Conception et contrats (chef de projet)
- [x] Scénario complet (histoire, personnages, 7 mondes, incidents, boss, lobby, difficulté)
- [x] Contrats partagés : `Tower.luau` (nouveaux pièges, incidents, sbires), `Incidents.luau`,
      `Util/TrapClock.luau` (horloge des pièges qui tient compte des incidents), données (clés USB)
- [x] Découpage du travail entre agents (ci-dessous)

### Phase 1 — Fondations (4 agents en parallèle)
- [ ] **A1 · Architecte de la tour** : découper `TowerBuilder` (2 100 lignes) en modules :
      `World/Tower/Common` (outils + contexte), `Shell`, `Lobby`, `Worlds/W1..W7`, salle de terminal
      standard, entrée/sortie fixes de chaque monde ; le rendu actuel est conservé, tests verts.
- [ ] **A2 · Pièges** : `TrapController` — 14 nouveaux pièges (voir contrat), horloge `TrapClock`
      (FREEZE / LAG SPIKE), effets des incidents sur les pièges (BLACKOUT, CORRUPTION, SURCHAUFFE),
      tests de simulation.
- [ ] **A3 · Scénario en jeu** : `IncidentService` (serveur) + incidents côté client (annonce,
      effets d'écran, tempête de pop-ups à fermer, blackout), widget « Performance du PC »
      (FPS / ping / °C), mondes infectés ↔ nettoyés (tags), répliques d'Anga et de LAGZ,
      moniteur du live dans le lobby, cinématique de fin « le live commence ».
- [ ] **A4 · Mini-jeux** : 2 nouveaux mini-jeux (Pop-up Killer, Défrag) + variante boss du
      Firewall (LAGZ), tests.

### Phase 2 — Contenu 3D (5 agents en parallèle, sur la base de A1 + A2)
- [ ] **B1 · Chambre d'Anga + tour** : lobby sur le bureau (écran du live, clavier RGB, souris,
      micro, tasse, lampe), Miniaturiseur AngAInOne (départ), tour vitrée plus réaliste.
- [ ] **B2 · Mondes 1–2** (Centrale, Memory Lanes) : parcours uniques, pièges signature, décor
      infecté/propre, sbires, clés USB.
- [ ] **B3 · Mondes 3–4** (Data Vault, Cryo Tower).
- [ ] **B4 · Mondes 5–6** (The Core, Render Canyon).
- [ ] **B5 · Monde 7 + boss LAGZ** : arène, 3 phases (serveur `BossService` + client
      `BossController`), fin.

### Phase 3 — Intégration (chef de projet)
- [ ] Fusion, clés USB (serveur + HUD + récompenses), équilibrage, relecture indépendante,
      rendus, README, build `.rbxl`, envoi.

## Contrats techniques

### Monde (A1 → B2..B5)
`src/server/World/Tower/Worlds/W{n}.luau` renvoie `function(ctx: Common.WorldContext)`.
Le contexte fournit : la définition du monde, le `Model` du monde, la bande de hauteur
(`ctx.Base` → `ctx.Base + BAND`), l'**entrée** (CFrame d'arrivée, fixe) et la **salle du terminal**
(fixe, construite par `ctx.TerminalRoom()`, avec terminal, portail, rampe vers le monde suivant),
et des outils : `ctx.Checkpoint(stage, cframe)`, `ctx.Coin(position)`, `ctx.UsbKey(position, i)`,
`ctx.Trap(kind, part, attributes)`, `ctx.Hazard(...)`, `ctx.Platform(...)`, palette du monde.
Un monde doit poser les checkpoints `Tower.FirstStage(n) .. Tower.TerminalStage(n) - 1` dans son
parcours ; le checkpoint `TerminalStage(n)` est dans la salle du terminal.

### Pièges (A2 ↔ mondes)
Tag `Trap`, attributs `Kind` (dans `Tower.TrapKinds`), **`World`** (numéro du monde, obligatoire)
et ceux listés dans `Tower.luau`. Le temps des pièges vient de `TrapClock.Now(world)`.

### Incidents (A3 → A2)
Le serveur publie l'état dans `ReplicatedStorage.IncidentState` (attributs par monde) :
`Kind{w}` ("" ou un type d'`Incidents.Kinds`), `Warn{w}` (annonce), `Start{w}`, `End{w}`
(heures `Workspace:GetServerTimeNow()`), `Offset{w}` (secondes de FREEZE déjà écoulées).
Fin d'un FREEZE : `Offset{w} += End - Start` et `Kind{w} = ""` dans la même frame.

### Décor infecté / propre (A3 ↔ mondes)
Tag `Infected` : visible seulement tant que le joueur n'a pas nettoyé le monde (`World`).
Tag `Cleaned` : visible seulement après. Les deux portent l'attribut `World`.

### Clés USB (mondes → phase 3)
Tag `UsbKey`, attribut `KeyId` = `W{n}K{i}` (i = 1..3), non collidable, touchable.
