--!nonstrict
-- FUSION LAB : deux kaijus ADULTES -> un nouveau kaiju (ou un SECRET avec la
-- bonne recette). Les probabilités (FuseOdds) sont TOUJOURS affichées avant de
-- fusionner. Cinématique complète dans la fenêtre après la fusion.
--   Fusion.Open({ A = uid? })  -- présélectionne l'emplacement A

local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local Workspace = game:GetService("Workspace")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Kaijus = require(Shared.Config.Kaijus)
local Rarities = require(Shared.Config.Rarities)
local Mutations = require(Shared.Config.Mutations)
local Growth = require(Shared.Config.Growth)
local Calc = require(Shared.Logic.Calc)
local Format = require(Shared.Logic.Format)

local Kit = require(script.Parent.Parent.Kit)
local Viewport = require(script.Parent.Parent.Viewport)
local Controllers = script.Parent.Parent.Parent.Controllers
local State = require(Controllers.State)
local Remote = require(Controllers.Remote)
local Audio = require(Controllers.Audio)
local UIRegistry = require(Controllers.UIRegistry)

local C = Kit.Colors
local F = Kit.Fonts
local LocalPlayer = Players.LocalPlayer

local Fusion = {}

local MIN_STAGE = 3 -- Adulte
local MAX_ODDS = 3

local RAINBOW = ColorSequence.new({
	ColorSequenceKeypoint.new(0, Color3.fromRGB(255, 70, 90)),
	ColorSequenceKeypoint.new(0.2, Color3.fromRGB(255, 200, 40)),
	ColorSequenceKeypoint.new(0.4, Color3.fromRGB(124, 255, 79)),
	ColorSequenceKeypoint.new(0.6, Color3.fromRGB(61, 224, 255)),
	ColorSequenceKeypoint.new(0.8, Color3.fromRGB(170, 90, 255)),
	ColorSequenceKeypoint.new(1, Color3.fromRGB(255, 61, 139)),
})

----------------------------------------------------------------------------
-- Aides
----------------------------------------------------------------------------

local function rainbow(parent: Instance, period: number?): UIGradient
	local g = parent:FindFirstChild("Rainbow") :: UIGradient?
	if not g then
		g = Kit.new("UIGradient", { Name = "Rainbow", Color = RAINBOW, Parent = parent })
		Kit.Tween(g :: UIGradient, period or 2.5, { Rotation = 360 }, Enum.EasingStyle.Linear, Enum.EasingDirection.InOut, -1)
	end
	return g :: UIGradient
end

local function clearRainbow(parent: Instance)
	local g = parent:FindFirstChild("Rainbow")
	if g then
		g:Destroy()
	end
end

local function inkText(props: { [string]: any }): TextLabel
	props.Stroke = false
	props.FontFace = props.FontFace or F.Body
	props.TextColor3 = props.TextColor3 or C.Ink
	return Kit.Text(props)
end

local function anchorOf(uid: string): any
	local root = Workspace:FindFirstChild("Kaijus")
	local folder = root and root:FindFirstChild(tostring(LocalPlayer.UserId))
	return folder and folder:FindFirstChild(uid)
end

local function stageOf(rec: any): number
	local stage = Calc.Stage(rec)
	local anchor = anchorOf(rec.Uid)
	if anchor then
		stage = math.max(stage, anchor:GetAttribute("Stage") or 1)
	end
	return stage
end

local function isCarried(uid: string): boolean
	local anchor = anchorOf(uid)
	return anchor ~= nil and (anchor:GetAttribute("CarriedBy") or 0) ~= 0
end

local function eligible(rec: any): boolean
	return not rec.Egg and rec.Species ~= nil and stageOf(rec) >= MIN_STAGE and not isCarried(rec.Uid)
end

local function findRecord(uid: string?): any
	if not uid then
		return nil
	end
	for _, rec in State.Get("Kaijus") or {} do
		if rec.Uid == uid then
			return rec
		end
	end
	return nil
end

local function speciesName(id: string?): string
	local s = if id then Kaijus.Get(id) else nil
	return if s then s.Name else "???"
end

local function rarityColor(id: string): Color3
	return if id == "Secret" then C.Ink else Rarities.Get(id).Color
end

local function discovered(id: string): boolean
	local index = State.Get("Index") or {}
	return index[id] ~= nil
end

-- Libellés serveur : noms de rareté localisés -> identifiants anglais.
local function englishLabel(label: string): (string, Color3?)
	local color = nil
	for _, r in Rarities.List do
		if r.Id ~= "Secret" and r.Name ~= r.Id and string.find(label, r.Name, 1, true) then
			label = string.gsub(label, r.Name, r.Id)
		end
		if r.Id ~= "Secret" and string.find(label, r.Id, 1, true) then
			color = r.Color
		end
	end
	if string.find(label, "SECRET", 1, true) then
		color = C.Pink
	end
	return label, color
end

local function setBreathing(button: GuiObject, on: boolean)
	if button:GetAttribute("Breathing") == on then
		return
	end
	button:SetAttribute("Breathing", on)
	if on then
		Kit.Breathe(button, 0.06, 0.7)
	else
		Kit.Tween(Kit.ScaleOf(button), 0.2, { Scale = 1 })
	end
	if not button:GetAttribute("BreatheHooked") then
		button:SetAttribute("BreatheHooked", true)
		button.MouseLeave:Connect(function()
			task.delay(0.25, function()
				if button:GetAttribute("Breathing") then
					Kit.Breathe(button, 0.06, 0.7)
				end
			end)
		end)
	end
end

-- Secousse sans dérive : la position d'origine est mémorisée une fois et une
-- nouvelle secousse remplace la précédente.
local shakeBase: { [Instance]: UDim2 } = {}
local shakeToken: { [Instance]: number } = {}
local function safeShake(inst: GuiObject, intensity: number, duration: number)
	local base = shakeBase[inst]
	if not base then
		base = inst.Position
		shakeBase[inst] = base
	end
	local token = (shakeToken[inst] or 0) + 1
	shakeToken[inst] = token
	local t0 = os.clock()
	local conn
	conn = RunService.RenderStepped:Connect(function()
		local t = os.clock() - t0
		local mine = shakeToken[inst] == token
		if t > duration or not mine or not inst.Parent then
			conn:Disconnect()
			if mine then
				inst.Position = base
			end
			return
		end
		local k = (1 - t / duration) * intensity
		inst.Position = base + UDim2.fromOffset((math.random() - 0.5) * 2 * k, (math.random() - 0.5) * 2 * k)
	end)
end

-- Apparition élastique différée (relance la respiration si besoin).
local function popIn(item: GuiObject, delay: number, from: number?)
	Kit.ScaleOf(item).Scale = 0.01
	task.delay(delay, function()
		Kit.Pop(item, from or 0.3, 0.45)
		if item:GetAttribute("Breathing") then
			task.delay(0.46, function()
				if item:GetAttribute("Breathing") then
					Kit.Breathe(item, 0.06, 0.7)
				end
			end)
		end
	end)
end

