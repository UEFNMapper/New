--!strict
--[[
	RemoteGuard : point d'entrée UNIQUE des requêtes client.
	Pour chaque remote : limite de fréquence, session chargée obligatoire, validation
	stricte du nombre et du type des arguments. Toute requête invalide est ignorée
	(et comptée ; au-delà d'un seuil, le joueur est expulsé pour abus).

	Usage :
		RemoteGuard.On("Upgrade", { Limit = "Upgrade", Args = { RemoteGuard.String(16), RemoteGuard.Int(-1, 10) } },
			function(session, moduleId, amount) ... end)
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local GameConfig = require(Shared.Config.GameConfig)
local Remotes = require(Shared.Net.Remotes)
local RateLimiter = require(script.Parent.RateLimiter)
local Session = require(script.Parent.Parent.Core.Session)

export type Validator = (value: any) -> boolean
export type Spec = {
	Limit: string?, -- clé de GameConfig.RateLimits (Default si absent)
	Args: { Validator },
}

local RemoteGuard = {}

local MAX_STRIKES = 60 -- requêtes invalides tolérées par session avant expulsion
local limiters: { [string]: RateLimiter.Limiter } = {}
local strikes: { [Player]: number } = {}

local function limiterFor(limitKey: string): RateLimiter.Limiter
	local existing = limiters[limitKey]
	if existing then
		return existing
	end
	local params = (GameConfig.RateLimits :: any)[limitKey] or GameConfig.RateLimits.Default
	local limiter = RateLimiter.new(params.Rate, params.Burst)
	limiters[limitKey] = limiter
	return limiter
end

local function strike(player: Player, reason: string)
	local count = (strikes[player] or 0) + 1
	strikes[player] = count
	if count == 20 then
		warn(`[RemoteGuard] {player.Name} : requêtes invalides répétées ({reason})`)
	end
	if count >= MAX_STRIKES then
		player:Kick("Trop de requêtes invalides.")
	end
end

-- Validateurs ------------------------------------------------------------------

function RemoteGuard.String(maxLength: number): Validator
	return function(value: any): boolean
		return type(value) == "string" and #value > 0 and #value <= maxLength and utf8.len(value) ~= nil
	end
end

function RemoteGuard.Int(min: number, max: number): Validator
	return function(value: any): boolean
		return type(value) == "number" and value == value and value % 1 == 0 and value >= min and value <= max
	end
end

function RemoteGuard.Number(min: number, max: number): Validator
	return function(value: any): boolean
		return type(value) == "number" and value == value and value >= min and value <= max
	end
end

function RemoteGuard.Bool(): Validator
	return function(value: any): boolean
		return type(value) == "boolean"
	end
end

function RemoteGuard.OneOf(options: { string }): Validator
	local set: { [string]: boolean } = {}
	for _, option in options do
		set[option] = true
	end
	return function(value: any): boolean
		return type(value) == "string" and set[value] == true
	end
end

-- Branchement -------------------------------------------------------------------

function RemoteGuard.On(name: string, spec: Spec, handler: (Session.Session, ...any) -> ())
	local remote = Remotes.Get(name)
	local limiter = limiterFor(spec.Limit or "Default")
	local argCount = #spec.Args

	remote.OnServerEvent:Connect(function(player: Player, ...: any)
		if not limiter:Allow(`{player.UserId}:{name}`) then
			return -- trop rapide : ignoré silencieusement (pas de strike, ça peut être du lag)
		end
		local session = Session.Get(player)
		if not session then
			return
		end
		if select("#", ...) ~= argCount then
			strike(player, `{name} : nombre d'arguments`)
			return
		end
		local args = table.pack(...)
		for index, validate in spec.Args do
			if not validate(args[index]) then
				strike(player, `{name} : argument {index} invalide`)
				return
			end
		end
		xpcall(handler, function(err: any)
			warn(`[RemoteGuard] erreur dans {name} :`, err, debug.traceback())
		end, session, table.unpack(args, 1, argCount))
	end)
end

-- Distance entre le personnage du joueur et une position (math.huge sans personnage).
function RemoteGuard.DistanceTo(player: Player, position: Vector3): number
	local character = player.Character
	local root = character and character:FindFirstChild("HumanoidRootPart")
	if root and root:IsA("BasePart") then
		return (root.Position - position).Magnitude
	end
	return math.huge
end

Players.PlayerRemoving:Connect(function(player: Player)
	strikes[player] = nil
	for _, limiter in limiters do
		limiter:Forget(`{player.UserId}:`)
	end
end)

return table.freeze(RemoteGuard)
