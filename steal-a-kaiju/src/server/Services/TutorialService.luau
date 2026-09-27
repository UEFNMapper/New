--!nonstrict
-- Missions d'introduction validées côté serveur + voleur d'entraînement (PNJ).
-- Les autres services signalent les événements via TutorialService.Notify.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Workspace = game:GetService("Workspace")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Tutorial = require(Shared.Config.Tutorial)
local Layout = require(Shared.Config.Layout)
local Theme = require(Shared.Config.Theme)

local Registry = require(script.Parent.Registry)
local DataService = require(script.Parent.DataService)
local Router = require(script.Parent.Router)
local Notify = require(script.Parent.Notify)

local TutorialService = {}

type Thief = {
	Player: Player,
	Model: Model,
	Root: BasePart,
	Uid: string,
	State: string, -- Walk | Flee | Gone
	Started: number,
}

local thieves: { [Player]: Thief } = {}

local function step(player: Player): number
	local data = DataService.Get(player)
	if not data then
		return 0
	end
	return math.max(1, data.Tutorial)
end

----------------------------------------------------------------------------
-- Voleur d'entraînement
----------------------------------------------------------------------------

local function buildThief(): (Model, BasePart)
	local model = Instance.new("Model")
	model.Name = "TrainingThief"
	local function part(name: string, size: Vector3, color: Color3, offset: CFrame, shape: Enum.PartType?): Part
		local p = Instance.new("Part")
		p.Name = name
		p.Size = size
		p.Color = color
		p.Material = Enum.Material.SmoothPlastic
		p.Anchored = true
		p.CanCollide = false
		p.CanQuery = false
		p.CanTouch = false
		if shape then
			p.Shape = shape
		end
		p:SetAttribute("Offset", offset)
		p.Parent = model
		return p
	end
	local ink = Theme.Colors.Ink
	local root = part("HumanoidRootPart", Vector3.new(2, 2, 1), ink, CFrame.new(0, 0, 0))
	root.Transparency = 1
	part("Torso", Vector3.new(2, 2, 1), ink, CFrame.new(0, 0, 0))
	part("Stripe", Vector3.new(2.05, 0.4, 1.05), Color3.fromRGB(255, 255, 255), CFrame.new(0, 0.5, 0))
	part("Stripe2", Vector3.new(2.05, 0.4, 1.05), Color3.fromRGB(255, 255, 255), CFrame.new(0, -0.4, 0))
	part("Head", Vector3.new(1.3, 1.3, 1.3), Color3.fromRGB(255, 205, 160), CFrame.new(0, 1.65, 0), Enum.PartType.Ball)
	part("Mask", Vector3.new(1.4, 0.45, 1.4), ink, CFrame.new(0, 1.75, 0))
	part("Hat", Vector3.new(1.5, 0.35, 1.5), ink, CFrame.new(0, 2.3, 0), Enum.PartType.Cylinder)
	part("Bag", Vector3.new(1.4, 1.4, 1), Color3.fromRGB(190, 160, 120), CFrame.new(0, 0.2, 0.9), Enum.PartType.Ball)
	part("LegL", Vector3.new(0.8, 2, 0.8), ink, CFrame.new(-0.5, -2, 0))
	part("LegR", Vector3.new(0.8, 2, 0.8), ink, CFrame.new(0.5, -2, 0))
	part("ArmL", Vector3.new(0.7, 1.8, 0.7), ink, CFrame.new(-1.4, 0, 0))
	part("ArmR", Vector3.new(0.7, 1.8, 0.7), ink, CFrame.new(1.4, 0, 0))
	model.PrimaryPart = root
	local gui = Instance.new("BillboardGui")
	gui.Size = UDim2.fromOffset(200, 50)
	gui.StudsOffset = Vector3.new(0, 4, 0)
	gui.AlwaysOnTop = true
	gui.Adornee = root
	local label = Instance.new("TextLabel")
	label.BackgroundTransparency = 1
	label.Size = UDim2.fromScale(1, 1)
	label.FontFace = Theme.Fonts.Title
	label.TextScaled = true
	label.TextColor3 = Theme.Colors.Red
	label.Text = "🥷 TRAINING THIEF"
	local stroke = Instance.new("UIStroke")
	stroke.Thickness = 3
	stroke.Color = ink
	stroke.Parent = label
	label.Parent = gui
	gui.Parent = root
	return model, root
