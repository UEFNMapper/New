--!strict
--[[
	AppPanels : les grandes FENÊTRES DE L'APP AngAInOne accrochées aux parois de la tour.
	Chaque monde incarne une page de l'app (Tower.Worlds[n].AppSection) ; 2 ou 3 fenêtres par monde
	la montrent en train de travailler, et évoluent avec la progression du joueur (dessin et
	animation côté client : Controllers/AppPanels, valeurs : Util/AppPanelLogic).

	Contrat (World{n}/AppPanels) :
	- AppPanel : dalle fine (décor pur : ni collision, ni toucher, ni requêtes), tag "AppPanel",
	  attributs World (n), Page (AppSection du monde), Kind (∈ AppPages.Kinds[n]) ; la face avant
	  (LookVector) regarde l'intérieur de la tour, le client y pose un SurfaceGui quand elle est proche ;
	- Bezel (cadre sombre) et AccentBar (liseré violet), décor pur.
	Emplacements choisis hors du volume du parcours : plaquées sur les parois intérieures
	(-X, façade -Z, fond +Z ; jamais côté vitre +X), dans des zones libres de toute pièce sur 9 studs
	de profondeur, et visibles depuis une bonne partie du parcours (tests/apppanels.spec.luau).
	Budget : 3 pièces par fenêtre, aucune lumière, aucun SurfaceGui côté serveur.
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Tower = require(Shared.Config.Tower)
local Branding = require(Shared.Config.Branding)
local AppPages = require(Shared.Util.AppPanelLogic)
local Build = require(script.Parent.Parent.Build)
local Common = require(script.Parent.Common)

local AppPanels = {}

local INNER = Common.INNER
local INSET = 0.7 -- distance de la dalle à la paroi
local THICK = 0.4

-- Parois intérieures : normale (vers l'intérieur) et axe horizontal le long duquel on place `At`.
local WALLS: { [string]: { Normal: Vector3, Origin: Vector3, Along: Vector3 } } = {
	W = { Normal = Vector3.xAxis, Origin = Vector3.new(-INNER, 0, 0), Along = Vector3.zAxis },
	F = { Normal = Vector3.zAxis, Origin = Vector3.new(0, 0, -INNER), Along = Vector3.xAxis },
	B = { Normal = -Vector3.zAxis, Origin = Vector3.new(0, 0, INNER), Along = Vector3.xAxis },
}

export type Spot = {
	World: number,
	Kind: string,
	Wall: string, -- "W" | "F" | "B"
	At: number, -- position le long de la paroi (Z pour W, X pour F et B)
	Y: number, -- hauteur du centre
	Width: number,
	Height: number,
}

-- Emplacements mesurés sur la tour construite (zones libres, vues depuis le parcours).
AppPanels.Spots = table.freeze({
	{ World = 1, Kind = "PowerPlan", Wall = "W", At = 44, Y = 58, Width = 44, Height = 25 },
	{ World = 1, Kind = "Watts", Wall = "F", At = -34, Y = 66, Width = 44, Height = 25 },
	{ World = 2, Kind = "Startup", Wall = "W", At = 92, Y = 150, Width = 44, Height = 25 },
	{ World = 2, Kind = "Memory", Wall = "B", At = 30, Y = 126, Width = 44, Height = 25 },
	{ World = 3, Kind = "Drive", Wall = "B", At = -46, Y = 270, Width = 44, Height = 25 },
	{ World = 3, Kind = "Treemap", Wall = "W", At = 92, Y = 246, Width = 44, Height = 25 },
	{ World = 4, Kind = "Temps", Wall = "F", At = -20, Y = 358, Width = 44, Height = 25 },
	{ World = 4, Kind = "Verdict", Wall = "W", At = -4, Y = 366, Width = 44, Height = 25 },
	{ World = 5, Kind = "FpsGraph", Wall = "W", At = -28, Y = 454, Width = 44, Height = 25 },
	{ World = 5, Kind = "PerfScore", Wall = "B", At = -40, Y = 450, Width = 44, Height = 25 },
	{ World = 5, Kind = "LaunchBanner", Wall = "F", At = -44, Y = 438, Width = 40, Height = 12 },
	{ World = 6, Kind = "Driver", Wall = "B", At = 86, Y = 558, Width = 44, Height = 25 },
	{ World = 6, Kind = "DriverLog", Wall = "F", At = 98, Y = 566, Width = 44, Height = 25 },
	{ World = 7, Kind = "Crashes", Wall = "W", At = -34, Y = 686, Width = 44, Height = 25 },
	{ World = 7, Kind = "CrashAlert", Wall = "B", At = -10, Y = 682, Width = 44, Height = 25 },
}) :: { Spot }

-- Repère de la face avant d'un emplacement (LookVector = vers l'intérieur de la tour).
function AppPanels.FrameOf(spot: Spot): CFrame
	local wall = WALLS[spot.Wall]
	assert(wall, `[AppPanels] paroi inconnue : {spot.Wall}`)
	local center = wall.Origin + wall.Normal * INSET + wall.Along * spot.At + Vector3.new(0, spot.Y, 0)
	return Common.Facing(center, wall.Normal)
end

local SURFACE = Color3.fromHex(Branding.PartnerApp.Surface)
local ACCENT = Color3.fromHex(Branding.PartnerApp.Accent):Lerp(Color3.new(1, 1, 1), 0.2)
local BEZEL = Color3.fromRGB(14, 14, 18)

local function place(parent: Instance, spot: Spot)
	local cf = AppPanels.FrameOf(spot)
	local def = Tower.Worlds[spot.World]
	-- Cadre (derrière la dalle, côté paroi) et liseré violet sous la fenêtre
	Build.Decor({
		Name = "Bezel",
		Size = Vector3.new(spot.Width + 1.2, spot.Height + 1.2, 0.3),
		CFrame = cf * CFrame.new(0, 0, (THICK + 0.3) / 2),
		Color = BEZEL,
		Material = Enum.Material.SmoothPlastic,
		CastShadow = false,
		Parent = parent,
	})
	Build.Neon({
		Name = "AccentBar",
		Size = Vector3.new(spot.Width * 0.6, 0.35, 0.35),
		CFrame = cf * CFrame.new(0, -spot.Height / 2 - 1.1, 0),
		Color = ACCENT,
		Transparency = 0.15,
		Parent = parent,
	})
	local panel = Build.Decor({
		Name = "AppPanel",
		Size = Vector3.new(spot.Width, spot.Height, THICK),
		CFrame = cf,
		Color = SURFACE,
		Material = Enum.Material.SmoothPlastic,
		CastShadow = false,
		Tags = { "AppPanel" },
		Parent = parent,
	})
	panel:SetAttribute("World", spot.World)
	panel:SetAttribute("Page", def.AppSection)
	panel:SetAttribute("Kind", spot.Kind)
end

-- Pose toutes les fenêtres (après la construction des mondes : World{n} doit exister).
function AppPanels.Build(tower: Folder)
	for _, spot in AppPanels.Spots do
		local kinds = AppPages.Kinds[spot.World]
		assert(
			kinds and table.find(kinds, spot.Kind),
			`[AppPanels] {spot.Kind} n'est pas une page du monde {spot.World}`
		)
		local world = tower:FindFirstChild(`World{spot.World}`)
		assert(world, `[AppPanels] World{spot.World} introuvable`)
		local folder = world:FindFirstChild("AppPanels") or Build.Folder("AppPanels", world)
		place(folder, spot)
	end
end

return table.freeze(AppPanels)
