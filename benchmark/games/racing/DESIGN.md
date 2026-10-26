# Racing game: Cinderloop

The eighth genre of the staged game programme (`benchmark/PLAN.md`): the one that exercises input, physics, the camera
and frame pacing. A car runs on a fixed physics step whose rates are all per second, so a lap takes the same time at any
tick rate (`godot-math`, `godot-determinism`); laps are counted by gates crossed in order; the best lap is kept as a
ghost of quantised inputs that drives the lap again exactly; AI rivals follow the racing line; a chase camera eases the
same at any frame rate; keys are rebindable while the gamepad keeps working (`godot-input`); and the save keeps best
laps, ghosts and keys (`godot-saves`). One game, written twice: `gdscript/` (built) and `csharp/` (to come, from this
design). Both behave the same, use the same data files, scene tree, node names and log lines, and pass the same flows.
Only the code and the test framework differ: GUT for GDScript, gdUnit4 (run by the kit's `gdunit4` runner) for C#.

Everything here is made up for the benchmark: the name, the tracks, the rivals. The cars, roads and ground are drawn in
code, the sounds come from the kit's `sfx` command, and the store art is captured from the game and cut with ffmpeg.
Nothing comes from a real game.

## The game

Seen from above, four little cars race on loops of cinder road: the player's and three rivals'. The player starts at
the back of the grid. Each track is a few laps; a place in the top two opens the next track, and the top two on the
third, Caldera Hairpins, is victory. The ghost of the best lap on each track drives alongside.

### The contract the C# port keeps

**Car** (`scripts/car.gd` `Car`, engine-light): `position` (Vector2, pixels, y down), `heading` (radians, 0 along +x),
`speed` (pixels a second along the heading, negative in reverse), `on_road`, `index` (the track segment it is on).
`step(throttle, steer, dt, road)`, throttle and steer clamped to -1..1, in this order:

1. Turn: nothing below 0.001 px/s; otherwise `rate = TURN_RATE * min(|speed| / TURN_SPEED, 1)`, then
   `rate = min(rate, GRIP / |speed|)`, and `heading = wrap(heading + steer * rate * sign(speed) * dt, -PI, PI)`.
2. Throttle 0 or more, or a car standing or reversing: `speed += push * dt`, push `ACCEL * throttle` (throttle >= 0)
   or `REVERSE_ACCEL * throttle`. Braking a car moving forward: `speed = max(speed + BRAKE * throttle * dt, 0)`.
3. Drag, implicitly: `speed /= 1 + drag * dt`, drag `DRAG` on the road and `GRASS_DRAG` off it; then
   `speed = max(speed, -REVERSE_MAX)`.
4. `position += forward * speed * dt`.

| Constant | Value | | Constant | Value |
|---|---:|---|---|---:|
| `ACCEL` | 640 | | `REVERSE_MAX` | 160 |
| `DRAG` | 0.8 | | `TURN_RATE` | 2.6 |
| `GRASS_DRAG` | 3.2 | | `TURN_SPEED` | 140 |
| `BRAKE` | 1000 | | `GRIP` | 1300 |
| `REVERSE_ACCEL` | 320 | | | |

Top speed is exactly `ACCEL / DRAG` (800 px/s) at every tick rate. No `exp()`: it comes from each OS's C library, and
`architecture.json` marks `scripts` as simulation code (`nondeterministic-sim` an error).

**Track** (`Track.from_row`): the control points of a row of `data/tracks.json` (`id`, `name` a translation key,
`laps`, `width`, `points`, `checkpoints`, indices of control points) become a closed uniform Catmull-Rom path, `SUB` (10)
points a segment; `lengths` is the distance to each point. Gate g is at dense point `checkpoints[g] * SUB`, across the
road and `GATE_MARGIN` (40) past each edge; gate 0 is the start line. `crosses_gate(g, from, to)`: the move crosses the
gate's segment and goes along the track's tangent there. `nearest(position, hint)`: with a hint, the segments from 3
behind to 8 ahead, unless the best of them is further than the road's width, then the whole loop; `lookups` counts
segments examined. `is_on_road`: within `width / 2` of the nearest segment. `speed_profile`: per point, the bend's limit
`min(sqrt(GRIP * r), r * TURN_RATE) * 0.92` (r the radius through the points 2 either side), then two passes backwards
round the loop with `v[i] = min(v[i], sqrt(v[i+1]^2 + 2 * 700 * ds))`. `grid_slot(k)`: 60 + 70 * (k / 2) pixels behind
the line along the path, a quarter of the width left (even k) or right.

**Laps** (`LapTracker`): `next_gate` (0 at the start), `armed`, `laps`, `lap_start_tick`, `lap_times` (ticks),
`best_lap` (-1 before the first). `update(track, from, to, tick)`: only `next_gate` is tested. A checkpoint advances
`next_gate`. The start line, the first time, only arms it; after the last checkpoint it completes a lap
(time `tick - lap_start_tick`, so lap 1 is timed from the start) and `next_gate` becomes 1. `gates_passed`: 0 unarmed,
`next_gate`, or the gate count when `next_gate` is 0.

**AI** (`AiDriver`, `pace`, `line_offset`): aims at the point `70 + 0.3 * speed` pixels ahead along the path, moved
`line_offset` to the right; `steer = clamp(angle_difference(heading, aim) * 2.4, -1, 1)`; the limit is the lowest
`speed_profile` over the next half second of travel times `pace`; throttle `pace`, 0 above the limit, -1 more than 40
over it.

**Race** (`Race.new(track, drivers, rate)`): car 0 is the player's (driver null: `step(input)` gives its input) on the
last grid slot, the others in order from slot 0. `step(input)`: `tick += 1`; for each car in order, its input (driver
or given), each part quantised to hundredths (`Ghost.quantize`), car 0's recorded into `ghost`, `step` with
`is_on_road` at its old position, `index = nearest(position, index)`, then its tracker; a lap of car 0 makes its ghost
`best_ghost` when faster and starts a new one from the car's state; a car with the track's laps joins `finish_order`.
Signals `lap_completed(car, lap, ticks)`, `car_finished(car, place)`. `standings()`: the flag in its order, then laps,
gates passed, the distance along the path to the next gate, the index; `position_of(i)` is 1-based.

**Ghost**: `start` (position, heading, speed), `rate`, `throttles` and `steers` as integer hundredths; `drive(car, tick,
track)` steps a car by one recorded tick; `replay(track)` returns the positions; `to_dict` / `from_dict`
(`{"rate", "start": {"x", "y", "heading", "speed"}, "throttle": [...], "steer": [...]}`, null when damaged). A ghost
plays only at its own rate.

**Tracks and rivals** (`Tracks`): `data/rivals.json` rows `id`, `color`, `pace`, `line`. `drivers_for(n, seed, bot)`:
the player's (null, or `AiDriver.new()` for the bot), then n rivals, the data's in turn, shuffled by a
`RandomNumberGenerator` seeded with the race seed (Fisher-Yates from the last down, `randi_range(0, i)`).

| Track | Name (key) | Laps | Width | Checkpoints | Bot alone, both or all laps |
|---:|---|---:|---:|---|---:|
| 1 | Ashfall Oval (`TRACK_1`) | 3 | 150 | 1, 4, 7, 10 | 27.8 s |
| 2 | Ember Esses (`TRACK_2`) | 2 | 140 | 1, 4, 6, 8, 10 | 21.8 s |
| 3 | Caldera Hairpins (`TRACK_3`) | 2 | 140 | 1, 4, 8, 11, 14, 17 | 37.8 s |

| Rival | Colour | Pace | Line |
|---:|---|---:|---:|
| 1 | `#e4572e` | 0.95 | -18 |
| 2 | `#4c9f70` | 0.92 | 16 |
| 3 | `#7b6ccf` | 0.89 | 0 |

**Controls**: actions `accelerate` (W, right trigger, A), `brake` (S, left trigger, B), `steer_left` (A, left stick
left, d-pad left), `steer_right` (D, stick right, d-pad right), `pause` (Escape, Start). `Controls.rebind(action, key)`
replaces only the keyboard binding of the four driving actions, by physical key; `to_dict` gives key names
(`{"brake": "K"}`), `apply` skips unknown actions and keys, `reset` reloads the project's map.

**Saves** (`SaveStore`): `user://save.json`, version 2: `unlocked`, `best` (track id as text -> lap in milliseconds),
`ghosts` (track id -> `Ghost.to_dict`), `settings` (`volume`, `locale`), `controls`. Written beside and renamed over.
Version 1 (a file without a version too) was `{"version": 1, "best": {"<id>": seconds}}`: each time becomes
milliseconds, and `unlocked` the highest id with a time plus one. `record_lap(data, id, ms, ghost)` keeps a lap that
beats the best.

**Scenes and nodes**:

- `res://main.tscn`: root `Main` (Control) with `Menu/Title`, `StartButton` (opens `TrackSelect`), `SettingsButton`,
  `CreditsButton`, `QuitButton`, `VersionLabel`. Screens are children of Main: `TrackSelect`
  (`res://ui/track_select.tscn`, `Box/Grid/Track<N>Button`, `Box/BackButton`), `Game`, `Settings`
  (`Box/VolumeSlider`, `Box/Languages/<Locale>Button`, `Box/Controls/<Action>Label` and `<Action>Button`, e.g.
  `AccelerateButton`, `Box/BackButton`; `capture_key(keycode)` after a key button), `Credits`, `Victory`.
- `res://game/game.tscn`: root `Game` (Node2D) with `Track`, `Ghost` (a car drawn as an outline), `Cars` (`Car0`...),
  `Camera` (`ChaseCamera`, zoom 0.8), `SfxGo`, `SfxLap`, `SfxPass`, `HUD` (CanvasLayer: `Flash`, `TrackLabel`,
  `LapLabel`, `PositionLabel`, `TimeLabel`, `BestLabel`, `CountdownLabel`, `PauseButton`), `PauseMenu` (`Title`,
  `ResumeButton`, `RestartButton`, `QuitButton`) and `ResultMenu` (`Box/Title`, `Box/PlaceLabel`, `Box/TimeLabel`,
  `Box/NextButton`, `Box/RetryButton`, `Box/MenuButton`).
- The game's API: properties `track`, `state` (`countdown`, `racing`, `finished`), `race`, `place`, `lap`, `camera`;
  methods `start_track(id, seed = -1)`, `restart()`, `next_track()`; signals `race_finished(track, place, best_ms,
  ghost)`, `finished(victory)`, `menu_requested`.

**The camera** (`ChaseCamera.follow(target, velocity, delta)`, every drawn frame, with the car's position interpolated
between ticks): look-ahead `velocity * 0.35` (at most 220 px) eased at 3 a second, the focus eased towards car plus
look-ahead at 6 a second, both `1 - exp(-rate * delta)`; then the car is held within `MAX_LAG` (240 px) of the focus.
`reset_to(target)` jumps.

**Pacing** (60 physics ticks, physics interpolation on, all game logic in `_physics_process`): a 3 s countdown, the
result 1 s after the player's flag (a bot run then goes on: the next track, or the same one again with the next seed
below the top two). The player's car drives on at pace 0.6 after the flag.