end

local function placeThief(thief: Thief, position: Vector3, lookAt: Vector3)
	local flat = Vector3.new(lookAt.X, position.Y, lookAt.Z)
	local cf = if (flat - position).Magnitude > 0.1 then CFrame.lookAt(position, flat) else CFrame.new(position)
	local bob = math.sin(os.clock() * 12) * 0.15
	for _, p in thief.Model:GetChildren() do
		if p:IsA("BasePart") then
			local offset = p:GetAttribute("Offset") :: CFrame
			p.CFrame = cf * CFrame.new(0, bob, 0) * offset
		end
	end
end

local function firstHatched(player: Player)
	local data = DataService.Get(player)
	if not data then
		return nil
	end
	for _, rec in data.Kaijus do
		if not rec.Egg then
			return rec
		end
	end
	return nil
end

local function endThief(player: Player, reason: string)
	local thief = thieves[player]
	if not thief then
		return
	end
	thieves[player] = nil
	local anchor = Registry.KaijuService.Anchor(thief.Uid)
	if anchor and anchor:GetAttribute("CarriedBy") == -1 then
		anchor:SetAttribute("CarriedBy", 0)
		Notify.FxAll("KaijuReturned", { Uid = thief.Uid, Reason = reason })
	end
	Notify.Fx(player, "ThiefGone", { Reason = reason })
	Notify.Fx(player, "AlarmStop", { Uid = thief.Uid })
	local model = thief.Model
	task.delay(1.5, function()
		model:Destroy()
	end)
end

local function spawnThief(player: Player)
	if thieves[player] then
		return
	end
	local plot = Registry.PlotService.Get(player)
	local rec = firstHatched(player)
	if not plot or not rec then
		return
	end
	local model, root = buildThief()
	local start = (plot.CFrame * CFrame.new(0, 3, -Layout.PlotDepth / 2 - 14)).Position
	local thief: Thief = { Player = player, Model = model, Root = root, Uid = rec.Uid, State = "Walk", Started = os.clock() }
	model:SetAttribute("Owner", player.UserId)
	model.Parent = Workspace:WaitForChild("Effects")
	placeThief(thief, start, plot.CFrame.Position)
	thieves[player] = thief
	Notify.Fx(player, "ThiefSpawn", { Uid = rec.Uid })
end

-- Appelé par StealService.bonk : renvoie true si un voleur d'entraînement a été touché.
function TutorialService.TryBonkThief(player: Player, position: Vector3, range: number): boolean
	local thief = thieves[player]
	if not thief or thief.State == "Gone" then
		return false
	end
	local offset = thief.Root.Position - position
	if Vector3.new(offset.X, 0, offset.Z).Magnitude > range + 3 then
		return false
	end
	thief.State = "Gone"
	Notify.FxAll("BonkHit", { UserId = -1, Position = thief.Root.Position })
	Notify.Fx(player, "ThiefBonked", {})
	-- il s'envole
	task.spawn(function()
		local from = thief.Root.Position
		local dir = if offset.Magnitude > 0.1 then Vector3.new(offset.X, 0, offset.Z).Unit else Vector3.new(0, 0, 1)
		for i = 1, 12 do
			task.wait(0.05)
			placeThief(thief, from + dir * i * 3 + Vector3.new(0, i * 2.5 - i * i * 0.1, 0), from + dir * 10)
		end
	end)
	endThief(player, "Dropped")
	TutorialService.Notify(player, "Thief")
	return true
end

