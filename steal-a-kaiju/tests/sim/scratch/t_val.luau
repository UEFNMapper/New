local Runtime = require("../Runtime")
local new = Runtime.NewInstance
Runtime.task.spawn(function()
	local f = new("Frame")
	f.TextScaled = true
	f.BackgroundColor3 = nil
	local b = new("Frame")
	local _ = b.Activated
	local t = new("TextButton")
	local _ = t.Activated
	local p = new("Part")
	p:GetBoundingBox()
	local u = new("UIStroke")
	u.ApplyStrokeMode = 1
end)
for _, e in Runtime.Errors do print(e) end
