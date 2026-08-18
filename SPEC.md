# Block Arena (file: Tetris Arena.rbxl) — build spec

Terse implementation reference. Full reasoning: https://claude.ai/code/artifact/6f3bb0db-8b3a-454e-9538-a6037fd529c1

Studio instance: **Tetris Battle**. Ship name **BLOCK ARENA** — never render "Tetris" or "Tetrimino" in UI. 4-line clear = **QUAD**.

## Locked decisions

1. `Shared/Board` is PURE Lua — no Instances, no `tick()`, no `Random.new()`. Runs on client (prediction), server (authority), and bot.
2. Server keeps a shadow board per player. Client sends lock events only; server replays to validate reachability. On mismatch: resync, never kick.
3. Server sends one `seed` at match start; both clients run identical xorshift 7-bag locally. Never `math.random`.
4. Mirror all scripts to `D:\KAPE\src\` + `git init`. MCP edits are unversioned.

## Tuning constants (`Shared/Tuning`, mirrored to Instance attributes)

| Key | Value |
|---|---|
| DAS | 133 ms |
| ARR | 0 ms |
| SOFT_DROP | 20G |
| LOCK_DELAY | 500 ms |
| LOCK_RESETS | 15 |
| ARE | 0 ms |
| CLEAR_DELAY | 0 ms (raise in Phase 7) |
| PREVIEW | 5 |
| BOARD_W / BOARD_H | 10 / 40 (20 visible) |
| GARBAGE_DELAY | 500 ms |
| TICK | 1/120 s |
| SUDDEN_DEATH | 150 s |
| MATCH_CAP | 300 s |

## Attack table (`Shared/Attack`)

Single 0 · Double 1 · Triple 2 · Quad 4 · B2B Quad +1 · Perfect clear +10
T-spin single 2 · double 4 · triple 6 · mini single 0 · mini double 1 (indexed by lines, from zero)
Combo (by consecutive clears): `{0,0,1,1,1,2,2,3,3,4,4,4,5}`
Cancel: `incoming -= outgoing`, send remainder. Resolve before transmitting.
Garbage: one gap column per **batch**; ~70% chance to re-roll column on each new batch.

## Piece colors

I `#22E4F5` · O `#FFD84D` · T `#C24DFF` · S `#3DE86B` · Z `#FF3D5E` · J `#4D82FF` · L `#FF9A2B` · garbage `#6E6790`
Second high-contrast palette behind a setting.

## Non-negotiable rules

Full SRS kick tables (JLSTZ + I) · lock-delay reset cap 15 · garbage cancelling · charged garbage queue · one hold per piece · three top-outs (block out / lock out / garbage push-out) · perfect clear check · stall protection. T-spin: 3-corner rule, last action must be a rotation; both front corners = full, one = mini.
Attack **single 2 / double 4 / triple 6**, mini **single 0 / double 1**, paid instead of the base clear.
Enabled in Phase 11; the server derives it from the shadow board via `Board.verifySpin`, never from the client.

## Roblox traps

