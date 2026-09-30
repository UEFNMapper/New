--!strict
--[[
	ErrorReporter : dans Roblox Studio UNIQUEMENT, affiche les erreurs du client dans un
	encadré rouge à l'écran (en plus de la fenêtre Sortie), pour pouvoir les copier
	facilement. Ne dépend d'aucun autre module du jeu : il marche même si l'UI plante.
]]

local LogService = game:GetService("LogService")
local Players = game:GetService("Players")
local RunService = game:GetService("RunService")

local ErrorReporter = {}

local label: TextLabel? = nil
local lines: { string } = {}

local function show(text: string)
	if not RunService:IsStudio() then
		return
	end
	table.insert(lines, text)
	while #lines > 6 do
		table.remove(lines, 1)
	end
	if not label then
		local gui = Instance.new("ScreenGui")
		gui.Name = "AngAInOneErrors"
		gui.DisplayOrder = 1000
		gui.ResetOnSpawn = false
		local box = Instance.new("TextLabel")
		box.AnchorPoint = Vector2.new(0.5, 1)
		box.Position = UDim2.new(0.5, 0, 1, -130)
		box.Size = UDim2.new(0.8, 0, 0, 160)
		box.BackgroundColor3 = Color3.fromRGB(60, 10, 16)
		box.BackgroundTransparency = 0.1
		box.TextColor3 = Color3.fromRGB(255, 200, 200)
		box.TextXAlignment = Enum.TextXAlignment.Left
		box.TextYAlignment = Enum.TextYAlignment.Top
		box.TextWrapped = true
		box.TextSize = 14
		box.Font = Enum.Font.Code
		box.Parent = gui
		local padding = Instance.new("UIPadding")
		padding.PaddingLeft = UDim.new(0, 10)
		padding.PaddingTop = UDim.new(0, 8)
		padding.Parent = box
		gui.Parent = Players.LocalPlayer:WaitForChild("PlayerGui")
		label = box
	end
	local box = label
	if box then
		box.Text = "[AngAInOne · erreurs client (Studio)] Copie ce texte et envoie-le :\n" .. table.concat(lines, "\n")
	end
end

function ErrorReporter.Report(context: string, err: any)
	local text = `{context} : {tostring(err)}`
	warn("[AngAInOne]", text)
	show(text)
end

function ErrorReporter.Start()
	LogService.MessageOut:Connect(function(message: string, messageType: Enum.MessageType)
		if messageType == Enum.MessageType.MessageError then
			show(message)
		end
	end)
end

return ErrorReporter
