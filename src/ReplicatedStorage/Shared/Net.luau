-- Wire encoding for board snapshots.
--
-- A visible field is 10 x 20 = 200 cells, each 0..8. That fits in four bits, so
-- two cells pack into a byte and the whole board is 100 bytes. Sending it as a
-- Lua array instead would cost roughly 1.6 KB per snapshot per player.

local Net = {}

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

function Net.unpackBoard(buf: buffer, count: number): { number }
	local out = table.create(count, 0)
	for i = 1, count, 2 do
		local byte = buffer.readu8(buf, (i - 1) // 2)
		out[i] = byte // 16
		if i + 1 <= count then
			out[i + 1] = byte % 16
		end
	end
	return out
end

return Net
