--!strict
--[[
	Defrag : "Défrag" (monde 3, Data Vault). Corrupto a éparpillé les fichiers sur le
	disque : échange les blocs pour que chaque fichier soit d'un seul morceau (les blocs
	de même couleur se touchent), avant d'être à court de coups ou de temps.

	Contrôles :
	- doigt / souris : glisser un bloc sur une autre case, ou toucher un bloc puis une case
	- clavier : flèches / ZQSD / WASD pour viser, Espace ou Entrée pour prendre / poser,
	  Retour arrière pour annuler
	- manette : croix ou stick pour viser, A pour prendre / poser, B pour annuler
	Règles et chiffres : DefragLogic (pur, testé).
]]

local GuiService = game:GetService("GuiService")
local UserInputService = game:GetService("UserInputService")

local Create = require(script.Parent.Parent.Create)
local Motion = require(script.Parent.Parent.Motion)
local Style = require(script.Parent.Parent.Style)
local Core = require(script.Parent.Core)
local Common = require(script.Parent.Common)
local DefragLogic = require(script.Parent.DefragLogic)

local New = Create.New
local C = Common.Colors
local At = Common.At
local Box = Common.Box

local Defrag = {}

-- Types de fichiers (DefragLogic.MAX_FILES) : extension + couleur. L'extension écrite sur
-- chaque bloc aide aussi les joueurs qui distinguent mal les couleurs.
local FILES = table.freeze({
	{ Name = "IMG", Color = "AccentCyan" },
	{ Name = "MP3", Color = "AccentAmber" },
	{ Name = "DOC", Color = "Success" },
	{ Name = "JEU", Color = "AccentViolet" },
	{ Name = "VID", Color = "BrandAnga" },
})

local MOVES: { [Enum.KeyCode]: { number } } = {
	[Enum.KeyCode.Left] = { -1, 0 },
	[Enum.KeyCode.A] = { -1, 0 },
	[Enum.KeyCode.Q] = { -1, 0 },
	[Enum.KeyCode.DPadLeft] = { -1, 0 },
	[Enum.KeyCode.Right] = { 1, 0 },
	[Enum.KeyCode.D] = { 1, 0 },
	[Enum.KeyCode.DPadRight] = { 1, 0 },
	[Enum.KeyCode.Up] = { 0, -1 },
	[Enum.KeyCode.W] = { 0, -1 },
	[Enum.KeyCode.Z] = { 0, -1 },
	[Enum.KeyCode.DPadUp] = { 0, -1 },
	[Enum.KeyCode.Down] = { 0, 1 },
	[Enum.KeyCode.S] = { 0, 1 },
	[Enum.KeyCode.DPadDown] = { 0, 1 },
}
local PICK_KEYS = {
	[Enum.KeyCode.ButtonA] = true,
	[Enum.KeyCode.Space] = true,
	[Enum.KeyCode.Return] = true,
	[Enum.KeyCode.KeypadEnter] = true,
}
local CANCEL_KEYS = {
	[Enum.KeyCode.ButtonB] = true,
	[Enum.KeyCode.Backspace] = true,
}
local STICK_PUSH, STICK_RELEASE = 0.6, 0.3
local DRAG_START = 18 -- unités avant qu'un appui devienne un glisser

function Defrag.Info(difficulty: number, device: Common.Device): Common.Info
	local p = DefragLogic.Params(difficulty)
	return {
		Title = "DÉFRAG",
		Rule = "Échange les blocs : chaque couleur doit être collée !",
		Target = `Répare {p.Files} fichiers !`,
		Controls = if device == "Gamepad"
			then "Croix pour viser, A pour prendre puis poser"
			elseif device == "Touch" then "Glisse un bloc sur une case (ou tape, puis tape)"
			else "Glisse les blocs à la souris, ou flèches + Espace",
		Tip = "Astuce : choisis où ranger chaque couleur avant de bouger !",
		Goal = p.Files,
		Unit = "fichiers",
		Icon = "Check",
		Accent = "AccentCyan",
	}
end

