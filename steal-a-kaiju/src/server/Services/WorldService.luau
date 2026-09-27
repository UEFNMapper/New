--!nonstrict
-- Mondes : déblocage (niveau + évolution + péage), voyage par portail ou depuis
-- la carte du monde, retour à la maison, et suivi du monde où se trouve chaque
-- joueur (les météores d'un monde ne tombent que s'il y a quelqu'un).

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Worlds = require(Shared.Config.Worlds)
local Levels = require(Shared.Config.Levels)
local Format = require(Shared.Logic.Format)

local Registry = require(script.Parent.Registry)
local DataService = require(script.Parent.DataService)
local Router = require(script.Parent.Router)
local Notify = require(script.Parent.Notify)

local WorldService = {}

local worldOf: { [Player]: string } = {} -- "Island" | "Crater" | id d'un monde
local lastTravel: { [Player]: number } = {}

local function setWhere(player: Player, where: string)
	if worldOf[player] ~= where then
		worldOf[player] = where
		player:SetAttribute("World", where)
	end
end

local function rootOf(player: Player): BasePart?
	local character = player.Character
	return character and character:FindFirstChild("HumanoidRootPart") :: BasePart?
end

-- Nombre de joueurs présents dans un monde.
function WorldService.CountIn(id: string): number
	local n = 0
	for _, w in worldOf do
		if w == id then
			n += 1
		end
	end
	return n
end

function WorldService.Where(player: Player): string
	return worldOf[player] or "Island"
end

function WorldService.IsUnlocked(player: Player, id: string): boolean
	local data = DataService.Get(player)
	return data ~= nil and data.Worlds[id] == true
end

-- Un joueur peut-il se téléporter ? (pas pendant un vol ni une partie de Rampage)
local function canTeleport(player: Player, leavingHome: boolean?): (boolean, string?)
	if Registry.StealService.IsCarrying(player) then
		return false, "Drop the kaiju first!"
	end
	-- une vague en cours : on défend son île avant de partir (sinon le réacteur est pillé)
	if leavingHome and Registry.SiegeService.IsActive(player) then
		return false, "Defend your island first!"
	end
	local rampage = Registry.RampageService
	if rampage and rampage.IsActive and rampage.IsActive(player) then
		return false, "Finish your Rampage first!"
	end
	if (lastTravel[player] or 0) > os.clock() then
		return false, nil
	end
	return true, nil
end

local function teleport(player: Player, cf: CFrame)
	local character = player.Character
	if character then
		lastTravel[player] = os.clock() + 1.5
		character:PivotTo(cf)
	end
end

function WorldService.TravelTo(player: Player, id: string): (boolean, string?)
	local world = Worlds.ById[id]
	if not world then
		return false, nil
	end
	if not WorldService.IsUnlocked(player, id) then
		return false, "Unlock this world first!"
	end
	local ok, msg = canTeleport(player, true)
	if not ok then
		return false, msg
	end
	local cf = if id == Worlds.Default then CFrame.lookAt(Vector3.new(0, 4, 52), Vector3.new(0, 4, 0)) else Worlds.SpawnPoint(id)
	teleport(player, cf)
	setWhere(player, id)
	Notify.Fx(player, "Travel", { World = id })
	return true, nil
end

function WorldService.GoHome(player: Player): (boolean, string?)
	local ok, msg = canTeleport(player)
	if not ok then
		return false, msg
	end
	lastTravel[player] = os.clock() + 1.5
	Registry.PlotService.SpawnAt(player)
	setWhere(player, "Island")
	Notify.Fx(player, "Travel", { World = "Island" })
	return true, nil
end

local function unlock(player: Player, payload: any): Router.Result
	local id = Router.String(payload.Id)
	local data = DataService.Get(player)
	local world = id and Worlds.ById[id]
	if not data or not world then
		return { ok = false }
	end
	if data.Worlds[world.Id] then
		return { ok = false, msg = "Already unlocked!" }
	end
	if data.Level < world.Level then
		return { ok = false, msg = ("Reach LEVEL %d first!"):format(world.Level) }
	end
	if data.Rebirths < world.Rebirths then
		return { ok = false, msg = ("Reach EVOLUTION %d first!"):format(world.Rebirths) }
	end
	if not DataService.Spend(player, "Cash", world.Toll) then
		return { ok = false, msg = "Need " .. Format.Cash(world.Toll) }
	end
	data.Worlds[world.Id] = true
	data.Stats.Worlds += 1
	DataService.Replicate(player, "Worlds", "Stats")
	Registry.LevelService.AddXp(player, Levels.Xp.WorldUnlock * world.Order, "World")
	Notify.Fx(player, "WorldUnlocked", { World = world.Id })
	Notify.FeedExcept(player, ("🌍 %s opened %s!"):format(player.DisplayName, string.upper(world.Name)), "Info", world.Palette.Glow)
	return { ok = true }
end

local function travel(player: Player, payload: any): Router.Result
	local id = Router.String(payload.Id)
	if not id then
		return { ok = false }
	end
	local ok, msg = WorldService.TravelTo(player, id)
	return { ok = ok, msg = msg }
end

local function home(player: Player): Router.Result
	local ok, msg = WorldService.GoHome(player)
	return { ok = ok, msg = msg }
end

-- Portails physiques : ceux du cratère mènent aux mondes, ceux des arènes à la maison.
local function onPortal(player: Player, id: string)
	if (lastTravel[player] or 0) > os.clock() then
		return
	end
	if id == "Home" then
		local ok, msg = WorldService.GoHome(player)
		if not ok and msg then
			Notify.Toast(player, msg, "Bad")
		end
		return
	end
	if WorldService.IsUnlocked(player, id) then
		local ok, msg = WorldService.TravelTo(player, id)
		if not ok and msg then
			Notify.Toast(player, msg, "Bad")
		end
	else
		-- verrouillé : le client ouvre la carte du monde sur ce monde
		lastTravel[player] = os.clock() + 2
		Notify.Fx(player, "PortalLocked", { World = id })
	end
end

function WorldService.SetWorlds(worlds: { [string]: any })
	for id, info in worlds do
		for _, entry in { { info.HubPortal, id }, { info.HomePortal, "Home" } } do
			local gate: BasePart? = entry[1]
			if gate then
				gate.Touched:Connect(function(hit)
					local player = Players:GetPlayerFromCharacter(hit.Parent)
					if player and DataService.Get(player) then
						onPortal(player, entry[2])
					end
				end)
			end
		end
	end
end

function WorldService.Init()
	Router.On("UnlockWorld", unlock, 2)
	Router.On("Travel", travel, 2)
	Router.On("Home", home, 2)

	Players.PlayerRemoving:Connect(function(player)
		worldOf[player] = nil
		lastTravel[player] = nil
	end)

	-- Où est chaque joueur ? (arène d'un monde, cratère central, ou ailleurs)
	task.spawn(function()
		while true do
			task.wait(0.5)
			-- une erreur ne doit jamais arrêter la boucle pour tout le serveur
			local ok, err = pcall(function()
				for _, player in Players:GetPlayers() do
					local root = rootOf(player)
					if root then
						local at = Worlds.At(root.Position)
						setWhere(player, at or (if Vector3.new(root.Position.X, 0, root.Position.Z).Magnitude < 130 then Worlds.Default else "Island"))
					end
				end
			end)
			if not ok then
				warn("[WorldService] boucle : " .. tostring(err))
			end
		end
	end)
end

return WorldService
