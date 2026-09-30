--!strict
--[[
	MomentQueue : petite file d'attente PURE des « moments » plein écran (sans instance Roblox,
	testée dans Lune : tests/moments.spec.luau). Moments.luau s'occupe de l'affichage.

	Un seul moment à la fois : bannière « VIRUS ÉLIMINÉS » -> carte de médaille -> en-tête du
	monde suivant, jamais l'un par-dessus l'autre.
	- Push      : ajoute un moment (Unique = remplace un moment du même type encore en attente)
	- Step      : à appeler régulièrement ; termine le moment en cours quand son temps est écoulé
	              et démarre le suivant. Renvoie (démarré?, terminé?)
	- Finish    : le moment en cours de ce type se termine maintenant
	- FinishItem: CE moment se termine maintenant s'il est toujours en cours (fermé d'un toucher…)
	- Expedite  : raccourcit un type de moment (en cours : au plus `minShown` s affiché au total ;
	              en attente : durée plafonnée à `minShown`)
	- Clear     : vide la file et termine le moment en cours (victoire : l'écran final passe devant)
]]

local MomentQueue = {}

export type Item = {
	Kind: string, -- « Cleared », « Medal », « World »…
	Hold: number, -- secondes d'affichage (fondu compris) avant le moment suivant
	Unique: boolean?, -- un seul moment de ce type en attente (le plus récent gagne)
	Data: any, -- libre (fonction d'affichage côté Moments)
}

export type Queue = {
	Pending: { Item },
	Current: Item?,
	StartedAt: number,
	EndsAt: number,
}

function MomentQueue.new(): Queue
	return { Pending = {}, Current = nil, StartedAt = 0, EndsAt = 0 }
end

function MomentQueue.Push(queue: Queue, item: Item)
	if item.Unique then
		for index = #queue.Pending, 1, -1 do
			if queue.Pending[index].Kind == item.Kind then
				table.remove(queue.Pending, index)
			end
		end
	end
	table.insert(queue.Pending, item)
end

-- Termine le moment en cours si son temps est écoulé, puis démarre le suivant.
-- Renvoie le moment démarré (ou nil) et le moment terminé (ou nil).
function MomentQueue.Step(queue: Queue, now: number): (Item?, Item?)
	local finished: Item? = nil
	local current = queue.Current
	if current then
		if now < queue.EndsAt then
			return nil, nil
		end
		finished = current
		queue.Current = nil
	end
	local nextItem = table.remove(queue.Pending, 1)
	if nextItem then
		queue.Current = nextItem
		queue.StartedAt = now
		queue.EndsAt = now + math.max(nextItem.Hold, 0)
	end
	return nextItem, finished
end

-- Le moment en cours de ce type se termine maintenant (le prochain Step passe au suivant).
function MomentQueue.Finish(queue: Queue, kind: string, now: number): boolean
	local current = queue.Current
	if current and current.Kind == kind then
		queue.EndsAt = math.min(queue.EndsAt, now)
		return true
	end
	return false
end

-- Ce moment précis se termine maintenant, s'il est encore celui en cours (un rappel tardif
-- d'un moment déjà remplacé ne coupe jamais le suivant).
function MomentQueue.FinishItem(queue: Queue, item: Item, now: number): boolean
	if queue.Current == item then
		queue.EndsAt = math.min(queue.EndsAt, now)
		return true
	end
	return false
end

-- Raccourcit un type de moment : affiché au plus `minShown` s depuis son début (en cours),
-- durée plafonnée à `minShown` (en attente).
function MomentQueue.Expedite(queue: Queue, kind: string, now: number, minShown: number)
	local current = queue.Current
	if current and current.Kind == kind then
		queue.EndsAt = math.min(queue.EndsAt, math.max(now, queue.StartedAt + minShown))
	end
	for _, item in queue.Pending do
		if item.Kind == kind then
			item.Hold = math.min(item.Hold, minShown)
		end
	end
end

-- Retire les moments en attente d'un type (nil = tous).
function MomentQueue.Drop(queue: Queue, kind: string?)
	for index = #queue.Pending, 1, -1 do
		if kind == nil or queue.Pending[index].Kind == kind then
			table.remove(queue.Pending, index)
		end
	end
end

-- Vide la file et termine le moment en cours.
function MomentQueue.Clear(queue: Queue, now: number)
	MomentQueue.Drop(queue, nil)
	if queue.Current then
		queue.EndsAt = math.min(queue.EndsAt, now)
	end
end

-- Un moment de ce type est-il affiché ou en attente ?
function MomentQueue.Has(queue: Queue, kind: string): boolean
	local current = queue.Current
	if current and current.Kind == kind then
		return true
	end
	for _, item in queue.Pending do
		if item.Kind == kind then
			return true
		end
	end
	return false
end

return MomentQueue