-- Bloc de fichier (carré arrondi coloré + extension). Taille en échelle du parent.
local function buildBlock(parent: Instance, file: number, size: UDim2, position: UDim2, zIndex: number): Frame
	local def = FILES[file] or FILES[1]
	local color = Style.Color(def.Color)
	local block: Frame = New("Frame", {
		Name = `Block{file}`,
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = position,
		Size = size,
		BackgroundColor3 = C.White,
		BorderSizePixel = 0,
		ZIndex = zIndex,
		Parent = parent,
	}, {
		Common.Corner(UDim.new(0.18, 0)),
		New("UIGradient", { Rotation = 90, Color = ColorSequence.new(color:Lerp(C.White, 0.35), color) }),
	})
	New("UIStroke", { Name = "Edge", Color = color:Lerp(C.Ink, 0.45), Thickness = 2, Parent = block })
	-- Petite étiquette + "lignes de données"
	New("TextLabel", {
		Name = "Ext",
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromScale(0.5, 0.4),
		Size = UDim2.fromScale(0.8, 0.36),
		BackgroundTransparency = 1,
		Text = def.Name,
		TextScaled = true,
		TextColor3 = C.Ink,
		Tag = "FontHeavy",
		ZIndex = zIndex + 1,
		Parent = block,
	}, { New("UITextSizeConstraint", { MaxTextSize = 26, MinTextSize = 8 }) })
	for i = 0, 1 do
		Common.Shape(
			block,
			UDim2.fromScale(0.5, 0.7 + i * 0.12),
			UDim2.fromScale(0.6 - i * 0.2, 0.06),
			C.Ink,
			UDim.new(1, 0),
			{
				Name = "Line",
				BackgroundTransparency = 0.55,
				ZIndex = zIndex + 1,
			}
		)
	end
	return block
end

-- Flèche "->" en Frames (illustration).
local function arrow(parent: Instance, position: UDim2)
	local root: Frame = New("Frame", {
		Name = "Arrow",
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = position,
		Size = UDim2.fromOffset(60, 30),
		BackgroundTransparency = 1,
		Parent = parent,
	})
	Common.Shape(root, UDim2.fromScale(0.42, 0.5), UDim2.fromScale(0.74, 0.22), C.Gold, UDim.new(1, 0))
	for _, angle in { 40, -40 } do
		Common.Shape(
			root,
			UDim2.fromScale(0.8, 0.5 + (if angle > 0 then -0.18 else 0.18)),
			UDim2.fromScale(0.44, 0.2),
			C.Gold,
			UDim.new(1, 0),
			{
				Rotation = angle,
			}
		)
	end
	Common.Pulse(root, { Position = position + UDim2.fromOffset(8, 0) }, 0.5)
end

function Defrag.Illustrate(parent: Frame)
	-- Avant (éparpillé) -> après (regroupé), sur un mini disque 4 x 2.
	local before = { 1, 0, 2, 1, 2, 1, 0, 2 }
	local after = { 1, 1, 0, 2, 1, 0, 2, 2 }
	for g, cells in { before, after } do
		local grid: Frame = New("Frame", {
			Name = if g == 1 then "Before" else "After",
			AnchorPoint = Vector2.new(0.5, 0.5),
			Position = UDim2.fromScale(if g == 1 then 0.26 else 0.74, 0.5),
			Size = UDim2.fromOffset(200, 100),
			BackgroundColor3 = C.Ink,
			BackgroundTransparency = 0.3,
			BorderSizePixel = 0,
			Parent = parent,
		}, { Common.Corner(UDim.new(0, 10)) })
		for index, file in cells do
			local col, row = (index - 1) % 4, (index - 1) // 4
			local position = UDim2.fromScale((col + 0.5) / 4, (row + 0.5) / 2)
			if file > 0 then
				buildBlock(grid, file, UDim2.fromScale(0.23, 0.46), position, 2)
			end
		end
		if g == 2 then
			New("UIStroke", { Color = C.Good, Thickness = 3, Parent = grid })
		end
	end
	arrow(parent, UDim2.fromScale(0.5, 0.5))
end

type BlockView = { Frame: Frame, File: number }

