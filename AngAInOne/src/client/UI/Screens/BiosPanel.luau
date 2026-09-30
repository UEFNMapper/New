--!strict
--[[
	BiosPanel : console BIOS.
	- Reboot : aperçu du Firmware gagné, ce qui est gardé / réinitialisé,
	  confirmation par APPUI LONG (1,5 s) pour éviter toute erreur.
	- Singularité : les 5 phases de la fin du jeu.
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Zones = require(Shared.Config.Zones)
local GameConfig = require(Shared.Config.GameConfig)
local NumberFormat = require(Shared.Util.NumberFormat)

local Create = require(script.Parent.Parent.Create)
local Style = require(script.Parent.Parent.Style)
local Panel = require(script.Parent.Parent.Components.Panel)
local Keycap = require(script.Parent.Parent.Components.Keycap)
local Widgets = require(script.Parent.Parent.Components.Widgets)
local App = require(script.Parent.Parent.App)
local Store = require(script.Parent.Parent.Parent.Controllers.Store)
local Net = require(script.Parent.Parent.Parent.Controllers.Net)

local New = Create.New

local BiosPanel = {}

local panel: Panel.Panel
local tab = "Reboot"
local tabKeys: { [string]: Keycap.Keycap } = {}
local body: Frame
local holdConnection: RBXScriptConnection? = nil
local HOLD_SECONDS = 1.5

local function line(parent: Instance, order: number, text: string, tag: string, height: number?)
	New("TextLabel", {
		Size = UDim2.new(1, -4, 0, height or 22),
		BackgroundTransparency = 1,
		Text = text,
		TextWrapped = true,
		RichText = true,
		TextXAlignment = Enum.TextXAlignment.Left,
		LayoutOrder = order,
		Tag = tag,
		Parent = parent,
	})
end

local function buildReboot(state: any)
	local data = state.Data
	local perPoint = GameConfig.Reboot.FirmwarePerPoint
	local gain = state.FirmwarePreview
	local currentMult = 1 + data.Firmware * perPoint
	local nextMult = 1 + (data.Firmware + gain) * perPoint
	local available = data.Zone >= GameConfig.Reboot.RequiredZone and gain >= GameConfig.Reboot.MinFirmwareGain

	local scroll = Widgets.Scroll(body, 8)
	line(scroll, 1, "> AngAInOne BIOS · procédure de REBOOT", "TextTitle", 30)
	line(scroll, 2, `Génération actuelle : <b>{data.Generation}</b>  →  <b>{data.Generation + 1}</b>`, "TextBody")
	line(
		scroll,
		3,
		`Firmware : <b>{data.Firmware}</b> (x{string.format("%.2f", currentMult)})  →  <b>{data.Firmware + gain}</b> (x{string.format(
			"%.2f",
			nextMult
		)})`,
		"TextBody"
	)
	if data.RebootBoostPending then
		line(scroll, 4, "Reboot Boost actif : Firmware x1,5 déjà inclus.", "TextChips")
	end
	line(scroll, 5, "", "TextBody", 6)
	line(
		scroll,
		6,
		"<b>Réinitialisé :</b> Bits, niveaux des modules, étages, alimentation, radiateurs.",
		"TextMuted",
		40
	)
	line(scroll, 7, "<b>Conservé :</b> Chips, Nanobots, Firmware, fragments, pass, statistiques.", "TextMuted", 40)
	if not available then
		local reason = if data.Zone < GameConfig.Reboot.RequiredZone
			then `Débloque {Zones[GameConfig.Reboot.RequiredZone].Name} (GPU) pour rebooter.`
			else "Produis encore un peu : le gain de Firmware est nul pour l'instant."
		line(scroll, 8, reason, "TextHeading", 40)
	end

	-- Bouton à maintenir
	local holder: Frame = New("Frame", {
		Size = UDim2.new(1, -4, 0, 70),
		BackgroundTransparency = 1,
		LayoutOrder = 20,
		Parent = scroll,
	})
	local key = Keycap.new({
		Text = if available then `MAINTENIR POUR REBOOTER (+{gain})` else "REBOOT INDISPONIBLE",
		Variant = "Primary",
		Size = UDim2.new(1, 0, 0, 60),
		Small = true,
		Parent = holder,
	})
	key:SetEnabled(available)
	local fill: Frame = New("Frame", {
		Size = UDim2.new(0, 0, 1, -4),
		BackgroundColor3 = Style.Color("TextPrimary"),
		BackgroundTransparency = 0.75,
		BorderSizePixel = 0,
		ZIndex = 5,
		Tag = "RoundM",
		Parent = key.Button:FindFirstChild("Cap"),
	})
	local holding = false
	local started = 0
	key.Button.MouseButton1Down:Connect(function()
		if available then
			holding = true
			started = os.clock()
		end
	end)
	local function release()
		holding = false
		fill.Size = UDim2.new(0, 0, 1, -4)
	end
	key.Button.MouseButton1Up:Connect(release)
	key.Button.MouseLeave:Connect(release)
	if holdConnection then
		holdConnection:Disconnect()
	end
	holdConnection = RunService.RenderStepped:Connect(function()
		if not panel:IsOpen() then
			release()
			if holdConnection then
				holdConnection:Disconnect()
				holdConnection = nil
			end
			return
		end
		if not holding then
			return
		end
		local t = (os.clock() - started) / HOLD_SECONDS
		fill.Size = UDim2.new(math.clamp(t, 0, 1), 0, 1, -4)
		if t >= 1 then
			release()
			Net.Fire("Reboot")
			App.Close()
		end
	end)
end

local function buildSingularity(state: any)
	local data = state.Data
	local scroll = Widgets.Scroll(body, 10)
	line(scroll, 1, "> LA SINGULARITÉ", "TextTitle", 30)
	line(
		scroll,
		2,
		"Anga : « Si on termine ça… ton PC deviendra le plus puissant de l'univers. »",
		"TextMuted",
		40
	)
	if data.Zone < #Zones then
		line(scroll, 3, `Débloque {Zones[#Zones].Name} pour commencer la construction.`, "TextHeading", 40)
		return
	end
	local bits = Store.Bits()
	for index, cost in GameConfig.SingularityPhases do
		local done = data.SingularityPhase >= index
		local isNext = data.SingularityPhase + 1 == index
		local card = Widgets.Card(UDim2.new(1, -4, 0, 70), scroll, 10 + index)
		New("TextLabel", {
			Position = UDim2.fromOffset(16, 10),
			Size = UDim2.new(1, -240, 0, 24),
			BackgroundTransparency = 1,
			Text = `Phase {index} · {if done then "terminée" else NumberFormat.Compact(cost) .. " Bits"}`,
			TextXAlignment = Enum.TextXAlignment.Left,
			Tag = "TextHeading",
			Parent = card,
		})
		local bar =
			Widgets.Bar(UDim2.new(1, -240, 0, 10), Style.Color(if done then "Success" else "AccentViolet"), card)
		bar.Root.Position = UDim2.fromOffset(16, 44)
		bar:Set(if done then 1 elseif isNext then bits / cost else 0, false)
		if isNext then
			local key = Keycap.new({
				Text = "CONSTRUIRE",
				Variant = "Primary",
				Size = UDim2.fromOffset(190, 50),
				AnchorPoint = Vector2.new(1, 0.5),
				Position = UDim2.new(1, -12, 0.5, 0),
				Small = true,
				OnClick = function()
					Net.Fire("BuySingularityPhase")
				end,
				Parent = card,
			})
			key:SetEnabled(bits >= cost)
		end
	end
	if data.Singularities > 0 then
		line(
			scroll,
			30,
			`Singularités atteintes : {data.Singularities}. Fais un Reboot pour viser la Génération suivante !`,
			"TextChips",
			40
		)
	end
end

local function rebuild()
	local state = Store.State
	if not state or not panel:IsOpen() then
		return
	end
	for _, child in body:GetChildren() do
		if child:IsA("GuiObject") then
			child:Destroy()
		end
	end
	for id, key in tabKeys do
		key:SetVariant(if id == tab then "Primary" else "Secondary")
	end
	if tab == "Reboot" then
		buildReboot(state)
	else
		buildSingularity(state)
	end
end

function BiosPanel.Mount(layer: Frame)
	panel = Panel.new({
		Name = "BiosPanel",
		Title = "BIOS",
		Subtitle = "Prestige et fin de partie",
		Size = UDim2.fromScale(0.7, 0.82),
		Parent = layer,
		Accent = Style.Color("AccentViolet"),
	})
	local tabs: Frame = New("Frame", {
		Size = UDim2.new(1, 0, 0, 48),
		BackgroundTransparency = 1,
		Parent = panel.Body,
	}, {
		Create.List(Enum.FillDirection.Horizontal, 8),
	})
	for index, info in { { Id = "Reboot", Text = "Reboot" }, { Id = "Singularity", Text = "Singularité" } } do
		tabKeys[info.Id] = Keycap.new({
			Text = info.Text,
			Variant = "Secondary",
			Size = UDim2.fromOffset(170, 44),
			LayoutOrder = index,
			Small = true,
			OnClick = function()
				tab = info.Id
				rebuild()
			end,
			Parent = tabs,
		})
	end
	body = New("Frame", {
		Position = UDim2.fromOffset(0, 58),
		Size = UDim2.new(1, 0, 1, -58),
		BackgroundTransparency = 1,
		Parent = panel.Body,
	})
	-- Reconstruit seulement si ce qui est affiché change (et jamais pendant un appui long).
	local lastKey = ""
	Store.Changed:Connect(function(state: any)
		local data = state.Data
		local key =
			`{tab}|{data.SingularityPhase}|{data.Zone}|{state.FirmwarePreview}|{data.Firmware}|{data.RebootBoostPending}`
		if key ~= lastKey then
			lastKey = key
			rebuild()
		end
	end)
	App.RegisterPanel("Bios", {
		Panel = panel,
		OnOpen = function(arg: any)
			if arg == "Reboot" or arg == "Singularity" then
				tab = arg
			end
			task.defer(rebuild)
		end,
	})
end

return BiosPanel
