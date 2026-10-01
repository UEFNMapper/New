--!strict
--[[
	Tri : « Tri des fichiers » (monde 5, The Core). Minor cache son mineur parmi tes fichiers :
	range chaque fichier qui arrive sur le tapis dans le bon bac avant qu'il file !
	- GARDER : tes vrais fichiers (photos, devoirs, sauvegardes) ;
	- CORBEILLE : doublons, fichiers temporaires, caches ;
	- QUARANTAINE : programmes déguisés (« .jpg.exe », « .scr », « .bat »).
	Ce qu'on apprend : lire l'extension complète d'un fichier avant de l'ouvrir.

	Contrôles : doigt / clic sur un bac (à l'appui) ; clavier ← ↓ → ou 1 2 3 ; manette : croix
	(← ↓ →) ou X / A / Y. Règles et chiffres : TriLogic (pur, testé).
]]

local UserInputService = game:GetService("UserInputService")

local Create = require(script.Parent.Parent.Create)
local Motion = require(script.Parent.Parent.Motion)
local Style = require(script.Parent.Parent.Style)
local Icon = require(script.Parent.Parent.Components.Icon)
local Common = require(script.Parent.Common)
local TriLogic = require(script.Parent.TriLogic)

local New = Create.New
local C = Common.Colors
local At = Common.At
local Box = Common.Box

local Tri = {}

type BinDef = { Bin: TriLogic.Bin, Text: string, Icon: string, Color: string, X: number }

local BINS: { BinDef } = {
	{ Bin = "Keep", Text = "GARDER", Icon = "Check", Color = "Success", X = 180 },
	{ Bin = "Trash", Text = "CORBEILLE", Icon = "Close", Color = "TextMuted", X = 450 },
	{ Bin = "Quarantine", Text = "QUARANTAINE", Icon = "Lock", Color = "Danger", X = 720 },
}

local KEYS: { [Enum.KeyCode]: TriLogic.Bin } = {
	[Enum.KeyCode.Left] = "Keep",
	[Enum.KeyCode.One] = "Keep",
	[Enum.KeyCode.KeypadOne] = "Keep",
	[Enum.KeyCode.DPadLeft] = "Keep",
	[Enum.KeyCode.ButtonX] = "Keep",
	[Enum.KeyCode.Down] = "Trash",
	[Enum.KeyCode.Two] = "Trash",
	[Enum.KeyCode.KeypadTwo] = "Trash",
	[Enum.KeyCode.DPadDown] = "Trash",
	[Enum.KeyCode.ButtonA] = "Trash",
	[Enum.KeyCode.Right] = "Quarantine",
	[Enum.KeyCode.Three] = "Quarantine",
	[Enum.KeyCode.KeypadThree] = "Quarantine",
	[Enum.KeyCode.DPadRight] = "Quarantine",
	[Enum.KeyCode.ButtonY] = "Quarantine",
}

local BIN_Y = 400
local BIN_W, BIN_H = 240, 150
local CARD_X, CARD_Y = 450, 150
local CARD_W, CARD_H = 420, 170

function Tri.Info(difficulty: number, device: Common.Device): Common.Info
	local p = TriLogic.Params(difficulty)
	return {
		Title = "TRI DES FICHIERS",
		Rule = "Range chaque fichier dans le bon bac avant qu'il file !",
		Target = `Trie {p.Target} fichiers !`,
		Controls = if device == "Gamepad"
			then "Croix : ← Garder · ↓ Corbeille · → Quarantaine"
			elseif device == "Touch" then "Tape le bon bac sous le fichier"
			else "Clique un bac, ou ← ↓ → (1, 2, 3)",
		Tip = "Astuce : « .jpg.exe », c'est un programme déguisé en photo : Quarantaine !",
		Goal = p.Target,
		Unit = "fichiers",
		Icon = "Check",
		Accent = "AccentCyan",
	}
end

-- Illustration de la carte d'intro : un fichier et les trois bacs.
function Tri.Illustrate(parent: Frame)
	Common.File({ Size = UDim2.fromOffset(80, 80), Position = UDim2.fromScale(0.5, 0.3), Parent = parent })
	for index, def in BINS do
		local tile: Frame = New("Frame", {
			AnchorPoint = Vector2.new(0.5, 0.5),
			Position = UDim2.fromScale(0.2 + 0.3 * (index - 1), 0.8),
			Size = UDim2.fromOffset(84, 40),
			BackgroundColor3 = Style.Color(def.Color),
			BackgroundTransparency = 0.2,
			BorderSizePixel = 0,
			Parent = parent,
		}, { Common.Corner(UDim.new(0, 8)) })
		local icon = Icon.new(def.Icon, 24, "BgDeep")
		icon.AnchorPoint = Vector2.new(0.5, 0.5)
		icon.Position = UDim2.fromScale(0.5, 0.5)
		icon.Parent = tile
	end
end

function Tri.Run(container: Frame, difficulty: number, finish: Common.Finish, hud: Common.Hud?): () -> ()
	local ui = hud or Common.NullHud
	local bin = Common.Bin()
	local sim = TriLogic.new(difficulty, Common.Seed())
	local p = sim.Params
	local finished = false

	local stage = Common.Stage(container)
	bin:Add(stage)

	local function done(success: boolean)
		if finished then
			return
		end
		finished = true
		finish(success, sim.Sorted)
	end

	-- Tapis roulant (bande) sous la carte du fichier
	local belt = Common.Shape(stage, At(CARD_X, CARD_Y + 20), Box(860, 70), C.Screen, UDim.new(0, 12), {
		Name = "Belt",
		ZIndex = 1,
	})
	for k = 0, 9 do
		Common.Shape(belt, UDim2.fromScale(0.05 + k * 0.1, 0.5), UDim2.fromScale(0.012, 0.6), C.Dim, UDim.new(1, 0), {
			Name = "Roller",
			BackgroundTransparency = 0.5,
		})
	end

	-- Carte du fichier courant
	local card: Frame = New("Frame", {
		Name = "FileCard",
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = At(CARD_X, CARD_Y),
		Size = Box(CARD_W, CARD_H),
		BackgroundColor3 = C.Raised,
		BorderSizePixel = 0,
		Visible = false,
		ZIndex = 3,
		Parent = stage,
	}, {
		Common.Corner(UDim.new(0, 12)),
		New("UIStroke", { Color = C.Cyan, Thickness = 2, Transparency = 0.3 }),
	})
	local sprite = Common.File({
		Size = UDim2.fromScale(0.26, 0.62),
		Position = UDim2.fromScale(0.15, 0.45),
		Parent = card,
		ZIndex = 4,
	})
	local nameLabel: TextLabel = New("TextLabel", {
		Name = "FileName",
		Position = UDim2.fromScale(0.3, 0.14),
		Size = UDim2.fromScale(0.66, 0.36),
		BackgroundTransparency = 1,
		Text = "",
		TextScaled = true,
		TextXAlignment = Enum.TextXAlignment.Left,
		TextColor3 = C.White,
		Tag = "FontHeavy",
		ZIndex = 4,
		Parent = card,
	}, { New("UITextSizeConstraint", { MaxTextSize = 34, MinTextSize = 18 }) })
	local hintLabel: TextLabel = New("TextLabel", {
		Name = "Hint",
		Position = UDim2.fromScale(0.3, 0.54),
		Size = UDim2.fromScale(0.66, 0.2),
		BackgroundTransparency = 1,
		Text = "",
		TextScaled = true,
		TextXAlignment = Enum.TextXAlignment.Left,
		TextColor3 = C.Muted,
		Tag = "FontBold",
		ZIndex = 4,
		Parent = card,
	}, { New("UITextSizeConstraint", { MaxTextSize = 24, MinTextSize = 18 }) })
	local timerBack =
		Common.Shape(card, UDim2.fromScale(0.63, 0.86), UDim2.fromScale(0.66, 0.08), C.Screen, UDim.new(1, 0), {
			Name = "TimerBack",
			ZIndex = 4,
		})
	local timerFill: Frame = New("Frame", {
		Name = "TimerFill",
		Size = UDim2.fromScale(1, 1),
		BackgroundColor3 = C.Cyan,
		BorderSizePixel = 0,
		ZIndex = 5,
		Parent = timerBack,
	}, { Common.Corner(UDim.new(1, 0)) })

	-- Les trois bacs
	type BinView = { Button: TextButton, Def: BinDef }
	local views: { [string]: BinView } = {}
	local sortBin: (bin: TriLogic.Bin) -> ()

	for _, def in BINS do
		local color = Style.Color(def.Color)
		local button: TextButton = New("TextButton", {
			Name = def.Bin,
			AnchorPoint = Vector2.new(0.5, 0.5),
			Position = At(def.X, BIN_Y),
			Size = Box(BIN_W, BIN_H),
			BackgroundColor3 = color:Lerp(C.Screen, 0.55),
			BorderSizePixel = 0,
			AutoButtonColor = false,
			Text = "",
			Selectable = true,
			ZIndex = 2,
			Parent = stage,
		}, {
			Common.Corner(UDim.new(0, 14)),
			New("UIStroke", { Color = color, Thickness = 3 }),
		})
		local icon = Icon.new(def.Icon, 40, def.Color)
		icon.AnchorPoint = Vector2.new(0.5, 0.5)
		icon.Position = UDim2.fromScale(0.5, 0.34)
		icon.ZIndex = 3
		icon.Parent = button
		New("TextLabel", {
			AnchorPoint = Vector2.new(0.5, 0.5),
			Position = UDim2.fromScale(0.5, 0.74),
			Size = UDim2.fromScale(0.9, 0.3),
			BackgroundTransparency = 1,
			Text = def.Text,
			TextScaled = true,
			TextColor3 = C.White,
			Tag = "FontHeavy",
			ZIndex = 3,
			Parent = button,
		}, { New("UITextSizeConstraint", { MaxTextSize = 28, MinTextSize = 18 }) })
		views[def.Bin] = { Button = button, Def = def }
		bin:Add(button.InputBegan:Connect(function(input: InputObject)
			if Common.IsPress(input) then
				sortBin(def.Bin)
			end
		end))
		bin:Add(button.Activated:Connect(function()
			local last = UserInputService:GetLastInputType()
			if string.find(last.Name, "^Gamepad") or last == Enum.UserInputType.Keyboard then
				sortBin(def.Bin)
			end
		end))
	end

	local function showFile(file: TriLogic.File)
		card.Visible = true
		nameLabel.Text = file.Name
		hintLabel.Text = if p.Hints then `({file.Hint})` else ""
		timerFill.Size = UDim2.fromScale(1, 1)
		card.Position = At(CARD_X + 380, CARD_Y)
		Motion.Tween(card, { Position = At(CARD_X, CARD_Y) }, 0.18, Enum.EasingStyle.Quad)
		local scale = Motion.ScaleOf(sprite)
		scale.Scale = 0.8
		Motion.Tween(scale, { Scale = 1 }, 0.2, Enum.EasingStyle.Back)
	end

	local function sendCard(toX: number, toY: number)
		local ghost = card:Clone()
		ghost.Name = "Leaving"
		ghost.Parent = stage
		card.Visible = false
		Motion.Tween(
			ghost,
			{ Position = At(toX, toY), Size = Box(CARD_W * 0.3, CARD_H * 0.3) },
			0.22,
			Enum.EasingStyle.Quad
		)
		task.delay(0.25, function()
			ghost:Destroy()
		end)
	end

	local function handle(event: TriLogic.Event)
		local file = event.File
		if event.Kind == "Spawn" and file then
			showFile(file)
		elseif event.Kind == "Sorted" and file and event.Bin then
			local view = views[event.Bin]
			sendCard(view.Def.X, BIN_Y)
			if event.Ok then
				Common.Sound("Collect", 1 + math.min(sim.Sorted, 10) * 0.03)
				Common.Burst(stage, At(view.Def.X, BIN_Y - 40), Style.Color(view.Def.Color), 8, 50)
				Common.Popup(stage, At(view.Def.X, BIN_Y - 100), "+1", C.Good, 26)
				ui.SetProgress(sim.Sorted, p.Target)
			else
				Common.Sound("Error")
				Common.Shake(stage, 8, 0.25)
				Common.Popup(stage, At(450, 270), (TriLogic.WHY :: any)[file.Kind], C.Bad, 22)
				ui.SetLives(sim.Lives, p.Lives)
			end
		elseif event.Kind == "Miss" and file then
			sendCard(-120, CARD_Y)
			Common.Sound("Error")
			Common.Popup(stage, At(450, 270), `Trop lent ! {(TriLogic.WHY :: any)[file.Kind]}`, C.Bad, 22)
			ui.SetLives(sim.Lives, p.Lives)
		elseif event.Kind == "Win" then
			done(true)
		elseif event.Kind == "Lose" or event.Kind == "Timeout" then
			done(false)
		end
	end

	sortBin = function(target: TriLogic.Bin)
		if finished then
			return
		end
		for _, event in TriLogic.Sort(sim, target) do
			handle(event)
		end
	end

	bin:Add(UserInputService.InputBegan:Connect(function(input: InputObject)
		if finished or UserInputService:GetFocusedTextBox() then
			return
		end
		local target = KEYS[input.KeyCode]
		if target then
			sortBin(target :: TriLogic.Bin)
		end
	end))

	ui.SetProgress(0, p.Target)
	ui.SetLives(sim.Lives, p.Lives)
	ui.SetTimer(TriLogic.TimeLeft(sim))
	if p.Hints then
		local hint = Common.Hint(stage, "Lis bien l'extension : .exe = un programme !", 0.58)
		task.delay(4, function()
			if hint.Parent then
				hint:Destroy()
			end
		end)
	end

	Common.Loop(bin, function(dt: number)
		if finished then
			return
		end
		for _, event in TriLogic.Step(sim, dt) do
			handle(event)
		end
		ui.SetTimer(TriLogic.TimeLeft(sim))
		local current = sim.Current
		if current then
			local left = math.clamp((current.Expires - sim.Time) / p.Lifetime, 0, 1)
			timerFill.Size = UDim2.fromScale(left, 1)
			timerFill.BackgroundColor3 = if left < 0.3 then C.Bad elseif left < 0.6 then C.Amber else C.Cyan
		end
	end, function()
		done(false)
	end)

	return function()
		finished = true
		Common.Unfocus(stage)
		bin:Clean()
	end
end

return Tri
