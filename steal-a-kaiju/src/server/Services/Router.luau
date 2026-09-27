--!nonstrict
-- Aiguillage des requêtes client. Chaque service enregistre ses actions ;
-- toutes les entrées sont validées ici (type) et limitées en débit.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Net = require(Shared.Net)

local Router = {}

export type Result = { ok: boolean, msg: string?, [string]: any }
type Handler = (player: Player, payload: any) -> Result?

local handlers: { [string]: { fn: Handler, perSecond: number } } = {}
local buckets: { [Player]: { [string]: { tokens: number, last: number } } } = {}
local inputHandlers: { [string]: (player: Player, payload: any) -> () } = {}

-- `perSecond` : nombre maximal d'appels par seconde (seau à jetons).
function Router.On(action: string, fn: Handler, perSecond: number?)
	assert(handlers[action] == nil, "Action déjà enregistrée : " .. action)
	handlers[action] = { fn = fn, perSecond = perSecond or 4 }
end

function Router.OnInput(kind: string, fn: (player: Player, payload: any) -> ())
	inputHandlers[kind] = fn
end

local function allow(player: Player, action: string, perSecond: number): boolean
	local b = buckets[player]
	if not b then
		b = {}
		buckets[player] = b
	end
	local now = os.clock()
	local bucket = b[action]
	if not bucket then
		bucket = { tokens = perSecond * 2, last = now }
		b[action] = bucket
	end
	bucket.tokens = math.min(perSecond * 2, bucket.tokens + (now - bucket.last) * perSecond)
	bucket.last = now
	if bucket.tokens < 1 then
		return false
	end
	bucket.tokens -= 1
	return true
end

function Router.Init()
	local remote = Net.Function("Action")
	remote.OnServerInvoke = function(player: Player, action: any, payload: any): Result
		if type(action) ~= "string" then
			return { ok = false, msg = "Bad request" }
		end
		local h = handlers[action]
		if not h then
			return { ok = false, msg = "Unknown action" }
		end
		if not allow(player, action, h.perSecond) then
			return { ok = false, msg = "Slow down!" }
		end
		if payload ~= nil and type(payload) ~= "table" then
			return { ok = false, msg = "Bad payload" }
		end
		local ok, result = pcall(h.fn, player, payload or {})
		if not ok then
			warn("[Router] " .. action .. " : " .. tostring(result))
			return { ok = false, msg = "Something went wrong" }
		end
		return result or { ok = true }
	end

	Net.Event("Input").OnServerEvent:Connect(function(player: Player, kind: any, payload: any)
		if type(kind) ~= "string" then
			return
		end
		local fn = inputHandlers[kind]
		if not fn or not allow(player, "input:" .. kind, 12) then
			return
		end
		local ok, err = pcall(function()
			fn(player, payload)
		end)
		if not ok then
			warn("[Router] input " .. kind .. " : " .. tostring(err))
		end
	end)

	Players.PlayerRemoving:Connect(function(player)
		buckets[player] = nil
	end)
end

-- Aides de validation
function Router.String(v: any, maxLen: number?): string?
	if type(v) == "string" and #v <= (maxLen or 64) then
		return v
	end
	return nil
end

function Router.Int(v: any, min: number, max: number): number?
	if type(v) == "number" and v == v and v % 1 == 0 and v >= min and v <= max then
		return v
	end
	return nil
end

return Router
