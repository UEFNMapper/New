--!strict
--[[
	Lagz : le visage de LAGZ, le virus méchant-mignon (aucune image à importer).
	Blob violet « glitché » (tranches magenta / cyan décalées), yeux en pixels, et une
	couronne en roue de chargement. Lagz.Face(taille, parent) renvoie le cadre racine.
]]

local Lagz = {}

Lagz.Color = Color3.fromHex("9F7AEA") -- violet de LAGZ (plaque de nom, bordures)
Lagz.Dark = Color3.fromHex("553C9A")
Lagz.Glitch = Color3.fromHex("ED64A6")
Lagz.Cyan = Color3.fromHex("4FD1C5")

local function block(parent: Instance, props: { [string]: any }): Frame
	local frame = Instance.new("Frame")
	frame.BorderSizePixel = 0
	frame.AnchorPoint = Vector2.new(0.5, 0.5)
	for key, value in props do
		if key ~= "Round" then
			(frame :: any)[key] = value
		end
	end
	local round = props.Round
	if round then
		local corner = Instance.new("UICorner")
		corner.CornerRadius = if round == true then UDim.new(1, 0) else UDim.new(round, 0)
		corner.Parent = frame
	end
	frame.Parent = parent
	return frame
end

function Lagz.Face(size: number, parent: Instance?): Frame
	local root = Instance.new("Frame")
	root.Name = "LagzFace"
	root.Size = UDim2.fromOffset(size, size)
	root.BackgroundTransparency = 1

	-- Couronne : roue de chargement (points de plus en plus pâles)
	local dots = 8
	for i = 0, dots - 1 do
		local angle = (i / dots) * math.pi * 2
		block(root, {
			Name = "Crown",
			Position = UDim2.fromScale(0.5 + math.cos(angle) * 0.16, 0.16 + math.sin(angle) * 0.12),
			Size = UDim2.fromScale(0.08, 0.08),
			BackgroundColor3 = Color3.fromHex("F6E05E"),
			BackgroundTransparency = i / dots * 0.85,
			Round = true,
		})
	end

	-- Tranches glitch derrière le corps
	block(root, {
		Position = UDim2.fromScale(0.44, 0.66),
		Size = UDim2.fromScale(0.8, 0.62),
		BackgroundColor3 = Lagz.Glitch,
		BackgroundTransparency = 0.25,
		Round = 0.3,
	})
	block(root, {
		Position = UDim2.fromScale(0.56, 0.64),
		Size = UDim2.fromScale(0.8, 0.62),
		BackgroundColor3 = Lagz.Cyan,
		BackgroundTransparency = 0.45,
		Round = 0.3,
	})
	-- Corps
	local body = block(root, {
		Name = "Body",
		Position = UDim2.fromScale(0.5, 0.65),
		Size = UDim2.fromScale(0.8, 0.62),
		BackgroundColor3 = Lagz.Color,
		Round = 0.3,
	})
	local gradient = Instance.new("UIGradient")
	gradient.Rotation = 90
	gradient.Color = ColorSequence.new(Color3.new(1, 1, 1), Color3.fromRGB(150, 130, 200))
	gradient.Parent = body
	-- Pixels « cassés » sur les bords
	for _, spot in { Vector2.new(0.14, 0.3), Vector2.new(0.9, 0.55), Vector2.new(0.2, 0.85) } do
		block(body, {
			Position = UDim2.fromScale(spot.X, spot.Y),
			Size = UDim2.fromScale(0.12, 0.12),
			BackgroundColor3 = Lagz.Glitch,
		})
	end
	-- Yeux en pixels (carrés) avec pupilles qui regardent de côté
	for _, x in { 0.32, 0.68 } do
		local eye = block(body, {
			Position = UDim2.fromScale(x, 0.42),
			Size = UDim2.fromScale(0.24, 0.3),
			BackgroundColor3 = Color3.new(1, 1, 1),
		})
		block(eye, {
			Position = UDim2.fromScale(0.62, 0.58),
			Size = UDim2.fromScale(0.5, 0.45),
			BackgroundColor3 = Color3.fromHex("1A1033"),
		})
	end
	-- Sourire en dents de scie (pixels)
	for i = 0, 4 do
		block(body, {
			Position = UDim2.fromScale(0.3 + i * 0.1, if i % 2 == 0 then 0.78 else 0.74),
			Size = UDim2.fromScale(0.09, 0.07),
			BackgroundColor3 = Color3.fromHex("1A1033"),
		})
	end
	root.Parent = parent
	return root
end

return Lagz
