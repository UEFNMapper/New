local Boot = require("../boot")
local Runtime = Boot.Start()
local ClientRuntime = require("../ClientRuntime")
ClientRuntime.Install(Runtime)
local hero = ClientRuntime.StartClient(Runtime, "Hero")
Runtime.Advance(12)
print("ready", hero:GetAttribute("ClientReady"), "errors", #Runtime.Errors)
for i, e in Runtime.Errors do if i <= 5 then print("----", e:sub(1, 900)) end end
