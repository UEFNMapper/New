--!nonstrict
-- Missions d'introduction (côté client) : carte d'objectif animée, flèches
-- au sol vers la cible, célébration à chaque mission, guidage pendant un vol
-- et vers un voleur (alarme).

local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local Workspace = game:GetService("Workspace")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Rarities = require(Shared.Config.Rarities)
local Economy = require(Shared.Config.Economy)
local TutorialConfig = require(Shared.Config.Tutorial)
local Theme = require(Shared.Config.Theme)
local Format = require(Shared.Logic.Format)

local Controllers = script.Parent.Parent.Controllers
local State = require(Controllers.State)
local Remote = require(Controllers.Remote)
local Audio = require(Controllers.Audio)
local FxBus = require(Controllers.FxBus)
local UIRegistry = require(Controllers.UIRegistry)
local CameraFx = require(Controllers.CameraFx)
local Kit = require(script.Parent.Parent.UI.Kit)
local Guide = require(script.Parent.Guide)

local C = Theme.Colors
local F = Theme.Fonts
local player = Players.LocalPlayer

local Tutorial = {}

local layer: ScreenGui
local card: Frame
local cardIcon: GuiObject
local cardStep: TextLabel
local cardTitle: TextLabel
local cardText: TextLabel
local cardHint: TextLabel
local guide = Guide.new(C.Radioactive)
local carryGuide = Guide.new(C.Gold)
local thiefGuide = Guide.new(C.Red)
local currentStep = 0

local function myPlot(): Model?
	local index = player:GetAttribute("Plot")
	local map = Workspace:FindFirstChild("Map")
	return if index and map then map:FindFirstChild("Plot" .. index) :: Model else nil
end

local function myKaijuAnchor(): BasePart?
	local folder = Workspace:FindFirstChild("Kaijus")
	local mine = folder and folder:FindFirstChild(tostring(player.UserId))
	if not mine then
		return nil
	end
	for _, a in mine:GetChildren() do
		if a:IsA("BasePart") and not a:GetAttribute("Egg") then
			return a
		end
	end
	return mine:FindFirstChildWhichIsA("BasePart")
end

local function nearestFreeMeteor(): BasePart?
	local folder = Workspace:FindFirstChild("Meteors")
	local root = player.Character and player.Character:FindFirstChild("HumanoidRootPart") :: BasePart?
	if not folder or not root then
		return nil
	end
	local best, bestD = nil, math.huge
	for _, m in folder:GetChildren() do
		if m:IsA("BasePart") then
			local owner = m:GetAttribute("Owner") or 0
			local order = Rarities.Get(m:GetAttribute("Rarity") or "Common").Order
			if (owner == 0 or owner == player.UserId) and order <= Economy.FreeFirstEggMaxOrder then
				local d = (m.Position - root.Position).Magnitude
				if d < bestD then
					best, bestD = m, d
				end
			end
		end
	end
	return best
end

-- État de la défense de mon île (dossier répliqué par SiegeService).
local function mySiegeState(): string?
	local siege = Workspace:FindFirstChild("Siege")
	local index = player:GetAttribute("Plot")
	local mine = siege and index and siege:FindFirstChild("Plot" .. index)
	return if mine then mine:GetAttribute("State") else nil
end

----------------------------------------------------------------------------
-- Carte de mission
----------------------------------------------------------------------------

local function buildCard()
	card = Kit.new("Frame", {
		Name = "Mission",
		Size = UDim2.fromOffset(430, 118),
		Position = UDim2.new(0.5, 0, 0, 168),
		AnchorPoint = Vector2.new(0.5, 0),
		BackgroundTransparency = 1,
		Visible = false,
		Parent = layer,
	})
	Kit.AutoScale(card)
	local _, body = Kit.Panel({ Size = UDim2.fromScale(1, 1), Rotation = -1, Gradient = "Paper", Parent = card })
	Kit.Hazard({ Size = UDim2.new(1, -16, 0, 8), Position = UDim2.fromOffset(8, 5), Parent = body })
	cardStep = Kit.Text({
		Size = UDim2.fromOffset(120, 22),
		Position = UDim2.fromOffset(14, 16),
		Text = "MISSION 1/6",
		FontFace = F.Title,
		TextColor3 = C.Magma,
		TextXAlignment = Enum.TextXAlignment.Left,
		Stroke = false,
		ZIndex = 4,
		Parent = body,
	})
	cardIcon = Kit.Icon("egg", { Size = UDim2.fromOffset(64, 64), Position = UDim2.fromOffset(12, 42), ZIndex = 4, Parent = body })
	Kit.Wobble(cardIcon, 8, 0.9)
	cardTitle = Kit.Text({
		Size = UDim2.new(1, -100, 0, 30),
		Position = UDim2.fromOffset(84, 36),
		Text = "",
		FontFace = F.Impact,
		TextColor3 = C.Ink,
		TextXAlignment = Enum.TextXAlignment.Left,
		Stroke = false,
		MaxTextSize = 30,
		ZIndex = 4,
		Parent = body,
	})
	cardText = Kit.Text({
		Size = UDim2.new(1, -100, 0, 44),
		Position = UDim2.fromOffset(84, 66),
		Text = "",
		FontFace = F.Body,
		TextColor3 = C.InkSoft,
		TextXAlignment = Enum.TextXAlignment.Left,
		TextYAlignment = Enum.TextYAlignment.Top,
		TextWrapped = true,
		Stroke = false,
		MaxTextSize = 17,
		ZIndex = 4,
		Parent = body,
	})
	cardHint = Kit.Text({
		Size = UDim2.new(0.6, 0, 0, 20),
		Position = UDim2.new(1, -14, 0, 16),
		AnchorPoint = Vector2.new(1, 0),
		Text = "",
		FontFace = F.Body,
		TextColor3 = C.RadioactiveDark,
		TextXAlignment = Enum.TextXAlignment.Right,
		Stroke = false,
		MaxTextSize = 16,
		ZIndex = 4,
		Parent = body,
	})
