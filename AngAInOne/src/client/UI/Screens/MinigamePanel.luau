--!strict
--[[
	MinigamePanel (version provisoire) : même API que l'hôte des mini-jeux 2D, remplacé
	par la vraie version. Ici, une partie « réussit » automatiquement après 12 s.
]]

local MinigamePanel = {}

local playing = false

function MinigamePanel.Mount(_layer: Frame) end

function MinigamePanel.Play(
	_kind: string,
	_difficulty: number,
	onDone: (success: boolean, score: number, duration: number) -> ()
)
	playing = true
	task.delay(12, function()
		playing = false
		onDone(true, 1, 12)
	end)
end

function MinigamePanel.IsPlaying(): boolean
	return playing
end

function MinigamePanel.Cancel() end

return MinigamePanel
