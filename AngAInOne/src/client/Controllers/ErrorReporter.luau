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

-- Messages du MOTEUR Roblox qui ne viennent pas du jeu (animations / sons de l'avatar du joueur,
-- assets privés non téléchargeables en Studio…) : ils restent dans la Sortie, pas à l'écran.
local ENGINE_NOISE = {
	"Failed to load animation",
	"Failed to load sound",
	"assetdelivery.roblox.com",
	"Asset is not approved",
	"is not authorized to access",
}

local function isEngineNoise(message: string): boolean
	for _, pattern in ENGINE_NOISE do
		if string.find(message, pattern, 1, true) then
			return true
		end
	end
	return false
end

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
		-- En haut à droite, compact : ne recouvre ni les boutons du jeu ni les cartes d'intro.
		box.AnchorPoint = Vector2.new(1, 0)
		box.Position = UDim2.new(1, -12, 0, 96)
		box.Size = UDim2.new(0.4, 0, 0, 120)
		box.BackgroundColor3 = Color3.fromRGB(60, 10, 16)
		box.BackgroundTransparency = 0.1
		box.TextColor3 = Color3.fromRGB(255, 200, 200)
		box.TextXAlignment = Enum.TextXAlignment.Left
		box.TextYAlignment = Enum.TextYAlignment.Top
		box.TextWrapped = true
		box.TextSize = 14
		box.Font = Enum.Font.Code
		box.Parent = gui
		-- ✕ pour fermer l'encadré (il se rouvre à la prochaine erreur)
		local close = Instance.new("TextButton")
		close.AnchorPoint = Vector2.new(1, 0)
		close.Position = UDim2.new(1, -4, 0, 4)
		close.Size = UDim2.fromOffset(28, 28)
		close.BackgroundColor3 = Color3.fromRGB(120, 20, 30)
		close.TextColor3 = Color3.new(1, 1, 1)
		close.Text = "✕"
		close.TextSize = 16
		close.Font = Enum.Font.GothamBold
		close.Parent = box
		close.Activated:Connect(function()
			box.Visible = false
			table.clear(lines)
		end)
		local padding = Instance.new("UIPadding")
		padding.PaddingLeft = UDim.new(0, 10)
		padding.PaddingTop = UDim.new(0, 8)
		padding.Parent = box
		gui.Parent = Players.LocalPlayer:WaitForChild("PlayerGui")
		label = box
	end
	local box = label
	if box then
		box.Visible = true
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
		if messageType == Enum.MessageType.MessageError and not isEngineNoise(message) then
			show(message)
		end
	end)
end

return ErrorReporter
