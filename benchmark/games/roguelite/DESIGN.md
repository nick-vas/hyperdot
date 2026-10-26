# Top-down roguelite: Wickerdeep

The fifth genre of the staged game programme (`benchmark/PLAN.md`): the one that exercises procedural generation, game
AI, saves and performance with many entities. Every floor is generated from a seed and checked by a sweep of seeds
(`godot-procgen`), the enemies wander and hunt by a small state machine over one shared distance field
(`godot-game-ai`), a swarm of hundreds is one flag away for `bench` (`godot-performance`), meta progress outlasts the
runs in a versioned save (`godot-saves`), and nothing in the simulation reads the clock or the global generator
(`godot-determinism`). One game, written twice: `gdscript/` (built) and `csharp/` (to come, from this design). Both
behave the same, use the same data files, scene tree, node names and log lines, and pass the same flows. Only the code
and the test framework differ: GUT for GDScript, gdUnit4 (run by the kit's `gdunit4` runner) for C#.

Everything here is made up for the benchmark: the name, the crypt, the enemies. The floor and the creatures are drawn in
code, the candle is a PNG drawn by a script, the sounds come from the kit's `sfx` command, and the store art is rendered
from the game. Nothing comes from a real game.

## The game

The player carries a candle, the wick, down four floors of a crypt. A floor is a grid of rooms joined by corridors;
its stairs stay sealed until every enemy on it is snuffed. Shades, cinder bats and tallow brutes wander until they see
the wick, then hunt it and strike from beside it. A run ends at the bottom (victory) or when the wick's hp reaches 0.
The embers its enemies leave are banked between runs, all of them after a victory, half after a death, and buy vigor
at the shrine: one more hp for every run after.

### The contract the C# port keeps

**The grid** (`scripts/dungeon.gd` `Dungeon`, engine-light): `width`, `height`, `tiles` (row by row, index
`y * width + x`, `WALL` 0 or `FLOOR` 1), `rooms` (`Rect2i`, room 0 holds the start), `start`, `stairs`, `spawns`
(`{ "kind", "cell" }` in the order rolled). `DIRS` is up, right, down, left: every search and choice tries steps in that
order. Cells are 4-connected; nothing moves diagonally.

**Generation**, `Dungeon.generate(seed, spec)`, one `RandomNumberGenerator` seeded with `seed`, its draws in this order:

1. `wanted = randi_range(rooms[0], rooms[1])`.
2. Up to 400 tries while fewer than `wanted` rooms: `size = (randi_range(low, high), randi_range(low, high))` (x drawn
   first), then `position = (randi_range(1, width - size.x - 1), randi_range(1, height - size.y - 1))`; the room is kept
   when `room.grow(1)` intersects no kept room (a wall between rooms), and its cells become floor.
3. Join: for each room `i` from 1, the nearest of rooms `0 .. i-1` by Manhattan distance between centres (the first on a
   tie), dug as an L corridor: `randi() % 2 == 0` goes across first (corner `(to.x, from.y)`), else down first (corner
   `(from.x, to.y)`). A centre is `position + size / 2` (integer division). A spanning tree grown from room 0, so every
   room is reachable whatever the seed.
4. `start` is room 0's centre; `stairs` the centre of the room farthest from the start by walking distance (the first
   on a tie, rooms from 1).
5. Spawns: for each room from 1, `count = randi_range(per_room[0], per_room[1])`; for each, a cell
   `(randi_range(x, end.x - 1), randi_range(y, end.y - 1))`, then a kind `enemies[randi_range(0, size - 1)]` (both drawn
   even when the cell is taken); a cell already taken (the start, the stairs, another spawn) is skipped.

`distance_field(from)` is a breadth-first search over floor (-1 where unreachable); `line_clear(a, b)` walks Bresenham's
line and is false when a cell strictly between the ends is not floor; `unreachable_cells()` counts floor the start
cannot reach; `to_text()` draws the floor (`#`, `.`, `S`, `>`, `s` shade, `b` bat, `B` brute) and two dungeons are the
same when their text is; `from_text(rows)` reads such rows back for tests (the whole grid one room).

