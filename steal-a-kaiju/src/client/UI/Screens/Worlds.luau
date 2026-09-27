--!nonstrict
-- Carte du monde : les 5 mondes, leurs œufs, leurs kaijus, leurs conditions
-- (niveau, évolution, péage) et le voyage en un clic.

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Worlds = require(Shared.Config.Worlds)
local Rarities = require(Shared.Config.Rarities)
local Mutations = require(Shared.Config.Mutations)
local Kaijus = require(Shared.Config.Kaijus)
local Roll = require(Shared.Logic.Roll)
local Format = require(Shared.Logic.Format)

local Kit = require(script.Parent.Parent.Kit)
local Viewport = require(script.Parent.Parent.Viewport)
local Controllers = script.Parent.Parent.Parent.Controllers
local State = require(Controllers.State)
local Remote = require(Controllers.Remote)
local Audio = require(Controllers.Audio)
local UIRegistry = require(Controllers.UIRegistry)
local CameraFx = require(Controllers.CameraFx)

local C = Kit.Colors
local F = Kit.Fonts

local WorldsScreen = {}

local window
local selected = Worlds.Default
local tabs: { [string]: { Button: GuiObject, Lock: TextLabel } } = {}
local ui: { [string]: any } = {}
local viewports = {}

-- État d'un monde pour le joueur : "Open" | "Buy" | "Locked"
local function stateOf(world: Worlds.World): string
	local unlocked = State.Get("Worlds") or {}
	if unlocked[world.Id] then
		return "Open"
	end
	local level = State.Get("Level") or 1
	local rebirths = State.Get("Rebirths") or 0
	if Worlds.MeetsGate(world, level, rebirths) then
		return "Buy"
	end
	return "Locked"
end

-- Nombre de mondes que le joueur peut ouvrir maintenant (badge du HUD).
function WorldsScreen.UnlockableCount(): number
	local n = 0
	local cash = State.Get("Cash") or 0
	for _, w in Worlds.List do
		if stateOf(w) == "Buy" and cash >= w.Toll then
			n += 1
		end
	end
	return n
end

local function requirementChip(parent: Instance, order: number, text: string, ok: boolean)
	local chip = Kit.Chip({
		Text = (if ok then "✓ " else "✗ ") .. text,
		Color = if ok then C.RadioactiveDark else C.Red:Lerp(C.Ink, 0.3),
		Size = UDim2.fromOffset(150, 32),
		Parent = parent,
	})
	chip.LayoutOrder = order
	return chip
end

