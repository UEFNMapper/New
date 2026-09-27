--!nocheck
-- Exporte l'arbre d'interface du client simulé (HUD + fenêtres) en JSON,
-- pour en faire des captures avec render_ui.py.
-- Lancer : lune run tools/render/export_ui.luau

local fs = require("@lune/fs")
local serde = require("@lune/serde")
local roblox = require("@lune/roblox")
local Boot = require("../../tests/sim/boot")
local Runtime = Boot.Start()
local ClientRuntime = require("../../tests/sim/ClientRuntime")
ClientRuntime.Install(Runtime)
Runtime.Validate = false

local S = Runtime.Services
local function req(inst)
	return Runtime.Globals.require(inst)
end
local Services = S.ServerScriptService:FindFirstChild("Server"):FindFirstChild("Services")
local KaijuService = req(Services:FindFirstChild("KaijuService"))
local DataService = req(Services:FindFirstChild("DataService"))
local PlotService = req(Services:FindFirstChild("PlotService"))
local EventService = req(Services:FindFirstChild("EventService"))
local Shared = S.ReplicatedStorage:FindFirstChild("Shared")
local Growth = req(Shared.Config.Growth)
local Kaijus = req(Shared.Config.Kaijus)

S.ReplicatedStorage:SetAttribute("IconPreview", true)
-- VIEWPORT=1121x393 : aperçus au format d'un téléphone en paysage
local process = require("@lune/process")
local vw, vh = string.match(process.env.VIEWPORT or "", "(%d+)x(%d+)")
if vw then
	Runtime.Viewport = roblox.Vector2.new(tonumber(vw), tonumber(vh))
	Runtime.Raw(S.Workspace.CurrentCamera, "ViewportSize", Runtime.Viewport)
end
local hero, client = ClientRuntime.StartClient(Runtime, "Hero")
local rival = Runtime.AddPlayer("Rival")
Runtime.Advance(20)
local UIRegistry = req(client:FindFirstChild("Controllers"):FindFirstChild("UIRegistry"))
local data = DataService.Get(hero)
data.Cash = 48_350_000
data.Gems = 1240
data.Nests = 16
data.Spins = 2
local Levels = req(Shared.Config.Levels)
data.Xp = Levels.TotalFor(14) + 420
data.Level = 14
data.Worlds = { Crater = true, Candy = true }
data.Tutorial = 7
data.Buddy.Xp = 64
PlotService.RefreshNests(hero)
for _, r in { { "Rexplosion", "Gold", 5 }, { "KawaiiKraken", nil, 4 }, { "SushiRex", nil, 3 }, { "Toastzilla", nil, 3 }, { "Sharkapillar", nil, 3 }, { "Drakonda", "Radioactive", 2 }, { "ThunderGoose", nil, 2 } } do
	local sp = Kaijus.Get(r[1])
	KaijuService.AddHatched(hero, r[1], r[2], Growth.Threshold(r[3], sp.Rarity) + 30)
end
DataService.Replicate(hero, "Cash", "Gems", "Nests", "Spins", "Xp", "Level", "Worlds", "Tutorial", "Buddy")
Runtime.Advance(3)

----------------------------------------------------------------------------
-- Sérialisation
----------------------------------------------------------------------------

local function color(c)
	return if c then { math.floor(c.R * 255 + 0.5), math.floor(c.G * 255 + 0.5), math.floor(c.B * 255 + 0.5) } else nil
end
local function udim2(u)
	return if typeof(u) == "UDim2" then { u.X.Scale, u.X.Offset, u.Y.Scale, u.Y.Offset } else nil
end
local function v2(v)
	return if v then { v.X, v.Y } else nil
end
local function enumName(e)
	return if e then tostring(e):match("[^%.]+$") else nil
end

local SKIP = { BillboardGui = true, SurfaceGui = true, WorldModel = true, Camera = true, Model = true, Part = true, WedgePart = true }

local function part3d(p)
	local shape = "Block"
	if p.ClassName == "WedgePart" then
		shape = "Wedge"
	elseif p:FindFirstChildOfClass("SpecialMesh") then
		shape = "Ellipsoid"
	elseif p.Shape == roblox.Enum.PartType.Cylinder then
		shape = "Cylinder"
	elseif p.Shape == roblox.Enum.PartType.Ball then
		shape = "Ball"
	end
	local c = p.Color or roblox.Color3.new(0.7, 0.7, 0.7)
	return { shape = shape, size = { p.Size.X, p.Size.Y, p.Size.Z }, cf = { p.CFrame:GetComponents() }, color = { c.R, c.G, c.B }, neon = p.Material == roblox.Enum.Material.Neon, transparency = p.Transparency or 0 }
end