end

local function showStep(step: number)
	local mission = TutorialConfig.Get(step)
	if not mission then
		card.Visible = false
		guide:Hide()
		return
	end
	card.Visible = true
	cardStep.Text = ("MISSION %d/%d"):format(step, #TutorialConfig.Missions)
	cardTitle.Text = mission.Title
	cardText.Text = mission.Text
	Kit.SetIcon(cardIcon, mission.Icon)
	local reward = mission.Reward
	cardHint.Text = "Reward: " .. (if reward.Cash then Format.Cash(reward.Cash) elseif reward.Gems then reward.Gems .. " 💎" else "")
	Kit.Pop(card, 0.4, 0.5)
end

local function celebrate(args)
	local mission = TutorialConfig.Get(args.Step or 0)
	if not mission then
		return
	end
	Audio.Play("quest_complete")
	CameraFx.FovPunch(-3, 0.4)
	local reward = args.Reward or {}
	local text = if reward.Cash then "+" .. Format.Cash(reward.Cash) elseif reward.Gems then "+" .. reward.Gems .. " 💎" else ""
	UIRegistry.Announce("MISSION COMPLETE!", C.Radioactive, mission.Title .. "  —  " .. text, nil, true)
	if args.Unlock and #args.Unlock > 0 then
		task.delay(3.2, function()
			UIRegistry.Toast("New menus unlocked: " .. table.concat(args.Unlock, ", "), "Good")
		end)
	end
end

----------------------------------------------------------------------------

function Tutorial.Init()
	layer = Kit.Layer("Tutorial", 9)
	buildCard()

	State.Observe("Tutorial", function(step)
		step = math.max(1, step or 1)
		if step ~= currentStep then
			currentStep = step
			showStep(step)
		end
	end)

	FxBus.On("MissionComplete", celebrate)
	FxBus.On("TutorialDone", function()
		task.delay(3.5, function()
			UIRegistry.Announce("YOU'RE READY!", C.Gold, "Level up to open new worlds. Follow the NEXT GOAL bar!", "hatch_legendary", true)
		end)
	end)

	RunService.Heartbeat:Connect(function()
		local plot = myPlot()
		local carrying = (player:GetAttribute("Carrying") or "") ~= ""
		-- la carte se cache pendant un Rampage (elle couvrirait la ville) et pendant un vol
		card.Visible = TutorialConfig.Get(currentStep) ~= nil and not carrying and player:GetAttribute("Rampage") ~= true
		local mission = TutorialConfig.Get(currentStep)
		local target = mission and mission.Target
		if target == "Kaiju" then
			guide:Point(myKaijuAnchor())
		elseif target == "Collector" and plot then
			guide:Point(plot:FindFirstChild("CollectorPad"))
		elseif target == "Meteor" then
			local m = nearestFreeMeteor()
			if m then
				guide:Point(m)
				cardHint.Text = "An egg is waiting in the crater!"
			else
				guide:Point(Vector3.new(0, 0, 0))
				local wait = Workspace:GetAttribute("NextMeteorIn") or 0
				cardHint.Text = if wait > 0 then ("Next meteor in %ds"):format(math.ceil(wait)) else "Head to the crater!"
			end
		elseif target == "Siege" then
			guide:Point(if plot then plot:FindFirstChild("Floor") else nil)
			local state = mySiegeState()
			cardHint.Text = if state == "Active" then "BONK the invaders on your island!" else "They're coming... get home!"
		elseif target == "RampagePortal" and plot then
			guide:Point(plot:FindFirstChild("RampagePortal"))
		elseif target == "Treasure" then
			local pos = player:GetAttribute("TreasurePos")
			if typeof(pos) == "Vector3" then
				guide:Point(pos)
				cardHint.Text = "Hold E on the glowing spot!"
			else
				guide:Hide()
				cardHint.Text = "Your buddy is sniffing around..."
			end
		else
			guide:Hide()
		end
		if carrying and plot then
			carryGuide:Point(plot:FindFirstChild("Floor"))
		else
			carryGuide:Hide()
		end
	end)
end

-- Flèches rouges vers un voleur (alarme)
function Tutorial.PointThief(target: any)
	thiefGuide:Point(target)
end

function Tutorial.HideThief()
	thiefGuide:Hide()
end

return Tutorial
