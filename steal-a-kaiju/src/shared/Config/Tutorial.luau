--!strict
-- Missions d'introduction (validées par le serveur). Chaque mission montre une
-- carte d'objectif, guide le joueur vers une cible, et donne une récompense.
--
-- Target : Kaiju (ton premier kaiju) | Collector | Meteor | LockButton | Thief | OtherPlot

export type Mission = {
	Step: number,
	Title: string,
	Text: string,
	Icon: string, -- clé d'icône (Config/Icons) ou emoji
	Target: string?,
	Reward: { Cash: number?, Gems: number? },
	UnlockMenus: { string }?, -- boutons du HUD débloqués à la fin de la mission
}

local Tutorial = {}

Tutorial.Missions = {
	{
		Step = 1,
		Title = "YOUR FIRST KAIJU",
		Text = "An egg landed on your island. Watch it hatch!",
		Icon = "egg",
		Target = "Kaiju",
		Reward = { Cash = 50 },
	},
	{
		Step = 2,
		Title = "COLLECT YOUR CASH",
		Text = "Your kaiju earns cash every second. Walk onto the green pad of the Cash Reactor to collect it.",
		Icon = "collect",
		Target = "Collector",
		Reward = { Cash = 100 },
	},
	{
		Step = 3,
		Title = "GRAB A METEOR EGG",
		Text = "Meteors drop eggs in the crater in the middle of the map. Follow the arrows and grab one — your first is FREE!",
		Icon = "meteor",
		Target = "Meteor",
		Reward = { Gems = 10 },
		UnlockMenus = { "Shop", "Upgrades" },
	},
	{
		Step = 4,
		Title = "LOCK YOUR BASE",
		Text = "Other players can steal your kaijus! Press the red LOCK button (or the L key) to raise a shield.",
		Icon = "shield",
		Target = "LockButton",
		Reward = { Cash = 150 },
	},
	{
		Step = 5,
		Title = "BONK THE THIEF!",
		Text = "A training thief is coming for your kaiju! Equip your Bonker (hotbar slot 1) and hit him to make him drop it.",
		Icon = "bonk",
		Target = "Thief",
		Reward = { Gems = 15 },
		UnlockMenus = { "Index", "Quests", "Playtime", "Daily", "Spin", "Rebirth", "Fusion" },
	},
	{
		Step = 6,
		Title = "STEAL A KAIJU",
		Text = "Now it's your turn! Go to another island, hold E on a kaiju and run it back home. Big ones need 2 thieves.",
		Icon = "thief",
		Target = "OtherPlot",
		Reward = { Gems = 25 },
	},
} :: { Mission }

Tutorial.Done = #Tutorial.Missions + 1

-- Boutons du HUD toujours visibles (les autres se débloquent mission après mission)
Tutorial.AlwaysVisible = { "Settings", "HowToPlay" }

function Tutorial.Get(step: number): Mission?
	return Tutorial.Missions[step]
end

-- Boutons visibles pour une étape donnée.
function Tutorial.VisibleMenus(step: number): { [string]: boolean }
	local visible: { [string]: boolean } = {}
	for _, id in Tutorial.AlwaysVisible do
		visible[id] = true
	end
	for _, m in Tutorial.Missions do
		if m.Step < step and m.UnlockMenus then
			for _, id in m.UnlockMenus do
				visible[id] = true
			end
		end
	end
	if step >= Tutorial.Done then
		for _, id in { "Shop", "Upgrades", "Index", "Quests", "Playtime", "Daily", "Spin", "Rebirth", "Fusion" } do
			visible[id] = true
		end
	end
	return visible
end

-- Voleur d'entraînement
Tutorial.Thief = {
	WalkSpeed = 9, -- vers le kaiju
	FleeSpeed = 6, -- en repartant avec le kaiju (plus lent : facile à rattraper)
	BonkRange = 12,
	Timeout = 90, -- s : au-delà, le voleur abandonne (le kaiju n'est jamais perdu)
}

-- Pages de l'écran « How to play »
Tutorial.HowToPlay = {
	{ Icon = "egg", Title = "HATCH & GROW", Text = "Meteor eggs hatch into kaijus. They grow through 5 stages — Baby, Teen, Adult, Titan, Colossus — and earn more cash at every stage. Feed them to grow faster." },
	{ Icon = "collect", Title = "COLLECT CASH", Text = "Cash piles up in your Cash Reactor. Walk on the green pad to collect it. Buy more nests, upgrades and eggs with it." },
	{ Icon = "meteor", Title = "METEORS", Text = "Eggs fall in the central crater every few seconds. Rarer eggs have brighter trails — Legendary meteors glow gold. A personal meteor also lands on your island now and then." },
	{ Icon = "thief", Title = "STEAL", Text = "Walk into another island and hold E on a kaiju to grab it. Run it back to your island before its owner bonks you. Titans and Colossi need TWO thieves." },
	{ Icon = "shield", Title = "DEFEND", Text = "Lock your base to raise a shield. Hit thieves with your Bonker to make them drop your kaiju. New players are protected for a while." },
	{ Icon = "fusion", Title = "FUSE & EVOLVE", Text = "Fuse two Adult kaijus in the Fusion Lab to discover SECRET kaijus. Evolve (rebirth) to reset with a permanent cash multiplier." },
}

return Tutorial
