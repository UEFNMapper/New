--!nonstrict
-- Tutoriel guidé (5 étapes) + guidage automatique pendant un vol.
--   0 : ton œuf éclôt       -> quand un kaiju est éclos
--   1 : collecte ton cash    -> après une collecte
--   2 : achète un œuf        -> après un achat
--   3 : verrouille ta base   -> après un verrouillage (ou 25 s)
--   4 : va voler !           -> 12 s puis terminé (5)

local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local Workspace = game:GetService("Workspace")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Layout = require(Shared.Config.Layout)
local Rarities = require(Shared.Config.Rarities)
local Economy = require(Shared.Config.Economy)
local Theme = require(Shared.Config.Theme)

local Controllers = script.Parent.Parent.Controllers
local State = require(Controllers.State)
local Remote = require(Controllers.Remote)
local Audio = require(Controllers.Audio)
local FxBus = require(Controllers.FxBus)
local Kit = require(script.Parent.Parent.UI.Kit)
local Guide = require(script.Parent.Guide)

local C = Theme.Colors
local player = Players.LocalPlayer

local Tutorial = {}

local STEPS = {
	[0] = { Icon = "🥚", Text = "Your first egg is hatching! Watch it on your island." },
	[1] = { Icon = "⚛️", Text = "Your kaiju makes cash! Step on the Cash Reactor to collect." },
	[2] = { Icon = "☄️", Text = "Meteors drop eggs in the crater. Buy one — it's FREE!" },
	[3] = { Icon = "🛡️", Text = "Thieves are coming! Press LOCK BASE to raise your shield." },
	[4] = { Icon = "🦹", Text = "Now go STEAL kaijus from other islands! Big ones need 2 thieves." },
}

local hint: Frame
local hintText: TextLabel
local hintIcon: TextLabel
local guide
local carryGuide
local step = -1
local stepStarted = 0

local function myPlot(): Model?
	local index = player:GetAttribute("Plot")
	local map = Workspace:FindFirstChild("Map")
	return if index and map then map:FindFirstChild("Plot" .. index) :: Model else nil
end

local function myFirstKaijuAnchor(): BasePart?
	local folder = Workspace:FindFirstChild("Kaijus")
	local mine = folder and folder:FindFirstChild(tostring(player.UserId))
	return mine and mine:FindFirstChildWhichIsA("BasePart")
end

local function nearestMeteor(): BasePart?
	local folder = Workspace:FindFirstChild("Meteors")
	local root = player.Character and player.Character:FindFirstChild("HumanoidRootPart") :: BasePart?
	if not folder or not root then
		return nil
	end
	local best, bestD = nil, math.huge
	for _, m in folder:GetChildren() do
		if m:IsA("BasePart") and (m:GetAttribute("Owner") or 0) == 0 or m:GetAttribute("Owner") == player.UserId then
			local d = (m.Position - root.Position).Magnitude
			if d < bestD and Rarities.Get(m:GetAttribute("Rarity") or "Common").Order <= Economy.FreeFirstEggMaxOrder then
				best, bestD = m, d
			end
		end
	end
	return best
end

local function setStep(n: number)
	if n == step then
		return
	end
	step = n
	stepStarted = os.clock()
	local def = STEPS[n]
	if not def then
		hint.Visible = false
		guide:Hide()
		return
	end
	hint.Visible = true
	hintIcon.Text = def.Icon
	hintText.Text = def.Text
	Kit.Pop(hint, 0.5)
	Audio.Play("quest_complete", { Volume = 0.6 })
end

local function advance(to: number)
	if to > (State.Get("Tutorial") or 0) then
		Remote.Call("Tutorial", { Step = to }, true)
	end
	setStep(to)
end

function Tutorial.Init()
	local layer = Kit.Layer("Tutorial", 9)
	hint = Kit.new("Frame", {
		Size = UDim2.fromOffset(620, 74),
		Position = UDim2.new(0.5, 0, 0, 196),
		AnchorPoint = Vector2.new(0.5, 0),
		BackgroundTransparency = 1,
		Visible = false,
		Parent = layer,
	})
	Kit.AutoScale(hint)
	local _, body = Kit.Panel({ Size = UDim2.fromScale(1, 1), Rotation = -1, Gradient = "Gold", Parent = hint })
	hintIcon = Kit.Text({ Size = UDim2.fromOffset(60, 60), Position = UDim2.fromOffset(8, 7), Text = "🥚", FontFace = Kit.Fonts.Body, Stroke = false, ZIndex = 4, Parent = body })
	Kit.Wobble(hintIcon, 8, 0.7)
	hintText = Kit.Text({ Size = UDim2.new(1, -86, 1, -14), Position = UDim2.fromOffset(74, 7), Text = "", FontFace = Kit.Fonts.Body, TextColor3 = C.Ink, Stroke = false, TextXAlignment = Enum.TextXAlignment.Left, ZIndex = 4, Parent = body })

	guide = Guide.new(C.Radioactive)
	carryGuide = Guide.new(C.Gold)

	local saved = State.Get("Tutorial") or 0
	if saved < 5 then
		setStep(saved)
	end

	FxBus.On("Hatch", function()
		if step == 0 then
			task.delay(4, function()
				advance(1)
			end)
		end
	end)
	FxBus.On("Collect", function()
		if step == 1 then
			advance(2)
		end
	end)
	State.Changed("Stats"):Connect(function(stats)
		if step == 2 and stats.EggsBought > 0 then
			advance(3)
		elseif step == 3 and (stats.Locks or 0) > 0 then
			advance(4)
		end
	end)
	State.Changed("Kaijus"):Connect(function(list)
		if step == 0 then
			for _, rec in list do
				if not rec.Egg then
					advance(1)
					break
				end
			end
		end
	end)

	RunService.Heartbeat:Connect(function()
		-- étapes chronométrées
		if step == 3 and os.clock() - stepStarted > 25 then
			advance(4)
		elseif step == 4 and os.clock() - stepStarted > 12 then
			advance(5)
		end
		-- cible du guide
		local plot = myPlot()
		if step == 0 then
			guide:Point(myFirstKaijuAnchor())
		elseif step == 1 and plot then
			guide:Point(plot:FindFirstChild("CollectorPad"))
		elseif step == 2 then
			local m = nearestMeteor()
			if m then
				guide:Point(m)
			else
				guide:Hide()
			end
		elseif step == 3 then
			guide:Hide()
		elseif step == 4 then
			local index = player:GetAttribute("Plot") or 1
			local other = (index % Layout.PlotCount) + 1
			local map = Workspace:FindFirstChild("Map")
			local target = map and map:FindFirstChild("Plot" .. other)
			if target and target:GetAttribute("OwnerId") then
				guide:Point(target:FindFirstChild("Floor"))
			else
				guide:Hide()
			end
		else
			guide:Hide()
		end
		-- le bandeau s'efface pendant un vol (le panneau de portage prend sa place)
		local carrying = (player:GetAttribute("Carrying") or "") ~= ""
		hint.Visible = STEPS[step] ~= nil and not carrying
		-- pendant un vol : flèches dorées vers sa propre île
		if carrying and plot then
			carryGuide:Point(plot:FindFirstChild("Floor"))
		else
			carryGuide:Hide()
		end
	end)
end

return Tutorial
