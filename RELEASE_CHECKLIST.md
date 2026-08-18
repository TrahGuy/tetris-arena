# Block Arena — release checklist

Run this before shipping a build. It is written to be re-used, so it lists what
to check rather than what happened on any one occasion.

Anything marked **(needs 2 clients)** cannot be done from a single Studio
session driven over MCP — it needs Studio's Test tab with a local server and two
players, which is a UI action. Those boxes are the ones most likely to be
skipped, so they are called out.

## Build

- [ ] `git status` clean, on `master`, in sync with `origin/master`
- [ ] Full suite green in **Play mode**, Server datamodel:
      `require(game.ServerScriptService.Services.Tests).run()`
- [ ] Output contains no unexplained errors after a full play session
- [ ] `Tuning.BLITZ_TIME` is 120 and no test tuning survives in the tree
- [ ] No temporary scripts, fake DataStore rows or profiling code committed

## Multiplayer

- [ ] Quick pairs two humans, no bot **(needs 2 clients)**
- [ ] Ranked pairs humans only, never a bot **(needs 2 clients)**
- [ ] Private pairs humans only, no Quick contamination **(needs 2 clients)**
- [ ] Bot fallback appears for Quick alone, after `Tuning.BOT_AFTER`
- [ ] A second match in the same session runs clean, and stale traffic from the
      first cannot touch it **(needs 2 clients)**
- [ ] Ranked disconnect: the leaver takes the loss and the rating hit, the other
      player wins **(needs 2 clients)**
- [ ] Queue cancel leaves no ghost entry in any mode

## Battle dimension

- [ ] Output says `battle dimension: ready` at startup
- [ ] A match moves both players out of the lobby and into an arena
      **(needs 2 clients)**
- [ ] Each player lands on their own pad, facing the middle **(needs 2 clients)**
- [ ] MATCH FOUND → VS → fade plays over the move, and the VS card names the
      opponent's equipped title
- [ ] The result stays readable in the arena, then RETURNING TO LOBBY covers the
      trip back
- [ ] Both players end up where they were standing before the match
      **(needs 2 clients)**
- [ ] Two matches at once get different arenas and cannot see each other
      **(needs 2 clients)**
- [ ] `Workspace.MatchDimensions` is empty once every match has settled
- [ ] A player who disconnects mid-match does not hold an arena open
- [ ] Falling off the platform puts the character back on their pad
- [ ] A respawn during a match returns the character to the arena, not the lobby
- [ ] `ServerStorage.Debug.Arenas` reads `idle` when nothing is running

## Solo

- [ ] Sprint: 40 lines, timer, best time saved, restarting spends the old session
- [ ] Blitz: 120s on the server clock, score from server-derived clears
- [ ] Blitz top-out ends early and keeps the score
- [ ] Blitz quit (F) abandons and records nothing
- [ ] Blitz expiry finalizes from the server with no client involvement

## Input

- [ ] Keyboard: move, DAS, soft drop, hard drop, CW/CCW/180, hold, forfeit
- [ ] Touch: every button, and a finger sliding off a button releases it
- [ ] Touch: FORFEIT and the lobby header sit below the Roblox top bar
- [ ] Gamepad: DPad, hard drop, rotations, hold, forfeit
- [ ] Gamepad: results, rematch, back to lobby and settings are reachable
      without a mouse
- [ ] Character controls restore after every exit: result, KO, forfeit,
      disconnect, Sprint finish, Blitz finish, Blitz top-out, Blitz quit

## Persistence

- [ ] Profile round trip keeps every field through a real save/load
- [ ] Ranked rating and the global index update on a ranked result
- [ ] WORLD RANK reads the global board, falls back to SERVER RANK honestly
- [ ] Skins: ownership and equipped skin persist
- [ ] Secret puzzle completion persists and cannot be undone
- [ ] Titles: ownership persists, equipped persists, retroactive unlocks fire once
- [ ] QUAD MACHINE grants GOLDEN T and ELITE grants DIAMOND I, once each
- [ ] Sprint best (lower is better) and Blitz best (higher is better) persist

## Security

- [ ] Stale `matchId` cannot touch a live match
- [ ] Stale `sessionId` cannot touch a live Blitz run
- [ ] A lock carrying both addresses, or neither, is rejected
- [ ] Malformed payloads on every client-to-server remote produce no errors
- [ ] Forged `score`, `lines`, `combo`, `b2b`, `perfect`, `tspin` are ignored
- [ ] No remote grants a skin, sets a score or completes the puzzle
- [ ] Rate limits do not reject legitimate fast play

## Polish

- [ ] Audio: every cue loads, quad outweighs a clear, music sits under SFX
- [ ] No player-facing string says Tetris or Tetrimino; four lines is a QUAD
- [ ] UI fits at small phone, large phone, 720p, 1080p
- [ ] No element hidden behind the Roblox top bar
- [ ] Colourblind palette still overrides the equipped skin
- [ ] Performance: no per-frame allocation on the board path
