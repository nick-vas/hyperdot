# Narrative game: Saltmere Crossing

The seventh genre of the staged game programme (`benchmark/PLAN.md`): the one that exercises dialogue data,
localisation, text that fits its boxes, and saves. The story is data, nodes, choices, flags and endings in JSON checked
by the `data` runner (`game-data`, `narrative`), with what the runner cannot see (reachability, dead ends, flags
set and never read) checked by a search the game ships; every line is a translation key in English, French and German
with a length limit per row that the `l10n` runner holds (`localization`); and the save keeps the story at the
line shown, with its flags and history (`saves`). It is one of the mid tier's three genres (`PLAN.md`, the tier
table), so every task is graded by hard checks. One game, written twice: `gdscript/` and `csharp/` (ported from this
design), both built. Both behave the same, use the same data files, scene tree, node names and log lines, and pass the
same flows. Only the code and the test framework differ: GUT for GDScript, gdUnit4 (run by the kit's `gdunit4` runner)
for C#.

Everything here is made up for the benchmark: the name, the story, the people and places in it, and every line of its
text in the three languages. The river, the boat and the figures are drawn in code, the lantern is a PNG drawn by a
script, the sounds come from the kit's `sfx` command, and the store art is rendered from the game. Nothing comes from a
real game or book.

## The game

You keep the night ferry at Hensmouth. A stranger in a grey coat asks to be taken across the Saltmere to Greywick.
On the way you greet her or keep silent, tell her the toll honestly or lie, steady yourself or hurry when the fog comes
down, and ask her name, what is in her bag and about the bell you hear under the water. On the far bank you bring the
boat in (if she trusts you and you are calm), turn back, or row to the drowned tower of Old Hensmouth (if she told you
of it). Three endings: the letter (`shore`), the empty seat (`return`) and the drowned bell (`bell`). A crossing takes
a few minutes; the menu counts the endings found.

### The contract the C# port keeps

**The story as data** (`data/*.json`, read by `StoryGraph`; each a JSON array, one object per row):

- `flags.json`: `id`, `kind` (`count`, raised one at a time, or `switch`, set and cleared). `trust` (count), `lied`,
  `afraid` and `knows_bell` (switches).
- `nodes.json`: `id`, `chapter` (1-3), `speaker` (`narrator` or `stranger`), `text` (a translation key `N_...`). The
  first row is where every story starts (`dock`).
- `choices.json`: `id`, `from` and `to` (nodes), `text` (a key `C_...`), and optionally `needs` (the kit's criteria
  grammar: `trust>=2;!afraid`, `lied=1`), `raise`, `set` and `clear` (lists of flags) and `once` (true). Choices out of a
  node are offered in file order.
- `endings.json`: `id`, `node`, `title` (a key `ENDING_...`), in the order the bot finds them.
- `names.json`: the proper nouns (Maudrey, Quillon, Hensmouth, Greywick, Saltmere), for the data runner's `names` rule
  over `i18n/strings.csv`.

| Node | Chapter | Speaker | Choices out (needs; effects) |
|---|---:|---|---|
| `dock` | 1 | narrator | `dock_greet` -> toll (raise trust), `dock_silent` -> toll |
| `toll` | 1 | stranger | `toll_true` -> launch (raise trust), `toll_lie` -> launch (set lied) |
| `launch` | 1 | narrator | `launch_row` -> fog (set afraid) |
| `fog` | 2 | narrator | `fog_steady` -> crossing (clear afraid), `fog_hurry` -> crossing |
| `crossing` | 2 | stranger | `ask_name` -> name (once; raise trust), `ask_cargo` -> cargo (once), `ask_bell` -> bell_tale (once; set knows_bell), `confess` -> confession (`lied=1`; raise trust, clear lied), `cross_on` -> far_bank |
| `name`, `cargo`, `bell_tale`, `confession` | 2 | stranger, stranger, stranger, narrator | `name_back`, `cargo_back`, `bell_back`, `confess_back` -> crossing |
| `far_bank` | 3 | narrator | `land` -> end_shore (`trust>=2;!afraid`), `turn_back` -> end_return, `to_tower` -> bell_tower (`knows_bell=1`) |
| `bell_tower` | 3 | narrator | `ring_bell` -> end_bell, `leave_tower` -> far_bank |
| `end_shore`, `end_return`, `end_bell` | 3 | stranger, narrator, narrator | none: the endings `shore`, `return`, `bell` |

**Rules** (engine-light: `scripts/conditions.gd` `Conditions`, `scripts/story_graph.gd` `StoryGraph`,
`scripts/story.gd` `Story`, `scripts/story_check.gd` `StoryCheck`):

- `Conditions.holds(needs, flags)`: every criterion holds; `!flag` is 0 or missing, `flag op n` with `=`, `<`, `<=`,
  `>`, `>=` against a whole number; empty needs hold. `parse` gives `{ "key", "op", "value" }` (`!` as op `!`, value 0),
  `keys` the flags read.
- `Story.new(graph)`: at `graph.start`, every declared flag 0, `history` empty (the choice ids taken, in order).
  `available()`: the choices out of the node whose needs hold and, when `once`, whose id is not in the history; none at
  an ending. `choose(id)`: false unless offered; otherwise raise (+1), then set (=1), then clear (=0), each change
  emitting `flag_changed(flag, before, after)`, then the id joins the history, the story moves to `to` and emits
  `node_entered(to)`, and `ended(ending)` when `to` is an ending node. `ending()` is the ending id or "".
- `to_dict()`: `node`, `flags` (flag -> int) and `history`. `Story.from_dict(graph, data)`: a missing flag is 0, a node
  the graph lacks is the start. `Story.replay(graph, ids)` takes them in order and stops at the first one not offered.
- `StoryCheck.problems(graph)`: sentences, empty for a sound story: `choice 'x' leads to 'y', which is no node`,
  `node 'x' cannot be reached`, `ending 'x' cannot be reached`, `flag 'x' is never set`, `flag 'x' is never read`,
  `flag 'x' of choice 'y' is not in flags.json`, `node 'x' is no ending and has no choice out of it`,
  `ending 'x' at 'y' has choices out of it`, `a story can get stuck at 'x' (<flags>): no choice is open`.
  `StoryCheck.search(graph, from)` plays every order of choices breadth first from a story (a new one when null), with
  every flag capped at one above the largest number any needs compare with, a state being the node, the flags and the
  once-only choices spent; it returns `nodes`, `endings`, `paths` (ending -> the choice ids of a shortest way, choices
  tried in file order) and `dead_ends`. `path_to(graph, ending, from)` is the bot's way.

**Saves** (`SaveStore`): `user://save.json` with `version` 2, `story` (`Story.to_dict()` of the story in progress, or
`null`), `endings` (the ids found, each once) and `settings` (`volume`, `locale`). The story is saved each time a line
is shown, except an ending's; reaching an ending records it and clears `story`. Version 1 (a file without a version is
version 1) was `{ "version": 1, "choices": [<ids taken>], "found": [<ending ids>] }`: its endings are kept and its
choices replayed for the story (none: no story).

