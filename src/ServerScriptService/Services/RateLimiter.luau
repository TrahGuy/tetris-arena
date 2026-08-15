-- Token bucket per player per remote.
--
-- Every remote handler needs one. A client can fire a RemoteEvent in a tight
-- loop, and an unbounded handler is a one-player server crash.

local RateLimiter = {}
RateLimiter.__index = RateLimiter

function RateLimiter.new(rate: number, burst: number)
	return setmetatable({
		rate = rate,   -- tokens per second
		burst = burst, -- bucket size
		buckets = {},
	}, RateLimiter)
end

function RateLimiter:allow(key: any): boolean
	local now = os.clock()
	local b = self.buckets[key]
	if not b then
		b = { tokens = self.burst, at = now }
		self.buckets[key] = b
	end
	b.tokens = math.min(self.burst, b.tokens + (now - b.at) * self.rate)
	b.at = now
	if b.tokens < 1 then
		return false
	end
	b.tokens -= 1
	return true
end

function RateLimiter:forget(key: any)
	self.buckets[key] = nil
end

return RateLimiter