**Command-line arguments**, after `--`: `--autoplay` (a full-pace AI drives the player's car from the main scene, track
after track from `--track`), `--seed=N` (race n of the run, counted from 1, has seed `N * 1009 + n`; without it,
`randi() % 1000000`), `--no-save`, `--track=N`, `--rivals=N` (0 to 31; more than three repeats them, for stress runs).

**Log lines** (print): `[Run] track N, seed S` at a race's start, `[Run] track N lap L <seconds>` for the player's laps,
`[Run] track N finished P<place> <seconds>`, `[Run] victory`; for `juice`, in game time, `[juice] event
race_start|position_gained|lap_completed <ms>` and `[juice] feedback flash|sfx|pop <ms>`.

## The release candidate (the whole game, `game/`)

| Part | Files |
|---|---|
| Tests | GDScript: `test/unit/test_*.gd` (GUT), 69 tests: the car's handling (`test_car.gd`, at 30 and 120 ticks too), the track, laps, the AI on every track, the race, standings, the ghost, saves, controls, launch options, the camera and the race scene. C#: `test/*Test.cs` (gdUnit4) |
| Flows | `test/flows/start.flow.json` (menu, track select, track 1), `select.flow.json` (Back), `pause.flow.json` (pause, resume, restart), `settings.flow.json` (French and back), `controls.flow.json` (a key rebound, Escape keeping it, back to W) |
| Data | `data/tracks.json`, `data/rivals.json`; `data.json` |
| Bot runs | `playthrough.json`: `--autoplay --seed=1 --no-save`, the three tracks finished (track 1 in first place) and `[Run] victory` within 7800 frames (it takes about 6000). `juice.json`: 1500 frames; race_start gets flash and sfx, position_gained and lap_completed pop and sfx, each within 100 ms |
| Text | `i18n/strings.csv` (keys, `en`, `fr`, `de`), every visible text through `tr()`; `textsize.json` (menu, race, track select, settings at 1280x800); `layout.json` (menu, race and track select on `phone_landscape` and `ultrawide`) |
| Architecture | `architecture.json`: `parent-path`, `per-frame-lookup` and `nondeterministic-sim` are errors; `simulation` is `scripts` |
| Assets | sounds in `sounds/sfx/` from `hyperdot.ps1 sfx -Sound blip,powerup,coin -Seed 9`; `assets.json` with each source and licence |
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
| prototype | Car, Track, LapTracker, AiDriver, Race without standings, Ghost (recorded, not shown), Ashfall Oval, three rivals, the chase camera; `game/game.tscn` is the main scene (an overlay: no menus, plain English, the race starts again after the flag); 31 tests | menus, track 2-3, standings, pause, results, saves, controls screen, launch options, sounds, juice, the bot, translations, data checks, `test_car.gd`, store, export, plan |
| alpha | menus, track select, pause and restart, results, tracks 1-2, standings, the ghost shown and saved, SaveStore (version 2 only), settings with volume and keys, juice and sounds, flows `start`, `select`, `pause`, `controls`, `data.json`, `architecture.json`, `plan.json` at the alpha gate, English | track 3, the bot, French and German, the settings flow, text size and layout checks, store, export, credits |
| beta | all three tracks, the bot, `playthrough.json`, `juice.json`, English and French, the settings flow, SaveStore version 1 migration; `test_car.gd` without its tick-rate test | store, export presets, credits, German |
| release | everything | nothing |

