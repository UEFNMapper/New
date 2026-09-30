--!strict
--[[
	TowerBuilder (version provisoire) : construit une tour minimale qui respecte le contrat
	(voir Config/Tower.luau) pour faire tourner les services. Remplacé par la vraie tour.
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Workspace = game:GetService("Workspace")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Tower = require(Shared.Config.Tower)
local Build = require(script.Parent.Build)

local TowerBuilder = {}

local function prompt(parent: BasePart, action: string, text: string): ProximityPrompt
	return Build.Prompt(parent, text, "", action, 12)
end

function TowerBuilder.Build(): Folder
	local existing = Workspace:FindFirstChild("Tower")
	if existing then
		existing:Destroy()
	end
	local tower = Instance.new("Folder")
	tower.Name = "Tower"

	local lobby = Build.Model("Lobby", tower)
	Build.Part({ Name = "Floor", Size = Vector3.new(120, 2, 120), CFrame = CFrame.new(0, -1, 0), Parent = lobby })
	local spawn = Instance.new("SpawnLocation")
	spawn.Name = "LobbySpawn"
	spawn.Size = Vector3.new(12, 0.4, 12)
	spawn.CFrame = CFrame.new(0, 0.2, 30)
	spawn.Anchored = true
	spawn.Neutral = true
	spawn.Duration = 0
	spawn.Parent = lobby
	Build.Part({
		Name = "AppScreen",
		Size = Vector3.new(60, 34, 1),
		CFrame = CFrame.lookAt(Vector3.new(0, 25, -40), Vector3.new(0, 25, 0)),
		Tags = { "AppScreen" },
		Parent = lobby,
	})
	for index, board in { "Wins", "BestTime", "Stage" } do
		local part = Build.Part({
			Name = board,
			Size = Vector3.new(20, 14, 1),
			CFrame = CFrame.lookAt(Vector3.new(-40 + index * 20, 10, -30), Vector3.new(-40 + index * 20, 10, 0)),
			Tags = { "LeaderboardScreen" },
			Parent = lobby,
		})
		part:SetAttribute("Board", board)
	end
	Build.Part({
		Name = "Title",
		Size = Vector3.new(40, 10, 0.2),
		CFrame = CFrame.new(0, 50, -40),
		Tags = { "TitleHologram" },
		Parent = lobby,
	})
	for index, action in { "Shop", "Arcade", "Daily" } do
		local stand = Build.Part({
			Name = `{action}Terminal`,
			Size = Vector3.new(4, 5, 3),
			CFrame = CFrame.new(-30 + index * 15, 2.5, 10),
			Parent = lobby,
		})
		prompt(stand, action, action)
	end
	Build.Part({
		Name = "AngaSpot",
		Size = Vector3.one,
		CFrame = CFrame.new(10, 3, 20),
		Transparency = 1,
		CanCollide = false,
		Parent = lobby,
	})

	local checkpoints = Build.Folder("Checkpoints", tower)
	for stage = 0, Tower.TOTAL_STAGES do
		local pad = Build.Part({
			Name = `Checkpoint{stage}`,
			Size = Vector3.new(12, 1, 12),
			CFrame = CFrame.new(0, stage * 6, -60 - stage * 14),
			Tags = { "Checkpoint" },
			Parent = checkpoints,
		})
		pad:SetAttribute("Stage", stage)
	end
	for world = 1, Tower.WORLD_COUNT do
		local model = Build.Model(`World{world}`, tower)
		model:SetAttribute("World", world)
		local stage = Tower.TerminalStage(world)
		local terminal = Build.Part({
			Name = "Terminal",
			Size = Vector3.new(4, 5, 3),
			CFrame = CFrame.new(8, stage * 6 + 3, -60 - stage * 14),
			Tags = { "MinigameTerminal" },
			Parent = model,
		})
		terminal:SetAttribute("World", world)
		prompt(terminal, "Minigame", "Antivirus"):SetAttribute("World", world)
		local gate = Build.Part({
			Name = "Gate",
			Size = Vector3.new(14, 12, 1),
			CFrame = CFrame.new(0, stage * 6 + 6, -67 - stage * 14),
			CanCollide = false,
			Tags = { "WorldGate" },
			Parent = model,
		})
		gate:SetAttribute("World", world)
		local coin = Build.Part({
			Name = "Coin",
			Size = Vector3.one * 2,
			CFrame = CFrame.new(-4, stage * 6 + 3, -60 - stage * 14),
			CanCollide = false,
			Tags = { "Coin" },
			Parent = model,
		})
		coin:SetAttribute("CoinId", `S{stage}C1`)
	end
	local last = Tower.TOTAL_STAGES + 1
	Build.Part({
		Name = "Finish",
		Size = Vector3.new(12, 1, 12),
		CFrame = CFrame.new(0, last * 6, -60 - last * 14),
		Tags = { "Finish" },
		Parent = tower,
	})
	tower.Parent = Workspace
	return tower
end

return TowerBuilder
