--!strict
--[[
	Scan : des virus surgissent dans les prises d'une carte mère ; touche-les avant
	qu'ils filent ! Les gentils fichiers souriants, eux, on ne les touche pas.

	Règles et chiffres : ScanLogic (pur, testé). Ce module ne fait que l'affichage et
	les entrées : doigt / clic (à l'appui, sans attendre le relâchement), manette
	(croix pour choisir une prise, A pour toucher).
]]

local UserInputService = game:GetService("UserInputService")

local Create = require(script.Parent.Parent.Create)
local Motion = require(script.Parent.Parent.Motion)
local Icon = require(script.Parent.Parent.Components.Icon)
local Core = require(script.Parent.Core)
local Common = require(script.Parent.Common)
local ScanLogic = require(script.Parent.ScanLogic)

local New = Create.New
local C = Common.Colors

local Scan = {}

function Scan.Info(difficulty: number, device: Common.Device): Common.Info
	local p = ScanLogic.Params(difficulty)
	return {
		Title = "SCAN ANTIVIRUS",
		Rule = "Touche les virus, pas les fichiers !",
		Target = `Élimine {p.Target} virus !`,
		Controls = if device == "Gamepad"
			then "Croix pour viser, A pour toucher"
			elseif device == "Touch" then "Tape avec ton doigt"
			else "Clique sur les virus",
		Tip = "Astuce : les fichiers qui sourient sont gentils !",
		Goal = p.Target,
		Unit = "virus",
		Icon = "Virus",
		Accent = "AccentViolet",
	}
end

-- Illustration de la carte d'intro : un virus à toucher, un fichier à laisser.
function Scan.Illustrate(parent: Frame)
	Common.Virus({ Size = UDim2.fromOffset(110, 110), Position = UDim2.fromScale(0.34, 0.5), Parent = parent })
	local ring: Frame = New("Frame", {
		Name = "TapRing",
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromScale(0.34, 0.5),
		Size = UDim2.fromOffset(120, 120),
		BackgroundTransparency = 1,
		ZIndex = 3,
		Parent = parent,
	}, {
		Common.Corner(),
		New("UIStroke", { Color = C.Good, Thickness = 3, Transparency = 0.1 }),
	})
	Common.Pulse(ring, { Size = UDim2.fromOffset(140, 140) }, 0.6)
	local ok = Icon.new("Check", 34, "Success")
	ok.AnchorPoint = Vector2.new(0.5, 0.5)
	ok.Position = UDim2.fromScale(0.34 + 0.1, 0.12)
	ok.Parent = parent
	Common.File({ Size = UDim2.fromOffset(96, 96), Position = UDim2.fromScale(0.68, 0.5), Parent = parent })
	local no = Icon.new("Close", 34, "Danger")
	no.AnchorPoint = Vector2.new(0.5, 0.5)
	no.Position = UDim2.fromScale(0.68 + 0.09, 0.12)
	no.Parent = parent
end

function Scan.Run(container: Frame, difficulty: number, finish: Common.Finish, hud: Common.Hud?): () -> ()
	local ui = hud or Common.NullHud
	local bin = Common.Bin()
	local sim = ScanLogic.new(difficulty, Common.Seed())
	local p = sim.Params
	local finished = false

	local stage = Common.Stage(container)
	bin:Add(stage)

	-- Grille centrée : cases carrées aussi grandes que possible.
	local margin = 20
	local cell = math.min((Core.FIELD_W - margin * 2) / p.Cols, (Core.FIELD_H - margin * 2) / p.Rows)
	local originX = (Core.FIELD_W - cell * p.Cols) / 2
	local originY = (Core.FIELD_H - cell * p.Rows) / 2

	type Slot = { Button: TextButton, Socket: Frame, Stroke: UIStroke, Sprite: Frame?, Id: number }
	local slots: { Slot } = {}

	local function done(success: boolean)
		if finished then
			return
		end
		finished = true
		finish(success, sim.Hits)
	end

	local function flashSocket(slot: Slot, color: Color3)
		slot.Stroke.Color = color
		slot.Stroke.Transparency = 0
		Motion.Tween(slot.Stroke, { Transparency = 0.65 }, 0.4)
		task.delay(0.4, function()
			if slot.Stroke.Parent then
				slot.Stroke.Color = C.Cyan
			end
		end)
	end

	local function removeSprite(slot: Slot, how: "Hit" | "Escape" | "Oops")
		local sprite = slot.Sprite
		if not sprite then
			return
		end
		slot.Sprite = nil
		slot.Id = 0
		if how == "Hit" then
			sprite:Destroy()
		else
			-- Il file dans sa prise (ou le fichier s'en va, vexé).
			local scale = Motion.ScaleOf(sprite)
			Motion.Tween(scale, { Scale = 0 }, 0.16, Enum.EasingStyle.Back, Enum.EasingDirection.In)
			Motion.Tween(sprite, { Position = UDim2.fromScale(0.5, 0.75) }, 0.16)
			task.delay(0.2, function()
				sprite:Destroy()
			end)
		end
	end

	local function handle(event: ScanLogic.Event)
		local slot = slots[event.Cell]
		if event.Kind == "Spawn" and slot then
			local life = event.Life or p.Lifetime
			local props: Common.SpriteProps = {
				Size = UDim2.fromScale(0.78, 0.78),
				Position = UDim2.fromScale(0.5, 0.5),
				ZIndex = 2,
			}
			local sprite = if event.What == "File" then Common.File(props) else Common.Virus(props)
			-- Barre de temps : le virus va bientôt filer.
			if event.What == "Virus" then
				local bar: Frame = New("Frame", {
					Name = "LifeBar",
					AnchorPoint = Vector2.new(0.5, 0),
					Position = UDim2.fromScale(0.5, 1.04),
					Size = UDim2.fromScale(0.7, 0.07),
					BackgroundColor3 = C.VirusHot,
					BorderSizePixel = 0,
					ZIndex = 3,
					Parent = sprite,
				}, { Common.Corner() })
				Motion.Tween(bar, { Size = UDim2.fromScale(0, 0.07) }, life, Enum.EasingStyle.Linear)
			end
			local scale = Motion.ScaleOf(sprite)
			scale.Scale = 0.2
			sprite.Position = UDim2.fromScale(0.5, 0.72)
			sprite.Parent = slot.Button
			Motion.Tween(scale, { Scale = 1 }, 0.2, Enum.EasingStyle.Back)
			Motion.Tween(sprite, { Position = UDim2.fromScale(0.5, 0.5) }, 0.2, Enum.EasingStyle.Back)
			slot.Sprite = sprite
			slot.Id = event.Id or 0
			Common.Sound("Click", if event.What == "File" then 0.8 else 1.15 + math.random() * 0.2)
		elseif event.Kind == "Escape" and slot then
			removeSprite(slot, "Escape")
		elseif event.Kind == "Hit" and slot then
			local where = slot.Button.Position
			removeSprite(slot, "Hit")
			flashSocket(slot, C.Good)
			Common.Burst(stage, where, C.VirusHot, 12, 80)
			Common.Burst(stage, where, C.Gold, 5, 50)
			Common.Popup(stage, where, "+1", C.Gold)
			Common.Sound("Zap", 1 + math.min(sim.Combo, 10) * 0.04)
			if sim.Combo > 0 and sim.Combo % 5 == 0 then
				Common.Popup(stage, UDim2.fromScale(0.5, 0.12), `COMBO x{sim.Combo} !`, C.Gold, 36)
				Common.Sound("Collect", 1.1)
			end
			ui.SetProgress(sim.Hits, p.Target)
		elseif event.Kind == "Oops" and slot then
			local where = slot.Button.Position
			removeSprite(slot, "Oops")
			flashSocket(slot, C.Bad)
			Common.Popup(stage, where, "Oups ! -1", C.Bad, 28)
			Common.Sound("Error")
			Common.Shake(stage, 8, 0.3)
			ui.SetProgress(sim.Hits, p.Target)
		elseif event.Kind == "Win" then
			done(true)
		elseif event.Kind == "Timeout" then
			done(false)
		end
	end

	local function tap(index: number)
		if finished then
			return
		end
		for _, event in ScanLogic.Tap(sim, index) do
			handle(event)
		end
	end

	for index = 1, p.Cols * p.Rows do
		local col = (index - 1) % p.Cols
		local row = (index - 1) // p.Cols
		local button: TextButton = New("TextButton", {
			Name = `Cell{index}`,
			AnchorPoint = Vector2.new(0.5, 0.5),
			Position = Common.At(originX + (col + 0.5) * cell, originY + (row + 0.5) * cell),
			Size = Common.Box(cell, cell),
			BackgroundTransparency = 1,
			Text = "",
			AutoButtonColor = false,
			Selectable = true,
			ZIndex = 2,
			Parent = stage,
		})
		-- Prise de la carte mère : trou sombre bordé de cyan.
		local socket: Frame = New("Frame", {
			Name = "Socket",
			AnchorPoint = Vector2.new(0.5, 0.5),
			Position = UDim2.fromScale(0.5, 0.5),
			Size = UDim2.fromScale(0.86, 0.86),
			BackgroundTransparency = 0.1,
			BorderSizePixel = 0,
			ZIndex = 1,
			Tag = "GlassSunken",
			Parent = button,
		}, {
			Common.Corner(UDim.new(0.2, 0)),
		})
		local stroke: UIStroke = New("UIStroke", {
			Color = C.Cyan,
			Thickness = 2,
			Transparency = 0.65,
			Parent = socket,
		})
		Common.Shape(socket, UDim2.fromScale(0.5, 0.66), UDim2.fromScale(0.64, 0.3), C.Ink, UDim.new(1, 0), {
			Name = "Hole",
			BackgroundTransparency = 0.25,
		})
		local slot: Slot = { Button = button, Socket = socket, Stroke = stroke, Sprite = nil, Id = 0 }
		slots[index] = slot
		-- Appui immédiat (doigt / souris) : pas besoin d'attendre le relâchement.
		bin:Add(button.InputBegan:Connect(function(input: InputObject)
			if Common.IsPress(input) then
				tap(index)
			end
		end))
		-- Manette / clavier (bouton sélectionné + A ou Entrée).
		bin:Add(button.Activated:Connect(function()
			local last = UserInputService:GetLastInputType()
			if string.find(last.Name, "^Gamepad") or last == Enum.UserInputType.Keyboard then
				tap(index)
			end
		end))
	end

	-- Focus manette sur la case du milieu.
	Common.Focus(slots[math.ceil(#slots / 2)].Button)

	ui.SetProgress(0, p.Target)
	ui.SetLives(nil)
	ui.SetTimer(ScanLogic.TimeLeft(sim))

	Common.Loop(bin, function(dt: number)
		if finished then
			return
		end
		for _, event in ScanLogic.Step(sim, dt) do
			handle(event)
		end
		ui.SetTimer(ScanLogic.TimeLeft(sim))
		-- Petits glitchs aléatoires sur les virus visibles.
		for _, slot in slots do
			local sprite = slot.Sprite
			if sprite and sprite.Name == "Virus" and math.random() < 0.012 then
				Common.Glitch(sprite)
			end
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

return Scan