**Seeds**: a run's seed is `--seed=N` for the first run of a session, `N + 1` for the next, and so on; without it,
`randi() % 1000000 + 1` of the global generator (in the game, never in `scripts/`). Floor `f` of a run has seed
`run_seed * 1009 + f` (`Run.floor_seed()`); the enemies' own stream (`World`) is seeded with `floor_seed * 31 + 7`, so
how they wander never moves a room. `test_dungeon.gd` pins seed 7 of floor 1: 6 rooms, room 0 `Rect2i(22, 9, 5, 4)`,
start `(24, 11)`, stairs `(10, 18)`, 170 floor cells, 8 spawns.

**Creatures** (`scripts/actor.gd` `Actor`): `kind`, `cell`, `from_cell` and `moved_at` (the game slides it between the
two over `move_ticks`), `hp`, `max_hp`, `damage`, `move_ticks`, `attack_ticks`, `sight`, `embers`, `move_cooldown`,
`attack_cooldown`, `facing`, `alert` (ticks it goes on hunting; 0 while it wanders), `mercy` (the wick's), `hit_at`.
`Actor.from_kind(stats, cell)` makes an enemy from a row of `data/enemies.json`.

**A floor in play** (`scripts/world.gd` `World`): `World.create(dungeon, kinds, seed, hp, max_hp)` puts the wick (damage
1, a step every `WICK_MOVE_TICKS` 6, a blow every `WICK_ATTACK_TICKS` 14) on the start and the spawns in order. One
`step(move, attack)` is one tick:

1. `tick += 1`; the wick's cooldowns and mercy count down; nothing more when the wick is out or the floor is done.
2. With `attack` and no attack cooldown, a blow: the enemy in the faced cell, else the first beside it in `DIRS` order,
   loses the wick's damage, its `alert` rises to at least `MEMORY_TICKS`; at 0 hp it is snuffed (removed, its embers
   added to `embers`, `enemy_snuffed`; the last one opens the stairs, `stairs_opened`), else `enemy_hit`.
3. With a `move` and no move cooldown, `facing = move`, and the wick steps when the cell is floor and free.
4. On the open stairs, `done` and the tick ends.
5. The distance field from the wick is searched again only if the wick changed cell (`path_searches` counts searches).
6. Each enemy, in list order: cooldowns down; if it sees the wick (`sight` squared at least `dx*dx + dy*dy`, and
   `line_clear`) `alert = max(alert, MEMORY_TICKS 90)`, else `alert` counts down. Beside the wick (Manhattan 1) it
   strikes when its attack cooldown is 0 (`hurt_wick(damage)`, cooldown `attack_ticks`); away from it the attack
   cooldown is held at least `WINDUP_TICKS` 30, so it winds up after arriving. Then, when its move cooldown is 0
   (reset to `move_ticks`): hunting, it steps to the free neighbour with the smallest field value below its own;
   wandering, `roll = rng.randi_range(0, 5)`, 0-3 a step in `DIRS[roll]` if that cell is floor and free, 4-5 none.

`hurt_wick(amount)` does nothing during mercy (`MERCY_TICKS` 30 after a hurt that lands); else hp falls (not below 0),
mercy starts and `wick_hurt` is emitted. `add_swarm(count, stats)` adds hunting enemies (alert for ever) on free floor
at least 6 steps from the wick, picked by a partial Fisher-Yates over the cells in row order with the enemies' stream.
`play_out(bot, max_ticks)` plays with a bot: `"cleared"`, `"dead"` or `"stuck"`.

**The bot** (`scripts/bot.gd` `Bot`): an enemy beside the wick, strike; while the wick cannot step, wait; else step
towards the nearest enemy the wick can walk to (by the field from the wick; the first in the list on a tie), or to the
open stairs when none is left, down the field searched from that target, to the free neighbour with the smallest value
below the wick's own. With no enemy it can reach and the stairs shut it waits, which is how a floor it cannot clear
shows as `"stuck"`.

**Data** (`data/floors.json`, `data/enemies.json`, `Floors`), checked by `data.json`:

