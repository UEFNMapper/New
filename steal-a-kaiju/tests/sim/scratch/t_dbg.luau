local Runtime = require("../Runtime")
local oldWait = Runtime.task.wait
Runtime.task.wait = function(t)
	print(string.format("[t=%.2f] wait(%s) %s", Runtime.Now(), tostring(t), debug.traceback("", 2):sub(1, 300)))
	return oldWait(t)
end
local Boot = require("../boot")
Boot.Start()
