--!strict
--[[
	SocialService : bonus entre amis (+10 % de Bits par ami présent, max +30 %),
	réglages du joueur, et fin de l'intro d'Anga.
]]

local Session = require(script.Parent.Parent.Core.Session)
local Wallet = require(script.Parent.Parent.Core.Wallet)
local GameEvents = require(script.Parent.Parent.Core.GameEvents)
local RemoteGuard = require(script.Parent.Parent.Security.RemoteGuard)

local SocialService = {}

local friendCache: { [string]: boolean } = {}

local function pairKey(a: number, b: number): string
	return if a < b then `{a}:{b}` else `{b}:{a}`
end

local function areFriends(a: Session.Session, b: Session.Session): boolean
	local key = pairKey(a.UserId, b.UserId)
	local cached = friendCache[key]
	if cached ~= nil then
		return cached
	end
	local ok, result = pcall(function(): boolean
		return a.Player:IsFriendsWithAsync(b.UserId)
	end)
	local friends = ok and result == true
	friendCache[key] = friends
	return friends
end

local function recomputeFriends()
	local all = Session.All()
	for _, session in all do
		local count = 0
		for _, other in all do
			if other ~= session and areFriends(session, other) then
				count += 1
			end
		end
		if count ~= session.FriendsInServer then
			session.FriendsInServer = count
			if count > 0 then
				Wallet.Notify(session, "Boost", `Bonus d'amis : +{math.min(count * 10, 30)} % de Bits !`)
			end
			GameEvents.StateChanged:Fire(session.Player)
		end
	end
end

function SocialService.Start()
	Session.Added:Connect(function(_session: Session.Session)
		task.spawn(recomputeFriends)
	end)
	Session.Removing:Connect(function(_session: Session.Session)
		task.defer(recomputeFriends)
	end)
	RemoteGuard.On("SaveSettings", {
		Limit = "Settings",
		Args = { RemoteGuard.Number(0, 1), RemoteGuard.Number(0, 1), RemoteGuard.Bool() },
	}, function(session: Session.Session, music: number, sfx: number, reduced: boolean)
		local settings = session.Data.Settings
		settings.Music = music
		settings.Sfx = sfx
		settings.ReducedMotion = reduced
	end)
	RemoteGuard.On("IntroSeen", { Args = {} }, function(session: Session.Session)
		if not session.Data.IntroSeen then
			session.Data.IntroSeen = true
			GameEvents.StateChanged:Fire(session.Player)
		end
	end)
end

return SocialService
