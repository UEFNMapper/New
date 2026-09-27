local Boot = require("../boot")
local Runtime = Boot.Start()
local roblox = require("@lune/roblox")
local a = Runtime.AddPlayer("A")
local b = Runtime.AddPlayer("B")
Runtime.Advance(3)
local pa = roblox.Vector3.new(0, 5, 0)
b.Character.HumanoidRootPart.CFrame = roblox.CFrame.lookAt(pa + roblox.Vector3.new(0, 0, 4), pa)
a.Character.HumanoidRootPart.CFrame = roblox.CFrame.new(pa)
local n = #Runtime.ClientLog
Boot.Input(b, "Bonk")
Runtime.Advance(0.2)
for i = n + 1, #Runtime.ClientLog do
	local e = Runtime.ClientLog[i]
	print(e.remote, e.args[1])
end
print("errors", #Runtime.Errors)
local ra = a.Character:FindFirstChild("HumanoidRootPart")
local rb = b.Character:FindFirstChild("HumanoidRootPart")
local look = rb.CFrame.LookVector
local offset = ra.Position - rb.Position
local flat = roblox.Vector3.new(offset.X, 0, offset.Z)
print("look", look, "offset", offset, "mag", flat.Magnitude, "dot", flat.Unit:Dot(look))
print("players", #Runtime.Services.Players:GetPlayers())
for _, p in Runtime.Services.Players:GetPlayers() do print(p, p ~= b, rawequal(p, b)) end
