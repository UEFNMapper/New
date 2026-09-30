--!strict
--[[
	WorldSigns : des panneaux pour ne JAMAIS être perdu dans le PC géant (côté client).
	1. Un grand panneau flottant au-dessus de chaque zone, visible à travers les murs :
	   nom de la zone + « ouverte » ou « 🔒 prix ». Celui de la zone où l'on est est caché.
	2. Dans le hub, une étiquette au-dessus de chaque ligne lumineuse qui mène à un portail.
	Les panneaux suivent la progression du joueur local (Store).
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Workspace = game:GetService("Workspace")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Zones = require(Shared.Config.Zones)
local WorldLayout = require(Shared.Config.WorldLayout)
local NumberFormat = require(Shared.Util.NumberFormat)

local Store = require(script.Parent.Store)
local WorldFx = require(script.Parent.WorldFx)
local Create = require(script.Parent.Parent.UI.Create)
local Style = require(script.Parent.Parent.UI.Style)

local New = Create.New

local WorldSigns = {}

type Sign = { Zone: number, Gui: BillboardGui, Status: TextLabel, Card: Frame }

local signs: { Sign } = {}
local folder: Folder

local function anchor(name: string, position: Vector3): Part
	return New("Part", {
		Name = name,
		Size = Vector3.one,
		CFrame = CFrame.new(position),
		Anchored = true,
		CanCollide = false,
		CanQuery = false,
		CanTouch = false,
		Transparency = 1,
		Parent = folder,
	})
end

local function inwardOf(layout: WorldLayout.ZoneLayout): Vector3
	local delta = (layout.Spawn - layout.Gate) * Vector3.new(1, 0, 1)
	return delta.Unit
end

local function buildZoneSign(layout: WorldLayout.ZoneLayout)
	local zone = Zones[layout.Zone]
	local color = Color3.fromHex(zone.Primary)
	-- Au-dessus de la place de la zone (entre le portail et les machines), assez haut pour dépasser.
	local position = layout.Gate + inwardOf(layout) * 70 + Vector3.new(0, 48, 0)
	local gui: BillboardGui = New("BillboardGui", {
		Name = "ZoneSign",
		Size = UDim2.fromOffset(230, 66),
		AlwaysOnTop = true,
		LightInfluence = 0,
		MaxDistance = 2000,
		Parent = anchor(`Sign{layout.Zone}`, position),
	})
	local card: Frame = New("Frame", {
		Size = UDim2.fromScale(1, 1),
		BackgroundColor3 = Style.Color("BgDeep"),
		BackgroundTransparency = 0.2,
		BorderSizePixel = 0,
		Tag = "RoundM",
		Parent = gui,
	}, {
		New("UIStroke", { Color = color, Thickness = 2.5, Transparency = 0.1 }) :: Instance,
	})
	New("Frame", {
		Position = UDim2.fromOffset(10, 12),
		Size = UDim2.fromOffset(12, 12),
		BackgroundColor3 = color,
		BorderSizePixel = 0,
		Tag = "RoundPill",
		Parent = card,
	})
	New("TextLabel", {
		Position = UDim2.fromOffset(28, 4),
		Size = UDim2.new(1, -36, 0, 30),
		BackgroundTransparency = 1,
		Text = string.upper(zone.Name),
		TextScaled = true,
		TextXAlignment = Enum.TextXAlignment.Left,
		TextColor3 = Style.Color("TextPrimary"),
		Tag = "FontHeavy",
		Parent = card,
	})
	local status: TextLabel = New("TextLabel", {
		Position = UDim2.fromOffset(10, 36),
		Size = UDim2.new(1, -20, 0, 24),
		BackgroundTransparency = 1,
		Text = "",
		TextScaled = true,
		TextXAlignment = Enum.TextXAlignment.Left,
		TextColor3 = Style.Color("TextMuted"),
		Tag = "FontBold",
		Parent = card,
	})
	-- Hors du ScreenGui : on applique les règles de style (coins, polices) explicitement.
	Style.ApplyTo(gui)
	table.insert(signs, { Zone = layout.Zone, Gui = gui, Status = status, Card = card })
end

-- Étiquettes au-dessus des lignes lumineuses du hub (spawn -> portails reliés au hub).
local function buildHubLabels()
	for _, layout in WorldLayout.Zones do
		if layout.Parent == 0 then
			local zone = Zones[layout.Zone]
			local from = WorldLayout.HubSpawn * Vector3.new(1, 0, 1)
			local position = from:Lerp(layout.Gate, 0.55) + Vector3.new(0, 7, 0)
			local gui: BillboardGui = New("BillboardGui", {
				Name = "PathLabel",
				Size = UDim2.fromOffset(190, 40),
				LightInfluence = 0,
				MaxDistance = 140,
				Parent = anchor(`Path{layout.Zone}`, position),
			})
			New("TextLabel", {
				Size = UDim2.fromScale(1, 1),
				BackgroundColor3 = Color3.fromHex(zone.Primary),
				BackgroundTransparency = 0.25,
				Text = `→ {zone.Name}`,
				TextScaled = true,
				TextColor3 = Style.Color("TextPrimary"),
				TextStrokeTransparency = 0.5,
				Tag = { "FontHeavy", "RoundPill" },
				Parent = gui,
			}, { Create.Padding(6, 12) :: Instance })
			Style.ApplyTo(gui)
		end
	end
end

local function refresh()
	local data = Store.Data()
	local unlocked = if data then data.Zone else 1
	local here = WorldFx.CurrentZone
	for _, sign in signs do
		local zone = Zones[sign.Zone]
		sign.Gui.Enabled = sign.Zone ~= here
		if sign.Zone <= unlocked then
			sign.Status.Text = `✓ Ouverte · {zone.AppSection}`
			sign.Status.TextColor3 = Style.Color("Success")
			sign.Card.BackgroundTransparency = 0.2
		else
			sign.Status.Text = `🔒 {NumberFormat.Compact(zone.UnlockCost)} Bits`
			sign.Status.TextColor3 = Style.Color("CurrencyBits")
			sign.Card.BackgroundTransparency = 0.35
		end
	end
end

function WorldSigns.Start()
	folder = New("Folder", { Name = "ClientSigns", Parent = Workspace })
	for _, layout in WorldLayout.Zones do
		buildZoneSign(layout)
	end
	buildHubLabels()
	Store.Changed:Connect(refresh)
	refresh()
	-- La zone courante change sans événement Store : petit contrôle régulier.
	local lastZone = -1
	task.spawn(function()
		while true do
			task.wait(0.5)
			if WorldFx.CurrentZone ~= lastZone then
				lastZone = WorldFx.CurrentZone
				refresh()
			end
		end
	end)
end

return WorldSigns
