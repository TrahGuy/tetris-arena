-- Minimal signal. BindableEvents serialise their arguments and lose table
-- identity; this keeps references intact and costs nothing.

local Signal = {}
Signal.__index = Signal

function Signal.new()
	return setmetatable({ _handlers = {} }, Signal)
end

function Signal:Connect(fn: (...any) -> ())
	local handlers = self._handlers
	handlers[fn] = true
	return {
		Disconnect = function()
			handlers[fn] = nil
		end,
	}
end

function Signal:Fire(...)
	-- Snapshot first: a handler is allowed to disconnect itself or others.
	local snapshot = {}
	for fn in pairs(self._handlers) do
		table.insert(snapshot, fn)
	end
	for _, fn in ipairs(snapshot) do
		if self._handlers[fn] then
			local ok, err = pcall(fn, ...)
			if not ok then
				warn("[Signal] handler error: " .. tostring(err))
			end
		end
	end
end

function Signal:DisconnectAll()
	table.clear(self._handlers)
end

return Signal