| Floor | Name (key) | Size | Rooms | Room sides | Enemies (repeats weigh more) | Per room |
|---:|---|---|---|---|---|---|
| 1 | The Wax Cellar (`FLOOR_1`) | 40 x 24 | 5-6 | 4-7 | shade | 1-2 |
| 2 | The Ossuary (`FLOOR_2`) | 42 x 24 | 6-7 | 4-7 | shade, bat | 2-3 |
| 3 | The Drowned Nave (`FLOOR_3`) | 44 x 26 | 6-8 | 4-8 | shade, bat, brute | 1-2 |
| 4 | The Wick's End (`FLOOR_4`) | 44 x 26 | 7-8 | 4-8 | shade, bat, brute | 1-3 |

| Enemy | Name (key) | hp | Damage | Move ticks | Attack ticks | Sight | Embers |
|---|---|---:|---:|---:|---:|---:|---:|
| `shade` | Shade (`ENEMY_SHADE`) | 2 | 1 | 12 | 45 | 6 | 1 |
| `bat` | Cinder bat (`ENEMY_BAT`) | 1 | 1 | 8 | 40 | 5 | 1 |
| `brute` | Tallow brute (`ENEMY_BRUTE`) | 3 | 2 | 18 | 70 | 5 | 3 |

With a wick of 5 hp, the bot clears 20, 20, 19 and 18 of the twenty floors of seeds 1-20 (seed `s * 1009 + f`), losing
9, 13, 27 and 45 hp over them; whole runs (one hp back at each stairs) reach the bottom for 29 of seeds 1-40, seed 1
among them.

**Runs and meta** (`Run`, `Meta`, `SaveStore`): a run is `seed`, `floor`, `hp`, `max_hp`, `embers`; clearing a floor adds
the floor's embers and relights one hp (up to `max_hp`). `Meta.bank(save, run_embers, floor_reached, won)` adds the
run's embers (half, rounded down, after a death), keeps the deepest floor and counts the run; `Meta.buy_vigor(save)`
spends 5, 10 and 15 embers for vigor 1 to 3; `Meta.max_hp(save)` is 5 plus vigor. `user://save.json` is version 2:
`meta` (`embers`, `vigor`, `best_floor`, `runs`), `run` (the run in progress as `Run.to_dict()`, kept at the start of
each floor, or `null`) and `settings` (`volume`, `locale`). Version 1 was `{ "version": 1, "embers": N, "best": F }` (a
file without a version is version 1): the embers and the deepest floor carry over, vigor and runs start at 0. Continue
generates the saved floor again from its seed, with the saved hp and embers.

**Scenes and nodes**:

- `res://main.tscn`: root `Main` (Control) with `Menu/Title`, `Menu/EmbersLabel`, `StartButton` (a new run),
  `ContinueButton` (shown when the save holds a run), `ShrineButton`, `SettingsButton`, `CreditsButton`, `QuitButton`,
  `VersionLabel`. Screens are children of Main: `Game`, `Shrine` (`res://ui/shrine.tscn`: `Box/Title`,
  `Box/EmbersLabel`, `Box/VigorLabel`, `Box/VigorButton`, `Box/BackButton`), `Settings` (`Box/Languages/<Locale>Button`,
  `Box/BackButton`), `Credits`.
- `res://game/game.tscn`: root `Game` (Node2D) with `Camera`, `Tiles` (draws the floor once per floor), `Creatures`
  (draws every creature in one pass, and the rings of snuffed ones), `SfxHit`, `SfxHurt`, `SfxSnuff`, `SfxStairs`, `HUD`
  (CanvasLayer: `Flash`, `FloorLabel`, `HpLabel`, `EmbersLabel`, `EnemiesLabel`, `PauseButton`), `PauseMenu` (`Title`,
  `ResumeButton`, `QuitButton`) and `RunOverMenu` (`Box/Title`, `Box/MessageLabel`, `Box/AgainButton`, `Box/MenuButton`).
  Cells are drawn 22 px wide, the floor centred below y 112.
