--!strict
--[[
	OverclockOverlay : mini-jeu de timing.
	L'aiguille est calculée avec la MÊME formule que le serveur (Formulas.NeedlePosition)
	à partir de l'heure synchronisée : ce que tu vois est ce que le serveur valide.
	STOP : clic/tap sur le bouton, Espace, ou bouton A de la manette.
]]

local ContextActionService = game:GetService("ContextActionService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local Workspace = game:GetService("Workspace")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Theme = require(Shared.Config.Theme)
local Formulas = require(Shared.Economy.Formulas)

local Create = require(script.Parent.Parent.Create)
local Style = require(script.Parent.Parent.Style)
local Motion = require(script.Parent.Parent.Motion)
local Material = require(script.Parent.Parent.Material)
local Keycap = require(script.Parent.Parent.Components.Keycap)
local Net = require(script.Parent.Parent.Parent.Controllers.Net)

local New = Create.New

local OverclockOverlay = {}

OverclockOverlay.OnResult = nil :: ((grade: string) -> ())?

local root: Frame
local gauge: Frame
local needle: Frame
local goodZone: Frame
local perfectZone: Frame
local resultLabel: TextLabel
local stopKey: Keycap.Keycap
local running = false
local params: any = nil
local renderConnection: RBXScriptConnection? = nil

local ACTION = "AngAInOneOverclockStop"

local function hide(delay: number)
	task.delay(delay, function()
		if running then
			return
		end
		Motion.Tween(
			root,
			{ Position = UDim2.new(0.5, 0, 1, 260) },
			0.3,
			Enum.EasingStyle.Quad,
			Enum.EasingDirection.In
		).Completed
			:Once(function()
				if not running then
					root.Visible = false
				end
			end)
		if renderConnection then
			renderConnection:Disconnect()
			renderConnection = nil
		end
	end)
end

local resultToken = 0

local function stop()
	if not running then
		return
	end
	running = false
	ContextActionService:UnbindAction(ACTION)
	Net.Fire("OverclockStop")
	-- Filet de sécurité : si le résultat ne revient pas (requête refusée), on range l'overlay.
	resultToken += 1
	local token = resultToken
	task.delay(3, function()
		if token == resultToken and not running then
			hide(0)
		end
	end)
end

local function begin(data: any)
	params = data
	running = true
	root.Visible = true
	root.Position = UDim2.new(0.5, 0, 1, 260)
	Motion.Tween(root, { Position = UDim2.new(0.5, 0, 1, -140) }, 0.35, Enum.EasingStyle.Back)
	resultLabel.Text = "Arrête l'aiguille dans la zone dorée !"
	resultLabel.TextColor3 = Style.Color("TextPrimary")
	goodZone.Position = UDim2.fromScale(data.Target - data.Good, 0)
	goodZone.Size = UDim2.fromScale(data.Good * 2, 1)
	perfectZone.Position = UDim2.fromScale(data.Target - data.Perfect, 0)
	perfectZone.Size = UDim2.fromScale(data.Perfect * 2, 1)
	stopKey:SetEnabled(true)
	ContextActionService:BindAction(
		ACTION,
		function(_name: string, state: Enum.UserInputState): Enum.ContextActionResult
			if state == Enum.UserInputState.Begin then
				stop()
				return Enum.ContextActionResult.Sink
			end
			return Enum.ContextActionResult.Pass
		end,
		false,
		Enum.KeyCode.Space,
		Enum.KeyCode.ButtonA
	)
	if renderConnection then
		renderConnection:Disconnect()
	end
	renderConnection = RunService.RenderStepped:Connect(function()
		if not params then
			return
		end
		local elapsed = Workspace:GetServerTimeNow() - params.Start
		if running and elapsed > params.MaxSeconds then
			stop()
		end
		if running then
			needle.Position = UDim2.fromScale(Formulas.NeedlePosition(elapsed, params.Period), 0.5)
		end
	end)
end

local function result(data: any)
	resultToken += 1
	running = false
	ContextActionService:UnbindAction(ACTION)
	stopKey:SetEnabled(false)
	local grade = data.Grade
	if grade == "Perfect" then
		resultLabel.Text = `PARFAIT ! Production x{data.Mult}`
		resultLabel.TextColor3 = Style.Color("CurrencyBits")
	elseif grade == "Good" then
		resultLabel.Text = `BIEN ! Production x{data.Mult}`
		resultLabel.TextColor3 = Style.Color("Success")
	else
		resultLabel.Text = "Raté… la station refroidit 20 s."
		resultLabel.TextColor3 = Style.Color("Danger")
	end
	Motion.Pop(resultLabel, 0.2)
	if OverclockOverlay.OnResult then
		OverclockOverlay.OnResult(grade)
	end
	hide(1.8)
end

function OverclockOverlay.Mount(layer: Frame)
	root = New("Frame", {
		Name = "Overclock",
		AnchorPoint = Vector2.new(0.5, 1),
		Position = UDim2.new(0.5, 0, 1, 260),
		Size = UDim2.fromOffset(620, 230),
		BackgroundTransparency = Theme.Alpha.GlassStrong,
		BorderSizePixel = 0,
		Visible = false,
		Tag = { "Glass", "RoundL" },
		Parent = layer,
	}, {
		New("UIShadow", {
			BlurRadius = UDim.new(0, 24),
			Transparency = 0.4,
			Offset = UDim2.fromOffset(0, 8),
			Color = Style.Color("BgDeep"),
		}),
	})
	Material.Glass(root, true)
	Material.RgbEdge(root, 2, 0.1, 90)
	New("TextLabel", {
		Position = UDim2.fromOffset(24, 14),
		Size = UDim2.new(1, -48, 0, 26),
		BackgroundTransparency = 1,
		Text = "STATION D'OVERCLOCK",
		TextXAlignment = Enum.TextXAlignment.Left,
		Tag = "TextTitle",
		Parent = root,
	})
	resultLabel = New("TextLabel", {
		Position = UDim2.fromOffset(24, 44),
		Size = UDim2.new(1, -48, 0, 24),
		BackgroundTransparency = 1,
		Text = "",
		TextXAlignment = Enum.TextXAlignment.Left,
		Tag = "DynHeading",
		TextColor3 = Style.Color("TextPrimary"),
		Parent = root,
	})
	gauge = New("Frame", {
		Position = UDim2.fromOffset(24, 80),
		Size = UDim2.new(1, -48, 0, 34),
		BorderSizePixel = 0,
		ClipsDescendants = false,
		Tag = { "GlassSunken", "RoundPill" },
		Parent = root,
	})
	goodZone = New("Frame", {
		Size = UDim2.fromScale(0.28, 1),
		BackgroundTransparency = 0.45,
		BorderSizePixel = 0,
		Tag = { "FillCyan", "RoundS" },
		Parent = gauge,
	})
	perfectZone = New("Frame", {
		Size = UDim2.fromScale(0.1, 1),
		BackgroundTransparency = 0.1,
		BorderSizePixel = 0,
		Tag = { "FillGold", "RoundS" },
		Parent = gauge,
	})
	needle = New("Frame", {
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromScale(0, 0.5),
		Size = UDim2.new(0, 6, 1, 18),
		BorderSizePixel = 0,
		ZIndex = 5,
		Tag = { "FillBrand", "RoundPill" },
		Parent = gauge,
	}, {
		New("UIStroke", { Color = Style.Color("TextPrimary"), Thickness = 1.5 }),
	})
	stopKey = Keycap.new({
		Text = "STOP",
		Icon = "Power",
		Variant = "Primary",
		Size = UDim2.new(1, -48, 0, 70),
		Position = UDim2.fromOffset(24, 134),
		OnClick = stop,
		Parent = root,
	})

	Net.On("Overclock", function(phase: string, data: any)
		if phase == "Begin" then
			begin(data)
		elseif phase == "Result" then
			result(data)
		end
	end)
end

return OverclockOverlay
