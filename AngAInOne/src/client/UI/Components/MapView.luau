--!strict
--[[
	MapView : la carte du PC géant vue de dessus (nord en haut), pensée pour les enfants.
	- Une tuile par zone, à sa vraie place sur la carte mère, aux couleurs de la zone
	- Zone verrouillée : grisée + cadenas + prix ; zone où l'on se trouve : contour blanc
	- Flèche du joueur (position + direction de la caméra) et étoile de l'objectif
	Deux tailles : Compact (minimap du HUD, noms courts) et grande carte (panneau Carte).
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Zones = require(Shared.Config.Zones)
local WorldLayout = require(Shared.Config.WorldLayout)
local NumberFormat = require(Shared.Util.NumberFormat)

local Create = require(script.Parent.Parent.Create)
local Style = require(script.Parent.Parent.Style)
local Motion = require(script.Parent.Parent.Motion)
local Icon = require(script.Parent.Icon)

local New = Create.New

local MapView = {}

export type Props = {
	Parent: Instance,
	Size: UDim2,
	Position: UDim2?,
	AnchorPoint: Vector2?,
	Compact: boolean,
	OnSelect: ((zone: number) -> ())?, -- touche d'une tuile (0 = hub)
}

type Tile = {
	Zone: number,
	Button: TextButton,
	Name: TextLabel,
	Status: TextLabel?,
	Lock: Frame,
	Stroke: UIStroke,
}

export type MapView = {
	Root: Frame,
	Refresh: (self: MapView, unlockedZone: number, currentZone: number) -> (),
	SetPlayer: (self: MapView, position: Vector3?, look: Vector3?) -> (),
	SetTarget: (self: MapView, position: Vector3?) -> (),
}

local WIDTH = WorldLayout.MAX_X - WorldLayout.MIN_X
local DEPTH = WorldLayout.MAX_Z - WorldLayout.MIN_Z

-- Position monde -> position relative sur la carte (0..1, nord en haut).
local function toMap(position: Vector3): Vector2
	return Vector2.new(
		math.clamp((position.X - WorldLayout.MIN_X) / WIDTH, 0, 1),
		math.clamp((position.Z - WorldLayout.MIN_Z) / DEPTH, 0, 1)
	)
end

local function boundsOf(rects: { WorldLayout.Rect }): WorldLayout.Rect
	local minX, maxX, minZ, maxZ = math.huge, -math.huge, math.huge, -math.huge
	for _, rect in rects do
		minX = math.min(minX, rect.MinX)
		maxX = math.max(maxX, rect.MaxX)
		minZ = math.min(minZ, rect.MinZ)
		maxZ = math.max(maxZ, rect.MaxZ)
	end
	return { MinX = minX, MaxX = maxX, MinZ = minZ, MaxZ = maxZ }
end

local SHORT_NAMES: { [number]: string } = {
	[0] = "Hub",
	[1] = "Centrale",
	[2] = "RAM",
	[3] = "SSD",
	[4] = "Cryo",
	[5] = "CPU",
	[6] = "GPU",
	[7] = "IA",
}

function MapView.new(props: Props): MapView
	local compact = props.Compact
	local root: Frame = New("Frame", {
		Name = "MapView",
		Size = props.Size,
		Position = props.Position or UDim2.new(),
		AnchorPoint = props.AnchorPoint or Vector2.zero,
		BackgroundColor3 = Style.Color("BgDeep"),
		BackgroundTransparency = 0.15,
		BorderSizePixel = 0,
		ClipsDescendants = true,
		Tag = if compact then "RoundM" else "RoundL",
		Parent = props.Parent,
	}, {
		New("UIAspectRatioConstraint", { AspectRatio = WIDTH / DEPTH }) :: Instance,
		New("UIStroke", { Color = Style.Color("TextPrimary"), Transparency = 0.75, Thickness = 1.5 }),
	})
	local gap = if compact then 2 else 5

	local tiles: { Tile } = {}
	local function addTile(zone: number, rect: WorldLayout.Rect)
		local color = if zone == 0 then Style.Color("AccentViolet") else Color3.fromHex(Zones[zone].Primary)
		local topLeft = toMap(Vector3.new(rect.MinX, 0, rect.MinZ))
		local bottomRight = toMap(Vector3.new(rect.MaxX, 0, rect.MaxZ))
		local button: TextButton = New("TextButton", {
			Name = `Zone{zone}`,
			Position = UDim2.new(topLeft.X, gap, topLeft.Y, gap),
			Size = UDim2.new(bottomRight.X - topLeft.X, -gap * 2, bottomRight.Y - topLeft.Y, -gap * 2),
			BackgroundColor3 = color,
			BackgroundTransparency = 0.55,
			AutoButtonColor = false,
			Text = "",
			Active = props.OnSelect ~= nil,
			Selectable = props.OnSelect ~= nil,
			Tag = if compact then "RoundS" else "RoundM",
			Parent = root,
		})
		local stroke: UIStroke = New("UIStroke", {
			Color = color,
			Thickness = if compact then 1 else 2,
			Transparency = 0.2,
			ApplyStrokeMode = Enum.ApplyStrokeMode.Border,
			Parent = button,
		})
		local name: TextLabel = New("TextLabel", {
			AnchorPoint = Vector2.new(0.5, 0.5),
			Position = UDim2.fromScale(0.5, if compact then 0.5 else 0.36),
			Size = UDim2.fromScale(0.92, if compact then 0.5 else 0.3),
			BackgroundTransparency = 1,
			Text = if compact then SHORT_NAMES[zone] else (if zone == 0 then "HUB" else string.upper(Zones[zone].Name)),
			TextScaled = true,
			TextColor3 = Style.Color("TextPrimary"),
			TextStrokeTransparency = 0.5,
			Tag = "FontHeavy",
			Parent = button,
		}, { New("UITextSizeConstraint", { MaxTextSize = if compact then 14 else 30 }) :: Instance })
		local status: TextLabel? = nil
		if not compact then
			status = New("TextLabel", {
				AnchorPoint = Vector2.new(0.5, 0),
				Position = UDim2.fromScale(0.5, 0.56),
				Size = UDim2.fromScale(0.92, 0.22),
				BackgroundTransparency = 1,
				Text = "",
				TextScaled = true,
				TextColor3 = Style.Color("TextPrimary"),
				TextStrokeTransparency = 0.6,
				Tag = "FontBold",
				Parent = button,
			}, { New("UITextSizeConstraint", { MaxTextSize = 20 }) :: Instance })
		end
		local lock = Icon.new("Lock", if compact then 12 else 26, "TextPrimary")
		lock.AnchorPoint = Vector2.new(1, 0)
		lock.Position = UDim2.new(1, -4, 0, 4)
		lock.Parent = button
		if props.OnSelect then
			local onSelect = props.OnSelect
			button.Activated:Connect(function()
				Motion.Pop(button, 0.05)
				onSelect(zone)
			end)
		end
		table.insert(
			tiles,
			{ Zone = zone, Button = button, Name = name, Status = status, Lock = lock, Stroke = stroke }
		)
	end

	for _, layout in WorldLayout.Zones do
		addTile(layout.Zone, boundsOf(layout.Rects))
	end
	addTile(0, WorldLayout.HubRect)

	-- Objectif : étoile qui pulse
	local target: Frame = New("Frame", {
		Name = "Target",
		AnchorPoint = Vector2.new(0.5, 0.5),
		Size = UDim2.fromOffset(if compact then 18 else 34, if compact then 18 else 34),
		BackgroundTransparency = 1,
		Visible = false,
		ZIndex = 5,
		Parent = root,
	})
	local star = Icon.new("Star", if compact then 18 else 34, "CurrencyBits")
	star.ZIndex = 5
	star.Parent = target
	local pulseScale: UIScale = New("UIScale", { Parent = target })

	-- Joueur : pastille + nez qui indique la direction de la caméra
	local marker: Frame = New("Frame", {
		Name = "Player",
		AnchorPoint = Vector2.new(0.5, 0.5),
		Size = UDim2.fromOffset(if compact then 14 else 24, if compact then 14 else 24),
		BackgroundTransparency = 1,
		Visible = false,
		ZIndex = 6,
		Parent = root,
	})
	New("Frame", {
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromScale(0.5, 0.5),
		Size = UDim2.fromScale(1, 1),
		BackgroundColor3 = Style.Color("TextPrimary"),
		BorderSizePixel = 0,
		ZIndex = 6,
		Tag = "RoundPill",
		Parent = marker,
	}, { New("UIStroke", { Color = Style.Color("BrandAnga"), Thickness = if compact then 2 else 3 }) :: Instance })
	New("Frame", {
		AnchorPoint = Vector2.new(0.5, 1),
		Position = UDim2.fromScale(0.5, 0.05),
		Size = UDim2.new(0.34, 0, 0.7, 0),
		BackgroundColor3 = Style.Color("BrandAnga"),
		BorderSizePixel = 0,
		ZIndex = 7,
		Tag = "RoundPill",
		Parent = marker,
	})

	local view = {} :: any
	view.Root = root

	function view.Refresh(_self: MapView, unlockedZone: number, currentZone: number)
		for _, tile in tiles do
			local unlocked = tile.Zone <= unlockedZone
			local here = tile.Zone == currentZone
			tile.Button.BackgroundTransparency = if unlocked then (if here then 0.3 else 0.55) else 0.88
			tile.Name.TextTransparency = if unlocked then 0 else 0.35
			tile.Lock.Visible = not unlocked
			tile.Stroke.Color = if here
				then Style.Color("TextPrimary")
				else (if tile.Zone == 0
					then Style.Color("AccentViolet")
					else Color3.fromHex(Zones[tile.Zone].Primary))
			tile.Stroke.Thickness = if here then (if compact then 2 else 4) else (if compact then 1 else 2)
			tile.Stroke.Transparency = if unlocked or here then 0.1 else 0.6
			local status = tile.Status
			if status then
				if here then
					status.Text = "📍 Tu es ici"
				elseif unlocked then
					status.Text = if tile.Zone == 0
						then "Touche pour y aller"
						else `{Zones[tile.Zone].AppSection} · Y aller`
				else
					status.Text = `🔒 {NumberFormat.Compact(Zones[tile.Zone].UnlockCost)} Bits`
				end
			end
		end
	end

	function view.SetPlayer(_self: MapView, position: Vector3?, look: Vector3?)
		if not position then
			marker.Visible = false
			return
		end
		local p = toMap(position)
		marker.Position = UDim2.fromScale(p.X, p.Y)
		if look and (look.X ~= 0 or look.Z ~= 0) then
			marker.Rotation = math.deg(math.atan2(look.X, -look.Z))
		end
		marker.Visible = true
	end

	function view.SetTarget(_self: MapView, position: Vector3?)
		if not position then
			target.Visible = false
			return
		end
		local p = toMap(position)
		target.Position = UDim2.fromScale(p.X, p.Y)
		target.Visible = true
		pulseScale.Scale = 1 + math.abs(math.sin(os.clock() * 3)) * 0.3
	end

	return view :: MapView
end

return MapView
