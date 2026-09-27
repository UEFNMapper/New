--!nonstrict
-- Centre des récompenses : un seul bouton du HUD pour la série quotidienne,
-- les cadeaux de temps de jeu, les quêtes du jour et la roue.

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Format = require(Shared.Logic.Format)

local Kit = require(script.Parent.Parent.Kit)
local Controllers = script.Parent.Parent.Parent.Controllers
local State = require(Controllers.State)
local UIRegistry = require(Controllers.UIRegistry)

local C = Kit.Colors
local F = Kit.Fonts

local Rewards = {}

local window
local tiles: { [string]: { Button: GuiObject, Status: TextLabel } } = {}

local TILES = {
	{ Id = "Daily", Title = "DAILY STREAK", Icon = "daily", Color = "Gold", Text = "Come back every day!" },
	{ Id = "Playtime", Title = "PLAY GIFTS", Icon = "gifts", Color = "Pink", Text = "Free gifts while you play" },
	{ Id = "Quests", Title = "DAILY QUESTS", Icon = "quests", Color = "Radioactive", Text = "3 new quests every day" },
	{ Id = "Spin", Title = "LUCKY SPIN", Icon = "spin", Color = "Cyan", Text = "Spin to win eggs & gems" },
}

-- Ce que chaque tuile a à réclamer (et un texte d'état).
local function status(id: string): (number, string)
	local screen = UIRegistry.Screens[id]
	if not screen then
		return 0, ""
	end
	if id == "Daily" and screen.CanClaim then
		local ok = screen.CanClaim()
		return if ok then 1 else 0, if ok then "READY TO CLAIM!" else "Claimed today ✓"
	elseif id == "Playtime" and screen.ClaimableCount then
		local n = screen.ClaimableCount()
		local wait = if screen.NextReadyIn then screen.NextReadyIn() else -1
		local text = if n > 0 then ("%d GIFT%s READY!"):format(n, if n > 1 then "S" else "") elseif wait > 0 then "Next gift in " .. Format.Clock(wait) else "All gifts opened ✓"
		return n, text
	elseif id == "Quests" and screen.ClaimableCount then
		local n = screen.ClaimableCount()
		return n, if n > 0 then ("%d QUEST%s DONE!"):format(n, if n > 1 then "S" else "") else "Keep playing!"
	elseif id == "Spin" and screen.CanFreeSpin then
		local free = screen.CanFreeSpin()
		local spins = State.Get("Spins") or 0
		local n = if free then 1 else spins
		return n, if free then "FREE SPIN!" elseif spins > 0 then ("%d SPIN%s"):format(spins, if spins > 1 then "S" else "") else "Next free spin soon"
	end
	return 0, ""
end

-- Total à réclamer (badge du bouton REWARDS du HUD).
function Rewards.ClaimableCount(): number
	local total = 0
	for _, t in TILES do
		total += (status(t.Id))
	end
	return total
end

local function refresh()
	for _, t in TILES do
		local tile = tiles[t.Id]
		local n, text = status(t.Id)
		tile.Status.Text = text
		tile.Status.TextColor3 = if n > 0 then C.Gold else C.Paper
		Kit.SetBadge(tile.Button, n > 0, if n > 1 then tostring(n) else "!")
	end
end

function Rewards.Init()
	window = Kit.Window({ Name = "Rewards", Title = "REWARDS", Icon = "🎁", Color = "Pink", Size = UDim2.fromOffset(700, 460), RibbonWidth = 320 })
	local grid = Kit.new("Frame", {
		Size = UDim2.new(1, -20, 1, -20),
		Position = UDim2.fromOffset(10, 10),
		BackgroundTransparency = 1,
		Parent = window.Frame,
	}, {
		Kit.new("UIGridLayout", {
			CellSize = UDim2.new(0.5, -12, 0.5, -12),
			CellPadding = UDim2.fromOffset(20, 20),
			SortOrder = Enum.SortOrder.LayoutOrder,
			HorizontalAlignment = Enum.HorizontalAlignment.Center,
			VerticalAlignment = Enum.VerticalAlignment.Center,
		}),
	})
	for i, t in TILES do
		local button = Kit.Button({
			Name = t.Id,
			Text = "",
			Color = t.Color,
			Size = UDim2.fromOffset(300, 160),
			LayoutOrder = i,
			Corner = 20,
			Parent = grid,
			OnClick = function()
				local screen = UIRegistry.Screens[t.Id]
				if screen and screen.Open then
					screen.Open()
				end
			end,
		})
		local face = button:FindFirstChild("Face") or button
		local icon = Kit.Icon(t.Icon, { Size = UDim2.fromOffset(84, 84), Position = UDim2.new(0, 14, 0.5, 0), AnchorPoint = Vector2.new(0, 0.5), ZIndex = 12, Parent = face })
		Kit.Wobble(icon, 6, 1.1 + i * 0.1)
		Kit.Text({ Size = UDim2.new(1, -118, 0, 36), Position = UDim2.fromOffset(108, 22), Text = t.Title, FontFace = F.Title, TextXAlignment = Enum.TextXAlignment.Left, MaxTextSize = 28, Stroke = 3, ZIndex = 13, Parent = face })
		Kit.Text({ Size = UDim2.new(1, -118, 0, 22), Position = UDim2.fromOffset(108, 60), Text = t.Text, FontFace = F.Body, TextXAlignment = Enum.TextXAlignment.Left, MaxTextSize = 16, Stroke = 2, ZIndex = 13, Parent = face })
		local statusLabel = Kit.Text({ Size = UDim2.new(1, -118, 0, 28), Position = UDim2.fromOffset(108, 92), Text = "", FontFace = F.Impact, TextXAlignment = Enum.TextXAlignment.Left, MaxTextSize = 24, Stroke = 3, ZIndex = 13, Parent = face })
		tiles[t.Id] = { Button = button, Status = statusLabel }
	end
	task.spawn(function()
		while true do
			if window.IsOpen then
				refresh()
			end
			task.wait(0.5)
		end
	end)
end

function Rewards.Open()
	window:Open()
	refresh()
end

function Rewards.Close()
	window:Close()
end

return Rewards
