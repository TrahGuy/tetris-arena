# Block Arena

1v1 battle Tetris for Roblox. Neon arcade. Studio working title *Tetris Arena*;
everything shipped to players says **BLOCK ARENA**.

- **[SPEC.md](SPEC.md)** — locked decisions, tuning constants, attack table, phase order.
- **`build/`** — Luau world builders. Run in Edit mode via the command bar or MCP
  `execute_luau`. They are idempotent and are the source of truth for scenery;
  the `.rbxl` is just their output.
- **`src/`** — mirror of every script in the DataModel, laid out by service.

The place file is `D:\KAPE\Tetris Arena.rbxl` (one level up, since Studio has it
open at that path). Move it in here when convenient.

## Status

| Phase | State |
| --- | --- |
| 0 — Studio place, lighting, folder scaffold | done |
| 1 — Lobby world (300x300, 8 zones) | done |
| 2 — Lobby GUI | next |
| 2.5 — Shared foundations (Tuning, Pieces, SRS, Board, Bag, Attack) | |
| 3 — Solo Tetris | |
| 4 — Hold / Next / ghost / HUD | |
| 4.5 — Bot opponent + practice modes | |
| 5 — Queue and match flow | |
| 6 — 1v1 garbage, opponent board, KO | |
| 6.5 — Authority hardening | |
| 7 — Juice, audio, polish | |
| 8 — Persistence, settings, stats | |

## Lobby layout

300 × 300 studs, deck top at y = 0. Cyan owns −X, magenta owns +X.

| Zone | Centre | Size | Accent |
| --- | --- | --- | --- |
| Tetris Core (spawn) | (0, 20) | 60 × 60 | violet |
| Matchmaking | (0, −40) | 120 × 50 | orange |
| Block Battle Portal | (0, −122) | 150 wide facade | cyan / magenta |
| Block Museum | (−95, −20) | 50 × 50 | purple |
| Leaderboard Tower | (95, −10) | 40 × 80, 95 tall | gold |
| Training Zone | (−75, 95) | 80 × 80 | cyan |
| Block Lounge | (75, 95) | 60 × 60 | magenta |
| Secret nook | (130, −132) | hidden, unlit | violet |

Run the builders in order: `00_ground` → `01_core` → `02_portal` → `03_stations`
→ `04_zones`. `00_ground` destroys and recreates `workspace.Lobby`, so a full
rebuild means running all five; the others only touch their own folders.

## What is built but not yet wired

The lobby is physically complete. These are geometry plus attributes, waiting on
the phase that owns the logic — none of them need the world to change again.

| Thing | Hook | Owed by |
| --- | --- | --- |
| PLAY / RANKED / CREATE ROOM pads | `PadMode` attribute on each `Pad_*` part | Phase 5 |
| Practice pad | `PadMode = "practice"` | Phase 4.5 |
| Leaderboard rows | `PANELS` table in `03_stations.luau` | Phase 8 |
| Museum exhibits | display only | whenever skins exist |
| Emote pad / idle rewards | `PadMode = "emote"` | Phase 7 |
| Secret puzzle | `Board` folder attrs `Puzzle`, `Solved`; `SlotIndex` / `PieceIndex` | later |

Walking through the open portal currently leads to a small empty alcove. Phase 5
turns that into the match hand-off.

## Client FX

`src/…/Client/LobbyFX.client.lua` drives every moving thing in the lobby: the
orbiting tetrominoes, the museum exhibits, the bot's head, the station rings, the
ambient falling blocks, the spawn burst, the training board, and the portal door.

It is a LocalScript on purpose. Every part it touches is anchored, so local
CFrame writes never replicate — the whole lobby animates at zero server cost. Do
not move this to the server.

## Manual step outstanding

`Lighting.Technology` is not scriptable — it cannot even be read from the plugin
context. Set it to **ShadowMap** by hand in the Properties panel. `Future` looks
marginally better but costs a lot more, and the neon here comes from emissive
material plus Bloom rather than from lighting technology.