## The tasks

For each stage, in the order the tiers take them (the min and mid tiers take the first two). Each task has a
**reference** solution, `solutions/<stage>/<template>/` (whole files laid over the game, plus `answer.md` when the
answer is graded), and some a **decoy**, `solutions/<stage>/<template>-decoy/`, a tempting wrong fix.
`tests/Test-GameProgramme.ps1 -Genre racing` plants each defect and checks that the untouched game fails, the reference
passes and the decoy fails.

The six defects of this genre: a lap that counts when a checkpoint is skipped (prototype fix-bug), the camera easing
by frame (alpha fix-bug), physics that depends on the tick rate (beta fix-playthrough), per-tick work that grows with
every rival (beta fix-performance), a ghost that drifts from its recording (beta fix-bug) and keys that are lost on
restart (beta fix-flow). Each is graded by a measured or hidden behaviour, not only by the visible suite.

### Prototype

| # | Template | Defect planted (`edits`) | Graded by |
|---|---|---|---|
| 1 | `fix-bug` | LapTracker takes any later gate a car crosses ("a car can miss a gate at speed"), so the infield is a shortcut | a hidden test: a skipped gate makes no lap (each in turn), going back for it does, gates out of order and a lap driven backwards make none, a drive across Ashfall Oval's infield makes none, a lap on the road does; `test_lap_tracker.gd` `unchanged`. Decoy: the checkpoints kept as a set, in any order |
| 2 | `write-tests` | none; `{file}` is `test/unit/test_car.gd` (removed from the stage) | 8 mutants of Car: throttle all or nothing, braking into reverse, reverse unlimited, a slow car at full lock, reversing turning the same way, no grip limit, the grass as fast as the road, drag per tick (only a test at another tick rate sees it); `car.gd` `unchanged` |
| 3 | `add-feature` | none (standings removed from the stage); `{feature}`: `Race.standings()` and `position_of` | a hidden test (the grid, laps, gates, distance to the next gate, level cars by index, the flag first, a real race ending in its finish order) |
| 4 | `explain-failure` | the best lap kept when slower (`time > best_lap`) | the answer names `test_the_best_lap_is_the_fastest`, `test_lap_tracker.gd` line 59, 300 and 600 (number terms that `Godot 4.7.2` in the prompt cannot satisfy); nothing `unchanged` may change |

