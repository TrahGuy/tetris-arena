-- Seeded 7-bag randomiser.
--
-- Deliberately not math.random: the server hands both clients one seed at match
-- start and each generates the identical sequence locally, so the Next queue
-- costs zero network traffic and cannot desync. That only works if the
-- generator is reproducible, which the global RNG is not.
--
-- xorshift32. Cheap, deterministic, and good enough to shuffle seven items.

local Bag = {}
Bag.__index = Bag

local function xorshift(state: number): number
	state = bit32.bxor(state, bit32.lshift(state, 13))
	state = bit32.bxor(state, bit32.rshift(state, 17))
	state = bit32.bxor(state, bit32.lshift(state, 5))
	return state
end

function Bag.new(seed: number)
	-- A zero state is a fixed point for xorshift and would emit nothing but
	-- zeroes forever, so force it off zero.
	local s = bit32.band(math.floor(seed), 0xFFFFFFFF)
	if s == 0 then s = 0x9E3779B9 end
	return setmetatable({ state = s, buf = {} }, Bag)
end

function Bag:_next(n: number): number
	self.state = xorshift(self.state)
	return (self.state % n) + 1
end

function Bag:_refill()
	local bag = { 1, 2, 3, 4, 5, 6, 7 }
	-- Fisher-Yates, so every permutation is reachable.
	for i = 7, 2, -1 do
		local j = self:_next(i)
		bag[i], bag[j] = bag[j], bag[i]
	end
	for i = 1, 7 do
		table.insert(self.buf, bag[i])
	end
end

-- Peek at the upcoming pieces without consuming them.
function Bag:peek(count: number): { number }
	while #self.buf < count do
		self:_refill()
	end
	local out = table.create(count)
	for i = 1, count do
		out[i] = self.buf[i]
	end
	return out
end

function Bag:pop(): number
	if #self.buf == 0 then
		self:_refill()
	end
	return table.remove(self.buf, 1) :: number
end

-- Serialisable snapshot, so a shadow board can be rebuilt mid-match.
function Bag:save(): { state: number, buf: { number } }
	return { state = self.state, buf = table.clone(self.buf) }
end

function Bag.load(snapshot): any
	return setmetatable({ state = snapshot.state, buf = table.clone(snapshot.buf) }, Bag)
end

return Bag
