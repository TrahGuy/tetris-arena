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
| 4.5 — Bot opponent + practice | done — practice is a 40-line Sprint |
| 5 — Queue and match flow | done — quick / ranked / private are three real queues |
| 6 — 1v1 garbage, opponent board, KO | done |
| 6.5 — Authority hardening | done |
| 7 — Juice and audio | done |
| 8 — Persistence, settings, stats, Elo | done |
| 9 — Mobile touch / gamepad | done |
| 10 — Competitive hardening | done |
| 11 — T-spin scoring and attack | done |
| 12 — Global ranked leaderboard | done |
| 13 — Skin ownership and equip | done |
| 14 — Secret puzzle and reward | done |
| 15 — Blitz mode | done |

**Phase 2 was reinterpreted.** It was written before the lobby had physical
matchmaking pads. A fullscreen PLAY menu on top of them would be two front doors
to the same room, so `LobbyUi` covers what the world cannot show — searching,
results, settings, help — and starting a match belongs to the pads.

## Audio

Every id in `Sound.luau` comes from a source Roblox licenses for use in
experiences — **ProSoundEffects** (its official free SFX library) and
**DistrokidOfficial** (its licensed music partner) — and each was loaded and
checked for a real duration before being wired in. Most of what a free audio
search returns is ripped from other games; several results say so in their own
descriptions. None of that is here.

They are general-purpose effects, not sounds authored for a block game, so each
cue carries its own volume and pitch: the same one-second beep is a piece-move
tick at 2.7x speed and 16% volume. Nothing was auditioned — they were chosen by
description — so swap any that sound wrong. One line each.

## Known gaps

| Gap | Why |
| --- | --- |
| No global Blitz board | The best score is saved per account and the tower shows the best in this server. A world ranking would need a second OrderedDataStore; ranked Elo has one, Blitz does not. |
| A forged spin witness buys a placement the player could have spun into | The server verifies the rotation is legal and lands where it says, not that it happened. A patched client can claim a spin for a T it dropped into the same slot — a position it would have had to build anyway — and doing so desyncs its own board against the shadow, which resyncs it. Closing the gap entirely means replaying inputs, not placements. |
| Only one skin can be earned | The secret nook pays out GALAXY CUBE. GOLDEN T and DIAMOND I still have no source; they wait on the same server-only grant an achievement or a purchase would use. No monetisation is implemented. |
| WIN STREAK and TOP SCORES are server-local | Only WORLD RANK is global. Both panels say so in their titles. Globalising them would mean an ordered index per statistic, which is a lot of write budget for a sign. |
| Practice results are bounded, not replayed | The server times the session and rejects anything inconsistent with it, but it does not simulate the run. Proving a sprint outright means replaying the client's inputs against a server board. |
| Never tested with two live humans | Studio over MCP drives one client. `Tests.twoPlayer` covers the path headlessly: two stand-in clients run their own boards and report locks exactly as `Main.client` does, with garbage and resync mirrored back the way the remotes deliver them. |

## Competitive integrity

Four things the server used to take on trust, and no longer does.

**Every competitive message names its match.** `MatchUpdate`, `Lock`, `Garbage`,
`Resync`, `Snapshot`, `Result` and `Forfeit` all carry a `matchId`, and both
ends drop anything addressed elsewhere. Matches run back to back — rematch,
requeue — and a message still in flight from the last one used to land on the
next: at best a spurious resync, at worst a stale `topout` or forfeit throwing
away a game that had barely started.

**Opponent boards come from the shadow, never from the client that owns them.**
`MatchInstance:_publishSnapshots` packs both sides at `SNAPSHOT_HZ`. It costs no
freshness — cells only move when a piece locks or garbage lands, and the shadow
does both at the same moments — and it means nobody can draw what they like on
their opponent's screen, send a malformed buffer that errors the receiver's
decoder, or hide their stack by simply not sending. The client's own snapshot is
still sent, but only as the divergence probe that triggers a resync, and it is
checked by `Net.isValidBoard` before anything is done with it.

**Leaving a ranked match costs rating.** It always said so; the code did the
opposite. `playerLeft` cleared the side's Player before the result was recorded,
so by the time `recordMatch` looked for the profile that owed the loss there was
nobody there — no loss, no streak reset, no Elo. The reference now survives the
disconnect and a `left` flag stops anything being fired at a client that has
gone. Rating is settled before the result goes out, so the card shows what the
match did to it.