function Defrag.Run(container: Frame, difficulty: number, finish: Common.Finish, hud: Common.Hud?): () -> ()
	local ui = hud or Common.NullHud
	local bin = Common.Bin()
	local sim = DefragLogic.new(difficulty, Common.Seed())
	local p = sim.Params
	local total = p.Cols * p.Rows
	local finished = false
	local cellSize, originX, originY = DefragLogic.Layout(p)

	local stage = Common.Stage(container)
	bin:Add(stage)
	local catcher = Common.Catcher(stage)

	local function center(index: number): UDim2
		local x, y = DefragLogic.CellCenter(p, index)
		return At(x, y)
	end

	-- Disque : fond + cases (secteurs)
	New("Frame", {
		Name = "Disk",
		Position = At(originX - 8, originY - 8),
		Size = Box(cellSize * p.Cols + 16, cellSize * p.Rows + 16),
		BackgroundColor3 = C.Ink,
		BackgroundTransparency = 0.25,
		BorderSizePixel = 0,
		ZIndex = 2,
		Parent = stage,
	}, {
		Common.Corner(UDim.new(0, 14)),
		New("UIStroke", { Color = C.Cyan, Thickness = 2, Transparency = 0.5 }),
	})
	local slots: { Frame } = {}
	for index = 1, total do
		slots[index] =
			Common.Shape(stage, center(index), Box(cellSize * 0.92, cellSize * 0.92), C.Screen, UDim.new(0.16, 0), {
				Name = `Slot{index}`,
				BackgroundTransparency = 0.1,
				ZIndex = 3,
			})
		New("UIStroke", { Color = C.Cyan, Thickness = 1, Transparency = 0.75, Parent = slots[index] })
	end

	-- Calque des blocs (au-dessus des cases) et repères de sélection
	local layer: Frame = New("Frame", {
		Name = "Blocks",
		Size = UDim2.fromScale(1, 1),
		BackgroundTransparency = 1,
		ZIndex = 4,
		Parent = stage,
	})
	local blockSize = Box(cellSize * 0.84, cellSize * 0.84)
	local blocks: { [number]: BlockView } = {}
	for index, file in sim.Solved do
		if file > 0 then
			blocks[index] = { Frame = buildBlock(layer, file, blockSize, center(index), 2), File = file }
		end
	end
	local function marker(color: Color3, thickness: number, name: string): (Frame, UIStroke)
		local frame = Common.Shape(stage, center(1), Box(cellSize * 0.98, cellSize * 0.98), color, UDim.new(0.18, 0), {
			Name = name,
			BackgroundTransparency = 1,
			Visible = false,
			ZIndex = 6,
		})
		local stroke: UIStroke = New("UIStroke", { Color = color, Thickness = thickness, Parent = frame })
		return frame, stroke
	end
	local selectMark = marker(C.Gold, 4, "Selected")
	local cursorMark = marker(C.White, 3, "Cursor")
	local targetMark = marker(C.Cyan, 3, "Target")
	Common.Pulse(Motion.ScaleOf(selectMark), { Scale = 1.06 }, 0.35)

	-- Bandeau : coups restants + consigne
	local movesPill: TextLabel = New("TextLabel", {
		Name = "Moves",
		AnchorPoint = Vector2.new(0, 0.5),
		Position = At(16, DefragLogic.BAND / 2),
		Size = Box(200, 40),
		BackgroundColor3 = C.Ink,
		BackgroundTransparency = 0.2,
		Text = "",
		TextScaled = true,
		TextColor3 = C.White,
		Tag = "FontHeavy",
		ZIndex = 5,
		Parent = stage,
	}, {
		Common.Corner(),
		New("UIPadding", { PaddingLeft = UDim.new(0.08, 0), PaddingRight = UDim.new(0.08, 0) }),
		New("UITextSizeConstraint", { MaxTextSize = 24 }),
	})
	local banner: TextLabel = New("TextLabel", {
		Name = "Banner",
		AnchorPoint = Vector2.new(0, 0.5),
		Position = At(232, DefragLogic.BAND / 2),
		Size = Box(Core.FIELD_W - 248, 40),
		BackgroundTransparency = 1,
		Text = "Corrupto mélange les fichiers…",
		TextScaled = true,
		TextColor3 = C.Cyan,
		TextXAlignment = Enum.TextXAlignment.Left,
		Tag = "FontBold",
		ZIndex = 5,
		Parent = stage,
	}, { New("UITextSizeConstraint", { MaxTextSize = 22 }) })

	local function done(success: boolean)
		if finished then
			return
		end
		finished = true
		finish(success, DefragLogic.FixedCount(sim))
	end

	local shownMoves = -1
	local function refreshMoves()
		local left = DefragLogic.MovesLeft(sim)
		if left == shownMoves then
			return
		end
		local lost = shownMoves > 0 and left < shownMoves
		shownMoves = left
		movesPill.Text = `Coups : {left}`
		movesPill.TextColor3 = if left <= 2 then C.Bad else C.White
		if lost then
			Motion.Pop(movesPill, 0.15)
		end
	end

	-- Bordure des blocs : blanche et brillante quand le fichier est réparé.
	local function refreshFixed()
		for _, view in blocks do
			local edge = view.Frame:FindFirstChild("Edge")
			if edge and edge:IsA("UIStroke") then
				local whole = sim.Fixed[view.File] == true and sim.Phase ~= "Scramble"
				edge.Color = if whole then C.White else Style.Color(FILES[view.File].Color):Lerp(C.Ink, 0.45)
				edge.Thickness = if whole then 3 else 2
			end
		end
	end

	-- Échange visuel des blocs des cases a et b.
	local function swapViews(a: number, b: number, speed: number)
		local va, vb = blocks[a], blocks[b]
		blocks[a], blocks[b] = vb, va
		if va then
			va.Frame.ZIndex = 3
			Motion.Tween(va.Frame, { Position = center(b) }, speed, Enum.EasingStyle.Back)
		end
		if vb then
			vb.Frame.ZIndex = 2
			Motion.Tween(vb.Frame, { Position = center(a) }, speed, Enum.EasingStyle.Back)
		end
	end

	local function setMark(mark: Frame, index: number?)
		if index then
			mark.Position = center(index)
			mark.Visible = true
		else
			mark.Visible = false
		end
	end

	local function handle(event: DefragLogic.Event)
		local kind = event.Kind
		if kind == "Ready" then
			banner.Text = "Regroupe chaque couleur !"
			banner.TextColor3 = C.White
			Motion.Pop(banner, 0.2)
			Common.Sound("PowerOn", 1.3)
			refreshFixed()
		elseif kind == "Select" then
			setMark(selectMark, event.Cells[1])
			local view = blocks[event.Cells[1]]
			if view then
				Motion.Pop(view.Frame, 0.15)
			end
			Common.Sound("Click", 1.25)
		elseif kind == "Deselect" then
			setMark(selectMark, nil)
			Common.Sound("Click", 0.9)
		elseif kind == "Swap" then
			setMark(selectMark, nil)
			swapViews(event.Cells[1], event.Cells[2], 0.2)
			Common.Sound("Whoosh", 1.2)
			refreshMoves()
		elseif kind == "Same" then
			setMark(selectMark, nil)
			Common.Popup(stage, center(event.Cells[2]), "Même fichier !", C.Cyan, 22)
			Common.Sound("Click", 0.8)
		elseif kind == "Fixed" then
			local file = event.File or 1
			refreshFixed()
			for index, view in blocks do
				if view.File == file then
					Motion.Pop(view.Frame, 0.2)
					Common.Burst(stage, center(index), C.Gold, 5, 40)
				end
			end
			Common.Popup(
				stage,
				At(Core.FIELD_W / 2, DefragLogic.BAND + 30),
				`{FILES[file].Name} réparé !`,
				C.Good,
				28
			)
			Common.Sound("Collect", 1 + DefragLogic.FixedCount(sim) * 0.06)
			ui.SetProgress(DefragLogic.FixedCount(sim), p.Files)
		elseif kind == "Broken" then
			refreshFixed()
			ui.SetProgress(DefragLogic.FixedCount(sim), p.Files)
		elseif kind == "Win" then
			setMark(selectMark, nil)
			setMark(targetMark, nil)
			for index, view in blocks do
				task.delay(index * 0.02, function()
					if view.Frame.Parent then
						Motion.Pop(view.Frame, 0.2)
					end
				end)
			end
			done(true)
		elseif kind == "Lose" then
			setMark(selectMark, nil)
			Common.Shake(stage, 10, 0.3)
			done(false)
		end
	end

	local function run(events: { DefragLogic.Event })
		for _, event in events do
			handle(event)
		end
	end

	-- Entrées ------------------------------------------------------------------------
	GuiService.SelectedObject = nil -- la croix / le stick déplacent le curseur de la grille
	local cursor = math.ceil(total / 2)
	local keyMode = Common.Device() == "Gamepad"
	local dragInput: InputObject? = nil
	local dragFrom: number? = nil
	local dragStart = Vector2.zero
	local dragging = false
	local pressedSelected = false
	local stickArmed = true

	local function showCursor()
		setMark(cursorMark, if keyMode and not finished then cursor else nil)
	end

	local function cancelDrag()
		local from = dragFrom
		if from and dragging then
			local view = blocks[from]
			if view then
				view.Frame.ZIndex = 2
				Motion.Tween(view.Frame, { Position = center(from) }, 0.15)
			end
		end
		dragInput, dragFrom, dragging, pressedSelected = nil, nil, false, false
		setMark(targetMark, nil)
	end

	local function isDragMove(input: InputObject): boolean
		local drag = dragInput
		if not drag then
			return false
		end
		return input == drag
			or (
				drag.UserInputType == Enum.UserInputType.MouseButton1
				and input.UserInputType == Enum.UserInputType.MouseMovement
			)
	end

	local function isDragEnd(input: InputObject): boolean
		local drag = dragInput
		if not drag then
			return false
		end
		return input == drag
			or (
				drag.UserInputType == Enum.UserInputType.MouseButton1
				and input.UserInputType == Enum.UserInputType.MouseButton1
			)
	end

	bin:Add(catcher.InputBegan:Connect(function(input: InputObject)
		if finished or not Common.IsPress(input) or sim.Phase ~= "Play" then
			return
		end
		keyMode = false
		showCursor()
		cancelDrag()
		local point = Common.ToField(stage, input.Position)
		local index = DefragLogic.CellAt(p, point.X, point.Y)
		if not index then
			if sim.Selected then
				run(DefragLogic.Tap(sim, sim.Selected)) -- appui hors de la grille : on annule
			end
			return
		end
		cursor = index
		local selected = sim.Selected
		if selected and selected ~= index then
			run(DefragLogic.Tap(sim, index)) -- 2e appui : échange
			return
		end
		if sim.Cells[index] == 0 then
			return
		end
		pressedSelected = selected == index
		if not selected then
			run(DefragLogic.Tap(sim, index)) -- 1er appui : on prend le bloc
		end
		dragInput = input
		dragFrom = index
		dragStart = point
		dragging = false
	end))
	bin:Add(UserInputService.InputChanged:Connect(function(input: InputObject)
		if finished then
			return
		end
		if input.KeyCode == Enum.KeyCode.Thumbstick1 then
			local v = Vector2.new(input.Position.X, -input.Position.Y)
			if stickArmed and v.Magnitude > STICK_PUSH then
				stickArmed = false
				local dx = if math.abs(v.X) > math.abs(v.Y) then math.sign(v.X) else 0
				local dy = if dx == 0 then math.sign(v.Y) else 0
				local col, row = DefragLogic.Coords(p, cursor)
				cursor = DefragLogic.Index(p, math.clamp(col + dx, 0, p.Cols - 1), math.clamp(row + dy, 0, p.Rows - 1))
					or cursor
				keyMode = true
				showCursor()
			elseif v.Magnitude < STICK_RELEASE then
				stickArmed = true
			end
			return
		end
		local from = dragFrom
		if not from or not isDragMove(input) then
			return
		end
		local point = Common.ToField(stage, input.Position)
		if not dragging and (point - dragStart).Magnitude >= DRAG_START then
			dragging = true
		end
		if dragging then
			local view = blocks[from]
			if view then
				view.Frame.ZIndex = 3
				view.Frame.Position = At(point.X, point.Y)
			end
			local target = DefragLogic.CellAt(p, point.X, point.Y)
			setMark(targetMark, if target ~= from then target else nil)
		end
	end))
	bin:Add(UserInputService.InputEnded:Connect(function(input: InputObject)
		local from = dragFrom
		if finished or not from or not isDragEnd(input) then
			return
		end
		if dragging then
			local point = Common.ToField(stage, input.Position)
			local target = DefragLogic.CellAt(p, point.X, point.Y)
			if target and target ~= from and sim.Phase == "Play" then
				-- Le bloc suit déjà le doigt : il file directement à sa nouvelle case.
				dragging = false
				dragInput, dragFrom = nil, nil
				setMark(targetMark, nil)
				local events = DefragLogic.Swap(sim, from, target)
				local swapped = false
				for _, event in events do
					swapped = swapped or event.Kind == "Swap"
				end
				local view = blocks[from]
				if not swapped and view then
					view.Frame.ZIndex = 2
					Motion.Tween(view.Frame, { Position = center(from) }, 0.15)
				end
				run(events)
				if sim.Selected then
					run(DefragLogic.Tap(sim, sim.Selected))
				end
				setMark(selectMark, nil)
				return
			end
			cancelDrag()
			if sim.Selected then
				run(DefragLogic.Tap(sim, sim.Selected)) -- lâché au même endroit : on repose
			end
			return
		end
		-- Simple appui : un 2e appui sur le bloc choisi le repose.
		local wasSelected = pressedSelected
		cancelDrag()
		if wasSelected and sim.Selected == from then
			run(DefragLogic.Tap(sim, from))
		end
	end))
	bin:Add(UserInputService.InputBegan:Connect(function(input: InputObject)
		if finished or UserInputService:GetFocusedTextBox() then
			return
		end
		local code = input.KeyCode
		local move = MOVES[code]
		if move then
			local col, row = DefragLogic.Coords(p, cursor)
			cursor = DefragLogic.Index(
				p,
				math.clamp(col + move[1], 0, p.Cols - 1),
				math.clamp(row + move[2], 0, p.Rows - 1)
			) or cursor
			keyMode = true
			showCursor()
		elseif PICK_KEYS[code] then
			if not keyMode then
				keyMode = true
				showCursor()
				return -- 1er appui : on montre le curseur
			end
			cancelDrag()
			run(DefragLogic.Tap(sim, cursor))
		elseif CANCEL_KEYS[code] and sim.Selected then
			run(DefragLogic.Tap(sim, sim.Selected))
		end
	end))

	ui.SetProgress(DefragLogic.FixedCount(sim), p.Files)
	ui.SetLives(nil)
	ui.SetTimer(DefragLogic.TimeLeft(sim))
	refreshMoves()
	showCursor()

	-- Mélange animé : on rejoue les échanges de Corrupto pendant la phase "Scramble".
	local applied = 0
	local scrambleSpan = DefragLogic.SCRAMBLE_TIME * 0.75
	local function scrambleTo(count: number)
		while applied < math.min(count, #sim.Swaps) do
			applied += 1
			local swap = sim.Swaps[applied]
			swapViews(swap[1], swap[2], 0.18)
			for _, index in swap do
				local view = blocks[index]
				if view then
					Motion.Pop(view.Frame, 0.25)
				end
			end
			Common.Burst(stage, center(swap[1]), C.VirusHot, 4, 30)
			Common.Sound("Click", 0.7 + math.random() * 0.3)
		end
	end

	Common.Loop(bin, function(dt: number)
		if finished then
			return
		end
		local events = DefragLogic.Step(sim, dt)
		if sim.Phase == "Scramble" then
			local elapsed = DefragLogic.SCRAMBLE_TIME - sim.ScrambleLeft
			scrambleTo(math.floor(elapsed / scrambleSpan * #sim.Swaps))
		elseif applied < #sim.Swaps then
			scrambleTo(#sim.Swaps)
		end
		run(events)
		ui.SetTimer(DefragLogic.TimeLeft(sim))
	end, function()
		done(false)
	end)

	return function()
		finished = true
		Common.Unfocus(stage)
		bin:Clean()
	end
end

return Defrag
