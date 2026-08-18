-- Wire encoding for board snapshots.
--
-- A visible field is 10 x 20 = 200 cells, each 0..8. That fits in four bits, so
-- two cells pack into a byte and the whole board is 100 bytes. Sending it as a
-- Lua array instead would cost roughly 1.6 KB per snapshot per player.
--
-- Everything decoded here may have come from a client, so unpackBoard never
-- reads past the end of the buffer it was handed, and isValidBoard is the one
-- place that decides whether a buffer is a board at all.

local Net = {}

-- 0 is empty, 1..7 are the tetrominoes, 8 is garbage. Four bits hold up to 15,
-- so the top values are unreachable and a buffer containing one did not come
-- out of packBoard.
Net.MAX_CELL = 8

-- One byte per two cells; an odd count still needs the last byte.
function Net.boardBytes(count: number): number
	return math.ceil(count / 2)
end

-- Both nibbles legal, answered by lookup rather than by arithmetic per cell:
-- this runs over every byte of every snapshot the server receives.
local LEGAL_BYTE = table.create(256, false)
for byte = 0, 255 do
	LEGAL_BYTE[byte + 1] = (byte // 16) <= Net.MAX_CELL and (byte % 16) <= Net.MAX_CELL
end

function Net.packBoard(cells: { number }): buffer
	local n = #cells
	local buf = buffer.create(math.ceil(n / 2))
	local i = 1
	local offset = 0
	while i <= n do
		local a = cells[i] or 0
		local b = cells[i + 1] or 0
		buffer.writeu8(buf, offset, a * 16 + b)
		offset += 1
		i += 2
	end
	return buf
end

-- Is this a board of exactly `count` cells, holding only values the game can
-- produce? Nothing reaches another player without passing through here.
function Net.isValidBoard(buf: any, count: number): boolean
	if typeof(buf) ~= "buffer" then return false end
	local bytes = Net.boardBytes(count)
	if buffer.len(buf) ~= bytes then return false end
	for offset = 0, bytes - 1 do
		if not LEGAL_BYTE[buffer.readu8(buf, offset) + 1] then return false end
	end
	return true
end

function Net.unpackBoard(buf: buffer, count: number): { number }
	local out = table.create(count, 0)
	-- A short buffer reads as empty cells rather than erroring. The server
	-- validates before relaying, but a decoder that can be made to throw by the
	-- bytes it is given is a decoder that only works while everyone is honest.
	local have = (typeof(buf) == "buffer") and buffer.len(buf) or 0
	for i = 1, count, 2 do
		local offset = (i - 1) // 2
		local byte = (offset < have) and buffer.readu8(buf, offset) or 0
		out[i] = byte // 16
		if i + 1 <= count then
			out[i + 1] = byte % 16
		end
	end
	return out
end

return Net
