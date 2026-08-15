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
| 2 — Lobby GUI | done — reinterpreted, see below |
| 2.5 — Shared foundations | done, 158 headless tests |
| 3 — Solo Tetris | done |
| 4 — Hold / Next / ghost / HUD | done |
| 4.5 — Bot opponent | done — practice is one generic board, not Sprint/Blitz |
| 5 — Queue and match flow | done |
| 6 — 1v1 garbage, opponent board, KO | done |
| 6.5 — Authority hardening | done |
| 7 — Juice | done — **no audio: no asset ids** |
| 8 — Persistence, settings, stats | done |
| 9 — Mobile touch / gamepad | not started (always was later) |

**Phase 2 was reinterpreted.** It was written before the lobby had physical
matchmaking pads. A fullscreen PLAY menu on top of them would be two front doors
to the same room, so `LobbyUi` covers what the world cannot show — searching,
results, settings, help — and starting a match belongs to the pads.

## Known gaps

| Gap | Why |
| --- | --- |
| **No audio at all** | `Sound.luau` has the mixer, volume settings, preloading and every cue call wired. It has no asset ids, because inventing them yields either a silent 404 or somebody else's sound in your game. Upload audio, paste ids into `IDS`, done. |
| Practice is one mode | The pad gives a solo board. Sprint (40 lines) and Blitz (2 min) are not separate modes with their own goal and timer. |
| CREATE ROOM falls through to quick play | A private match needs a friend-invite flow that does not exist. `MatchmakingService.enqueue` says so in a comment rather than silently misbehaving. |
| RANKED queues like quick play | There is no rating system to rank against yet. |
| T-spins score zero | Detected and shown; `Attack.TSPIN_ENABLED` is false on purpose until the base game is proven. |
| Museum skins are display-only | No cosmetic ownership system. |
| Secret puzzle has no solve logic | Geometry and attributes are in place; nothing reads them. |
| Never tested with two humans | Studio-over-MCP can only drive one client. Tested extensively against the bot. |

## Lobby layout

300 × 300 studs. Vertical datum:

| y | |
| --- | --- |
| −4.5 | sunken plaza floor |
| 0 | main concourse |
| 1.5 | zone platform tops |
| 16 → 86 | glazing |
| 94 | beam soffit (portal tops out at 84, leaderboard crown at 93) |
| 102 | ceiling slab underside |

| Zone | Centre | Size | Accent |
| --- | --- | --- | --- |
| Tetris Core (spawn) | (0, 20) | 92 × 92 sunken plaza | violet |
| Matchmaking | (0, −40) | 120 × 50 | orange |
| Block Battle Portal | (0, −122) | 150 wide facade | cyan / magenta |
| Block Museum | (−95, −20) | 50 × 50 | purple |
| Leaderboard Tower | (95, −10) | 40 × 80, 95 tall | gold |
| Training Zone | (−75, 95) | 80 × 80 | cyan |
| Block Lounge | (75, 95) | 60 × 60 | magenta |
| Secret nook | (130, −132) | hidden, unlit | violet |

Run in order: `lighting` → `00_shell` → `01_core` → `02_portal` → `03_stations`
→ `04_zones` → `05_lighting_rig` → `06_finish`. `00_shell` destroys and
recreates `workspace.Lobby`, so a full rebuild means running the lot. Each
builder is idempotent and only clears what it owns.

Two files are cross-cutting on purpose:

- **`05_lighting_rig`** owns every light in the hall. It deletes the lamps
  01–04 drop as they build and rebuilds from one plan, so the room has a
  scheme instead of forty unrelated point lights.
- **`06_finish`** owns the material language — the de-neon rule, signage and
  props. Art direction lives in one file rather than smeared across five.

### Running them without pasting them

`execute_luau` has `loadstring`, and Studio can `GetAsync` from localhost, so the
on-disk copies can be run directly — which also proves the files are the real
build rather than a paraphrase of it.

```powershell
Start-Process python -ArgumentList '-m','http.server','8731','--bind','127.0.0.1' `
  -WorkingDirectory 'D:\KAPE\Tetris Arena\build' -WindowStyle Hidden
```

```lua
local Http = game:GetService("HttpService")
Http.HttpEnabled = true                       -- persisted place setting; turn it back off
for _, n in ipairs({ "lighting", "lobby/00_shell", "lobby/01_core", "lobby/02_portal",
    "lobby/03_stations", "lobby/04_zones", "lobby/05_lighting_rig", "lobby/06_finish" }) do
    assert(loadstring(Http:GetAsync("http://127.0.0.1:8731/" .. n .. ".luau"), n))()
end
Http.HttpEnabled = false
```

## Art direction

The lobby is an **interior**, not a plain. Dark concrete and brushed metal, lit
by its own ceiling, with the city visible through full-height glazing. The
tetromino motif appears as structure and sculpture; it is not painted on in
light.

Three rules, learned the expensive way:

1. **Neon is signage, never outline.** A glow strip around every object is a
   wireframe, not a place. `06_finish` enforces this: emissive is reserved for
   the marquee, piece cells, station faces, ceiling lenses, city windows and
   cove strips. Everything else that was Neon becomes brushed metal, which still
   catches light and reads as trim.
2. **Bloom is what makes a scene look "neon".** At intensity 0.95 / threshold
   0.92 every mildly bright surface bleeds and the whole image flattens into
   haze. It now sits at 0.38 / 1.05, so only genuinely emissive signage blooms.
3. **Neon lights nothing.** It only glows. Illumination has to come from actual
   lights, which is why the ceiling coffers exist — and why the first version
   was simultaneously very bright and completely unlit.

The failure mode in both directions is real. Too dark (ambient 10/6/20, no
fixtures) and a 300 × 300 hall is a void. Too bright (ambient 46/46/50, 18
overlapping 150-stud lights) and it flattens into a pale office lobby with no
contrast for the accents to work against. The hall wants dark surfaces with
pools of light: ambient 26/26/31, coffer lights at 112 range and 0.8 brightness.

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

## Lighting.Technology

Not scriptable — it cannot even be *read* from the plugin context, so nothing in
`build/` touches it. Check it by hand if you like (Explorer → Lighting →
Properties, filter for `Technology`), but it is almost certainly already right:
**ShadowMap is Studio's default** and this place came from the Baseplate
template.

It also barely matters here. Future's advantage over ShadowMap is per-pixel
shadows from local lights, and every light in `05_lighting_rig` sets
`Shadows = false` deliberately — 63 shadow-casting lights would be very
expensive for no gain, since the look comes from emissive material and Bloom.
Future would cost a lot and change almost nothing.
