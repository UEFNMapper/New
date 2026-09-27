--!nonstrict
-- Pluie de météores : des œufs tombent dans le cratère (achetables par tous,
-- premier arrivé premier servi), dans les mondes où se trouvent des joueurs
-- (œufs propres à chaque monde) et sur l'île de chaque joueur (météore perso,
-- tiré dans le meilleur monde débloqué avec sa chance personnelle).

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Workspace = game:GetService("Workspace")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Kaijus = require(Shared.Config.Kaijus)
local Rarities = require(Shared.Config.Rarities)
local Economy = require(Shared.Config.Economy)
local Layout = require(Shared.Config.Layout)
local Worlds = require(Shared.Config.Worlds)
local Roll = require(Shared.Logic.Roll)
local Format = require(Shared.Logic.Format)

local Registry = require(script.Parent.Registry)
local DataService = require(script.Parent.DataService)
local Router = require(script.Parent.Router)
local Notify = require(script.Parent.Notify)

local MeteorService = {}

local FALL_TIME = 2.6 -- secondes entre l'apparition et l'impact

local folder: Folder
local pads: { [string]: { BasePart } } = {} -- monde -> plateformes
local padUsed: { [string]: { [number]: string } } = {} -- monde -> plateforme -> météore
local meteors: { [string]: BasePart } = {}
local nextId = 0
local serverLuck = 1
local serverLuckUntil = 0
local personalNext: { [Player]: number } = {}
local personalCount: { [Player]: number } = {}

local function now(): number
	return Workspace:GetServerTimeNow()
end

-- Prix d'un œuf d'une rareté : moyenne des espèces achetables.
local eggPrices: { [string]: number } = {}
for _, r in Rarities.List do
	local total, n = 0, 0
	local pool: { any } = Kaijus.ByRarity[r.Id] or {}
	for _, s in pool do
		if s.Price > 0 then
			total += s.Price
			n += 1
		end
	end
	if n > 0 then
		eggPrices[r.Id] = math.floor(total / n)
	end
end

function MeteorService.EggPrice(rarity: string): number
	return eggPrices[rarity] or 100
end

function MeteorService.CraterLuck(): number
	local luck = 1
	if serverLuckUntil > now() then
		luck *= serverLuck
	end
	local event = Registry.EventService.Current()
	if event then
		luck *= event.Luck
	end
	return luck
end

local function publishLuck()
	Workspace:SetAttribute("CraterLuck", MeteorService.CraterLuck())
	Workspace:SetAttribute("ServerLuck", if serverLuckUntil > now() then serverLuck else 1)
	Workspace:SetAttribute("ServerLuckUntil", serverLuckUntil)
end

function MeteorService.AddServerLuck(mult: number, seconds: number)
	local t = now()
	serverLuck = math.max(serverLuck, mult)
	serverLuckUntil = math.max(serverLuckUntil, t) + seconds
	publishLuck()
end

local function spawnMeteor(position: Vector3, rarity: string, price: number, owner: Player?, pad: number?, lifetime: number, world: string): BasePart
	nextId += 1
	local id = "M" .. nextId
	local p = Instance.new("Part")
	p.Name = id
	p.Anchored = true
	p.CanCollide = false
	p.CanQuery = false
	p.CanTouch = false
	p.Transparency = 1
	p.Size = Vector3.new(2, 2, 2)
	p.CFrame = CFrame.new(position)
	local t = now()
	p:SetAttribute("Id", id)
	p:SetAttribute("Rarity", rarity)
	p:SetAttribute("Price", price)
	p:SetAttribute("LandAt", t + FALL_TIME)
	p:SetAttribute("ExpireAt", t + FALL_TIME + lifetime)
	p:SetAttribute("Owner", if owner then owner.UserId else 0)
	p:SetAttribute("Pad", pad or 0)
	p:SetAttribute("World", world)
	p.Parent = folder
	meteors[id] = p
	local r = Rarities.Get(rarity)
	-- annonce serveur : dans les mondes, seulement les tout meilleurs œufs
	local announce = r.Announce and (world == Worlds.Default or r.Order >= 6)
	if announce and not owner then
		Notify.Feed(("%s %s METEOR INCOMING!"):format("☄️", string.upper(r.Name)), "Meteor", r.Color)
	end
	return p
end

