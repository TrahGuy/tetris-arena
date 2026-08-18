-- The global ranked index: UserId to Elo, plus the cached top of the board.
--
-- This is a DERIVED index, not a second profile. BlockArenaProfiles_v1 stays
-- canonical for everything, rating included; nothing here is ever read back
-- into a player's gameplay rating. If the two disagree the profile is right and
-- the index is stale, which the next ranked result or the player's next join
-- corrects. That direction is deliberate: an OrderedDataStore holds one number
-- per key, so it can rank but it cannot own.
--
-- The backend is injected. In production it is an OrderedDataStore plus
-- UserService; in tests it is a table. That keeps the suite off the network and
-- puts every DataStore call in one place, wrapped, where the failure modes are
-- obvious.

local DataStoreService = game:GetService("DataStoreService")
local UserService = game:GetService("UserService")

local GlobalRank = {}
GlobalRank.__index = GlobalRank

GlobalRank.STORE_NAME = "BlockArenaRankedRating_v1"
GlobalRank.LIMIT = 5             -- the WORLD RANK panel has five rows
GlobalRank.REFRESH_INTERVAL = 60 -- a global board does not need to be fresher
GlobalRank.MIN_GAP = 15          -- floor between fetches when one is requested early
GlobalRank.UNKNOWN = "—"

-- Who belongs on a ranked board: someone who has played a ranked match.
--
-- Pure, and deliberately reading the fields the profile actually has. A new
-- account sits at the default 1000 with no ranked history, and putting that on
-- a ranked leaderboard says something false about it — with enough fresh
-- accounts the whole top five would be players who have never ranked.
--
-- Draws count. A ranked draw moves both ratings without touching rankedWins or
-- rankedLosses, so a player whose only ranked match was a draw still carries a
-- rating that a ranked result produced, and belongs on the board.
function GlobalRank.eligible(profile: any): boolean
	if type(profile) ~= "table" then return false end
	local played = (tonumber(profile.rankedWins) or 0)
		+ (tonumber(profile.rankedLosses) or 0)
		+ (tonumber(profile.rankedDraws) or 0)
	return played > 0
end

function GlobalRank.new(backend: any?)
	return setmetatable({
		backend = backend,
		rows = nil,        -- last GOOD global page; nil until one read succeeds
		fetchedAt = nil,
		requested = false,
		pending = {},      -- userId to rating, waiting to be written
		pendingCount = 0,
		names = {},        -- userId to current identity, in memory only
		status = backend and "waiting" or "unavailable",
		lastError = "",
		reads = 0,
		writes = 0,
	}, GlobalRank)
end

-- ── Writing ───────────────────────────────────────────────────────────────

-- Queued, never written inline.
--
-- This is called from the middle of settling a ranked result, and a DataStore
-- round trip there would sit in front of the Result both players are waiting
-- for. Keyed by user, so a rating that moves twice before the queue drains
-- costs one write rather than two, and writing the same rating twice is
-- harmless by construction.
function GlobalRank:publish(userId: any, rating: any): boolean
	if not self.backend then return false end
	local id, value = tonumber(userId), tonumber(rating)
	if not id or not value then return false end
	if id ~= id or value ~= value then return false end -- NaN
	if id % 1 ~= 0 then return false end
	if self.pending[id] == nil then
		self.pendingCount += 1
	end
	self.pending[id] = math.floor(value)
	return true
end

-- Drains the queue. Yields in production, which is why nothing in a match path
-- calls it. A failed write is dropped rather than retried into a loop: the next
-- ranked result republishes, and so does the player's next join, so the index
-- heals without anything here having to remember that it was broken.
function GlobalRank:flush(): number
	if not self.backend or self.pendingCount == 0 then return 0 end
	local batch = self.pending
	self.pending, self.pendingCount = {}, 0
	local written = 0
	for userId, rating in pairs(batch) do
		self.writes += 1
		local ok, err = self.backend.write(userId, rating)
		if ok then
			written += 1
		else
			self.lastError = tostring(err or "write failed")
		end
	end
	return written
end

-- ── Reading ───────────────────────────────────────────────────────────────

function GlobalRank:request()
	self.requested = true
end

function GlobalRank:shouldFetch(now: number): boolean
	if not self.backend then return false end
	if self.fetchedAt == nil then return true end
	local age = now - self.fetchedAt
	if age >= GlobalRank.REFRESH_INTERVAL then return true end
	return self.requested and age >= GlobalRank.MIN_GAP
end

