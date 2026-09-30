--!strict
--[[
	Audio : musiques et effets sonores.
	Tous les sons viennent des bibliothèques sous licence Roblox (APMOfficial,
	ProSoundEffects) trouvées dans le Creator Store : utilisables dans toute expérience.
	Pour changer un son : remplace l'ID (le numéro) par un autre du Creator Store.
]]

local function id(n: number): string
	return `rbxassetid://{n}`
end

return table.freeze({
	-- Une piste douce par zone (index = zone). Crossfade de 2,5 s au changement de zone.
	Music = table.freeze({
		Hub = id(9045437523), -- "Horizon - Instrumental" (APM)
		[1] = id(9046862941), -- "Sunset Chill (Bed Version)" (APM)
		[2] = id(9046864489), -- "Violet Clouds" (APM)
		[3] = id(9046863579), -- "City Lights" (APM)
		[4] = id(9046865270), -- "Glowing Light (Bed Version)" (APM)
		[5] = id(1839824120), -- "Ambient Electronica" (APM)
		[6] = id(9046527904), -- "Elevation (Instrumental)" (APM)
		[7] = id(9045439830), -- "Luna Glow - Instrumental" (APM)
	}),
	MusicVolume = 0.35,
	CrossfadeSeconds = 2.5,

	Sfx = table.freeze({
		Click = { Id = id(9114650491), Volume = 0.25 }, -- Graphics Beeps 1
		Collect = { Id = id(9116394545), Volume = 0.45 }, -- Soft chiming hits 1
		Upgrade = { Id = id(9126073001), Volume = 0.4 }, -- Synth sparkle bell ding
		PowerOn = { Id = id(9117297453), Volume = 0.6 }, -- Phasey synth power up rise
		Unlock = { Id = id(1839901345), Volume = 0.55 }, -- Powered Up Chimes (APM)
		Zap = { Id = id(9114277757), Volume = 0.45 }, -- Electric Zaps 12
		Whoosh = { Id = id(9114340693), Volume = 0.35 }, -- Sci-fi tonal whoosh
		Error = { Id = id(9119100090), Volume = 0.3 }, -- Robot bleep
		Achievement = { Id = id(1836473467), Volume = 0.55 }, -- Golden Achievement Sting (APM)
		Toast = { Id = id(9116394876), Volume = 0.3 }, -- Soft chiming hits 2
		Voice = { Id = id(9114650491), Volume = 0.12 }, -- "voix" d'Anga dans les dialogues (bip aigu)
	}),
})
