-- Accepting a placement onto a shadow board.
--
-- This is the middle of what MatchInstance has done since Phase 6 and Phase 11
-- hardened: given a board the server owns and a placement a client reports, is
-- that placement one the player could have made, and if so, put the piece
-- there. It was extracted so a solo Blitz run can be validated by exactly the
-- same code as a ranked match rather than by a second implementation that
-- slowly drifts away from it.
--
-- Deliberately small. It does not lock the piece, count anything, decide who
-- was sent garbage or know what a session is — those differ between a match and
-- a solo run, and pulling them in here would have meant restructuring
-- MatchInstance to suit an abstraction rather than the other way round.
--
-- It DOES mutate the board: a legal hold swap is part of deciding whether the
-- claimed piece is one the player could be holding, and the piece has to end up
-- where the placement says before the caller locks it.

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Pieces = require(Shared.Pieces)

local LockValidation = {}

-- Returns true, or false and the reason to reject on.
function LockValidation.accept(board: any, msg: any): (boolean, string)
	if not board.piece then return false, "no active piece" end

	local kind, rot = tonumber(msg.kind), tonumber(msg.rot)
	local x, y = tonumber(msg.x), tonumber(msg.y)
	if not (kind and rot and x and y) or rot < 1 or rot > 4 then
		return false, "malformed placement"
	end

	-- The claimed piece must be one the player could actually have: the active
	-- one, or a legal hold swap into it.
	if kind ~= board.piece.kind then
		local canSwap = not board.holdUsed
			and (board.hold == kind or (board.hold == nil and board.bag:peek(1)[1] == kind))
		if not canSwap then
			return false, "piece is not the one in play"
		end
		board:swapHold()
	end

	if not board:reachable(kind, rot, x, y) then
		return false, "placement is not reachable"
	end

	-- The shadow is advanced by placements, not by inputs, so it never runs the
	-- rotation that makes a spin a spin. The client sends the rotation it says
	-- it made and it is replayed here against the server's own cells; only a
	-- rotation that genuinely lands on this square, from a square the piece
	-- could have reached, sets the flag. Everything downstream — full or mini,
	-- the line count, back-to-back, the combo, the attack, and in Blitz the
	-- score — is then derived by board:lock() from the server's board. Nothing
	-- about the result comes off the wire. Restricted to T because nothing else
	-- scores a spin, and the check costs a reachability search.
	board.lastKick = kind == Pieces.T and board:verifySpin(kind, rot, x, y, msg.spin) or false

	board.piece.rot, board.piece.x, board.piece.y = rot, x, y
	return true, "ok"
end

-- A shadow board does not run gravity, so it never spawns on its own.
function LockValidation.respawn(board: any)
	if board.alive and not board.piece then
		board.spawnDelay = 0
		board:applyReadyGarbage()
		if board.alive then board:spawn() end
	end
end

return LockValidation