### Alpha

| # | Template | Defect | Graded by |
|---|---|---|---|
| 1 | `fix-bug` | the camera eases by `rate * delta` (look-ahead and focus) instead of `1 - exp(-rate * delta)`: it trails differently at 30 and 144 fps and overshoots the car on a long frame | a hidden test: after a 200 px jump the view is as far behind at 30 and 144 fps as at 60 (0.5 px, at 1/3 and 1/2 s), a 0.1-0.5 s frame never reaches or passes the car, one frame covers less than half (not bolted on), it looks ahead at speed, and a hairpin flat out with hitches keeps the car on screen at 20, 60 and 144 fps; `test_camera.gd` `unchanged`. Decoy: the linear weights clamped to 1 |
| 2 | `add-content` | none; `{content}`: track 3, Caldera Hairpins, 2 laps, 120-200 px wide, six checkpoints or more, two hairpins under 250 px/s, finished alone in 30-70 s | `data`; a hidden test (name, laps, width, checkpoints in order, clearance, hairpins, a driver finishing on the road in time); a hidden flow starting track 3 |
| 3 | `migrate-save` | none, SaveStore reads only version 2; `{report}`: best laps gone and track 2 locked after updating | a hidden test loading version 1 (seconds to milliseconds, open tracks), a file without a version, a version 2 file, and the migrated save written as version 2 |
| 4 | `fix-architecture` | the lap counter set by `Car0`'s view with `get_node("../../HUD/LapLabel")` every frame, and no longer by the game | the architecture runner (errors); a hidden test that the counter follows a lap, a restart and a new track, also with the cars' views not processing |