**Practice results are vetted against the clock the server measured.**
`PracticeService` issues a session with the seed and times the run itself.
A submitted result has to be consistent with that window and with limits the
game defines — `MAX_PPS`, four rows per piece, ten cells per row, `SPRINT_GOAL`.
A hand-written remote call claiming a billion lines in a millisecond credits
what the elapsed seconds allow and sets no record. Short of replaying inputs
server-side, a cheater can still claim any run they could have played; they can
no longer claim one they could not have.

## T-spins

**The rule.** The piece is a T, the last successful action was a rotation, and
three of the four corners of its 3x3 box are solid — walls and the floor count,
open air above the buffer does not. Both corners on the side the T points at
makes it *full*; one makes it a *mini*. That is the standard 3-corner rule and
it is unchanged from the detector Phase 4 shipped; what Phase 11 changed is who
gets to decide it.

**Attack**, paid instead of the base clear, never on top of it:

| | 1 line | 2 lines | 3 lines |
| --- | --- | --- | --- |
| full | 2 | 4 | 6 |
| mini | 0 | 1 | — |

Back-to-back adds 1 and any spin that clears keeps the chain alive, so quad into
spin and spin into quad both hold it. Combo and perfect clear apply exactly as
they do to any other clear. A spin that clears nothing is worth nothing, does
not touch the chain, and is not counted in `stats.tspins` — but it is still
named on the banner, because a player who has just wedged a T into a slot and
got silence cannot tell whether the game saw it.

**How the server knows.** The shadow board is advanced by reported placements,
never by inputs, so it never runs the rotation that makes a spin a spin — its
`lastKick` was false for every lock a human ever sent, and it would have scored
every T-spin as an ordinary clear while the client scored it as a spin. Since
`Board:lock` cancels incoming garbage with that number, the two boards would
have taken different garbage and desynced.

So the lock carries a **witness**: the square the piece turned from and which
way. `Board.verifySpin` replays that rotation on the server's own cells — the
piece must have fitted where the client says it stood, that square must be one
`reachable()` can get to, and the SRS kick table applied from there must land
exactly on the reported placement. A witness that passes sets the same flag the
player's own rotation would have set, and detection proceeds from the server's
board as usual. Nothing else about the spin comes off the wire; `send` and
`lines` were removed from the lock payload entirely.

## Global ranked leaderboard

**WORLD RANK is global.** A ranked result in any server moves both ratings, each
one is written to an ordered index, and every other server's tower reads that
index — the player does not have to be present, or online, to be on it.

| | |
| --- | --- |
| Canonical profile | `BlockArenaProfiles_v1` — rating included |
| Ranking index | `BlockArenaRankedRating_v1`, an OrderedDataStore |
| Key | `tostring(UserId)` |
| Value | integer Elo, nothing else |
| Refresh | 60s, or 15s when a ranked result asks for one |
| Rows | top 5, matching the panel |

The index is **derived, never canonical**. Nothing reads a rating out of it into
a player's profile; an OrderedDataStore holds one number per key, so it can rank
but it cannot own. If the two disagree the profile is right and the index is
stale, which the player's next join or next ranked result corrects — `load`
republishes what the profile says every time, so drift heals on its own.

**Who is on it.** Only accounts with ranked history: `rankedWins + rankedLosses
+ rankedDraws > 0`. A fresh account sits at the default 1000, and a ranked board
full of players who have never ranked would be a board about nothing. Draws
count, because a ranked draw moves both ratings — Phase 12 added `rankedDraws`
to the profile for exactly this, since Phase 10 moved the ratings without
recording that the match happened.

**Names are not stored.** The index holds UserId and a number. Identities are
resolved at display time through `UserService:GetUserInfosByUserIdsAsync`, so a
renamed player shows their current name, no user-authored text is ever written
into leaderboard storage, and there is no second name database to moderate. A
failed lookup falls back to the last identity this server saw, then to a dash —
never to dropping the row.

**Nothing waits on it.** Rating writes are queued and drained by one background
task; a match never blocks on a DataStore. Reads happen on their own clock, and
`refreshLeaderboard` — which runs on every join, departure and result — only
renders the cache. A failed read keeps the last good page rather than blanking
the board. A failed write is dropped, because the next result or join will
republish it anyway.

**The fallback does not lie.** With no good global page — API access off, the
index unreachable, or nobody ranked yet — the panel shows this server's players
under the title **SERVER RANK**. Server-local rows under the words WORLD RANK
would be the kind of wrong nobody ever catches, because it looks exactly like
the truth. `ServerStorage.Debug` carries `GlobalRankStatus`, `GlobalRankRows`,
`GlobalRankAge` and `GlobalRankLastError` for checking which state a live server
is in.