- The game's API: properties `run`, `world`, `state` (`playing`, `between`, `over`, `done`), `floor_number`, `hp`,
  `enemies_left`, `wick_cell`; methods `setup(floors, options, max_hp, saved)`, `start_run(seed = -1)`,
  `start_floor(n)`, `resume(data)`; signals `run_over(won, floor, embers)`, `checkpoint(data)`, `finished`,
  `menu_requested`.
- Input actions: `move_up`, `move_down`, `move_left`, `move_right` (WASD, arrows, the d-pad; one held direction, up
  first), `attack` (Space, J, the gamepad's X), `pause` (Escape, Start).

**Pacing** (60 physics ticks, all game logic in `_physics_process`): the stairs take 30 ticks before the next floor; a
bot run shows a death for 60 ticks before the next run.

**Command-line arguments**, after `--`: `--autoplay` (Bot in the wick's place from the main scene; a death starts a new
run with the next seed; the game quits after victory), `--seed=N`, `--no-save`, `--floor=N` (the floor a run starts
on), `--swarm=N` (N more bats hunting from the start of every floor: the load for `bench`).

**Log lines** (print): `[Run] floor N, seed S: R rooms, E enemies` when a floor starts, `[Run] floor N cleared`,
`[Run] died on floor N`, `[Run] victory`; for `juice`, in game time, `[juice] event enemy_hit|wick_hurt|enemy_snuffed
<ms>` and `[juice] feedback sfx|flash|shake|pop <ms>`. The killing blow emits `enemy_snuffed` only, never
`enemy_hit`, and the stairs' sound is not logged as feedback, so neither can stand in for a snuffed enemy's sound.

**Determinism**: nothing in `scripts/` reads the clock or the global generator (`architecture.json` marks `scripts` as
simulation code, `nondeterministic-sim` an error); a seed builds the same floor in both languages because
`RandomNumberGenerator` is the engine's class in both and the draws above come in a fixed order.

## The release candidate (the whole game, `game/`)

| Part | Files |
|---|---|
| Tests | GDScript: `test/unit/test_*.gd` (GUT), 44 tests: the generator over a sweep of seeds and its pinned seed (`test_dungeon.gd`), World's rules on floors drawn by hand (`test_world_rules.gd`), hunting, embers, a swarm and a floor replayed from its seed (`test_world.gd`), mercy, the bot and each floor's fairness, Meta, saves and the run kept in them, the launch options and the game scene. C#: `test/*Test.cs` (gdUnit4) |
| Flows | `test/flows/start.flow.json` (menu to floor 1), `pause.flow.json`, `play.flow.json` (the wick walks where the player holds), `shrine.flow.json`, `settings.flow.json` (French and back) |
| Data | `data/floors.json`, `data/enemies.json` (floors `ref` the enemies); `data.json` |
| Bot runs | `playthrough.json`: `--autoplay --seed=1 --no-save`, `[Run] floor 1 cleared` to `[Run] floor 4 cleared` and `[Run] victory` within 10800 frames (seed 1 reaches the bottom in about 3770 ticks). `juice.json`: 1800 frames; enemy_hit gets sfx, wick_hurt flash, shake and sfx, enemy_snuffed pop and sfx, each within 100 ms |
| Text | `i18n/strings.csv` (keys, `en`, `fr`, `de`), every visible text through `tr()`; `textsize.json` (menu, game, shrine at 1280x800); `layout.json` (the same on `phone_landscape` and `ultrawide`) |
| Architecture | `architecture.json`: `parent-path`, `per-frame-lookup` and `nondeterministic-sim` are errors; `simulation` is `scripts` |
| Assets | `art/wick.png` drawn by a script; sounds in `sounds/sfx/` from `hyperdot.ps1 sfx -Sound blip,hit,explosion,powerup -Seed 6`; `assets.json` with each source and licence |
| Release | `export_presets.cfg` (Linux, Web; C# Linux only); `application/config/version="1.0.0"`; `store/steam/` art at the sizes `doctor` checks, 5 screenshots and `short_description.txt`; `store/.gdignore`; `CREDITS.md`, `credits.json` and `THIRD-PARTY-NOTICES.txt` from `credits` |
| Plan | `plan/plan.json` at the release gate, its gates met; `docs/` (GDD, decisions, milestones, tech debt, trailer) |

The whole game passes the kit's `test` (validate, architecture, gut, flows, smoke, juice, playthrough, l10n, data,
textsize, layout) and `doctor` with no FAIL, and `export -Preset Linux -Run` starts the build. For the load,
`hyperdot.ps1 bench -Scene res://game/game.tscn -GameArgs '--swarm=200'`.

## The stages

Each stage is the whole game minus parts, through `stages/<stage>.json` (`remove`, `edits`) and the overlay
`stages/<stage>/`. Every stage passes `test` with the runners it has. Defects are never part of a stage: each task plants
its own.

| Stage | Has | Removed from the whole game |
|---|---|---|
| prototype | Dungeon, World without mercy, Actor, Bot, Run, Floors with floor 1 only; `game/game.tscn` is the main scene, one run with the floor and the HUD, plain English text; 16 tests (the generator, World over time, the options) | menus, the shrine, Meta, saves, pause, the run-over panel, sounds, juice, floors 2-4, translations, data checks, store, export, plan, most tests |
| alpha | menus, the shrine, pause, the run-over panel, floors 1-2 with shades and bats, mercy, Meta, SaveStore (version 2 only) with Continue, juice and sounds, flows `start`, `pause`, `play`, `shrine`, `data.json`, `architecture.json`, `plan.json` at the alpha gate, English | floors 3-4, the brute, `--autoplay`, French and German, the settings flow, text size and layout checks, store, export, credits |
| beta | all four floors, the bot, `playthrough.json`, `juice.json`, English and French, settings, SaveStore version 1 migration | store, export presets, credits, German |
| release | everything | nothing |

## The tasks

For each stage, in the order the tiers take them (the min and mid tiers take the first two). Each task has a
**reference** solution, `solutions/<stage>/<template>/` (whole files laid over the game, plus `answer.md` when the
answer is graded), and some a **decoy**, `solutions/<stage>/<template>-decoy/`, a tempting wrong fix.
`tests/Test-GameProgramme.ps1 -Genre roguelite` plants each defect and checks that the untouched game fails, the
reference passes and the decoy fails.

The defects of this genre: a generated room unreachable for some seeds (prototype fix-bug), an enemy that sees through
walls or steps into them (eight World mutants in prototype write-tests; enemies wandering into the rock in beta
fix-playthrough), per-enemy work that scales badly (beta fix-performance, graded by a counter), a save losing meta
progress (alpha fix-bug) and a seed not deterministic (beta fix-bug).

### Prototype

| # | Template | Defect planted (`edits`) | Graded by |
|---|---|---|---|
| 1 | `fix-bug` | rooms joined to their nearest neighbour among all rooms instead of the nearest already joined, so pairs of rooms form islands for some seeds | a hidden test with its own search: on floor 1 and two bigger shapes, 300 seeds each, every floor cell and every room's cells reachable, the rooms rolled all there, the stairs and every enemy reachable; `test_dungeon.gd` `unchanged`. Decoy: walling up what the start cannot reach (rooms and enemies left in the rock) |
| 2 | `write-tests` | none; `{file}` is `test/unit/test_world_rules.gd` | 8 mutants of World: a step into a wall, two creatures in one cell, sight through walls, sight beyond its range, a strike from a diagonal, a blow that does no harm, a snuffed enemy left on the floor, the stairs open with an enemy left; `world.gd` `unchanged` |
| 3 | `add-feature` | none (mercy removed from the stage); `{feature}`: mercy | a hidden test (30 ticks counted by `step`, a missed hurt starts no new mercy, three shades striking together land one blow); `newTests` 1 |
| 4 | `explain-failure` | a snuffed enemy's embers counted twice (in `_swing` as well as `_snuff`) | the answer names `test_snuffed_enemies_leave_their_embers`, `test_world.gd` line 50, 10 and 20 (number terms that `Godot 4.7.2` in the prompt cannot satisfy); nothing `unchanged` may change |

### Alpha

| # | Template | Defect | Graded by |
|---|---|---|---|
| 1 | `add-content` | none; `{content}`: floor 3, The Drowned Nave, 44 x 26 with 6 to 8 rooms, and the tallow brute (3 hp, blows of 2, slower than a shade, 3 embers), fair (the bot clears at least 15 of 20 seeded floors and loses at least 10 hp over them) | `data`; a hidden test of the floor, the brute, 100 seeds whole and mostly with brutes, and the fairness; a hidden flow starting floor 3 |
| 2 | `fix-architecture` | the wick's hp label set from `Creatures` with `get_node("../HUD/HpLabel")` every frame, and no longer by the game | the architecture runner (per-frame-lookup is an error); a hidden test that the label follows a hurt, a new floor and a new run |
| 3 | `migrate-save` | none, SaveStore reads only version 2; `{report}`: banked embers and the deepest floor gone after updating | a hidden test loading a version 1 file, one without a version, banking and buying over a migrated save written back as version 2, and a version 2 file |
| 4 | `fix-bug` | a save losing meta progress: `Meta.bank` sets the bank to the run's embers instead of adding them | a hidden test of deaths and victories adding up, and of vigor and the bank through the save; `test_meta.gd` `unchanged` (the alpha leaves out its test of runs adding up). Decoy: only a victory fixed, a death still overwrites the bank |

### Beta

| # | Template | Defect | Graded by |
|---|---|---|---|
| 1 | `fix-playthrough` | a wandering enemy checks only the grid's bounds and free cells, not the floor, so enemies drift into the rock where the bot cannot reach them and the stairs stay sealed (seed 1 stalls on floor 1) | `playthrough`; a hidden test that over 900 ticks on every floor and 8 seeds no enemy ever stands in the rock and none vanishes without a blow, a walled-in wanderer stays put, and the bot clears every floor of seed 1. Decoy: snuffing enemies found in the rock, which hides the stall |
| 2 | `add-feedback` | a snuffed enemy plays no sound | `juice` |
| 3 | `fill-translations` | the run-over panel's two messages and Descend again are empty in `fr` | `l10n`; the panel's script and the scene `unchanged`. Decoy: the keys deleted |
| 4 | `fix-bug` | a seed not deterministic: a room's width drawn with the global `randi_range` | a hidden test (one seed after `randomize()` on every floor, a floor played twice, seeds that differ, the global generator left alone); `test_dungeon.gd` `unchanged` (it pins seed 7). Decoy: `seed(seed_value)` before generating |
| 5 | `fix-performance` | every hunting enemy searches the whole floor for its own path on each step, instead of following the one field searched when the wick moves | a hidden test reading `path_searches`: at most 2 while a swarm of 150 closes in on a still wick for 240 ticks, at most one per cell the wick moves, and a hunter still finds its way round a corner |
| 6 | `fix-flow` | the settings screen's Back button is not connected | the `settings` flow |

### Release

| # | Template | Defect | Graded by |
|---|---|---|---|
| 1 | `fix-export` | the Linux preset excludes `data/*` | `kit`: `export -Preset Linux -Run` |
| 2 | `fix-store` | `library_capsule` is 600x800 (a `copy` edit lays `defects/library_capsule_600x800.png` over it), and the art's entry in `assets.json` has no licence | `kit`: `doctor` (no FAIL) and `credits`; a hidden check that the capsule is 600x900 |
| 3 | `cut-version` | none; `{version}` 1.1.0, `{details}`: the project, a `CHANGELOG.md` entry, the menu | `match` on `project.godot` and `CHANGELOG.md`; a hidden flow reading the menu's version label |

### Milestones

Each is the next stage's `milestone` entry. It runs on the earlier stage and is graded by these hidden acceptance files.
Its reference is every file of the next stage that the earlier one lacks or has otherwise.

| From, to | `{goal}` | Accepted by |
|---|---|---|
| prototype to alpha | a menu, pause, floor 2 with cinder bats, `data.json`, Meta's bank and vigor with a shrine, a save of the meta progress and of the run in progress with Continue | hidden flows `start`, `pause` and `shrine`; a hidden test of two floors, Meta, the save and Continue; `data.json` passes |
| alpha to beta | floors 3 and 4 with the tallow brute, fair; a bot that reaches the bottom; juice for blows, hurts and snuffs; version 1 saves; French with a settings screen | `playthrough.json`, `juice.json` and the `settings` flow of the whole game, hidden; hidden tests of French and of four fair floors and version 1 saves |
| beta to release | export presets for Linux and Web, store art, credits, German, version 1.0.0 | `kit`: `doctor`, `export -Preset Linux -Run`, `credits` |

## Rules for writing it

- Each stage must be green under `pwsh ci/godot/hyperdot.ps1 test -Project <stage>` and `doctor` without FAIL; `tests/
  Test-GameProgramme.ps1 -Genre roguelite -Language <lang>` builds every stage and checks every task.
- Hidden tests and flows sit in `hidden/`, named for their task; they are copied into the game only when it is graded.
- Floors, enemies and the bot change together: `test_bot.gd` holds every floor to being cleared by the bot at least 15
  times in 20 and costing it hp, and seed 1's run to reaching the bottom.
- Keep the game small: about 1,600 lines of game code per language, a test run under a minute, a playthrough under 3
  minutes of game time.
- Comment like the rest of the kit: say why, not what.

## As built

Choices made in the GDScript build where the design was open. The C# port follows them.

- **A grid, stepped in ticks.** The wick and the enemies move a whole cell at a time on cooldowns counted in physics
  ticks and are drawn sliding between cells. Collisions, sight and paths are then integer questions about cells, the
  rules tests draw their floors as text, and a floor replays exactly from its seed and inputs, which a test checks.
- **The rules live in World, not in nodes.** The game feeds World one input a tick and draws it; it never decides. So the
  tests, the bot's balance checks and the hidden checks play whole floors in moments, without a scene.
- **Two random streams per floor**: the generator's and the enemies'. Tuning how enemies wander never moves a room, and
  the pinned seed in `test_dungeon.gd` only moves when the generator changes.
- **Validity by construction, checked by sweeps.** The spanning tree makes every room reachable, so the generator never
  retries; `test_dungeon.gd` sweeps 60 seeds of every floor and the hidden check of the fix-bug task 900 more with a
  search of its own, so a fix that only patches `unreachable_cells()` does not pass.
- **One distance field for every hunter**, searched again only when the wick changes cell, rather than a path per enemy:
  a swarm of hundreds costs one search a step. `path_searches` counts searches for the performance task; `--swarm=N` is
  the same load for `bench`.
- **Enemies wind up.** One that arrives beside the wick waits 30 ticks before its first blow, longer than the wick
  needs to snuff a shade, so damage comes from crowds and brutes, as the playtest intends; without it the bot died on
  floor 3 of every seed.
- **The killing blow emits `enemy_snuffed` only**, not `enemy_hit` as well, so the snuffed enemy's own sound is what the
  juice runner checks, which is what lets the add-feedback task be caught.
- **The stairs relight one hp**, and a death banks half the run's embers; seed 1's run clears all four floors in about
  63 s of game time.
- **The prototype keeps the bot and `--autoplay`** (the World tests use the bot), the alpha drops the flag but keeps
  `Bot` for its balance tests, and the alpha-to-beta milestone asks for the flag back with the beta's bot runs.
- **The alpha's test of runs adding up to the bank is left out** (the rest of `test_meta.gd` stays), so the fix-bug
  defect is found by reading the report, not by a failing test; the beta and later have it again.
- **Tests use only shades and bats** from the data, or kinds of their own (`test_snuffed_enemies_leave_their_embers`),
  so the brute can arrive with the alpha's add-content task without breaking them.
- **Store art** is rendered by the game under Xvfb: five 1920x1080 screenshots of the menu, the shrine, floors 1 and 3
  and a swarm, and the capsules cut from a frame of the swarm without the HUD, the title drawn by ImageMagick. The
  600x800 capsule of the fix-store defect is a crop of the real one.
- **Decoys:** fix-bug (prototype, alpha, beta), fix-playthrough and fill-translations. The beta fix-bug decoy, seeding
  the global generator, is deterministic: it fails because it moves the pinned seed, disturbs the global generator and
  still calls it (the architecture runner's error).
