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

local Levels = req(Shared.Config.Levels)
local TutorialCfg = req(Shared.Config.Tutorial)
local Notify = req(Services:FindFirstChild("Notify"))
local UIRegistry = req(client:FindFirstChild("Controllers"):FindFirstChild("UIRegistry"))
local data = DataService.Get(hero)
local C3 = roblox.Color3.fromRGB

-- 1. Nouveau joueur : mission 1
Runtime.Advance(12)
shot("tut1_start")
for _ = 1, 40 do
	Runtime.Advance(0.5)
	if (data.Tutorial or 1) >= 2 then break end
end
Runtime.Advance(1.2)
shot("tut1_hatch")
Runtime.Advance(8)
shot("tut2_collect")
-- 2. mission 3 (météore)
data.Tutorial = 3
data.Cash = 450
DataService.Replicate(hero, "Tutorial", "Cash")
Runtime.Advance(4)
shot("tut3_meteor")
-- 3. Joueur normal solo, niveau 8
data.Tutorial = TutorialCfg.Done
data.Xp = Levels.TotalFor(8) + 120
data.Level = 8
data.Cash = 182_000
data.Gems = 85
DataService.Replicate(hero, "Tutorial", "Xp", "Level", "Cash", "Gems")
PlotService.RefreshNests(hero)
for _, r in { { "Toastzilla", nil, 3 }, { "SushiRex", nil, 2 }, { "Sharkapillar", nil, 2 }, { "KawaiiKraken", nil, 1 } } do
	local sp = Kaijus.Get(r[1])
	KaijuService.AddHatched(hero, r[1], r[2], Growth.Threshold(r[3], sp.Rarity) + 5)
end
PlotService.RefreshNests(hero)
Runtime.Advance(12)
shot("solo_idle")
-- 4. Rafale typique (≈ 5 s de jeu normal)
Notify.Fx(hero, "Collect", { Amount = 4200 })
Notify.Fx(hero, "Xp", { Amount = 10, Reason = "Grow" })
Notify.Toast(hero, "Sushi Rex grew into a TEEN!", "Good")
Notify.Fx(hero, "QuestReady", { Id = "Grow3", Text = "Grow kaijus 3 stages" })
Notify.Toast(hero, "Sharkapillar grew into a TEEN!", "Good")
Notify.Fx(hero, "Discovered", { Species = "SushiRex", NewSpecies = true })
Notify.Feed("☄️ LEGENDARY METEOR INCOMING!", "Meteor", C3(255, 176, 32))
Runtime.Advance(0.6)
shot("solo_burst")
Runtime.Advance(6)
-- 5. Montée de niveau + mission + toasts
Notify.Fx(hero, "LevelUp", { Level = 9, Gems = 12, Unlocks = {} })
Notify.Toast(hero, "🐾 Your buddy sniffed out a TREASURE! Follow the arrows!", "Good")
Notify.Fx(hero, "PersonalMeteor", { Rarity = "Rare", World = "Crater", Golden = false })
Runtime.Advance(0.8)
shot("solo_levelup")
Runtime.Advance(6)
-- 6. Défense active en solo
Boot.Call(hero, "SiegeStartNow")
Runtime.Advance(0.8)
shot("solo_siren")
Runtime.Advance(7)
Notify.Fx(hero, "SiegeLeak", { Plot = hero:GetAttribute("Plot"), Id = 1, Amount = 900 })
Notify.Fx(hero, "SiegeBagSaved", { Plot = hero:GetAttribute("Plot"), Amount = 900, By = hero.UserId })
Notify.Fx(hero, "Xp", { Amount = 1, Reason = "SiegeKill" })
Runtime.Advance(0.5)
shot("solo_siege")
-- 7. Multijoueur : fil d'annonces des autres
local rival = Runtime.AddPlayer("Rival")
local rival2 = Runtime.AddPlayer("xXDragonSlayerXx")
Runtime.Advance(4)
Notify.FeedExcept(hero, "Rival reached LEVEL 12!", "Info")
Notify.FeedExcept(hero, "🌍 xXDragonSlayerXx opened CANDY COAST!", "Info", C3(255, 120, 200))
Notify.Feed("🦹 Rival stole xXDragonSlayerXx's Teen Sushi Rex!", "Heist", C3(80, 160, 255))
Notify.Feed("xXDragonSlayerXx hatched a EPIC Drakonda!", "Rare", C3(190, 90, 255))
Notify.Feed("🆘 Rival needs a hand lifting a TITAN! Help them!", "Help", C3(255, 120, 40))
Notify.Toast(hero, "Quest complete: Buy 3 meteor eggs", "Good")
Runtime.Advance(0.8)
shot("multi_feed")

shots.__viewport = { tonumber(vw) or 1280, tonumber(vh) or 720 }
fs.writeFile(process.env.OUT or "/tmp/audit_ui.json", serde.encode("json", shots))
print("erreurs :", #Runtime.Errors)
for i, e in Runtime.Errors do
	if i <= 5 then print(e:sub(1, 400)) end
end
