--!nonstrict
-- Îles des joueurs : attribution, apparition, bouclier (verrou), collecteur,
-- nids débloqués, protection des nouveaux joueurs.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Workspace = game:GetService("Workspace")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Layout = require(Shared.Config.Layout)
local Economy = require(Shared.Config.Economy)
local Levels = require(Shared.Config.Levels)

local Registry = require(script.Parent.Registry)
local DataService = require(script.Parent.DataService)
local Router = require(script.Parent.Router)
local Notify = require(script.Parent.Notify)

local MapBuilder = require(script.Parent.Parent.World.MapBuilder)

local PlotService = {}

local plots: { MapBuilder.PlotInfo } = {}
local ownerOf: { [number]: Player } = {} -- index d'île -> joueur
local plotOf: { [Player]: MapBuilder.PlotInfo } = {}

local function now(): number
	return Workspace:GetServerTimeNow()
end

function PlotService.SetMap(map: MapBuilder.MapInfo)
	plots = map.Plots
end

function PlotService.Get(player: Player): MapBuilder.PlotInfo?
	return plotOf[player]
end

function PlotService.Owner(index: number): Player?
	return ownerOf[index]
end

function PlotService.All(): { MapBuilder.PlotInfo }
	return plots
end

-- Position monde d'un nid.
function PlotService.NestCFrame(plot: MapBuilder.PlotInfo, slot: number): CFrame
	local local_ = Layout.Nests[slot]
	return plot.CFrame * CFrame.new(local_.X, 0.5, local_.Z)
end