local function refresh()
	if not ui.Title then
		return
	end
	local world = Worlds.Get(selected)
	local pal = world.Palette
	local level = State.Get("Level") or 1
	local rebirths = State.Get("Rebirths") or 0
	local cash = State.Get("Cash") or 0

	-- onglets
	for id, tab in tabs do
		local w = Worlds.Get(id)
		local st = stateOf(w)
		tab.Lock.Text = if st == "Open" then "" elseif st == "Buy" then "!" else "🔒"
		tab.Lock.TextColor3 = if st == "Buy" then C.Gold else C.Paper
		Kit.SetButtonColor(tab.Button, if id == selected then "Magma" else "Ink")
	end

	ui.Title.Text = string.upper(world.Name)
	ui.Title.TextColor3 = pal.Glow
	ui.Tagline.Text = world.Tagline
	Kit.SetIcon(ui.Icon, world.Icon)
	ui.Hero.BackgroundColor3 = pal.Rock
	ui.HeroGradient.Color = ColorSequence.new(pal.Glow:Lerp(C.Ink, 0.2), pal.Rock:Lerp(C.Ink, 0.5))

	-- kaijus natifs (silhouettes tant qu'ils ne sont pas découverts)
	local index = State.Get("Index") or {}
	for i, vp in viewports do
		local id = world.Species[i]
		vp.Frame.Visible = id ~= nil
		if id then
			vp.View:Set(id, nil)
			vp.View:SetSilhouette(index[id] == nil)
			local s = Kaijus.Get(id)
			vp.Name.Text = if index[id] and s then s.Name else "???"
			vp.Name.TextColor3 = if s then Rarities.Get(s.Rarity).Color else C.Paper
		end
	end

	-- chances des œufs
	local odds = Roll.RarityOdds(State.Get("Luck") or 1, world.Id)
	local rows = 0
	for _, r in Rarities.List do
		local p = odds[r.Id] or 0
		if p > 0 then
			rows += 1
			local row = ui.OddRows[rows]
			if row then
				row.Frame.Visible = true
				row.Label.Text = r.Name
				row.Label.TextColor3 = r.Color
				row.Pct.Text = Format.Percent(p)
				row.Fill.BackgroundColor3 = r.Color
				row.Fill.Size = UDim2.fromScale(math.clamp(p ^ 0.5, 0.02, 1), 1)
			end
		end
	end
	for i = rows + 1, #ui.OddRows do
		ui.OddRows[i].Frame.Visible = false
	end
	local mutationNames = {}
	for _, m in world.Mutations do
		local def = Mutations.Get(m.Id)
		if def then
			table.insert(mutationNames, ("%s x%d"):format(def.Name, def.Mult))
		end
	end
	ui.Mutation.Text = if #mutationNames > 0 then "✨ Local mutation: " .. table.concat(mutationNames, ", ") else "✨ Starter world: all the basics"

	-- conditions
	for _, child in ui.Reqs:GetChildren() do
		if child:IsA("GuiObject") then
			child:Destroy()
		end
	end
	local st = stateOf(world)
	if st ~= "Open" then
		requirementChip(ui.Reqs, 1, ("LEVEL %d"):format(world.Level), level >= world.Level)
		if world.Rebirths > 0 then
			requirementChip(ui.Reqs, 2, ("EVOLUTION %d"):format(world.Rebirths), rebirths >= world.Rebirths)
		end
		requirementChip(ui.Reqs, 3, Format.Cash(world.Toll), cash >= world.Toll)
	end

	local where = State.Get("WorldAt") or ""
	if st == "Open" then
		local here = where == world.Id
		Kit.SetButtonText(ui.Action, if here then "YOU ARE HERE" else "TRAVEL!")
		Kit.SetButtonColor(ui.Action, if here then "Grey" else "Radioactive")
		Kit.SetDisabled(ui.Action, here)
	elseif st == "Buy" then
		Kit.SetButtonText(ui.Action, "UNLOCK " .. Format.Cash(world.Toll))
		Kit.SetButtonColor(ui.Action, if cash >= world.Toll then "Gold" else "Grey")
		Kit.SetDisabled(ui.Action, false)
	else
		local need = if level < world.Level then ("REACH LEVEL %d"):format(world.Level) else ("REACH EVOLUTION %d"):format(world.Rebirths)
		Kit.SetButtonText(ui.Action, "🔒 " .. need)
		Kit.SetButtonColor(ui.Action, "Grey")
		Kit.SetDisabled(ui.Action, true)
	end
end

local function select(id: string)
	selected = id
	refresh()
	Kit.Pop(ui.Detail, 0.9, 0.25)
end

local function act()
	local world = Worlds.Get(selected)
	local st = stateOf(world)
	if st == "Open" then
		local r = Remote.Call("Travel", { Id = world.Id })
		if r.ok then
			window:Close()
		end
	elseif st == "Buy" then
		local r = Remote.Call("UnlockWorld", { Id = world.Id })
		if r.ok then
			Audio.Play("rebirth")
			CameraFx.FovPunch(-8, 0.6)
			refresh()
		end
	end
end

function WorldsScreen.Init()
	window = Kit.Window({ Name = "Worlds", Title = "WORLD MAP", Icon = "🗺️", Color = "Cyan", Size = UDim2.fromOffset(900, 500), RibbonWidth = 360 })
	local content = window.Frame

	-- colonne des mondes
	local list = Kit.new("Frame", {
		Size = UDim2.new(0, 230, 1, -10),
		BackgroundTransparency = 1,
		Parent = content,
	}, { Kit.List(Enum.FillDirection.Vertical, 10, Enum.HorizontalAlignment.Center, Enum.VerticalAlignment.Top) })
	for i, w in Worlds.List do
		local button = Kit.Button({
			Name = w.Id,
			Text = string.upper(w.Name),
			Icon = w.Icon,
			IconSize = 34,
			TextSize = 19,
			Color = "Ink",
			Size = UDim2.fromOffset(220, 70),
			LayoutOrder = i,
			Sound = "ui_tab",
			Parent = list,
			OnClick = function()
				select(w.Id)
			end,
		})
		local lock = Kit.Text({
			Name = "Lock",
			Size = UDim2.fromOffset(34, 34),
			Position = UDim2.new(1, 8, 0, -8),
			AnchorPoint = Vector2.new(1, 0),
			Text = "",
			FontFace = F.Title,
			MaxTextSize = 26,
			ZIndex = 20,
			Parent = button,
		})
		tabs[w.Id] = { Button = button, Lock = lock }
	end

	-- détail du monde sélectionné
	local detail = Kit.new("Frame", {
		Name = "Detail",
		Size = UDim2.new(1, -250, 1, -10),
		Position = UDim2.fromOffset(250, 0),
		BackgroundTransparency = 1,
		Parent = content,
	})
	ui.Detail = detail
	local hero = Kit.new("Frame", {
		Name = "Hero",
		Size = UDim2.new(1, 0, 0, 200),
		BackgroundColor3 = C.Ink,
		Parent = detail,
	}, { Kit.Corner(16), Kit.Stroke(4) })
	ui.Hero = hero
	ui.HeroGradient = Kit.new("UIGradient", { Rotation = 90, Parent = hero })
	ui.Icon = Kit.Icon("worlds", { Size = UDim2.fromOffset(84, 84), Position = UDim2.fromOffset(14, 12), ZIndex = 4, Parent = hero })
	Kit.Wobble(ui.Icon, 6, 1.2)
	ui.Title = Kit.Text({
		Size = UDim2.new(1, -120, 0, 50),
		Position = UDim2.fromOffset(108, 14),
		Text = "",
		FontFace = F.Title,
		TextXAlignment = Enum.TextXAlignment.Left,
		MaxTextSize = 44,
		ZIndex = 4,
		Parent = hero,
	})
	ui.Tagline = Kit.Text({
		Size = UDim2.new(1, -120, 0, 26),
		Position = UDim2.fromOffset(108, 62),
		Text = "",
		FontFace = F.Body,
		TextColor3 = C.Paper,
		TextXAlignment = Enum.TextXAlignment.Left,
		MaxTextSize = 20,
		ZIndex = 4,
		Parent = hero,
	})
	-- 4 kaijus natifs
	local strip = Kit.new("Frame", {
		Size = UDim2.new(1, -20, 0, 100),
		Position = UDim2.new(0, 10, 1, -104),
		BackgroundTransparency = 1,
		ZIndex = 4,
		Parent = hero,
	}, { Kit.List(Enum.FillDirection.Horizontal, 8, Enum.HorizontalAlignment.Left, Enum.VerticalAlignment.Center) })
	for i = 1, 6 do
		local cell = Kit.new("Frame", { Size = UDim2.fromOffset(92, 100), BackgroundTransparency = 1, LayoutOrder = i, ZIndex = 4, Parent = strip })
		local view = Viewport.new({ Species = "Gloop", Size = UDim2.fromOffset(84, 76), Position = UDim2.fromScale(0.5, 0), AnchorPoint = Vector2.new(0.5, 0), ZIndex = 5, Parent = cell })
		local name = Kit.Text({ Size = UDim2.new(1, 0, 0, 20), Position = UDim2.new(0, 0, 1, -22), Text = "???", FontFace = F.Title, MaxTextSize = 15, ZIndex = 6, Parent = cell })
		viewports[i] = { Frame = cell, View = view, Name = name }
	end

	-- chances des œufs
	local oddsPanel = Kit.new("Frame", {
		Size = UDim2.new(0.55, -8, 0, 206),
		Position = UDim2.fromOffset(0, 212),
		BackgroundColor3 = C.PaperDark,
		Parent = detail,
	}, { Kit.Corner(12), Kit.Stroke(3) })
	Kit.Text({ Size = UDim2.new(1, -20, 0, 26), Position = UDim2.fromOffset(10, 6), Text = "☄️ EGG ODDS", FontFace = F.Title, TextColor3 = C.Ink, Stroke = false, TextXAlignment = Enum.TextXAlignment.Left, MaxTextSize = 20, Parent = oddsPanel })
	local rowsHolder = Kit.new("Frame", {
		Size = UDim2.new(1, -20, 1, -40),
		Position = UDim2.fromOffset(10, 34),
		BackgroundTransparency = 1,
		Parent = oddsPanel,
	}, { Kit.List(Enum.FillDirection.Vertical, 4) })
	ui.OddRows = {}
	for i = 1, 6 do
		local row = Kit.new("Frame", { Size = UDim2.new(1, 0, 0, 24), BackgroundTransparency = 1, LayoutOrder = i, Parent = rowsHolder })
		local label = Kit.Text({ Size = UDim2.new(0, 96, 1, 0), Text = "", FontFace = F.Title, TextXAlignment = Enum.TextXAlignment.Left, Stroke = 2, MaxTextSize = 17, Parent = row })
		local track = Kit.new("Frame", { Size = UDim2.new(1, -170, 0, 14), Position = UDim2.new(0, 100, 0.5, 0), AnchorPoint = Vector2.new(0, 0.5), BackgroundColor3 = C.Ink, Parent = row }, { Kit.Round() })
		local fill = Kit.new("Frame", { Size = UDim2.fromScale(0.5, 1), BackgroundColor3 = C.Gold, Parent = track }, { Kit.Round() })
		local pct = Kit.Text({ Size = UDim2.new(0, 64, 1, 0), Position = UDim2.new(1, 0, 0, 0), AnchorPoint = Vector2.new(1, 0), Text = "", FontFace = F.Body, TextColor3 = C.Ink, Stroke = false, TextXAlignment = Enum.TextXAlignment.Right, MaxTextSize = 16, Parent = row })
		ui.OddRows[i] = { Frame = row, Label = label, Fill = fill, Pct = pct }
	end

	-- conditions + action
	local side = Kit.new("Frame", {
		Size = UDim2.new(0.45, -8, 0, 206),
		Position = UDim2.new(0.55, 8, 0, 212),
		BackgroundTransparency = 1,
		Parent = detail,
	})
	ui.Mutation = Kit.Text({
		Size = UDim2.new(1, 0, 0, 44),
		Text = "",
		FontFace = F.Body,
		TextColor3 = C.Ink,
		Stroke = false,
		TextWrapped = true,
		TextXAlignment = Enum.TextXAlignment.Left,
		MaxTextSize = 17,
		Parent = side,
	})
	ui.Reqs = Kit.new("Frame", {
		Size = UDim2.new(1, 0, 0, 76),
		Position = UDim2.fromOffset(0, 48),
		BackgroundTransparency = 1,
		Parent = side,
	}, { Kit.new("UIGridLayout", { CellSize = UDim2.fromOffset(150, 32), CellPadding = UDim2.fromOffset(8, 8), SortOrder = Enum.SortOrder.LayoutOrder }) })
	ui.Action = Kit.Button({
		Name = "Action",
		Text = "TRAVEL!",
		Icon = "🌀",
		IconSize = 30,
		TextSize = 26,
		Color = "Radioactive",
		Size = UDim2.new(1, 0, 0, 70),
		Position = UDim2.new(0, 0, 1, -72),
		Sound = "ui_click",
		Parent = side,
		OnClick = act,
	})

	for _, key in { "Worlds", "Level", "Rebirths", "Cash", "Index", "Luck" } do
		State.Observe(key, function()
			if window.IsOpen then
				refresh()
			end
		end)
	end
	UIRegistry.OpenWorld = function(id: string?)
		WorldsScreen.Open(id)
	end
end

function WorldsScreen.Open(id: string?)
	if id and Worlds.ById[id] then
		selected = id
	else
		-- par défaut : le prochain monde à ouvrir, sinon le meilleur ouvert
		local unlocked = State.Get("Worlds") or {}
		selected = Worlds.Default
		for _, w in Worlds.List do
			if not unlocked[w.Id] then
				selected = w.Id
				break
			end
			selected = w.Id
		end
	end
	window:Open()
	refresh()
end

function WorldsScreen.Close()
	window:Close()
end

return WorldsScreen
