--!strict
--[[
	RateLimiter : seau à jetons (token bucket) par clé (joueur + remote).
	`Rate` jetons/seconde, capacité `Burst`. Horloge injectable pour les tests.
]]

export type Limiter = {
	Allow: (self: Limiter, key: string) -> boolean,
	Forget: (self: Limiter, prefix: string) -> (),
}

type Bucket = { Tokens: number, Updated: number }

local RateLimiter = {}

function RateLimiter.new(rate: number, burst: number, clock: (() -> number)?): Limiter
	local now = clock or os.clock
	local buckets: { [string]: Bucket } = {}

	local limiter = {}

	function limiter.Allow(_self: Limiter, key: string): boolean
		local t = now()
		local bucket = buckets[key]
		if not bucket then
			bucket = { Tokens = burst, Updated = t }
			buckets[key] = bucket
		end
		bucket.Tokens = math.min(burst, bucket.Tokens + (t - bucket.Updated) * rate)
		bucket.Updated = t
		if bucket.Tokens >= 1 then
			bucket.Tokens -= 1
			return true
		end
		return false
	end

	-- Supprime les seaux d'un joueur qui part (évite la fuite mémoire).
	function limiter.Forget(_self: Limiter, prefix: string)
		for key in buckets do
			if string.sub(key, 1, #prefix) == prefix then
				buckets[key] = nil
			end
		end
	end

	return (limiter :: any) :: Limiter
end

return table.freeze(RateLimiter)
