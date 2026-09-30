--!strict
--[[
	Icon : icônes géométriques construites en Frames (aucune image à importer,
	nettes à toutes les tailles, colorées par le thème).
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Theme = require(ReplicatedStorage:WaitForChild("Shared").Config.Theme)

local Icon = {}

local function hex(name: string): Color3
	return Color3.fromHex((Theme.Colors :: any)[name])
end

local function shape(parent: Instance, props: { [string]: any }): Frame
	local frame = Instance.new("Frame")
	frame.BorderSizePixel = 0
	frame.AnchorPoint = Vector2.new(0.5, 0.5)
	for key, value in props do
		if key ~= "Round" then
			(frame :: any)[key] = value
		end
	end
	if props.Round then
		local corner = Instance.new("UICorner")
		corner.CornerRadius = if props.Round == true then UDim.new(1, 0) else UDim.new(0, props.Round)
		corner.Parent = frame
	end
	frame.Parent = parent
	return frame
end

local function ring(parent: Instance, position: UDim2, size: UDim2, color: Color3, thickness: number): Frame
	local frame = shape(parent, { Position = position, Size = size, BackgroundTransparency = 1, Round = true })
	local stroke = Instance.new("UIStroke")
	stroke.Color = color
	stroke.Thickness = thickness
	stroke.Parent = frame
	return frame
end

local function at(x: number, y: number): UDim2
	return UDim2.fromScale(x, y)
end

local function sz(w: number, h: number): UDim2
	return UDim2.fromScale(w, h)
end

-- Crée une icône `kind` de `size` px. `colorName` = token de Theme.Colors (optionnel).
function Icon.new(kind: string, size: number, colorName: string?): Frame
	local root = Instance.new("Frame")
	root.Name = `Icon_{kind}`
	root.Size = UDim2.fromOffset(size, size)
	root.BackgroundTransparency = 1
	local ink = hex(colorName or "TextPrimary")
	local dark = hex("BgDeep")
	local t = math.max(1.5, size / 14)

	if kind == "Bits" then
		shape(root, {
			Position = at(0.5, 0.5),
			Size = sz(0.72, 0.72),
			Rotation = 45,
			BackgroundColor3 = hex("CurrencyBits"),
			Round = 3,
		})
		shape(
			root,
			{ Position = at(0.5, 0.5), Size = sz(0.36, 0.36), Rotation = 45, BackgroundColor3 = dark, Round = 2 }
		)
		shape(
			root,
			{ Position = at(0.5, 0.5), Size = sz(0.14, 0.14), Rotation = 45, BackgroundColor3 = hex("CurrencyBits") }
		)
	elseif kind == "Chips" then
		shape(
			root,
			{ Position = at(0.5, 0.5), Size = sz(0.6, 0.6), BackgroundColor3 = hex("CurrencyChips"), Round = 3 }
		)
		shape(root, { Position = at(0.5, 0.5), Size = sz(0.3, 0.3), BackgroundColor3 = dark, Round = 2 })
		for i = -1, 1 do
			for _, side in { 0.08, 0.92 } do
				shape(root, {
					Position = at(0.5 + i * 0.18, side),
					Size = sz(0.08, 0.16),
					BackgroundColor3 = hex("CurrencyChips"),
				})
				shape(root, {
					Position = at(side, 0.5 + i * 0.18),
					Size = sz(0.16, 0.08),
					BackgroundColor3 = hex("CurrencyChips"),
				})
			end
		end
	elseif kind == "Bolt" then
		shape(
			root,
			{ Position = at(0.58, 0.3), Size = sz(0.18, 0.5), Rotation = 25, BackgroundColor3 = ink, Round = 2 }
		)
		shape(
			root,
			{ Position = at(0.5, 0.5), Size = sz(0.5, 0.14), Rotation = -20, BackgroundColor3 = ink, Round = 2 }
		)
		shape(
			root,
			{ Position = at(0.42, 0.7), Size = sz(0.18, 0.5), Rotation = 25, BackgroundColor3 = ink, Round = 2 }
		)
	elseif kind == "Heat" then
		shape(root, { Position = at(0.5, 0.4), Size = sz(0.26, 0.62), BackgroundColor3 = ink, Round = true })
		shape(root, { Position = at(0.5, 0.74), Size = sz(0.44, 0.44), BackgroundColor3 = ink, Round = true })
		shape(root, { Position = at(0.5, 0.45), Size = sz(0.1, 0.4), BackgroundColor3 = dark, Round = true })
	elseif kind == "Cpu" then
		shape(root, { Position = at(0.5, 0.5), Size = sz(0.56, 0.56), BackgroundColor3 = ink, Round = 3 })
		shape(root, { Position = at(0.5, 0.5), Size = sz(0.26, 0.26), BackgroundColor3 = dark, Round = 1 })
		for i = -1, 1 do
			for _, side in { 0.1, 0.9 } do
				shape(root, { Position = at(0.5 + i * 0.16, side), Size = sz(0.07, 0.14), BackgroundColor3 = ink })
				shape(root, { Position = at(side, 0.5 + i * 0.16), Size = sz(0.14, 0.07), BackgroundColor3 = ink })
			end
		end
	elseif kind == "Bot" then
		shape(root, { Position = at(0.5, 0.56), Size = sz(0.7, 0.56), BackgroundColor3 = ink, Round = 5 })
		shape(root, { Position = at(0.36, 0.56), Size = sz(0.14, 0.14), BackgroundColor3 = dark, Round = true })
		shape(root, { Position = at(0.64, 0.56), Size = sz(0.14, 0.14), BackgroundColor3 = dark, Round = true })
		shape(root, { Position = at(0.5, 0.18), Size = sz(0.06, 0.2), BackgroundColor3 = ink })
		shape(root, { Position = at(0.5, 0.1), Size = sz(0.16, 0.16), BackgroundColor3 = ink, Round = true })
	elseif kind == "Quest" then
		shape(root, { Position = at(0.5, 0.52), Size = sz(0.62, 0.76), BackgroundColor3 = ink, Round = 3 })
		for i = 0, 2 do
			shape(
				root,
				{ Position = at(0.54, 0.36 + i * 0.16), Size = sz(0.34, 0.07), BackgroundColor3 = dark, Round = true }
			)
			shape(
				root,
				{ Position = at(0.31, 0.36 + i * 0.16), Size = sz(0.08, 0.08), BackgroundColor3 = dark, Round = true }
			)
		end
	elseif kind == "Shop" then
		ring(root, at(0.5, 0.3), sz(0.36, 0.36), ink, t)
		shape(root, { Position = at(0.5, 0.62), Size = sz(0.7, 0.52), BackgroundColor3 = ink, Round = 4 })
	elseif kind == "Menu" then
		for i = -1, 1 do
			shape(
				root,
				{ Position = at(0.5, 0.5 + i * 0.24), Size = sz(0.7, 0.1), BackgroundColor3 = ink, Round = true }
			)
		end
	elseif kind == "Close" then
		shape(
			root,
			{ Position = at(0.5, 0.5), Size = sz(0.7, 0.12), Rotation = 45, BackgroundColor3 = ink, Round = true }
		)
		shape(
			root,
			{ Position = at(0.5, 0.5), Size = sz(0.7, 0.12), Rotation = -45, BackgroundColor3 = ink, Round = true }
		)
	elseif kind == "Elevator" then
		shape(root, { Position = at(0.5, 0.5), Size = sz(0.12, 0.6), BackgroundColor3 = ink, Round = true })
		shape(root, { Position = at(0.5, 0.2), Size = sz(0.3, 0.3), Rotation = 45, BackgroundColor3 = ink, Round = 2 })
		shape(root, { Position = at(0.5, 0.8), Size = sz(0.3, 0.3), Rotation = 45, BackgroundColor3 = ink, Round = 2 })
	elseif kind == "Lock" then
		ring(root, at(0.5, 0.34), sz(0.42, 0.42), ink, t)
		shape(root, { Position = at(0.5, 0.64), Size = sz(0.66, 0.46), BackgroundColor3 = ink, Round = 3 })
		shape(root, { Position = at(0.5, 0.64), Size = sz(0.1, 0.18), BackgroundColor3 = dark, Round = true })
	elseif kind == "Gift" then
		shape(root, { Position = at(0.5, 0.6), Size = sz(0.7, 0.56), BackgroundColor3 = ink, Round = 3 })
		shape(root, { Position = at(0.5, 0.6), Size = sz(0.12, 0.56), BackgroundColor3 = dark })
		shape(root, { Position = at(0.5, 0.32), Size = sz(0.8, 0.14), BackgroundColor3 = ink, Round = 2 })
		shape(
			root,
			{ Position = at(0.38, 0.18), Size = sz(0.22, 0.16), Rotation = -30, BackgroundColor3 = ink, Round = true }
		)
		shape(
			root,
			{ Position = at(0.62, 0.18), Size = sz(0.22, 0.16), Rotation = 30, BackgroundColor3 = ink, Round = true }
		)
	elseif kind == "Download" then
		shape(root, { Position = at(0.5, 0.38), Size = sz(0.14, 0.5), BackgroundColor3 = ink, Round = true })
		shape(
			root,
			{ Position = at(0.5, 0.6), Size = sz(0.34, 0.34), Rotation = 45, BackgroundColor3 = ink, Round = 2 }
		)
		shape(root, { Position = at(0.5, 0.9), Size = sz(0.76, 0.1), BackgroundColor3 = ink, Round = true })
	elseif kind == "Star" then
		shape(root, { Position = at(0.5, 0.5), Size = sz(0.6, 0.6), BackgroundColor3 = ink, Round = 2 })
		shape(root, { Position = at(0.5, 0.5), Size = sz(0.6, 0.6), Rotation = 45, BackgroundColor3 = ink, Round = 2 })
	elseif kind == "Power" then
		ring(root, at(0.5, 0.55), sz(0.66, 0.66), ink, t * 1.3)
		shape(root, { Position = at(0.5, 0.3), Size = sz(0.28, 0.3), BackgroundColor3 = dark })
		shape(root, { Position = at(0.5, 0.3), Size = sz(0.12, 0.42), BackgroundColor3 = ink, Round = true })
	elseif kind == "Check" then
		shape(
			root,
			{ Position = at(0.36, 0.6), Size = sz(0.36, 0.12), Rotation = 45, BackgroundColor3 = ink, Round = true }
		)
		shape(
			root,
			{ Position = at(0.6, 0.48), Size = sz(0.6, 0.12), Rotation = -50, BackgroundColor3 = ink, Round = true }
		)
	elseif kind == "Heart" then
		shape(root, { Position = at(0.36, 0.4), Size = sz(0.42, 0.42), BackgroundColor3 = ink, Round = true })
		shape(root, { Position = at(0.64, 0.4), Size = sz(0.42, 0.42), BackgroundColor3 = ink, Round = true })
		shape(
			root,
			{ Position = at(0.5, 0.58), Size = sz(0.44, 0.44), Rotation = 45, BackgroundColor3 = ink, Round = 2 }
		)
	elseif kind == "Trophy" then
		shape(root, { Position = at(0.5, 0.36), Size = sz(0.56, 0.46), BackgroundColor3 = ink, Round = 6 })
		shape(root, { Position = at(0.5, 0.7), Size = sz(0.12, 0.2), BackgroundColor3 = ink })
		shape(root, { Position = at(0.5, 0.86), Size = sz(0.46, 0.1), BackgroundColor3 = ink, Round = 2 })
	else
		shape(root, { Position = at(0.5, 0.5), Size = sz(0.5, 0.5), BackgroundColor3 = ink, Round = true })
	end
	return root
end

return Icon