local function confetti(parent: GuiObject, count: number, colors: { Color3 }, z: number)
	for i = 1, count do
		local angle = (i / count) * math.pi * 2 + math.random() * 0.4
		local dist = 160 + math.random() * 280
		local piece = Kit.new("Frame", {
			Size = UDim2.fromOffset(math.random(10, 20), math.random(6, 12)),
			Position = UDim2.fromScale(0.5, 0.42),
			AnchorPoint = Vector2.new(0.5, 0.5),
			BackgroundColor3 = colors[(i % #colors) + 1],
			Rotation = math.random(0, 360),
			ZIndex = z,
			Parent = parent,
		}, { Kit.Corner(3), Kit.Stroke(2) })
		local target = UDim2.new(0.5, math.cos(angle) * dist, 0.42, math.sin(angle) * dist * 0.7)
		Kit.Tween(piece, 0.9 + math.random() * 0.5, { Position = target, Rotation = piece.Rotation + math.random(-400, 400) }, Enum.EasingStyle.Quint)
		task.delay(0.9, function()
			Kit.Tween(piece, 0.5, { BackgroundTransparency = 1, Position = target + UDim2.fromOffset(0, 60) }, Enum.EasingStyle.Quad, Enum.EasingDirection.In)
			local stroke = piece:FindFirstChildOfClass("UIStroke")
			if stroke then
				Kit.Tween(stroke, 0.5, { Transparency = 1 })
			end
		end)
		task.delay(1.6, function()
			piece:Destroy()
		end)
	end
end

----------------------------------------------------------------------------
-- État
----------------------------------------------------------------------------

local win: any = nil
local ui: { [string]: any } = {}
local rows: { [string]: any } = {} -- [uid] = ligne de la liste
local slots = { A = nil :: string?, B = nil :: string? }
local pods: { [string]: any } = {}
local oddsToken = 0
local oddsReady = false
local busy = false
local cinematic = false
local bookOpen = false
local recipeRows: { any } = {}
local pollConn: RBXScriptConnection? = nil
local accum = 0

local refreshAll -- déclarée plus bas

----------------------------------------------------------------------------
-- Emplacements (pods)
----------------------------------------------------------------------------

local function buildPod(root: Instance, key: string, x: number, rotation: number, gradient: string): any
	local holder, body = Kit.Panel({
		Name = "Pod" .. key,
		Size = UDim2.fromOffset(150, 184),
		Position = UDim2.fromOffset(x, 6),
		Rotation = rotation,
		Gradient = gradient,
		Corner = 18,
		Parent = root,
	})
	local halo = Kit.new("Frame", {
		Name = "Halo",
		Size = UDim2.fromOffset(120, 120),
		Position = UDim2.fromScale(0.5, 0.4),
		AnchorPoint = Vector2.new(0.5, 0.5),
		BackgroundColor3 = if key == "R" then C.Pink else C.Purple,
		BackgroundTransparency = 0.6,
		ZIndex = 3,
		Parent = body,
	}, { Kit.Round() })
	local vpHolder = Kit.new("Frame", {
		Name = "VpHolder",
		Size = UDim2.new(1, -12, 0, 130),
		Position = UDim2.fromOffset(6, 6),
		BackgroundTransparency = 1,
		ZIndex = 4,
		Parent = body,
	})
	local empty = Kit.Text({
		Name = "Empty",
		Size = UDim2.fromOffset(90, 90),
		Position = UDim2.fromScale(0.5, 0.4),
		AnchorPoint = Vector2.new(0.5, 0.5),
		Text = if key == "R" then "?" else "+",
		FontFace = F.Impact,
		TextColor3 = if key == "R" then C.Gold else C.White,
		MaxTextSize = 90,
		Stroke = 4,
		ZIndex = 5,
		Parent = body,
	})
	Kit.Breathe(empty, 0.12, 0.8)
	local name = Kit.Text({
		Name = "PodName",
		Size = UDim2.new(1, -14, 0, 22),
		Position = UDim2.new(0.5, 0, 1, -40),
		AnchorPoint = Vector2.new(0.5, 0),
		Text = if key == "R" then "RESULT" else "PICK A KAIJU",
		MaxTextSize = 20,
		Stroke = 2.5,
		ZIndex = 6,
		Parent = body,
	})
	local sub = Kit.Text({
		Name = "PodSub",
		Size = UDim2.new(1, -14, 0, 14),
		Position = UDim2.new(0.5, 0, 1, -18),
		AnchorPoint = Vector2.new(0.5, 0),
		Text = "",
		FontFace = F.Body,
		TextColor3 = C.Paper,
		MaxTextSize = 14,
		Stroke = 1.5,
		ZIndex = 6,
		Parent = body,
	})
	if key ~= "R" then
		local badge = Kit.new("Frame", {
			Name = "Badge",
			Size = UDim2.fromOffset(40, 40),
			Position = UDim2.fromOffset(-10, -10),
			BackgroundColor3 = if key == "A" then C.Pink else C.Cyan,
			Rotation = -10,
			ZIndex = 12,
			Parent = holder,
		}, { Kit.Round(), Kit.Stroke(3) })
		Kit.Text({
			Size = UDim2.fromScale(0.7, 0.7),
			Position = UDim2.fromScale(0.5, 0.5),
			AnchorPoint = Vector2.new(0.5, 0.5),
			Text = key,
			Stroke = 2.5,
			ZIndex = 13,
			Parent = badge,
		})
	end
	local click = Kit.new("TextButton", {
		Name = "Click",
		Size = UDim2.fromScale(1, 1),
		BackgroundTransparency = 1,
		Text = "",
		ZIndex = 11,
		Parent = holder,
	})
	local pod = {
		Key = key,
		Holder = holder,
		Body = body,
		Halo = halo,
		VpHolder = vpHolder,
		Vp = nil :: any,
		ModelKey = "",
		Empty = empty,
		Name = name,
		Sub = sub,
		Click = click,
	}
	click.MouseEnter:Connect(function()
		if pod.Vp and pod.Vp.Frame.Visible then
			pod.Vp.Speed = 2
		end
		Kit.Tween(Kit.ScaleOf(holder), 0.2, { Scale = 1.04 }, Enum.EasingStyle.Back)
	end)
	click.MouseLeave:Connect(function()
		if pod.Vp then
			pod.Vp.Speed = 0.7
		end
		Kit.Tween(Kit.ScaleOf(holder), 0.2, { Scale = 1 })
	end)
	return pod
end

local function podViewport(pod: any): any
	if not pod.Vp then
		pod.Vp = Viewport.new({ Parent = pod.VpHolder, ZIndex = 5, Speed = 0.7 })
	end
	return pod.Vp
end

local function renderPod(key: string, animate: boolean)
	local pod = pods[key]
	local rec = findRecord(slots[key])
	if rec and rec.Species then
		local vp = podViewport(pod)
		vp.Frame.Visible = true
		local modelKey = rec.Species .. ":" .. (rec.Mutation or "")
		if pod.ModelKey ~= modelKey then
			pod.ModelKey = modelKey
			vp:SetSilhouette(false)
			vp:Set(rec.Species, rec.Mutation)
		end
		vp.Spin = true
		pod.Empty.Visible = false
		pod.Name.Text = speciesName(rec.Species)
		pod.Name.TextColor3 = if rec.Rarity == "Secret" then C.White else Rarities.Get(rec.Rarity).Color:Lerp(C.White, 0.3)
		local m = Mutations.Get(rec.Mutation)
		pod.Sub.Text = string.upper(Growth.Get(stageOf(rec)).Name) .. (if m then " · " .. string.upper(m.Name) else "")
		pod.Halo.BackgroundColor3 = if rec.Rarity == "Secret" then C.Gold else Rarities.Get(rec.Rarity).Glow
		if animate then
			Kit.Pop(pod.Holder, 1.25, 0.45)
			Kit.Pop(vp.Frame, 0.2, 0.5)
		end
	else
		if pod.Vp then
			pod.Vp.Frame.Visible = false
			pod.Vp.Spin = false
		end
		pod.Empty.Visible = true
		pod.Name.Text = "PICK A KAIJU"
		pod.Name.TextColor3 = C.White
		pod.Sub.Text = "from the list"
		pod.Halo.BackgroundColor3 = C.Purple
		if animate then
			Kit.Punch(pod.Holder, -0.1)
		end
	end
end

-- Pod résultat : « ? », ou silhouette du Secret si la recette correspond.
local function renderResult()
	local pod = pods.R
	local a, b = findRecord(slots.A), findRecord(slots.B)
	local recipe = if a and b then Kaijus.FindRecipe(a.Species or "", b.Species or "") else nil
	clearRainbow(pod.Empty)
	clearRainbow(pod.Name)
	if recipe then
		local vp = podViewport(pod)
		vp.Frame.Visible = true
		if pod.ModelKey ~= recipe.Id then
			pod.ModelKey = recipe.Id
			vp:Set(recipe.Id)
		end
		vp:SetSilhouette(not discovered(recipe.Id))
		vp.Spin = true
		pod.Empty.Visible = false
		pod.Name.Text = "SECRET!"
		pod.Name.TextColor3 = C.White
		rainbow(pod.Name, 1.8)
		pod.Sub.Text = if discovered(recipe.Id) then recipe.Name else "Recipe match!"
		pod.Halo.BackgroundColor3 = C.Gold
		Kit.Pop(pod.Holder, 1.3, 0.5)
		Audio.Play("stage_up", { Volume = 0.6 })
	else
		if pod.Vp then
			pod.Vp.Frame.Visible = false
			pod.Vp.Spin = false
		end
		pod.Empty.Visible = true
		pod.Empty.TextColor3 = C.Gold
		pod.Name.Text = "RESULT"
		pod.Name.TextColor3 = C.White
		pod.Halo.BackgroundColor3 = C.Pink
		if a and b and a.Species == b.Species then
			pod.Sub.Text = "Same kaiju + mutation"
		elseif a and b then
			pod.Sub.Text = "Mystery kaiju"
		else
			pod.Sub.Text = "Pick two kaijus"
		end
		if a and b then
			pod.Empty.TextColor3 = C.White
			rainbow(pod.Empty, 1.5)
			Kit.Pop(pod.Holder, 1.15, 0.4)
		end
	end
end

----------------------------------------------------------------------------
-- Probabilités
----------------------------------------------------------------------------

local function setFuseEnabled(on: boolean)
	Kit.SetDisabled(ui.Fuse, not on)
	setBreathing(ui.Fuse, on)
end

local function showOdds(list: { any }?, message: string?)
	for i, row in ui.OddsRows do
		local item = if list then list[i] else nil
		row.Frame.Visible = item ~= nil
		if item then
			local label, color = englishLabel(tostring(item.Label or "?"))
			local chance = tonumber(item.Chance) or 0
			row.Label.Text = label
			row.Pct.Text = Format.Percent(chance)
			row.Fill.BackgroundColor3 = color or C.Purple
			row.Fill.Size = UDim2.fromScale(0, 1)
			Kit.Tween(row.Fill, 0.5, { Size = UDim2.fromScale(math.clamp(chance, 0, 1), 1) }, Enum.EasingStyle.Quart)
			if string.find(label, "SECRET", 1, true) then
				rainbow(row.Fill, 2)
			else
				clearRainbow(row.Fill)
			end
			Kit.ScaleOf(row.Frame).Scale = 0.01
			task.delay(0.06 * i, function()
				Kit.Pop(row.Frame, 0.3, 0.4)
			end)
		end
	end
	ui.OddsMsg.Visible = message ~= nil
	ui.OddsMsg.Text = message or ""
end

local function requestOdds(attempt: number?)
	oddsToken += 1
	oddsReady = false
	setFuseEnabled(false)
	local a, b = slots.A, slots.B
	if not a or not b then
		showOdds(nil, "Pick <b>two ADULT kaijus</b> to see the fusion odds.")
		return
	end
	local token = oddsToken
	showOdds(nil, "Calculating odds...")
	task.spawn(function()
		local res = Remote.Call("FuseOdds", { A = a, B = b }, true)
		if token ~= oddsToken then
			return
		end
		if res.ok and type(res.odds) == "table" and #res.odds > 0 then
			showOdds(res.odds, nil)
			oddsReady = true
			Kit.Punch(ui.OddsHolder, 0.06)
			setFuseEnabled(true)
			popIn(ui.Fuse, 0, 1.25)
		else
			showOdds(nil, "Couldn't load the odds. Retrying...")
			-- nouvel essai limité (limite de débit du serveur)
			local n = (attempt or 0) + 1
			if n <= 3 then
				task.delay(1.2, function()
					if token == oddsToken and win.IsOpen then
						requestOdds(n)
					end
				end)
			else
				showOdds(nil, "Couldn't load the odds. Pick the kaijus again!")
			end
		end
	end)
end

----------------------------------------------------------------------------
-- Liste des kaijus éligibles
----------------------------------------------------------------------------

local function updateRowTags()
	for uid, row in rows do
		local tag = if slots.A == uid then "A" elseif slots.B == uid then "B" else nil
		row.Tag.Visible = tag ~= nil
		if tag then
			row.Tag.BackgroundColor3 = if tag == "A" then C.Pink else C.Cyan
			row.Tag.Text.Text = tag
		end
		row.Body.BackgroundColor3 = if tag then C.Gold else C.White
	end
end

local function slotsChanged(animateKey: string?)
	if animateKey then
		renderPod(animateKey, true)
	end
	updateRowTags()
	renderResult()
	requestOdds()
end

local function setSlot(key: string, uid: string?)
	slots[key] = uid
	slotsChanged(key)
end

local function pick(uid: string)
	if cinematic or busy then
		return
	end
	if slots.A == uid then
		setSlot("A", nil)
	elseif slots.B == uid then
		setSlot("B", nil)
	elseif not slots.A then
		setSlot("A", uid)
	else
		setSlot("B", uid)
	end
end

local function buildRow(rec: any): any
	local button = Kit.new("TextButton", {
		Name = rec.Uid,
		Size = UDim2.new(1, -8, 0, 66),
		BackgroundTransparency = 1,
		Text = "",
		AutoButtonColor = false,
		ZIndex = 6,
		Parent = ui.List,
	})
	Kit.new("Frame", {
		Name = "Shadow",
		Size = UDim2.fromScale(1, 1),
		Position = UDim2.fromOffset(4, 4),
		BackgroundColor3 = C.Ink,
		ZIndex = 6,
		Parent = button,
	}, { Kit.Corner(12) })
	local body = Kit.new("Frame", {
		Name = "Body",
		Size = UDim2.fromScale(1, 1),
		BackgroundColor3 = C.White,
		ZIndex = 7,
		Parent = button,
	}, { Kit.Corner(12), Kit.Stroke(3) })
	Kit.Gradient("Paper").Parent = body
	local thumb = Kit.new("Frame", {
		Name = "Thumb",
		Size = UDim2.fromOffset(54, 54),
		Position = UDim2.new(0, 6, 0.5, 0),
		AnchorPoint = Vector2.new(0, 0.5),
		BackgroundColor3 = C.White,
		ZIndex = 8,
		Parent = body,
	}, { Kit.Corner(10), Kit.Stroke(2) })
	local thumbGrad = Kit.Gradient({ C.White, C.White }, 90)
	thumbGrad.Parent = thumb
	local name = inkText({
		Name = "RName",
		Size = UDim2.new(1, -120, 0, 22),
		Position = UDim2.fromOffset(68, 8),
		Text = "",
		FontFace = F.Title,
		TextXAlignment = Enum.TextXAlignment.Left,
		MaxTextSize = 20,
		ZIndex = 8,
		Parent = body,
	})
	local sub = inkText({
		Name = "RSub",
		Size = UDim2.new(1, -120, 0, 16),
		Position = UDim2.fromOffset(68, 32),
		Text = "",
		TextXAlignment = Enum.TextXAlignment.Left,
		MaxTextSize = 15,
		ZIndex = 8,
		Parent = body,
	})
	local chip = Kit.Chip({
		Name = "Rarity",
		Text = "",
		Size = UDim2.fromOffset(84, 16),
		Position = UDim2.fromOffset(68, 48),
		ZIndex = 8,
		Parent = body,
	})
	local tag = Kit.Chip({
		Name = "Tag",
		Text = "A",
		Size = UDim2.fromOffset(40, 40),
		Position = UDim2.new(1, -10, 0.5, 0),
		AnchorPoint = Vector2.new(1, 0.5),
		ZIndex = 9,
		Parent = body,
	})
	tag.Visible = false
	local row = {
		Uid = rec.Uid,
		Button = button,
		Body = body,
		ThumbGradient = thumbGrad,
		Vp = Viewport.new({ Species = rec.Species, Mutation = rec.Mutation, Parent = thumb, ZIndex = 9, Spin = false }),
		Key = (rec.Species or "") .. ":" .. (rec.Mutation or ""),
		Name = name,
		Sub = sub,
		Chip = chip,
		Tag = tag,
	}
	button.MouseEnter:Connect(function()
		Audio.Play("ui_hover", { Cooldown = 0.06 })
		row.Vp.Spin = true
		row.Vp.Speed = 1.6
		Kit.Tween(Kit.ScaleOf(button), 0.2, { Scale = 1.03 }, Enum.EasingStyle.Back)
		Kit.Tween(button, 0.2, { Rotation = -1.2 }, Enum.EasingStyle.Back)
	end)
	button.MouseLeave:Connect(function()
		row.Vp.Spin = false
		Kit.Tween(Kit.ScaleOf(button), 0.2, { Scale = 1 })
		Kit.Tween(button, 0.2, { Rotation = 0 })
	end)
	button.Activated:Connect(function()
		Audio.Play("ui_click")
		Kit.Punch(button, 0.1)
		pick(row.Uid)
	end)
	return row
end

local function updateRow(row: any, rec: any)
	local key = (rec.Species or "") .. ":" .. (rec.Mutation or "")
	if key ~= row.Key then
		row.Key = key
		row.Vp:Set(rec.Species, rec.Mutation)
	end
	local rarity = Rarities.Get(rec.Rarity)
	local secret = rec.Rarity == "Secret"
	row.Name.Text = speciesName(rec.Species)
	local m = Mutations.Get(rec.Mutation)
	local stage = string.upper(Growth.Get(stageOf(rec)).Name)
	row.Sub.Text = if m
		then ("%s · <font color=\"#%s\"><b>%s x%s</b></font>"):format(stage, m.Color:ToHex(), string.upper(m.Name), tostring(m.Mult))
		else stage
	row.Chip.BackgroundColor3 = rarityColor(rec.Rarity)
	row.Chip.Text.Text = string.upper(rec.Rarity)
	if secret then
		rainbow(row.Chip, 2)
	end
	row.ThumbGradient.Color = if secret
		then ColorSequence.new(C.InkSoft, C.Ink)
		else ColorSequence.new(rarity.Glow, rarity.Color:Lerp(C.Ink, 0.15))
end

-- Synchronise la liste (création / suppression incrémentale des lignes).
local function syncList(animate: boolean)
	local list = {}
	for _, rec in State.Get("Kaijus") or {} do
		if eligible(rec) then
			table.insert(list, rec)
		end
	end
	table.sort(list, function(a, b)
		local ra, rb = Rarities.Get(a.Rarity).Order, Rarities.Get(b.Rarity).Order
		if ra ~= rb then
			return ra > rb
		end
		return Calc.BaseIncome(a) > Calc.BaseIncome(b)
	end)
	local keep = {}
	for i, rec in list do
		keep[rec.Uid] = true
		local row = rows[rec.Uid]
		if not row then
			row = buildRow(rec)
			rows[rec.Uid] = row
			if animate then
				Kit.ScaleOf(row.Button).Scale = 0.01
				task.delay(0.03 * math.min(i, 15), function()
					Kit.Pop(row.Button, 0.3, 0.4)
				end)
			end
		end
		row.Button.LayoutOrder = i
		updateRow(row, rec)
	end
	for uid, row in rows do
		if not keep[uid] then
			row.Vp:Destroy()
			row.Button:Destroy()
			rows[uid] = nil
		end
	end
	ui.ListCount.Text.Text = tostring(#list)
	ui.ListEmpty.Visible = #list == 0

	-- emplacements devenus invalides (vendu, volé, fusionné...)
	local changed = false
	for _, key in { "A", "B" } do
		local uid = slots[key]
		if uid and not keep[uid] then
			slots[key] = nil
			renderPod(key, true)
			changed = true
		end
	end
	if changed then
		slotsChanged(nil)
	else
		updateRowTags()
	end
end

----------------------------------------------------------------------------
-- Livre des recettes
----------------------------------------------------------------------------

local function refreshBook()
	for _, r in recipeRows do
		local s = r.Species
		local found = discovered(s.Id)
		r.Vp:SetSilhouette(not found)
		r.Name.Text = if found then s.Name else "???"
		local recipe = s.Recipe or {}
		if found then
			r.Recipe.Text = ("<b>%s</b>  +  <b>%s</b>"):format(speciesName(recipe[1]), speciesName(recipe[2]))
			r.Hint.Text = ("✓ Discovered! Fuse these two at %s+ again anytime."):format(string.upper(Growth.Get(s.RecipeStage or 3).Name))
		else
			r.Recipe.Text = "<b>???  +  ???</b>"
			r.Hint.Text = ('Hint: "%s" (both %s+)'):format(s.Hint or "...", string.upper(Growth.Get(s.RecipeStage or 3).Name))
		end
		r.Lock.Text = if found then "✓" else "🔒"
		r.Lock.TextColor3 = if found then C.Radioactive else C.Gold
	end
end

local function setBook(open: boolean)
	if bookOpen == open then
		return
	end
	bookOpen = open
	Kit.SetButtonText(ui.BookButton, if open then "BACK TO LAB" else "RECIPES")
	Kit.SetButtonColor(ui.BookButton, if open then "Magma" else "Ink")
	local book = ui.Book
	if open then
		refreshBook()
		book.Visible = true
		book.Position = UDim2.new(0, 306, 0, -30)
		Kit.Tween(book, 0.45, { Position = UDim2.fromOffset(306, 0) }, Enum.EasingStyle.Back)
		Kit.Pop(book, 0.7, 0.45)
		for i, r in recipeRows do
			Kit.ScaleOf(r.Frame).Scale = 0.01
			task.delay(0.05 * i, function()
				Kit.Pop(r.Frame, 0.3, 0.4)
			end)
			r.Vp.Spin = true
		end
	else
		Kit.Tween(Kit.ScaleOf(book), 0.18, { Scale = 0.6 }, Enum.EasingStyle.Quad, Enum.EasingDirection.In)
		task.delay(0.18, function()
			if not bookOpen then
				book.Visible = false
			end
		end)
		for _, r in recipeRows do
			r.Vp.Spin = false
		end
	end
end

local function buildBook(root: Instance)
	local holder, body = Kit.Panel({
		Name = "Book",
		Size = UDim2.fromOffset(550, 356),
		Position = UDim2.fromOffset(306, 0),
		Rotation = 0.8,
		Gradient = "Ink",
		Corner = 18,
		ZIndex = 40,
		Parent = root,
	})
	holder.Visible = false
	ui.Book = holder
	local title = Kit.Text({
		Size = UDim2.new(1, -40, 0, 34),
		Position = UDim2.fromOffset(20, 10),
		Text = "📖 SECRET RECIPES",
		MaxTextSize = 32,
		Stroke = 3,
		ZIndex = 41,
		Parent = body,
	})
	rainbow(title, 3)
	Kit.Text({
		Size = UDim2.new(1, -40, 0, 16),
		Position = UDim2.fromOffset(20, 44),
		Text = "Fuse the right two ADULT kaijus to create a SECRET. 100% guaranteed!",
		FontFace = F.Body,
		TextColor3 = C.Paper,
		MaxTextSize = 15,
		Stroke = false,
		ZIndex = 41,
		Parent = body,
	})
	local scroll = Kit.Scroll({
		Size = UDim2.new(1, -24, 1, -76),
		Position = UDim2.fromOffset(12, 66),
		ZIndex = 41,
		Parent = body,
	})
	scroll.ScrollBarImageColor3 = C.Paper
	Kit.List(Enum.FillDirection.Vertical, 8).Parent = scroll
	Kit.new("UIPadding", { PaddingRight = UDim.new(0, 12), PaddingTop = UDim.new(0, 4), PaddingBottom = UDim.new(0, 8), Parent = scroll })
	local order = 0
	for _, s in Kaijus.List do
		if s.Rarity == "Secret" then
			order += 1
			local frame = Kit.new("Frame", {
				Name = s.Id,
				Size = UDim2.new(1, -6, 0, 78),
				BackgroundColor3 = C.White,
				LayoutOrder = order,
				ZIndex = 42,
				Parent = scroll,
			}, { Kit.Corner(12), Kit.Stroke(3), Kit.Gradient("Paper") })
			local thumb = Kit.new("Frame", {
				Size = UDim2.fromOffset(64, 64),
				Position = UDim2.new(0, 7, 0.5, 0),
				AnchorPoint = Vector2.new(0, 0.5),
				BackgroundColor3 = C.White,
				ZIndex = 43,
				Parent = frame,
			}, { Kit.Corner(10), Kit.Stroke(2), Kit.Gradient({ C.InkSoft, C.Ink }) })
			local vp = Viewport.new({ Species = s.Id, Parent = thumb, ZIndex = 44, Spin = false, Speed = 1 })
			local name = Kit.Text({
				Size = UDim2.new(1, -140, 0, 22),
				Position = UDim2.fromOffset(80, 6),
				Text = "",
				TextXAlignment = Enum.TextXAlignment.Left,
				MaxTextSize = 20,
				Stroke = 2.5,
				ZIndex = 43,
				Parent = frame,
			})
			rainbow(name, 2.5)
			local recipe = inkText({
				Size = UDim2.new(1, -140, 0, 20),
				Position = UDim2.fromOffset(80, 30),
				Text = "",
				TextXAlignment = Enum.TextXAlignment.Left,
				MaxTextSize = 18,
				ZIndex = 43,
				Parent = frame,
			})
			local hint = inkText({
				Size = UDim2.new(1, -140, 0, 16),
				Position = UDim2.fromOffset(80, 54),
				Text = "",
				TextColor3 = C.InkSoft,
				TextXAlignment = Enum.TextXAlignment.Left,
				MaxTextSize = 14,
				ZIndex = 43,
				Parent = frame,
			})
			local lock = Kit.Text({
				Size = UDim2.fromOffset(44, 44),
				Position = UDim2.new(1, -10, 0.5, 0),
				AnchorPoint = Vector2.new(1, 0.5),
				Text = "🔒",
				FontFace = F.Body,
				Stroke = 2.5,
				ZIndex = 43,
				Parent = frame,
			})
			table.insert(recipeRows, { Species = s, Frame = frame, Vp = vp, Name = name, Recipe = recipe, Hint = hint, Lock = lock })
		end
	end
end

----------------------------------------------------------------------------
-- Cinématique
----------------------------------------------------------------------------

local function runCinematic(recA: any, recB: any, pending: { done: boolean, res: any })
	cinematic = true
	setBook(false)
	local overlay = ui.Overlay
	overlay:ClearAllChildren()
	Kit.Corner(16).Parent = overlay
	overlay.Visible = true
	overlay.BackgroundTransparency = 1
	Kit.Tween(overlay, 0.3, { BackgroundTransparency = 0.15 })
	local Z = 61

	-- anneau d'énergie
	local ring = Kit.new("Frame", {
		Size = UDim2.fromOffset(120, 120),
		Position = UDim2.fromScale(0.5, 0.42),
		AnchorPoint = Vector2.new(0.5, 0.5),
		BackgroundColor3 = C.Purple,
		BackgroundTransparency = 0.5,
		ZIndex = Z,
		Parent = overlay,
	}, { Kit.Round(), Kit.Stroke(5, C.Pink) })
	local charging = Kit.Text({
		Size = UDim2.fromOffset(520, 60),
		Position = UDim2.fromScale(0.5, 0.12),
		AnchorPoint = Vector2.new(0.5, 0.5),
		Text = "FUSING...",
		FontFace = F.Impact,
		TextColor3 = C.Radioactive,
		MaxTextSize = 60,
		Stroke = 4,
		Rotation = -3,
		ZIndex = Z + 5,
		Parent = overlay,
	})
	Kit.Pop(charging, 2.5, 0.4)

	local function inputVp(rec: any, x: number): any
		local holder = Kit.new("Frame", {
			Size = UDim2.fromOffset(190, 190),
			Position = UDim2.fromScale(x, 0.42),
			AnchorPoint = Vector2.new(0.5, 0.5),
			BackgroundTransparency = 1,
			ZIndex = Z + 1,
			Parent = overlay,
		})
		local vp = Viewport.new({ Species = rec.Species, Mutation = rec.Mutation, Parent = holder, ZIndex = Z + 2, Speed = 1.5 })
		Kit.Pop(holder, 0.3, 0.4)
		return { Holder = holder, Vp = vp }
	end
	local va = inputVp(recA, 0.24)
	local vb = inputVp(recB, 0.76)

	-- charge : glissement vers le centre, secousses croissantes
	Audio.Play("fusion_charge")
	local t0 = os.clock()
	local duration = 2
	local secondCharge = false
	local conn
	conn = RunService.RenderStepped:Connect(function()
		local t = math.clamp((os.clock() - t0) / duration, 0, 1)
		local e = t * t
		local k = 2 + 22 * e
		va.Holder.Position = UDim2.new(0.24 + 0.2 * e, (math.random() - 0.5) * k, 0.42, (math.random() - 0.5) * k)
		vb.Holder.Position = UDim2.new(0.76 - 0.2 * e, (math.random() - 0.5) * k, 0.42, (math.random() - 0.5) * k)
		va.Vp.Speed = 1.5 + 14 * e
		vb.Vp.Speed = -(1.5 + 14 * e)
		local size = 120 + 260 * e + math.sin(os.clock() * 30) * 12 * e
		ring.Size = UDim2.fromOffset(size, size)
		ring.BackgroundTransparency = 0.5 - 0.3 * e
		charging.Rotation = -3 + (math.random() - 0.5) * 6 * e
		overlay.BackgroundColor3 = C.Ink:Lerp(C.Purple, 0.35 * e * (0.5 + 0.5 * math.sin(os.clock() * 40)))
		if t > 0.5 and not secondCharge then
			secondCharge = true
			Audio.Play("fusion_charge", { Pitch = 1.35 })
			safeShake(win.Holder, 5, 0.9)
		end
	end)
	task.wait(duration)
	-- attente de la réponse du serveur (normalement déjà arrivée)
	local waited = 0
	while not pending.done and waited < 10 do
		waited += task.wait()
	end
	conn:Disconnect()
	overlay.BackgroundColor3 = C.Ink

	local res = pending.res
	if not res or not res.ok or not res.species then
		-- échec : fizzle
		Audio.Play("ui_error")
		charging.Text = "FUSION FAILED"
		charging.TextColor3 = C.Red
		Kit.Punch(charging, 0.3)
		Kit.Tween(va.Holder, 0.4, { Position = UDim2.fromScale(0.24, 0.42) }, Enum.EasingStyle.Back)
		Kit.Tween(vb.Holder, 0.4, { Position = UDim2.fromScale(0.76, 0.42) }, Enum.EasingStyle.Back)
		Kit.Tween(ring, 0.3, { Size = UDim2.fromOffset(0, 0) })
		task.wait(1.2)
		Kit.Tween(overlay, 0.25, { BackgroundTransparency = 1 })
		task.wait(0.25)
		va.Vp:Destroy()
		vb.Vp:Destroy()
		overlay.Visible = false
		overlay:ClearAllChildren()
		cinematic = false
		refreshAll(false)
		return
	end

	local speciesId = res.species
	local species = Kaijus.Get(speciesId)
	local rarityId = if species then species.Rarity else "Common"
	local rarity = Rarities.Get(rarityId)
	local secret = rarityId == "Secret"
	local mutation = Mutations.Get(res.mutation)

	-- FLASH
	va.Vp:Destroy()
	vb.Vp:Destroy()
	va.Holder:Destroy()
	vb.Holder:Destroy()
	ring:Destroy()
	charging:Destroy()
	local flash = Kit.new("Frame", {
		Size = UDim2.fromScale(1, 1),
		BackgroundColor3 = C.White,
		BackgroundTransparency = 0,
		ZIndex = Z + 20,
		Parent = overlay,
	}, { Kit.Corner(16) })
	Kit.Tween(flash, 0.7, { BackgroundTransparency = 1 }, Enum.EasingStyle.Quad)
	task.delay(0.75, function()
		flash:Destroy()
	end)
	Audio.Play(if secret then "hatch_secret" else "fusion_boom")
	if secret then
		Audio.Play("fusion_boom", { Volume = 0.6 })
	end
	safeShake(win.Holder, if secret then 20 else 12, 0.55)

	-- rayons
	local burst = Kit.Starburst({
		Size = UDim2.fromOffset(1000, 1000),
		Position = UDim2.fromScale(0.5, 0.42),
		Color = if secret then C.Gold else rarity.Glow,
		Transparency = 0.45,
		Rays = 16,
		Period = 9,
		ZIndex = Z,
		Parent = overlay,
	})
	Kit.Pop(burst, 0.1, 0.8)
	local burst2 = nil
	if secret then
		burst2 = Kit.Starburst({
			Size = UDim2.fromOffset(760, 760),
			Position = UDim2.fromScale(0.5, 0.42),
			Color = C.Pink,
			Transparency = 0.5,
			Rays = 10,
			Period = 6,
			ZIndex = Z,
			Parent = overlay,
		})
		Kit.Tween(burst2, 8, { Rotation = -360 }, Enum.EasingStyle.Linear)
		Kit.Pop(burst2, 0.1, 0.9)
	end

	-- kaiju résultat
	local resultHolder = Kit.new("Frame", {
		Size = UDim2.fromOffset(260, 260),
		Position = UDim2.fromScale(0.5, 0.4),
		AnchorPoint = Vector2.new(0.5, 0.5),
		BackgroundTransparency = 1,
		ZIndex = Z + 2,
		Parent = overlay,
	})
	local resultVp = Viewport.new({ Species = speciesId, Mutation = res.mutation, Parent = resultHolder, ZIndex = Z + 3, Speed = 1 })
	Kit.Pop(resultHolder, 0.05, 0.7)

	local nameLabel = Kit.Text({
		Size = UDim2.fromOffset(640, 64),
		Position = UDim2.fromScale(0.5, 0.74),
		AnchorPoint = Vector2.new(0.5, 0.5),
		Text = string.upper(if species then species.Name else speciesId),
		FontFace = F.Impact,
		TextColor3 = if secret then C.White else rarity.Color:Lerp(C.White, 0.2),
		MaxTextSize = 64,
		Stroke = 5,
		Rotation = -2,
		ZIndex = Z + 6,
		Parent = overlay,
	})
	nameLabel.Visible = false
	if secret then
		rainbow(nameLabel, 1.6)
	end
	local chips = Kit.new("Frame", {
		Size = UDim2.new(1, -40, 0, 32),
		Position = UDim2.fromScale(0.5, 0.84),
		AnchorPoint = Vector2.new(0.5, 0.5),
		BackgroundTransparency = 1,
		ZIndex = Z + 6,
		Parent = overlay,
	}, { Kit.List(Enum.FillDirection.Horizontal, 10, Enum.HorizontalAlignment.Center, Enum.VerticalAlignment.Center) })
	local rchip = Kit.Chip({ Text = string.upper(rarityId), Color = rarityColor(rarityId), AutoWidth = true, TextSize = 20, Size = UDim2.fromOffset(0, 32), LayoutOrder = 1, ZIndex = Z + 7, Parent = chips })
	if secret then
		rainbow(rchip, 1.5)
	end
	if mutation then
		Kit.Chip({
			Text = ("%s x%s"):format(string.upper(mutation.Name), tostring(mutation.Mult)),
			Color = mutation.Color,
			AutoWidth = true,
			TextSize = 20,
			Size = UDim2.fromOffset(0, 32),
			LayoutOrder = 2,
			ZIndex = Z + 7,
			Parent = chips,
		})
	end
	chips.Visible = false

	-- claquement du nom
	task.delay(0.45, function()
		nameLabel.Visible = true
		Kit.Pop(nameLabel, 3, 0.45)
		safeShake(win.Holder, 8, 0.3)
		task.delay(0.2, function()
			chips.Visible = true
			Kit.Pop(chips, 0.3, 0.4)
		end)
	end)

	local stamp: TextLabel? = nil
	if secret then
		task.delay(0.9, function()
			local s = Kit.Text({
				Size = UDim2.fromOffset(300, 90),
				Position = UDim2.fromScale(0.78, 0.2),
				AnchorPoint = Vector2.new(0.5, 0.5),
				Text = "SECRET!",
				FontFace = F.Impact,
				MaxTextSize = 90,
				Stroke = 6,
				ZIndex = Z + 8,
				Parent = overlay,
			})
			rainbow(s, 1.2)
			Kit.Pop(s, 4, 0.5)
			Kit.Wobble(s, 10, 0.5)
			stamp = s
			confetti(overlay, 36, { C.Gold, C.Pink, C.Cyan, C.Radioactive, C.Purple }, Z + 9)
			Audio.Play("hatch_secret", { Pitch = 1.2, Cooldown = 0 })
		end)
	else
		task.delay(0.5, function()
			confetti(overlay, 18, { rarity.Color, C.Gold, C.White }, Z + 9)
		end)
	end

	-- bouton de fin
	local finished = false
	local awesome
	awesome = Kit.Button({
		Text = if secret then "LEGENDARY!" else "AWESOME!",
		Color = "Radioactive",
		Size = UDim2.fromOffset(240, 60),
		Position = UDim2.new(0.5, 0, 1, -16),
		AnchorPoint = Vector2.new(0.5, 1),
		ZIndex = Z + 10,
		Parent = overlay,
		OnClick = function()
			if finished then
				return
			end
			finished = true
			Kit.Tween(overlay, 0.25, { BackgroundTransparency = 1 })
			Kit.Tween(Kit.ScaleOf(resultHolder), 0.2, { Scale = 0 }, Enum.EasingStyle.Back, Enum.EasingDirection.In)
			Kit.Tween(Kit.ScaleOf(nameLabel), 0.2, { Scale = 0 }, Enum.EasingStyle.Back, Enum.EasingDirection.In)
			Kit.Tween(Kit.ScaleOf(burst), 0.25, { Scale = 0 })
			if burst2 then
				Kit.Tween(Kit.ScaleOf(burst2), 0.25, { Scale = 0 })
			end
			if stamp then
				stamp.Visible = false
			end
			awesome.Visible = false
			task.delay(0.26, function()
				resultVp:Destroy()
				overlay.Visible = false
				overlay:ClearAllChildren()
				cinematic = false
				refreshAll(true)
			end)
		end,
	})
	awesome.Visible = false
	task.delay(1.3, function()
		if not finished then
			awesome.Visible = true
			Kit.Pop(awesome, 0.3, 0.45)
			task.delay(0.46, function()
				if awesome.Parent then
					Kit.Breathe(awesome, 0.06, 0.6)
				end
			end)
		end
	end)
end

function Fusion._Fuse()
	if busy or cinematic then
		return
	end
	local a, b = slots.A, slots.B
	local recA, recB = findRecord(a), findRecord(b)
	if not a or not b or not recA or not recB then
		Audio.Play("ui_error")
		return
	end
	if not oddsReady then
		-- les probabilités doivent être visibles avant toute fusion
		Audio.Play("ui_error")
		safeShake(ui.OddsHolder, 6, 0.3)
		return
	end
	busy = true
	setFuseEnabled(false)
	oddsToken += 1
	local pending = { done = false, res = nil :: any }
	task.spawn(function()
		pending.res = Remote.Call("Fuse", { A = a, B = b })
		pending.done = true
	end)
	-- les emplacements se vident pendant la cinématique
	slots.A = nil
	slots.B = nil
	renderPod("A", false)
	renderPod("B", false)
	renderResult()
	updateRowTags()
	runCinematic(recA, recB, pending)
	busy = false
	local res = pending.res
	if res and res.ok and res.species then
		local species = Kaijus.Get(res.species)
		local secret = species ~= nil and species.Rarity == "Secret"
		UIRegistry.Toast(("%s %s joined your base!"):format(if secret then "🌈 SECRET" else "🧪", if species then species.Name else "A new kaiju"), if secret then "Rare" else "Good")
	end
end

----------------------------------------------------------------------------
-- Construction
----------------------------------------------------------------------------

local function build()
	win = Kit.Window({
		Name = "Fusion",
		Title = "FUSION LAB",
		Icon = "🧪",
		Color = "Purple",
		Size = UDim2.fromOffset(900, 580),
		RibbonWidth = 340,
		Rotation = 1,
	})
	local root: Frame = win.Frame
	ui.Root = root

	--------------------------------------------------------------- liste
	local listHolder, listBody = Kit.Panel({
		Name = "ListPanel",
		Size = UDim2.fromOffset(290, 490),
		Position = UDim2.fromOffset(0, 2),
		Rotation = -1.2,
		Parent = root,
	})
	ui.ListHolder = listHolder
	inkText({
		Size = UDim2.new(1, -80, 0, 26),
		Position = UDim2.fromOffset(14, 10),
		Text = "ADULT KAIJUS",
		FontFace = F.Title,
		TextXAlignment = Enum.TextXAlignment.Left,
		MaxTextSize = 24,
		ZIndex = 3,
		Parent = listBody,
	})
	ui.ListCount = Kit.Chip({
		Text = "0",
		Color = C.Purple,
		Size = UDim2.fromOffset(48, 26),
		Position = UDim2.new(1, -12, 0, 10),
		AnchorPoint = Vector2.new(1, 0),
		ZIndex = 4,
		Parent = listBody,
	})
	inkText({
		Size = UDim2.new(1, -28, 0, 16),
		Position = UDim2.fromOffset(14, 38),
		Text = "Tap to fill slot A, then B. Tap again to remove.",
		TextColor3 = C.InkSoft,
		TextXAlignment = Enum.TextXAlignment.Left,
		MaxTextSize = 14,
		ZIndex = 3,
		Parent = listBody,
	})
	local list = Kit.Scroll({
		Name = "List",
		Size = UDim2.new(1, -12, 1, -70),
		Position = UDim2.fromOffset(8, 60),
		ZIndex = 5,
		Parent = listBody,
	})
	Kit.List(Enum.FillDirection.Vertical, 10).Parent = list
	Kit.new("UIPadding", { PaddingTop = UDim.new(0, 4), PaddingBottom = UDim.new(0, 10), PaddingRight = UDim.new(0, 8), Parent = list })
	ui.List = list
	ui.ListEmpty = inkText({
		Size = UDim2.new(1, -40, 0, 120),
		Position = UDim2.fromScale(0.5, 0.45),
		AnchorPoint = Vector2.new(0.5, 0.5),
		Text = "No ADULT kaijus yet!\n\nFeed and grow your kaijus to the <b>ADULT</b> stage (3) to fuse them.",
		TextWrapped = true,
		TextColor3 = C.InkSoft,
		MaxTextSize = 18,
		ZIndex = 6,
		Parent = listBody,
	})

	--------------------------------------------------------------- labo
	local lab = Kit.new("Frame", {
		Name = "Lab",
		Size = UDim2.fromOffset(550, 500),
		Position = UDim2.fromOffset(306, 0),
		BackgroundTransparency = 1,
		ZIndex = 5,
		Parent = root,
	})
	ui.Lab = lab
	pods.A = buildPod(lab, "A", 0, -2, "Ink")
	pods.B = buildPod(lab, "B", 200, 1.5, "Ink")
	pods.R = buildPod(lab, "R", 400, -1, "Purple")
	for _, key in { "A", "B" } do
		pods[key].Click.Activated:Connect(function()
			if cinematic or busy then
				return
			end
			if slots[key] then
				Audio.Play("ui_close")
				setSlot(key, nil)
			else
				Audio.Play("ui_error")
				safeShake(ui.ListHolder, 5, 0.3)
			end
		end)
	end
	local function op(text: string, x: number)
		local l = Kit.Text({
			Size = UDim2.fromOffset(44, 60),
			Position = UDim2.fromOffset(x, 98),
			AnchorPoint = Vector2.new(0.5, 0.5),
			Text = text,
			FontFace = F.Impact,
			TextColor3 = C.Gold,
			MaxTextSize = 60,
			Stroke = 4,
			ZIndex = 8,
			Parent = lab,
		})
		Kit.Wobble(l, 8, 0.7)
		return l
	end
	ui.Plus = op("+", 176)
	ui.Equals = op("=", 376)

	-- probabilités
	local oddsHolder, oddsBody = Kit.Panel({
		Name = "Odds",
		Size = UDim2.fromOffset(550, 150),
		Position = UDim2.fromOffset(0, 206),
		Rotation = 0.6,
		Parent = lab,
	})
	ui.OddsHolder = oddsHolder
	Kit.Text({
		Size = UDim2.fromOffset(200, 24),
		Position = UDim2.fromOffset(14, 8),
		Text = "🎲 FUSION ODDS",
		TextXAlignment = Enum.TextXAlignment.Left,
		TextColor3 = C.Purple,
		MaxTextSize = 22,
		Stroke = 2.5,
		ZIndex = 3,
		Parent = oddsBody,
	})
	inkText({
		Size = UDim2.fromOffset(300, 16),
		Position = UDim2.new(1, -14, 0, 12),
		AnchorPoint = Vector2.new(1, 0),
		Text = "Both kaijus are consumed by the fusion.",
		TextColor3 = C.MagmaDark,
		TextXAlignment = Enum.TextXAlignment.Right,
		MaxTextSize = 14,
		ZIndex = 3,
		Parent = oddsBody,
	})
	local oddsList = Kit.new("Frame", {
		Size = UDim2.new(1, -28, 1, -44),
		Position = UDim2.fromOffset(14, 38),
		BackgroundTransparency = 1,
		ZIndex = 3,
		Parent = oddsBody,
	}, { Kit.List(Enum.FillDirection.Vertical, 5) })
	ui.OddsRows = {}
	for i = 1, MAX_ODDS do
		local row = Kit.new("Frame", {
			Name = "Row" .. i,
			Size = UDim2.new(1, 0, 0, 29),
			BackgroundColor3 = C.Paper,
			LayoutOrder = i,
			Visible = false,
			ZIndex = 4,
			Parent = oddsList,
		}, { Kit.Corner(8), Kit.Stroke(2.5) })
		local fillClip = Kit.new("CanvasGroup", {
			Size = UDim2.fromScale(1, 1),
			BackgroundTransparency = 1,
			ZIndex = 4,
			Parent = row,
		}, { Kit.Corner(8) })
		local fill = Kit.new("Frame", {
			Size = UDim2.fromScale(0, 1),
			BackgroundColor3 = C.Purple,
			BackgroundTransparency = 0.35,
			BorderSizePixel = 0,
			ZIndex = 4,
			Parent = fillClip,
		})
		local label = inkText({
			Size = UDim2.new(1, -90, 0, 20),
			Position = UDim2.new(0, 10, 0.5, 0),
			AnchorPoint = Vector2.new(0, 0.5),
			Text = "",
			TextXAlignment = Enum.TextXAlignment.Left,
			MaxTextSize = 18,
			ZIndex = 5,
			Parent = row,
		})
		local pct = Kit.Text({
			Size = UDim2.fromOffset(80, 24),
			Position = UDim2.new(1, -10, 0.5, 0),
			AnchorPoint = Vector2.new(1, 0.5),
			Text = "",
			TextXAlignment = Enum.TextXAlignment.Right,
			MaxTextSize = 22,
			Stroke = 2.5,
			ZIndex = 5,
			Parent = row,
		})
		ui.OddsRows[i] = { Frame = row, Fill = fill, Label = label, Pct = pct }
	end
	ui.OddsMsg = inkText({
		Size = UDim2.new(1, -40, 0, 40),
		Position = UDim2.new(0.5, 0, 0, 70),
		AnchorPoint = Vector2.new(0.5, 0),
		Text = "",
		TextWrapped = true,
		TextColor3 = C.InkSoft,
		MaxTextSize = 18,
		ZIndex = 4,
		Parent = oddsBody,
	})

	-- boutons
	local fuseWrap = Kit.new("Frame", {
		Name = "FuseWrap",
		Size = UDim2.fromOffset(318, 92),
		Position = UDim2.fromOffset(0, 374),
		BackgroundTransparency = 1,
		ZIndex = 10,
		Parent = lab,
	}, { Kit.List(Enum.FillDirection.Vertical, 0, Enum.HorizontalAlignment.Left) })
	ui.FuseWrap = fuseWrap
	ui.Fuse = Kit.Button({
		Name = "Fuse",
		Text = "FUSE!",
		Icon = "🧪",
		IconSize = 40,
		TextSize = 40,
		Color = "Pink",
		Size = UDim2.fromOffset(318, 84),
		Corner = 20,
		ZIndex = 10,
		Parent = fuseWrap,
		OnClick = function()
			Fusion._Fuse()
		end,
	})
	ui.BookButton = Kit.Button({
		Name = "Book",
		Text = "RECIPES",
		Icon = "📖",
		IconSize = 28,
		TextSize = 24,
		Color = "Ink",
		Size = UDim2.fromOffset(212, 66),
		Position = UDim2.fromOffset(336, 383),
		ZIndex = 10,
		Parent = lab,
		OnClick = function()
			setBook(not bookOpen)
		end,
	})

	ui.Fuse.Activated:Connect(function()
		if ui.Fuse:GetAttribute("Disabled") then
			safeShake(fuseWrap, 5, 0.3)
			if slots.A and slots.B then
				safeShake(ui.OddsHolder, 4, 0.3)
			else
				safeShake(ui.ListHolder, 4, 0.3)
			end
		end
	end)

	buildBook(root)

	-- calque de cinématique (bloque les clics)
	ui.Overlay = Kit.new("TextButton", {
		Name = "Cinematic",
		Size = UDim2.new(1, 20, 1, 20),
		Position = UDim2.fromOffset(-10, -10),
		BackgroundColor3 = C.Ink,
		BackgroundTransparency = 1,
		AutoButtonColor = false,
		Text = "",
		Visible = false,
		ZIndex = 60,
		Parent = root,
	})
end

refreshAll = function(animate: boolean)
	syncList(animate)
	renderPod("A", false)
	renderPod("B", false)
	renderResult()
	requestOdds()
	if bookOpen then
		refreshBook()
	end
end

----------------------------------------------------------------------------
-- Interface publique
----------------------------------------------------------------------------

function Fusion.Init()
	build()
	setFuseEnabled(false)
	showOdds(nil, "Pick <b>two ADULT kaijus</b> to see the fusion odds.")
	renderPod("A", false)
	renderPod("B", false)
	renderResult()

	State.Changed("Kaijus"):Connect(function()
		if win.IsOpen and not cinematic then
			syncList(true)
		end
	end)
	State.Changed("Index"):Connect(function()
		if win.IsOpen and bookOpen then
			refreshBook()
		end
	end)

	win.Opened:Connect(function()
		-- vérification périodique : vols en cours / changements de stade
		if pollConn then
			pollConn:Disconnect()
		end
		accum = 0
		pollConn = RunService.Heartbeat:Connect(function(dt)
			accum += dt
			if accum >= 0.75 then
				accum = 0
				if not cinematic and not busy then
					syncList(false)
				end
			end
		end)
	end)
	win.Closed:Connect(function()
		if pollConn then
			pollConn:Disconnect()
			pollConn = nil
		end
		for _, pod in pods do
			if pod.Vp then
				pod.Vp.Spin = false
			end
		end
		for _, row in rows do
			row.Vp.Spin = false
		end
		setBook(false)
	end)
end

function Fusion.Open(args: any?)
	if args == Fusion then
		args = nil
	end
	win:Open()
	syncList(true)
	-- présélection de l'emplacement A
	local want = if type(args) == "table" then args.A else nil
	if want and not cinematic then
		local rec = findRecord(want)
		if rec and eligible(rec) then
			if slots.B == want then
				slots.B = nil
				renderPod("B", false)
			end
			slots.A = want
			renderPod("A", true)
		elseif rec then
			UIRegistry.Toast("Only ADULT kaijus (stage 3+) can be fused!", "Bad")
		end
	end
	for _, key in { "A", "B" } do
		local pod = pods[key]
		if pod.Vp and pod.Vp.Frame.Visible then
			pod.Vp.Spin = true
		end
	end
	updateRowTags()
	renderResult()
	requestOdds()

	-- apparition en cascade
	local items = { ui.ListHolder, pods.A.Holder, ui.Plus, pods.B.Holder, ui.Equals, pods.R.Holder, ui.OddsHolder, ui.Fuse, ui.BookButton }
	for i, item in items do
		popIn(item, 0.04 * i)
	end
end

function Fusion.Close()
	if win then
		win:Close()
	end
end

return Fusion
