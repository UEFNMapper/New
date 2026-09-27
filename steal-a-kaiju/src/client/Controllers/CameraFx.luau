--!nonstrict
-- Secousses de caméra et coups de zoom (FOV).

local RunService = game:GetService("RunService")
local Workspace = game:GetService("Workspace")
local TweenService = game:GetService("TweenService")

local CameraFx = {}

local shakes: { { t0: number, d: number, a: number, f: number } } = {}
local baseFov = 70
local fovTween: Tween? = nil

-- intensité en studs, durée en s
function CameraFx.Shake(intensity: number, duration: number?, frequency: number?)
	table.insert(shakes, { t0 = os.clock(), d = duration or 0.4, a = intensity, f = frequency or 22 })
end

-- Secousse selon la distance à une position monde.
function CameraFx.ShakeAt(position: Vector3, intensity: number, radius: number, duration: number?)
	local camera = Workspace.CurrentCamera
	if not camera then
		return
	end
	local d = (camera.CFrame.Position - position).Magnitude
	if d < radius then
		CameraFx.Shake(intensity * (1 - d / radius), duration)
	end
end

function CameraFx.FovPunch(amount: number, duration: number?)
	local camera = Workspace.CurrentCamera
	if not camera then
		return
	end
	if fovTween then
		fovTween:Cancel()
	end
	camera.FieldOfView = baseFov + amount
	fovTween = TweenService:Create(camera, TweenInfo.new(duration or 0.5, Enum.EasingStyle.Back), { FieldOfView = baseFov })
	fovTween:Play()
end

function CameraFx.Init()
	RunService:BindToRenderStep("KaijuCameraShake", Enum.RenderPriority.Camera.Value + 1, function()
		if #shakes == 0 then
			return
		end
		local camera = Workspace.CurrentCamera
		if not camera then
			return
		end
		local now = os.clock()
		local offset = Vector3.zero
		local rot = 0
		for i = #shakes, 1, -1 do
			local s = shakes[i]
			local t = now - s.t0
			if t > s.d then
				table.remove(shakes, i)
			else
				local k = s.a * (1 - t / s.d) ^ 2
				offset += Vector3.new(math.noise(t * s.f, 0.3) * k, math.noise(0.7, t * s.f) * k, 0)
				rot += math.noise(t * s.f, 5.1) * k * 0.02
			end
		end
		camera.CFrame *= CFrame.new(offset) * CFrame.Angles(0, 0, rot)
	end)
end

return CameraFx
