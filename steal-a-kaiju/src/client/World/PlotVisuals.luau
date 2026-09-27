--!nonstrict
-- Visuels des îles : dôme de bouclier, laser de porte, minuteur du bouclier,
-- nids verrouillés (et achat du suivant), réacteur qui pulse selon le cash
-- en attente, flèche « COLLECT ».

local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local Workspace = game:GetService("Workspace")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Layout = require(Shared.Config.Layout)
local Economy = require(Shared.Config.Economy)
local Theme = require(Shared.Config.Theme)
local Format = require(Shared.Logic.Format)

local Controllers = script.Parent.Parent.Controllers
local State = require(Controllers.State)
local Remote = require(Controllers.Remote)
local Audio = require(Controllers.Audio)
local FxBus = require(Controllers.FxBus)
local Effects = require(script.Parent.Effects)

local C = Theme.Colors
local player = Players.LocalPlayer

local PlotVisuals = {}

type PlotEntry = {
	Model: Model,
	Dome: BasePart,
	Timer: BillboardGui,
	Gate: BasePart?,
	Active: boolean,
	NestLocks: { [number]: BillboardGui },
}

local plots: { PlotEntry } = {}
local folder: Folder
local nestPrompt: ProximityPrompt? = nil

local function now(): number
	return Workspace:GetServerTimeNow()
end

local function makeDome(model: Model): BasePart
	local index = model:GetAttribute("Index") or 1
	local cf = Layout.PlotCFrame(index)
	local dome = Instance.new("Part")
	dome.Name = "ShieldDome"
	dome.Shape = Enum.PartType.Ball
	dome.Size = Vector3.new(1, 1, 1) * (Layout.PlotDepth * 1.35)
	dome.CFrame = cf
	dome.Anchored = true
	dome.CanCollide = false
	dome.CanQuery = false
	dome.CanTouch = false
	dome.CastShadow = false
	dome.Material = Enum.Material.ForceField
	dome.Color = C.Cyan
	dome.Transparency = 1
	dome.Parent = folder
	return dome
end

local function makeTimer(model: Model): BillboardGui
	local gate = model:FindFirstChild("Gate") :: BasePart?
	local gui = Instance.new("BillboardGui")
	gui.Name = "ShieldTimer"
	gui.Size = UDim2.fromOffset(200, 50)
	gui.StudsOffsetWorldSpace = Vector3.new(0, 9, 0)
	gui.MaxDistance = 260
	gui.LightInfluence = 0
	gui.Adornee = gate
	gui.Enabled = false
	local label = Instance.new("TextLabel")
	label.Name = "Text"
	label.BackgroundTransparency = 1
	label.Size = UDim2.fromScale(1, 1)
	label.FontFace = Theme.Fonts.Impact
	label.TextScaled = true
	label.TextColor3 = C.Cyan
	local stroke = Instance.new("UIStroke")
	stroke.Thickness = 3
	stroke.Color = C.Ink
	stroke.Parent = label
	label.Parent = gui
	gui.Parent = folder
	return gui
end

local function nestLockLabel(model: Model, slot: number): BillboardGui?
	local nest = model:FindFirstChild("Nest" .. slot) :: BasePart?
	if not nest then
		return nil
	end
	local gui = Instance.new("BillboardGui")
	gui.Name = "NestLock"
	gui.Size = UDim2.fromOffset(150, 44)
	gui.StudsOffsetWorldSpace = Vector3.new(0, 3, 0)
	gui.MaxDistance = 60
	gui.LightInfluence = 0
	gui.Adornee = nest
	local label = Instance.new("TextLabel")
	label.Name = "Text"
	label.BackgroundTransparency = 1
	label.Size = UDim2.fromScale(1, 1)
	label.FontFace = Theme.Fonts.Title
	label.TextScaled = true
	label.TextColor3 = C.Paper
	label.Text = "🔒"
	local stroke = Instance.new("UIStroke")
	stroke.Thickness = 2.5
	stroke.Color = C.Ink
	stroke.Parent = label
	label.Parent = gui
	gui.Parent = folder
	return gui
end

