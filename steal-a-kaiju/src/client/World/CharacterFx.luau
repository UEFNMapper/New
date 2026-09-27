--!nonstrict
-- Personnages : le Bonker (coup + animation), recul comique quand on se fait
-- bonker (étoiles, « BONK! »), effets des autres joueurs, rayon d'évolution.

local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Theme = require(Shared.Config.Theme)

local Controllers = script.Parent.Parent.Controllers
local Remote = require(Controllers.Remote)
local Audio = require(Controllers.Audio)
local FxBus = require(Controllers.FxBus)
local CameraFx = require(Controllers.CameraFx)
local UIRegistry = require(Controllers.UIRegistry)
local Effects = require(script.Parent.Effects)

local C = Theme.Colors
local player = Players.LocalPlayer

local CharacterFx = {}

local BONK_WORDS = { "BONK!", "WHAM!", "BOP!", "POW!", "BONK!!" }

local function rootOf(p: Player?): BasePart?
	local character = p and p.Character
	return character and character:FindFirstChild("HumanoidRootPart") :: BasePart?
end

local function hookTool(tool: Tool)
	if tool.Name ~= "Bonker" or tool:GetAttribute("Hooked") then
		return
	end
	tool:SetAttribute("Hooked", true)
	local last = 0
	tool.Activated:Connect(function()
		if os.clock() - last < 0.35 then
			return
		end
		last = os.clock()
		-- animation « toolslash » du script Animate par défaut
		local anim = Instance.new("StringValue")
		anim.Name = "toolanim"
		anim.Value = "Slash"
		anim.Parent = tool
		task.delay(0.3, function()
			anim:Destroy()
		end)
		Audio.Play("knockback_whoosh", { Volume = 0.6 })
		Remote.Input("Bonk")
		CameraFx.FovPunch(2, 0.25)
	end)
end

local function watchCharacter(character: Model)
	for _, child in character:GetChildren() do
		if child:IsA("Tool") then
			hookTool(child)
		end
	end
	character.ChildAdded:Connect(function(child)
		if child:IsA("Tool") then
			hookTool(child)
		end
	end)
end

-- Étoiles qui tournent autour de la tête.
local function dizzy(character: Model, duration: number)
	local head = character:FindFirstChild("Head") :: BasePart?
	if not head then
		return
	end
	local stars = {}
	for i = 1, 3 do
		local gui = Instance.new("BillboardGui")
		gui.Size = UDim2.fromOffset(30, 30)
		gui.AlwaysOnTop = true
		gui.LightInfluence = 0
		gui.Adornee = head
		local t = Instance.new("TextLabel")
		t.BackgroundTransparency = 1
		t.Size = UDim2.fromScale(1, 1)
		t.Text = "⭐"
		t.TextScaled = true
		t.Parent = gui
		gui.Parent = head
		stars[i] = gui
	end
	local t0 = os.clock()
	local conn
	conn = RunService.RenderStepped:Connect(function()
		local t = os.clock() - t0
		if t > duration or not head.Parent then
			conn:Disconnect()
			for _, s in stars do
				s:Destroy()
			end
			return
		end
		for i, s in stars do
			local a = t * 6 + i * (math.pi * 2 / 3)
			s.StudsOffsetWorldSpace = Vector3.new(math.cos(a) * 1.6, 1.4, math.sin(a) * 1.6)
		end
	end)
end

function CharacterFx.Init()
	if player.Character then
		watchCharacter(player.Character)
	end
	player.CharacterAdded:Connect(watchCharacter)

	FxBus.On("Knockback", function(args)
		local character = player.Character
		local root = rootOf(player)
		local humanoid = character and character:FindFirstChildOfClass("Humanoid")
		if not root or not humanoid then
			return
		end
		humanoid:ChangeState(Enum.HumanoidStateType.FallingDown)
		root.AssemblyLinearVelocity = args.Velocity or Vector3.new(0, 50, 0)
		root.AssemblyAngularVelocity = Vector3.new(math.random(-8, 8), math.random(-8, 8), math.random(-8, 8))
		Audio.Play("bonk")
		CameraFx.Shake(1, 0.4)
		dizzy(character, 1.6)
		task.delay(0.9, function()
			if humanoid.Parent then
				humanoid:ChangeState(Enum.HumanoidStateType.GettingUp)
			end
		end)
		if args.From then
			UIRegistry.Toast(("%s bonked you! 😵"):format(args.From), "Bad")
		end
	end)

	FxBus.On("BonkHit", function(args)
		local pos = args.Position
		if typeof(pos) ~= "Vector3" then
			return
		end
		Effects.FloatingText(pos + Vector3.new(0, 4, 0), BONK_WORDS[math.random(1, #BONK_WORDS)], C.Gold, 1.2)
		Effects.Burst(pos + Vector3.new(0, 2, 0), C.Gold, 18, 1.6)
		if args.UserId ~= player.UserId then
			Audio.Play("bonk", { Parent = rootOf(Players:GetPlayerByUserId(args.UserId)) })
		end
	end)

	FxBus.On("BonkSwing", function(args)
		if args.UserId == player.UserId then
			return
		end
		local root = rootOf(Players:GetPlayerByUserId(args.UserId or 0))
		if root then
			Audio.Play("knockback_whoosh", { Parent = root, Volume = 0.5 })
		end
	end)

	FxBus.On("Rebirth", function(args)
		local root = rootOf(Players:GetPlayerByUserId(args.UserId or 0))
		if root then
			Effects.Pillar(root.Position, C.Radioactive, 3)
			Effects.Burst(root.Position, C.Radioactive, 60, 3)
		end
	end)
end

return CharacterFx
