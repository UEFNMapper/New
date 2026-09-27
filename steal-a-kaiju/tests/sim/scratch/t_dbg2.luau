local Runtime = require("../Runtime")
local Harness = require("../../Harness")
local FakeProfileStore = require("../FakeProfileStore")
FakeProfileStore.Signal = Runtime.Signal
Runtime.Globals.Random = Harness.Random
local S = Runtime.Services
Runtime.Mount("src/shared", S.ReplicatedStorage, "Shared")
local server = Runtime.Mount("src/server", S.ServerScriptService, "Server")
Runtime.Overrides["game.ServerScriptService.Server.Vendor.ProfileStore"] = FakeProfileStore
print("avant RunScript", Runtime.Now())
Runtime.RunScript(server:FindFirstChild("Main"))
print("après RunScript", Runtime.Now())
print("Map ?", S.Workspace:FindFirstChild("Map") ~= nil, "Remotes ?", S.ReplicatedStorage:FindFirstChild("Remotes") ~= nil, "queue", #Runtime.Errors)
local Services = server:FindFirstChild("Services")
print("fin du script de test")