**Eventual consistency.** A server patches its own cached page from a ranked
result it just settled, so the player who takes first place sees it immediately;
other servers see it within a refresh. The profile store deliberately has no
session locking, so one account playing on two servers at once can still write
the index twice — last writer wins, and the next join corrects it.

## Skins

Four board skins, defined once in `Shared/SkinData.luau`. The three unlockable
ones are the museum's existing exhibits rather than inventions — the lobby has
displayed GOLDEN T, DIAMOND I and GALAXY CUBE under glass since Phase 1 with
nothing behind them.

| id | name | owned | look |
| --- | --- | --- | --- |
| `classic` | CLASSIC | always | the shipping palette, unchanged |
| `golden` | GOLDEN T | granted | warm metals on a bronze field |
| `diamond` | DIAMOND I | granted | cut glass, cold light |
| `galaxy` | GALAXY CUBE | granted | jewel tones on void |

**Ids are stable, names are not.** A profile stores `ownedSkins` as a set of ids
and `equippedSkin` as one id — never a palette, never a display name. Names get
rewritten; entitlement stored in a label somebody is going to edit is
entitlement waiting to be lost.

**The server owns all of it.** The client may send `EquipSkin { skinId }`, which
is a request: the server checks the skin exists, that the profile owns it, that
the player is not mid-match, and that it is not already equipped before anything
is written. There is no remote anywhere near granting — unlocks go through
`StatsService.grantSkin(player, skinId)`, which is server-only and is the seam
every future source of skins plugs into. A patched client can paint its own
board any colour it likes; what it cannot do is make the server persist a skin
it does not own.

**Old profiles migrate on load and cannot be broken by the catalog changing.**
The default is always owned, the equipped skin is always one the player owns,
and ids that have left the catalog are quietly dropped from what is presented
without being erased from the store. Retiring a cosmetic needs no migration
script. On save, ownership is a **union** rather than last-write-wins: with no
session lock two servers can hold one profile, and a grant made on one must not
be taken back by the other saving afterward with an older view.

**Accessibility wins.** Colourblind mode overrides skin piece colours outright
rather than asking each skin for its own accessible variant — a cosmetic must
never be able to switch accessibility off, and a per-skin high-contrast palette
is a per-skin chance to get one wrong. The board, empty cells and ghost still
follow the skin, so an equipped skin is still visibly equipped. The suite also
checks every palette keeps the seven pieces far enough apart to tell at speed;
it caught the first draft of DIAMOND I, where I and S were both pale and cool.

**Cosmetics never touch the simulation.** `Board` takes no skin argument and
there is nowhere to pass one. Cyan-for-yours and magenta-for-theirs stays fixed
whatever is equipped, because which board is which is readability rather than
decoration — and your screen renders both boards with *your* skin, so nobody's
cosmetic state rides on the competitive wire.

**The museum is the interface.** `MuseumService` tags each existing exhibit with
its skin and drops an invisible interaction pad in front of it, so the lobby's
existing dwell-to-activate pattern picks them up like any other station — which
is positional, so it works on keyboard, gamepad and touch without a mouse. The
prompt reads LOCKED, OWNED or EQUIPPED. Standing on an owned exhibit equips it.

For testing, a Studio-only grant path sits on a ServerStorage attribute, which
no client can write or even see:

```lua
game.ServerStorage.Debug:SetAttribute("GrantSkin", "12345678:golden")
```

## The secret nook

There is an unfinished 5x5 board in the far corner of the lobby with a T-shaped
hole in it and four loose blocks on the floor. It has been there since Phase 1.
Filling the hole unlocks **GALAXY CUBE** — the exhibit the museum has labelled
SECRET all along.

**It is not signposted, and it should stay that way.** No marker, no arrow, no
sign. The lamp over it is deliberately faint. The only thing that announces the
puzzle is a prompt that appears when you are already standing in front of it.

**How it works.** `PuzzleService` discovers the nook rather than describing it:
slots come from the `SlotIndex` attributes on the board, blocks from
`PieceIndex`, and the layout stays whatever `04_zones.luau` built. If the
geometry is not what it expects — wrong count, duplicate index, missing board —
it warns once and switches itself off instead of taking the lobby down.

Interaction is a server-owned `ProximityPrompt` on each block and each cell, so
`Triggered` arrives on the server already attributed to a player: **there is no
puzzle remote at all**, nothing to forge, and it works on a keyboard, a
controller and a phone without any of them being special-cased. The server still
re-checks distance, because a prompt is a request like any other.

