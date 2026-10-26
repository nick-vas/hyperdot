# Idle game: Duskhive

The fifth genre of the staged game programme (`benchmark/PLAN.md`): the one that exercises an economy in data, saves
that last for months and survive updates, and a portrait layout for phones and the Web. Producers are bought at prices
that grow geometrically and the numbers are JSON checked by the `data` runner (`godot-data`, `godot-progression`), glow
grows past 2^53 and is printed readably (`godot-math`), time away is paid from the saved clock and a clock set back pays
nothing (`godot-saves`), saves of the previous version keep their prestige, and the screens fit a notched portrait
phone, a tablet and a desktop browser in every language (`godot-mobile-web`, `godot-localization`). One game, written
twice: `gdscript/` and `csharp/` (ported from this design), both built. Both behave the same, use the same data files,
scene tree, node names and log lines, and pass the same flows. Only the code and the test framework differ: GUT for
GDScript, gdUnit4 (run by the kit's `gdunit4` runner) for C#.

Everything here is made up for the benchmark: the name, the hive, the producers and upgrades. The sky and its motes are
drawn in code, the icon is a PNG drawn by a script, the sounds come from the kit's `sfx` command, and the store art is
rendered from the game. Nothing comes from a real game.

## The game

A hive of moths gathers glow at dusk. The player presses Gather for the first few motes of glow, then buys producers
that make glow every second: each one bought makes the next of its kind dearer. Upgrades double a producer, Gather or
everything. Once a run has earned a million glow, the player can greet the dawn: the hive sleeps through the day, glow,
producers and upgrades are gone, and embers stay, each adding 10% to all production for good. The game keeps running
while closed: on return, the time away is paid, up to eight hours.

### The contract the C# port keeps

**Numbers** (`scripts/numbers.gd` `Numbers`): every amount is a double. Up to 2^53 it is exact; past it the game keeps
16 significant digits and allows a relative error of `TOLERANCE` (1e-12) between, say, one long tick and many short
ones, which is far below the three digits the screen shows. Glow stops at `MAX` (1e300), never reaching infinity.
`format(x)`: `0` for nothing, whole numbers below 10 with one decimal when there is one (`0.5`, `7`), whole numbers below
1000, then three significant digits **rounded down** and a suffix per thousand: `K M B T Qa Qi Sx Sp Oc No Dc`, then
two letters `aa` (1e36), `ab` ... `az`, `ba` (1e114) ... Never scientific notation. 1000^k is parsed from its decimal
text (so 1e33 is exactly 1.00Dc), and `power(base, n)` multiplies a whole power out by squaring: nothing in `scripts/`
calls `pow()` or `log()`, whose last bit can differ between machines (`architecture.json`: `nondeterministic-sim`).
`format_rate(x)` is `format(x)` and `/s`; `close(a, b, tolerance)` compares relatively.

**Data** (`Catalog`, all three files JSON arrays checked by `data.json`):

| Producer | Name key | Cost | Growth | Glow/s | Pays back in |
|---|---|---:|---:|---:|---:|
| `wick_moth` | `PRODUCER_WICK_MOTH` | 10 | 1.15 | 0.5 | 20 s |
| `glow_snail` | `PRODUCER_GLOW_SNAIL` | 120 | 1.15 | 4 | 30 s |
| `firefly_choir` | `PRODUCER_FIREFLY_CHOIR` | 1,500 | 1.14 | 30 | 50 s |
| `moon_lily` | `PRODUCER_MOON_LILY` | 20,000 | 1.13 | 220 | 91 s |
| `star_loom` | `PRODUCER_STAR_LOOM` | 300,000 | 1.12 | 1,800 | 167 s |

| Upgrade | Target | Times | Cost | Needs |
|---|---|---:|---:|---:|
| `twin_wicks` | `wick_moth` | 2 | 150 | 10 |
| `warm_hands` | `tap` (Gather) | 5 | 300 | 0 |
| `silver_trails` | `glow_snail` | 2 | 2,000 | 10 |
| `choir_harmony` | `firefly_choir` | 2 | 25,000 | 10 |
| `night_dew` | `moon_lily` | 2 | 300,000 | 10 |
| `dusk_bloom` | `all` producers | 1.5 | 1,000,000 | 50 owned in all |
| `star_thread` | `star_loom` | 2 | 5,000,000 | 10 |

`data/economy.json` (rows `{ id, value, note }`): `tap` 1, `milestone_every` 25, `milestone_multiplier` 2,
`dawn_base` 1,000,000, `ember_bonus` 0.1, `offline_cap_seconds` 28,800, `autosave_seconds` 30. A missing producers or
economy file is an error (`push_error`); a missing upgrades file is an empty table (the prototype has none).

**The economy** (engine-light, `scripts/economy.gd` `Economy`, signals `bought(id, amount)`, `upgraded(id)`,
`dawned(embers)`):

- State: `glow`, `run_earned` (glow earned since the last dawn, spent or not), `total_earned` (all runs), `owned` (id ->
  count), `upgrades` (id -> true, this run), `embers`, `dawns`, and `rate_computations`, a counter of how often the rate
  was worked out from scratch.
- `cost(id, amount = 1)`: with `n` owned, `cost * growth^n` for one, and for several the sum of their single prices,
  `cost * (growth^(n + amount) - growth^n) / (growth - 1)`.
- `max_affordable(id)`: the largest k with `cost(id, k) <= glow` (0 when not even one), exact at a price boundary and
  with any amount of glow (doubling, then halving the gap); `buy(id, amount)` and `buy_max(id)` spend and add.
- `multiplier(id)`: the bought upgrades that target it (and `all`, for producers), times `milestone_multiplier` for
  every `milestone_every` owned. `ember_multiplier()` is `1 + embers * ember_bonus`.
- `rate()` and `producer_rate(id)`: each producer's `rate * owned * multiplier * ember_multiplier`. Worked out once per
  change (a purchase, an upgrade, a dawn, a load) and kept, so a tick costs the same however much is owned.
- `tick(seconds)` earns `rate() * seconds`; `tap()` earns `tap * multiplier("tap")`; `earn(x)` adds to glow,
  `run_earned` and `total_earned`.
- `dawn_gain()` is `floor(sqrt(run_earned / dawn_base))`; `dawn()` (with a gain of at least 1) adds it to embers, counts
  the dawn and empties glow, `run_earned`, producers and upgrades.
- `to_dict()` / `Economy.from_dict(catalog, data)`: `glow`, `run_earned`, `total_earned`, `owned`, `upgrades` (ids) and
  `prestige` (`embers`, `dawns`); anything missing or not a number starts at zero.

**Time away** (`scripts/offline.gd` `Offline`, given the time; nothing in `scripts/` reads the clock):
`seconds_away(saved_at, now, cap) = clamp(now - saved_at, 0, cap)`; `seen_at(saved_at, now) = max(saved_at, now)`,
the time the next save keeps, so a clock set back cannot move it back and a clock put right does not pay twice;
`apply(economy, saved_at, now)` ticks the economy for the seconds away and returns `{ seconds, glow }`.

**Saves** (`SaveStore`): `user://save.json` with `version` 3, `economy` (`to_dict()`), `saved_at` (Unix seconds, the
latest the game has seen) and `settings` (`volume`, `locale`), written with full precision (glow past 2^53 comes back as
the same double) and synced to IndexedDB on the Web. Version 2 (the 0.x releases; also a file without a version) kept
`embers` and `dawns` at the top level, beside the economy: they move into `economy.prestige`. Main saves every 30 real
seconds, after a dawn, when the settings close, and on close, on pause (phones) and on focus loss (a browser tab).

**The bot** (`scripts/bot.gd` `Bot`): `next_action(economy)` returns `{ kind, id }`: `dawn` once a dawn would give at
least as many embers as there are (the first at 1), else `upgrade` (the first in data order it can pay for), else
`buy` the producer with the shortest payback (`cost(id) / unit_rate(id)`) when it can pay for it, else `gather` while
nothing is owned, else `wait`. `act(economy)` does it. One action per tick.

**Scenes and nodes**:

- `res://main.tscn`: root `Main` (Control, `ui/main.gd`) with the hive as its child `Game`, and the screen over it:
  `Settings` (`res://ui/settings.tscn`: `Safe/Box/Title`, `VolumeLabel`, `VolumeSlider`, `LanguageLabel`,
  `Languages/<Locale>Button` per language loaded, `CreditsButton`, `BackButton`, `VersionLabel`) or `Credits`
  (`res://ui/credits.tscn`: `Safe/Box/Title`, `Text`, `BackButton`, back to the settings). The hive is hidden under a
  screen. Main's API: `save_path` and `clock` (a Callable returning Unix seconds), both set before it enters the tree,
  `save_now()`, `game`, `seen_at`.
- `res://game/game.tscn`: root `Game` (Control) with `Sky` (drawn motes), `Safe` (a MarginContainer kept inside the
  `SafeArea` autoload's rectangle) / `Column` with `Top/GlowLabel` (`%s glow`), `Top/RateLabel`, `Top/EmbersLabel`
  (`Embers: N (+P% glow)`), `GatherButton`, `Header/PageTitle`, `Header/BuyModeButton`, `ProducerPage/List` with a row
  per producer (`<Id in PascalCase>Row`, a `ProducerRow`: `Box/Info/NameLabel`, `Box/Info/DetailLabel` (`N owned ·
  rate`), `Box/BuyButton` (`Buy N` and the price)), `UpgradePage/List` with an `UpgradeRow` per upgrade (shown once
  unlocked, hidden once bought), and `Bar` (`ProducersTab`, `UpgradesTab`, `DawnButton`, `SettingsButton`); then
  `Flash`, `WelcomePanel/Box` (`Title`, `MessageLabel`, `CollectButton`), `DawnPanel/Box` (`Title`, `MessageLabel`,
  `ConfirmButton`, `CancelButton`), and `SfxBuy`, `SfxUpgrade`, `SfxDawn`, `SfxGather` on the `Sfx` bus.
- The game's API: `economy`, `buy_mode` (1, 10 or 0 for as many as the glow pays for), `page` (`producers` or
  `upgrades`), `setup(catalog, options, saved)`, `restore(saved)`, `gather()`, `buy(id)`, `buy_upgrade(id)`,
  `next_mode()`, `show_page(which)`, `ask_dawn()`, `confirm_dawn()`, `show_welcome(seconds, glow)`, `add_glow(amount)`
  (for tests and flows); signals `dawned`, `settings_requested`, `finished`.
- Input: Gather is the `gather` action (G, the gamepad's X) and a button; everything else is buttons.

**Layout**: designed at 720x1280 portrait (`canvas_items`, `expand`, `handheld/orientation` portrait), every button at
least 88 px of canvas (48 dp on a 420 dpi phone), the bar's buttons wrapping long words. `layout.json` checks
`phone_portrait`, a portrait tablet (`1536x2048@264` with insets), `tablet` and `ultrawide` (a desktop browser);
`textsize.json` checks 720x1280 and 1280x800 (the smallest font, 22 px, is 13.75 px there). A landscape phone is not a
target: a portrait UI scaled to its 1080 px height leaves buttons at 31 dp.

**Command-line arguments**, after `--`: `--autoplay` (the bot plays from the main scene, without offline pay, and the
run ends at the goal), `--speed=N` (N seconds of play per second of game time, 1 to 600), `--no-save`.

**Log lines** (print): `[Run] dawn N, E embers` after each dawn, `[Run] goal: G glow after N dawns` when the glow earned
in all runs reaches 1e9 (`GOAL_GLOW`); for `juice`, in game time (ticks / 60, not play time),
`[juice] event gathered|bought|upgraded|dawn <ms>` and `[juice] feedback sfx|pop|flash|shake <ms>`.

## The release candidate (the whole game, `game/`)

| Part | Files |
|---|---|
| Tests | GDScript: `test/unit/test_*.gd` (GUT), 62 tests: numbers and their formatting past 2^53 and 1e36, prices and purchases, Buy max at exact boundaries, upgrades, the dawn, time away, saves and version 2, the bot's choices, the data's balance, the launch options, the game scene and Main with a test clock. C#: `test/*Test.cs` (gdUnit4), the same 62 |
| Flows | `test/flows/gather.flow.json` (Gather, the first wick moth, its production), `pages.flow.json` (the bar's pages), `dawn.flow.json` (the Dawn button, its panel, an ember), `settings.flow.json` (German and back, Back), `credits.flow.json` |
| Data | `data/producers.json`, `data/upgrades.json`, `data/economy.json`; `data.json` (ranges, name key patterns) |
| Bot runs | `playthrough.json`: `--autoplay --speed=60 --no-save`, `[Run] dawn 1,` to `[Run] dawn 3,` and `[Run] goal` within 10,800 frames (it takes about 6,700: six dawns). `juice.json`: 1,500 frames; gathered and bought and upgraded get sfx and pop, the dawn flash, shake and sfx, each within 100 ms |
| Text | `i18n/strings.csv` (keys, `en`, `de`, `fr`), every visible text through `tr()`; `textsize.json`; `layout.json` |
| Architecture | `architecture.json`: `parent-path`, `per-frame-lookup` and `nondeterministic-sim` are errors; `simulation` is `scripts` |
| Assets | `art/icon.png` drawn by a script; sounds in `sounds/sfx/` from `hyperdot.ps1 sfx -Sound coin,powerup,blip,jump -Seed 9`; `assets.json` |
| Release | `export_presets.cfg` (Linux, Web without threads, Android with `import_etc2_astc` and the icon; C# Linux and Android only); `application/config/version="1.0.0"`; `store/steam/` art at the sizes `doctor` checks, 5 screenshots, `short_description.txt` and `store/privacy-policy.md`; `CREDITS.md`, `credits.json` and `THIRD-PARTY-NOTICES.txt` from `credits` |
| Plan | `plan/plan.json` at the release gate; `docs/` (GDD, decisions, milestones, tech debt, trailer); `CHANGELOG.md` |

The whole game passes the kit's `test` (validate, architecture, gut, flows, smoke, juice, playthrough, l10n, data,
textsize, layout) and `doctor` with no FAIL, `export -Preset Linux -Run` starts the build, and `export -Preset Web -Run`
starts it in Chromium.

## The stages

Each stage is the whole game minus parts, through `stages/<stage>.json` (`remove`, `edits`) and the overlay
`stages/<stage>/`. Every stage passes `test` with the runners it has. Defects are never part of a stage: each task plants
its own.

| Stage | Has | Removed from the whole game |
|---|---|---|
| prototype | Numbers, Catalog, Economy (prices, Buy 1 and 10, milestones, Gather), three producers; `game/game.tscn` is the main scene, one screen; English only; the gather flow; 27 tests | Buy max, the Moon Lily and the Star Loom, upgrades, the dawn, time away, saves, Main and its screens, the bot, sounds, juice, data checks, layout and text size checks, store, export, plan |
| alpha | Main, four producers, Buy max, upgrades, the dawn, saves (version 3 only) with time away, settings (volume), juice log lines and sounds, flows `gather`, `pages`, `dawn`, `data.json`, `architecture.json`, `plan.json` at the alpha gate, English | the Star Loom, version 2 saves, the bot, German and French, the settings flow, layout and text size checks, store, export, credits |
| beta | all five producers, the bot, `playthrough.json`, `juice.json`, English and German, the settings flow, layout and text size checks, version 2 saves | store, export presets, credits, French |
| release | everything | nothing |

## The tasks

For each stage, in the order the tiers take them (the min and mid tiers take the first two). Each task has a
**reference** solution, `solutions/<stage>/<template>/` (whole files laid over the game, plus `answer.md` when the
answer is graded), and a **decoy**, `solutions/<stage>/<template>-decoy/`, a tempting wrong fix (but explain-failure,
which is graded by its answer alone). `tests/Test-GameProgramme.ps1 -Genre idle` plants each defect and checks that
the untouched game fails, the reference passes and the decoy fails.

The six defects of this genre: a cost formula off by one level (prototype fix-bug), a number printed in scientific
notation past a size (prototype explain-failure), time away that pays for a clock set back and pays twice when it is put
right (alpha fix-bug), a save from the previous version that loses its prestige (alpha migrate-save), a button pushed
off a phone screen in one language (beta fix-bug) and a tick that works the rate out from scratch every time (beta
fix-performance). Most are graded by behaviour the visible tests do not reach, as the pilots asked: a hidden test that
counts, measures a layout or plays a clock forward and back.

### Prototype

| # | Template | Defect planted (`edits`) | Graded by |
|---|---|---|---|
| 1 | `fix-bug` | the price of several is the sum from one level too high (`growth^(n + amount + 1) - growth^(n + 1)`), so Buy 10 asks 2.80K for ten Glow Snails that cost 2.43K one by one; a single price is right | a hidden test: every producer, 0, 7 and 40 owned, 2, 10 and 25 at once, against the singles bought one by one; the single price; Buy 10 in the game spends exactly that. `test_economy.gd` `unchanged`. Decoy: several cost the first price each |
| 2 | `write-tests` | none; `{file}` is `test/unit/test_economy_rules.gd` | 8 mutants of Economy: the price does not grow, several cost the first price each, a purchase spends nothing, a purchase the glow does not cover goes through, several add one, production ignores the seconds, the 25th does not double, the rate is not worked out again after a purchase; `economy.gd` `unchanged`. Decoy: tests that leave out the milestone and the rate after a purchase |
| 3 | `add-feature` | none (Buy max removed from the stage); `{feature}`: Buy max | a hidden test (nothing without one price, the most at 0, 3 and 30 owned, an exact price buys the last one, 1e80 glow, buy_max spends that, the mode button steps 1, 10, max); `newTests` 1. Decoy: counts one at a time up to 1000 |
| 4 | `explain-failure` | `Numbers.suffix` returns `"e%d" % (group * 3)` past Dc | the answer names `test_past_decillions_letters_take_over`, `test_numbers.gd` line 31 (or 32, 33), "1.50aa" and "1.50e36"; nothing `unchanged` may change |

### Alpha

| # | Template | Defect | Graded by |
|---|---|---|---|
| 1 | `add-content` | none; `{content}`: the Star Loom and Star Thread, with a price between 200K and 500K, growth 1.10 to 1.15 and a payback between the Moon Lily's and twice it | `data`; a hidden test of the producer, its order, its payback, its upgrade and its names; a hidden flow buying one. Decoy: a Star Loom that pays back faster than the Moon Lily |
| 2 | `fix-architecture` | the rows no longer refreshed by the game: each row looks the game up with `get_node("../../../../..")` every frame | the architecture runner (parent-path and per-frame-lookup are errors); a hidden test that the rows follow glow, a purchase, the buy mode and a dawn, and that a row alone shows what it is given without errors. Decoy: the lookup made once in `_ready`, still five levels up |
| 3 | `migrate-save` | none, SaveStore reads only version 3; `{report}`: the embers are gone after updating | a hidden test: a version 2 save keeps its embers, dawns, glow past 2^53, producers, upgrades, time and settings; a file without a version; a migrated save written back as version 3; a version 3 save untouched. Decoy: the top-level embers copied whatever the version, which empties a version 3 save's |
| 4 | `fix-bug` | `seconds_away` is `min(abs(now - saved_at), cap)` and `seen_at` is `now` | a hidden test through Main with a test clock: an hour away, a clock set back a day (nothing), a month (8 hours), and a clock set back, played, then put right (only the hour since the save, then a minute); `test_offline.gd` `unchanged`. Decoy: `seconds_away` fixed and `seen_at` left as `now`, which pays the night again |

### Beta

| # | Template | Defect | Graded by |
|---|---|---|---|
| 1 | `fix-performance` | `tick` calls `_recompute()` every time | a hidden test reading `rate_computations`: at most one over 600 idle ticks, one or two for a purchase, a thousand ticks of a loaded economy, and the rate right at once after a purchase, an upgrade, a dawn and a load. Decoy: worked out once every 60 ticks, which pays a stale rate after a purchase |
| 2 | `fix-bug` | the bar's buttons no longer wrap, so in German (Erzeuger, Verbesserungen, Morgengrauen, Einstellungen) the bar is wider than a 720 px portrait screen | a hidden test laying the game out at 1080x2400 in English, German and a made-up language of 30-letter words: every bar button on the screen and the column no wider than it; `strings.csv` `unchanged`. Decoy: a 14 px font in the bar (8.75 px at 1280x800, which `textsize` fails, and the long words still do not fit) |
| 3 | `fix-playthrough` | production is added to the glow but not to the run's or the total's count, so the dawn never comes | `playthrough`; a hidden test: production and time away count toward the dawn and the total, spending does not lower the dawn, the dawn costs what it did, the bot greets 3 to 11 dawns in an hour; `data/economy.json` `unchanged`. Decoy: the dawn reads the glow on hand too |
| 4 | `add-feedback` | an upgrade plays no sound | `juice`. Decoy: the sound a quarter of a second late |
| 5 | `fill-translations` | the welcome-back panel's three keys are empty in `de` | `l10n`; `game.gd` and `game.tscn` `unchanged`. Decoy: the keys deleted |
| 6 | `fix-flow` | the settings screen's Back button is not connected | the `settings` flow. Decoy: Back hides the screen instead of closing it |

### Release

| # | Template | Defect | Graded by |
|---|---|---|---|
| 1 | `fix-export` | the Linux preset excludes `data/*` | `kit`: `export -Preset Linux -Run` (the catalog's `push_error` for a missing table). Decoy: `data/*` added to the include filter too, which the exclude filter still beats |
| 2 | `fix-store` | `library_capsule` is 600x800 (`defects/library_capsule_600x800.png`), and the art's entry in `assets.json` has no licence | `kit`: `doctor` and `credits`; a hidden check that the capsule is 600x900. Decoy: the licence alone |
| 3 | `cut-version` | none; `{version}` 1.1.0, `{details}`: the project, a `CHANGELOG.md` entry, the settings screen | `match` on `project.godot` and `CHANGELOG.md`; a hidden flow reading the settings' version label. Decoy: no changelog entry |

### Milestones

Each is the next stage's `milestone` entry. It runs on the earlier stage and is graded by these hidden acceptance files.
Its reference is every file of the next stage that the earlier one lacks or has otherwise.

| From, to | `{goal}` | Accepted by |
|---|---|---|
| prototype to alpha | Main holding the hive, the Moon Lily, Buy max, upgrades on a second page, the dawn, a save with time away (capped, nothing for a clock set back), settings, `data.json` | hidden flows `gather`, `pages` and `dawn`; a hidden test of the producers, Buy max, an upgrade, the dawn, a save through Main with a test clock and the settings screen; `data.json` passes |
| alpha to beta | the Star Loom, a bot that greets dawns and reaches the goal, juice for gathering, purchases, upgrades and the dawn, German with the bar on a phone, version 2 saves, layout and text size checks | `playthrough.json`, `juice.json`, `textsize.json` and the `settings` flow of the whole game, hidden; hidden tests of five producers, German, the bot, the bar in German and version 2 saves |
| beta to release | export presets for Linux, Web and Android, store art and a privacy policy, credits from the settings, French, version 1.0.0 | `kit`: `doctor`, `export -Preset Linux -Run`, `credits`; the hidden `credits` flow |

## Rules for writing it

- Each stage must be green under `pwsh ci/godot/hyperdot.ps1 test -Project <stage>` and `doctor` without FAIL; `tests/
  Test-GameProgramme.ps1 -Genre idle -Language <lang>` builds every stage and checks every task.
- Hidden tests and flows sit in `hidden/`, named for their task; they are copied into the game only when it is graded.
- Data and balance change together: `test_catalog.gd` holds every later producer to a longer payback, and the bot's
  hour (three dawns or more, fewer than twelve) is checked by the hidden fix-playthrough test.
- Keep the game small: about 1,400 lines of game code per language, a test run under a minute, a playthrough under 3
  minutes of game time.
- Comment like the rest of the kit: say why, not what.

## As built

Choices made in the GDScript build where the design was open. The C# port follows them; its own choices come after.

- **The economy lives in Economy, not in nodes.** The game node ticks it in `_physics_process` and shows it; the tests,
  the bot's balance checks and the hidden tests play hours of it in a loop without a scene.
- **Doubles, not a big-number type.** A double reaches 1.8e308, and the screen shows three digits, so a mantissa and
  exponent type would have cost the C# port a second implementation to match for no visible gain. What a double loses
  (Gather adds nothing visible to 1e20) is stated in `Numbers`; the tolerance is tested by an hour of quarter-second ticks
  past 2^53 against one tick of an hour, and a save round trip keeps the same double.
- **No `pow()` or `log()` in `scripts/`.** The architecture runner's `nondeterministic-sim` rule flags them in simulation
  code, and it is right to: prices compared at an exact boundary must agree in both languages. Powers are multiplied out
  by squaring, Buy max doubles and halves instead of solving with a logarithm, and the thousands are parsed from text.
- **The clock is Main's.** `Offline` is given the times, so the prototype-to-alpha milestone and the alpha's clock bug
  are graded through Main with a test clock (`clock`, `save_path`), never the player's save.
- **Time away is paid by ticking the economy once**, at the rate saved, so it counts toward the dawn like any other
  production; the bot gets none (`--autoplay`).
- **The bot dawns when the dawn would double its embers.** It reaches the goal (1e9 glow over all runs) in about 6,700
  seconds of play after six dawns; at `--speed=60` that is about 112 s of game time. The goal is what fails when the
  playthrough defect hides the dawn: the bot can still buy, so a playthrough that only waited for purchases would pass.
- **Portrait, not both orientations.** A landscape phone would scale the portrait UI to 1080 px of height and its
  buttons to 31 dp, which the layout runner fails; the game locks portrait on phones, and tablets and desktop browsers
  get the same column, wider.
- **The bar's buttons wrap** (`AUTOWRAP_WORD_SMART`) instead of shrinking their text, so German and any longer
  translation stay on screen without failing `textsize`; the hidden test uses a made-up language of 30-letter words so
  that shortening the German words is not a fix.
- **The catalog fails loudly on a missing producers or economy table** (`push_error`), and quietly on a missing
  upgrades table. The release's export defect needs the former; the prototype, which has no upgrades yet, the latter.
- **Store art** is rendered by the game under Xvfb: five 1920x1080 screenshots of a 720x1280 hive in its sky beside a
  caption, and the capsules from the sky, the icon and the title. The 600x800 capsule of the fix-store defect is a crop.
- **Saves are written on focus loss too**, which is how a browser tab that is closed gets its last save; the Web export
  calls `JavaScriptBridge.force_fs_sync()` after each write.

### C#

- **The same numbers, checked line for line.** Every amount is a double in both languages, and the simulation code
  does the same operations in the same order: a rate is `rate * owned * multiplier * ember_multiplier`, a price is
  multiplied out by squaring, and besides minimum, maximum and clamp its only library calls are `Math.Sqrt` and
  `Math.Floor`; the thousands are parsed from their decimal text with the invariant culture. So the bot run
  (`--autoplay --speed=60 --no-save`) prints the same 3,487 `[Run]` and `[juice]` lines as the GDScript version, game
  times included: six dawns and the goal after 111.4 s of game time. Nothing in `scripts/` calls `Math.Pow`,
  `Math.Log` or their float variants, which the architecture runner's `nondeterministic-sim` rule flags in C# too.
- **Culture-proof text.** C# formats a double with the machine's culture, so `Numbers` and `TextFormat` (which fills the
  translation table's `%s`, `%d`, `%02d` and `%%`) write every number with `CultureInfo.InvariantCulture`, and every
  parse names it, as do the juice log's times: on a machine set to German the game prints `1.50aa`, not `1,50aa`,
  and its bot run is the same, line for line.
- **Names:** `Game` keeps the snake_case names the flows and the contract use: `economy`, `buy_mode`, `page`,
  `restore`, `gather`, `buy`, `buy_upgrade`, `next_mode`, `show_page`, `ask_dawn`, `confirm_dawn`, `show_welcome` and
  `add_glow` (the flows call it with a whole number, which the engine passes to its `double`); `Main` keeps
  `save_path`, `clock` (a `Func<double>`), `game`, `seen_at` and `save_now`, which tests set or call before and after
  it enters the tree. The rest is C#'s own case: `Numbers.Format`, `FormatRate`, `Suffix`, `GroupOf`, `Thousand`,
  `Power`, `Close`, `Max` and `Tolerance`; `Economy.Cost`, `MaxAffordable`, `Buy`, `BuyMax`, `CanBuy`,
  `UpgradeUnlocked`, `CanUpgrade`, `BuyUpgrade`, `Multiplier`, `EmberMultiplier`, `Rate`, `ProducerRate`,
  `UnitRate`, `TapValue`, `Tap`, `Tick`, `Earn`, `DawnGain`, `CanDawn`, `Dawn`, `ToDict` and `FromDict`;
  `Offline.SecondsAway`, `SeenAt` and `Apply` (a `TimeAway` record); `Bot.NextAction` and `Act` (a `BotAction` record
  rather than a dictionary); `Game.Setup`.
- **One method the GDScript tests do without.** `Economy.SetCount(id, count)` sets how many of a producer are owned and
  marks the rate to be worked out again, where the GDScript tests write `owned[id]` and `_dirty` directly; `Owned` is
  read-only. `Upgrades` is a `HashSet<string>` the tests add to, as they add to the GDScript dictionary.
  `Game.Refresh` is internal, so that the fix-bug hidden test can call it as `test_hidden_bulk_cost.gd` calls `_refresh`.
- **Typed rows and C# events.** A producer is a `ProducerData` record and an upgrade an `UpgradeData`; `Catalog.Producer`
  and `Catalog.Upgrade` give null for an id the data lacks, where GDScript gives `{}`. `Economy`'s signals and the
  game's and screens' are C# events; `SafeArea.Changed` is a Godot signal, as the kit's layout runner and
  `SafeMargins` expect.
- **Simulation code the architecture runner passes.** Nothing in `scripts/` iterates a `Dictionary` or `HashSet`: the
  "all" upgrade counts the catalog's producers, `ToDict` writes `owned` and `upgrades` in data order (so the same
  economy always writes the same file), and the game refreshes its rows in data order too.
- **Saves:** `SaveStore` takes a file path (Main globalises `save_path`) and uses `System.Text.Json`, which writes a
  double's shortest round-trip text, so glow past 2^53 comes back as the same double; its tests use temporary files.
  `SaveData` holds `Economy` (a `JsonObject`, as `ToDict()` gives it), `SavedAt`, `Volume` and `Locale`; the file is
  the GDScript version's, so a save from either loads in the other. There is no Web build to sync to IndexedDB.
- **Tests:** 62 gdUnit4 tests in `test/*Test.cs`, the GUT tests one for one, run by the kit's `dotnet` runner, and
  `gdunit4` for the mutants. The suites that read `res://` or load a scene are `[RequireGodotRuntime]`; `Numbers` and
  `LaunchOptions` are tested without the engine. The game scene's tests load it with `ISceneRunner` and wait whole
  physics ticks; the tests of Main, and the hidden bar check (which resizes the window first), add the scene to the
  tree themselves, since Main's `save_path` and `clock` must be set before it is ready and the scene runner adds a scene
  at once.
- **Hidden checks that differ.** C# has no engine error count, so the fix-architecture check of a row alone reads its
  buy button as well as its count; the architecture runner is what catches the lookup. `SaveStore.Read` gives a
  `SaveData`, which has no version of its own, so the migration check reads the version back from the written file.
- **The explain-failure test** is `Past_decillions_letters_take_over`, `test/NumbersTest.cs` line 47; gdUnit4 stops at
  its first failed assertion, so lines 48 and 49 are not reported.
- **Stages** lay overlays of `game/Game.cs`, `game/game.tscn`, `scripts/Economy.cs` and `test/GameTest.cs` (prototype),
  as the GDScript stage does with its scripts; the data, translations and plans are the GDScript version's files, and
  the rest, the alpha's and beta's removals from Main, Game, Settings, SaveStore and LaunchOptions included, is edits.
  The task references and decoys are the stage's files with the defect undone or a wrong fix made; those of data and
  translations are the GDScript version's files. The milestone references follow the rule above, generated from the
  built stages.
- **Export:** Linux and Android (Godot 4.7 cannot export C# to the Web). The Android preset builds without Gradle, so
  the project targets `net9.0` when `GodotTargetPlatform` is `android`, as `doctor` asks; the planted export defect
  adds `data/*` to the Linux preset's `exclude_filter="test/*"`. `THIRD-PARTY-NOTICES.txt` comes from `credits` on the
  C# game, with the .NET runtime's notices; the store art, docs, data, translations, sounds and flows are the GDScript
  version's files, and `CHANGELOG.md` names the builds this version has. `doctor` wants the .NET build of Godot in
  `GODOT_BIN` for a C# project, as the self-test workflow sets it.