### Beta

| # | Template | Defect | Graded by |
|---|---|---|---|
| 1 | `fix-playthrough` | physics raised to 120 ticks, and Car's drag per tick from `TICK := 1.0 / 60.0`, so the cars crawl and the bot runs out of frames on track 3 | `playthrough`; `match` on `physics_ticks_per_second=120`; a hidden test: top speed `ACCEL / DRAG` at 30, 60, 120 and 144 ticks, races on tracks 1 and 3 taking the same time at each within 1.5%, Ashfall Oval in 26-30 s. Decoy: `TICK := 1.0 / 120.0` |
| 2 | `fix-performance` | `Track.nearest` searches the whole loop every time (no hint), for every car every tick | a hidden test reading `Track.lookups`: under 24 segment checks a car a tick with 12 cars on Caldera Hairpins (its loop has 190); every car's segment the one a full search finds, every tick of a race of 8; a car across the grass and dropped elsewhere found again; ghosts still replay |
| 3 | `fix-bug` | Race no longer quantises the inputs before the cars use them; the ghost keeps hundredths, so its replay drifts from an analog lap | a hidden test: an analog driver's opening lap and best flying lap, saved and loaded through SaveStore, replay within 0.01 px every tick, and the replay crosses the line on the lap's tick; `test_ghost.gd` `unchanged` (it drives on the keys, which hundredths hold exactly). Decoy: only the steering quantised |
| 4 | `fix-flow` | `SaveStore.write` leaves `controls` out | a hidden test: rebound keys saved, the map reset, the save read back and applied as Main does, the keys back and the gamepad still bound; the other settings kept; the flows |
| 5 | `add-feedback` | overtaking plays no sound | `juice` |
| 6 | `fill-translations` | the result panel's title, place and Next keys are empty in `fr` | `l10n`; the panel's script and the scene `unchanged`. Decoy: the keys deleted |

### Release

| # | Template | Defect | Graded by |
|---|---|---|---|
| 1 | `fix-export` | the Linux preset excludes `data/*` | `kit`: `export -Preset Linux -Run` |
| 2 | `fix-store` | `library_capsule` is 600x800 (a `copy` edit lays `defects/library_capsule_600x800.png` over it), and the track data's entry in `assets.json` has no licence | `kit`: `doctor` (no FAIL) and `credits`; a hidden check that the capsule is 600x900 |
| 3 | `cut-version` | none; `{version}` 1.1.0, `{details}`: the project, a `CHANGELOG.md` entry, the menu | `match` on `project.godot` and `CHANGELOG.md`; a hidden flow reading the menu's version label |

### Milestones

Each is the next stage's `milestone` entry. It runs on the earlier stage and is graded by these hidden acceptance files.
Its reference is every file of the next stage that the earlier one lacks or has otherwise.

| From, to | `{goal}` | Accepted by |
|---|---|---|
| prototype to alpha | a menu, a track select, pause with restart, track 2, `data.json`, a save of the best laps and the open tracks | hidden flows `start`, `select` and `pause`; a hidden test of two tracks and the save; `data.json` passes |
| alpha to beta | track 3, a bot that wins the championship from the back of the grid, juice for the start, overtakes and laps, French with a settings screen | `playthrough.json`, `juice.json` and the `settings` flow of the whole game, hidden; hidden tests of French and of three tracks the bot wins |
| beta to release | export presets for Linux and Web, store art, credits, German, version 1.0.0 | `kit`: `doctor`, `export -Preset Linux -Run`, `credits` |

