--!nocheck
-- Remplaçant de ProfileStore pour la simulation : stockage en mémoire,
-- persistant entre deux connexions d'un même joueur (test hors ligne).

local FakeProfileStore = {}
FakeProfileStore.Saved = {} -- clé -> données
FakeProfileStore.Sessions = {}

local function deepCopy(t)
	if type(t) ~= "table" then
		return t
	end
	local c = {}
	for k, v in t do
		c[k] = deepCopy(v)
	end
	return c
end

local function reconcile(target, template)
	for k, v in template do
		if type(k) == "string" then
			if target[k] == nil then
				target[k] = deepCopy(v)
			elseif type(target[k]) == "table" and type(v) == "table" then
				reconcile(target[k], v)
			end
		end
	end
end

function FakeProfileStore.New(name, template)
	local store = { Name = name }
	function store.StartSessionAsync(_, key, _params)
		local Signal = FakeProfileStore.Signal
		local data = deepCopy(FakeProfileStore.Saved[key] or template)
		local profile = { Data = data, Key = key, OnSessionEnd = Signal.new(), active = true }
		function profile.Reconcile(p)
			reconcile(p.Data, template)
		end
		function profile.AddUserId() end
		function profile.IsActive(p)
			return p.active
		end
		function profile.Save(p)
			FakeProfileStore.Saved[key] = deepCopy(p.Data)
		end
		function profile.EndSession(p)
			p.active = false
			FakeProfileStore.Saved[key] = deepCopy(p.Data)
		end
		FakeProfileStore.Sessions[key] = profile
		return profile
	end
	store.Mock = store
	return store
end

return FakeProfileStore
