local Runtime = require("../Runtime")
local S = Runtime.Services
Runtime.Mount("src/shared", S.ReplicatedStorage, "Shared")
local probe = Runtime.Mount("/tmp/claude-0/simt", S.ServerScriptService, "Probe")
Runtime.RunScript(probe:FindFirstChild("Probe"))
print("after run")