local function dump(inst)
	local cls = inst.ClassName
	if SKIP[cls] then
		return nil
	end
	local node = { class = cls, name = inst.Name, children = {} }
	local d = Runtime.Data(inst).Props
	node.size = udim2(d.Size)
	node.position = udim2(d.Position)
	node.anchor = v2(d.AnchorPoint)
	node.rotation = d.Rotation
	node.visible = d.Visible
	node.enabled = d.Enabled
	node.bg = color(d.BackgroundColor3)
	node.bgT = d.BackgroundTransparency
	node.z = d.ZIndex
	node.order = d.LayoutOrder
	node.clip = d.ClipsDescendants
	node.displayOrder = d.DisplayOrder
	node.autoSize = enumName(d.AutomaticSize)
	if d.Text ~= nil then
		node.text = d.Text
		node.textColor = color(d.TextColor3)
		node.textT = d.TextTransparency
		node.textScaled = d.TextScaled
		node.wrapped = d.TextWrapped
		node.textSize = d.TextSize
		node.xAlign = enumName(d.TextXAlignment)
		node.yAlign = enumName(d.TextYAlignment)
		node.font = if d.FontFace then tostring(d.FontFace.Family) else nil
	end
	node.imageColor = color(d.ImageColor3)
	node.image = d.Image
	node.imageT = d.ImageTransparency
	-- modificateurs
	if cls == "UICorner" then
		node.radius = { d.CornerRadius and d.CornerRadius.Scale or 0, d.CornerRadius and d.CornerRadius.Offset or 8 }
	elseif cls == "UIStroke" then
		node.thickness = d.Thickness or 1
		node.color = color(d.Color or roblox.Color3.new())
		node.mode = enumName(d.ApplyStrokeMode) or "Contextual"
		node.transparency = d.Transparency or 0
	elseif cls == "UIGradient" then
		local cs = d.Color
		if cs then
			node.colors = {}
			for _, k in cs.Keypoints do
				table.insert(node.colors, { k.Time, color(k.Value) })
			end
		end
		local ts = d.Transparency
		if ts then
			node.transp = {}
			for _, k in ts.Keypoints do
				table.insert(node.transp, { k.Time, k.Value })
			end
		end
		node.gradRotation = d.Rotation or 0
		node.offset = v2(d.Offset)
	elseif cls == "UIScale" then
		node.scale = d.Scale or 1
	elseif cls == "UIPadding" then
		node.pad = {
			d.PaddingLeft and d.PaddingLeft.Offset or 0,
			d.PaddingRight and d.PaddingRight.Offset or 0,
			d.PaddingTop and d.PaddingTop.Offset or 0,
			d.PaddingBottom and d.PaddingBottom.Offset or 0,
		}
	elseif cls == "UIListLayout" then
		node.dir = enumName(d.FillDirection) or "Vertical"
		node.padding = d.Padding and d.Padding.Offset or 0
		node.hAlign = enumName(d.HorizontalAlignment) or "Left"
		node.vAlign = enumName(d.VerticalAlignment) or "Top"
	elseif cls == "UIGridLayout" then
		node.cell = udim2(d.CellSize)
		node.cellPad = udim2(d.CellPadding)
		node.hAlign = enumName(d.HorizontalAlignment) or "Left"
	elseif cls == "UITextSizeConstraint" then
		node.maxText = d.MaxTextSize or 100
	elseif cls == "ViewportFrame" then
		local cam = d.CurrentCamera
		if cam then
			node.camera = { cf = { cam.CFrame:GetComponents() }, fov = cam.FieldOfView or 70 }
		end
		node.parts = {}
		for _, p in inst:GetDescendants() do
			if p:IsA("BasePart") and p.Name ~= "Root" and (p.Transparency or 0) < 0.95 then
				table.insert(node.parts, part3d(p))
			end
		end
		node.silhouette = d.ImageColor3 and d.ImageColor3.R < 0.2
	end
	for _, child in inst:GetChildren() do
		local c = dump(child)
		if c then
			table.insert(node.children, c)
		end
	end
	return node
end

local shots = {}
local function shot(name)
	local gui = hero:FindFirstChild("PlayerGui")
	local tree = dump(gui)
	shots[name] = tree
	print("capture", name)
end

----------------------------------------------------------------------------
-- Scénario de captures
----------------------------------------------------------------------------

shot("hud")
for _, name in { "Shop", "Index", "Rebirth", "Fusion", "Daily", "Playtime", "Quests", "Spin", "Settings", "HowToPlay", "Worlds", "Rewards" } do
	local screen = UIRegistry.Screens[name]
	screen.Open()
	Runtime.Advance(2)
	shot(name)
	screen.Close()
	Runtime.Advance(1)
end
UIRegistry.Screens.Shop.Open("Upgrades")
Runtime.Advance(2)
shot("ShopUpgrades")
UIRegistry.Screens.Shop.Close()
UIRegistry.Screens.Shop.Open("Boosts")
Runtime.Advance(2)
shot("ShopBoosts")
UIRegistry.Screens.Shop.Close()
Runtime.Advance(1)
local rec
for _, r in data.Kaijus do
	if r.Species == "Rexplosion" then
		rec = r
	end