local function stepThieves()
	for player, thief in thieves do
		if player.Parent ~= Players or not thief.Model.Parent then
			thieves[player] = nil
			continue
		end
		local anchor = Registry.KaijuService.Anchor(thief.Uid)
		local plot = Registry.PlotService.Get(player)
		if not anchor or not plot or os.clock() - thief.Started > Tutorial.Thief.Timeout then
			endThief(player, "Timeout")
			continue
		end
		local pos = thief.Root.Position
		if thief.State == "Walk" then
			local target = anchor.Position + Vector3.new(0, 2.5, 0)
			local delta = Vector3.new(target.X - pos.X, 0, target.Z - pos.Z)
			if delta.Magnitude < 3 then
				thief.State = "Flee"
				anchor:SetAttribute("CarriedBy", -1)
				anchor:SetAttribute("Helper", 0)
				anchor:SetAttribute("Lifting", false)
				Notify.Fx(player, "Alarm", { Uid = thief.Uid, Thief = "Training Thief", Species = anchor:GetAttribute("Species") })
			else
				placeThief(thief, pos + delta.Unit * Tutorial.Thief.WalkSpeed * 0.1, target)
			end
		elseif thief.State == "Flee" then
			local exit = (plot.CFrame * CFrame.new(0, 3, -Layout.PlotDepth / 2 - 30)).Position
			local delta = Vector3.new(exit.X - pos.X, 0, exit.Z - pos.Z)
			if delta.Magnitude < 3 then
				-- Il s'échappe… mais c'est un entraînement : le kaiju revient.
				Notify.Toast(player, "The thief escaped! Don't worry, your kaiju came back. Try again!", "Bad")
				endThief(player, "Timeout")
				task.delay(4, function()
					if player.Parent == Players and step(player) == 5 then
						spawnThief(player)
					end
				end)
			else
				placeThief(thief, pos + delta.Unit * Tutorial.Thief.FleeSpeed * 0.1, exit)
			end
		end
	end
end

----------------------------------------------------------------------------
-- Missions
----------------------------------------------------------------------------

local function startStep(player: Player, s: number)
	if s == 5 then
		task.delay(3, function()
			if player.Parent == Players and step(player) == 5 then
				spawnThief(player)
			end
		end)
	end
end

local function advance(player: Player)
	local data = DataService.Get(player)
	if not data then
		return
	end
	local current = step(player)
	local mission = Tutorial.Get(current)
	if not mission then
		return
	end
	data.Tutorial = current + 1
	if mission.Reward.Cash then
		DataService.AddCash(player, mission.Reward.Cash, false)
	end
	if mission.Reward.Gems then
		DataService.AddGems(player, mission.Reward.Gems)
	end
	DataService.Replicate(player, "Tutorial")
	Notify.Fx(player, "MissionComplete", { Step = current, Reward = mission.Reward, Unlock = mission.UnlockMenus })
	if data.Tutorial >= Tutorial.Done then
		Notify.Fx(player, "TutorialDone", {})
	else
		startStep(player, data.Tutorial)
	end
end

-- event : Hatch | Collect | Meteor | Lock | Thief | Steal
function TutorialService.Notify(player: Player, event: string)
	local s = step(player)
	if s >= Tutorial.Done then
		return
	end
	local mission = Tutorial.Get(s)
	if not mission then
		return
	end
	local expected = ({ Kaiju = "Hatch", Collector = "Collect", Meteor = "Meteor", LockButton = "Lock", Thief = "Thief", OtherPlot = "Steal" })[mission.Target or ""]
	if event == expected then
		advance(player)
	end
end

function TutorialService.IsThiefCarrying(uid: string): boolean
	for _, thief in thieves do
		if thief.Uid == uid and thief.State == "Flee" then
			return true
		end
	end
	return false
end

function TutorialService.Init()
	-- Le client peut passer la mission de vol (serveur vide) après un délai : validé ici
	Router.On("SkipMission", function(player)
		if step(player) == 6 and #Players:GetPlayers() <= 1 then
			advance(player)
			return { ok = true }
		end
		return { ok = false, msg = "Finish the mission first!" }
	end, 1)

	DataService.Loaded:Connect(function(player, data)
		task.delay(3, function()
			if player.Parent ~= Players then
				return
			end
			if data.Tutorial <= 0 then
				data.Tutorial = 1
			end
			-- rattrapage : déjà un kaiju éclos ?
			if step(player) == 1 and firstHatched(player) then
				advance(player)
			end
			DataService.Replicate(player, "Tutorial")
			startStep(player, step(player))
		end)
	end)

	Players.PlayerRemoving:Connect(function(player)
		local thief = thieves[player]
		if thief then
			thieves[player] = nil
			thief.Model:Destroy()
		end
	end)

	task.spawn(function()
		while true do
			task.wait(0.1)
			local ok, err = pcall(stepThieves)
			if not ok then
				warn("[TutorialService] " .. tostring(err))
			end
		end
	end)
end

return TutorialService