## Rules for writing it

- Each stage must be green under `pwsh ci/godot/hyperdot.ps1 test -Project <stage>` and `doctor` without FAIL; `tests/
  Test-GameProgramme.ps1 -Genre racing -Language <lang>` builds every stage and checks every task.
- Hidden tests and flows sit in `hidden/`, named for their task; they are copied into the game only when it is graded.
- A test that counts frames counts them from the tick rate, because the fix-playthrough task grades the game at 120
  ticks a second.
- Keep the game small: about 1,500 lines of game code per language, a test run under a minute, a playthrough under 3
  minutes of game time.
- Comment like the rest of the kit: say why, not what.

## As built

Choices made in the GDScript build where the design was open. The C# port follows them.

- **2D from above**, cars and roads drawn in code (`CarView`, `track_view.gd`); the ground's cinders come from a fixed
  seed in the view, outside the simulation.
- **The race lives in plain classes** (Car, Track, LapTracker, AiDriver, Race, Ghost). The game node counts down, reads
  the input, steps the race once a tick and draws it, so the tests run whole races in milliseconds without a scene.
- **No walls and no contact between cars.** Off the road is ash, with four times the drag, so a shortcut is something a
  car can physically take and only the gates refuse; the cars pass through each other, which keeps the race
  deterministic and ordered by index (contact is in the tech debt).
- **Drag is implicit** (`speed / (1 + drag * dt)`), not `exp()`: the architecture rule flags `exp()` in simulation code,
  and the implicit form gives the same top speed at every tick rate. Laps of the same driver differ by under 0.1 s
  between 30 and 144 ticks; the planted per-tick drag halves the top speed at 120.
- **Inputs are quantised in Race**, before any car uses them, not in the input code: the bot, the rivals and the
  player all go through it, and the ghost stores the same hundredths. A keyboard lap is exact either way, which is why
  the visible ghost test drives on the keys and the hidden one with analog inputs.
- **Lap 1 is timed from the green light**, the grid being behind the line; the first crossing of the line only arms
  the tracker. The best lap is usually lap 2 or 3, a flying one, and its ghost starts on the line.
- **The camera follows in `_process`** with the car's position interpolated between ticks by
  `Engine.get_physics_interpolation_fraction()` (Godot has no interpolated transform for 2D nodes); `ChaseCamera` sets
  `process_callback` to physics itself, as physics interpolation would force it, so Godot does not warn. Its `MAX_LAG`
  is a guarantee rather than something the game reaches: at 800 px/s the look-ahead keeps the car within about 180 px.
- **The ghost to chase** is the saved best lap of the track, replaced as soon as the race has a faster one; on its own
  (a flow or a test) the game shows this race's best after the first lap.
- **The settings screen holds the keys.** Its key buttons wait for the next key in `_input` and call `capture_key`,
  which the controls flow calls directly, since a flow cannot press a key. The beta's fix-flow task is that screen's
  keys being lost, graded by a hidden test, not a disconnected button.
- **The fix-performance defect removes the hint mechanism** (the search window and its fall-back), not just its use,
  so the fix is the windowed search itself; the hidden test compares every car with a full search, a car across the
  grass included, which a window without a fall-back gets wrong.
- **The beta drops the visible tick-rate test** of `test_car.gd`, so the planted tick-rate defect is found from the
  bot's run, not from a failing test; the release has it again.
- **Store art** is captured under Xvfb at 1920x1080 (four races and the menu) and a hero shot without the HUD; the
  capsules are cut from it with ffmpeg and the title drawn in DejaVu Sans Bold. The 600x800 capsule of the fix-store
  defect is a crop of the real one.
- **Flows wait for a state, not a count of ticks** (`pause.flow.json` waits until the race is on), because the
  fix-playthrough task runs the game at 120 ticks a second, where the countdown takes twice as many.
- **A hidden test stops at a missing track** rather than racing on it: an empty track has no road to search, and the
  untouched games of add-content and the milestones must fail quickly, not run to the kit's time limit.
- **Decoys:** fix-bug (all three stages), fix-playthrough and fill-translations.