end
UIRegistry.OpenKaiju(rec.Uid)
Runtime.Advance(2)
shot("KaijuPanel")
UIRegistry.Screens.KaijuPanel.Close()
Runtime.Advance(1)
-- Compagnon : trésor flairé (pastille « ! »)
req(Services:FindFirstChild("BuddyService")).ForceTreasure(hero)
Runtime.Advance(1)
shot("Buddy")
-- Cinématique d'éclosion (Légendaire doré)
local egg = KaijuService.AddEgg(hero, "Legendary", 1)
Runtime.Advance(1.6)
local t0 = Runtime.Now()
repeat
	Runtime.Advance(0.25)
until Runtime.Now() - t0 > 4.2
shot("Hatch")
Runtime.Advance(8)
-- Événement + alarme
EventService.Stop()
EventService.Force("BloodMoon")
Runtime.Advance(1.5)
shot("Event")
Runtime.Advance(5)
local Notify = req(Services:FindFirstChild("Notify"))
Notify.Fx(hero, "Alarm", { Uid = rec.Uid, Thief = "Rival", Species = "Rexplosion" })
Notify.Toast(hero, "Your Rexplosion grew into a TITAN!", "Good")
Notify.Toast(hero, "Quest complete: Buy 3 meteor eggs", "Good")
Notify.Feed("🦹 Rival stole Hero's Titan Kawaii Kraken!", "Heist", roblox.Color3.fromRGB(255, 176, 32))
Notify.Feed("☄️ LEGENDARY METEOR INCOMING!", "Meteor", roblox.Color3.fromRGB(255, 176, 32))
Runtime.Advance(1)
shot("Alarm")
Notify.Fx(hero, "AlarmStop", { Uid = rec.Uid })
Runtime.Advance(6)

-- Défense de l'île : compte à rebours, sirène, Alpha, fin de vague, œuf
local Tutorial = req(Shared.Config.Tutorial)
local siegeFolder = S.Workspace:FindFirstChild("Siege"):FindFirstChild("Plot" .. hero:GetAttribute("Plot"))
data.Tutorial = Tutorial.Done
data.Siege.Wave = 5
DataService.Replicate(hero, "Tutorial", "Siege")
PlotService.SpawnAt(hero)
Runtime.Advance(3)
shot("SiegeCountdown")
Boot.Call(hero, "SiegeStartNow")
Runtime.Advance(0.6)
shot("SiegeSiren")
local alphaShot = false
for _ = 1, 400 do
	Runtime.Advance(0.5)
	if not alphaShot and hero.PlayerGui.SiegeHud.SiegeAlpha.Visible then
		Runtime.Advance(1)
		shot("SiegeAlpha")
		alphaShot = true
	end
	if not shots.SiegeEgg and hero.PlayerGui.SiegeHud:FindFirstChild("SiegeEgg") then
		Runtime.Advance(0.5)
		shot("SiegeEgg")
	end
	if siegeFolder:GetAttribute("State") ~= "Active" then
		break
	end
end
for _ = 1, 20 do
	Runtime.Advance(0.5)
	if hero.PlayerGui.SiegeHud:FindFirstChild("SiegeEnd") then
		Runtime.Advance(1.5)
		shot("SiegeEnd")
		break
	end
end

-- RAMPAGE : écran de choix, HUD de partie (combo en cours), résultats
local RampageController = req(client:FindFirstChild("World"):FindFirstChild("RampageController"))
Runtime.Advance(8)
UIRegistry.Screens.Rampage.Open()
Runtime.Advance(2)
shot("Rampage")
UIRegistry.Screens.Rampage.Close()
Runtime.Advance(1)
Boot.Call(hero, "RampageStart", { Uid = rec.Uid, District = 1 })
Runtime.Advance(2.5)
-- avance jusqu'au pâté de maisons le plus proche (à la vitesse de marche), piétine, rugit
local buildings = S.Workspace:FindFirstChild("RampageCities"):FindFirstChild(tostring(hero.UserId)):FindFirstChild("Buildings")
local root = hero.Character.HumanoidRootPart
for _ = 1, 3 do
	local target, best = nil, math.huge
	for _, b in buildings:GetChildren() do
		local d = (b.PrimaryPart.Position - root.Position) * roblox.Vector3.new(1, 0, 1)
		if d.Magnitude < best then
			target, best = b, d.Magnitude
		end
	end
	local goal = target.PrimaryPart.Position
	for _ = 1, 40 do
		local d = (goal - root.Position) * roblox.Vector3.new(1, 0, 1)
		if d.Magnitude < 9 then
			break
		end
		local p = root.Position + d.Unit * 2.2
		root.CFrame = Runtime.CFrame.lookAt(p, p + d.Unit)
		Runtime.Advance(0.1)
	end
	RampageController.Stomp()
	Runtime.Advance(0.45)
end
RampageController.Roar()
Runtime.Advance(0.3)
shot("RampageHud")
Boot.Call(hero, "RampageLeave")
Runtime.Advance(3)
shot("RampageResults")

shots.__viewport = { tonumber(vw) or 1280, tonumber(vh) or 720 }
fs.writeFile("tools/render/ui.json", serde.encode("json", shots))
print("erreurs :", #Runtime.Errors)
for i, e in Runtime.Errors do
	if i <= 5 then
		print(e:sub(1, 400))
	end
end
