# Tower defence: Bramblegate

The sixth genre of the staged game programme (`benchmark/PLAN.md`), one of the mid tier's three: the one that exercises
pathfinding, economy data, balance and `bench`. Pests walk the shortest way across a grid (AStarGrid2D,
`godot-algorithms`), every tower planted reroutes them and may never shut the way, towers, upgrades, pests, maps and
waves are JSON checked by the `data` runner (`godot-data`), a rule-based bot holds every map to a measured balance
(`godot-progression`), a swarm scene loads the field for `bench` (`godot-performance`), and the save keeps each map's
best result (`godot-saves`). One game, written twice: `gdscript/` (built) and `csharp/` (to come, from this design).
Both behave the same, use the same data files, scene tree, node names and log lines, and pass the same flows. Only the
code and the test framework differ: GUT for GDScript, gdUnit4 (run by the kit's `gdunit4` runner) for C#.

Everything here is made up for the benchmark: the name, the garden, the towers, the pests and the maps. The field,
towers and pests are drawn in code, the seed store is a PNG drawn by a script, the sounds come from the kit's `sfx`
command, and the store art is rendered from the game. Nothing comes from a real game.

## The game

Pests (aphids, beetles, moths and a slug queen) come in through a gap in the hedge, the **gate**, and walk to the
**seed store**. Each pest that reaches it eats seeds (the player's lives). The player plants towers on the grass with
**sap** (gold): sap comes from fallen pests and from each cleared wave. A tower on the pests' way makes them walk round
it, so the towers build a maze; a tower may never leave them without a way. Three maps of 4, 5 and 6 waves; clearing a
map opens the next, clearing the third is victory.

### The contract the C# port keeps

**The field** (engine-light, `scripts/path_map.gd` `PathMap`): `PathMap.from_rows(rows)` reads rows of text, `.` grass,
`#` rock, `S` the gate, `G` the store; `size`, `gate`, `store`. Paths come from an `AStarGrid2D` over the map's region,
`cell_size` 1, `DIAGONAL_MODE_NEVER`, Manhattan for both heuristics; rocks and towers are solid. `path_from(cell)` is
`get_id_path(cell, store)` (the cell first; empty from a solid cell or with no way) and adds one to `path_queries`, which
counts every search, previews included. `route` is the way from the gate, recomputed by `set_tower(cell, standing)`.
`is_open` (in bounds, no rock, no tower), `is_buildable` (open, not the gate or the store), `blocks(cell, from_cells)`
(with a tower on the cell, the gate or any of the cells has no way: one search per distinct cell, the gate first),
`preview_route(cell)` (the route with a tower there); both leave the map as it was.

**A pest** (`scripts/enemy.gd` `Enemy`): `uid`, `id`, `hp`, `max_hp`, `speed` (cells a tick), `reward`, `leak`, `pos`
(in cells, `Enemy.centre(cell)` is the cell plus (0.5, 0.5)), `path` (the cells still to walk, the one it is heading to
first), `alive`, `slow`, `slow_ticks`. `cell()` floors `pos`; `target()` is `path[0]`, or `cell()` with no path;
`remaining()` is the distance to `path[0]` plus `path.size() - 1`; `pace()` is `speed * (1 - slow)` while `slow_ticks`
lasts. `SLOW_TICKS` 60.

**The battle** (`scripts/battle.gd` `Battle`), 60 ticks to a second of play:

- `Battle.create(catalog, map_id, seed)` and `Battle.custom(catalog, rows, gold, lives, waves, seed = 1, id = "custom")`;
  one `RandomNumberGenerator` seeded with `seed` draws each pest's speed as it spawns:
  `speed * (1 + randf_range(-0.08, 0.08)) / 60`.
- `gold`, `lives`, `start_lives`, `wave` (the wave under way or the last cleared; 0 before the first), `waves`, `phase`
  (`Build`, `Wave`, `Won`, `Lost`; `phase_name()`), `ticks`, `break_left`, `towers` (cell -> `{ "id", "level",
  "cooldown" }`, in the order built), `enemies`, `shots`, `range_checks`, `kills`, `leaks`.
- `can_place(id, cell)`: not over, a known tower, `gold >= cost`, a buildable cell without a tower, no pest standing on
  it or heading to it (`cell()` or `target()`), and `not map.blocks(cell, targets of every pest)`. `place` pays the cost,
  adds the tower at level 1, `map.set_tower`, then **re-paths every pest** (`path = map.path_from(target())`) and emits
  `tower_placed`.
- `upgrade(cell)` pays `upgrade_cost(id, level + 1)` up to the tower's last level. `refund(cell)` is
  `floor(0.7 * (cost + every upgrade bought))`; `sell(cell)` pays it, frees the cell, re-paths every pest, emits
  `tower_sold` and returns it (0 with no tower or once over).
- `start_wave()` (in Build, with a wave left): `wave += 1`, Wave; the wave's groups give spawns at `delay + i * gap`
  ticks after its start, ordered by tick and then by group order. A break of `BREAK_TICKS` (600) starts the next wave by
  itself; `start_wave()` calls it early.
- `step()`: nothing once over; `ticks += 1`; in Build the break counts down (and may start the wave); due spawns (each at
  the gate's centre with `route` minus the gate); every pest walks `pace()` from centre to centre, **never into a cell
  that is not open** (it waits there), and leaks when its path is empty at the store (`lives -= leak`, never below 0,
  `enemy_leaked`, Lost at 0); towers fire; shots fly; a Wave with no spawn left and no pest is cleared: `gold += bonus`
  once, `wave_cleared`, Won after the last wave, else Build with a new break.
- Towers, in the order built: `cooldown -= 1` while above 0; at 0 the tower looks for a target, the pest within its
  range (`distance_squared <= range * range` from the cell's centre, each test adding one to `range_checks`) with the
  least `remaining()`, the first such in `enemies` on a tie. None: `cooldown = IDLE_TICKS` (4). Found: a shot
  `{ "pos", "aim", "target", "damage", "speed" (shot_speed / 60), "splash", "slow", "tower" }` and `cooldown = reload`.
- A shot flies at its speed towards its target's position while the target lives, else to the last aim; on arrival a
  shot without splash wounds its target if alive, one with splash wounds every pest within `splash` of the aim. A wound
  takes `damage` and, with slow above 0, sets `slow` and `slow_ticks = 60`; at 0 hp the pest falls: `gold += reward`,
  `kills += 1`, `enemy_killed`.
- `spawn_at(id, cell)` puts a pest on a cell at once, outside the waves (tests, the bench). Log lines:
  `[Wave] <map> wave <n> of <count>`, `[Wave] <map> wave <n> cleared, bonus <b>`.

**Data** (`Catalog`, `data/*.json`, all checked by `data.json`):

| Tower | Name (key) | Cost | Range | Damage | Reload | Shot speed | Splash | Slow | Level 2 (cost: damage, range, reload) | Level 3 |
|---|---|---:|---:|---:|---:|---:|---:|---:|---|---|
| `thorn` | Thorn Sprout (`TOWER_THORN`) | 50 | 2.5 | 4 | 20 | 12 | 0 | 0 | 40: 6, 2.75, 18 | 70: 9, 3.0, 15 |
| `puff` | Pollen Puff (`TOWER_PUFF`) | 70 | 2.0 | 2 | 30 | 8 | 1.0 | 0.5 | 50: 3, 2.25, 26 | 80: 5, 2.5, 22 |
| `acorn` | Acorn Mortar (`TOWER_ACORN`) | 100 | 3.5 | 14 | 70 | 6 | 0.9 | 0 | 70: 20, 3.75, 64 | 110: 30, 4.0, 58 |

| Pest | Name (key) | HP | Speed (cells/s) | Reward | Seeds taken |
|---|---|---:|---:|---:|---:|
| `aphid` | Aphid | 29 | 1.5 | 4 | 1 |
| `beetle` | Beetle | 98 | 0.9 | 10 | 2 |
| `moth` | Moth | 34 | 2.4 | 6 | 1 |
| `slug_queen` | Slug Queen | 1170 | 0.45 | 80 | 20 |

Maps (`data/maps.json`, 16 by 9): The Meadow (`meadow`, 120 sap, 20 seeds, 4 waves), The Sunken Path (`sunken`, 160,
20, 5 waves, moths in the fifth), The Briar Maze (`briar`, 220, 20, 6 waves, the slug queen in the last). Waves are rows
of `data/waves.json` (`map`, `number`, `bonus`) and their groups rows of `data/groups.json` (`wave`, `enemy`, `count`,
`gap`, `delay`), so every reference is one the `data` runner checks.

**The bot** (`scripts/bot.gd` `Bot`): `act(battle)` makes at most one decision. Under `MAX_TOWERS` (10) it buys the next
of `thorn, thorn, puff, acorn` (by the number of towers built): with the sap, it tries the buildable cells within that
tower's range of the route, best first by how many cells of `preview_route(cell)` lie in range (ties in row order), and
places on the first `place` accepts; without the sap it calls the next wave. At ten towers it upgrades the
lowest-level tower (the first built on a tie), or calls the next wave. `Bot.play(battle, max_ticks)` and
`Bot.idle(battle, max_ticks)` (no tower, every wave called) play a battle to its end.

**Balance** (measured by `test_balance.gd` and the `--autoplay` bot): the bot clears every map with seeds 1 to 3 and
loses some seeds over the campaign (seed 1: 7, 1 and 4); with no tower each map is lost before its last wave.

**Progress and saves** (`Progress`, `SaveStore`): `user://save.json` with `version` 2, `progress` (map id ->
`{ "stars", "lives" }`) and `settings` (`volume`, `locale`). Stars: 3 with no seed lost, 2 with at least half kept, 1
otherwise; `record` keeps the best (more stars, then more seeds). The first map is open; the next opens once the one
before is cleared. Version 1 was `{ "version": 1, "cleared": [<map ids>], "volume" }` (no version is version 1): each
map cleared gets 1 star.

**Scenes and nodes**:

- `res://main.tscn`: root `Main` (Control) with `Menu/Title`, `StartButton` (opens `MapSelect`), `SettingsButton`,
  `CreditsButton`, `QuitButton`, `VersionLabel`. Screens are children of Main: `MapSelect` (`res://ui/map_select.tscn`,
  `Box/Grid/Map<N>Button`, `Box/BackButton`), `Game`, `Settings` (`Box/Languages/<Locale>Button`, `Box/BackButton`),
  `Credits`, `Victory`.
- `res://game/game.tscn`: root `Game` (Node2D) with `Camera`, `Field` (draws the battle; origin (66, 120), cells of 54),
  `Store`, `SfxPlace`, `SfxKill`, `SfxLeak`, `SfxWin`, `HUD` (CanvasLayer: `Flash`, `MapLabel`, `GoldLabel` "Sap: %d",
  `LivesLabel` "Seeds: %d", `WaveLabel`, `InfoLabel`, `SpeedButton`, `PauseButton`, `Towers/ThornButton`,
  `Towers/PuffButton`, `Towers/AcornButton`, `UpgradeButton`, `SellButton`, `NextWaveButton`), `PauseMenu`
  (`Title`, `ResumeButton`, `QuitButton`) and `ResultMenu` (`Box/Title`, `Box/MessageLabel`, `Box/NextButton`,
  `Box/RetryButton`, `Box/MenuButton`).
- The game's API: properties `level` (the map's place, from 1), `state` (`playing`, `over`, `done`), `battle`,
  `building`, `selected`, `speed`, `gold`, `lives`, `wave`, `phase`; methods `start_map(index, seed = -1)`,
  `place_at(x, y)` (builds `building` there, or selects the tower already there), `select_tower(id)`,
  `upgrade_selected()`, `sell_selected()`, `next_wave()`, `toggle_speed()` (1 and 3), `next_map()`, `retry()`.
- Input actions: `next_wave` (N, the gamepad's Y), `toggle_speed` (F, X), `pause` (Escape, Start); a click on a cell
  builds or selects.

**Pacing**: all game logic in `_physics_process` at 60 ticks; the game runs `speed` battle ticks per physics tick (with
`--autoplay` the bot acts before each); a bot run shows a finished map for 40 ticks.

**Command-line arguments**, after `--`: `--autoplay` (the bot builds from the main scene, map after map from `--map`;
a lost map is replayed), `--seed=N` (battle n of the run, counted from 1, has seed `N * 1009 + n`; without it,
`randi() % 1000000`), `--no-save`, `--map=N`, `--speed=N` (1 to 8; 3 with `--autoplay` unless given).

**Log lines** (print): `[Wave] ...` above; `[Run] map N, seed S` when a battle starts, `[Run] map N won` or
`[Run] map N lost` when it ends, `[Run] victory` after the third; for `juice`, in game time,
`[juice] event tower_placed|enemy_killed|enemy_leaked <ms>` and `[juice] feedback sfx|flash|shake|pop <ms>`. Shots
make no logged sound and the win sound is not logged, so neither can stand in for another event's feedback.

**Determinism**: nothing in `scripts/` reads the clock or the global generator (`architecture.json` marks `scripts` as
simulation code, `nondeterministic-sim` an error); `test_battle.gd` replays a battle from one seed.

## The release candidate (the whole game, `game/`)

| Part | Files |
|---|---|
| Tests | GDScript: `test/unit/test_*.gd` (GUT), 63 tests: the field and its paths (`test_path_map.gd`), building and waves (`test_battle.gd`), the rules (`test_battle_rules.gd`), the sap (`test_economy.gd`), selling, the never-block rule, re-pathing, targeting, the data's meaning, the balance, progress, saves, the launch options and the game scene. C#: `test/*Test.cs` (gdUnit4) |
| Flows | `test/flows/start.flow.json` (menu, map select, the Meadow), `select.flow.json` (the map select's Back), `pause.flow.json`, `build.flow.json` (a thorn, Next wave, its first kill), `settings.flow.json` (French and back) |
| Data | `data/towers.json`, `upgrades.json` (`tower` refs), `enemies.json`, `maps.json` (rows of `[.#SG]{16}`), `waves.json` (`map` refs), `groups.json` (`wave` and `enemy` refs); `data.json` |
| Bot runs | `playthrough.json`: `--autoplay --seed=1 --no-save`, `[Run] map 1 won` to `[Run] map 3 won` and `[Run] victory` within 10800 frames (it takes about 6,700). `juice.json`: 1800 frames; tower_placed gets pop and sfx, enemy_killed pop and sfx, enemy_leaked flash, shake and sfx, each within 100 ms |
| Bench | `bench/swarm.tscn`: 200 pests kept on an open field lined with 40 towers, for `hyperdot.ps1 bench -Scene res://bench/swarm.tscn` |
| Text | `i18n/strings.csv` (keys, `en`, `fr`, `de`), every visible text through `tr()`; `textsize.json` (menu, game, map select at 1280x800); `layout.json` (the same on `phone_landscape` and `ultrawide`) |
| Architecture | `architecture.json`: `parent-path`, `per-frame-lookup` and `nondeterministic-sim` are errors; `simulation` is `scripts` |
| Assets | `art/seed.png` drawn by a script; sounds in `sounds/sfx/` from `hyperdot.ps1 sfx -Sound blip,hit,explosion,powerup -Seed 6`; `assets.json` with each source and licence |
| Release | `export_presets.cfg` (Linux, Web; C# Linux only); `application/config/version="1.0.0"`; `store/steam/` art at the sizes `doctor` checks, 5 screenshots and `short_description.txt`; `store/.gdignore`; `CREDITS.md`, `credits.json` and `THIRD-PARTY-NOTICES.txt` from `credits` |
| Plan | `plan/plan.json` at the release gate, its gates met; `docs/` (GDD, decisions, milestones, tech debt, trailer) |

The whole game passes the kit's `test` (validate, architecture, gut, flows, smoke, juice, playthrough, l10n, data,
textsize, layout) and `doctor` with no FAIL, and `export -Preset Linux -Run` starts the build.

## The stages

Each stage is the whole game minus parts, through `stages/<stage>.json` (`remove`, `edits`) and the overlay
`stages/<stage>/`. Every stage passes `test` with the runners it has. Defects are never part of a stage: each task plants
its own.

| Stage | Has | Removed from the whole game |
|---|---|---|
| prototype | PathMap, Enemy, Catalog, Battle without selling; the Meadow with three waves, aphids and beetles; `game/game.tscn` is the main scene, building, upgrades, Next wave and speed, plain English text; 28 tests (field, battle, sap, data, targeting) | menus, maps 2-3, the moth and the queen, selling, the bot, saves, pause, the result panel, sounds, juice, translations, data checks, store, export, plan, most tests |
| alpha | menus, map select, pause, the result panel, selling, maps 1-2 (the Sunken Path with four waves), the bot's class and the balance tests, Progress and SaveStore (version 2 only), juice log lines and sounds, flows `start`, `select`, `pause`, `build`, `data.json`, `architecture.json`, `plan.json` at the alpha gate, English | the Briar Maze, the moth, the slug queen, `--autoplay`, the re-path test, the bench, French and German, the settings flow, text size and layout checks, store, export, credits |
| beta | all three maps, the moth and the queen, the bot run, `playthrough.json`, `juice.json`, the bench, English and French, settings, SaveStore version 1 migration | store, export presets, credits, German |
| release | everything | nothing |

## The tasks

For each stage, in the order the tiers take them (the min and mid tiers take the first two; the mid tier runs this
genre's prototype and alpha in GDScript and its beta and release in C#). Each task has a **reference** solution,
`solutions/<stage>/<template>/` (whole files laid over the game, plus `answer.md` when the answer is graded), and some a
**decoy**, `solutions/<stage>/<template>-decoy/`, a tempting wrong fix. `tests/Test-GameProgramme.ps1 -Genre
towerdefence` plants each defect and checks that the untouched game fails, the reference passes and the decoy fails.

The genre's defects: a tower that shuts the only way (prototype fix-bug), a wave bonus paid twice (prototype
explain-failure), pests that do not re-path after a placement (alpha fix-bug), a boss no build can stop (beta
fix-playthrough), targeting that searches a path per pest per look (beta fix-performance) and a save that loses
progress (beta fix-bug).

### Prototype

| # | Template | Defect planted (`edits`) | Graded by |
|---|---|---|---|
| 1 | `fix-bug` | `can_place` no longer asks `map.blocks`, so a tower may shut the way and the pests stand still for ever | a hidden test: the last gap refused (sap kept), a route cell with a way round allowed, a wall across keeps a gap, a pest in a corner never cut off, the wave still ends; `test_battle.gd` and `test_path_map.gd` `unchanged`. Decoy: refuse every cell of the current route |
| 2 | `write-tests` | none; `{file}` is `test/unit/test_battle_rules.gd` | 7 mutants of Battle: a tower costs nothing, one dearer than the sap left can be placed, a fallen pest pays nothing, every pest takes one seed, the map goes on with no seed left, towers shoot past their range, towers shoot the newest pest in range; `battle.gd` `unchanged` |
| 3 | `add-feature` | none (selling removed from the stage); `{feature}`: `Battle.sell(cell)` | a hidden test (35 back for a thorn, upgrades counted, never a profit, the route and the pests take the opened way, nothing without a tower or once over); `newTests` 1 |
| 4 | `explain-failure` | a cleared wave's bonus paid twice | the answer names `test_clearing_a_wave_pays_its_bonus`, `test_economy.gd` line 21, 115 and 130 (number terms that `Godot 4.7.2` in the prompt cannot satisfy); nothing `unchanged` may change |

### Alpha

| # | Template | Defect | Graded by |
|---|---|---|---|
| 1 | `add-content` | none; `{content}`: the moth (2.4 cells a second, 34 hp, 6 sap, 1 seed) and the Sunken Path's fifth wave (bonus 45, at least 12 moths with beetles), the map still fair (the bot clears it with seeds 1-3, no tower loses it) | `data`; a hidden test of the moth, the wave and the balance; a hidden flow starting the Sunken Path with five waves |
| 2 | `fix-bug` | `place` no longer re-paths the pests: those on the field walk up to a new tower and wait until it shoots them | a hidden test: their paths go round at once and are shortest, a pest never stands still and reaches the store, every pest turns, paths are searched on placements only; `test_battle.gd` `unchanged`. Decoy: a pest re-paths when it reaches the tower |
| 3 | `fix-architecture` | the sap line set from `Field` with `get_node("../HUD/GoldLabel")` every frame, and no longer by the game | the architecture runner (per-frame-lookup is an error); a hidden test that the line follows a placement, a fallen pest, a sale and a new map |
| 4 | `migrate-save` | none, SaveStore reads only version 2; `{report}`: cleared maps locked again after updating | a hidden test loading a version 1 file (and its volume), one without a version, recording over a migrated save, and a version 2 file |

### Beta

| # | Template | Defect | Graded by |
|---|---|---|---|
| 1 | `fix-playthrough` | the slug queen's hp is 11700, ten times what it should be: she reaches the store in every run and eats all 20 seeds, so the bot replays the Briar Maze for ever | `playthrough`; a hidden test: her hp between 600 and 2400 and over five times any other pest's, she ends the Briar Maze, the bot clears it with seeds 1-3 and no tower loses it. Decoy: her hp set to 50 |
| 2 | `fix-performance` | towers rank pests by `map.path_from(enemy.cell())` (an A* search for every pest at every look) instead of `remaining()` | a hidden test reading `path_queries`: at most 150 searches over 300 ticks with 80 pests and no placement (the defect makes thousands), and the leading pest in range still the one shot. The swarm scene shows the cost in `bench` (about 0.7 ms a tick against 13 ms) |
| 3 | `add-feedback` | a falling pest plays no sound | `juice` |
| 4 | `fill-translations` | the result panel's message and Retry keys are empty in `fr` | `l10n`; the panel's script and the scene `unchanged`. Decoy: the keys deleted |
| 5 | `fix-bug` | `Progress.record` replaces the whole progress with the map just cleared | a hidden test: three maps kept, the next maps open, a worse replay keeps the best, more seeds at the same stars count, through the save; `test_progress.gd` `unchanged`. Decoy: every result overwrites the best |
| 6 | `fix-flow` | the map select's Back button is not connected | the `select` flow |

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
| prototype to alpha | a menu, a map select, pause, the Meadow's fourth wave and the Sunken Path, `data.json`, a save of each map's best stars by `Progress` and `SaveStore` | hidden flows `start`, `select` and `pause`; a hidden test of two maps and the save; `data.json` passes |
| alpha to beta | the Briar Maze and the slug queen, the moth, fair maps, a bot that finishes the campaign, juice for placements, kills and leaks, French with a settings screen | `playthrough.json`, `juice.json` and the `settings` flow of the whole game, hidden; hidden tests of French and of three fair maps |
| beta to release | export presets for Linux and Web, store art, credits, German, version 1.0.0 | `kit`: `doctor`, `export -Preset Linux -Run`, `credits` |

## Rules for writing it

- Each stage must be green under `pwsh ci/godot/hyperdot.ps1 test -Project <stage>` and `doctor` without FAIL; `tests/
  Test-GameProgramme.ps1 -Genre towerdefence -Language <lang>` builds every stage and checks every task.
- Hidden tests and flows sit in `hidden/`, named for their task; they are copied into the game only when it is graded.
- Waves, pests and the bot change together: `test_balance.gd` holds every map to being cleared by the bot and lost
  without towers.
- Keep the game small: about 1,900 lines of game code per language, a test run under a minute, a playthrough under 3
  minutes of game time.
- Comment like the rest of the kit: say why, not what.

## As built

Choices made in the GDScript build where the design was open. The C# port follows them.

- **The battle lives in Battle, not in nodes.** The game node feeds it ticks and input and draws it from its state and
  signals; it never decides. So the rules, the bot and the balance tests play whole maps in about a tenth of a second
  each, without a scene.
- **One A* search per pest per placement, none per tick.** A spawning pest copies the map's route; a placement or a
  sale re-paths every pest from the cell it is heading to; targeting reads `remaining()`, which the pest knows from its
  own path. That keeps `path_queries` at zero between placements, which is what the fix-performance task's hidden test
  reads, and the C# port must count the same searches.
- **A pest never walks into a tower: it waits.** With re-pathing at every placement it never has to, which is why a
  missing re-path shows as pests standing in front of a new tower (the alpha fix-bug) rather than walking through it.
  Such a pest is shot where it stands, so the defect makes the game easier, not unfinishable; the fix-playthrough
  defect is a balance one instead.
- **The never-block rule checks the pests too.** A tower is refused when it leaves the gate or the cell any pest is
  heading to without a way; a cell a pest stands on or heads to cannot be built on at all. The prototype fix-bug's
  report names both, and its hidden test has a pest in a corner.
- **The bot builds a maze.** It scores each candidate cell by the route the tower would leave, so towers on the route
  lengthen it; it calls each wave as soon as it cannot buy anything, which keeps a bot run near 110 s of game time at
  three ticks a frame. Waves were tuned so that it leaks in the early waves of each map (the juice run needs a leak in
  its first 1800 frames) and clears every map with seeds 1-10 in a sweep.
- **The slug queen takes all 20 seeds.** At her designed 1170 hp the bot always stops her; at ten times that she always
  gets through and one leak loses the map, so the bot replays the Briar Maze until the playthrough's frames run out.
- **Store art** is rendered by the game under Xvfb: five 1920x1080 screenshots of real screens and bot battles, and
  the capsules cut from a capture of the field without the HUD, with the title as a Label. The 600x800 capsule of the
  fix-store defect is a crop of the real one.
- **The HUD keeps 140 px from the screen's sides** so the `layout` runner's phone safe area holds it, and every button
  is 84 px tall (48 dp on a phone); the field (cells of 54 px) fits between.
- **Decoys:** fix-bug (prototype, alpha, beta), fix-playthrough and fill-translations. The alpha fix-bug decoy, a pest
  that re-paths when it reaches the tower, does get every pest to the store; it fails because the pests walk up to the
  tower first, which the hidden test sees in their paths right after the placement.