local function removeMeteor(id: string)
	local m = meteors[id]
	if not m then
		return
	end
	meteors[id] = nil
	local pad = m:GetAttribute("Pad") or 0
	local used = padUsed[m:GetAttribute("World") or Worlds.Default]
	if pad > 0 and used and used[pad] == id then
		used[pad] = nil
	end
	m:Destroy()
end

-- Fait tomber un œuf sur une plateforme libre d'un monde.
local function worldStep(worldId: string)
	local list = pads[worldId]
	if not list then
		return
	end
	local used = padUsed[worldId]
	local free = {}
	for i = 1, #list do
		if not used[i] then
			table.insert(free, i)
		end
	end
	if #free == 0 then
		return
	end
	local pad = free[math.random(1, #free)]
	local rarity = Roll.Rarity(MeteorService.CraterLuck(), nil, worldId)
	local pos = list[pad].Position + Vector3.new(0, 1.2, 0)
	local m = spawnMeteor(pos, rarity, MeteorService.EggPrice(rarity), nil, pad, Economy.MeteorLifetime, worldId)
	used[pad] = m.Name
end

local function personalStep(player: Player)
	local plot = Registry.PlotService.Get(player)
	if not plot then
		return
	end
	-- Un seul météore perso à la fois
	for _, m in meteors do
		if m:GetAttribute("Owner") == player.UserId then
			return
		end
	end
	local data = DataService.Get(player)
	local world = Worlds.Best(if data then data.Worlds else {})
	local luck = Registry.KaijuService.PersonalLuck(player)
	personalCount[player] = (personalCount[player] or (if data then data.GoldenCount or 0 else 0)) + 1
	if data then
		data.GoldenCount = personalCount[player] -- le compteur du météore doré survit à une reconnexion
	end
	local golden = personalCount[player] % Economy.GoldenEvery == 0
	local rarity = if golden then Roll.GoldenRarity(luck, nil, world.Id) else Roll.Rarity(luck, nil, world.Id)
	local price = math.floor(MeteorService.EggPrice(rarity) * (if golden then Economy.GoldenPriceMult else 0.8))
	local pos = (plot.CFrame * CFrame.new(Layout.PersonalPad.X, 1.2, Layout.PersonalPad.Z)).Position
	local m = spawnMeteor(pos, rarity, price, player, nil, Economy.PersonalMeteorLifetime, world.Id)
	m:SetAttribute("Golden", golden)
	Notify.Fx(player, "PersonalMeteor", { Rarity = rarity, World = world.Id, Golden = golden })
end

local function buy(player: Player, payload: any): Router.Result
	local id = Router.String(payload.Id)
	local m = id and meteors[id]
	local data = DataService.Get(player)
	if not m or not data or not id then
		return { ok = false, msg = "Too late!" }
	end
	local t = now()
	if (m:GetAttribute("LandAt") or 0) > t then
		return { ok = false, msg = "Wait for it to land!" }
	end
	local owner = m:GetAttribute("Owner") or 0
	if owner ~= 0 and owner ~= player.UserId then
		return { ok = false, msg = "This meteor belongs to someone else" }
	end
	-- œufs d'un monde : seulement si ce monde est débloqué (anti-téléportation)
	local meteorWorld = m:GetAttribute("World") or Worlds.Default
	if owner == 0 and meteorWorld ~= Worlds.Default and not Registry.WorldService.IsUnlocked(player, meteorWorld) then
		return { ok = false, msg = "Unlock this world first!" }
	end
	local character = player.Character
	local root = character and character:FindFirstChild("HumanoidRootPart") :: BasePart?
	if not root or (root.Position - m.Position).Magnitude > 22 then
		return { ok = false, msg = "Get closer!" }
	end
	if not Registry.KaijuService.FreeNest(player) and not Registry.KaijuService.CanMakeRoom(player, m:GetAttribute("Rarity") or "Common") then
		return { ok = false, msg = "Your nests are full! Sell or unlock more." }
	end
	local price = m:GetAttribute("Price") or 0
	local isFree = data.Stats.EggsBought == 0 and Rarities.Get(m:GetAttribute("Rarity") or "Common").Order <= Economy.FreeFirstEggMaxOrder
	if not isFree and not DataService.Spend(player, "Cash", price) then
		return { ok = false, msg = "Need " .. Format.Cash(price) }
	end
	local rarity = m:GetAttribute("Rarity") :: string
	local world = m:GetAttribute("World") or Worlds.Default
	local from = m.Position
	removeMeteor(id)
	Notify.FxAll("MeteorBought", { Id = id, Buyer = player.UserId, Rarity = rarity, From = from })
	-- l'œuf est enregistré tout de suite (rien ne se perd si le joueur part ou
	-- évolue pendant l'animation) ; le client le fait voler jusqu'au nid
	local rec = Registry.KaijuService.AddEgg(player, rarity, nil, world)
	if not rec then
		Registry.KaijuService.GiveEgg(player, rarity, "Meteor", world)
	end
	Registry.RewardService.Track(player, "EggsBought", 1)
	Registry.TutorialService.Notify(player, "Meteor")
	return { ok = true, free = isFree }
end

function MeteorService.Init()
	folder = Workspace:WaitForChild("Meteors") :: Folder
	Router.On("BuyMeteor", buy, 4)

	Players.PlayerRemoving:Connect(function(player)
		personalNext[player] = nil
		personalCount[player] = nil
		for id, m in meteors do
			if m:GetAttribute("Owner") == player.UserId then
				removeMeteor(id)
			end
		end
	end)
end

-- Plateformes de chaque monde (le cratère inclus), fournies par la carte.
function MeteorService.SetWorlds(worlds: { [string]: { Pads: { BasePart } } })
	for id, info in worlds do
		pads[id] = info.Pads
		padUsed[id] = {}
	end
end

function MeteorService.Start()
	-- Pluie du cratère (toujours) et des mondes (quand quelqu'un s'y trouve)
	task.spawn(function()
		local timers: { [string]: number } = {}
		for _, w in Worlds.List do
			timers[w.Id] = 3
		end
		while true do
			task.wait(0.5)
			-- une erreur ne doit jamais arrêter la boucle pour tout le serveur
			local ok, err = pcall(function()
				local event = Registry.EventService.Current()
				local rate = if event then event.MeteorRate else 1
				for _, w in Worlds.List do
					local isCrater = w.Id == Worlds.Default
					local active = isCrater or Registry.WorldService.CountIn(w.Id) > 0
					if active and rate > 0 then
						timers[w.Id] -= 0.5 * rate
					end
					if timers[w.Id] <= 0 then
						local interval = if isCrater then Economy.MeteorInterval else Worlds.MeteorInterval
						timers[w.Id] = interval * (0.8 + math.random() * 0.4)
						worldStep(w.Id)
					end
					local attr = if isCrater then "NextMeteorIn" else "NextMeteorIn_" .. w.Id
					Workspace:SetAttribute(attr, if rate > 0 then timers[w.Id] / rate else -1)
				end
				-- expiration
				local t = now()
				for id, m in meteors do
					if (m:GetAttribute("ExpireAt") or 0) < t then
						Notify.FxAll("MeteorExpired", { Id = id })
						removeMeteor(id)
					end
				end
				publishLuck()
			end)
			if not ok then
				warn("[MeteorService] boucle : " .. tostring(err))
			end
		end
	end)

	-- Météores personnels
	task.spawn(function()
		while true do
			task.wait(1)
			-- une erreur ne doit jamais arrêter la boucle pour tout le serveur
			local ok, err = pcall(function()
				local t = os.clock()
				for _, player in Players:GetPlayers() do
					if DataService.Get(player) then
						if not personalNext[player] then
							personalNext[player] = t + 40
						elseif t >= personalNext[player] then
							personalNext[player] = t + Economy.PersonalMeteorInterval
							personalStep(player)
						end
						-- compte à rebours du prochain météore doré (affiché sur le HUD)
						local saved = DataService.Get(player)
						local done = personalCount[player] or (if saved then saved.GoldenCount or 0 else 0)
						local dropsLeft = Economy.GoldenEvery - (done % Economy.GoldenEvery) - 1
						local seconds = math.max(0, personalNext[player] - t) + dropsLeft * Economy.PersonalMeteorInterval
						player:SetAttribute("GoldenMeteorAt", Workspace:GetServerTimeNow() + seconds)
					end
				end
			end)
			if not ok then
				warn("[MeteorService] boucle : " .. tostring(err))
			end
		end
	end)
end

return MeteorService
