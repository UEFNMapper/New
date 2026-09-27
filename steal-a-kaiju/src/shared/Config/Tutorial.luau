--!strict
-- Missions d'introduction (validées par le serveur). Chaque mission montre une
-- carte d'objectif, guide le joueur vers une cible, et donne une récompense.
--
-- Target : Kaiju (ton premier kaiju) | Collector | Meteor | Siege | RampagePortal | Treasure

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
		Title = "DEFEND YOUR ISLAND!",
		Text = "Wild kaijus are invading your island! Your kaijus shoot them. The BIG one is for you: hit it with your Bonker!",
		Icon = "bonk",
		Target = "Siege",
		Reward = { Gems = 15 },
	},
	{
		Step = 5,
		Title = "RAMPAGE!",
		Text = "Step into the RAMPAGE portal, become your kaiju and smash the toy city! Your kaiju grows while it stomps.",
		Icon = "rampage",
		Target = "RampagePortal",
		Reward = { Gems = 20 },
		UnlockMenus = { "Rampage", "Index", "Rewards" },
	},
	{
		Step = 6,
		Title = "DIG UP A TREASURE",
		Text = "Your buddy kaiju follows you everywhere and sniffs out treasure. Follow the arrows and hold E to dig!",
		Icon = "treasure",
		Target = "Treasure",
		Reward = { Gems = 15 },
	},
} :: { Mission }

Tutorial.Done = #Tutorial.Missions + 1

-- Boutons du HUD toujours visibles (les autres se débloquent mission après mission)
Tutorial.AlwaysVisible = { "Settings", "HowToPlay" }

function Tutorial.Get(step: number): Mission?
	return Tutorial.Missions[step]
end

-- Menus visibles une fois le tutoriel terminé
Tutorial.AfterTutorial = { "Shop", "Upgrades", "Rampage", "Index", "Rewards" }

-- Boutons visibles pour une étape donnée (les menus liés au niveau sont
-- ajoutés par le HUD : voir Levels.MenuLevels).
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
		for _, id in Tutorial.AfterTutorial do
			visible[id] = true
		end
	end
	return visible
end

-- Pages de l'écran « How to play »
Tutorial.HowToPlay = {
	{ Icon = "egg", Title = "HATCH & GROW", Text = "Meteor eggs hatch into kaijus. They grow through 5 stages — Baby, Teen, Adult, Titan, Colossus — and earn more cash (and get stronger) at every stage." },
	{ Icon = "meteor", Title = "METEORS & WORLDS", Text = "Eggs fall in the crater every few seconds. Level up to open new WORLDS through the portals: Candy Coast, Frost Peaks, Volcano Core, Cosmic Rift. Better worlds, rarer eggs!" },
	{ Icon = "bonk", Title = "DEFEND YOUR ISLAND", Text = "Wild kaijus invade your island every few minutes. Your kaijus shoot them. Bonk the ones that sneak through before they grab your cash!" },
	{ Icon = "rampage", Title = "RAMPAGE", Text = "Jump in the RAMPAGE portal to become your kaiju and smash a toy city. Earn stars, cash, and your kaiju grows while it stomps!" },
	{ Icon = "treasure", Title = "YOUR BUDDY", Text = "One of your kaijus follows you as a buddy. It sniffs out treasure, grabs orbs and helps you fight. Pick your buddy in the kaiju panel." },
	{ Icon = "thief", Title = "STEAL & LOCK", Text = "With other players: hold E on their kaijus and run them home! Lock your base with the red button and bonk thieves. Titans and Colossi need TWO thieves." },
	{ Icon = "fusion", Title = "FUSE & EVOLVE", Text = "Fuse two kaijus in the Fusion Lab to find SECRET kaijus. Evolve to restart richer with a permanent cash multiplier and open the best worlds." },
}

return Tutorial
