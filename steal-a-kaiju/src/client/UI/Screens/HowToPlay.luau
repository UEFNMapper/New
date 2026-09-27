--!nonstrict
-- Écran « How to play » : 6 pages illustrées, accessible à tout moment.

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local TutorialConfig = require(Shared.Config.Tutorial)

local Kit = require(script.Parent.Parent.Kit)
local Audio = require(script.Parent.Parent.Parent.Controllers.Audio)

local C = Kit.Colors
local F = Kit.Fonts

local HowToPlay = {}

local window
local pageIndex = 1
local pages: { Frame } = {}
local dots: { Frame } = {}
local counter: TextLabel

local function select(index: number)
	pageIndex = ((index - 1) % #pages) + 1
	for i, page in pages do
		page.Visible = i == pageIndex
		dots[i].BackgroundColor3 = if i == pageIndex then C.Magma else C.PaperDark
	end
	counter.Text = ("%d / %d"):format(pageIndex, #pages)
	Kit.Pop(pages[pageIndex], 0.7, 0.3)
	Audio.Play("ui_tab")
end

function HowToPlay.Init()
	window = Kit.Window({ Name = "HowToPlay", Title = "HOW TO PLAY", Icon = "❓", Color = "Cyan", Size = UDim2.fromOffset(760, 480), RibbonWidth = 360 })
	local content = window.Frame
	local holder = Kit.new("Frame", { Size = UDim2.new(1, 0, 1, -70), BackgroundTransparency = 1, Parent = content })
	for i, def in TutorialConfig.HowToPlay do
		local page = Kit.new("Frame", { Size = UDim2.fromScale(1, 1), BackgroundTransparency = 1, Visible = false, Parent = holder })
		local burst = Kit.Starburst({ Size = UDim2.fromOffset(340, 340), Position = UDim2.fromScale(0.22, 0.5), Color = C.Gold, Transparency = 0.8, Parent = page })
		burst.ZIndex = 4
		local icon = Kit.Icon(def.Icon, { Size = UDim2.fromOffset(170, 170), Position = UDim2.fromScale(0.22, 0.5), AnchorPoint = Vector2.new(0.5, 0.5), ZIndex = 6, Parent = page })
		Kit.Wobble(icon, 5, 1.4)
		Kit.Chip({ Text = ("STEP %d"):format(i), Color = C.Magma, Size = UDim2.fromOffset(110, 30), Position = UDim2.new(0.44, 0, 0, 30), TextSize = 18, ZIndex = 6, Parent = page })
		Kit.Text({
			Size = UDim2.new(0.54, 0, 0, 54),
			Position = UDim2.new(0.44, 0, 0, 66),
			Text = def.Title,
			FontFace = F.Impact,
			TextColor3 = C.Ink,
			TextXAlignment = Enum.TextXAlignment.Left,
			Stroke = false,
			MaxTextSize = 50,
			ZIndex = 6,
			Parent = page,
		})
		Kit.Text({
			Size = UDim2.new(0.54, 0, 0, 200),
			Position = UDim2.new(0.44, 0, 0, 130),
			Text = def.Text,
			FontFace = F.Body,
			TextColor3 = C.InkSoft,
			TextXAlignment = Enum.TextXAlignment.Left,
			TextYAlignment = Enum.TextYAlignment.Top,
			TextWrapped = true,
			Stroke = false,
			MaxTextSize = 22,
			ZIndex = 6,
			Parent = page,
		})
		pages[i] = page
	end
	local nav = Kit.new("Frame", { Size = UDim2.new(1, 0, 0, 60), Position = UDim2.new(0, 0, 1, -60), BackgroundTransparency = 1, Parent = content })
	Kit.Button({ Text = "◀ BACK", Color = "Ink", Size = UDim2.fromOffset(150, 50), Position = UDim2.new(0, 10, 0.5, 0), AnchorPoint = Vector2.new(0, 0.5), TextSize = 22, OnClick = function() select(pageIndex - 1) end, Parent = nav })
	local next = Kit.Button({ Text = "NEXT ▶", Color = "Radioactive", Size = UDim2.fromOffset(150, 50), Position = UDim2.new(1, -10, 0.5, 0), AnchorPoint = Vector2.new(1, 0.5), TextSize = 22, OnClick = function() select(pageIndex + 1) end, Parent = nav })
	Kit.Breathe(next, 0.04, 0.8)
	local dotRow = Kit.new("Frame", { Size = UDim2.fromOffset(200, 16), Position = UDim2.new(0.5, 0, 0.5, -12), AnchorPoint = Vector2.new(0.5, 0.5), BackgroundTransparency = 1, Parent = nav }, { Kit.List(Enum.FillDirection.Horizontal, 8, Enum.HorizontalAlignment.Center, Enum.VerticalAlignment.Center) })
	for i = 1, #pages do
		dots[i] = Kit.new("Frame", { Size = UDim2.fromOffset(14, 14), BackgroundColor3 = C.PaperDark, LayoutOrder = i, Parent = dotRow }, { Kit.Round(), Kit.Stroke(2) })
	end
	counter = Kit.Text({ Size = UDim2.fromOffset(100, 20), Position = UDim2.new(0.5, 0, 0.5, 14), AnchorPoint = Vector2.new(0.5, 0.5), Text = "1 / 6", FontFace = F.Body, TextColor3 = C.InkSoft, Stroke = false, Parent = nav })
	select(1)
end

function HowToPlay.Open(args)
	if type(args) == "table" and args.Page then
		select(args.Page)
	else
		select(1)
	end
	window:Open()
end

function HowToPlay.Close()
	window:Close()
end

return HowToPlay