function PlotService.UnlockedNests(player: Player): number
	local data = DataService.Get(player)
	if not data then
		return 0
	end
	local extra = if Registry.ShopService.HasPass(player, "ExtraNests") then Economy.PassBonusNests else 0
	local base = math.max(data.Nests, Levels.NestsFor(data.Level or 1))
	return math.min(#Layout.Nests, base + extra)
end

function PlotService.RefreshNests(player: Player)
	local plot = plotOf[player]
	if plot then
		plot.Model:SetAttribute("Nests", PlotService.UnlockedNests(player))
	end
end

function PlotService.IsShielded(plot: MapBuilder.PlotInfo): boolean
	local t = now()
	return (plot.Model:GetAttribute("ShieldUntil") or 0) > t or (plot.Model:GetAttribute("ProtectedUntil") or 0) > t
end

function PlotService.ShieldDuration(player: Player): number
	local data = DataService.Get(player)
	local level = if data then data.Upgrades.Shield else 0
	local duration = Economy.ShieldBase + level * Economy.UpgradesById.Shield.PerLevel
	if Registry.ShopService.HasPass(player, "MegaShield") then
		duration *= 2
	end
	return duration
end

local function lock(player: Player): Router.Result
	local plot = plotOf[player]
	if not plot then
		return { ok = false }
	end
	local t = now()
	local model = plot.Model
	if (model:GetAttribute("ShieldUntil") or 0) > t then
		return { ok = false, msg = "Shield already active!" }
	end
	local cooldown = model:GetAttribute("ShieldCooldown") or 0
	if cooldown > t then
		return { ok = false, msg = ("Shield recharging (%ds)"):format(math.ceil(cooldown - t)) }
	end
	local duration = PlotService.ShieldDuration(player)
	model:SetAttribute("ShieldUntil", t + duration)
	model:SetAttribute("ShieldCooldown", t + duration + Economy.ShieldCooldown)
	Notify.FxAll("ShieldUp", { Plot = plot.Index })
	Registry.RewardService.Track(player, "Locks", 1)
	Registry.TutorialService.Notify(player, "Lock")
	return { ok = true }
end

function PlotService.ForceShield(player: Player, seconds: number): boolean
	local plot = plotOf[player]
	if not plot then
		return false
	end
	local t = now()
	local current = math.max(t, plot.Model:GetAttribute("ShieldUntil") or 0)
	plot.Model:SetAttribute("ShieldUntil", current + seconds)
	plot.Model:SetAttribute("ShieldCooldown", current + seconds)
	Notify.FxAll("ShieldUp", { Plot = plot.Index })
	return true
end

-- Téléporte le personnage sur son île.
function PlotService.SpawnAt(player: Player)
	local plot = plotOf[player]
	local character = player.Character
	if not plot or not character then
		return
	end
	local spawnCf = plot.CFrame * CFrame.new(Layout.Spawn)
	character:PivotTo(CFrame.lookAt(spawnCf.Position, spawnCf.Position + plot.CFrame.LookVector))
end

local function assign(player: Player)
	for _, plot in plots do
		if not ownerOf[plot.Index] then
			ownerOf[plot.Index] = player
			plotOf[player] = plot
			local model = plot.Model
			model:SetAttribute("OwnerId", player.UserId)
			model:SetAttribute("OwnerName", player.DisplayName)
			model:SetAttribute("ShieldUntil", 0)
			model:SetAttribute("ShieldCooldown", 0)
			model:SetAttribute("ProtectedUntil", now() + Economy.NewPlayerProtection)
			model:SetAttribute("Stored", 0)
			player:SetAttribute("Plot", plot.Index)
			local title = plot.Sign:FindFirstChild("Title") :: TextLabel?
			if title then
				title.Text = string.upper(player.DisplayName) .. "'S ISLAND"
				title.TextColor3 = plot.Color
			end
			PlotService.RefreshNests(player)
			return plot
		end
	end
	return nil
end

local function release(player: Player)
	local plot = plotOf[player]
	if not plot then
		return
	end
	plotOf[player] = nil
	ownerOf[plot.Index] = nil
	local model = plot.Model
	for _, attr in { "OwnerId", "OwnerName", "ShieldUntil", "ShieldCooldown", "ProtectedUntil", "Nests", "Stored" } do
		model:SetAttribute(attr, nil)
	end
	local title = plot.Sign:FindFirstChild("Title") :: TextLabel?
	if title then
		title.Text = "EMPTY ISLAND"
		title.TextColor3 = Color3.fromRGB(255, 246, 222)
	end
	local amount = plot.CollectorGui:FindFirstChild("Amount") :: TextLabel?
	if amount then
		amount.Text = "$0"
	end
end

-- Pousse hors de l'île les intrus quand le bouclier est actif.
local function enforceShields()
	local t = now()
	for _, plot in plots do
		local owner = ownerOf[plot.Index]
		if owner and PlotService.IsShielded(plot) then
			local shieldActive = (plot.Model:GetAttribute("ShieldUntil") or 0) > t
			for _, other in Players:GetPlayers() do
				if other ~= owner then
					local character = other.Character
					local root = character and character:FindFirstChild("HumanoidRootPart") :: BasePart?
					if root and Layout.InPlot(plot.CFrame, root.Position, 1) then
						-- Hors de l'île, devant la porte
						local out = plot.CFrame * CFrame.new(math.clamp(plot.CFrame:PointToObjectSpace(root.Position).X, -8, 8), 3, -Layout.PlotDepth / 2 - 12)
						character:PivotTo(CFrame.lookAt(out.Position, out.Position + plot.CFrame.LookVector))
						Notify.Fx(other, "ShieldZap", { Plot = plot.Index, Protected = not shieldActive })
					end
				end
			end
		end
	end
end

function PlotService.Init()
	Router.On("Lock", lock, 2)

	DataService.Loaded:Connect(function(player)
		local plot = assign(player)
		if not plot then
			player:Kick("This server is full, please join another one!")
			return
		end
		if player.Character then
			PlotService.SpawnAt(player)
		end
	end)

	Players.PlayerAdded:Connect(function(player)
		player.CharacterAdded:Connect(function()
			task.defer(function()
				if plotOf[player] then
					PlotService.SpawnAt(player)
				end
			end)
		end)
	end)

	Players.PlayerRemoving:Connect(release)

	-- Collecteur et bouton de verrouillage : trois façons de les activer, pour
	-- ne jamais dépendre d'un seul mécanisme de Roblox :
	--   1. contact (Touched), 2. proximité vérifiée par le serveur, 3. invite « E ».
	local debounce: { [Player]: number } = {}
	local function tryCollect(player: Player, plot: MapBuilder.PlotInfo)
		if ownerOf[plot.Index] == player and (debounce[player] or 0) < os.clock() then
			debounce[player] = os.clock() + 0.6
			Registry.KaijuService.Collect(player)
		end
	end
	local function tryLock(player: Player, plot: MapBuilder.PlotInfo)
		if ownerOf[plot.Index] == player and (debounce[player] or 0) < os.clock() then
			debounce[player] = os.clock() + 1
			local result = lock(player)
			if not result.ok and result.msg then
				Notify.Toast(player, result.msg, "Bad")
			end
		end
	end
	local function prompt(parent: BasePart, action: string, object: string, color: string, onTrigger: (Player) -> ()): ProximityPrompt
		local p = Instance.new("ProximityPrompt")
		p.Style = Enum.ProximityPromptStyle.Custom
		p.ActionText = action
		p.ObjectText = object
		p.KeyboardKeyCode = Enum.KeyCode.E
		p.HoldDuration = 0
		p.MaxActivationDistance = 12
		p.RequiresLineOfSight = false
		p:SetAttribute("Color", color)
		p.Triggered:Connect(onTrigger)
		p.Parent = parent
		return p
	end
	for _, plot in plots do
		plot.Collector.CanTouch = true
		plot.Collector.Touched:Connect(function(hit)
			local player = Players:GetPlayerFromCharacter(hit.Parent)
			if player then
				tryCollect(player, plot)
			end
		end)
		prompt(plot.Collector, "COLLECT CASH", "Cash Reactor", "Radioactive", function(player)
			tryCollect(player, plot)
		end)
		plot.LockButton.CanTouch = true
		plot.LockButton.Touched:Connect(function(hit)
			local player = Players:GetPlayerFromCharacter(hit.Parent)
			if player then
				tryLock(player, plot)
			end
		end)
		prompt(plot.LockButton, "LOCK BASE", "Shield", "Red", function(player)
			tryLock(player, plot)
		end)
	end

	-- Proximité : le propriétaire debout sur le pad collecte automatiquement
	task.spawn(function()
		while true do
			task.wait(0.25)
			for _, plot in plots do
				local owner = ownerOf[plot.Index]
				local character = owner and owner.Character
				local root = character and character:FindFirstChild("HumanoidRootPart") :: BasePart?
				if owner and root then
					local pad = plot.Collector.Position
					local flat = Vector3.new(root.Position.X - pad.X, 0, root.Position.Z - pad.Z).Magnitude
					if flat <= 6.5 and math.abs(root.Position.Y - pad.Y) < 9 then
						tryCollect(owner, plot)
					end
				end
			end
		end
	end)

	task.spawn(function()
		while true do
			task.wait(0.2)
			enforceShields()
		end
	end)
end

return PlotService
