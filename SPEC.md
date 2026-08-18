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
