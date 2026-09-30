--!strict
--[[
	Wallet : Bits du joueur (gains avec bonus, dépenses) + messages vers son client.
	Module sans état : utilisable par tous les services sans cycle de require.
	Bonus sur les gains « de jeu » : VIP x2, amis (+10 % chacun, max +30 %), groupe (+5 %).
	Les achats Robux et les récompenses fixes (quotidien) ne sont pas multipliés.
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local GameConfig = require(Shared.Config.GameConfig)
local Remotes = require(Shared.Net.Remotes)
local Session = require(script.Parent.Session)
local GameEvents = require(script.Parent.GameEvents)
local Telemetry = require(script.Parent.Telemetry)

local Wallet = {}

local notifyRemote: RemoteEvent? = nil
local fxRemote: RemoteEvent? = nil

local function remote(name: string): RemoteEvent
	if name == "Notify" then
		notifyRemote = notifyRemote or Remotes.Get("Notify")
		return notifyRemote :: RemoteEvent
	end
	fxRemote = fxRemote or Remotes.Get("Fx")
	return fxRemote :: RemoteEvent
end

-- Multiplicateur des gains de jeu pour ce joueur.
function Wallet.Multiplier(session: Session.Session): number
	local mult = 1
	if session.Passes.VIP then
		mult *= GameConfig.VipBitsMultiplier
	end
	local friends = math.min(session.FriendsInServer * GameConfig.FriendBonusPerFriend, GameConfig.FriendBonusMax)
	mult *= 1 + friends + (if session.InGroup then GameConfig.GroupBonus else 0)
	return mult
end

-- Ajoute des Bits. `boosted` = appliquer les bonus (gains de jeu). Renvoie le montant réel.
function Wallet.Add(session: Session.Session, amount: number, source: string, boosted: boolean): number
	local gain = math.floor(amount * (if boosted then Wallet.Multiplier(session) else 1) + 0.5)
	if gain <= 0 then
		return 0
	end
	local data = session.Data
	data.Bits += gain
	data.TotalBits += gain
	Telemetry.Economy(session.Player, "Source", "Bits", gain, data.Bits, source)
	GameEvents.StateChanged:Fire(session.Player)
	return gain
end

-- Dépense des Bits si le solde suffit.
function Wallet.Spend(session: Session.Session, amount: number, sink: string, sku: string?): boolean
	local data = session.Data
	if amount < 0 or data.Bits < amount then
		return false
	end
	data.Bits -= amount
	Telemetry.Economy(session.Player, "Sink", "Bits", amount, data.Bits, sink, sku)
	GameEvents.StateChanged:Fire(session.Player)
	return true
end

-- Petit message à l'écran (kind : "Info" | "Success" | "Error" | "Reward" | …).
function Wallet.Notify(session: Session.Session, kind: string, text: string)
	if session.Player.Parent then
		remote("Notify"):FireClient(session.Player, kind, text)
	end
end

-- Effet ponctuel pour le client de ce joueur.
function Wallet.Fx(session: Session.Session, kind: string, payload: { [string]: any })
	if session.Player.Parent then
		remote("Fx"):FireClient(session.Player, kind, payload)
	end
end

-- Effet visible par tous les joueurs (ex. effet de mort).
function Wallet.FxAll(kind: string, payload: { [string]: any })
	remote("Fx"):FireAllClients(kind, payload)
end

return Wallet
