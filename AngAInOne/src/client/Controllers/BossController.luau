--!strict
--[[
	BossController : le combat contre LAGZ vu par le joueur LOCAL (monde 7, arène W7Arena).
	Le serveur (BossService) décide de tout ; ce contrôleur ne fait que l'habillage et relaie
	les prises antivirus. État lu dans les attributs du joueur : BossPhase (Util/BossLogic),
	BossSince (heure serveur du début de la phase), BossPlugs (masque des prises branchées).

	- Pièges de l'arène (tag BossTrap, attribut BossPhases) : actifs seulement pendant leurs
	  phases. Sinon le tag Trap est retiré LOCALEMENT (TrapController les oublie), la pièce est
	  remise à sa pose de repos (attribut Rest) et cachée ; les fragments (Vanish) restent un
	  sol fixe et solide. Phase 1 : lasers + curseur ; phase 2 : fragments + virus + curseur.
	- Barrières (tag BossBarrier) : solides et visibles pendant les phases 1–2 (arène verrouillée).
	- LAGZ (tag BossLagz) : flotte, regarde le joueur, glitche pendant le combat, tire ses lasers
	  (faisceaux vers les pièges Laser actifs), titube une fois le bouclier (tag BossShield) brisé,
	  explose en pixels quand le monde 7 est nettoyé.
	- Prises antivirus (tag BossPlug, attribut Index) : en phase 2, marcher dessus envoie
	  Net.Fire("BossPlug", index) (le serveur vérifie la distance) ; étiquette au-dessus.
	- Interface : bandeau LAGZ (chrono de survie, prises 3/3, terminal ouvert) + répliques
	  (Dialogue) et notifications (Toasts) à chaque changement de phase.
]]

