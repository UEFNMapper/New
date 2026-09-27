--!nonstrict
-- Mondes côté client : lumière et musique propres à chaque arène, textes des
-- portails (ouvert / conditions), minuteurs des météores des arènes, bannière
-- d'arrivée, fondu au voyage, écran des mondes quand un portail est verrouillé.

local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local Workspace = game:GetService("Workspace")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Worlds = require(Shared.Config.Worlds)
local Theme = require(Shared.Config.Theme)
local Format = require(Shared.Logic.Format)

local Controllers = script.Parent.Parent.Controllers
local State = require(Controllers.State)
local Audio = require(Controllers.Audio)
local FxBus = require(Controllers.FxBus)
local UIRegistry = require(Controllers.UIRegistry)
local CameraFx = require(Controllers.CameraFx)
local Kit = require(script.Parent.Parent.UI.Kit)
local EventVisuals = require(script.Parent.EventVisuals)

local C = Theme.Colors
local player = Players.LocalPlayer

local WorldVisuals = {}

local CLOCK = { Candy = 13.5, Frost = 11, Volcano = 18.4, Cosmic = 0.5 }

local currentWorld = ""
local visited: { [string]: boolean } = {}
local fade: Frame

local function lightingFor(id: string)
	local w = Worlds.Get(id)
	local pal = w.Palette
	return {
		ClockTime = CLOCK[id] or 15.2,
		Ambient = pal.Ambient,
		FogColor = pal.Sky,
		FogEnd = 2200,
		Tint = pal.Tint,
	}
end

local function setWorld(where: string)
	if where == currentWorld then
		return
	end
	currentWorld = where
	State.Set("WorldAt", where)
	local world = Worlds.ById[where]
	if world and world.Id ~= Worlds.Default then
		EventVisuals.SetWorldLighting(lightingFor(world.Id))
		Audio.Music(if world.Palette.Music == "Event" then "music_event" else "music_main")
	else
		EventVisuals.SetWorldLighting(nil)
		if not Workspace:GetAttribute("EventId") then
			Audio.Music("music_main")
		end
	end
end

-- Fondu rapide (voyage).
local function flash()
	fade.BackgroundTransparency = 0
	Kit.Tween(fade, 0.6, { BackgroundTransparency = 1 }, Enum.EasingStyle.Quad)
end

local function portalTexts()
	local map = Workspace:FindFirstChild("Map")
	local folder = map and map:FindFirstChild("Worlds")
	if not folder then
		return
	end
	local unlocked = State.Get("Worlds") or {}
	local level = State.Get("Level") or 1
	local rebirths = State.Get("Rebirths") or 0
	for _, w in Worlds.List do
		local portal = folder:FindFirstChild("Portal_" .. w.Id)
		local sub = portal and portal:FindFirstChild("Sub")
		local gui = sub and sub:FindFirstChild("SignGui")
		local label = gui and gui:FindFirstChild("Text") :: TextLabel?
		if label then
			if unlocked[w.Id] then
				label.Text = "OPEN — WALK IN!"
				label.TextColor3 = C.Radioactive
			elseif Worlds.MeetsGate(w, level, rebirths) then
				label.Text = "UNLOCK: " .. Format.Cash(w.Toll)
				label.TextColor3 = C.Gold
			else
				local need = if level < w.Level then ("LEVEL %d"):format(w.Level) else ("EVOLUTION %d"):format(w.Rebirths)
				label.Text = "🔒 " .. need
				label.TextColor3 = C.Paper
			end
		end
	end
end

local function arenaTimers()
	local map = Workspace:FindFirstChild("Map")
	local folder = map and map:FindFirstChild("Worlds")
	if not folder then
		return
	end
	for _, w in Worlds.List do
		local arena = folder:FindFirstChild("World_" .. w.Id)
		local sign = arena and arena:FindFirstChild("MeteorTimer")
		local gui = sign and sign:FindFirstChild("SignGui")
		local label = gui and gui:FindFirstChild("Text") :: TextLabel?
		if label then
			local wait = Workspace:GetAttribute("NextMeteorIn_" .. w.Id) or -1
			label.Text = if wait >= 0 then ("NEXT METEOR IN %ds"):format(math.ceil(wait)) else "METEORS PAUSED"
		end
	end
end

function WorldVisuals.Init()
	local layer = Kit.Layer("WorldFade", 30)
	fade = Kit.new("Frame", {
		Name = "Fade",
		Size = UDim2.fromScale(1, 1),
		BackgroundColor3 = Color3.new(1, 1, 1),
		BackgroundTransparency = 1,
		BorderSizePixel = 0,
		Parent = layer,
	})

	player:GetAttributeChangedSignal("World"):Connect(function()
		setWorld(player:GetAttribute("World") or "Island")
	end)
	setWorld(player:GetAttribute("World") or "Island")

	for _, key in { "Worlds", "Level", "Rebirths" } do
		State.Observe(key, portalTexts)
	end
	task.spawn(function()
		while true do
			arenaTimers()
			task.wait(0.5)
		end
	end)

	FxBus.On("Travel", function(args)
		flash()
		Audio.Play("whoosh")
		CameraFx.FovPunch(10, 0.6)
		local world = Worlds.ById[args.World or ""]
		-- grande bannière seulement à la première visite de la session
		if world and world.Id ~= Worlds.Default and not visited[world.Id] then
			visited[world.Id] = true
			task.delay(0.4, function()
				UIRegistry.Announce(string.upper(world.Name), world.Palette.Glow, world.Tagline)
			end)
		end
	end)
	FxBus.On("WorldUnlocked", function(args)
		local world = Worlds.ById[args.World or ""]
		if not world then
			return
		end
		UIRegistry.Announce(string.upper(world.Name) .. " OPENED!", world.Palette.Glow, "Walk into its portal in the crater, or travel from the WORLD MAP!", "rebirth", true)
		CameraFx.Shake(0.3, 0.5)
		portalTexts()
	end)
	FxBus.On("PortalLocked", function(args)
		local open = UIRegistry.OpenWorld
		if open then
			open(args.World)
		end
		UIRegistry.Toast("This world is locked — check what you need!", "Info")
	end)

	-- le monde d'arrivée sert aussi quand l'attribut serveur tarde (téléportation locale)
	RunService.Heartbeat:Connect(function()
		local root = player.Character and player.Character:FindFirstChild("HumanoidRootPart") :: BasePart?
		if root then
			local at = Worlds.At(root.Position)
			if at and at ~= currentWorld then
				setWorld(at)
			end
		end
	end)
end

return WorldVisuals