-- Turns raw index entries into display rows, resolving identities from UserId.
--
-- Names are never stored in the index, only UserId is, so this is where a
-- number becomes a person. A lookup that fails falls back to the last identity
-- this server saw, and only then to a placeholder: one flaky request should not
-- blank the board, and it certainly should not remove anybody from it.
function GlobalRank:_rows(entries: any): { any }
	local clean, ids = {}, {}
	for _, e in ipairs(entries) do
		local id, rating = tonumber(e.userId), tonumber(e.rating)
		-- Anything that is not a user and a number is not a ranking row.
		if id and rating and id % 1 == 0 and id > 0 and rating == rating then
			table.insert(clean, { userId = id, rating = math.floor(rating) })
			table.insert(ids, id)
		end
	end
	if #ids > 0 and self.backend.names then
		local found, err = self.backend.names(ids)
		if type(found) == "table" then
			for id, name in pairs(found) do
				if type(name) == "string" and name ~= "" then
					self.names[id] = name
				end
			end
		else
			self.lastError = tostring(err or "identity lookup failed")
		end
	end
	local out = {}
	for i, e in ipairs(clean) do
		out[i] = {
			rank = i,
			userId = e.userId,
			rating = e.rating,
			name = self.names[e.userId] or GlobalRank.UNKNOWN,
		}
	end
	return out
end

-- A failed read leaves the last good page exactly where it was. An empty board
-- and an unreachable one render identically otherwise, and the second one is a
-- lie told in the same typeface as the truth.
function GlobalRank:refresh(now: number): boolean
	if not self.backend then
		self.status = "unavailable"
		return false
	end
	self.reads += 1
	local top, err = self.backend.top(GlobalRank.LIMIT)
	if type(top) ~= "table" then
		self.status = self.rows and "stale" or "unavailable"
		self.lastError = tostring(err or "read failed")
		return false
	end
	self.rows = self:_rows(top)
	self.fetchedAt = now
	self.requested = false
	self.status = "ok"
	self.lastError = ""
	return true
end

-- The cached page, or nil when there has never been a good one. Callers must
-- read nil as "no global data", never as "nobody is ranked".
function GlobalRank:top(): ({ any }?, string)
	return self.rows, self.status
end

function GlobalRank:age(now: number): number
	if not self.fetchedAt then return -1 end
	return now - self.fetchedAt
end

-- This server already knows the authoritative new rating, so the board it is
-- showing does not have to stay wrong until the next fetch. Cache only — the
-- index itself is written by flush() — and it drops whoever the new ordering
-- pushes past the last row, so a patch can never inflate the page.
function GlobalRank:patch(userId: any, rating: any, name: string?): boolean
	if not self.rows then return false end
	local id, value = tonumber(userId), tonumber(rating)
	if not id or not value or value ~= value or id % 1 ~= 0 then return false end
	if type(name) == "string" and name ~= "" then
		self.names[id] = name
	end
	local rows = {}
	for _, r in ipairs(self.rows) do
		if r.userId ~= id then table.insert(rows, r) end
	end
	table.insert(rows, { userId = id, rating = math.floor(value),
		name = self.names[id] or GlobalRank.UNKNOWN })
	table.sort(rows, function(a, b)
		if a.rating == b.rating then return a.userId < b.userId end
		return a.rating > b.rating
	end)
	while #rows > GlobalRank.LIMIT do table.remove(rows) end
	for i, r in ipairs(rows) do r.rank = i end
	self.rows = rows
	return true
end

-- ── The live backend ──────────────────────────────────────────────────────

-- Every DataStore and identity call in the global path, in one place, each one
-- wrapped. Returns nil when the API is unavailable at all, which is the normal
-- state in Studio without API access: GlobalRank.new(nil) then reports
-- "unavailable" and the tower falls back honestly rather than throwing.
function GlobalRank.liveBackend(storeName: string?): any?
	local ok, store = pcall(function()
		return DataStoreService:GetOrderedDataStore(storeName or GlobalRank.STORE_NAME)
	end)
	if not ok or not store then return nil end

	return {
		write = function(userId: number, rating: number)
			local good, err = pcall(function()
				-- One key per user, set outright: the index holds a rating, not
				-- a history, so the newest authoritative value simply wins.
				store:SetAsync(tostring(userId), rating)
			end)
			return good, err
		end,

		top = function(limit: number)
			local good, result = pcall(function()
				local pages = store:GetSortedAsync(false, limit)
				local out = {}
				for _, entry in ipairs(pages:GetCurrentPage()) do
					table.insert(out, { userId = tonumber(entry.key), rating = entry.value })
				end
				return out
			end)
			if not good then return nil, result end
			return result
		end,

		names = function(ids: { number })
			local good, result = pcall(function()
				return UserService:GetUserInfosByUserIdsAsync(ids)
			end)
			if not good then return nil, result end
			local out = {}
			for _, info in ipairs(result) do
				out[info.Id] = info.DisplayName or info.Username
			end
			return out
		end,
	}
end

return GlobalRank
