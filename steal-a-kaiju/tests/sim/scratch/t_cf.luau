local r = require("@lune/roblox")
local V = r.Vector3.new
local cf = r.CFrame.lookAt(V(0,5,4), V(0,5,0))
print("lookAt LookVector", cf.LookVector, "Right", cf.RightVector, "Up", cf.UpVector)
local fwd = V(0,0,-1)
local right = fwd:Cross(V(0,1,0)).Unit
local up = right:Cross(fwd)
local m = r.CFrame.fromMatrix(V(0,5,4), right, up, -fwd)
print("fromMatrix LookVector", m.LookVector, m.RightVector)
print("new(pos, look)", r.CFrame.new(V(0,5,4), V(0,5,0)).LookVector)
print("Angles(0,pi,0) look", r.CFrame.Angles(0, math.pi, 0).LookVector, "identity look", r.CFrame.new().LookVector)
