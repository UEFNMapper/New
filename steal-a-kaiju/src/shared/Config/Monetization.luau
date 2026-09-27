--!strict
-- Boutique Premium (Robux).
--
-- ⚠️ À CONFIGURER : crée chaque Game Pass et Developer Product sur le Creator Hub,
-- puis colle son identifiant dans le champ `Id`. Tant que `Id = 0`, l'achat est
-- simulé gratuitement DANS STUDIO UNIQUEMENT (pour les playtests) et désactivé
-- en ligne.

export type Pass = {
	Key: string,
	Id: number,
	Name: string,
	Description: string,
	Icon: string,
	Robux: number, -- prix conseillé (affiché si le prix réel n'est pas disponible)
	Color: Color3,
	Featured: boolean?,
	Random: boolean?, -- lié au hasard payant : masqué si ArePaidRandomItemsRestricted
}

export type Product = {
	Key: string,
	Id: number,
	Name: string,
	Description: string,
	Icon: string,
	Robux: number,
	Category: string, -- Cash | Gems | Boost | Kaiju | Server | Pack
	Amount: number?,
	Color: Color3,
	OneTime: boolean?,
	Random: boolean?,
}

local rgb = Color3.fromRGB

local Monetization = {}

Monetization.Passes = {
	{ Key = "VIP", Id = 0, Name = "VIP", Description = "+20% cash, VIP tag, golden name, +1 free spin per day", Icon = "👑", Robux = 399, Color = rgb(255, 196, 40), Featured = true },
	{ Key = "DoubleCash", Id = 0, Name = "2x Cash", Description = "Double ALL cash, forever", Icon = "💰", Robux = 499, Color = rgb(90, 220, 110), Featured = true },
	{ Key = "AutoCollect", Id = 0, Name = "Auto Collect", Description = "Cash goes straight to your wallet", Icon = "🧲", Robux = 249, Color = rgb(80, 200, 255) },
	{ Key = "ExtraNests", Id = 0, Name = "+3 Nests", Description = "Three extra nest slots on your island", Icon = "🪺", Robux = 299, Color = rgb(255, 150, 60) },
	{ Key = "LuckyAura", Id = 0, Name = "Lucky Aura", Description = "x2 personal luck: better personal meteors and mutations", Icon = "🍀", Robux = 349, Color = rgb(120, 255, 140), Random = true },
	{ Key = "FastGrowth", Id = 0, Name = "Fast Growth", Description = "Your kaijus grow 50% faster", Icon = "🌱", Robux = 349, Color = rgb(190, 255, 90) },
	{ Key = "SuperBonk", Id = 0, Name = "Super Bonk", Description = "Golden bonker: bigger range and knockback", Icon = "🔨", Robux = 199, Color = rgb(255, 120, 60) },
	{ Key = "MegaShield", Id = 0, Name = "Mega Shield", Description = "Your base shield lasts twice as long", Icon = "🛡️", Robux = 199, Color = rgb(120, 140, 255) },
	{ Key = "Offline", Id = 0, Name = "Night Shift", Description = "Earn offline for up to 8 hours", Icon = "🌙", Robux = 149, Color = rgb(150, 120, 255) },
} :: { Pass }

Monetization.Products = {
	{ Key = "StarterPack", Id = 0, Name = "Starter Pack", Description = "Legendary egg + 150 gems + 2 Luck potions. Once per player!", Icon = "🎁", Robux = 99, Category = "Pack", Color = rgb(255, 90, 170), OneTime = true, Random = true },
	{ Key = "CashS", Id = 0, Name = "Pile of Cash", Description = "10 minutes of your income", Icon = "💵", Robux = 29, Category = "Cash", Amount = 600, Color = rgb(90, 220, 110), Random = true },
	{ Key = "CashM", Id = 0, Name = "Bag of Cash", Description = "1 hour of your income", Icon = "💰", Robux = 99, Category = "Cash", Amount = 3600, Color = rgb(60, 200, 90), Random = true },
	{ Key = "CashL", Id = 0, Name = "Vault of Cash", Description = "6 hours of your income", Icon = "🏦", Robux = 399, Category = "Cash", Amount = 21600, Color = rgb(30, 170, 70), Random = true },
	{ Key = "Gems100", Id = 0, Name = "100 Gems", Description = "", Icon = "💎", Robux = 49, Category = "Gems", Amount = 100, Color = rgb(80, 200, 255), Random = true },
	{ Key = "Gems550", Id = 0, Name = "550 Gems", Description = "+10% bonus", Icon = "💎", Robux = 199, Category = "Gems", Amount = 550, Color = rgb(60, 160, 255), Random = true },
	{ Key = "Gems1400", Id = 0, Name = "1,400 Gems", Description = "+40% bonus", Icon = "💎", Robux = 449, Category = "Gems", Amount = 1400, Color = rgb(60, 110, 255), Random = true },
	{ Key = "Gems3500", Id = 0, Name = "3,500 Gems", Description = "BEST VALUE", Icon = "💎", Robux = 999, Category = "Gems", Amount = 3500, Color = rgb(130, 80, 255), Random = true },
	{ Key = "InstantGrow", Id = 0, Name = "Instant Grow", Description = "Selected kaiju grows to its next stage", Icon = "⚡", Robux = 25, Category = "Kaiju", Color = rgb(190, 255, 90) },
	{ Key = "InstantHatch", Id = 0, Name = "Instant Hatch", Description = "Hatch all your eggs right now", Icon = "🥚", Robux = 19, Category = "Kaiju", Color = rgb(255, 225, 120) },
	{ Key = "ShieldNow", Id = 0, Name = "Emergency Shield", Description = "3 minute shield, no cooldown", Icon = "🛡️", Robux = 29, Category = "Boost", Color = rgb(120, 140, 255) },
	{ Key = "Spins3", Id = 0, Name = "3 Spins", Description = "Spin the Kaiju Wheel 3 times", Icon = "🎡", Robux = 79, Category = "Boost", Amount = 3, Color = rgb(255, 176, 32), Random = true },
	{ Key = "ServerLuck", Id = 0, Name = "Server Luck x2", Description = "EVERYONE gets x2 meteor luck for 15 min", Icon = "🍀", Robux = 199, Category = "Server", Color = rgb(120, 255, 140), Random = true },
	{ Key = "MeteorShower", Id = 0, Name = "Meteor Shower", Description = "Start a Meteor Shower for the whole server!", Icon = "🌠", Robux = 299, Category = "Server", Color = rgb(255, 106, 31), Random = true },
	{ Key = "BloodMoon", Id = 0, Name = "Blood Moon", Description = "Summon a Blood Moon: Blood mutations for all!", Icon = "🌕", Robux = 399, Category = "Server", Color = rgb(200, 20, 40), Random = true },
} :: { Product }

Monetization.PassByKey = {} :: { [string]: Pass }
Monetization.PassById = {} :: { [number]: Pass }
for _, p in Monetization.Passes do
	Monetization.PassByKey[p.Key] = p
	if p.Id ~= 0 then
		Monetization.PassById[p.Id] = p
	end
end

Monetization.ProductByKey = {} :: { [string]: Product }
Monetization.ProductById = {} :: { [number]: Product }
for _, p in Monetization.Products do
	Monetization.ProductByKey[p.Key] = p
	if p.Id ~= 0 then
		Monetization.ProductById[p.Id] = p
	end
end

return Monetization
