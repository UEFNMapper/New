--!strict
--[[
	TowerBuilder : construit toute la tour PC verticale du deathrun (Workspace.Tower).
	Orchestrateur seulement : le contenu est dans World/Tower (voir l'en-tête de Tower/Common.luau) :
	- Tower/Lobby.luau        lobby sur le bureau + maison de départ (checkpoint 0)
	- Tower/Shell.luau        coque vitrée de la tour
	- Tower/Worlds/W{n}.luau  un module par monde : `function(ctx: Common.WorldContext)`
	- Tower/Common.luau       dimensions, repères, palette, contexte de monde, salle du terminal standard
	- Tower/Bonus.luau        détours « Ventilo bonus » (un par monde, accroché à un checkpoint)
	- Tower/Legacy.luau       parcours v1 (anneau de modules) et décor v1, réutilisés par W1..W7
	- ModelLibrary.luau       vrais modèles 3D (Blender → assets/models/*.glb), avec décor de secours

	Contrat (voir Config/Tower) :
	Workspace.Tower
	├─ Lobby        (Model, Persistent) LobbySpawn, AppScreen, LeaderboardScreen×3 (Board),
	│                TitleHologram, bornes Shop/Arcade/Daily (prompt Action), AngaSpot, porte d'entrée
	├─ Checkpoints  pads tag Checkpoint, attribut Stage (0 = entrée du parcours, dans le lobby)
	├─ Shell        (Model, Persistent) parois, vitre, ventilateurs de façade
	└─ World1..7    (Model, Atomic, attribut World)
	     ├─ Stage{s}   plateformes + pièges (tag Trap, attributs Kind + World + paramètres)
	     ├─ Bonus      détour « Ventilo bonus » (tag BonusRoute, attributs World, Stage, Bits) : passerelle,
	     │             ventilateur à pales SpinBar, Méga-Bit (Value 5) — voir Tower/Bonus.luau
	     ├─ Coins      orbes « Bit » (tag Coin, attribut CoinId unique "S{s}C{i}" ; Bonus = true et
	     │             Value > 1 pour ceux des détours)
	     ├─ UsbKeys    clés USB dorées (tag UsbKey, attribut KeyId "W{n}K{i}"), si le monde en pose
	     ├─ Terminal   salle du terminal : MinigameTerminal, WorldGate (+ Finish au monde 7)
	     └─ Decor      composant géant, vide mortel (tag Hazard), panneaux

	Attributs des pièges (animés côté client par TrapController à partir de GetServerTimeNow) :
	- World : numéro du monde (obligatoire, posé par ctx.Trap).
	- Offset / Direction : Vector3 en coordonnées MONDE (studs). Axis : "X" | "Y" | "Z" (axe LOCAL).
	- Phase : fraction de période (ou de tour pour SpinBar, de boucle pour Virus), dans [0, 1[.
	- Waypoints (Virus) : chaîne "x,y,z;x,y,z;…" = décalages MONDE relatifs à la position de repos
	  (le premier point vaut 0,0,0) ; la patrouille boucle sur les points (aller-retour si 2 points).
	Les pièges mortels sont non solides (CanCollide false) : le client détecte le contact lui-même.

	Budget : ≤ 8000 BaseParts, ≤ 90 PointLights (tests/tower.spec.luau).
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Workspace = game:GetService("Workspace")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Tower = require(Shared.Config.Tower)
local TowerParts = script.Parent.Tower
local Common = require(TowerParts.Common)
local Legacy = require(TowerParts.Legacy)
local Lobby = require(TowerParts.Lobby)
local Shell = require(TowerParts.Shell)
local Cameos = require(TowerParts.Cameos)
local AppPanels = require(TowerParts.AppPanels)
local Bonus = require(TowerParts.Bonus)
local ModelLibrary = require(script.Parent.ModelLibrary)

type WorldBuilder = (ctx: Common.WorldContext) -> ()

-- Un module par monde (l'ordre suit Tower.Worlds).
local WORLDS: { WorldBuilder } = {
	require(TowerParts.Worlds.W1),
	require(TowerParts.Worlds.W2),
	require(TowerParts.Worlds.W3),
	require(TowerParts.Worlds.W4),
	require(TowerParts.Worlds.W5),
	require(TowerParts.Worlds.W6),
	require(TowerParts.Worlds.W7),
}

local TowerBuilder = {}

TowerBuilder.Dimensions = Common.Dimensions
TowerBuilder.StageHeight = Common.StageHeight
TowerBuilder.ModuleList = Legacy.ModuleList

function TowerBuilder.Build(): Folder
	local existing = Workspace:FindFirstChild("Tower")
	if existing then
		existing:Destroy()
	end
	ModelLibrary.Preload() -- vrais modèles 3D (Config/ModelAssets) ; sinon décor de secours
	local tower = Instance.new("Folder")
	tower.Name = "Tower"
	Common.Begin(tower)
	Lobby.Build(tower)
	Shell.Build(tower)
	assert(#WORLDS == Tower.WORLD_COUNT, "un module par monde")
	for i, world in Tower.Worlds do
		local ctx, finish = Common.NewContext(tower, world)
		WORLDS[i](ctx)
		Bonus.Build(ctx) -- détour « Ventilo bonus » accroché à un checkpoint du monde
		finish()
	end
	Cameos.Build(tower) -- LAGZ dans un écran sur les parois de chaque monde (client LagzCameo)
	AppPanels.Build(tower) -- fenêtres de l'app AngAInOne sur les parois des mondes
	tower:SetAttribute("PointLights", Common.LightCount())
	tower.Parent = Workspace
	return tower
end

return TowerBuilder
