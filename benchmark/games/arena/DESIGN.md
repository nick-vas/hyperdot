# Multiplayer arena: Glimmerpit

The ninth genre of the staged game programme (`benchmark/PLAN.md`): the one that exercises ENet, `soak` and the netcode
core. An authoritative server owns the match; each client predicts its own glimmer with the server's own movement code
and reconciles it against snapshots, and draws the others a little in the past (`godot-multiplayer`); hits are decided
by the server's trace alone; players join and leave in the middle of a match and bots fill every empty slot, so tests
and the bot run need no second machine; the same server runs headless as a dedicated server, which is what `soak`
starts. One game, written twice: `gdscript/` and `csharp/` (ported from this design), both built. Both behave the same,
use the same data files, scene tree, node names, wire messages and log lines, and pass the same flows. Only the code and
the test framework differ: GUT for GDScript, gdUnit4 (run by the kit's `dotnet` runner) for C#.

Everything here is made up for the benchmark: the name, the courts and the glimmers. The pit is drawn in code, the icon
and the store art are rendered by the game, and the sounds come from the kit's `sfx` command. Nothing comes from a real
game.

## The game

Four glimmers in a walled pit, seen from above. Each moves eight ways, aims with the mouse or a stick, fires sparks (a
ray that stops at the first glimmer or pillar it meets) and dashes. Five hits put a glimmer out of the round; the last
one standing wins the round and a point; the first slot to three points wins the match. Rounds alternate between two
courts. A slot is held by a player (local, or over the network) or by a bot.

### The contract the C# port keeps

**Simulation** (engine-light, `scripts/`; `architecture.json` marks it as simulation code, `nondeterministic-sim` an
error): whole pixels and integer arithmetic for everything that moves, so a client's prediction lands exactly where the
server puts it.

- 30 ticks a second (`Sim.TICK_RATE`, the physics rate). The court is 1200 x 640; its (0, 0) is drawn at (40, 64).
- `Court` (`data/courts.json`, `data/walls.json`, `data/spawns.json`, in file order): pillars are `Rect2i`; a glimmer is a
  square of half side 16 against walls. `slide(from, dx, dy)` moves x, then y, each clamped to the court and stopped
  flush against a pillar it would overlap (touching edges do not overlap). `ray_length(from, dir, max)` (slab method,
  the court's edges as walls) and `clear_line(a, b)`.
- `Fighter`: `slot`, `x`, `y`, `ax`, `ay` (the last aim, any length), `hp`, `alive`, `cooldown`, `dash_ticks`,
  `dash_cooldown`. On the wire it is the array `[slot, x, y, ax, ay, hp, alive 0/1, cooldown, dash_ticks, dash_cooldown]`.
- An input is `{ "seq", "mx", "my", "ax", "ay", "fire", "dash", "claim" }`; `Sim.sanitize` clamps `mx`, `my` to -1..1 and
  `ax`, `ay` to +-10000. `Sim.step(f, input, court)` on a living fighter: `cooldown` and `dash_cooldown` drop by 1;
  a non-zero aim replaces `ax`, `ay`; a dash press with both dash timers at 0 sets `dash_ticks` 5 and `dash_cooldown` 45;
  the speed is 8 along one axis, 6 on each axis diagonally, times 3 while `dash_ticks` > 0 (which then drops by 1); then
  `slide`. It returns true (and sets `cooldown` 12) when the input fires with `cooldown` at 0.
- `Sim.trace(court, fighters, shooter)`: from the shooter's centre along its normalised aim, 1000 pixels at most, stopped
  by the first pillar or edge; the nearest living other fighter whose circle of radius 18 the ray meets before that is
  the target. Returns `{ "target", "x", "y" }` (the end point, truncated).
- `ArenaMatch`: four slots; `owners[slot]` is 0 for a bot or a peer id; `scores`; states Warmup (30 ticks), Round,
  Intermission (45 ticks) and Over. `apply(slot, input)` only in a round: `Sim.step`, and a shot is traced by the
  server, never taken from the input's `claim` (a claim that differs from the trace counts in `refused_claims`). A hit
  takes 1 health; at 0 the glimmer is out. `remove_fighter(slot)` takes a glimmer out of the round in play (its player
  left, or a newcomer took a bot's slot). After any glimmer leaves the round, one left standing wins it (+1 point), none
  draws it; three points end the match (`winner`), else the intermission. A round on court `(round - 1) % courts`
  spawns slot s at spawn `(s + round - 1) % 4`, full health, aimed at the court's centre. `set_owner(slot, owner)`
  removes the glimmer from the round and resets the slot's score. `restart()` keeps the owners.
- `snapshot()`: `tick`, `round`, `court` (id), `state`, `state_ticks`, `scores`, `owners`, `winner`, `fighters` (arrays);
  the server adds `events` (`shot` {slot, x, y, ex, ey}, `hit` {slot, by}, `out` {slot, by, x, y}, `gone` {slot},
  `round` {round, winner}, `start` {round}, `over` {winner}).
- `Bot` (seeded `RandomNumberGenerator`, seed `match_seed * 7919 + slot` on the server): targets the nearest living rival,
  one in sight first (+2000 for one out of sight); approaches past 420 pixels or out of sight, backs off under 220,
  circles between (direction flipped with chance 0.4 every 24 ticks); steps eight ways, turning when a pillar is in the
  way; aims at the target with +-26 pixels of error; fires with chance 0.35 when in sight and its cooldown is at most 1;
  dashes with chance 0.02 when the target is far and out of sight.

**Netcode** (engine-light, `scripts/`):

- `ArenaServer(courts, match_seed)`: `peer_joined(peer)` gives the first bot slot, or sends `{ "t": "full" }`; it sends
  `{ "t": "welcome", "slot", "snap" }`. `peer_left(peer)` gives the slot back to a bot and erases everything kept for the
  peer (`record_count()` never exceeds `peer_count()`). `receive(peer, { "t": "input", "inputs": [...] })` queues each
  sequence number once, in order. `tick()`: each slot applies one input (a bot's decision, or the peer's next queued
  input; a starved peer's glimmer is left as it is, its timers included), a second one when a queue holds more than 4;
  then the match advances; every 2 ticks each peer gets `{ "t": "snap", "ack" (its last applied seq), "slot", "snap" }`.
  `loop_matches` (the dedicated server) restarts a finished match after 150 ticks.
- `ArenaClient(courts)`: `step(mx, my, ax, ay, fire, dash)` numbers an input, predicts it with `Sim.step` during a round
  (a shot's `claim` is its own trace of what it shows), keeps it pending and sends the newest 3 pending inputs. On a
  snapshot it drops acknowledged inputs, takes the server's fighter and replays the pending ones (corrections counts a
  snapshot that moved the prediction, in the same round). Others are drawn 5 ticks behind the newest snapshot,
  interpolated between the two around that tick; the clock follows the snapshots, reset whenever it drifts more than 3.
- `SimLink(server, delay, jitter, seed)`: clients and the server in one process, messages turned into bytes and back,
  `delay` ticks each way plus up to `jitter`, never reordered; `--lag=MS` is `round(MS / 2 * 30 / 1000)` ticks each way.
- `NetSession` (`game/net_session.gd`): ENet, `send_bytes` of `var_to_bytes` dictionaries; inputs unreliable-ordered on
  channel 1, the rest reliable on channel 2; `create_server(port, 8)` (no channel count: `enet-server-channels`).

**Scenes and nodes**:

- `res://main.tscn`: root `Main` (Control) with `Menu/Title`, `PlayButton` (a local match), `HostButton`, `JoinButton`,
  `SettingsButton`, `CreditsButton`, `QuitButton`, `VersionLabel`, and `StatusLabel` beside the menu. Screens are
  children of Main: `Game`, `Join` (`res://ui/join.tscn`: `Box/Title`, `Box/AddressLabel`, `Box/AddressEdit`,
  `Box/JoinButton`, `Box/BackButton`), `Settings` (`Box/Languages/<Locale>Button`, `Box/BackButton`), `Credits`; a
  `NetSession` named `Net` while hosting or joined. With `--server` or `--soak-role` it shows nothing and runs `Headless`.
- `res://game/game.tscn`: root `Game` (Node2D) with `Camera`, `CourtView`, `SfxShot`, `SfxHit`, `SfxOut`, `SfxRound`,
  `HUD` (`Flash`, `Scores/Slot<0-3>Label`, `RoundLabel`, `HealthLabel`, `StatusLabel`, `PauseButton`), `PauseMenu`
  (`Title`, `ResumeButton`, `QuitButton`; pauses only a local match) and `ResultMenu` (`Box/Title`, `Box/MessageLabel`,
  `Box/RematchButton`, `Box/MenuButton`).
- The game's API: `mode` (`local`, `host`, `join`), `server`, `link`, `client`, `state` (`warmup`, `round`,
  `intermission`, `over`), `round_number`, `my_slot`; `setup(mode, options, session, courts)`, `start_match(seed)`,
  `rematch()`. The local player is peer 1 on the link; the bot run's guest is peer 2.
- Input actions: `move_*` (WASD, arrows, left stick), `aim_*` (right stick), `fire` (left mouse, J, right trigger),
  `dash` (Shift, K, the gamepad's A), `pause` (Escape, Start).

**Command-line arguments**, after `--`: `--autoplay`, `--seed=N` (match n of the run has seed `N * 1009 + n`), `--no-save`,
`--lag=MS`, `--server`, `--port=N` (24650 by default), and soak's `--soak-role=server|client`, `--soak-port=N`,
`--soak-id=N`.

**The bot run** (`--autoplay`, `game/autopilot.gd`): a bot plays the player's glimmer through the player's client; a
guest client (peer 2) joins over the link, played by another bot, walks out whenever it is one of the last two standing
with 1 health left, and joins again 60 ticks later. Main quits 60 physics frames after the match.

**Soak** (`game/headless.gd`): the server prints `[soak] ready` once listening and, every 5 s, `[soak] metric players`,
`peer_records`, `matches` and `refused_claims`, and `[soak] fail the server keeps N peer records for M players` when it
keeps more than it has players. A client prints `[soak] ready` when first connected, plays with a bot, leaves after
`4 + soak-id` seconds and rejoins 30 ticks later, and reports `joins`, `snapshots` and `corrections`; a lost connection
is `[soak] fail`.

**Log lines** (print): `[Match] round N started on <court>`, `[Match] round N won by slot S (a-b-c-d)`, `[Match] round N
drawn`, `[Match] over: slot S wins A rounds to B`, `[Net] peer P joined slot S`, `[Net] peer P left slot S`,
`[Run] match N, seed S`, `[Run] match over, won|lost`; for `juice`, in game time, `[juice] event shot_fired|player_hit|
player_out <ms>` and `[juice] feedback sfx|flash|pop|shake <ms>`. The round sound is not logged as feedback.

**Settings** (`SettingsStore`): `user://settings.json`, version 2: `volume` (0 to 1), `locale`, `played`, `won`. Version 1
(with `"version": 1` or none) was `{ "volume_db", "language" }`: the volume becomes `db_to_linear(volume_db)`.

## The release candidate (the whole game, `game/`)

| Part | Files |
|---|---|
| Tests | GDScript: `test/unit/test_*.gd` (GUT), 51 tests: movement and shots (`test_sim.gd`), the match (`test_match.gd`), its rules (`test_match_rules.gd`), the courts, the netcode over a SimLink with and without delay (`test_netcode.gd`), real ENet in one process (`test_enet.gd`, port 24651), bot matches, settings, launch options, the game scene. C#: `test/*Test.cs` (gdUnit4), 54 tests: the same 51 and three of the wire format (`WireTest.cs`) |
| Flows | `test/flows/start.flow.json` (menu, Play, the first round), `pause.flow.json`, `join.flow.json` (the join screen's Back), `settings.flow.json` (French and back) |
| Data | `data/courts.json`, `data/walls.json`, `data/spawns.json` (walls and spawns `ref` the courts); `data.json` |
| Bot runs | `playthrough.json`: `--autoplay --seed=1 --no-save`, the first round, the guest leaving and joining again, `[Match] over` and `[Run] match over` within 10800 frames. `juice.json`: 2400 frames; shot_fired gets sfx, player_hit flash and sfx, player_out pop, shake and sfx, each within 100 ms |
| Netcode | `soak`: the dedicated server and three churning clients (`.github/workflows/godot.yml`'s soak job, `docs/GDD.md`) |
| Text | `i18n/strings.csv` (keys, `en`, `fr`, `de`), every visible text through `tr()`; `textsize.json` and `layout.json` (menu, game, join, settings) |
| Architecture | `architecture.json`: `parent-path`, `per-frame-lookup`, `nondeterministic-sim` and `enet-server-channels` are errors; `simulation` is `scripts` |
| Assets | `art/glimmer.png` (the icon) drawn by a script; sounds in `sounds/sfx/` from `hyperdot.ps1 sfx -Sound laser,hit,explosion,powerup -Seed 9`; `assets.json` |
| Release | `export_presets.cfg` (Linux, and Linux Server with `dedicated_server`); version 1.0.0; `store/steam/` art and 5 screenshots rendered from the game, `short_description.txt`; `store/.gdignore`; `CREDITS.md`, `credits.json`, `THIRD-PARTY-NOTICES.txt` from `credits` |
| Plan | `plan/plan.json` at the release gate; `docs/` (GDD, decisions, milestones, tech debt, trailer) |

The whole game passes the kit's `test` (validate, architecture, gut, flows, smoke, juice, playthrough, l10n, data,
textsize, layout), `doctor` with no FAIL, `soak -Clients 3`, and `export -Preset Linux -Run`.

## The stages

Each stage is the whole game minus parts, through `stages/<stage>.json` (`remove`, `edits`) and the overlay
`stages/<stage>/`. Every stage passes `test` with the runners it has. Defects are never part of a stage: each task plants
its own.

| Stage | Has | Removed from the whole game |
|---|---|---|
| prototype | Court (the Cinder Pit only), Fighter, Sim without the dash, ArenaMatch, Bot, ArenaServer, ArenaClient, SimLink; `game/game.tscn` is the main scene, a local match against three bots, English; 16 tests (movement, the netcode) | menus, ENet, the dedicated server, the dash, the Hollow Ring, settings, pause, the result panel, sounds, juice, the bot run, data checks, most tests, store, export, plan |
| alpha | menus, host and join over ENet, the dedicated server and soak roles, the dash, pause, the result panel, settings (version 2 only), juice lines and sounds, flows `start`, `pause`, `join`, `data.json`, `architecture.json`, `plan.json` at the alpha gate, English | the Hollow Ring, the bot run (`--autoplay`), French and German, the settings flow, text size and layout checks, store, export, credits |
| beta | both courts, the bot run, `playthrough.json`, `juice.json`, English and French, the settings flow, settings version 1 migration | store, export presets, credits, German |
| release | everything | nothing |

## The tasks

For each stage, in the order the tiers take them (the min and mid tiers take the first two). Each task has a
**reference** solution, `solutions/<stage>/<template>/`, and some a **decoy**, `solutions/<stage>/<template>-decoy/`.
`tests/Test-GameProgramme.ps1 -Genre arena` plants each defect and checks that the untouched game fails, the reference
passes and the decoy fails.

The five defects of this genre: a server that trusts a client's hit and so scores through walls (prototype fix-bug), a
player who leaves and keeps a ghost glimmer (alpha fix-bug), a match that never ends when a player leaves the last two
standing, at match point or not (beta fix-playthrough), reconciliation that resets the prediction to every snapshot
(beta fix-bug, graded with simulated latency), and a server that keeps state for every player who ever joined (beta
fix-performance, graded by `soak` and a counter). The tests that would point straight at a defect (a leaver's slot going
back to a bot, a leave ending the round, records per peer) are hidden, not in the game's own suite.

### Prototype

| # | Template | Defect planted (`edits`) | Graded by |
|---|---|---|---|
| 1 | `fix-bug` | `ArenaMatch._fire` takes the input's `claim` as the target ("so a hit lands the moment the player sees it"); `refused_claims` still counts, so the game's tests pass | a hidden test sending inputs straight to the server: a claim through a pillar, on a glimmer out of the line, from across the pit, and honest shots. Decoy: the client stops sending claims, the server still trusts them |
| 2 | `write-tests` | none; `{file}` is `test/unit/test_match_rules.gd` | 8 mutants: a hit takes no health, the last hit does not knock out, the last one standing does not end the round, the winner scores nothing, the target does not end the match, shots pass pillars, the cooldown does not hold, glimmers walk through pillars sideways; the three scripts `unchanged` |
| 3 | `add-feature` | none (the dash removed from the stage); `{feature}`: the dash | a hidden test (3 times the speed for 5 ticks, 45 ticks of rest from the press, a pillar stops it, and online at 100 ms a dash corrects nothing); `newTests` 1 |
| 4 | `explain-failure` | a straight step uses the diagonal speed (`or` for `and`) | the answer names `test_a_straight_step_moves_eight_pixels`, `test_sim.gd` line 31, 108 and 106 (number terms that `Godot 4.7.2` in the prompt cannot satisfy) |

### Alpha

| # | Template | Defect | Graded by |
|---|---|---|---|
| 1 | `add-content` | none; `{content}`: the Hollow Ring, with fair spawns (clear, 300 pixels apart, out of each other's sight) and bot matches on it that end | `data`; a hidden test of the court, its spawns, round 2 on it and four bot matches on it alone ending within 150 s |
| 2 | `fix-architecture` | the round label set from `CourtView._process` with `get_node("../HUD/RoundLabel")`, and no longer by the game | the architecture runner (per-frame-lookup is an error); a hidden test that the label follows a round and a new match |
| 3 | `migrate-save` | none, SettingsStore reads only version 2; `{report}`: volume and language lost after updating | a hidden test: decibels to a linear volume (-6 dB is 0.501), a file without a version, rewriting a migrated file, version 2 unchanged |
| 4 | `fix-bug` | `peer_left` no longer gives the slot back to a bot: the glimmer stays, owned by a peer that is gone | a hidden test: the glimmer leaves the round at once, a bot holds and plays the slot from the next round, the snapshot no longer names the leaver, the slot can be taken again. Decoy: the glimmer removed but the slot never given to a bot |

### Beta

| # | Template | Defect | Graded by |
|---|---|---|---|
| 1 | `fix-playthrough` | `remove_fighter` no longer checks for the end of the round, so when the bot run's guest walks out of the last two the survivor waits alone forever | `playthrough`; a hidden test: the last two and one leaves, at match point the match ends, a newcomer taking the last rival's slot, the next round. Decoy: a 20-second round limit, which lets the bot run finish |
| 2 | `add-feedback` | a glimmer knocked out leaves no ring (`pop`) | `juice` |
| 3 | `fill-translations` | the result panel's Victory, message and Rematch keys are empty in `fr` | `l10n`; the panel's script and the scene `unchanged`. Decoy: the keys deleted |
| 4 | `fix-bug` | the client takes the server's fighter and drops the replay of pending inputs, so online the player's glimmer is pulled back on every snapshot (invisible with no delay, so the game's tests pass) | a hidden test over a SimLink at 100 ms, at 250 ms with jitter and at 150 ms: a whole step every tick, no correction, ending on the server's position. Decoy: easing towards the server's position |
| 5 | `fix-performance` | `peer_left` keeps the leaver's input log, and every tick trims every log | `kit`: `soak -Clients 3 -Seconds 20 -Warmup 3` (the server's own `[soak] fail` on peer records); a hidden test: every collection the server keeps back to its size after 200 players came and went, and static memory flat over 300 |
| 6 | `fix-flow` | the join screen's Back button is not connected | the `join` flow |

### Release

| # | Template | Defect | Graded by |
|---|---|---|---|
| 1 | `fix-export` | the Linux preset excludes `data/*`, so the menu's courts fail to load | `kit`: `export -Preset Linux -Run` |
| 2 | `fix-store` | `library_capsule` is 600x800 (a `copy` edit lays `defects/library_capsule_600x800.png` over it), and the art's entry in `assets.json` has no licence | `kit`: `doctor` and `credits`; a hidden check that the capsule is 600x900 |
| 3 | `cut-version` | none; `{version}` 1.1.0 | `match` on `project.godot` and `CHANGELOG.md`; a hidden flow reading the menu's version label |

### Milestones

Each is the next stage's `milestone` entry. Its reference is every file of the next stage that the earlier one lacks or
has otherwise.

| From, to | `{goal}` | Accepted by |
|---|---|---|
| prototype to alpha | menus, join screen, pause, a NetSession for hosting and joining over ENet, the dedicated server and soak roles, settings saved, `data.json` | hidden flows `start`, `pause` and `join`; the whole game's ENet test, hidden; `data.json` passes |
| alpha to beta | the Hollow Ring, the bot run with the guest who leaves and rejoins, juice for shots, hits and knock-outs, French with a settings screen | `playthrough.json`, `juice.json` and the `settings` flow of the whole game, hidden; hidden tests of French and of the Hollow Ring |
| beta to release | export presets (Linux and Linux Server), store art, credits, German, version 1.0.0 | `kit`: `doctor`, `export -Preset Linux -Run`, `credits` |

## Rules for writing it

- Each stage must be green under `pwsh ci/godot/hyperdot.ps1 test -Project <stage>` and `doctor` without FAIL; `tests/
  Test-GameProgramme.ps1 -Genre arena -Language <lang>` builds every stage and checks every task.
- Hidden tests and flows sit in `hidden/`, named for their task; they are copied into the game only when it is graded.
- Tests that open ENet use ports 24651 to 24659; the game's default port is 24650.
- Keep the game small, a test run under a minute, a playthrough under 3 minutes of game time.
- Comment like the rest of the kit: say why, not what.

## As built

Choices made in the GDScript build where the design was open. The C# port follows them; its own choices come after.

- **Rounds of last-one-standing, not a frag count.** A match to a score where players come and go needs a moment that a
  leave can decide: when one of the last two leaves, the other wins the round. That is where the never-ending match
  hides, and the bot run's guest walks out of exactly that situation, so the playthrough meets it every match.
- **Integers for everything that moves, axis-aligned pillars, squares against walls.** Prediction then matches the
  server to the pixel, so a correct client counts 0 corrections at any latency and the reconciliation test can ask for
  exact steps. Floats are only in the shot's ray, which decides hits on the server alone.
- **A starved server leaves the player's glimmer alone, timers included.** Repeating the last input (Overwatch's way)
  would move it where the client did not, and the reconciliation test would see corrections.
- **Slots, not players.** Four slots always fight; a joining player takes a bot's slot (its glimmer leaves the round,
  the player plays from the next), a leaver's slot goes back to a bot, and a slot's score starts again when it changes
  hands. A newcomer never inherits a leaver's points.
- **The client's claim stays in the input.** The client says what its own screen showed it hitting, which the server
  counts (`refused_claims`) and never uses: a natural place for the prototype's trust-the-client defect, and a soak
  metric.
- **Snapshots of the whole match, reliable, 15 a second.** Four players need nothing finer; the TRIBES model is written
  down as tech debt. Events ride in the snapshots, so a client never sees a hit before the shot.
- **ENet through `send_bytes`, not RPCs.** No node paths to keep alike on both sides, so the dedicated server, a host
  and the in-process tests share one NetSession; messages are dictionaries of numbers, never objects.
- **The tests that name a leave's effects are hidden.** The game's own suite checks a leaver loses its slot, but not
  that a bot takes it, that the round ends, or that nothing of the peer is kept: three of the defects would otherwise be
  found by running the tests, which every configuration does.
- **Soak finds the per-peer leak by itself.** The server reports `peer_records` and fails when it keeps more than its
  players; soak clients leave and rejoin every few seconds, so 20 s of soak sees about eight leaves.
- **Store art** is rendered by the game under Xvfb: the menu, two rounds in play, the last two standing and the French
  result panel; the capsules are a round with the title over it, and the 600x800 capsule of the fix-store defect is a
  crop of the real one.
- **About 2,200 lines of game code**, above the 1,500 aimed at: the netcode (server, client, link, ENet session,
  headless roles) is about 700 of them. A test run takes about 20 s; the bot run with seed 1 ends its match (slot 2 wins
  3 to 0, the guest leaves once) at about 29 s of game time.
- **Decoys:** fix-bug in all three stages that have one, fix-playthrough and fill-translations.

### C#

- **Same matches, checked against each other.** The movement is whole pixels, and the shot's ray and the bots' distances
  are taken from the engine's 32-bit `Vector2` and compared as doubles, as GDScript does with them; the bots and the
  link's jitter draw from the engine's `RandomNumberGenerator` in the contract's order, and the interpolation rounds half
  away from zero as `roundf` does. So the bot matches of seeds 1-20 end the same in both languages (tick, winner,
  scores, refused claims, where every glimmer stands and its health), and the bot run (`--autoplay --seed=1 --no-save`)
  prints the same 485 `[Match]`, `[Net]`, `[Run]` and `[juice]` lines, line for line.
- **Names:** `Game` keeps the snake_case names the flows, the hidden checks and the contract use: `mode`, `server`,
  `link`, `client`, `session`, `matches`, `state`, `round_number`, `my_slot`, `start_match` and `rematch`; `start_match`
  is two overloads, `()` and `(seed)`, not a default argument, because the engine calls a C# method only with all its
  arguments. The rest is C#'s own case: `Court.LoadAll`, `BoxFree`, `Slide`, `RayLength`, `ClearLine`, `Sim.Step`,
  `Trace`, `Sanitize`, `Idle`, `ArenaMatch.Apply`, `Advance`, `SetOwner`, `RemoveFighter`, `Snapshot`, `LoadSnapshot`,
  `ArenaServer.PeerJoined`, `PeerLeft`, `Receive`, `Tick`, `RecordCount`, `ArenaClient.Step`, `ShownFighters`,
  `SimLink.Join`, `Leave`, `Pump`, `TicksForMs`, `NetSession.Host`, `Serve`, `Join`, `JoinWith`, `Close`. The match's
  states are the enum `MatchState` (a nested `ArenaMatch.State` would clash with the `State` property), and the hit
  the GDScript tests reach as `_damage` is the public `ArenaMatch.DealDamage`.
- **Typed inside, dictionaries on the wire.** An input is a `SimInput` and an event a `MatchEvent`; a shot's trace is a
  `Shot` record. They become the contract's dictionaries (`ToWire`, `Sanitize`, `MatchEvent.FromWire`) only where a
  message is made or read, and snapshots, welcomes and inputs keep the contract's keys and arrays.
- **The wire is written in managed code.** `scripts/Wire.cs` writes and reads the engine's `var_to_bytes` format
  itself, for messages of numbers, booleans, strings, lists and dictionaries with string keys, and refuses anything
  else (a typed container, a count longer than the bytes, nesting past 16). The first build used the engine's
  `Godot.Collections.Dictionary` and `GD.VarToBytes`, as the GDScript version does; every message then made engine
  Variants, Arrays and Dictionaries whose native memory waits for the garbage collector to finalize their wrappers,
  and a 120-second soak saw the server's resident memory climb from 58 to 194 MB. `WireTest` holds the bytes to
  `GD.VarToBytes` byte for byte, so the two versions put the same bytes on the wire.
- **A server that keeps its memory where it settles.** Even managed, every message is a few small objects, and the
  runtime let them pile up to its first-generation budget (more than 38 MB here) before its first collection: `soak -Seconds
  120 -MaxGrowthMbPerHour 200`, the game's own workflow, read that as 2,100 MB/h of growth. `Headless` (the dedicated
  server and the soak clients) collects the first generation once a second, which takes well under a millisecond with
  so little alive; the same soak then reads about 3 MB/h for the server and under 40 for the clients. A screen's game does
  not, as nothing soaks it.
- **The server stops on SIGTERM**, as `tests/soak-fixture-cs` shows: `Headless` registers a `PosixSignalRegistration`
  that only sets a flag, and the next tick closes the session and quits with 0 (`soak -RequireCleanStop`: exit 0 in
  0.2 s). The GDScript server cannot catch the signal and dies with 143.
- **No server relay.** `NetSession.Host` turns `SceneMultiplayer.ServerRelay` off: players only talk to the server, and
  with the relay on the engine sent news of each newcomer to a peer still disconnecting, an engine error on its closed
  channels that soak counted 4 times in 120 seconds.
- **Sorted dictionaries on the server.** What it keeps per peer is in `SortedDictionary`s, so it broadcasts and trims
  in peer-id order on every run (the architecture runner's `nondeterministic-sim` flags iterating a `Dictionary` in
  `scripts`); in the bot run the peers join in id order anyway, so the order matches the GDScript version's.
- **NetSession** keeps the `SceneMultiplayer` it set up and disconnects only the signals it connected (the engine
  reports disconnecting anything else as an error); its signals are C# events, as are the game's and the screens'.
- **Settings:** `SettingsStore` takes a file path (Main passes `user://settings.json`, globalised) and reads and writes
  it with `System.Text.Json` into a `SettingsData` (`Version`, `Volume`, `Locale`, `Played`, `Won`); the file is the
  GDScript version's, so either reads the other's. Its tests use temporary files.
- **Tests:** 54 gdUnit4 tests in `test/*Test.cs`, the 51 GUT tests one for one and `WireTest`'s three, run by the kit's
  `dotnet` runner, and `gdunit4` for the mutants; the prototype keeps 19 (`SimTest`, `NetcodeTest`, `WireTest`). The ENet
  test gives each branch its own `SceneMultiplayer` with `SceneTree.SetMultiplayer`, as the GUT one does. The scene's
  tests load it with `ISceneRunner` and wait whole physics ticks; the French check adds the game to the tree itself.
- **Hidden checks** are the GDScript ones in C#. The milestone's ENet check is `HiddenEnetTest.cs`, a copy of the
  game's own under its own class name (port 24652), since a session may well write an `EnetTest` of its own. The
  fix-performance check finds the server's collections by reflection over its fields (private ones and properties'
  backing fields), and measures memory as the managed heap after a full collection (`GC.GetTotalMemory`), not the
  engine's static memory, which does not see C# objects.
- **The explain-failure test** is `A_straight_step_moves_eight_pixels`, `test/SimTest.cs` line 30. The add-feature
  prompt names the dash's C# shape: a `Dash` property of `SimInput`, `"dash"` on the wire.
- **Stages** lay overlays of `game/Game.cs` and `game/game.tscn` over the prototype, as the GDScript stage does with
  `game.gd`; the alpha and beta take the credits out of `ui/Main.cs` with edits. The task references and decoys are the
  stage's files with the defect undone or a wrong fix made; those of data and translations are the GDScript version's
  files. The milestone references follow the rule above, generated from the built stages.
- **Export:** Linux and Linux Server, with the .NET options (Godot 4.7 cannot export C# to the Web, and the GDScript
  version has no Web preset either), so the planted export defect adds `data/*` to the Linux preset's
  `exclude_filter="test/*"`. `THIRD-PARTY-NOTICES.txt` comes from `credits` on the C# game, with the .NET runtime's
  notices; the store art, docs, data, translations, sounds and flows are the GDScript version's files.