**Scenes and nodes**:

- `res://main.tscn`: root `Main` (Control) with `Menu/Title`, `NewButton`, `ContinueButton` (shown when the save holds a
  story), `SettingsButton`, `CreditsButton`, `QuitButton`, `EndingsLabel` (`Endings found: 1 of 3`), `VersionLabel`.
  Screens are children of Main: `Story`, `Settings` (`Box/Languages/<Locale>Button`, `Box/BackButton`), `Credits`.
- `res://story/story.tscn`: root `Story` (Control) with `Backdrop` (draws the river; `chapter`, and `glow` 0 to 1),
  `Flash`, `Panel` (`Speaker`, `Text`), `Choices` (a VBoxContainer 460 px wide holding one button `Choice<i>` per choice
  offered, 88 px high, font 22, word-wrapped), `HUD` (`ChapterLabel`, `HistoryButton`, `PauseButton`), `SfxChoice`,
  `SfxTrust`, `SfxEnding`, `History` (CanvasLayer: `Box/Title`, `Box/Scroll/Lines`, `Box/CloseButton`), `PauseMenu`
  (`Title`, `ResumeButton`, `QuitButton`) and `EndingMenu` (`Box/Title`, `Box/MessageLabel`, `Box/AgainButton`,
  `Box/MenuButton`).
- The scene's API: properties `story`, `graph`, `found`, `node` (the node's id), `chapter`, `state` (`reading`,
  `choosing`, `turning`, `ending`, `ended`, `done`) and `choice_checks`; methods `setup(graph, options, found, saved)`,
  `start_new()`, `resume(data)`, `reveal_all()`, `choose(index)`, `choose_id(id)`, `history_lines()`, `open_history()`;
  signals `checkpoint(data)`, `ending_found(id)`, `finished`, `menu_requested`.
