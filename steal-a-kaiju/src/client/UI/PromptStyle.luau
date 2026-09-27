--!nonstrict
-- Prompts de proximité au style du jeu (touche dans une pastille encrée,
-- bouton coloré, anneau de maintien). S'applique aux prompts « Custom ».

local ProximityPromptService = game:GetService("ProximityPromptService")
local UserInputService = game:GetService("UserInputService")
local TweenService = game:GetService("TweenService")
local Players = game:GetService("Players")

local Kit = require(script.Parent.Kit)
local Audio = require(script.Parent.Parent.Controllers.Audio)

local C = Kit.Colors
local F = Kit.Fonts

local PromptStyle = {}

local function keyText(prompt: ProximityPrompt, inputType: Enum.ProximityPromptInputType): string
	if inputType == Enum.ProximityPromptInputType.Touch then
		return "👆"
	elseif inputType == Enum.ProximityPromptInputType.Gamepad then
		return "X"
	end
	return UserInputService:GetStringForKeyCode(prompt.KeyboardKeyCode)
end

local function build(prompt: ProximityPrompt, inputType: Enum.ProximityPromptInputType, gui: ScreenGui)
	local billboard = Kit.new("BillboardGui", {
		Name = "Prompt",
		Size = UDim2.fromOffset(250, 76),
		AlwaysOnTop = true,
		LightInfluence = 0,
		Adornee = prompt.Parent,
		Active = true,
		Parent = gui,
	})
	local colorName = prompt:GetAttribute("Color") or "Radioactive"
	local button = Kit.Button({
		Text = prompt.ActionText,
		Color = colorName,
		Size = UDim2.fromOffset(180, 56),
		Position = UDim2.fromOffset(62, 8),
		TextSize = 24,
		Sound = "ui_click",
		Parent = billboard,
	})
	local key = Kit.new("Frame", {
		Size = UDim2.fromOffset(56, 56),
		Position = UDim2.fromOffset(4, 8),
		BackgroundColor3 = C.Paper,
		ZIndex = 8,
		Parent = billboard,
	}, { Kit.Round(), Kit.Stroke(4) })
	Kit.Text({
		Size = UDim2.fromScale(0.7, 0.7),
		Position = UDim2.fromScale(0.5, 0.5),
		AnchorPoint = Vector2.new(0.5, 0.5),
		Text = keyText(prompt, inputType),
		TextColor3 = C.Ink,
		Stroke = false,
		ZIndex = 9,
		Parent = key,
	})
	-- anneau de maintien (barre qui se remplit sous la touche)
	local holdBar = Kit.new("Frame", {
		Size = UDim2.new(0, 0, 0, 8),
		Position = UDim2.fromOffset(62, 70),
		BackgroundColor3 = C.Gold,
		ZIndex = 9,
		Parent = billboard,
	}, { Kit.Round(), Kit.Stroke(2) })
	if prompt.ObjectText ~= "" then
		Kit.Text({
			Size = UDim2.fromOffset(240, 22),
			Position = UDim2.fromOffset(4, -16),
			Text = prompt.ObjectText,
			FontFace = F.Body,
			TextXAlignment = Enum.TextXAlignment.Left,
			ZIndex = 9,
			Parent = billboard,
		})
	end
	Kit.Pop(billboard:FindFirstChildWhichIsA("TextButton") :: any, 0.5, 0.3)

	local holdTween: Tween? = nil
	local conns = {}
	table.insert(conns, prompt.PromptButtonHoldBegan:Connect(function()
		if prompt.HoldDuration > 0 then
			holdBar.Size = UDim2.new(0, 0, 0, 8)
			holdTween = TweenService:Create(holdBar, TweenInfo.new(prompt.HoldDuration, Enum.EasingStyle.Linear), { Size = UDim2.new(0, 180, 0, 8) })
			holdTween:Play()
			Audio.Play("steal_grab", { Pitch = 0.7, Volume = 0.4 })
		end
	end))
	table.insert(conns, prompt.PromptButtonHoldEnded:Connect(function()
		if holdTween then
			holdTween:Cancel()
		end
		holdBar.Size = UDim2.new(0, 0, 0, 8)
	end))
	table.insert(conns, prompt.Triggered:Connect(function()
		Kit.Punch(button, 0.2)
	end))
	table.insert(conns, prompt:GetPropertyChangedSignal("ActionText"):Connect(function()
		Kit.SetButtonText(button, prompt.ActionText)
	end))
	table.insert(conns, prompt.AttributeChanged:Connect(function(attr)
		if attr == "Color" then
			Kit.SetButtonColor(button, prompt:GetAttribute("Color") or "Radioactive")
		end
	end))
	-- clic / tap sur le bouton
	button.Activated:Connect(function()
		if prompt.HoldDuration <= 0 then
			prompt:InputHoldBegin()
			prompt:InputHoldEnd()
		end
	end)
	button.MouseButton1Down:Connect(function()
		if prompt.HoldDuration > 0 then
			prompt:InputHoldBegin()
		end
	end)
	button.MouseButton1Up:Connect(function()
		if prompt.HoldDuration > 0 then
			prompt:InputHoldEnd()
		end
	end)
	return function()
		for _, c in conns do
			c:Disconnect()
		end
		billboard:Destroy()
	end
end

function PromptStyle.Init()
	local gui = Kit.new("ScreenGui", {
		Name = "Prompts",
		ResetOnSpawn = false,
		Parent = Players.LocalPlayer:WaitForChild("PlayerGui"),
	})
	ProximityPromptService.PromptShown:Connect(function(prompt, inputType)
		if prompt.Style ~= Enum.ProximityPromptStyle.Custom then
			return
		end
		local cleanup = build(prompt, inputType, gui)
		prompt.PromptHidden:Once(cleanup)
	end)
end

return PromptStyle