- **`Escape` is unusable** for forfeit (Roblox menu, can't be sunk). Use `F` + HUD button.
- Bind via `ContextActionService` returning `Sink`, or Space jumps and arrows walk.
- Disable `ControlModule`, not just `WalkSpeed = 0`.
- Fixed timestep accumulator; never frame-tied gravity (fairness bug in 1v1).
- Sync start to `workspace:GetServerTimeNow()`.
- Lock input during countdown; ignore already-held keys at zero.
- Pre-create cell pool at load; no `Instance.new` during play.
- No `UIStroke` per cell — static grid background instead.
- Diff cells against `lastColor` before writing properties.
- Board inside a `CanvasGroup` for flash/shake.
- Absolute cell positioning in a `UIAspectRatioConstraint` (0.5) container, not `UIGridLayout`.
- Set `Lighting.Technology` in Phase 0 (`ShadowMap` + Bloom + Neon, not `Future`).
- Keep modules small — Luau 200-local cap fails silently.
- No Gotham dingbat/arrow glyphs (tofu). Draw rotate icons.
- `ContentProvider:PreloadAsync` behind the countdown.
- Live state on a `Debug` folder as **attributes** (MCP can't read the running game's module tables).

## Persistence

Profiles: `BlockArenaProfiles_v1`, canonical for everything including rating.
Ranked index: `BlockArenaRankedRating_v1` (OrderedDataStore), key `tostring(UserId)`, value integer Elo — **derived only, never read back into a profile**.
Eligibility: `rankedWins + rankedLosses + rankedDraws > 0`. Names resolved at display time from UserId; never stored.
Global top 5 cached, refreshed every 60s (15s floor when a ranked result requests it). Read failure keeps the last good page; no good page falls back to a panel titled SERVER RANK.

## Skins

Catalog: `Shared/SkinData.luau`. Ids are stable and machine-readable; profiles store ids only, never palettes or names.
Profile: `ownedSkins` (set of ids), `equippedSkin` (one id). Default `classic` is always owned and never removable.
Server validates every equip against profile ownership; there is no grant remote — `StatsService.grantSkin` is server-only.
Ownership merges as a UNION on save (no session lock). Equipped is last-write-wins.
Retired ids are dropped from presentation, never migrated; an invalid equipped id falls back to the default.
Colourblind mode overrides skin piece colours. Cosmetics never reach Board, Attack, the bag or the network contract.

## Secret puzzle

Geometry: `workspace.Lobby.Secret`, built by `04_zones.luau`. Board folder carries `Puzzle = "T"`; four Slot parts carry `SlotIndex` 13/14/15/19; four LoosePiece parts carry `PieceIndex` 1..4. Discovered, never duplicated in code.
Reward: `SkinData.SECRET_ID` = `galaxy`, granted through `StatsService.grantSkin`.
Completion: profile field `secretPuzzleSolved`, server-authoritative, **monotonic** (merges with OR), separate from owning the skin.
Interaction: server-owned ProximityPrompts. No puzzle remote exists; the client cannot claim a solve or a grant. Server re-validates distance, match and queue state.
Concurrency: one active solver; released on solve, timeout (45s), disconnect, lost character, match or queue.
`Board.Solved` is temporary world state for the celebration only and always returns to false.

## Blitz

`Tuning.BLITZ_TIME = 120`. Solo score attack, `Enums.Mode.Blitz`, entered from its own Training Zone pad. Never routed through matchmaking; no bot, no garbage, no snapshots.
Score: single/double/triple/quad 100/300/500/800; T-spin 800/1200/1600; mini 200/400; zero-line spins score 0. B2B multiplies the base by 1.5. Combo adds 50x(combo-1) from the second clear. Perfect clear +3500. Each applies once.
Authority: server shadow board, `Shared/LockValidation` shared with MatchInstance, score derived from Board's own ClearInfo. Client-supplied score/lines/combo/b2b/perfect are ignored.
Addressing: solo locks carry `sessionId`, competitive locks carry `matchId`. A payload with both, or neither, is rejected.
Timing: `startAt`/`endAt` on `workspace:GetServerTimeNow()`. The server finalizes on its own clock; late locks score nothing.
Persistence: `bestBlitz` on the profile, merged with MAX. Only a run that expired or topped out may set it; abandoning does not. No Elo, no ranked counters, no global index.

## Network

- Start: seed + opponent name + timestamp, once.
- C→S: `Lock{tick,index,x,y,rot}` on lock only.
- S→opponent: bit-packed board via `buffer` (3 bits/cell = 75 B), ≤10 Hz, `UnreliableRemoteEvent`.
- Token-bucket rate limit on every handler.
- Server owns: bag, garbage amounts, garbage application, KO, result.

## Phase order

0 Studio/folders/lighting (mostly done) → 1 Neon lobby → 2 Lobby GUI+Theme → **2.5 Shared foundations** → 3 Solo Tetris → 4 Hold/Next/ghost/HUD → **4.5 Bot + practice modes** → 5 Queue/match flow → 6 1v1 garbage/KO → **6.5 Authority hardening** → 7 Juice/audio → **8 Persistence/settings/stats** → 9 Mobile/gamepad

Solo game before the queue: the sim is the risk, matchmaking is glue.

## Module layout

```
ReplicatedStorage/Shared    Theme Tuning Pieces SRS Board Bag Attack Remotes Net Enums Signal
ServerScriptService/Services MatchmakingService MatchService MatchInstance ShadowBoard
                             BotService RateLimiter StatsService
StarterPlayerScripts/Client  InputController Sim BoardRenderer HudController MatchClient Fx Sound
```

## Bot (Phase 4.5, not optional)

Queue >20 s with no human → bot match, clearly labelled. Heuristic evaluator over all placements of current + held piece: aggregate height, holes, bumpiness, lines cleared, well depth. Difficulty = think delay + move speed + error rate, **never** a worse evaluator. Tiers: Rookie / Neon / Overdrive. Doubles as a headless soak harness.

## Tests

Headless `TestRunner` over pure `Board`: clears, garbage insertion, every SRS kick case (T-spin triple kick), all three top-outs. Desync test (same seed + inputs → identical boards). Bot-vs-bot soak, 100 matches, assert none fail to end. Then Start Server + 2 Players.

## Leaver rules

Opponent disconnects → win, "opponent left" (not KO). Queue disconnect → drop. Queue while in match → reject. Rematch offer expires if either leaves results. `MATCH_CAP` reached → most garbage sent wins.