- Input: choices are buttons; a click on the text or `ui_accept` shows the whole line; `pause` (Escape, Start).

**Pacing** (60 physics ticks, all in `_physics_process`): a line is typed 3 characters a tick; once it is whole the
choices are worked out and shown (`choice_checks` + 1) and the state is `choosing`; a choice taken plays its sound and
waits 12 ticks (`turning`, longer than the juice window) before `Story.choose`; an ending's line stays 30 ticks before
the ending panel; the bot thinks 20 ticks before each choice and shows the panel 40 ticks before the next story.

**Command-line arguments**, after `--`: `--autoplay` (from the main scene, the bot plays one story per ending, in
`endings.json` order, each by `StoryCheck.path_to` from a new story; an ending it cannot reach is skipped with
`[Run] no way to ending <id>`; then it quits), `--no-save`.

**Log lines** (print): `[Story] begin at <node>`, `[Story] node <id>`, `[Story] choice <id>`, `[Story] ending <id>`;
`[Run] endings found <n> of <m>` and, when all were found, `[Run] every ending`; for `juice`, in game time,
`[juice] event choice_made|trust_gained|ending_reached <ms>` and `[juice] feedback sfx|glow|flash <ms>`.
`trust_gained` is a rise of `trust`; it answers with the lantern's glow and a chime. The choice's own sound comes 200 ms
before, outside the window, so it cannot stand in for the chime.

**Determinism**: nothing in `scripts/` reads the clock or a random generator (`architecture.json` marks `scripts` as
simulation code). The story has no randomness at all, so a bot run is the same everywhere; `--seed` is not needed.

## The release candidate (the whole game, `game/`)

| Part | Files |
|---|---|
| Tests | GDScript: `test/unit/test_*.gd` (GUT), 53 tests: conditions, the story's rules on its own small story (`test_story_rules.gd`), the game's story (`test_story.gd`), the tables, once-only questions, the story check on the game and on broken stories, saves and the story kept in them, every story text in every language, the launch options and the scene. C#: `test/*Test.cs` (gdUnit4), the same 53 one for one |
| Flows | `test/flows/start.flow.json` (menu, New story, the first choices), `pause.flow.json`, `play.flow.json` (three choices to the fog and chapter 2), `history.flow.json` (open and Close), `settings.flow.json` (French and back) |
| Data | `data/flags.json`, `nodes.json`, `choices.json` (`from`, `to` ref nodes; `raise`, `set`, `clear` ref flags; `needs` of type criteria), `endings.json` (`node` ref nodes), `names.json` with the `names` rule over the strings; `data.json` |
| Bot runs | `playthrough.json`: `--autoplay --no-save`, `[Story] ending shore`, `[Story] ending return`, `[Story] ending bell` and `[Run] every ending` within 7200 frames (it takes about 1750). `juice.json`: 1800 frames; choice_made gets sfx, trust_gained glow and sfx, ending_reached flash and sfx, each within 100 ms |
| Text | `i18n/strings.csv` (keys, `en`, `fr`, `de`, `_max`, `_lines`): lines 170 characters, choices 52, endings 30, chapters 40, speakers 24, one line each; `textsize.json` (menu and story at 1280x800); `layout.json` (the same on `phone_landscape` and `ultrawide`) |
| Architecture | `architecture.json`: `parent-path`, `per-frame-lookup` and `nondeterministic-sim` are errors; `simulation` is `scripts` |
| Assets | `art/lantern.png` drawn by a script; sounds in `sounds/sfx/` from `hyperdot.ps1 sfx -Sound blip,coin,powerup -Seed 7`; `assets.json` with each source and licence |
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
| prototype | Conditions, StoryGraph, Story without once-only choices; `story/story.tscn` is the main scene, lines typed out and choices, an ending's title and Again; the story without the bell (two endings); English only; 19 tests (conditions, story, tables, text) | menus, pause, history, the ending panel, saves, StoryCheck, once, the bell, sounds, juice, the bot, translations, data checks, store, export, plan, most tests |
| alpha | menus, pause, history, the ending panel, once-only questions, StoryCheck, SaveStore (version 2 only) with Continue, juice log lines and sounds, flows `start`, `pause`, `play`, `history`, `data.json`, `architecture.json`, `plan.json` at the alpha gate, English | the bell, the bot, French and German, the settings flow, text size and layout checks, store, export, credits |
| beta | the bell (three endings), the bot, `playthrough.json`, `juice.json`, English and French, settings, SaveStore version 1 migration, text size and layout | store, export presets, credits, German |
| release | everything | nothing |

