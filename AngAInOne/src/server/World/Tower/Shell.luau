--!strict
--[[
	Shell : la coque de la tour PC (Workspace.Tower.Shell, Model persistant) : parois, vitre latérale
	(+X) et son cadre, rails RGB à chaque plancher de monde, façade (bandes, logo, bouton, 3 ventilateurs
	d'admission, porte d'entrée du parcours), ventilateurs d'extraction sur le dessus, plinthe.
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Tower = require(Shared.Config.Tower)
local Build = require(script.Parent.Parent.Build)
local Props = require(script.Parent.Parent.Props)
local Common = require(script.Parent.Common)

local Shell = {}

local INNER, WALL, TOP = Common.INNER, Common.WALL, Common.TOP
local UP = Common.UP
local C = Common.C
local Box, Rod = Props.Box, Props.Rod
local METAL = Enum.Material.Metal
local NEON = Enum.Material.Neon
local hex = Common.Hex
local corner, worldBase = Common.Corner, Common.WorldBase

function Shell.Build(tower: Folder)
	local shell = Build.Model("Shell", tower)
	shell.ModelStreamingMode = Enum.ModelStreamingMode.Persistent
	local outer = INNER + WALL
	local h = TOP
	local steel = Color3.fromRGB(34, 38, 50)
	local function wall(name: string, size: Vector3, position: Vector3, color: Color3?, material: Enum.Material?)
		return Build.Part({
			Name = name,
			Size = size,
			CFrame = CFrame.new(position),
			Color = color or steel,
			Material = material or METAL,
			CastShadow = false,
			Parent = shell,
		})
	end
	local zc = -(INNER + WALL / 2)
	local doorX0, doorX1 = Common.EntranceDoor()
	local doorTop = 8
	-- Façade avant (-Z), percée de la porte d'entrée
	wall("Front", Vector3.new(outer - doorX1, h, WALL), Vector3.new((doorX1 + outer) / 2, h / 2, zc))
	wall("Front", Vector3.new(doorX0 + outer, h, WALL), Vector3.new((-outer + doorX0) / 2, h / 2, zc))
	wall(
		"Front",
		Vector3.new(doorX1 - doorX0, h - doorTop, WALL),
		Vector3.new((doorX0 + doorX1) / 2, (h + doorTop) / 2, zc)
	)
	wall("Back", Vector3.new(outer * 2, h, WALL), Vector3.new(0, h / 2, INNER + WALL / 2))
	wall("Left", Vector3.new(WALL, h, INNER * 2), Vector3.new(-(INNER + WALL / 2), h / 2, 0))
	wall("Top", Vector3.new(outer * 2, 6, outer * 2), Vector3.new(0, h + 3, 0))
	-- Vitre latérale (+X) et son cadre alu
	local glass = wall(
		"SideGlass",
		Vector3.new(2, h, INNER * 2),
		Vector3.new(INNER + 1, h / 2, 0),
		Color3.fromRGB(190, 215, 240),
		Enum.Material.Glass
	)
	glass.Transparency = 0.72
	for _, z in { -(INNER - 2), INNER - 2 } do
		wall("GlassFrame", Vector3.new(WALL, h, 4), Vector3.new(INNER + WALL / 2, h / 2, z), C.Aluminum)
	end
	wall("GlassFrame", Vector3.new(WALL, 6, outer * 2), Vector3.new(INNER + WALL / 2, 3, 0), C.Aluminum)
	-- Rails horizontaux à chaque plancher de monde (vus à travers la vitre), liseré RGB
	for w = 2, Tower.WORLD_COUNT do
		local y = worldBase(w)
		local rail =
			Box(shell, "GlassRail", Vector3.new(3, 3, INNER * 2), CFrame.new(INNER + 2.5, y - 1, 0), C.Aluminum, METAL)
		rail.CastShadow = false
		Build.Neon({
			Name = "RgbRail",
			Size = Vector3.new(0.4, 0.8, INNER * 2),
			CFrame = CFrame.new(INNER + 4.2, y - 1, 0),
			Color = hex(Tower.Worlds[w].Primary),
			Tags = { "RgbStrip" },
			Parent = shell,
		})
	end
	-- Façade : bandes lumineuses verticales, logo, bouton d'alimentation, 3 ventilateurs d'admission
	local face = -(outer + 0.2)
	for _, x in { -outer + 8, outer - 8 } do
		Build.Neon({
			Name = "FrontStrip",
			Size = Vector3.new(1.2, h - 30, 0.4),
			CFrame = CFrame.new(x, h / 2 + 10, face),
			Color = C.Violet,
			Tags = { "RgbStrip" },
			Parent = shell,
		})
	end
	for i, y in { 190, 360, 530 } do
		local fanCf = CFrame.fromMatrix(Vector3.new(0, y, face + 0.2), -Vector3.zAxis, UP)
		Props.Fan(shell, fanCf, 110, hex(Tower.Worlds[i * 2].Primary), 7, { Speed = 1.2, Lite = true, Rgb = true })
	end
	local logo = Box(
		shell,
		"FrontLogo",
		Vector3.new(120, 26, 0.4),
		CFrame.new(0, h - 60, face) * CFrame.Angles(0, math.pi, 0),
		C.Bg
	)
	logo.Transparency = 1
	Props.Sign(logo, "ANGA TOWER", "Deathrun dans le PC", C.White, C.Cyan, Enum.NormalId.Back)
	Rod(
		shell,
		"PowerButton",
		CFrame.fromMatrix(Vector3.new(0, h - 22, face - 0.3), -Vector3.zAxis, UP),
		1.2,
		14,
		C.MetalDark
	)
	Props.Ring(
		shell,
		"PowerRing",
		CFrame.fromMatrix(Vector3.new(0, h - 22, face - 0.9), -Vector3.zAxis, UP),
		7.4,
		0.8,
		0.4,
		16,
		C.Cyan,
		NEON
	)
	-- Dessus : deux ventilateurs d'extraction
	for _, x in { -62, 62 } do
		Props.Fan(shell, CFrame.fromMatrix(Vector3.new(x, h + 6, 0), UP, Vector3.zAxis), 100, C.Violet, 7, {
			Speed = 1.5,
			Lite = true,
		})
	end
	-- Socle (plinthe) autour du pied de la tour
	for i = 0, 3 do
		local look = (corner(i + 1) - corner(i)).Unit
		local out = -look:Cross(UP)
		Box(
			shell,
			"Plinth",
			Vector3.new(outer * 2 + 4, 4, 3),
			CFrame.fromMatrix(out * (outer + 1.5) + Vector3.new(0, 2, 0), look, UP),
			C.Black,
			METAL
		)
	end
end

return table.freeze(Shell)
