-- Sensations de saut (Util/JumpTiming) : coyote time, saut mémorisé, jamais de double saut.
local JumpTiming = Shim.load("src/shared/Util/JumpTiming.luau")

local C, B = JumpTiming.COYOTE, JumpTiming.BUFFER

return {
	["réglages : fenêtres courtes (~0,1 s)"] = function()
		Expect.between(C, 0.08, 0.2)
		Expect.between(B, 0.08, 0.2)
	end,
	["coyote : saut juste après avoir quitté un bord en marchant"] = function()
		local s = JumpTiming.new()
		JumpTiming.OnAirborne(s, 10)
		Expect.equal(JumpTiming.OnRequest(s, 10 + C * 0.8, -3), "Coyote")
	end,
	["coyote : trop tard, l'appui est mémorisé à la place"] = function()
		local s = JumpTiming.new()
		JumpTiming.OnAirborne(s, 10)
		Expect.equal(JumpTiming.OnRequest(s, 10 + C + 0.05, -20), "Buffered")
	end,
	["coyote : un seul par passage en l'air (pas de double saut)"] = function()
		local s = JumpTiming.new()
		JumpTiming.OnAirborne(s, 10)
		Expect.equal(JumpTiming.OnRequest(s, 10.02, 0), "Coyote")
		JumpTiming.OnJumped(s, 10.03) -- le Humanoid passe en Jumping
		JumpTiming.OnAirborne(s, 10.04) -- Jumping -> Freefall : même passage en l'air
		Expect.equal(JumpTiming.OnRequest(s, 10.05, 0), "Buffered", "deuxième appui : pas de second saut")
		-- Même sans que l'état Jumping arrive, le coyote est consommé.
		local t = JumpTiming.new()
		JumpTiming.OnAirborne(t, 5)
		Expect.equal(JumpTiming.OnRequest(t, 5.01, 0), "Coyote")
		Expect.equal(JumpTiming.OnRequest(t, 5.02, 0), "Buffered")
	end,
	["pas de coyote après un vrai saut"] = function()
		local s = JumpTiming.new()
		JumpTiming.OnJumped(s, 10)
		JumpTiming.OnAirborne(s, 10.1) -- Jumping -> Freefall
		Expect.equal(JumpTiming.OnRequest(s, 10.12, 5), "Buffered")
	end,
	["pas de coyote quand on est propulsé vers le haut (trampoline, vent)"] = function()
		local s = JumpTiming.new()
		JumpTiming.OnAirborne(s, 10)
		Expect.equal(JumpTiming.OnRequest(s, 10.02, 60), "Buffered")
	end,
	["au sol : le moteur de Roblox saute tout seul"] = function()
		local s = JumpTiming.new()
		Expect.equal(JumpTiming.OnRequest(s, 1, 0), "None")
		Expect.equal(JumpTiming.OnLanded(s, 1.05), false, "déjà au sol : rien à rejouer")
	end,
	["saut mémorisé : appui juste avant d'atterrir"] = function()
		local s = JumpTiming.new()
		JumpTiming.OnJumped(s, 10)
		JumpTiming.OnRequest(s, 10.6, -30)
		Expect.equal(JumpTiming.OnLanded(s, 10.6 + B * 0.8), true)
		-- Consommé : un deuxième atterrissage ne relance pas de saut.
		JumpTiming.OnJumped(s, 10.8)
		Expect.equal(JumpTiming.OnLanded(s, 10.85), false)
	end,
	["saut mémorisé : appui trop tôt ignoré"] = function()
		local s = JumpTiming.new()
		JumpTiming.OnJumped(s, 10)
		JumpTiming.OnRequest(s, 10.2, 10)
		Expect.equal(JumpTiming.OnLanded(s, 10.2 + B + 0.1), false)
	end,
	["un nouveau passage en l'air redonne droit au coyote"] = function()
		local s = JumpTiming.new()
		JumpTiming.OnAirborne(s, 1)
		Expect.equal(JumpTiming.OnRequest(s, 1.05, 0), "Coyote")
		JumpTiming.OnJumped(s, 1.06)
		Expect.equal(JumpTiming.OnLanded(s, 1.7), false)
		JumpTiming.OnAirborne(s, 3) -- quitte un autre bord
		Expect.equal(JumpTiming.OnRequest(s, 3.1, -2), "Coyote")
	end,
	["appuis répétés d'un seul geste (JumpRequest plusieurs fois) : un seul saut"] = function()
		local s = JumpTiming.new()
		JumpTiming.OnAirborne(s, 0)
		local coyotes = 0
		for i = 0, 5 do
			if JumpTiming.OnRequest(s, 0.01 + i / 60, 0) == "Coyote" then
				coyotes += 1
			end
		end
		Expect.equal(coyotes, 1)
	end,
}
