--!nonstrict
-- Pluie de météores : des œufs tombent dans le cratère (achetables par tous,
-- premier arrivé premier servi) et sur l'île de chaque joueur (météore perso,
-- tiré avec sa chance personnelle).

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Workspace = game:GetService("Workspace")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Kaijus = require(Shared.Config.Kaijus)
local Rarities = require(Shared.Config.Rarities)
local Economy = require(Shared.Config.Economy)
local Layout = require(Shared.Config.Layout)
local Roll = require(Shared.Logic.Roll)
local Format = require(Shared.Logic.Format)

local Registry = require(script.Parent.Registry)
local DataService = require(script.Parent.DataService)
local Router = require(script.Parent.Router)
local Notify = require(script.Parent.Notify)

local MeteorService = {}

local FALL_TIME = 2.6 -- secondes entre l'apparition et l'impact

local folder: Folder
local pads: { BasePart } = {}
local padUsed: { [number]: string } = {}
local meteors: { [string]: BasePart } = {}
local nextId = 0
local serverLuck = 1
local serverLuckUntil = 0
local personalNext: { [Player]: number } = {}

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

local function spawnMeteor(position: Vector3, rarity: string, price: number, owner: Player?, pad: number?, lifetime: number): BasePart
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
	p.Parent = folder
	meteors[id] = p
	local r = Rarities.Get(rarity)
	if r.Announce and not owner then
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
	if pad > 0 and padUsed[pad] == id then
		padUsed[pad] = nil
	end
	m:Destroy()
end

local function craterStep()
	local free = {}
	for i = 1, #pads do
		if not padUsed[i] then
			table.insert(free, i)
		end
	end
	if #free == 0 then
		return
	end
	local pad = free[math.random(1, #free)]
	local rarity = Roll.Rarity(MeteorService.CraterLuck())
	local pos = pads[pad].Position + Vector3.new(0, 1.2, 0)
	local m = spawnMeteor(pos, rarity, MeteorService.EggPrice(rarity), nil, pad, Economy.MeteorLifetime)
	padUsed[pad] = m.Name
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
	local luck = Registry.KaijuService.PersonalLuck(player)
	local rarity = Roll.Rarity(luck)
	local price = math.floor(MeteorService.EggPrice(rarity) * 0.8)
	local pos = (plot.CFrame * CFrame.new(Layout.PersonalPad.X, 1.2, Layout.PersonalPad.Z)).Position
	spawnMeteor(pos, rarity, price, player, nil, Economy.PersonalMeteorLifetime)
	Notify.Fx(player, "PersonalMeteor", { Rarity = rarity })
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
	local character = player.Character
	local root = character and character:FindFirstChild("HumanoidRootPart") :: BasePart?
	if not root or (root.Position - m.Position).Magnitude > 22 then
		return { ok = false, msg = "Get closer!" }
	end
	if not Registry.KaijuService.FreeNest(player) then
		return { ok = false, msg = "Your nests are full! Sell or unlock more." }
	end
	local price = m:GetAttribute("Price") or 0
	local isFree = data.Stats.EggsBought == 0 and Rarities.Get(m:GetAttribute("Rarity") or "Common").Order <= Economy.FreeFirstEggMaxOrder
	if not isFree and not DataService.Spend(player, "Cash", price) then
		return { ok = false, msg = "Need " .. Format.Cash(price) }
	end
	local rarity = m:GetAttribute("Rarity") :: string
	local from = m.Position
	removeMeteor(id)
	Notify.FxAll("MeteorBought", { Id = id, Buyer = player.UserId, Rarity = rarity, From = from })
	-- l'œuf s'envole vers la base : il arrive après l'animation
	task.delay(1.2, function()
		if player.Parent == Players then
			local rec = Registry.KaijuService.AddEgg(player, rarity)
			if not rec then
				Registry.KaijuService.GiveEgg(player, rarity, "Meteor")
			end
		end
	end)
	Registry.RewardService.Track(player, "EggsBought", 1)
	local r = Rarities.Get(rarity)
	if r.Order >= 4 then
		Notify.FeedExcept(player, ("%s grabbed the %s egg!"):format(player.DisplayName, string.upper(r.Name)), "Rare", r.Color)
	end
	return { ok = true, free = isFree }
end

function MeteorService.Init()
	folder = Workspace:WaitForChild("Meteors") :: Folder
	Router.On("BuyMeteor", buy, 4)

	Players.PlayerRemoving:Connect(function(player)
		personalNext[player] = nil
		for id, m in meteors do
			if m:GetAttribute("Owner") == player.UserId then
				removeMeteor(id)
			end
		end
	end)
end

function MeteorService.SetPads(list: { BasePart })
	pads = list
end

function MeteorService.Start()
	-- Pluie du cratère
	task.spawn(function()
		local timer = 3
		while true do
			task.wait(0.5)
			local event = Registry.EventService.Current()
			local rate = if event then event.MeteorRate else 1
			if rate > 0 then
				timer -= 0.5 * rate
			end
			if timer <= 0 then
				timer = Economy.MeteorInterval * (0.8 + math.random() * 0.4)
				craterStep()
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
		end
	end)

	-- Météores personnels
	task.spawn(function()
		while true do
			task.wait(1)
			local t = os.clock()
			for _, player in Players:GetPlayers() do
				if DataService.Get(player) then
					if not personalNext[player] then
						personalNext[player] = t + 40
					elseif t >= personalNext[player] then
						personalNext[player] = t + Economy.PersonalMeteorInterval
						personalStep(player)
					end
				end
			end
		end
	end)
end

return MeteorService