**One solver at a time.** The nook is a single physical object in a shared
world, so the first eligible player to pick up a block reserves it. Everyone
else is refused until they finish, disconnect, wander into a match or a queue,
lose their character, or go quiet for 45 seconds. Every one of those ends in the
same place — the blocks go back where they were built, the prompts come back,
and `Board.Solved` returns to false. The physical board is never left solved:
that attribute is this-moment world state, not anybody's record.

**The record is in the profile.** `secretPuzzleSolved` is its own field, because
owning the skin and having found the puzzle are different facts — an account can
hold GALAXY CUBE from a grant without ever having seen the nook, and someone who
already owns it still gets credit for solving. Completion only ever moves from
false to true: with no session lock an older server can save after a newer one,
and finding the secret is not something a stale write gets to undo. A profile
that solved it but somehow lacks the skin is healed on load.

The reward goes through the same seam as every other unlock —
`StatsService.grantSkin` — inside one transaction that records the completion,
grants the skin and pushes the profile once, so the client never sees a solve
that has not paid or a payment for a solve that was not recorded. Solving twice
does nothing at all.

## Blitz

Two minutes, solo, highest score. It sits on its own pad in the Training Zone
beside Sprint — no queue, no opponent, nothing to wait for.

| clear | | with back-to-back |
| --- | --- | --- |
| single / double / triple / quad | 100 / 300 / 500 / 800 | quad 1200 |
| T-spin single / double / triple | 800 / 1200 / 1600 | double 1800 |
| mini single / double | 200 / 400 | |

Combo adds `50 x (combo - 1)` from the second consecutive clear. A perfect clear
adds 3500. Each applies once, in that order. A spin that clears nothing scores
nothing: Phase 11 already declines to count it as a T-spin, and paying for it
would make rotating a T in a notch a better use of two minutes than clearing
lines. There are no points for drop distance or movement either — the shadow
validates placements, not inputs, so paying for inputs would mean trusting the
client's account of them.

**The score is the server's.** Blitz keeps a shadow board and validates every
placement through the same `LockValidation` a ranked match uses: sequential lock
index, a piece the player could be holding, a reachable square, and the rotation
witness replayed to decide a spin. The clear, the T-spin, the combo, the
back-to-back chain and the perfect clear are all derived there, and the score is
computed from those. The client reports where it put a piece and nothing else;
`score`, `lines`, `combo`, `b2b` and `perfect` in a lock payload are read by
nobody.

**The clock is the server's too.** The session carries `startAt` and `endAt` on
`workspace:GetServerTimeNow()`, which both ends read, so a slow round trip costs
the player none of their two minutes and a fast one buys them nothing. The
server ends the run on its own clock whether or not the client says anything,
and a placement that arrives after the deadline is late whatever the client
believes.

A run ends three ways. The timer expiring and topping out are both runs played
out, and both can set `bestBlitz`; a top-out keeps every point earned before it.
Walking away does not count — a score that only counts when you like the look of
it is not a score. `bestBlitz` merges with **max**, so a stale server cannot take
a record away.

Sprint is unchanged and still on its Phase 10 path: the server times the session
and vets the claim rather than shadowing the board. Blitz needed the shadow
because it has a number worth cheating for; rewriting a working mode to match
would have been a redesign nobody asked for.

## Tests

660 assertions. **Run them in Play mode, from the Server datamodel:**

```lua
require(game.ServerScriptService.Services.Tests).run()
```

Running them from Edit over MCP is a trap — `require` caches per ModuleScript
and the MCP command thread keeps its own cache, so an edited module silently
re-runs as its stale self. Cloning `Shared` fixes it for modules the suite
requires directly, but `BotService` and `MatchInstance` reach `Shared` by
absolute path and still pick up the cached originals, so the two halves of a
test end up running different versions of `Board`. Play mode builds a fresh
datamodel, so everything there is current by construction.

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

The lobby was finished physically long before it was finished behaviourally, and
for a long time this table was most of it. The queue pads, the leaderboard rows,
the museum exhibits and the secret board have all since been wired to the
services that own them, each one by reading the attributes the builders already
set rather than by changing the world.

| Thing | Hook | Still owed |
| --- | --- | --- |
| Emote pad / idle rewards | `PadMode = "emote"` | the lounge pad is read and deliberately does nothing |

Walking through the open portal leads to a small alcove that Phase 5 turned into
the match hand-off.

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
