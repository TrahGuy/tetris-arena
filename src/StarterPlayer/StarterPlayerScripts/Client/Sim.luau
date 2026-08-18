-- Fixed-timestep driver around a Board.
--
-- Gravity must never be tied to frames. A 240 Hz monitor and a 30 fps laptop
-- have to play the identical game or the 1v1 is unfair, so real time is
-- accumulated and the board is stepped in whole TICKs regardless of framerate.
--
-- Inputs are buffered rather than applied immediately: a hard drop pressed
-- between two ticks would otherwise be dropped on the floor.

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Shared = ReplicatedStorage:WaitForChild("Shared")
local Board = require(Shared.Board)
local Tuning = require(Shared.Tuning)

local Sim = {}
Sim.__index = Sim

-- Above this many steps in one frame the client has stalled (alt-tab, a hitch);
-- catching all the way up would fast-forward the board through the player's
-- stack. Better to drop the backlog.
local MAX_CATCHUP = 10

function Sim.new(seed: number, opts: any?)
	return setmetatable({
		board = Board.new(seed, opts),
		acc = 0,
		tick = 0,
		pending = {},
		lockIndex = 0,
		onLock = nil, -- (payload) -> ()
		onEvent = nil, -- (event) -> ()
	}, Sim)
end

function Sim:push(action: string, arg: any?)
	table.insert(self.pending, { action, arg })
end

function Sim:setSoftDrop(on: boolean)
	self.board.softDropping = on
end

function Sim:_apply()
	local b = self.board
	for _, cmd in ipairs(self.pending) do
		local a = cmd[1]
		if a == "left" then
			b:move(-1)
		elseif a == "right" then
			b:move(1)
		elseif a == "cw" then
			b:rotate(1)
		elseif a == "ccw" then
			b:rotate(-1)
		elseif a == "flip" then
			b:rotate(1)
			b:rotate(1)
		elseif a == "hold" then
			b:swapHold()
		elseif a == "hardDrop" then
			b:hardDrop()
		elseif a == "softStep" then
			b:stepDown()
		end
	end
	table.clear(self.pending)
end

function Sim:update(dt: number)
	local b = self.board
	if not b.alive then return end

	self.acc += dt
	local steps = 0
	while self.acc >= Tuning.TICK and steps < MAX_CATCHUP do
		self.acc -= Tuning.TICK
		steps += 1

		self:_apply()
		b:step(Tuning.TICK)
		self.tick += 1

		for _, e in ipairs(b:drain()) do
			if e.kind == "lock" then
				self.lockIndex += 1
				-- The board reports exactly where the piece came to rest, so
				-- this never has to be reconstructed from the step before.
				local place = e.data.placed
				if self.onLock and place then
					self.onLock({
						index = self.lockIndex,
						tick = self.tick,
						kind = place.kind,
						rot = place.rot,
						x = place.x,
						y = place.y,
						-- The rotation that placed it, for the server to replay.
						-- `info` and `send` are this client's own reading and go
						-- no further than the local HUD and FX.
						spin = place.spin,
						info = e.data.info,
						send = e.data.send,
					})
				end
			end
			if self.onEvent then self.onEvent(e) end
		end
	end
	if steps >= MAX_CATCHUP then
		self.acc = 0
	end
end

function Sim:alive(): boolean
	return self.board.alive
end

return Sim
