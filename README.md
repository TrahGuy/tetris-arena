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
| 1 — Neon lobby world | done |
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

## Manual step outstanding

`Lighting.Technology` is not scriptable — it cannot even be read from the plugin
context. Set it to **ShadowMap** by hand in the Properties panel. `Future` looks
marginally better but costs a lot more, and the neon here comes from emissive
material plus Bloom rather than from lighting technology.

## Rebuilding the lobby

```lua
-- Edit mode, command bar:
loadstring(readfile("build/lobby.luau"))()  -- or paste the file contents
```

It destroys and recreates `workspace.Arena`, so it is safe to re-run after edits.
