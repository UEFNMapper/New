--!strict
-- Signal minimal (connexions synchrones, protégées par task.spawn).

export type Connection = { Disconnect: (self: Connection) -> (), Connected: boolean }
export type Signal<T...> = {
	Connect: (self: Signal<T...>, fn: (T...) -> ()) -> Connection,
	Once: (self: Signal<T...>, fn: (T...) -> ()) -> Connection,
	Fire: (self: Signal<T...>, T...) -> (),
	Wait: (self: Signal<T...>) -> T...,
}

local Signal = {}
Signal.__index = Signal

function Signal.new<T...>(): Signal<T...>
	local self = setmetatable({ _handlers = {} :: { any } }, Signal)
	return self :: any
end

function Signal:Connect(fn)
	local conn = { Connected = true, _fn = fn }
	local handlers = self._handlers
	function conn.Disconnect(c)
		if not c.Connected then
			return
		end
		c.Connected = false
		local i = table.find(handlers, c)
		if i then
			table.remove(handlers, i)
		end
	end
	table.insert(handlers, conn)
	return conn
end

function Signal:Once(fn)
	local conn
	conn = self:Connect(function(...)
		conn:Disconnect()
		fn(...)
	end)
	return conn
end

function Signal:Fire(...)
	for _, conn: any in table.clone(self._handlers) do
		if conn.Connected then
			task.spawn(conn._fn, ...)
		end
	end
end

function Signal:Wait()
	local thread = coroutine.running()
	self:Once(function(...)
		task.spawn(thread, ...)
	end)
	return coroutine.yield()
end

return Signal
