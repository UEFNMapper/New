--!nocheck
-- Extension « client » du runtime simulé : joueur local, réseau client↔serveur
-- dans le même processus, services d'interface (TweenService, UserInput…),
-- caméra, boucle d'images. Permet d'exécuter le VRAI code client.

local roblox = require("@lune/roblox")

local ClientRuntime = {}

function ClientRuntime.Install(Runtime)
	local methods = Runtime._methods
	local events = Runtime._events
	local defaults = Runtime._defaults
	local new = Runtime.NewInstance
	local game = Runtime.game
	local task = Runtime.task
	local Signal = Runtime.Signal
	local S = Runtime.Services

	-- Événements d'interface supplémentaires
	for _, name in {
		"MouseEnter", "MouseLeave", "MouseButton1Down", "MouseButton1Up", "MouseButton1Click", "MouseButton2Click",
		"InputBegan", "InputEnded", "InputChanged", "TouchTap", "FocusLost", "Focused",
		"PromptShown", "PromptHidden", "PromptButtonHoldBegan", "PromptButtonHoldEnded", "PromptTriggered",
		"Ended", "Completed", "Loaded", "Played", "DidLoop", "OnIncomingMessage", "LocalToolEquipped",
		"Equipped", "Unequipped", "Deactivated", "SelectionGained",
	} do
		events[name] = true
	end

	-- Valeurs lues par défaut (propriétés jamais écrites)
	local V2 = roblox.Vector2.new
	for k, v in {
		Size = roblox.UDim2.new(),
		Position = roblox.UDim2.new(),
		AnchorPoint = V2(0, 0),
		Rotation = 0,
		Visible = true,
		Enabled = true,
		BackgroundTransparency = 0,
		TextTransparency = 0,
		ImageTransparency = 0,
		Transparency = 0,
		ZIndex = 1,
		LayoutOrder = 0,
		Text = "",
		Scale = 1,
		Volume = 0.5,
		PlaybackSpeed = 1,
		Brightness = 1,
		Range = 8,
		Health = 100,
		WalkSpeed = 16,
		FieldOfView = 70,
		AbsolutePosition = V2(100, 100),
		AbsoluteSize = V2(120, 60),
		TextBounds = V2(80, 20),
		ViewportSize = V2(1280, 720),
		HoldDuration = 0,
		MaxActivationDistance = 10,
		Offset = V2(0, 0),
		Thickness = 1,
		Color = roblox.Color3.new(1, 1, 1),
		BackgroundColor3 = roblox.Color3.new(1, 1, 1),
		TextColor3 = roblox.Color3.new(0, 0, 0),
		ImageColor3 = roblox.Color3.new(1, 1, 1),
		ClockTime = 14,
		TouchEnabled = false,
		KeyboardEnabled = true,
		GamepadEnabled = false,
		MouseEnabled = true,
		IsPlaying = false,
		Looped = false,
		KeyboardKeyCode = roblox.Enum.KeyCode.E,
		ActionText = "",
		ObjectText = "",
		WorldPosition = function(self, d)
			local parent = d.Parent
			return if parent and parent.CFrame then parent.CFrame.Position else roblox.Vector3.new()
		end,
	} do
		defaults[k] = v
	end

	-- Méthodes génériques d'interface
	for _, name in {
		"Pause", "Resume", "Cancel", "CaptureFocus", "ReleaseFocus", "SetCore", "PreloadAsync",
		"RemoveDefaultLoadingScreen", "UnbindFromRenderStep", "SetCoreGuiEnabled", "ScaleTo", "AddItem",
		"TweenPosition", "TweenSize", "ApplyImpulse", "SetNetworkOwner", "Stop",
	} do
		local existing = methods[name]
		methods[name] = function(self, ...)
			if name == "AddItem" then
				local item, t = ...
				task.delay(t or 0, function()
					methods.Destroy(item)
				end)
			elseif existing then
				return existing(self, ...)
			end
		end
	end
	methods.GetStringForKeyCode = function(_, keyCode)
		return tostring(keyCode):match("[^%.]+$") or "?"
	end
	methods.IsKeyDown = function()
		return false
	end
	methods.GetMouseLocation = function()
		return V2(640, 360)
	end
	methods.GetBoundingBox = function(self)
		local lo, hi
		for _, p in methods.GetDescendants(self) do
			if Runtime._isA(Runtime.Data(p).ClassName, "BasePart") then
				local pos = p.CFrame.Position
				local half = p.Size / 2
				local a, b = pos - half, pos + half
				lo = if lo then roblox.Vector3.new(math.min(lo.X, a.X), math.min(lo.Y, a.Y), math.min(lo.Z, a.Z)) else a
				hi = if hi then roblox.Vector3.new(math.max(hi.X, b.X), math.max(hi.Y, b.Y), math.max(hi.Z, b.Z)) else b
			end
		end
		lo = lo or roblox.Vector3.new()
		hi = hi or roblox.Vector3.new(1, 1, 1)
		return roblox.CFrame.new((lo + hi) / 2), hi - lo
	end
	methods.BulkMoveTo = function(_, parts, cframes)
		for i, p in parts do
			p.CFrame = cframes[i]
		end
	end
	methods.Play = function(self)
		local d = Runtime.Data(self)
		if d.ClassName == "Sound" then
			d.Props.IsPlaying = true
			if not d.Props.Looped then
				task.delay(0.5, function()
					local s = d.Signals.Ended
					if s then
						s:Fire()
					end
				end)
			end
		elseif d.Props._tween then
			d.Props._tween()
		end
	end
	methods.InputHoldBegin = function(self)
		local d = Runtime.Data(self)
		if (d.Props.HoldDuration or 0) <= 0 then
			d.Signals.Triggered = d.Signals.Triggered or Signal.new()
			d.Signals.Triggered:Fire(Runtime.LocalPlayer)
		end
	end
	methods.InputHoldEnd = function() end
	methods.DisplaySystemMessage = function() end
	methods.Raycast = function()
		return nil
	end

	-- Services d'interface
	local function service(name)
		return methods.GetService(game, name)
	end

	-- TweenService : applique l'état final immédiatement (suffisant pour tester la logique)
	local TweenService = service("TweenService")
	Runtime.Raw(TweenService, "Create", function(_, inst, _info, props)
		local tween = new("Tween")
		Runtime.Data(tween).Props._tween = function()
			for k, v in props do
				inst[k] = v
			end
			task.defer(function()
				local s = Runtime.Data(tween).Signals.Completed
				if s then
					s:Fire(roblox.Enum.PlaybackState.Completed)
				end
			end)
		end
		return tween
	end)
	Runtime.Raw(TweenService, "GetValue", function(_, alpha)
		return alpha
	end)

	local RunService = S.Workspace and service("RunService")
	local renderStepped = Signal.new()
	local stepped = Signal.new()
	Runtime.Data(RunService).Props.RenderStepped = renderStepped
	Runtime.Data(RunService).Props.Stepped = stepped
	Runtime.Data(RunService).Props.IsClient = function()
		return true
	end
	Runtime.Raw(RunService, "BindToRenderStep", function(_, _name, _priority, fn)
		renderStepped:Connect(fn)
	end)
	Runtime.RenderStepped = renderStepped

	-- Boucle d'images (20 i/s virtuelles)
	task.spawn(function()
		while true do
			task.wait(0.05)
			renderStepped:Fire(0.05)
			stepped:Fire(Runtime.Now(), 0.05)
			Runtime.Heartbeat:Fire(0.05)
		end
	end)

	service("UserInputService")
	service("ProximityPromptService")
	service("ContentProvider")
	service("StarterGui")
	service("GuiService")
	service("Debris")
	service("SoundService")
	service("HapticService")

	-- Caméra
	local camera = new("Camera")
	camera.Name = "Camera"
	camera.CFrame = roblox.CFrame.new(0, 40, 60)
	Runtime.Raw(camera, "ViewportSize", V2(1280, 720))
	camera.FieldOfView = 70
	methods._setParent(camera, S.Workspace)
	S.Workspace.CurrentCamera = camera

	Runtime.Globals.TweenInfo = {
		new = function(...)
			return { Args = table.pack(...) }
		end,
	}
	Runtime.Globals.Rect = roblox.Rect
	Runtime.Globals.Vector2 = roblox.Vector2
	Runtime.Globals.Region3 = roblox.Region3

	-- Réseau : même processus, le joueur local est le « client »
	methods.FireServer = function(self, ...)
		local d = Runtime.Data(self)
		d.Signals.OnServerEvent = d.Signals.OnServerEvent or Signal.new()
		d.Signals.OnServerEvent:Fire(Runtime.LocalPlayer, ...)
	end
	methods.InvokeServer = function(self, ...)
		local fn = self.OnServerInvoke
		return fn(Runtime.LocalPlayer, ...)
	end
	-- Comme Roblox : les messages arrivés avant qu'un écouteur existe sont gardés
	local function clientSignal(self)
		local d = Runtime.Data(self)
		local sig = d.Signals.OnClientEvent
		if not sig or not sig.pending then
			sig = sig or Signal.new()
			sig.pending = {}
			local connect = Signal.Connect
			sig.Connect = function(this, fn)
				local c = connect(this, fn)
				if #this.pending > 0 then
					local list = this.pending
					this.pending = {}
					for _, args in list do
						task.defer(function()
							fn(table.unpack(args, 1, args.n))
						end)
					end
				end
				return c
			end
			d.Signals.OnClientEvent = sig
		end
		return sig
	end
	local function deliver(self, ...)
		local sig = clientSignal(self)
		if #sig.handlers == 0 then
			table.insert(sig.pending, table.pack(...))
		else
			sig:Fire(...)
		end
	end
	local function isLocal(player)
		return player == Runtime.LocalPlayer or (Runtime.LocalPlayer == nil and type(player) == "table" and player.Name == Runtime.LocalPlayerName)
	end
	local fireClient = methods.FireClient
	methods.FireClient = function(self, player, ...)
		fireClient(self, player, ...)
		if isLocal(player) then
			deliver(self, ...)
		end
	end
	local fireAll = methods.FireAllClients
	methods.FireAllClients = function(self, ...)
		fireAll(self, ...)
		if Runtime.LocalPlayer or Runtime.LocalPlayerName then
			deliver(self, ...)
		end
	end
end

-- Crée le joueur local (côté client) et lance les scripts client.
function ClientRuntime.StartClient(Runtime, name)
	Runtime.LocalPlayerName = name
	local player = Runtime.AddPlayer(name)
	Runtime.LocalPlayer = player
	Runtime.Raw(Runtime.Services.Players, "LocalPlayer", player)
	local gui = Runtime.NewInstance("PlayerGui")
	gui.Name = "PlayerGui"
	Runtime._methods._setParent(gui, player)
	local scripts = Runtime.NewInstance("PlayerScripts")
	scripts.Name = "PlayerScripts"
	Runtime._methods._setParent(scripts, player)
	local first = Runtime.Mount("src/first", Runtime.Services.ReplicatedFirst or Runtime.game:GetService("ReplicatedFirst"), "Loading")
	local client = Runtime.Mount("src/client", scripts, "Client")
	Runtime.RunScript(first:FindFirstChild("Loading"))
	Runtime.RunScript(client:FindFirstChild("Main"))
	return player, client
end

function S_players(Runtime)
	return Runtime.Services.Players
end

return ClientRuntime
