--!strict
--[[
	SocialService : bonus entre amis, likes de PC, paramètres joueur.
	- +10 % de Bits par ami présent dans le serveur (max +30 %)
	- 1 like par joueur et par jour ; le propriétaire est notifié
]]

local Session = require(script.Parent.Parent.Core.Session)
local GameEvents = require(script.Parent.Parent.Core.GameEvents)
local RemoteGuard = require(script.Parent.Parent.Security.RemoteGuard)
local EconomyService = require(script.Parent.EconomyService)
local WorldService = require(script.Parent.WorldService)

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
				EconomyService.Notify(session, "Boost", `Bonus d'amis : +{count * 10} % de Bits !`)
			end
			EconomyService.Refresh(session)
		end
	end
end

function SocialService.Like(session: Session.Session, ownerUserId: number)
	if ownerUserId == session.UserId then
		return
	end
	local owner = Session.ByUserId(ownerUserId)
	if not owner then
		return
	end
	local likes = session.Data.Likes
	local key = tostring(ownerUserId)
	if table.find(likes.GivenTo, key) then
		EconomyService.Notify(session, "Info", "Tu as déjà liké ce PC aujourd'hui.")
		return
	end
	table.insert(likes.GivenTo, key)
	owner.Data.Likes.Received += 1
	WorldService.Sync(owner)
	EconomyService.Notify(session, "Success", `Tu as liké le PC de {owner.Player.DisplayName} !`)
	EconomyService.Notify(owner, "Like", `{session.Player.DisplayName} a liké ton PC !`)
	GameEvents.TowerLiked:Fire(session.Player, ownerUserId)
end

function SocialService.SaveSettings(
	session: Session.Session,
	music: number,
	sfx: number,
	reducedMotion: boolean,
	rgbHue: number
)
	local settings = session.Data.Settings
	settings.Music = music
	settings.Sfx = sfx
	settings.ReducedMotion = reducedMotion
	settings.RgbHue = rgbHue
	WorldService.Sync(session)
end

function SocialService.Start()
	Session.Added:Connect(function(_session: Session.Session)
		task.spawn(recomputeFriends)
	end)
	Session.Removing:Connect(function(_session: Session.Session)
		task.defer(recomputeFriends)
	end)
	RemoteGuard.On("LikeTower", { Args = { RemoteGuard.Int(1, 2 ^ 53) } }, SocialService.Like)
	RemoteGuard.On("SaveSettings", {
		Limit = "Settings",
		Args = {
			RemoteGuard.Number(0, 1),
			RemoteGuard.Number(0, 1),
			RemoteGuard.Bool(),
			RemoteGuard.Number(-1, 1),
		},
	}, SocialService.SaveSettings)
end

return SocialService