## The tasks

For each stage, in the order the tiers take them (the min and mid tiers take the first two). Each task has a
**reference** solution, `solutions/<stage>/<template>/` (whole files laid over the game, plus `answer.md` when the
answer is graded), and some a **decoy**, `solutions/<stage>/<template>-decoy/`, a tempting wrong fix.
`tests/Test-GameProgramme.ps1 -Genre narrative` plants each defect and checks that the untouched game fails, the
reference passes and the decoy fails.

The five defects of this genre: a choice that leads to a missing node (prototype fix-bug), a save that drops the story's
flags (alpha fix-bug), a flag set and never cleared so an ending cannot be reached (beta fix-playthrough), a key missing
from the translations and shown raw (beta fill-translations) and a translated choice that overflows its button (beta
fix-bug).

### Prototype

| # | Template | Defect planted (`edits`) | Graded by |
|---|---|---|---|
| 1 | `fix-bug` | `ask_cargo` leads to `cargo_bag`, a node the story does not have: the text goes blank and no choice is offered | a hidden test: the question is offered at the crossing and leads to a node whose line is `N_CARGO`, and on to the crossing; every choice leads to a node; every node is reached; `test_story.gd` `unchanged`. Decoy: never offer a choice into a missing node |
| 2 | `write-tests` | none; `{file}` is `test/unit/test_story_rules.gd` | 7 mutants of Story: needs ignored, raise adds two, set and clear leave the flag, the history not kept, the story not moved, a choice not offered taken; `story.gd` `unchanged` |
| 3 | `add-feature` | none (once removed from the stage); `{feature}`: once-only choices, and the two questions made once-only | a hidden test (a small story: offered until taken, others repeat, a new story offers it again, a story carried on remembers it; the game's questions); `newTests` 1 |
| 4 | `explain-failure` | every raise applied twice | the answer names `test_three_kind_words_give_three_trust`, `test_story.gd` line 32, 3 and 6 (number terms that `Godot 4.7.2` in the prompt cannot satisfy); nothing `unchanged` may change |

### Alpha

| # | Template | Defect | Graded by |
|---|---|---|---|
| 1 | `add-content` | none; `{content}`: the drowned bell, a third ending: a once-only question that sets `knows_bell`, the tower offered only with it, the ending, every text in English within its limits | `data` and the story check; a hidden test of the way to the bell, the tower closed to those who did not ask, the two other endings, the new texts |
| 2 | `fix-architecture` | the chapter label set from `Backdrop` with `get_node("../HUD/ChapterLabel")` every frame, and no longer by the story | the architecture runner (per-frame-lookup is an error); a hidden test that the label follows a choice into the fog, a story carried on and a new story |
| 3 | `migrate-save` | none, SaveStore reads only version 2; `{report}`: Continue and the endings found lost after updating | a hidden test: a version 1 story carried on where it was (node, flags, history, a question already asked), a file without a version, one between stories, writing it back as version 2, a version 2 file |
| 4 | `fix-bug` | a save that drops the story's flags: `Story.to_dict` leaves `flags` out | a hidden test: every flag back at its value, trust enough to land, three trust staying three, the scene carrying on; `test_story_save.gd` `unchanged`. Decoy: only the names of the flags set saved, which turns trust 3 into 1 |

### Beta

| # | Template | Defect | Graded by |
|---|---|---|---|
| 1 | `fix-playthrough` | `fog_steady` no longer clears `afraid`, so `land` (`trust>=2;!afraid`) is never offered and the shore cannot be reached | `playthrough`; a hidden test: every ending reached, the fog still frightens, steadying calms, the shore still needs trust and calm. Decoy: `land` no longer needs calm |
| 2 | `add-feedback` | the trust chime removed (the glow stays) | `juice` |
| 3 | `fill-translations` | the row of `N_BELL_TOWER` deleted from the strings: the key is shown in every language | `test_story_text.gd` and `l10n`; the nodes, the scene script and StoryGraph `unchanged`. Decoy: the row back with French empty |
| 4 | `fix-bug` | the French of `C_TOLL_LIE` 99 characters long | `l10n` (`too long`, its row's `_max` 52); a hidden test measuring every choice in every language at 22 px in 440 px: two lines at most, and the toll answers still French; the scene and its script `unchanged`. Decoy: the row's `_max` raised to 100 |
| 5 | `fix-performance` | the choices worked out and their buttons rebuilt every frame while the player chooses | a hidden test reading `choice_checks`: at most one more over 120 idle frames with the same button shown, one or two per line |
| 6 | `fix-flow` | the history panel's Close button not connected | the `history` flow |

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
| prototype to alpha | a menu with New story and Continue, history, pause, once-only questions, `data.json`, StoryCheck, a save of the story at every line with its flags and history | hidden flows `start`, `pause` and `history`; a hidden test of the save, the questions and the story check; `data.json` passes |
| alpha to beta | the drowned bell, a bot that reaches every ending, juice for choices, trust and endings, French with a settings screen | `playthrough.json`, `juice.json` and the `settings` flow of the whole game, hidden; hidden tests of French and of the three endings |
| beta to release | export presets for Linux and Web, store art, credits, German, version 1.0.0 | `kit`: `doctor`, `export -Preset Linux -Run`, `credits` |

## Rules for writing it

- Each stage must be green under `pwsh ci/godot/hyperdot.ps1 test -Project <stage>` and `doctor` without FAIL;
  `tests/Test-GameProgramme.ps1 -Genre narrative -Language <lang>` builds every stage and checks every task.
- Hidden tests and flows sit in `hidden/`, named for their task; they are copied into the game only when it is graded.
- The story, its translations and the story check change together: `test_story_check.gd` holds the game's story to no
  problems, and `test_story_text.gd` holds every key of it to a text in every language.
- Keep the game small: about 1,500 lines of game code per language, a test run under a minute, a playthrough under 3
  minutes of game time.
- Comment like the rest of the kit: say why, not what.

## As built

Choices made in the GDScript build where the design was open. The C# port follows them; its own choices come after.

- **The story lives in Story, not in nodes.** The scene paces a story (the typing, the page turn, the bot's thinking)
  and shows it from Story's signals; it never decides what is offered. So the rules tests, the story check and the bot's
  planning play whole stories in microseconds, without a scene.
- **The data runner checks the shape, StoryCheck the meaning.** `data.json` holds the ids, the references (`to`, `raise`,
  `set`, `clear` and an ending's node), the criteria syntax of `needs` and the spelling of names; it cannot follow the
  story, so reachability, dead ends and flags set but never read are StoryCheck's, run by `test_story_check.gd`. The
  `softlock` kind of the data runner was not used: it models items picked up and spent in areas, and a story's state
  is its flags, so writing the story in that form would duplicate it in a second shape that could disagree with it. The
  prototype's missing-node defect is in data the prototype does not yet check (no `data.json`), so it is found by
  playing; from the alpha on, the data runner would catch it.
- **Choices are the kit's criteria grammar**, so the data runner checks their syntax (the grammar the C# example
  shares with it), and the game needs only a short parser for it.
- **Flags are capped in the search** at one above the largest number any needs compare with, so a hub that raised trust
  on every visit would still end; with once-only questions the whole search takes milliseconds.
- **A page turn of 200 ms** between a choice and the next line keeps the choice's click out of the juice window of what
  the choice causes, which is what lets the add-feedback task (the trust chime) be caught.
- **The bot plans, it does not wander.** For each ending in file order it asks StoryCheck for the shortest way from a
  new story and takes those choices through the scene's own `choose_id`, so the playthrough fails exactly when an ending
  cannot be reached, which is the fix-playthrough defect. It reaches the three endings in about 29 s of game time.
- **Length limits are characters, measured too.** Each row of the strings has `_max` and `_lines`, which the `l10n`
  runner holds without Godot; the overflow task's hidden test measures the real text in the button's font, so a raised
  limit (the decoy) does not pass. The choice buttons word-wrap to two lines at most: a single line at 460 px holds
  about 40 characters, too few for German.
- **The missing key is found by the game's own test.** The `l10n` runner checks keys the code names in `tr("...")`; the
  story's keys are in its data, so `test_story_text.gd` asks the TranslationServer for each in each loaded locale. With
  the row deleted the key comes back as itself; with a French cell left empty Godot falls back to English, so that decoy
  is caught by `l10n`'s `untranslated` instead.
- **The save is written at every line shown**, not on quitting, so a crash or a closed window never loses more than one
  line; reaching an ending clears the story and records the ending. Version 1 kept only the choices taken, so its
  migration replays them, which also restores the once-only questions already asked.
- **Store art** is rendered by the game under Xvfb: five 1920x1080 screenshots of real screens (the menu, the landing,
  the fog, the history and the bell's ending panel), and the capsules drawn by the game's own backdrop at each size with
  the title as a Label. The 600x800 capsule of the fix-store defect is a crop of the real one.
- **Decoys:** fix-bug (prototype, alpha, beta), fix-playthrough and fill-translations.

### C#

- **Same behaviour, checked line for line.** The bot run (`--autoplay --no-save`) prints the same `[Story]`, `[Run]`
  and `[juice]` lines in both languages, 122 of them with the same game times: the story has no randomness, and the
  scene counts the same ticks (a line's length is the same in UTF-16 as in GDScript, as every text is in the Basic
  Multilingual Plane). `StoryCheck.Search` keeps the GDScript order (breadth first, choices in file order), so the
  bot's ways are the same choice for choice.
- **Names:** the scene's script is `StoryScene` (`story/StoryScene.cs`), as `Story` is the playthrough's class. It keeps
  the snake_case names the flows and the contract use: `story`, `graph`, `found`, `node`, `chapter`, `state`,
  `choice_checks`, `start_new`, `resume`, `reveal_all`, `choose`, `choose_id`, `history_lines` and `open_history`;
  `Setup` and the constants (`StoryScene.TurnTicks`) are C#'s own case. The rest is C#'s own case too:
  `Conditions.Holds`, `Parse` (a `Criterion` record) and `Keys`; `StoryGraph.FromFiles`, `FromData` and `FromJson`
  (the four tables as JSON text, for the tests' small stories), `Node`, `Choice`, `Ending`, `ChoicesFrom`, `EndingAt`
  and the ids of each table in file order (`NodeIds`, `ChoiceIds`, `FlagIds`, `EndingIds`); `Story.Available`,
  `CanChoose`, `Choose`, `Flag(id)` (0 when missing), `ToDict`, `FromDict` and `Replay`; `StoryCheck.Problems`,
  `Search` (a `StorySearch`) and `PathTo`. The methods that take an optional story are overloads, as in the other ports.
- **Plain classes and C# events.** `Story`, `StoryGraph`, `StoryCheck` and `SaveStore` are plain C# classes; a node is
  a `StoryNode` record, a choice a `Choice` class with init-only properties (`Once` among them, so the prototype's
  manifest can take the property out and the add-feature task put it back), and Story's and the screens' signals are C#
  events, as `Checkpoint` carries a `JsonObject`. `Story.Flags` is a `SortedDictionary` and the graph keeps its ids in
  lists, so no simulation code iterates a `Dictionary`, which the architecture runner would flag.
- **Saves:** `SaveStore` takes a file path (Main passes `user://save.json`, globalised) and uses `System.Text.Json`, so
  its tests use temporary files. `SaveData` holds `Story` (a `JsonObject`, or null), `Endings`, `Volume` and `Locale`.
  Strings go into JSON arrays through `JsonValue.Create`: the generic `JsonArray.Add<T>` makes a value that cannot be
  written once Godot has turned off reflection-based serialisation. The version 1 migration replays the choices on the
  game's own story, so `SaveStoreTest` needs the engine.
- **Tests:** gdUnit4 suites in `test/*Test.cs`, run by the kit's `dotnet` runner, and `gdunit4` for the mutants. The
  suites that read `res://` are `[RequireGodotRuntime]`; the scene's tests load it with `ISceneRunner` and wait whole
  physics ticks. `Conditions`, `StoryRulesTest`'s own small story and `LaunchOptions` are tested without the engine.
  The hidden tests that must set the scene up before its `_Ready` (a saved story, a player without the bot) instantiate
  it, call `Setup` and add it to the tree themselves.
- **The explain-failure test** is `Three_kind_words_give_three_trust`, `test/StoryTest.cs` line 27.
- **The add-feature task** asks for `Once` as a public bool property of `Choice`, since the hidden test reads it.
- **Stages** lay overlays of `story/StoryScene.cs` (prototype, alpha) and `ui/Main.cs` (alpha, beta), as the GDScript
  stages do with `story.gd` and `main.gd`; the prototype also leaves out `scripts/TextFormat.cs`. The milestone
  references follow the rule above, generated from the built stages.
- **Export:** Linux only (Godot 4.7 cannot export C# to the Web), so the planted export defect adds `data/*` to that
  preset's `exclude_filter="test/*"`. `THIRD-PARTY-NOTICES.txt` comes from `credits` on the C# game, with the .NET
  runtime's notices; the store art, docs, data, translations, sounds and flows are the GDScript version's files.