local CollectionService = game:GetService("CollectionService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local Workspace = game:GetService("Workspace")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local BossLogic = require(Shared.Util.BossLogic)
local Tower = require(Shared.Config.Tower)

local Net = require(script.Parent.Net)
local Audio = require(script.Parent.Audio)
local UI = script.Parent.Parent.UI
local Create = require(UI.Create)
local Dialogue = require(UI.Screens.Dialogue)
local Toasts = require(UI.Screens.Toasts)
local LagzFace = require(UI.Components.Lagz)

local New = Create.New

local BossController = {}

local PHASE = BossLogic.Phase
local player = Players.LocalPlayer

local ANIMATE_RADIUS = 400 -- LAGZ animé si la caméra est à moins de cette distance
local PLUG_RADIUS = 3.4 -- pieds sur la prise (demi-largeur 2,5 + tolérance)
local PLUG_RETRY = 0.75

local LILAC = Color3.fromHex("E9D8FD")
local VIOLET = Color3.fromHex("9F7AEA")
local CYAN = Color3.fromHex("4FD1C5")
local GREEN = Color3.fromHex("68D391")
local MAGENTA = Color3.fromHex("ED64A6")
local WARN_TINT = Color3.fromRGB(196, 120, 220) -- fragments en phase 2 (pas rouge : ils ne tuent pas)

local phase = PHASE.Idle
local since = 0
local mask = 0

------------------------------------------------------------------------------------
-- Outils
------------------------------------------------------------------------------------

-- Cache / montre une pièce et ses pièces soudées (transparence locale).
local function setShown(root: Instance, shown: boolean)
	local value = if shown then 0 else 1
	if root:IsA("BasePart") then
		root.LocalTransparencyModifier = value
	end
	for _, d in root:GetDescendants() do
		if d:IsA("BasePart") then
			d.LocalTransparencyModifier = value
		end
	end
end

local function pick(list: { string }): string
	return list[math.random(1, #list)]
end

local function lagzSays(text: string, delay: number?)
	task.delay(delay or 0, function()
		Dialogue.Say(text, 3.5, "LAGZ")
	end)
end

local function angaSays(text: string, delay: number?)
	task.delay(delay or 0, function()
		Dialogue.Say(text, 4.5, "Anga")
	end)
end

-- Suit un tag (streaming : arrivée / départ des instances).
local function track(tag: string, added: (Instance) -> (), removed: ((Instance) -> ())?)
	for _, instance in CollectionService:GetTagged(tag) do
		task.spawn(added, instance)
	end
	CollectionService:GetInstanceAddedSignal(tag):Connect(added)
	if removed then
		CollectionService:GetInstanceRemovedSignal(tag):Connect(removed)
	end
end

------------------------------------------------------------------------------------
-- Pièges de l'arène, barrières, bouclier
------------------------------------------------------------------------------------

local bossTraps: { [BasePart]: Color3 } = {} -- pièce -> couleur d'origine
local barriers: { [BasePart]: boolean } = {}
local shields: { [BasePart]: Vector3 } = {} -- bouclier -> taille d'origine
local beams: { [BasePart]: Beam } = {} -- laser -> faisceau tiré par LAGZ

local function applyTrap(part: BasePart)
	local active = BossLogic.PhaseActive(part:GetAttribute("BossPhases"), phase)
	local kind = part:GetAttribute("Kind")
	local color = bossTraps[part]
	if active then
		setShown(part, true)
		if kind == "Vanish" and color then
			part.Color = color:Lerp(WARN_TINT, 0.55)
		end
		if not part:HasTag("Trap") then
			-- TrapController le reprend : sa pose de repos est le CFrame actuel, remis au repos
			local rest = part:GetAttribute("Rest")
			if typeof(rest) == "CFrame" then
				part.CFrame = rest
			end
			part:AddTag("Trap")
		end
	else
		if part:HasTag("Trap") then
			part:RemoveTag("Trap")
		end
		local rest = part:GetAttribute("Rest")
		if typeof(rest) == "CFrame" then
			part.CFrame = rest
		end
		if kind == "Vanish" then
			-- Fragment au repos : sol fixe, solide et visible
			setShown(part, true)
			part.CanCollide = true
			if color then
				part.Color = color
			end
		else
			setShown(part, false)
		end
	end
	local beam = beams[part]
	if beam then
		beam.Enabled = active
	end
end

local function applyBarrier(part: BasePart)
	local locked = BossLogic.Fighting(phase)
	part.CanCollide = locked
	part.Transparency = if locked then 0.35 else 1
end

local shieldPop = -math.huge -- heure (os.clock) où le bouclier a éclaté

-- Bouclier levé (phases 0–2) ; brisé ensuite (l'animation d'éclatement est dans step).
local function applyShield(part: BasePart)
	local up = phase == PHASE.Idle or BossLogic.Fighting(phase)
	if up then
		local size = shields[part]
		if size then
			part.Size = size
		end
		part.LocalTransparencyModifier = 0
	elseif os.clock() - shieldPop > 0.6 then
		part.LocalTransparencyModifier = 1
	end
end

local function applyAll()
	for part in bossTraps do
		if part.Parent then
			applyTrap(part)
		end
	end
	for part in barriers do
		if part.Parent then
			applyBarrier(part)
		end
	end
	for part in shields do
		if part.Parent then
			applyShield(part)
		end
	end
end

------------------------------------------------------------------------------------
-- LAGZ : animation, lasers, explosion
------------------------------------------------------------------------------------

type Lagz = { Model: Model, Rest: CFrame, Eye: Attachment? }
local lagzes: { [Model]: Lagz } = {}
local debris: { { Part: BasePart, Velocity: Vector3, Born: number } } = {}
local explodeAt = -math.huge

-- Attache « œil » de LAGZ : origine des faisceaux laser.
local function eyeOf(lagz: Lagz): Attachment?
	local existing = lagz.Eye
	if existing and existing.Parent then
		return existing
	end
	local model = lagz.Model
	local holder = model.PrimaryPart or model:FindFirstChildWhichIsA("BasePart", true)
	if not holder then
		return nil
	end
	local eye = Instance.new("Attachment")
	eye.Name = "LagzEye"
	eye.Parent = holder
	eye.WorldPosition = (lagz.Rest * CFrame.new(0, 6, -4.6)).Position
	lagz.Eye = eye
	return eye
end

-- Faisceau LAGZ -> laser (activé seulement quand le laser est actif).
local function linkBeam(part: BasePart)
	if beams[part] or part:GetAttribute("Kind") ~= "Laser" then
		return
	end
	for _, lagz in lagzes do
		local eye = eyeOf(lagz)
		if eye then
			local target = Instance.new("Attachment")
			target.Name = "LagzBeamEnd"
			target.Parent = part
			local beam = Instance.new("Beam")
			beam.Name = "LagzBeam"
			beam.Attachment0 = eye
			beam.Attachment1 = target
			beam.Color = ColorSequence.new(MAGENTA, Color3.fromRGB(255, 46, 84))
			beam.LightEmission = 1
			beam.FaceCamera = true
			beam.Width0 = 0.5
			beam.Width1 = 0.25
			beam.Transparency = NumberSequence.new(0.15, 0.45)
			beam.Enabled = false
			beam.Parent = part
			beams[part] = beam
			return
		end
	end
end

local function spawnDebris(center: Vector3)
	for k = 1, 16 do
		local part: BasePart = Instance.new("Part")
		part.Name = "LagzPixel"
		part.Anchored = true
		part.CanCollide = false
		part.CanQuery = false
		part.CanTouch = false
		part.CastShadow = false
		part.Material = Enum.Material.Neon
		part.Size = Vector3.one * (0.8 + math.random() * 1.2)
		part.Color = if k % 3 == 0 then CYAN elseif k % 3 == 1 then MAGENTA else VIOLET
		part.CFrame = CFrame.new(center)
		part.Parent = Workspace
		local direction = Vector3.new(math.random() - 0.5, math.random() * 0.8 + 0.2, math.random() - 0.5).Unit
		table.insert(debris, { Part = part, Velocity = direction * (18 + math.random() * 16), Born = os.clock() })
	end
end

local function animateLagz(lagz: Lagz, t: number, root: BasePart?)
	local model = lagz.Model
	if not model.Parent then
		return
	end
	if phase == PHASE.Defeated then
		if os.clock() - explodeAt > 0.25 then
			setShown(model, false)
		end
		return
	end
	setShown(model, true)
	local rest = lagz.Rest
	local position = rest.Position
	local fighting = BossLogic.Fighting(phase)
	local bob = math.sin(t * (if fighting then 2.6 else 1.4)) * (if fighting then 1.2 else 0.7)
	local offset = Vector3.new(0, bob, 0)
	local tilt = CFrame.identity
	if phase == PHASE.Terminal then
		-- Sonné : plus bas, il titube
		offset += Vector3.new(0, -3, 0)
		tilt = CFrame.Angles(math.sin(t * 3) * 0.25, 0, math.cos(t * 2.3) * 0.25)
	elseif fighting and math.floor(t * 8) % 7 == 0 then
		-- Glitch : petits sauts de côté
		offset += Vector3.new(math.sin(t * 91) * 0.8, 0, math.cos(t * 77) * 0.8)
	end
	local look = rest.LookVector
	if root then
		local flat = (root.Position - position) * Vector3.new(1, 0, 1)
		if flat.Magnitude > 1 then
			look = flat.Unit
		end
	end
	local pivot = CFrame.lookAt(position + offset, position + offset + look) * tilt
	model:PivotTo(pivot)
end

------------------------------------------------------------------------------------
-- Prises antivirus
------------------------------------------------------------------------------------

type Plug = { Part: BasePart, Index: number, Label: BillboardGui?, Text: TextLabel? }
local plugs: { [BasePart]: Plug } = {}
local lastPlugFire: { [number]: number } = {}

local function applyPlug(plug: Plug)
	local done = BossLogic.MaskHas(mask, plug.Index)
	local pending = phase == PHASE.Plugs and not done
	plug.Part.Color = if done then GREEN elseif pending then CYAN else VIOLET
	local label = plug.Label
	if label then
		label.Enabled = pending or (phase == PHASE.Plugs and done)
	end
	local text = plug.Text
	if text then
		text.Text = if done then `PRISE {plug.Index} ✓` else `PRISE ANTIVIRUS {plug.Index}`
		text.TextColor3 = if done then GREEN else LILAC
	end
end

local function addPlug(instance: Instance)
	local index = instance:GetAttribute("Index")
	if not instance:IsA("BasePart") or type(index) ~= "number" or plugs[instance] then
		return
	end
	local part = instance :: BasePart
	local label = New("BillboardGui", {
		Name = "PlugLabel",
		Size = UDim2.fromOffset(170, 34),
		StudsOffset = Vector3.new(0, 7, 0),
		AlwaysOnTop = true,
		LightInfluence = 0,
		MaxDistance = 140,
		Enabled = false,
		Parent = part,
	})
	local text = New("TextLabel", {
		Size = UDim2.fromScale(1, 1),
		BackgroundColor3 = Color3.fromRGB(20, 16, 36),
		BackgroundTransparency = 0.25,
		Font = Enum.Font.GothamBlack,
		TextScaled = true,
		TextColor3 = LILAC,
		Text = "",
		Parent = label,
	}, { Create.Corner(8) :: Instance, Create.Padding(4, 8) })
	local plug: Plug = { Part = part, Index = index, Label = label, Text = text }
	plugs[part] = plug
	applyPlug(plug)
end

local function checkPlugs(root: BasePart)
	if phase ~= PHASE.Plugs then
		return
	end
	local feet = root.Position - Vector3.new(0, 3, 0)
	local now = os.clock()
	for part, plug in plugs do
		if BossLogic.MaskHas(mask, plug.Index) or not part.Parent then
			continue
		end
		local p = part.Position
		local flat = Vector3.new(feet.X - p.X, 0, feet.Z - p.Z).Magnitude
		if flat <= PLUG_RADIUS and math.abs(feet.Y - p.Y) <= 3 then
			if now - (lastPlugFire[plug.Index] or -math.huge) >= PLUG_RETRY then
				lastPlugFire[plug.Index] = now
				Net.Fire("BossPlug", plug.Index)
			end
		end
	end
end

------------------------------------------------------------------------------------
-- Interface : bandeau LAGZ
------------------------------------------------------------------------------------

local bar: Frame? = nil
local status: TextLabel? = nil
local fill: Frame? = nil

local function buildBar(layer: Instance)
	local frame = New("Frame", {
		Name = "BossBar",
		AnchorPoint = Vector2.new(0, 0.5),
		Position = UDim2.new(0, 16, 0.42, 0),
		Size = UDim2.fromOffset(300, 84),
		BackgroundColor3 = Color3.fromRGB(24, 18, 42),
		BackgroundTransparency = 0.12,
		BorderSizePixel = 0,
		Visible = false,
		Parent = layer,
	}, {
		Create.Corner(14),
		New("UIStroke", { Color = VIOLET, Thickness = 2, Transparency = 0.2 }),
	})
	local face = LagzFace.Face(64, frame)
	face.Position = UDim2.fromOffset(8, 10)
	New("TextLabel", {
		Name = "Title",
		Position = UDim2.fromOffset(80, 8),
		Size = UDim2.new(1, -90, 0, 22),
		BackgroundTransparency = 1,
		Font = Enum.Font.GothamBlack,
		TextXAlignment = Enum.TextXAlignment.Left,
		TextScaled = true,
		TextColor3 = LILAC,
		Text = "LAGZ",
		Parent = frame,
	})
	status = New("TextLabel", {
		Name = "Status",
		Position = UDim2.fromOffset(80, 32),
		Size = UDim2.new(1, -90, 0, 20),
		BackgroundTransparency = 1,
		Font = Enum.Font.GothamBold,
		TextXAlignment = Enum.TextXAlignment.Left,
		TextScaled = true,
		TextColor3 = Color3.new(1, 1, 1),
		Text = "",
		Parent = frame,
	})
	local track_ = New("Frame", {
		Name = "Track",
		Position = UDim2.fromOffset(80, 60),
		Size = UDim2.new(1, -92, 0, 12),
		BackgroundColor3 = Color3.fromRGB(46, 36, 76),
		BorderSizePixel = 0,
		Parent = frame,
	}, { Create.Corner(6) })
	fill = New("Frame", {
		Name = "Fill",
		Size = UDim2.fromScale(1, 1),
		BackgroundColor3 = MAGENTA,
		BorderSizePixel = 0,
		Parent = track_,
	}, { Create.Corner(6) })
	bar = frame
end

local function updateBar(now: number)
	local frame, label, bar_ = bar, status, fill
	if not frame or not label or not bar_ then
		return
	end
	local visible = phase == PHASE.Lasers or phase == PHASE.Plugs or phase == PHASE.Terminal
	frame.Visible = visible
	if not visible then
		return
	end
	if phase == PHASE.Lasers then
		local remaining = BossLogic.Remaining(phase, since, now)
		label.Text = `Survis ! Bouclier actif · {math.ceil(remaining)} s`
		bar_.Size = UDim2.fromScale(remaining / BossLogic.LASER_SECONDS, 1)
		bar_.BackgroundColor3 = MAGENTA
	elseif phase == PHASE.Plugs then
		local count = 0
		for i = 1, BossLogic.PLUG_COUNT do
			if BossLogic.MaskHas(mask, i) then
				count += 1
			end
		end
		label.Text = `Prises antivirus : {count}/{BossLogic.PLUG_COUNT}`
		bar_.Size = UDim2.fromScale(1 - count / BossLogic.PLUG_COUNT, 1)
		bar_.BackgroundColor3 = VIOLET
	else
		label.Text = "Bouclier détruit ! Va au terminal final"
		bar_.Size = UDim2.fromScale(0.02, 1)
		bar_.BackgroundColor3 = GREEN
	end
end

------------------------------------------------------------------------------------
-- Changements de phase (répliques, sons)
------------------------------------------------------------------------------------

local function onPhase(previous: number, current: number)
	if current == PHASE.Lasers and previous == PHASE.Idle then
		Audio.Play("Error", 0.7)
		lagzSays("Tu oses entrer dans MON arène ? Chargement de ta défaite : 99 % !")
		angaSays("Cours ! Saute par-dessus ses lasers et ne reste jamais sous le curseur !", 0.5)
	elseif current == PHASE.Plugs then
		Audio.Play("Zap", 0.7)
		lagzSays("Grrr ! Mon sol se fragmente… et voilà mes virus !")
		angaSays("Branche les 3 prises antivirus pour casser son bouclier !", 0.5)
	elseif current == PHASE.Terminal and previous == PHASE.Plugs then
		shieldPop = os.clock()
		Audio.Play("Unlock")
		Toasts.Show("Success", "Bouclier de LAGZ détruit !")
		lagzSays("Mon bouclier ! NOOOON !")
		angaSays("Son bouclier est tombé ! Fonce au terminal final, derrière lui !", 0.5)
	elseif current == PHASE.Idle and BossLogic.Fighting(previous) then
		lagzSays(pick({
			"Hé hé ! Tout est à recommencer !",
			"Déjà fini ? Reviens quand tu veux, minus !",
			"Mouahaha ! Mon arène est trop forte pour toi !",
		}))
	elseif current == PHASE.Defeated and previous == PHASE.Terminal then
		explodeAt = os.clock()
		Audio.Play("Whoosh", 0.8)
		for _, lagz in lagzes do
			spawnDebris(lagz.Rest.Position + Vector3.new(0, 5, 0))
		end
		lagzSays("Non… mon lag… il s'en vaaa…")
	end
end

local function readState()
	local p = player:GetAttribute("BossPhase")
	local s = player:GetAttribute("BossSince")
	local m = player:GetAttribute("BossPlugs")
	local newPhase = if type(p) == "number" then p else PHASE.Idle
	since = if type(s) == "number" then s else 0
	local newMask = if type(m) == "number" then m else 0
	-- Prise branchée : notification (le serveur l'a validée)
	if newPhase == PHASE.Plugs or (newPhase == PHASE.Terminal and phase == PHASE.Plugs) then
		for i = 1, BossLogic.PLUG_COUNT do
			if BossLogic.MaskHas(newMask, i) and not BossLogic.MaskHas(mask, i) then
				Audio.Play("PowerOn", 1 + i * 0.08)
				local count = 0
				for k = 1, BossLogic.PLUG_COUNT do
					if BossLogic.MaskHas(newMask, k) then
						count += 1
					end
				end
				if newPhase == PHASE.Plugs then
					Toasts.Show("Success", `Prise antivirus branchée : {count}/{BossLogic.PLUG_COUNT}`)
				end
			end
		end
	end
	mask = newMask
	local previous = phase
	phase = newPhase
	if previous ~= phase then
		onPhase(previous, phase)
	end
	applyAll()
	for _, plug in plugs do
		applyPlug(plug)
	end
end

------------------------------------------------------------------------------------
-- Boucle et démarrage
------------------------------------------------------------------------------------

local function step()
	local now = Workspace:GetServerTimeNow()
	local character = player.Character
	local root = character and character:FindFirstChild("HumanoidRootPart")
	local rootPart = if root and root:IsA("BasePart") then root else nil
	if rootPart then
		checkPlugs(rootPart)
	end
	updateBar(now)
	-- LAGZ et bouclier (seulement près de l'arène)
	local camera = Workspace.CurrentCamera
	local eye = if camera then camera.CFrame.Position else Vector3.zero
	local t = os.clock()
	for _, lagz in lagzes do
		if (lagz.Rest.Position - eye).Magnitude <= ANIMATE_RADIUS then
			animateLagz(lagz, t, rootPart)
		end
	end
	-- Bouclier brisé : il gonfle et s'efface en 0,6 s, puis reste caché
	if phase == PHASE.Terminal or phase == PHASE.Defeated then
		local popAge = t - shieldPop
		for part, size in shields do
			if popAge <= 0.6 then
				part.Size = size * (1 + popAge * 0.9)
				part.LocalTransparencyModifier = popAge / 0.6
			elseif part.LocalTransparencyModifier < 1 then
				part.Size = size
				part.LocalTransparencyModifier = 1
			end
		end
	end
	-- Pixels de l'explosion
	for i = #debris, 1, -1 do
		local bit = debris[i]
		local age = t - bit.Born
		if age > 1.6 then
			bit.Part:Destroy()
			table.remove(debris, i)
		else
			local v = bit.Velocity + Vector3.new(0, -40 * age, 0)
			bit.Part.CFrame = CFrame.new(bit.Part.Position + v * (1 / 60)) * CFrame.Angles(age * 5, age * 3, 0)
			bit.Part.Transparency = age / 1.6
		end
	end
end

local introShown = false

function BossController.Start(layer: Instance?)
	if layer then
		buildBar(layer)
	end
	track("BossLagz", function(instance: Instance)
		if instance:IsA("Model") and not lagzes[instance] then
			lagzes[instance] = { Model = instance, Rest = instance:GetPivot(), Eye = nil }
			for part in bossTraps do
				linkBeam(part)
			end
		end
	end, function(instance: Instance)
		lagzes[instance :: Model] = nil
	end)
	track("BossTrap", function(instance: Instance)
		if instance:IsA("BasePart") then
			bossTraps[instance] = bossTraps[instance] or instance.Color
			linkBeam(instance)
			applyTrap(instance)
		end
	end, function(instance: Instance)
		bossTraps[instance :: BasePart] = nil
		beams[instance :: BasePart] = nil
	end)
	track("BossBarrier", function(instance: Instance)
		if instance:IsA("BasePart") then
			barriers[instance] = true
			applyBarrier(instance)
		end
	end, function(instance: Instance)
		barriers[instance :: BasePart] = nil
	end)
	track("BossShield", function(instance: Instance)
		if instance:IsA("BasePart") then
			shields[instance] = shields[instance] or instance.Size
			applyShield(instance)
		end
	end, function(instance: Instance)
		shields[instance :: BasePart] = nil
	end)
	track("BossPlug", addPlug, function(instance: Instance)
		plugs[instance :: BasePart] = nil
	end)

	for _, name in { "BossPhase", "BossSince", "BossPlugs" } do
		player:GetAttributeChangedSignal(name):Connect(readState)
	end
	readState()
	-- Arrivée au checkpoint de l'arène : Anga prévient (une fois par session)
	local function onStage()
		local stage = player:GetAttribute("Stage")
		if not introShown and stage == Tower.TerminalStage(BossLogic.WORLD) - 1 and phase == PHASE.Idle then
			introShown = true
			angaSays("Voilà l'arène de LAGZ ! Quand tu entres, il attaque : prépare-toi à courir.", 2)
		end
	end
	player:GetAttributeChangedSignal("Stage"):Connect(onStage)
	onStage()
	RunService.RenderStepped:Connect(step)
end

return BossController
