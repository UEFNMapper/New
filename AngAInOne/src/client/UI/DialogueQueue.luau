--!strict
--[[
	DialogueQueue : file d'attente PURE des répliques (sans instance Roblox, testée dans Lune :
	tests/moments.spec.luau). Screens/Dialogue.luau s'occupe de l'affichage.

	Une réplique peut EXPIRER : `expires` secondes après Dialogue.Say, si elle n'a pas encore
	commencé, elle est jetée. Sert aux répliques de fin de monde : elles ne retardent jamais
	l'intro du monde suivant.
]]

local DialogueQueue = {}

export type Line = {
	Text: string,
	Duration: number,
	Speaker: string,
	ExpiresAt: number?, -- heure (os.clock) après laquelle la réplique, pas encore affichée, est jetée
}

function DialogueQueue.Make(text: string, duration: number?, speaker: string?, expires: number?, now: number): Line
	return {
		Text = text,
		Duration = duration or 4,
		Speaker = speaker or "Anga",
		ExpiresAt = if expires and expires > 0 then now + expires else nil,
	}
end

local function expired(line: Line, now: number): boolean
	local deadline = line.ExpiresAt
	return deadline ~= nil and now >= deadline
end

-- Retire les répliques expirées ; renvoie combien ont été jetées.
function DialogueQueue.Prune(queue: { Line }, now: number): number
	local dropped = 0
	for index = #queue, 1, -1 do
		if expired(queue[index], now) then
			table.remove(queue, index)
			dropped += 1
		end
	end
	return dropped
end

-- Prochaine réplique encore valable (les expirées sont jetées au passage).
function DialogueQueue.PopNext(queue: { Line }, now: number): Line?
	while #queue > 0 do
		local line = table.remove(queue, 1) :: Line
		if not expired(line, now) then
			return line
		end
	end
	return nil
end

return DialogueQueue