-- Nids verrouillés sur MON île : grisés, cadenas, et prompt d'achat sur le suivant.
local function refreshMyNests()
	local myIndex = player:GetAttribute("Plot")
	for _, entry in plots do
		local model = entry.Model
		local mine = model:GetAttribute("Index") == myIndex
		local unlocked = model:GetAttribute("Nests") or 0
		for slot = 1, #Layout.Nests do
			local ring = nil
			local nest = model:FindFirstChild("Nest" .. slot) :: BasePart?
			if nest then
				for _, child in model:GetChildren() do
					if child.Name == "NestRing" and child:IsA("BasePart") and (child.Position - nest.Position).Magnitude < 1 then
						ring = child
					end
				end
			end
			local locked = slot > unlocked
			if ring then
				ring.Transparency = if locked then 0.85 else 0.5
			end
			if nest then
				nest.Transparency = if locked and mine then 0.55 else 0
			end
			local lock = entry.NestLocks[slot]
			if mine and locked then
				if not lock then
					lock = nestLockLabel(model, slot)
					entry.NestLocks[slot] = lock :: any
				end
				local text = (lock :: any).Text :: TextLabel
				if slot == unlocked + 1 and unlocked < Economy.MaxNests then
					text.Text = "🔒 " .. Format.Cash(Economy.NestPrice(State.Get("Nests") or Economy.StartNests))
					text.TextColor3 = if (State.Get("Cash") or 0) >= Economy.NestPrice(State.Get("Nests") or 6) then C.Cash else C.Paper
				else
					text.Text = "🔒"
					text.TextColor3 = C.Paper
				end
			elseif lock then
				lock:Destroy()
				entry.NestLocks[slot] = nil
			end
		end
		-- prompt d'achat sur le prochain nid
		if mine then
			local nextSlot = unlocked + 1
			local nest = model:FindFirstChild("Nest" .. nextSlot) :: BasePart?
			if nestPrompt and (not nest or nestPrompt.Parent ~= nest or unlocked >= Economy.MaxNests) then
				nestPrompt:Destroy()
				nestPrompt = nil
			end
			if nest and not nestPrompt and unlocked < Economy.MaxNests then
				local prompt = Instance.new("ProximityPrompt")
				prompt.Style = Enum.ProximityPromptStyle.Custom
				prompt.ActionText = "UNLOCK NEST"
				prompt.ObjectText = "New nest"
				prompt.HoldDuration = 0
				prompt.MaxActivationDistance = 12
				prompt.RequiresLineOfSight = false
				prompt:SetAttribute("Color", "Gold")
				prompt.Triggered:Connect(function()
					local r = Remote.Call("BuyNest")
					if r.ok then
						Effects.Burst(nest.Position + Vector3.new(0, 2, 0), C.Gold, 40, 3)
						Effects.Shockwave(nest.Position, C.Gold, 12, 0.6)
						Audio.Play("purchase")
					end
				end)
				prompt.Parent = nest
				nestPrompt = prompt
			end
		end
	end
end

function PlotVisuals.Init()
	folder = Instance.new("Folder")
	folder.Name = "ClientPlots"
	folder.Parent = Workspace

	local map = Workspace:WaitForChild("Map")
	for i = 1, Layout.PlotCount do
		local model = map:WaitForChild("Plot" .. i) :: Model
		local entry: PlotEntry = {
			Model = model,
			Dome = makeDome(model),
			Timer = makeTimer(model),
			Gate = model:FindFirstChild("Gate") :: BasePart?,
			Active = false,
			NestLocks = {},
		}
		table.insert(plots, entry)
		model.AttributeChanged:Connect(function(attr)
			if attr == "Nests" or attr == "OwnerId" then
				refreshMyNests()
			end
		end)
	end
	player:GetAttributeChangedSignal("Plot"):Connect(refreshMyNests)
	State.Observe("Nests", refreshMyNests)
	State.Changed("Cash"):Connect(function()
		-- rafraîchit la couleur du prix (léger)
		refreshMyNests()
	end)
	refreshMyNests()

	RunService.Heartbeat:Connect(function()
		local t = now()
		local pulse = (math.sin(os.clock() * 3) + 1) / 2
		for _, entry in plots do
			local model = entry.Model
			local shield = (model:GetAttribute("ShieldUntil") or 0) - t
			local protected = (model:GetAttribute("ProtectedUntil") or 0) - t
			local active = model:GetAttribute("OwnerId") ~= nil and (shield > 0 or protected > 0)
			if active ~= entry.Active then
				entry.Active = active
				if active then
					Effects.Shockwave(entry.Dome.Position, C.Cyan, Layout.PlotDepth * 0.7, 0.8)
				end
			end
			if active then
				entry.Dome.Color = if shield > 0 then C.Cyan else C.Radioactive
				entry.Dome.Transparency = 0.25 + pulse * 0.15
				if entry.Gate then
					entry.Gate.LocalTransparencyModifier = 0
					entry.Gate.Transparency = 0.2 + pulse * 0.2
				end
				entry.Timer.Enabled = true
				local label = entry.Timer:FindFirstChild("Text") :: TextLabel
				label.Text = if shield > 0 then ("🛡️ %ds"):format(math.ceil(shield)) else ("🌱 SAFE %ds"):format(math.ceil(protected))
				label.TextColor3 = if shield > 0 then C.Cyan else C.Radioactive
			else
				entry.Dome.Transparency = 1
				if entry.Gate then
					entry.Gate.Transparency = 1
				end
				entry.Timer.Enabled = false
			end
			-- réacteur : lumière selon le cash stocké
			local core = model:FindFirstChild("Core") :: BasePart?
			if core then
				local stored = model:GetAttribute("Stored") or 0
				local glow = math.clamp(math.log10(stored + 1) / 7, 0.1, 1)
				local light = core:FindFirstChildOfClass("PointLight")
				if light then
					light.Brightness = 0.6 + glow * 2.5 + pulse * glow
				end
			end
		end
	end)

	FxBus.On("ShieldUp", function(args)
		local entry = plots[args.Plot or 0]
		if entry then
			Audio.Play("shield_on", { Parent = entry.Dome, MaxDistance = 400 })
			Effects.Shockwave(entry.Dome.Position, C.Cyan, Layout.PlotDepth * 0.8, 0.9)
		end
	end)
	FxBus.On("ShieldZap", function(args)
		Audio.Play("shield_zap")
		local character = player.Character
		local root = character and character:FindFirstChild("HumanoidRootPart") :: BasePart?
		if root then
			Effects.Burst(root.Position, C.Cyan, 30, 2)
			Effects.FloatingText(root.Position + Vector3.new(0, 4, 0), if args.Protected then "NEW PLAYER!" else "ZAP!", C.Cyan)
		end
	end)
end

return PlotVisuals
