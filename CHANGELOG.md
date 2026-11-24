# Changelog

## Unreleased

## 0.2.0 - 2026-11-24
### Added
- `Update-AddonStatus.ps1` (the weekly canary) reads the newest release's zip of each add-on in `addons-status.json` (listed, never extracted or run) and compares its `addons/<name>/` folder and `.gdextension` file with the entry: a folder under another prefix is applied, a missing folder or file, a gone asset or a repository with a first release is reported for a person, and an API or download that cannot be reached is a note. Each entry with a release zip records it as `releaseZip` (tag, asset, prefix, date checked); the folders of Godot Jolt, godot-steam-audio and py4godot were confirmed against their zips on 2026-10-29.
- the `AGENTS.md` that `init` and `plan` copy into a game asks the agent to end each reply with `Certainty: NN%` and a clause saying what it rests on (what was run or read, and what was not checked), so the figure appears in every chat that works on the game.
- The `animation` skill covers reward screens and callouts (jackpots, combos, mode intros, attract loops): one thing moving at a time, an energy curve, many short pieces, a tested priority stack in which no covered callout expires unseen, and low-resolution dot-matrix displays; `game-juice` cites *The Art of Screenshake*, and `docs/art.md` lists the sources.
- `docs/awesome-lists.md` and a section "More add-ons, from awesome-godot" in `docs/addons.md`: 24 add-ons and tools from Calinou/awesome-godot (CC BY 4.0) read from their repositories (licence, newest tag, Godot and C# support), what was left out and why, godot-luaAPI marked do-not-use, and a note that a custom engine module cannot be tested or exported with the kit. Short notes in the `ui-accessibility`, `ui-flows`, `game-juice` and `llm` skills. The awesome project's own rules and its game-related lists are summarised; nothing was built or run.
- the token benchmark can finish a run that did not complete. `-SkipDone` runs only the sessions that have no result that ran in earlier results (before `-Shard`, so the rest splits evenly, and the dry run prices only the rest), `-MaxMinutes` stops starting sessions after a time and writes `not-reached.json` (exit 2, incomplete), and the Token benchmark workflow takes `continue_run` (an earlier run id) and `max_minutes` (default 300, under the 330-minute job limit).
- the Token benchmark workflow's `continue_run` takes several run ids separated by commas, so the last run of a chain can skip the sessions of every earlier one instead of repeating them.
- `brief` and the `/new-game` skill, the structured start of a new game. The user describes the game in their own words (`brief -Do start -TextFile`); `brief -Json` then lists, four at a time and in a fixed order, the questions from `ci/godot/templates/brief-questions.json` that are still open (basics: title, genre from `genres-uw.json`, 2D or 3D, camera, platforms, controls, GDScript or C#, players and network, core loop, session, kinds of fun, pillars, failure, saves; scope: jam, small or full, its length or hours a week, comparable games, out of scope; look and sound: art style, resolution, colours, sound), each with at most four options. An answer is taken from the description only with `-Quote`, the sentence that states it, found in it word for word; every other answer comes from asking the question as written, and anything outside its options is refused (`invalid-answer`). Rules across answers (C# with a Web export, touch with no touch platform, no kind of fun) block the draft with their fix. `brief -Do gdd` writes a draft `docs/GDD.md` that passes `doctor`'s feature grammar and, when there is none, `docs/STYLE.md`, and names the next steps (the Godot project, `plan -Do init` with the jam or full profile, `/game`). It needs no Godot project. New error codes `brief-missing`, `brief-exists`, `invalid-answer`, `brief-incomplete` and `gdd-exists`.
- `calendar` and the `/calendar` skill, the dates a game's marketing plans around: Steam's seasonal sales, Next Fest editions, themed fests and the Black Friday hub read from Valve's Upcoming Steam Events at run time, the most-joined itch.io jams, Epic's giveaways and discount windows, and comparable games' official-store prices and discounts, with LootRadar's lowest price and deepest discount over all stores (keyshops included), from LootRadar's public API (`-Comparable` or `release.comparables`). With `release.date` it says which seasonal sales the game can join, whether `release.nextFest` is an edition Valve lists (or names the last one before release with its demo deadline), warns about a discount marked seasonal outside every seasonal sale Valve lists, and writes `calendar-results/calendar.ics`. Pages are cached 6 hours in `.godot/hyperdot-calendar`; `-Offline` reads only the cache; one source failing is a warning, all failing is `calendar-unavailable`. plan.json's `release` gains `launchDiscount`, `discounts` and `comparables`, and `plan` and `status` now check the discounts against Steam's discounting rules (30 days after release, 30 days between discounts with seasonal sales exempt, 10 to 40% and 7 to 14 days for a launch discount). `help <name>` shows both entries when a command and its skill share the name.
- the JSON of a run that starts Godot lists the game's files the run changed in `changedProjectFiles[]` (git; a mono editor edits `project.godot` and writes `.cs.uid` files), `doctor` warns about `[TestSuite]` classes that are static (gdUnit4Net finds no test in them), and `-Project` at a repository whose `project.godot` is in a subfolder uses the shallowest one, as without `-Project`.
- `docs/ci-cache.md`, a design (not built) for a CI cache keyed by a hash of each job's inputs: the key, where results live, a verdict per self-test job, the risks and a staged plan starting with measurement only.
- `docs/ci.md` has the Self-test history of 5 to 28 October 2026 (842 runs): runs, failures, flaky failures, failures found only after merge and runner-minutes per job and slow step, and a recommendation of which jobs may move to the nightly run. Nothing was demoted.
- stage 0 of the CI cache (docs/ci-cache.md): every Self-test run computes an input hash per job from the files `Select-Jobs.ps1 -Inputs` lists for it, looks for a marker saved by an earlier green run, records which jobs went green on which hash (`record` job, `cache-observations` artifact) and skips nothing.
- `clip`, a scene recorded with Godot's Movie Maker at a fixed 30 fps as an MP4 (H.264, AAC) and a 480-wide GIF; and in the weekly brief, a `Marketing-Scene:` trailer (with `Marketing-Args:` and `Marketing-Seconds:`) that the promo workflow's new `clips` input records at the shipped commit, keeps as a 14-day artifact and links from a comment on the brief (`promo -Do clips`). Off by default (#274).
- `deck` reports `deck.framePacing` and warns when the project's frame cap (`application/run/max_fps`) is below a Steam Deck display's default rate and does not divide it (60 on the OLED's 90 Hz alternates between 90 and 45 fps; 45 on the LCD's 60 Hz between 60 and 30). Steam's store page now shows each tested game's average frame rate on a Deck with a histogram, from Decks at their default limit; `docs/steam.md` and the `console-cert` skill say what that changes.
- `docs/dialogue-tools.md` compares Dialogue Manager, Yarn Spinner for Godot, godot-ink, Dialogic 2 and inkgd from their repositories and records the owner's choice, Dialogue Manager 4 (v4.1.0), with how to install it and wire it to the `data` and `l10n` runners; the `narrative` skill recommends it. None was built or run here.
- `doctor` checks, from the field test: a GDExtension whose library is missing for the machine the kit runs on (the editor and `test` print "GDExtension dynamic library not found"), C# files in a project with no `.csproj` or `.sln`, a `Godot.NET.Sdk` pin of another Godot minor (or patch, as INFO: the editor rewrites it), a workflow whose `godot-version` is not the project's, and a note that a .NET `GODOT_BIN` on a GDScript-only project adds `[dotnet]` to `project.godot` and writes `.cs.uid` files.
- `doctor` warns when the kit's skills or subagents are in the game as copies (`init -Agents`) and also come from the enabled hyperdot plugin, so each shows twice (`/game-plan` and `hyperdot:game-plan`) and the copy goes stale.
- the plugin's edit hook (`hooks/edit-check.ps1`, `HYPERDOT_EDIT_CHECK=off` to disable). After Claude edits a `.gd`, `.tscn` or `.tres` file it loads that one file in headless Godot (`ci/godot/tools/editcheck.gd`) and tells Claude at once if the file has a syntax error, an undeclared name or a missing script or resource, instead of at the end of the turn. It costs the engine's start-up (about 0.2 s, measured the same on 6 and on 800 files), says nothing when the file loads, never blocks, and skips what it cannot check (no Godot, a game not yet imported, `addons/`, C#). `Test-EditCheck.ps1` covers it.
- the plugin's edit hook also checks a `.gdshader` file after an edit: it asks the shader for its uniforms, which makes headless Godot compile it, and reports the `SHADER ERROR` lines to Claude. A working shader says nothing.
- `export -DebugBuild` makes debug builds (`debug: true` in `exports[]`), and an Android export with no keystore fails with `export-no-keystore` and a message naming the variables to set and `-DebugBuild`, instead of `export-failed` "exited with 1" (#257)
- `test -Json`'s `failureDelta` counts how many runs of the same scope in a row a failing test was in: `stillFailing[].streak` (this run included) and `failureDelta.longestStreak` (`null` without a baseline). The `godot-test-loop` skill's cap of three attempts at one failure reads the count instead of relying on the agent's memory.
- `test -FixedFps` (workflow input `fixed-fps`) also runs the Godot that gdUnit4 starts at fixed game time, not only `smoke`, so gdUnit4 tests that wait for physics ticks no longer wait for the wall clock; on the C# example its tests went from 36 s to 13 s and `test` from 59 s to 36 s. A rate other than the game's physics tick rate is a warning; `-FixedFps` on another command or below 0 is `invalid-arguments`. Off by default: audio, the network and .NET timers still follow the wall clock.
- the `flows` runner resets the state autoloads hold between flows: every autoload with a `hyperdot_reset_flow_state()` method is called before the first flow and after each (it may return a String saying what it found dirty, shown in the flow's note), so a flow that asserts "the run holds 0 relics" passes alone and in a full run. The `ui-flows` skill documents the convention. Fixes #240.
- the `flows` and `validate` runners name a leak Godot reports at exit (`ObjectDB instances were leaked at exit`, `RID of type ... was leaked`) as an `exit-leak` warning with the last file that ran, and add it to the failure when the exit code fails the runner, so a failed runner never comes without a reason (#255)
- `game-design` covers Nicole Lazzaro's four keys to fun (hard, easy, serious and people fun, in her own words) as a way to read a playtest against the GDD's kinds of fun, a test for the main kinds (take one away in thought), and a short reading list (Koster, Schell, Salen and Zimmerman, Swink, Sellers). Marc LeBlanc's site answers again over plain HTTP, so its roadmap entry is gone.
- `benchmark/PLAN.md` records the Haiku configuration of the mid tier (run 45): 95 of 135 sessions ran for $8.34 before both parts reached the 330-minute job limit; 64 of 85 tasks and 2 of 10 milestones passed.
- `ci/godot/tools/Initialize-HyperdotGame.ps1` sets the kit up for a game in one run (doctor, `init -Plugin`, the tests, a commit and merge) and makes a worktree for a parallel Claude chat; it looks for local copies of the kit and of a Godot of the game's version before downloading anything, lists several matching Godots with their paths to choose from, and records the chosen one for the chat in `.claude/settings.local.json`
- `juice.json` can list several `runs` (stages), each with its own `name`, `args`, `frames` and `rules`, played and judged on its own, so a game whose events happen on different stages keeps every rule. Each run's JUnit cases start with its name and it has its own log, `juice-<name>.log`; the one-run form is unchanged (#284).
- `doctor` warns when files the kit wrote (`AGENTS.md`, `CLAUDE.md`, `docs/kit-help.md`, `.claude/settings.json`, the workflow and the like) are not committed in the game's repository, marking the ones that name a path of the machine, and lists them as `uncommittedKitFiles[]`; `doctor -ReportIssue` shows the issue it would file in the kit's repository and creates it with `gh` only after a yes; `/retro` has a last step that offers to commit them.
- `doctor` warns when `docs/STYLE.md` lists target resolutions of another shape than the project's base size while the stretch aspect is `keep` (Godot's default) or `ignore`: the game renders the same layout with bars there, so a screenshot cannot show a different one (`shot` returns the base-size picture and says so).
  Changed: the `look` skill takes its screenshots with `-RequireResolution`, so a resolution the engine cannot show fails with `shot-size` instead of returning a picture of another size, and it tells the agent to report that layout as not shown (with the stretch setting) and leave the choice to the user. Part of #212.
- `doctor` warns about godot-luaAPI (`addons/luaAPI`, `luaAPI.gdextension`) as archived and points to lua-gdextension, from an entry in the known-status list written from its repository; the release zip and GitHub's archived flag are left for the weekly canary.
- `doctor` asks for `store/steam/mac_icon.icns` when the project has a macOS export preset (a WARN when it is missing, a FAIL when the file is not an ICNS); without it the Mac client shows Steam's default logo.
- the README's licence section shows the End Software Patents campaign's two banners ("Innovating without patents" and "Patent-free"), linked to the campaign; the site shows them as their text.
- `godot-pitfalls` covers throw-away scene instances (a scene instantiated only to read its mesh is never freed: `Leaked instance dependency` and leaked ObjectDB instances at exit; `inst.Free()` fixes it, tested on 4.7.2) and the C# teardown `FATAL` at exit, with one game's `GC.Collect(); GC.WaitForPendingFinalizers();` in `_ExitTree` given as a reported fix that a minimal project did not reproduce (#283).
- `plan -Do move -Id t1,t2,t3 -Column done` moves several tasks in one call (all move or none), and returns `movedTasks[]`. Each plan call starts the kit and reads the project, so thirteen single moves took minutes. Part of #230.
- a second Stop hook in the plugin, `hooks/project-sync.ps1`, runs `plan -Do sync` after a turn that changed the plan's tasks when the plan has a GitHub Project, so the board follows without anyone asking. It keeps a hash in `.godot/hyperdot-project-sync`, never blocks the turn, and turns a failure into a one-line notice; `HYPERDOT_PROJECT_SYNC=off` disables it.
- `promo` and `init -Promo`, a weekly marketing brief: an issue with the player-facing changes (`Marketing:` trailers in commits or squash-merged pull requests) that are in a build whose kit check passed, a checklist carried over from last week and drafts for Discord, Bluesky and Steam news (GitHub Models drafts optional, off by default); the reusable `.github/workflows/promo.yml`, `docs/promo.json`, and a trailer rule in the `AGENTS.md` template (#270).
- `promo` lists the next 4 weeks' dates in the weekly brief (Steam's sales and fests from the store-page stage on, and plan.json's release deadlines not done yet), with a task for each one to act on; a week with nothing shipped but a date due within 7 days opens a short dates-only brief, with no tag. `"calendar": false` in `docs/promo.json` turns it off (#273).
- **Releases from a pull request.** After each push to main that passes Self-test, the Release PR workflow rebuilds `release/next` with the changelog fragments assembled and opens or updates the pull request "Release x.y.z"; merging it releases: when Self-test passes on that merge, `release.yml` tags the untagged changelog section (only at the commit that added it), moves `v1` and publishes the notes. `v1` never moves back to a 0.x release once 1.0.0 exists. The version follows the fragments (`Update-Changelog.ps1 -Next`: the minor for Added, Changed, Removed or Deprecated, the patch for Fixed or Security alone); a 0.x release moves `v1` by default.
- `.github/workflows/release.yml`, a manual workflow that tags `v<version>` and moves the major tag `v<major>` (tags cannot be pushed from the cloud session), then publishes the release with the changelog section as its notes; `.github/scripts/Get-ChangelogSection.ps1` extracts the section and `tests/Test-ReleaseNotes.ps1` tests it.
- the roadmap lists the README adoption rewrite, a `telemetry` view over the history log and an input-hash cache for CI as work for after the complete mid run.
- `shot -NameBySize` puts each picture's own size in its name (`main.1920x1080.png`; with a locale `main.fr.1920x1080.png`), so the pictures of one scene at several sizes sit side by side and one that is not the size asked for says so in its name. A `-Baseline` taken before the names carried the size is still found under its old name (`shots[].compare.baseline` names the file that was used). Refused on other commands. Fixes #212: the other asks of the issue (a loud `shot-size`, the comma-joined `-GameArgs` in `help shot`, the stretch-aspect warning in `doctor`) shipped in #217 and #237.
- `shot` says when a picture is not the size asked for with `-Resolution` (a project whose stretch aspect is `keep` renders at its base size, so `-Resolution 2560x1080` gave 1920x1080 without a word): a warning naming the project's stretch mode, aspect and base size, `shots[].requested` and `shots[].sizeMatches`, and `-RequireResolution` fails with the new code `shot-size`. `help shot` also documents that several `-GameArgs` flags go in one comma-joined argument.
- `status` and `plan` take `-TimeoutSec` (default 120 for `status` and a plain `plan`; none for `plan -Do sync|move|...`; 0 turns it off). git, a GitHub call and the folder walk are bounded by it: when it runs out the command still returns what it gathered, `partial` lists each skipped step and what it waited for (an editor holding git, a slow folder), and the text starts with PARTIAL. A GitHub call of `plan -Do sync` that outlives it stops with the new error code `command-timeout`, naming the call. The flag is refused on other commands. Fixes #230.
- the C# example has a Steam backend behind `IPlatformServices`: `SteamPlatform` over an `ISteamApi` seam (unit-tested with a fake), `PlatformFactory` (falls back to `LocalPlatform` and logs once when Steam is not running or its library is missing), and `SteamworksApi` on Steamworks.NET.AnyCPU 2026.164.4 in `src/Example.Steam`, built into the game only with `-p:Steam=true`.
- `doctor` warns, in a project that uses Steam, about a line that asks the player for a review (Valve forbids asking customers to review the game from inside it), and fails a build script whose `SetLive` branch name has a space; the default-branch warning now names the Steam Mobile Authenticator or SMS authorization a released game asks for.
- `docs/steam.md` has the Steamworks SDK release notes 1.59 to 1.65 paraphrased with what each means for a Godot game, and the `steam` skill names `IsRunningUnderProton`, the performance-setting calls and Steam Timeline, each marked as not in the pinned SDK 1.64 package where that is so.
- `telemetry`, one read-only view over `.godot/hyperdot-history.jsonl`: per command the runs, pass rate and mean, median and p95 duration of the newest `-Last` runs (50) with the trend of the newer half against the older, and for `test` the slowest runners, the tests that fail most often, the flaky ones and the recurring error keys. A history too thin for a number leaves it `null` and says `insufficient`; a missing file gives zero runs, a damaged line is skipped and counted. `test` now also records each runner's seconds (`runnerSeconds`) in its history line.
- the `godot-test-loop` skill now ends the fix-and-run loop: after 3 attempts at the same failure (same `error.code` and `engineErrors[].key`, or the same test in `failureDelta.stillFailing`) the agent stops changing code, re-reads the first error of the log, may try one fourth attempt only with a different cause, and otherwise reports what each attempt did instead of skipping or loosening the test.
- the `typography` skill (which fonts, how many, line spacing and length, capitals and letter-spacing, tabular figures for HUD numbers, pixel fonts, and real quotes, dashes, ellipses and spaces in the text) with `godot.md` and `punctuation.md`, the engine properties and behaviour measured in Godot 4.7.2, and `docs/typography.md`, the 15 sources the owner listed with what was read and what could not be; the parts each skill needs are also in `look` (type roles in the style guide and the critique), `asset-pipeline` (fonts), `localization` (marks per language) and `ui-flows` (asserting text with the real characters); `tests/Test-Typography.ps1` checks the engine names, numbers and behaviour.
- `status` lists `suggestedCommands` (which kit command is due and why: never run, failed, a file newer than its last run, too old for the plan's phase), from `ci/godot/workflow.json`; `docs/workflow.md` is the same table by moment and by phase, and `/game` runs the due checks before judging.
- the Evals and Token benchmark workflows take an `auth` input: `subscription` (the default, the `CLAUDE_CODE_OAUTH_TOKEN` secret) or `api-key` (the `ANTHROPIC_API_KEY` secret, billed to the API account). Only the chosen secret reaches each job, and `.github/scripts/Initialize-ClaudeAuth.ps1` checks it with one small request before anything runs, naming the secret that is missing or refused.
- the `xr` skill for headset games in Godot's OpenXR (the player's body against the origin, locomotion and comfort, hands and the action map, throwing from the peak of the last ten frames of hand speed, one-controller play, passthrough), with `xr_math.gd` and `xr_rig.gd` templates and a headless fixture, `tests/Test-Xr.ps1`, that checks every engine name the skill quotes against Godot 4.7.2 and runs the rig and its numbers with no headset; `docs/xr.md` has the sources

### Changed
- `ci/godot/addons-status.json` records the release zip of godot-luaAPI (v2.1-beta11, asset `gdextension.zip`, folder `addons/luaAPI` under the wrapper `container/`, read with `zipfile` and never run); the canary can now check it. The repository is still archived. Fixes #202.
- `ci/godot/addons-status.json` records what a look on 2026-11-03 found: py4godot is still a prototype (new commits since 2026-10-08, but its README still calls it a demo and its newest tag is still 4.7-alpha21) and godot-luaAPI is still archived (its tags now run to v2.1-beta11, but the release assets could not be read, so `docs/roadmap.md` lists what is left to do).
- AGENTS.md asks agents to cancel the workflow runs a newer push has made redundant after each push or merge
- the `godot-editor-bridge` skill carries the `init -McpAseprite` command (aseprite-mcp, for drawing and animating pixel art) next to the editor servers, and `/game` offers it when a next task draws sprites and `.mcp.json` has no `aseprite` server.
- the last five awesome lists (learn-gamedev, game datasets, game engine development, a11y, gametalks) are read by section and keyword in `docs/awesome-lists.md`, three gametalks are named as candidates for `docs/gdc`, and the `asset-pipeline` skill lists the licences of Quaternius (its own, since 2026-08-28), Poly Haven (CC0) and game-icons.net (CC BY 3.0).
- the remaining awesome lists (production, magictools, open-source games, Steam Deck, testing) are read entry by entry in `docs/awesome-lists.md`, six authoring tools are in `docs/addons.md`, and OpenLiberty is named as the field-test target.
- the token benchmark and the field test leave the closing `Certainty: NN%` line (and its clause) out of an answer before checking it: the game `AGENTS.md` template asks every reply to end with it, and it would otherwise count against `maxWords`, supply a `mustInclude` term from what the clause says was read, or trip a `forbid`. A reply that is only that line is still an empty answer.
- a continuation of a benchmark run (`-SkipDone`) must have the same selection as the run it continues (tier, model, plugin, repeat, narrowing) and is refused otherwise, naming what differs; its summary lists the runs it continues (`meta.continues`), and `Get-HyperdotLabel.ps1` reads a run and its continuations as one unit, so a continued configuration can be rated.
- `docs/roadmap.md` records what was measured about the two binding errors that print no JSON (a flag without its value, a value of the wrong type): a launcher catches both, breaks `-Switch:$false`, and the type case alone needs 23 parameters retyped; nothing was changed in the script.
- Poly Pizza is dropped from the asset sources in `docs/awesome-lists.md` and the roadmap (the owner's decision; its licences were never read).
- `detect`, `plan` and `status` are several times faster in a large game (BreakoutTheBreakout, 4,500 files: `detect` 9 s to 1.7 s, `plan` 15 s to 2 s, `status` 21 s to 4 s): the project file search walks with .NET instead of `Get-ChildItem` and a pipeline per folder, files are read once instead of line by line, the git root is remembered, and the suggested commands match file names without a pipeline per file. The results are the same files in the same order.
- the flows runner counts a flow as failed only from its own end line or an error of its own between its markers. The errors Godot's C# bindings log (`Handle is not initialized.`, godotengine/godot#124587) are warnings (`runnerResults[].warnings[]`, rule `engine-internal-error`, with the flow that was running) instead of failing flows that ended `ok`; the same for `validate`. The flows run with a throwaway `user://` folder on Linux and Windows, so a setting saved by an earlier run (a camera-sway toggle once turned `menu_navigation` red) does not reach them. The pull request comment's list of warnings is headed "Warnings", not "Architecture warnings". Fixes #231.
- when a runner fails in a game programme check without naming a failing test, the check now says why (`dotnet failed: reported no test results (exit code 1)`, with the locked file if there is one) instead of `dotnet failed`, so a failure that passes on a re-run (the racing C# milestone on `main`) leaves something to diagnose it from.
- `Fun: none` is valid at any GDD priority: a `must` or `should` feature can be work the game needs that serves no kind of fun (credits a licence requires, crash reports, cloud saves) without claiming a kind it does not serve or dropping to `could`. `doctor` no longer fails it; `status -Json` lists such features as `gdd.supportFeatures` for a design review, and the `game` and `game-design` skills no longer treat them as the first to cut (#285).
- the GDD feature grammar is a rule the kit enforces, not advice: each feature has exactly one `Priority:` line (must, should, could, won't) and exactly one `Fun:` line holding only kinds of fun, comma-separated, or `none`, which only a could or won't feature may have; feature ids are unique. `doctor` fails on every other form with the line and the one fix to make (an explanation on the `Fun:` line gives "Write `Fun: challenge` and put the rest on a line of its own"), and `status` lists the same problems in `gdd.problems` and its warnings. Fixed: `Priority: won't` was read as `won`, so won't features were warned about as missing plan tasks. The benchmark games' GDDs gain a `Fun:` line on every feature; their menus-and-saves and languages features become `could` with `Fun: none`, so token-benchmark runs before and after this change are not strictly comparable.
- `plan -Do sync` mirrors the plan to a GitHub Project instead of a board on another service. `plan -Do sync -Board @me` (or a login) makes a private project titled "<game> plan" with a Column field (Backlog, Design, To Do, Doing, Testing, Done), links it to the game's GitHub repository and puts every task on it; later syncs create, move, import and archive items both ways. It uses the GitHub CLI signed in with the `project` scope, so the kit stores no key. `-Board` takes `<owner>/<number>`, a project URL or an owner, `-Card` became `-Item` (a `PVTI_` id), task JSON has `itemId` instead of `cardId`, the board field is `projectBoard`, and `plan.json` has a `project` block (`owner`, `number`, `columns`, `toArchive`). The error codes of the earlier sync are now `project-credentials`, `project-error` and `project-column-missing`, and the sync workflow needs a `HYPERDOT_PROJECT_TOKEN` secret. The `game`, `game-plan` and `weekly-review` skills describe the new flow.
- the `l10n` glyph check warns (rule `default-font`) instead of failing when only Godot's own default font lacks a character, because the engine draws it through the player's system fonts; a font the project chose that lacks it still fails.
- the workflow `init` writes skips pull requests and pushes to `main` that change only documents, the plan or `.gitignore` (`paths-ignore`), so a private repository's Actions minutes last; the push to `main` stays, for the merge check and the caches pull requests read. The game `AGENTS.md` asks for one push per finished piece of work (#256)
- `help` without a name writes a Markdown page (a table each for commands and subagents, and the skills in groups) to `docs/kit-help.md` of the game, or to the temp folder outside one, and prints its path (`path` in `-Json`) instead of a console list; `init -Agents` and `init -Plugin` put the page in the game, and `/kit` shows the file. `help <name>` is unchanged.
- `/kit-review` files its (up to three) proposals as issues in the kit's repository, with the evidence and the exact change, and no longer prepares a branch or pull request in the kit clone
- `benchmark/cost-model.json` uses the means measured over the complete mid tier (six configurations, Haiku to Opus, with and without the plugin), the mid tier's cost ceiling in `game-programme.json` rises from $120 to $180 to fit them, and `benchmark/PLAN.md` records the results, what was lost and the finding that most failures are the answer-length limit.
- `.claude-plugin/plugin.json` declares no `version`, so Claude Code takes every commit on `main` as a new version of the plugin and a game that enables it from GitHub gets each merged change (a pinned version would hold it until the string changed). `release.yml` no longer checks the manifest against the release version (the tag and the changelog section carry it); `doctor`'s issue report and the label's default read the newest changelog heading. `Test-WorkflowLint.ps1` fails if a version comes back.
- the add-on status list records py4godot at 66f4787 (2026-11-14): still a demo by its README, newest release still 4.7-alpha21, so `doctor` keeps calling it a prototype (#263)
- the README opens with the problem (an agent proves a Godot game still works, with evidence), has a quick start that runs on the examples, a choose-your-path section, Core against Advanced and a table of what Hyperdot adds on top of the test frameworks it runs; the roadmap records what remains and the postponed measurements.
- `docs/roadmap.md` records the complete mid tier and the Opus run as done, what remains of them, and the decisions of 2026-11-03 (word limit kept, `www.gstatic.com` to be allowed).
- the game AGENTS.md template is a third shorter (kept: the safety rules and the pointers to skills; cut: flag lists and how-to rules the skills already carry), and the kit's own AGENTS.md moves its self-test table to docs/self-tests.md
- skills that are not about the engine itself lose the `godot-` prefix: `algorithms`, `animation`, `anti-cheat`, `asset-pipeline`, `automation-hooks`, `camera`, `console-cert`, `debug-tools`, `determinism`, `game-ai`, `game-design`, `game-plan`, `input`, `legal`, `llm`, `localization`, `math`, `mobile-web`, `modding`, `multiplayer`, `narrative`, `patterns`, `performance`, `procgen`, `progression`, `release-readiness`, `saves`, `servers`, `steam`, `store-page`, `ui-accessibility`, `ui-flows`, `verify-before-done` and `xr`; five that share a name with a command or runner became `game-audio`, `game-data`, `game-juice`, `game-playtest` and `game-telemetry`. `godot-addons`, `godot-diagnose`, `godot-editor-bridge`, `godot-export-release`, `godot-pitfalls`, `godot-shaders-vfx` and `godot-test-loop` keep it. A game that copied the old folders with `init -Agents` keeps them under the old names until they are deleted and `init -Agents` is run again; with the plugin nothing needs doing. `Test-Skills.ps1` now also checks a skill named as "the `x` skill" or `game-...`.
- `docs/skills-quality.md` records why skill descriptions do not get a "not for X, see Y" clause: 98 routings of 49 messages (14 written to sit between two skills) by a subagent that saw only the names and descriptions all landed on the expected skill, so there was no misrouting to fix.
- `init -Agents` no longer copies the skills and subagents into the game. It writes `AGENTS.md`, `CLAUDE.md` and `docs/kit-notes.md` and enables the hyperdot plugin in `.claude/settings.json`, which supplies the skills, the subagents and the hooks, so nothing in the game goes stale (`-Plugin` is now the same as `-Agents`). New `-CopySkills` copies them for a host that loads no plugins, and is refused in a game that already enables the plugin (each skill would load twice). New `-PluginSource github|local` (default `github`: this repository, `HYPERDOT_KIT_REPO` for a fork, works in cloud sessions, and every commit on `main` is a new plugin version; `local`: the kit's folder, loaded in place); a game that already has the plugin from the other source keeps it unless `-PluginSource` is given, and the old `settings.json` is kept as `.bak`. `init` no longer writes `docs/kit-help.md`, a copy that went stale (`help` and `/kit` write `.godot/kit-help.md`); it names an old copy so it can be deleted. The README, `docs/usage.md`, `docs/reference.md` and the help text say so.
- `soak` still gates on the smallest of three memory slopes, but now reports the other two (`growthWholeWindowPerHour`, `growthFirstHalfPerHour`, `growthSecondHalfPerHour`) and warns, without failing, when the whole-window or second-half slope is over `-MaxGrowthMbPerHour` while the gate passes (a one-time step or a leak that started late: soak longer).
- the Stop hook no longer blocks a session for code that already passed: each `test` run in the history is stamped with the git tree of the working folder (`tree`, tracked and untracked files, without touching the repository's index), and the hook lets the session finish when the tree in front of it is one that passed a full run, whatever the file times say (a checkout, a pull or a merge changes times, not the code). Other content is blocked as before.
- `telemetry` also reports `doctor` and `calendar`, which leave history lines too: `telemetry calendar` gives their runs, pass rate and durations.

### Fixed
- the benchmark review's defects: the label no longer counts a session twice when a continuation of sharded runs reruns it (runs of one chain are one unit, the latest rerun wins whatever the folder order, and each shard has its own run id); `continue_run` of a run of several configurations works (each job takes only its own artifacts, other configurations' folders are skipped, a continuation of a field test is accepted, a run with nothing left to run still writes `results.json`); grading can no longer be bypassed with a `.gutconfig.json` written by a session; a task that spent no tokens is "not run" instead of rating the version A; `-Verify` of a plugin sheet applies its quality factor; the class is read from the printed index; `isolated` in the summary says whether isolation really happened; a shard of the field test gets its share of the ceiling; the label notes runs repeated fewer times than the standard, with sessions not reached or with continued runs missing; the session counts of the 0.1.0 reference runs (192, not 216) and the rebuild recipe of `docs/label` are corrected.
- a build that cannot write its dll because a game a bot run left open still holds it is named: `build-failed` and the `dotnet` and `gdunit4` runners' "reported no test results" reason say which file is locked and, when MSBuild reports it (MSB3027), which process holds it, instead of failing with no diagnostics. `dotnet test`'s output is kept in the results folder (`dotnet.log`, `gdunit4.log`).
- the Self-test selection and input hashes no longer miss a file moved out of a gated path or one with a non-ASCII name, hash two files whose names differ in case as one, or key `local-windows` to the ubuntu image; re-run rows say `hitStale`; the release workflow matches versions whole and never moves the major tag backwards; the Token benchmark always passes a time limit 45 minutes under the job's; pull requests of two forks no longer cancel each other; `release: true` without exports fails; the canary runs upstream code in a job with no write token.
- a first import of a fresh checkout no longer fails `build` and `test` with errors the import itself resolves (a font's `.fontdata`, a theme that loaded before it): when the import prints errors it runs once more, and only the second pass is judged (`importRepeated` in the JSON). A startup error from an autoload in `addons/` (the `project startup` case of `validate`) now names its file and line.
- `bench -Json` (and anything else that wrote a CSV) began its stdout with a PowerShell warning on PowerShell 7.7, which marks `Export-Csv -NoTypeInformation` obsolete, so agents could not parse the result. The flag is dropped (type information has been off by default since 6.0), and `Test-PowerShellPatterns.ps1` flags it as `csv-notypeinformation`.
- `doctor` runs are recorded in the run history, so `status` stops suggesting `doctor` with "doctor has not run on this project" after it has run; the `doctor.changed` and `doctor.release` suggestions, which need a recorded run, now fire, and a new rule, `doctor.failed`, suggests doctor again after a run that found problems (#254)
- `doctor` no longer reports an absolute path in `AGENTS.md` or `CLAUDE.md` as a missing file when it points outside the game and its repository (the kit on the author's machine, a tool folder): such a path belongs to one machine and cannot be checked from another. A missing absolute path inside the game or its repository, and a missing relative file, are still reported.
- every Godot the kit starts runs its C# on .NET 8 when it is installed (`DOTNET_ROLL_FORWARD=Major`, kept if you set your own) instead of the newest runtime Godot's `LatestMajor` picks; on .NET 11 (GitHub's ubuntu-26.04 image 20261111) `godottest` under coverage failed with a CLR assert at shutdown after every test passed (#264)
- the Evals workflow scored a sandbox that refused every command (run 9: `apply-seccomp ... nested userns is capability-restricted`) as a green run. It now lifts the AppArmor user-namespace restriction on its throwaway runner, probes the nested user namespace Claude Code's seccomp helper needs before any case, and fails a run whose result or transcripts show a refused command.
- from the field test: `export` stops before anything is built or downloaded when a preset has no export path (`export-no-path`, which `export-failed` said before) and says `export-template-missing`, with the path Godot looked at, when the export template is absent (`engineErrors[]` now holds the line under "configuration errors:"); `runnerResults[].reason` and the `tests-failed` message say why a runner failed without a failing test (no test results, or a non-zero exit with no recorded failure).
- from a field test on four other people's projects: the mouse wheel is no longer listed as an action with no gamepad binding, and `export -Preset X` on a project with no export presets says `no-presets` instead of `preset-not-found`.
- flows run one physics tick per drawn frame (`Engine.max_physics_steps_per_frame = 1` for the run), so an action a step sends is handled before the next step reads the game; on a machine that fell behind, several physics ticks ran inside one drawn frame and a flow could assert the state from before a press (#253)
- the `flows` runner's autoload reset (`hyperdot_reset_flow_state()`) also finds a C# autoload's `HyperdotResetFlowState()`; Godot calls a C# method by the name it is written with, so the snake_case name would have had to be written into the C# code.
- the `flows` runner no longer lets one flow reach the next through shared state: after each flow the tree is unpaused, `Engine.time_scale` is back to 1 and nodes the game added to the root window (a toast, a popup layer) are freed, with a note in the log of what was found. A flow that left the tree paused used to fail the next flow with a message about something else. Autoloads keep their own state: a flow that changes one puts it back itself.
- from the retest on a real game: `doctor` no longer calls an absolute path that exists, or the folders a line says not to commit or a run creates (`.godot/`, `bin/`, `obj/`, `test-results/`, `build/`), missing instruction files; the godot-mcp add-on's "Failed to start server ... Already in use" (the editor is open on the project) is known noise; and an export of a Windows Desktop or Linux preset whose template files are not installed fails with `export-template-missing` before the import and the build, not after them.
- `help` without a name no longer rewrites `docs/kit-help.md` in the game (a tracked file, which left the working tree dirty); it writes `.godot/kit-help.md`, a folder no repository tracks, and prints the path. `init` still puts a first copy in `docs/kit-help.md` once and never rewrites it.
- The Stop hook no longer skips game files in folders named `build`, `bin` or `obj` below the project root (`scripts/build/placer.gd`, `levels/bin/x.tscn`), ignores files outside the game (a monorepo's `package.json`) and `plan/plan.json`, and says "Game files changed"; the `ci` plan gate also accepts the kit's composite action and a GitLab include; `flows` names the capped frame count of `wait_until`; the eval graders `unchanged` and `used-kit` can fail on real misuse (`ran-tests` added); the Stop hook, the tag `v1`, `init`'s files, the plugin's token-benchmark result, SECURITY.md (downloads are not checksum-verified, `npx -y` MCP entries are not pinned), NOTICE, AGENTS.md and several counts in the documentation are corrected.
- `init` no longer rewrites a workflow that calls the kit by its old name (`Godot_TestSuite`) into a copy of an existing `hyperdot.yml`: a game that had both ended up with two identical workflows on the same triggers and concurrency group, each cancelling the other, so Export and Release failed after 0 seconds on every pull request. It leaves the old one as it is and says to delete one; it also counts a workflow under either name before it writes `hyperdot.yml`. `doctor` warns when two workflows call the kit, and says when they share a concurrency group. Fixes #221.
- `doctor` no longer reports `.claude/settings.local.json` as a missing file named in agent instructions; it is per-machine and never in a clone.
- `Get-HyperdotLabel.ps1 -Introduce` rounds a median that is exactly halfway between two thousands up (2,500 to 3,000), as the judge's median does, instead of to the even thousand; the docs now say how to keep two versions of a model's sheets apart across folders, and count 51 skills
- with several `runs` in `juice.json`, each run got the earlier runs' `args` appended (a local variable was the `-GameArgs` parameter under another case), so a later run could play the wrong stage; each run now gets only its own `args` and `-GameArgs` (#290).
- the `juice` runner no longer fails a run for a Godot crash in its shutdown after every rule was judged (exit 134 from the mono teardown, `FATAL: Condition "csharp_lang && ..."`): that is a warning naming the FATAL line. A crash before every rule was judged, an engine error before the crash and any other nonzero exit still fail.
- a batch of defects in the kit's libraries. Failure text with control characters (BEL, ESC, NUL) no longer makes the JUnit report unreadable. `credits` now fails with `engine-notices-failed` when Godot cannot read the engine's notices, instead of writing a file without Godot's licence. `-Frames` below 1 and, for `playtest`, a `-HotspotCell` of 0 or less are refused as `invalid-arguments`, and `export -Preset` is checked before Godot's templates are downloaded. `status` skips history lines that are not runs, reads the history once, and the history is cut to the newest 2,000 lines. A failed `bench -Sweep` run no longer reports an earlier sweep's numbers. The `data` runner no longer crashes on a table without `fields` or on an invalid `pattern`. `plan` and `plan -Do add` work on a plan with no `tasks`, and the plan keeps the game's name as written. `sfx` gives different seeds different files and makes a sound named twice once. A tiny `playtest` cell is reported as `invalid-playtest-config` instead of crashing. `soak` refuses a `-Seconds` too short to measure memory growth when `-MaxGrowthMbPerHour` is set.
- `plan`'s `slice.export`, `jam.export` and `launch.gold` gates promised `export -Run` but checked only that an export preset exists, so they held even after a failed export. A new check, `export-run`, holds when every preset this machine can launch passed its newest `export -Run` and was launched; `export` records `run`, `presets` and `launched` in its history line, trimming keeps the newest `export -Run` line, `nextActions` gives each open gate's `detail`, and once a later phase has begun a newer failure is a warning instead of reopening the gate. Plans made before keep `preset`, and `plan` warns about those three gates until they use `export-run` (#288).
- `plan`'s `prototype.verdict` gate passed on any text in `docs/DECISIONS.md`, a placeholder verdict included. A new check, `verdict:<path>`, holds only on a line recording one verdict (`Verdict: PROCEED`, `PIVOT` or `KILL`, any case, also as a list item, heading or in bold), not on the template's list, a placeholder in parentheses, an HTML comment or a code block; the gate's `detail` says what is missing. Plans made before keep `file:`, and `plan` warns about `prototype.verdict` until it uses `verdict:docs/DECISIONS.md`. The `game-plan` skill says the verdict line is the user's decision (#289).
- `release.yml` takes a `major_tag` input (a 0.x release names `v1` there, as games pin `@v1`; the default stays `v<major>`), leaves a version tag and release that already point at the commit as they are, and still refuses a version tag at another commit.
- `release.yml` checks out the workflow's own commit and reads the changelog and plugin manifest of the commit to release with `git show`, so releasing a commit older than the notes script works.
- from the retest: `export-template-missing` now fires on Godot 4.7.2, which prints the template path on the line after the message (it was read only from the same line), and the `l10n` `missing glyphs` case names the file and line of an engine error under an autoload (`at res://addons/…:20`) like `validate` does.
- from the third retest: `doctor` no longer fails a `GODOT_BIN` that is a patch release of a major.minor pin (a `Godot.NET.Sdk/4.7.0` pin reads as 4.7 and Godot 4.7.2 meets it), the static `[TestSuite]` warning sees a doc comment between the attribute and the class, the stale-workflow check also reads the repository root's `.github/workflows` for a project in a subfolder, `export` skips the runner search (tens of seconds in a large project before an error such as `no-presets`), and the `missing glyphs` failure for the default font says it is drawn only through the player's system fonts and how to accept that (`l10n.json` `glyphIgnoreFonts`).
- the `flows` and `validate` runners no longer fail a run for a Godot crash in its shutdown (exit 134, the mono teardown's `FATAL` line) after every flow or file ended ok: one warning names the FATAL line, and the "Leaked unsafe reference" errors after the `done` line are not read as the project's (they were a failed `project startup` case). `flows` and `juice` run once more after a crash that came before every flow or rule was judged, and fail if it crashes again; a crash after a failed case and any other nonzero exit still fail. Fixes #239.
- five skills (`mobile-web`, `multiplayer`, `servers`, `steam`, `store-page`) had a `: ` inside an unquoted `description`, which is not valid YAML, so a strict parser refused their front matter; the descriptions are quoted now, and `Test-Skills.ps1` reports a plain `name` or `description` that is not valid YAML (`frontmatter-yaml`, with the fixture `bad-yaml`).
- the project file search skips every folder whose name starts with a dot (`.git`, `.godot`, `.claude`), as Godot does, not only `.godot`. On Windows `.claude/worktrees` holds whole copies of the game, which the `architecture` scan read, so other branches' `Benchmark.cs` and `GameManager.cs` showed up as the game's warnings; they also made every walk slower. Fixes #232.
- the soak self-test no longer asserts that a flat C# server draws no growth warning; on a 30 s window on a shared runner the warning (slopes that disagree) appears now and then, and a real leak is still failed by the growth limit.
- `soak` read a one-time memory step (a JIT tier, a GC resizing its heap) as hours-scale growth: over a 20 s window 1.5 MB looked like 400 MB/h and failed the C# self-test on GitHub runners. The growth is now the smallest slope over the whole window and over each half, so only memory that grows throughout counts; the C# self-test also measures for 30 s.
- Steam documentation corrected against Valve's partner pages and SDK 1.65, each point re-read in its source: asking players for reviews from inside the game breaks Valve's rule (`store-page`); the trailer page does name containers, bitrate and aspect ratios; the 21-day wait is Valve's rule for a first few titles; a beta key removes the game from a wishlist; a release date delayed over 24 hours inside two weeks drops the game from the Personal Calendar; only four screenshots flagged for all ages give hover previews; Steam counts only the first 20 tags; the rich presence key limit is 20 in Valve's docs and 30 in the SDK 1.65 header; Auto-Cloud has twelve roots and Root Overrides; Valve's stats guide still teaches the removed `RequestCurrentStats`; Steam Frame has its own compatibility review; "Official GS" needs the servers' IP range.
- `doctor`'s Steam store checks now follow Valve's pages: the shortcut icon may be an `.ico` (one holding a 256x256 image) as well as a PNG, localized screenshots (`screenshot1_japanese.jpg`, a Steam language name as the suffix) count with their screenshot in the store art and press kit checks, a trailer in another codec than H.264 and AAC is INFO instead of a warning (Steam transcodes many formats), a low bitrate and an aspect ratio other than 16:9 or 4:3 are INFO, an unsupported audio sample rate stays a warning, the tags message says Steam counts only the first 20, and `plan` words the 21-day fee wait as Valve's rule for a first few titles.
- self-tests that could not fail now fail on a broken rule: the skill validator's six unexercised error rules have broken fixtures, `Select-Jobs.ps1` is held to its Audio, BuildSize and Addons rows, playtest event limits, the data runner's bounds, solution search at the git root and by name, doc links with titles and reference definitions, the telemetry trend threshold, handoff text limits, changelog category order and exact version match, filtered-run build failures, the input hash contents and function shadowing in blocks; the process time limit ceiling is tighter, the install lock test waits for the first run instead of sleeping, and three Godot tests remove their temporary folders.
- the weekly canary no longer files an issue each time `gdUnit4.test.adapter` publishes a release that wants a pre-release `gdUnit4.api` (3.2.0 needs 5.1.0-rc6; the newest stable is 5.0.0, so the pair cannot restore, NU1605). `Update-Versions.ps1` reads each candidate NuGet package's dependencies and does not propose one that needs a newer version of another pinned package than that package's newest stable, with a note saying what it waits for; `-DependencyFile` replaces the NuGet lookups for tests.
- The Web self-test job runs on ubuntu-24.04, because the Vulkan validation layer on 26.04 reports Godot 4.7.2's own host-access barriers and fails the GPU validation test; Playwright is 1.64.1, which works on 26.04

### Removed
- the migration of a plan left by the earlier board sync (its card ids and block are no longer dropped by the first `plan -Do sync`; leftover fields are ignored) and the field of `sync` in `plan -Json` that counted them; every mention of the earlier service is gone from the docs, skills, tests and changelog.
- The GitLab CI template (`ci/gitlab/`), which never ran on a GitLab runner and had no known users, with its self-test and the `ci` plan gate's GitLab check; `test` still writes every runner's results as JUnit (`junitDir`) for any CI that reads JUnit.

### Security
- Godot's editor and export-template downloads are checked against the `SHA512-SUMS.txt` Godot publishes beside each release; a mismatch deletes the file and stops with the new `checksum-mismatch` code, and a release that publishes no sums (4.0) is used with a note in the log
- Every action the workflows use from another repository (`actions/checkout`, `cache`, `upload-artifact` and the rest) is pinned to a commit SHA with its version in a comment, `tests/Test-WorkflowLint.ps1` fails on an unpinned one, and a Dependabot config proposes the weekly bumps
- The Claude Code CLI and uv that the workflows install into jobs holding a token are pinned to a version; `Update-Versions.ps1` and the weekly canary propose bumps, and the workflow lint fails on an unpinned install
- `init -Mcp` and `-McpDiagnostics` write the npx servers at a pinned version (`@satelliteoflove/godot-mcp@4.1.11`, `@ryanmazzolini/minimal-godot-mcp@0.1.6`) instead of whatever is newest; `Update-Versions.ps1` and the weekly canary propose the bumps

## 0.1.0 - 2026-10-27
- **PowerShell review: six bugs fixed, four new syntax-tree checks.** `bench -Sweep 'particles=100 0',5000` named `' '`
  instead of the values (`$Matches` was overwritten before the message); eleven `Resolve-Path` calls on the kit's own
  tools now take `-LiteralPath` (a kit under a folder with `[ ]` found nothing); `Start-Process -ArgumentList` in four
  self-tests quotes its paths; `-replace` replacements built from a version line, a `[dotnet]` entry, a home folder, a
  licence line and a csproj block are script blocks, so a `$` in the data is not read as a group; the Stop hook and every
  child `pwsh` in the scripts start with `-NonInteractive`; `Test-SkillFixtures.ps1` pins strict mode.
  `Test-PowerShellPatterns.ps1` gains `resolve-path-wildcard`, `start-process-arglist`, `replace-interpolated` and
  `pwsh-interactive`, a strict-mode check for every entry and test script, and a check of the hook's arguments;
  `Test-BenchSweep.ps1` checks the refusal's message.
- **PowerShell review, second pass.** Every `ConvertTo-Json` now passes `-Depth` (nested data was cut at depth 2 and a
  warning reached stdout); `Plan.ps1`'s `file:` check, `Publish-Release.ps1` and the Godot templates copy read their paths
  literally; `Test-ReportPins.ps1` called `Install-Godot`, which does not exist (it failed on any machine without
  `GODOT_BIN`). New checks in `Test-PowerShellPatterns.ps1`: `json-depth`, `path-wildcard`, `duplicate-parameter` and
  `undefined-command`. `Set-ProjectVersionLine` (export's version patch) is a function so a `$` in the line is tested, and
  `tests/Test-KitPaths.ps1` runs the textsize runner from a folder named `kit [v2]` and keeps a `$` in `solution_directory`.
- **The first mid run of the staged programme, stopped halfway** (token-benchmark run 44, $34.53, 294 of 540 sessions
  graded; `benchmark/PLAN.md`). The owner's plan ran out of usage after 65 minutes of twenty parallel jobs, and a git
  race ended four parts early (fixed in nick-vas/hyperdot#134). Milestones cost about $0.40 to $0.50, not the guessed
  ten Sonnet tasks: `cost-model.json` now uses the measured means, and the mid tier is priced at $67.71. It also found
  a grading fault to decide on: the `unchanged` rule fails sessions that only add tests to a kept test file.
- **The judge's calibration applies the owner's rule over every set at once.** `Get-JudgeAgreement.ps1 -Calibration
  benchmark/calibration` holds a judge to the owner's own agreement on a blind re-judge (6 of 10, read from
  `calibration/retest-1.json`, whose stated result it checks against its pairs) and to 90% agreement with itself over
  every pair of every set; it measures agreement on every set but one marked `forAgreement: false` (the first, judged
  with the old rubric shown), with each re-judged pair's newer verdict, turned back where A and B were swapped. The
  workflow's `calibrate` input is now a switch: it rebuilds every set's pairs from its run and tries the judges
  `cost-model.json` prices, cheapest first, in place of one run at fixed bars of 80% and 90%. Recomputed from the saved
  judgements, it reproduces every recorded agreement and corrects one figure: Haiku's agreement with itself in the fourth
  calibration was 81%, not 84% (`tests/Test-ReviewPairs.ps1`).
- **A benchmark run can be split into parts.** `Invoke-TokenBenchmark.ps1 -Shard k/n` runs every n-th session of the
  run from the k-th, with its own estimate and its share of the ceiling; the n parts together hold each session once
  (`tests/Test-GameBenchmark.ps1`). The workflow's `shards` input runs each configuration as n parallel jobs: the
  mid tier, 135 sessions a configuration at three to four minutes each, outlasts one job's 330 minutes.
- **The staged programme's first run over all ten genres** (the min tier, token-benchmark run 43, $6.58): 66 of 80
  sessions passed and no task failed for every configuration (`benchmark/PLAN.md`). It found two faults in the kit, both
  fixed with regression tests: isolated sessions inherited no writable XDG folders, so Godot's config ended up inside a
  game (`Isolation.ps1` now gives each session its own, checked in `tests/Test-BenchmarkIsolation.ps1`), and the
  `validate` runner read `.tres` files in `test-results/` and `TestResults/`, which it now skips like the kit's file
  search (`tests/Test-StaleTres.ps1`). `cost-model.json`'s task prices are this run's mean costs.
- **The staged programme's min and mid tiers cover all ten genres.** min runs one stage of each genre (every language
  and stage pair at least once), 20 tasks a configuration, estimated at $5.70 for all four configurations; mid runs one
  stage of each genre in each language, 40 tasks and 5 milestones a configuration, three times, estimated at $100.20
  under a ceiling raised from $50 to $120. The runner now refuses a tier milestone that starts from none of the tier's
  cells, which it used to drop without a word.
- **The eval graders are tested against real sessions.** `tests/Test-EvalGraders.ps1` checks every regex and tool_used
  grader in `evals/` against 14 sessions from Evals runs 4 to 7 (`tests/eval-grader-fixtures/`, made from the
  workflow's artifact by `tests/New-EvalGraderFixture.ps1`). A stand-in for `claude plugin eval` first gives all 21
  verdicts the runs recorded; then each grader as it is now must agree with a person's reading of each session, and
  each needs a real session to pass and one to fail, or a reason in `gaps.json`. It found `explain-failure`'s `location`
  grader failing three right answers that put a number between the file and "line 7" (runs 5 and 6); its pattern now
  allows that. Model graders are not checked: they need a model.
- **The side-by-side judge can vote.** `Invoke-SideBySide.ps1 -Votes <n>` (and the token benchmark's `votes` input with
  `calibrate`) judges each order of a pair n times in fresh sessions; the order's choice is the majority, a tie is even,
  and an order where fewer than half the votes named a choice is an error. Each pair keeps its votes in
  `preferences.json`. A cheap judge that changes its mind between runs can then be calibrated by its majority.
- **A PowerShell guide, PSScriptAnalyzer on every script, and a check for the anti-patterns the code has dropped.**
  `docs/powershell.md` holds 78 lessons for anyone writing PowerShell here, merged from the official PowerShell
  documentation and the PowerShell Community blog, by theme (errors and exit codes, strict mode and the pipeline,
  culture and encoding, native commands, paths, parameters, JSON, concurrency, performance, secrets, tooling), each with
  why, a quoted source and whether it was run; the ten that cost most come first, then the sources' advice that does not
  hold on 7.6 under strict mode on Linux, and what checks each lesson. AGENTS.md's "Working here" gains the most
  consequential ones. The lint job's PSScriptAnalyzer step pins 1.25.0, scans every tracked `.ps1` (tests and the GitLab
  run step too) with Information severity, annotates each finding and fails on any; the wider scope found two dead
  variables in tests, now gone. `tests/Test-PowerShellPatterns.ps1` reads every script's syntax tree for ten patterns
  with no use left (`continue` in a pipeline block, `$null` on the right, `Invoke-Expression`, `[IO.Path]::Combine`,
  `$PSBoundParameters.Name`, a lowered `$ErrorActionPreference`, relative literal paths to .NET, `-Version Latest`,
  Windows-only aliases, one file read and written in one pipeline), each proven on a fixture file of its own.
- **PowerShell 7.6 or newer is required (breaking for PowerShell 7.2 to 7.5).** Every script now starts with
  `#Requires -Version 7.6`, the current LTS release: 7.2 left support on 8 November 2024, and 7.4 and 7.5 leave it on
  10 November 2026, while 7.6 is supported until 14 November 2028. GitHub's runner images already ship 7.6 (Ubuntu
  22.04 and 24.04, Windows Server 2022 and 2025, macOS 15), so the action and the workflow need nothing; on an older
  PowerShell the kit stops at once with PowerShell's own "#requires" message. To upgrade: `winget install
  Microsoft.PowerShell` (or `winget upgrade`) on Windows, `brew upgrade --cask powershell` on macOS, and Microsoft's package
  repository (`apt install powershell`) or the release tarball on Linux; self-hosted runners need the same. The GitLab
  template's .NET 8 SDK image carries PowerShell 7.4 (the global tool follows .NET 8, and 7.6 is built on .NET 10), so
  its `before_script` now unpacks PowerShell 7.6.9's self-contained Linux build into `.hyperdot-cache/pwsh/` (cached),
  puts it first on PATH and stops the job if `pwsh` is still older; games still build with the image's .NET 8 SDK.
  `tests/Test-GitLabTemplate.ps1` holds the template to the floor of `hyperdot.ps1`.
- **A staged-programme task's `unchanged` files may now gain lines.** The rule failed a session with `changed <file>` for
  any difference, so every session that added regression tests to the existing test file failed (run 44's
  `racing.alpha.csharp.fix-bug` passed 0 of 10 although they had removed nothing). A kept file now passes when every
  original line is still there in its order, line endings aside; a missing file and a changed, removed or reordered line
  still fail. Before the hidden tests, mutants and the suite run, the kept files are put back as they were, so added code
  cannot weaken the original tests (`newTests` counts the additions first). Self-tested in `tests/Test-GameBenchmark.ps1`.
- **The GDScript arena game turns the server relay off, as the C# port already did.** `NetSession.host` left
  `SceneMultiplayer.server_relay` on, so when a player connected the engine sent news of it to every other peer, also
  to one whose disconnect it had received but not yet reported (its channels are closed by then): an engine error,
  "Unable to send packet on channel 0, max channels: 0", that failed `soak` with `engine-errors` now and then (2 runs
  in 20 on the reference of `arena.beta.gdscript.fix-performance`, whose clients leave and rejoin all the time). Players
  only talk to the server, so nothing else changes. The base game and its `milestone-alpha` solution are fixed.
- **The self-test runs what a change needs.** It ran 35 jobs and about 500 runner-minutes for any change, 84% of them in
  the 20 pairs of the staged programme, and every push to a pull request branch started two runs. Now a `changes` job
  (`.github/scripts/Select-Jobs.ps1`, held by `tests/Test-SelectJobs.ps1`) lists the changed files and a pull request runs
  lint alone for documentation, the jobs that exercise the changed libs, tools and tests otherwise, one pair for a changed
  game and a sample of three pairs for the programme's own code; a push to `main`, the nightly run (02:23 UTC) and a
  manual run still run everything, and keep a few slow steps that have never failed for the full runs only. Branches are
  tested through their pull request, not on push, and the coverage floors are enforced on the full runs. Git's background
  maintenance is off in CI. [docs/ci.md](docs/ci.md) has the rules, the measured cost and the failure record of the last
  100 runs; faster game jobs were measured and not shipped (no gain beyond noise).
- **Game copies no longer race git's background maintenance.** Since git 2.54 a commit's automatic maintenance packs
  loose objects in a detached process ("geometric" strategy), and a beta or release game commits over a hundred: the
  benchmark's copy of the game or its `.git`, made a moment later, lost files under it ("Could not find a part of the
  path .git/objects/..."), which ended four parts of token-benchmark run 44 and two self-test jobs on the runners' git
  2.55. `New-GameWorkspace` now sets `gc.auto 0`, `gc.autoDetach false` and `maintenance.auto false` before the first
  commit, which also covers the git commands a session runs, and `tests/Test-GameProgramme.ps1` checks every workspace
  it grades.
- **A website, built from the docs.** `site/Build-Site.ps1` turns `README.md`, `CHANGELOG.md` and every
  `docs/**/*.md` into a GitHub Pages site (https://nick-vas.github.io/hyperdot/): the home page, the quick start, the
  label page with the labels and information sheets in `docs/label/`, a benchmark page with the reference runs, a docs
  index with each doc's first sentence and a search over titles and headings, and the changelog. It uses Markdig, the
  engine `ConvertFrom-Markdown` loads, with GitHub's extensions only, so heading ids, carets and escaped pipes in tables
  come out as on GitHub; links to other repository files go to GitHub at the built commit. No framework and nothing
  from another host; light and dark colours at WCAG 2.2 AA; readable at 360 px. `.github/workflows/pages.yml` builds,
  checks and publishes it on every push to `main` that changes the docs; `tests/Test-Site.ps1` checks every page, link,
  anchor and label, and proves the check fails on a broken link and anchor. `pwsh site/Build-Site.ps1 -Serve` previews
  it; [docs/site.md](docs/site.md) has the one owner step (Settings, Pages, Source: GitHub Actions).
- **The staged programme's CI check runs one job per genre and language**, and only for the pairs whose game
  changed (every pair when the harness or the programme changed, or when started by hand). One job per language ran
  every genre in turn and no longer fitted its 150 minutes with ten genres; a pull request that adds one genre now
  checks that genre alone.
- **Two C# test runs at once no longer take each other's results.** gdUnit4Net's adapter reaches the Godot it starts
  over a pipe with a fixed name, `gdunit4-message-pipe`, which .NET on Linux and macOS keeps as a socket in the temp
  folder. Two `dotnet test` runs that shared `TMPDIR` (two `test` runs on C# projects, two staged-programme checks)
  shared that socket: the second run's Godot replaced the first's, both adapters reached the second Godot, and the first
  run failed with `gdUnit4 (tests not run)` ("found 32 tests but ran 0") although its tests were fine. The `dotnet`
  and `gdunit4` runners now give each `dotnet test` a temp folder of its own through the `.runsettings`, in `/tmp`
  when `TMPDIR` is too long for a socket path (which made every gdUnit4 run fail before), and remove it after the run.
  `tests/Test-DotnetTempDir.ps1` runs two at once against a stand-in `dotnet` and Godot. Windows names its pipes
  globally and is unchanged.
- **The racing game in C#.** Cinderloop now has its C# version (`benchmark/games/racing/csharp/`), written from the
  language-neutral contract in its `DESIGN.md`: the same scenes, scene tree, node names, data files, flows, bot and
  juice runs and log lines, with 69 gdUnit4 tests in place of the GUT ones and a Linux export only. Its race keeps
  GDScript's arithmetic, doubles for numbers and float vectors with the number cast where they meet, the engine's
  `Geometry2D` and its `wrapf`, `posmod` and `roundi` as the engine defines them, so a race runs the same to the last
  bit: the bot run prints the same log lines as the GDScript one, line for line, for seed 1 and for other seeds, rival
  counts and starting tracks. Its four stages carry the same 17 tasks and three milestones as the GDScript version,
  each with hidden checks in C# and a reference solution, five with a decoy; all pass
  `tests/Test-GameProgramme.ps1 -Genre racing -Language csharp`. `DESIGN.md`'s "As built" records the port's choices.
- **The idle game in C#.** Duskhive now has its C# version (`benchmark/games/idle/csharp/`), written from the
  language-neutral contract in its `DESIGN.md`: the same scenes, scene tree, node names, data files, flows, portrait
  layout, bot and juice runs and log lines, with 62 gdUnit4 tests in place of the GUT ones and Linux and Android
  exports. Glow is a double in both, worked out with the same operations in the same order and no `Math.Pow` or
  `Math.Log` in the simulation, and every number is written with the invariant culture, so the bot run prints the same
  3,487 lines as the GDScript version, game times included, on a machine set to German too. Its four stages carry the
  same 17 tasks and three milestones as the GDScript version, each with hidden checks in C#, a reference solution and
  a decoy; all pass `tests/Test-GameProgramme.ps1 -Genre idle -Language csharp`. `DESIGN.md`'s "As built" records the
  port's choices.
- **The multiplayer arena in C#.** Glimmerpit now has its C# version (`benchmark/games/arena/csharp/`), written from
  the language-neutral contract in its `DESIGN.md`: the same scenes, scene tree, node names, data files, flows, wire
  messages, bot and juice runs and log lines, the same dedicated server and soak roles, with 54 gdUnit4 tests in place
  of the GUT ones and Linux exports only. Both versions move in whole pixels and trace shots and steer bots with the
  engine's 32-bit vectors and seeded generator, so the bot matches of seeds 1-20 end alike and the bot run prints the
  same 485 lines, line for line. Its messages are the engine's `var_to_bytes` bytes, written in managed code (a test
  holds them to `GD.VarToBytes` byte for byte), since engine dictionaries for every message kept the server's memory
  climbing until the garbage collector ran; the dedicated server collects its first generation once a second, stops
  with 0 on SIGTERM, and passes a 120-second `soak` at 200 MB/h. Its four stages carry the same 17 tasks and three
  milestones as the GDScript version, each with hidden checks in C# and a reference solution, five with a decoy; all
  pass `tests/Test-GameProgramme.ps1 -Genre arena -Language csharp`. `DESIGN.md`'s "As built" records the port's
  choices.
- **The roguelite in C#.** Wickerdeep now has its C# version (`benchmark/games/roguelite/csharp/`), written from the
  language-neutral contract in its `DESIGN.md`: the same scenes, scene tree, node names, data files, flows, bot and
  juice runs and log lines, the same `--swarm=N` load, with 44 gdUnit4 tests in place of the GUT ones and a Linux
  export only. Both versions generate with the engine's seeded generator, its draws in the same order, so a seed gives
  the same floor and the enemies the same paths: the floors of seeds 1-20 and the bot's play of each match, and the bot
  run prints the same log lines, line for line. Its four stages carry the same 17 tasks and three milestones as the
  GDScript version, each with hidden checks in C# and a reference solution, most with a decoy; all pass
  `tests/Test-GameProgramme.ps1 -Genre roguelite -Language csharp`. `DESIGN.md`'s "As built" records the port's
  choices.
- **The judge's calibration runs in CI.** `token-benchmark.yml` with `calibrate: <run id>` rebuilds the blind pairs
  of that run, checks they are the ones the owner judged (`benchmark/calibration/pilot-1.json` holds the verdicts and
  the answer key's hash), and has the candidate judges, cheapest first, judge them both ways until one agrees with the
  owner on 80% and with itself on 90%. A judgement that fails or names no choice is now an error, not "even": it
  fails the side-by-side run and counts as neither agreeing nor consistent, so a broken judge cannot pass.
- **The judge's rubric rewritten from the owner's verdicts.** The first calibration (Haiku and Sonnet both agreed with
  the owner on 53%) showed the rubric discounting what the owner values: an answer that explains the change with the
  context the next developer needs now counts for the work, "as small as the task allows" is gone, and work that
  does different parts of a task is even. A second blind set (`Invoke-SideBySide.ps1 -ReviewIdPrefix q`, shown
  without the rubric) checks it on pairs it was not written from.
  On it (run 34) neither judge passes either: Haiku agreed with the owner on 56% and with itself on 81%, Sonnet on
  50% and 63%, mostly by picking the same position in both orders; `benchmark/PLAN.md` records it.
  Opus (runs 35 and 36) no longer depends on the order (2 flips in 31 pairs) but agrees with the owner on 53% and 69%
  of the two sets, so no judge is pinned yet.
  The owner's blind re-judge of ten pairs (`benchmark/calibration/retest-1.json`) agreed with their earlier verdicts
  on 6, and on 2 of 5 from the first set, judged under the old rubric. Against that, Haiku and Sonnet with the
  rewritten rubric agree with the owner on 62% and with themselves on 81% and 74%; Opus on 71% and 94%.
  Haiku with ten votes per order (runs 41 and 42) stays at 62% and 81%: its order bias is steady, not noise.
  **The judge is pinned: Opus** (`claude-opus-5-5`), by the owner's rule: at least the owner's own agreement with
  themselves on the re-judge (60%), and 90% with itself. `cost-model.json` prices its judgement at $0.05.
- **The staged game programme's idle genre**, Duskhive, in GDScript (`benchmark/games/idle/`). A moth hive gathers
  glow at dusk: five producers whose prices grow geometrically, Buy 1, 10 or as many as the glow pays for, upgrades,
  and a dawn that trades a run's glow for embers. Every number is in data checked by the `data` runner; glow is a
  double printed with suffixes and two-letter groups past 2^53 and 1e36, never in scientific notation, with a tested
  tolerance and no `pow()` or `log()` in its simulation code; time away is paid from the saved clock, capped at
  eight hours and immune to a clock set back; saves of the previous version keep their embers. The release candidate is
  a portrait layout for phones, tablets and the Web (a SafeArea autoload, the `layout` and `textsize` checks; English,
  German and French), 62 GUT tests, five flows, a bot that greets six dawns with `--speed=60`, juice for every event,
  Linux, Web and Android presets, store art, credits and a plan; its four stages, tasks and milestones each have hidden
  checks, a reference and a decoy, and pass `tests/Test-GameProgramme.ps1 -Genre idle`.
- **The staged game programme's racing genre**, Cinderloop, in GDScript (`benchmark/games/racing/`). Four little cars
  race from above on three loops of cinder road: a car on a fixed physics step whose rates are all per second (drag
  taken implicitly, so the top speed and a lap's time are the same at any tick rate and nothing in the simulation
  calls `exp()`), laps counted by checkpoint gates crossed in order and direction, three AI rivals braking to a speed
  profile of the racing line, the best lap kept as a ghost of quantised inputs that drives it again exactly, a chase
  camera that looks ahead and eases by the second, and keys rebound in Settings while the gamepad keeps its bindings.
  The release candidate has 69 GUT tests, five flows, a bot that wins the championship from the back of the grid,
  juice, three languages, store art captured from the game and credits. Its four stages carry 17 tasks and three
  milestones, each with hidden checks and a reference solution, several with a decoy; all pass
  `tests/Test-GameProgramme.ps1 -Genre racing -Language gdscript`. `DESIGN.md` holds the language-neutral contract
  for the C# port, which is still to come.
- **The staged game programme's multiplayer arena**, Glimmerpit, in GDScript (`benchmark/games/arena/`). Up to four
  glimmers fight last-one-standing rounds in a walled pit, first to three; bots fill every empty slot, so tests and
  the bot run need no second machine, and players join and leave in the middle of a match. An authoritative server,
  client prediction and reconciliation in whole pixels, hits decided by the server's own trace, an in-process link
  that simulates the delay ENet cannot, ENet through `send_bytes`, and a dedicated server that takes part in `soak`
  with clients that leave and rejoin. The release candidate has 51 GUT tests (ENet in one process among them), four
  flows, a bot run with a guest who walks out and rejoins, juice, three languages, store art rendered from the game
  and credits. Its four stages carry 17 tasks and three milestones, each with hidden checks and a reference solution,
  most with a decoy; all pass `tests/Test-GameProgramme.ps1 -Genre arena -Language gdscript`. `DESIGN.md` holds the
  language-neutral contract for the C# port, which is still to come.
- **The narrative game in C#.** Saltmere Crossing now has its C# version (`benchmark/games/narrative/csharp/`), written
  from the language-neutral contract in its `DESIGN.md`: the same scenes, scene tree, node names, story data,
  translations, flows, bot and juice runs, with 53 gdUnit4 tests in place of the GUT ones and a Linux export only. The
  story check searches in the same order, so the bot takes the same ways and its run prints the same log lines, line for
  line. Its four stages carry the same 17 tasks and three milestones as the GDScript version, each with hidden checks in
  C# and a reference solution, most with a decoy; all pass `tests/Test-GameProgramme.ps1 -Genre narrative -Language
  csharp`. `DESIGN.md`'s "As built" records the port's choices.
- **The tower defence in C#.** Bramblegate now has its C# version (`benchmark/games/towerdefence/csharp/`), written
  from the language-neutral contract in its `DESIGN.md`: the same scenes, scene tree, node names, data files, flows,
  swarm bench scene, bot and juice runs and log lines, with 63 gdUnit4 tests in place of the GUT ones and a Linux
  export only. Paths come from `AStarGrid2D` with the same settings, pest speeds from the engine's seeded generator, and
  movement keeps GDScript's mix of doubles and 32-bit vectors, so a seed plays the same battle in both: the bot run
  prints the same lines at the same game times, and the bot's results on every map match for seeds 1 to 10, path
  searches included. Its four stages carry the same 17 tasks and three milestones as the GDScript version, each with
  hidden checks in C# and a reference solution, most with a decoy; all pass `tests/Test-GameProgramme.ps1 -Genre
  towerdefence -Language csharp`. `DESIGN.md`'s "As built" records the port's choices.
- **Bug reports pinned on their level.** `ci/godot/templates/addons/hyperdot_report_pins/`, an add-on a game copies:
  `bug_report.gd` saves the feedback key's report (`user://reports/<time>.json`: the line typed, the scene, the
  player's position and the camera's view in 2D or 3D, the seed, the commit, a screenshot), and the editor plugin pins
  each report of the open scene on it (a dot where the player stood, a ring where the camera was) and lists them in a
  Reports dock with the seed to replay. GDScript, so C# games use it too with no build. `tests/Test-ReportPins.ps1`.
- **`doctor`'s Steam names follow constants and the solution.** An achievement, stat or `steam_display` value passed
  as a string constant (C# `const string` or `static readonly string`, several to a line; GDScript `const`) is checked
  like a literal, and the solution's C# outside the Godot folder is read too, less its test projects. The C# example's
  `BreakoutProgress` names were invisible before; the example now keeps `steam/achievements.json` and
  `steam/rich_presence.vdf`, which `doctor` checks them against.
- **`placement` reads limits from C# too.** A `placement.json` limit may name a C# file and field
  (`"res://Tuning.cs:Reach"`): a `const` or `static readonly` field set to a number, `true`, `false`, a plain string or
  arithmetic on the file's other such fields (`JumpVelocity * JumpVelocity / (2f * Gravity) + BodyHeight`, divided as C#
  divides), read from the source past comments, since Godot gives no constants for a C# script. A field it cannot work
  out (`Mathf.Pi * 2`) is refused by name. The standard build reads it as well as the .NET one.
- **The staged game programme's seventh genre: a narrative game**, Saltmere Crossing, in GDScript
  (`benchmark/games/narrative/`). A ferrywoman takes a stranger across a foggy river at night; the story is data
  (nodes, choices that need and change flags in the kit's criteria grammar, three endings) checked by the `data`
  runner, and a search the game ships finds every node and ending reachable, no dead end and no flag set but never
  read. Every line is a translation key in English, French and German with a length limit per row for the `l10n`
  runner, and the story is saved at every line with its flags and history, with old saves replayed into the new form.
  The release candidate has 53 GUT tests, five flows, a bot that plans its way to every ending, juice, store art
  rendered from the game and credits. Its four stages carry 17 tasks and three milestones, each with hidden checks and
  a reference solution, most with a decoy; all pass `tests/Test-GameProgramme.ps1 -Genre narrative -Language
  gdscript`. `DESIGN.md` holds the language-neutral contract for the C# port.
- **The staged game programme's fifth genre: a top-down roguelite**, Wickerdeep, in GDScript
  (`benchmark/games/roguelite/`). A candle-bearer goes down four floors of a crypt, each generated from the run's seed
  (rooms joined by a spanning tree of corridors, every cell reachable, checked over sweeps of seeds), while shades, cinder
  bats and tallow brutes wander until they see it and then hunt it down one shared distance field. The rules live in a
  plain grid simulation stepped in ticks, so a floor replays exactly from its seed; `--swarm=N` adds hundreds of
  hunters for `bench`. Embers banked across runs buy vigor at a shrine, and the save keeps that meta progress and the run
  in progress for Continue, with version 1 saves migrated. The release candidate has 44 GUT tests, five flows, a bot
  that reaches the bottom, juice, three languages, store art rendered from the game and credits. Its four stages carry
  17 tasks and three milestones, each with hidden checks and a reference solution, most with a decoy; all pass
  `tests/Test-GameProgramme.ps1 -Genre roguelite -Language gdscript`. `DESIGN.md` holds the language-neutral contract
  for the C# port, which is still to come.
- **The staged game programme's sixth genre: a tower defence**, Bramblegate, in GDScript
  (`benchmark/games/towerdefence/`), one of the mid tier's three genres. Pests walk the shortest way across a grid
  (AStarGrid2D) from a gate to a seed store; every tower planted reroutes the pests on the field at once, and a tower
  that would leave the gate or any pest without a way is refused. Towers and their upgrades, pests, maps, waves and
  their groups are JSON checked by the `data` runner; a rule-based bot that builds a maze holds every map to a measured
  balance (cleared over several seeds, lost without towers); a swarm scene loads the field for `bench`; the save keeps
  each map's best stars. The release candidate has 63 GUT tests, five flows, a bot run through all three maps, juice,
  three languages, store art rendered from the game and credits. Its four stages carry 17 tasks and three milestones,
  each with hidden checks and a reference solution, most with a decoy; all pass
  `tests/Test-GameProgramme.ps1 -Genre towerdefence -Language gdscript`. `DESIGN.md` holds the language-neutral
  contract for the C# port.
- **The card game in C#.** Lanternfen now has its C# version (`benchmark/games/cards/csharp/`), written from the
  language-neutral contract in its `DESIGN.md`: the same scenes, node names, data files, flows, named phases, bot and
  juice runs, with 55 gdUnit4 tests in place of the GUT ones and a Linux export only. Both versions shuffle with the
  engine's seeded generator and score with the same arithmetic, so a seed deals the same duel and the AI makes the same
  choices: the bot run prints the same log lines, line for line. Its four stages carry the same 17 tasks and three
  milestones as the GDScript version, each with hidden checks in C# and a reference solution, most with a decoy; all
  pass `tests/Test-GameProgramme.ps1 -Genre cards -Language csharp`. `DESIGN.md`'s "As built" records the port's
  choices.
- **The platformer in C#.** Glowmoss Ridge now has its C# version (`benchmark/games/platformer/csharp/`), written from
  the language-neutral contract in its `DESIGN.md`: the same level scenes, scene tree, node names, data files, flows,
  bot and juice runs and log lines, with 34 gdUnit4 tests in place of the GUT ones and a Linux export only. Its four
  stages carry the same tasks and milestones as the GDScript version, each with hidden checks in C# and a reference
  solution, most with a decoy; all pass `tests/Test-GameProgramme.ps1 -Genre platformer -Language csharp`. Its
  `placement.json` names `Movement.Reach` in the C# source; `DESIGN.md`'s "As built" records the port's choices.
- **The staged game programme's fourth genre: a turn-based card game**, Lanternfen, in GDScript
  (`benchmark/games/cards/`). Two lantern-keepers duel with wisps that strike across three lanes and rites that act
  once; a turn is written as named phases (Draw, Main, Clash, End) in a plain class, each transition logged and tested.
  Cards, decks and five rivals are JSON checked by the `data` runner, the rivals are played by a utility AI with
  per-rival weights, every duel shuffles from its own seed, fatigue ends every duel, and the save keeps the duel in
  progress for Continue. The release candidate has 55 GUT tests, five flows, a bot that plays the AI against itself up
  the whole ladder, juice, three languages, store art rendered from the game and credits. Its four stages carry 17
  tasks and three milestones, each with hidden checks and a reference solution, most with a decoy; all pass
  `tests/Test-GameProgramme.ps1 -Genre cards -Language gdscript`. `DESIGN.md` holds the language-neutral contract for
  the C# port, which is still to come.
- **The puzzle Frostmote in C#** (`benchmark/games/puzzle/csharp`), the third genre's port: the same scenes, node names,
  data files, levels, flows, bot and juice logs as the GDScript build, with gdUnit4 tests (45 in the release candidate)
  run by the kit's .NET runner. The daily drift draws from Godot's `RandomNumberGenerator` with the same seed formula and
  draw order, and compares its rolls as doubles as GDScript does, so a seed gives the same level in both languages; seed
  7 is pinned by the same rows in each. Its four stages carry the same 17 tasks and 3 milestones, each with hidden
  gdUnit4 checks, a reference solution and the same decoys; all pass `tests/Test-GameProgramme.ps1 -Genre puzzle
  -Language csharp`. The C# build exports to Linux only, as Godot 4.7 cannot export C# to the Web.
  the C# port.
- **Blind review and the judge's calibration.** `benchmark/Invoke-SideBySide.ps1 -ReviewOut` writes the pairs the judge
  sees for a person instead (A and B in a seeded order, nothing naming the plugin, the key kept apart);
  `benchmark/review-page.html` shows them and keeps the owner's verdicts in its own store; `benchmark/Get-JudgeAgreement.ps1`
  scores the judge against those verdicts and against itself (80% and 90%, from `benchmark/PLAN.md`). Self-test:
  `tests/Test-ReviewPairs.ps1`.
- **A coverage map** ([docs/coverage.md](docs/coverage.md), made by `tests/Get-CoverageMap.ps1`): every command,
  documented error code, lib file, tool, skill, subagent and workflow job, with the self-tests and `self-test.yml` steps
  behind it and a list of gaps. It joins what the tests say (commands run, codes checked, files named) with what their kit
  runs reached: a run recorded under `HYPERDOT_COVERAGE` now names the `Test-*.ps1` that started it, and
  `tests/coverage-records.json` keeps each test's commands, codes and functions. `tests/Test-CoverageMap.ps1` (in the
  `lint` job) fails when something has no row; the `coverage` job adds the map from that run's records to its artifact.
  New cases for the gaps it showed: `import-failed` (a `project.godot` Godot cannot parse) and `no-browser` in
  `tests/Test-ErrorCodes.ps1`, `audio-clipping` in `tests/Test-Audio.ps1 -Mix` (`audio-fixture/loud.tscn`).
- **Argument mistakes come back as JSON.** An unknown command, a value outside a parameter's set (`-Do`, `-Mcp`,
  `-Profile`, `-Retry` above 5), an unknown flag or a word that belongs to no parameter used to be refused by PowerShell
  before the script started, with nothing on stdout under `-Json`. They now give `invalid-arguments` with the parameter,
  the value, what it takes and the nearest name (`-Projct` → `-Project`). The sets stay in the param block, as
  `[ArgumentCompletions]` (tab completion, not enforced while binding), checked by `Assert-KitArguments`; `help`, the
  skill and context checks and the coverage report read the same attributes. A flag without its value and a value of the
  wrong type (`-Retry abc`) are still PowerShell's. Self-test: `tests/Test-ErrorCodes.ps1 -NoGodot`.
- **The staged programme's first pilot** (min tier, 32 sessions, $1.89; `benchmark/PLAN.md`): five of the eight arcade
  GDScript tasks were solved by every configuration, Haiku's fix-playthrough sessions ran out of time (the template now
  allows 1800 s), the plugin used about twice the tokens again, and `cost-model.json` now holds the measured costs. The
  arcade explain-failure task asked for a bare `2`, which the prompt's `Godot 4.7.2` already contains, so the runner
  refused every tier holding it; its number terms now skip digits after a point, and `tests/Test-GameProgramme.ps1`
  first runs the runner's dry run on the programme, which catches such a task before any grading.
- **Design prompts placed.** `godot-progression` section 6: saving as a difficulty lever, pressure against stalling,
  sinks players want, fixed costs as a share of wealth, and charges on limited-use items shown, each ending in a number
  a test holds. A camera cost checklist in `godot-camera`, asked for by the `concept.decisions` gate. A premise in five
  Ws and a story summary with the player's verbs in bold (`godot-narrative`, and an optional Story section in the GDD
  template). A turn written as named phases with a test per transition (`godot-patterns`). The retro asks who owns each
  recurring job ("What recurring job has no owner?").
- **Intentional mistakes in `godot-game-ai`** (`mistakes.md`, a side file: the skill is at its size limit): Lars Lidén's
  "Artificial Stupidity" (*AI Game Programming Wisdom 2*) as rules with a test each: move before firing, miss the first
  time, be visible, poor aim on purpose, a few attackers at a time, tell the player, ease off at the end, openings on
  purpose. The chapter could not be read here, so only the two points the citing papers quote are marked verified;
  `docs/roadmap.md` asks for the text.
- **`templates/ARCHITECTURE.md`**, the shape of a game's code on one page: autoloads (each with its decision), the scene
  tree, signals that cross scenes, authored versus runtime data, the save schema version with its migrations, the
  minimum spec and the open technical questions an ADR answers. The `godot-architect` subagent creates it from the code
  with its first decision and adds what each proposal would change; `/game`'s review flags it missing or out of step
  with `status`'s inventory.
- **First-session steps as stubs.** `status -Json` lists the GDD's "First session, step by step" as
  `gdd.firstSession[]` (`S1`... from each step's number), with the flows, tests and `playthrough.json` tagged `GDD:S<n>`
  that play it and the `*.stub.json` files that only stub it; a confirmed GDD warns about steps with neither, and about
  tags for steps it lacks. Stubs never count as a feature's tests. `/game` writes the stubs
  (`test/flows/first_session_s<n>.stub.json` and `playthrough.stub.json`, which no runner plays, so a run stays green)
  and a task per step; starting the task turns the stub into a failing `.flow.json` first. `playthrough.json` may name
  the steps it plays in `"covers"`. Self-test: `tests/Test-Plan.ps1`.
- **A GDScript playtest tracker** (`examples/gdscript/playtest/playtest_tracker.gd`): the C# example's `PlaytestTracker`,
  its consent rule and `PlaytestFileSink` in one class. It raises the seven events of `templates/playtest-events.json`
  from the player's position and the game's calls, records nothing before the player agrees, and `flush()` appends one
  batch a line to `user://playtests/<session>.jsonl`; refusing consent deletes those files. Ten GUT tests
  (`test/test_playtest_tracker.gd`) repeat the C# cases with a fake clock and check every event against the template;
  `godot-playtest` and `docs/telemetry.md` point to it (the latter also had the sink's folder wrong). `doctor` now counts
  `PlaytestTracker` in the code as collecting player data, so a game using it without a privacy policy is warned; the
  GDScript example has one (`store/privacy-policy.md`).
- **GitLab CI template** (`ci/gitlab/hyperdot.gitlab-ci.yml`, untested on GitLab): `hyperdot-test` and `hyperdot-export`
  jobs, the GitHub action's steps and inputs as `HYPERDOT_*` variables (`ci/gitlab/Invoke-Hyperdot.ps1`), in the .NET 8
  SDK image, with Godot, NuGet and templates cached inside the checkout. Test results reach merge requests through
  `artifacts:reports:junit` and coverage through `coverage_report` (Cobertura). For it, `test` now also writes every
  runner's results as JUnit into `<results>/junit/` (`dotnet`'s and `gdunit4`'s TRX converted; `junitDir` in `-Json`).
  `tests/Test-GitLabTemplate.ps1` parses the template, holds it to GitLab's keywords and matches its report paths against
  what the kit writes. Docs: `docs/usage.md`, "GitLab CI".
- **`bench -Sweep <name>=<v1,v2,...>`:** one bench per value, the game getting `--<name>=<value>` after `-GameArgs`, one
  `bench.csv` row each (labelled `<-Label> <name>=<value>`) and a table of p99, p50, fps, draw calls and load time against the
  value in the log and in `-Json` (`sweep`). A value over `-BudgetMs`, `-MaxDrawCalls` or `-MaxLoadMs` is marked
  (`withinLimits`, `lastWithinLimits`), not a failure; a run that cannot be measured fails the sweep with the new code
  `bench-sweep-failed` after every value ran. `godot-performance` and `godot-shaders-vfx` use it for particle counts and
  quality tiers. Self-test: `tests/Test-BenchSweep.ps1` (`tests/bench-fixture/sweep.tscn`, headless).
- **Known-status list for add-ons** (`ci/godot/addons-status.json`): `doctor` warns about Godot Jolt on Godot 4.7,
  godot-steam-audio (archived), Godot-PerfBullets (Godot 4.1 and 4.2) and py4godot (a prototype), found by their folder
  in any letter case or, renamed, by their `.gdextension` file name and `entry_symbol`. Each name was confirmed from the
  add-on's repository (docs/addons.md says which files). `ci/godot/tools/Update-AddonStatus.ps1` refreshes each entry's
  newest commit and archived state; the canary runs it, puts what moved in its pull request and opens an issue for what
  needs a person. Tests: `tests/Test-Addons.ps1` (detection, the refresh on made-up repositories),
  `tests/Test-UpdatePins.ps1` (the canary).
- **The canary tracks aseprite-mcp's pins.** `Update-Versions.ps1` reads the commit and MCP SDK that `init -McpAseprite`
  writes (`lib/Init.ps1`) and proposes the server's newest commit (`git ls-remote`) and the newest `mcp` release on PyPI
  within the pinned major (a newer major is a note: SDK 2.x renamed the `FastMCP` the server imports). `-Apply` rewrites
  `lib/Init.ps1` and `docs/mcp.md`. `Invoke-Canary.ps1` tries them by starting the server through `uvx` and listing its
  tools (`-Uvx`, a stand-in in `tests/Test-UpdatePins.ps1`), without the example projects, which these pins do not touch;
  `canary.yml` installs uv.
- **A third genre for the staged game programme: the puzzle Frostmote, in GDScript** (`benchmark/games/puzzle`). A mote
  slides on ice until a wall, snow stops it, sparks open the exit: eight hand-made levels as JSON, checked by the `data`
  runner and held to their pars by a solver test, a daily drift from a seeded generator, undo, and a line that says when
  the exit can no longer be reached. Four stages with 17 tasks and 3 milestones, each with a reference solution and most
  with a decoy; `tests/Test-GameProgramme.ps1 -Genre puzzle -Language gdscript` checks them all. Its `DESIGN.md` is the
  contract the C# port follows.
- **The staged game programme's second genre: a platformer**, Glowmoss Ridge, in GDScript
  (`benchmark/games/platformer/`). A side view of a 3D world, so the `placement` runner measures every tuft of glowmoss
  against the climber's reach, read from the movement code. The jump has coyote time, a jump buffer and a short hop, and
  moves by each tick's average velocity, so it peaks at the same height at any tick rate. The release candidate has 34
  GUT tests, four flows, a bot that finishes five levels, juice, three languages, store art and credits. Its four stages
  carry 17 tasks and three milestones, each with hidden checks and a reference solution, most with a decoy; all pass
  `tests/Test-GameProgramme.ps1 -Genre platformer -Language gdscript`. `DESIGN.md` holds the language-neutral contract
  for the C# port.
- **Benchmark sessions as a separate user** (`-Isolate`, `benchmark/Isolation.ps1`; benchmark/PLAN.md stage 5). Each
  session runs as a user made for the run (`useradd`; `runuser` as root, `sudo -n -u` otherwise) whose only folder is its
  game copy: the runner's temporary files move into a folder it cannot list, the checkout is closed to other users for the
  run, and Godot (or a .NET SDK in the runner's home) is copied where it can run them. Credentials pass by inheritance,
  nothing else of the runner's environment does. After each session its processes are ended, links out of the game are
  removed and the game's `.git` is put back before grading. On in the Token benchmark workflow (input `isolate`); on
  Windows or without root or passwordless sudo it warns and runs as before. Self-test: `tests/Test-BenchmarkIsolation.ps1`.
- **The private field test** (`-GameSource <folder>`, `benchmark/FieldTest.ps1`, `benchmark/field-test.json`; stage 8):
  `fix-mutant`, `write-tests`, `doctor-green` and `bot-finish` on a copy of an owner's game, under the four
  configurations, reported as numbers only in `field-test.md`. Defects are planted generically: one flipped operator or
  changed number in the game's GDScript or C#, in an order a seed fixes, kept only when the game's own checks find it.
  `docs/token-benchmark.md` has the owner's steps on Windows, and `docs/label.md` a field-test table beside the label,
  outside the class. Self-test: `tests/Test-FieldTest.ps1` (both examples, with the stand-in).
- **Two installs of one Godot take turns.** Runs on one machine installing the same Godot (parallel jobs, two agent
  sessions) used to share the download's `.part` file and could start a half-unpacked editor. `setup` now holds a lock
  file per Godot build while it downloads and unpacks, unpacks beside the final folder and renames it into place (a run
  killed halfway leaves nothing that looks installed), and stops with the new code `install-busy` after waiting
  `HYPERDOT_TIMEOUT` seconds. Self-test: `tests/Test-InstallLock.ps1`.
- **Coverage counts the reusable workflow's jobs.** `godot.yml` takes a `kit-coverage` input (for the self-test only):
  its test and export jobs then record what the kit ran and upload it, and the self-test's `coverage` job adds the
  `zero-config`, `csharp` and `explicit-runners` jobs to its count.
- **Precision qualifiers in `godot-shaders-vfx`:** when `lowp` and `mediump` help on phones, what must stay `highp`, and
  a quoted shader using all three that `tests/Test-SkillShaders.ps1` compiles.
- **Lights per mesh on phones in `godot-mobile-web`.** The Mobile renderer's limit, 8 OmniLights and 8 SpotLights per
  mesh instance, is not a project setting: it is read from 4.7.2's Mobile scene shader, which packs each instance's lights
  as 8-bit indices in two 32-bit words (`sc_omni_lights(8)`). Compatibility's two settings sit beside it.
- **Commissioning a composer in `godot-audio`** (`commissioning.md`, from Untold History lesson 30): send something
  playable, say why it has to be them, hand over the adaptive plan and settle the rights.
- **Build size breakdown** on `export -Json` (`exports[].size`, `ci/godot/lib/BuildSize.ps1`): the output folder item by
  item, and Godot's pack (a `.pck`, one embedded in the executable, or one in a `.zip`) by top-level folder and by kind of
  source file, with imported textures and sounds and compiled scripts counted as their sources. The log names the largest
  folders. `tests/Test-BuildSize.ps1` reads a synthetic pack three ways and a real Linux export, separate and embedded.
- **Three `doctor` warnings**, each with a case both ways in `tests/doctor-fixture` (`tests/Test-DoctorFixture.ps1`):
  - asset files with the same content (size, then SHA-256), outside `addons/` and `.godot/`;
  - `OccluderInstance3D` nodes while `rendering/occlusion_culling/use_occlusion_culling` is off, so they cull nothing;
  - a `CharacterBody` or `RigidBody` script that moves the body in `_physics_process` / `_PhysicsProcess` while
    `physics/common/physics_interpolation` is off, unless the frame rate is capped at the tick rate (`application/run/max_fps`
    or `Engine.max_fps` / `Engine.MaxFps`).
- **Add-on licences without an `assets.json` entry** (`doctor`): an `addons/<name>/LICENSE*` whose add-on code no entry
  covers is a warning, since `credits` then writes no notice for code that ships. The fix is the entry, with the licence
  read from the text, `copyright` from its first `Copyright` line and `licenceFile`. GUT, gdUnit4 and the git plugin are
  left out.
- **Placeholders in `assets.json`**: `"placeholder": true`, with an optional `"due"` (yyyy-MM-dd) and `"status"` (`needed`
  or `in-progress`). `doctor` warns with the list and fails for one past its due date, as for an ended quarantine;
  `status` counts them (`placeholders`: `count`, `pastDue`, `entries[]`) and warns about those past due. The TECH-DEBT
  template points at the field.
- `doctor` reports MPL-2.0 entries (file-level copyleft) as INFO instead of an unrecognised licence.
- **MPL-2.0 in `credits`** (gdext and other Rust bindings): the licence text ships with the kit
  (`ci/godot/templates/licences/MPL-2.0.txt`, SPDX 3.29.0), and the notice tells players where the source of those files
  is, as section 3.2(a) asks. An MPL entry whose `source` is not a URL fails (`source-offer-missing`); a modified one
  warns (`mpl-modified`) that the changes are MPL-2.0 too. `copyright` is optional for it.
- **`help` and `/kit`.** `hyperdot.ps1 help` prints one line for each command, skill and subagent, and `help <name>`
  the short page of one (with `-Json`: `entries[]` or `entry`); it needs no project. The `kit` skill (`/kit`, `/kit <name>`)
  prints the same. The text has one source, `docs/help.md`; `tests/Test-Help.ps1` fails when a command, skill or subagent
  has no entry there.
- **`/game` reviews design and architecture.** Besides the feature marks, `plan/STATUS.md` gets a "Review" section: at
  most five design and architecture problems with their evidence (features that serve no kind of fun, scope drift,
  `architecture` warnings, autoloads no decision covers, subagent verdicts nobody acted on).
- **Handoff log.** `status -Handoff <subagent> -Checked <what> -Verdict <answer>` appends one line (time, subagent,
  what was checked, verdict, commit) to `.godot/hyperdot-handoffs.jsonl`, keeping the newest 200; `status` returns the 20
  newest as `handoffs[]`. Both subagents record their handoff before replying, and `/game` and `/retro` read the log.
  `tests/Test-Handoffs.ps1` checks it.
- **Kit notes.** `init -Agents` and `-Plugin` create `docs/kit-notes.md` in the game (template
  `ci/godot/templates/kit-notes.md`): one line each time the kit gets in the way. The `game` skill and the game's
  `AGENTS.md` say to append a line; `/retro` and `weekly-review` read it, and the weekly review proposes up to three kit
  changes for the owner to approve.
- **Start with `/game`.** The README's quick start, `docs/usage.md`, `docs/plan.md` and the game's `AGENTS.md` template
  say to start every Claude Code session in a game with `/game`.
- **`init` pins the kit's workflow at `@v1`** instead of `@main`, so a kit change reaches a game only when a release
  moves the `v1` tag, and a game moves up on purpose. The docs' snippets use `@v1` too. The tag is created at the 0.1.0
  release; a workflow `init` wrote earlier keeps its ref.
- **The Stop hook says what it checks.** The README, `docs/reference.md`, the hook, the plugin's description and
  `godot-verify-before-done` say plainly that it only checks that the tests passed after the last edit; it is not a design
  or code review.
- **`deck`, the Steam Deck check in one command** (note 15 of the question round): at 1280x800, the `textsize` runner,
  the `layout` runner on the new `steam_deck` profile (anything off screen), `shot`, and `bench` with a 33.3 ms (30 fps)
  budget unless `-BudgetMs` is given. Every part runs even after one fails; one verdict (`deck-failed`) with each part's
  own code in `deck.parts`. `-Scene` names the screens for all four. The parts are the existing commands and runners,
  run in one process. `tests/Test-Deck.ps1` on `tests/deck-fixture`.
- **`bench` holds three more budgets.** `-MaxDrawCalls` fails a scene that averages more draw calls a frame
  (`bench-over-draw-calls`); `loadMs`, with `loadBreakdownMs` (resource, instantiate, first frame), is the time from
  `load()` to the scene's first frame, and `-MaxLoadMs` fails a slower load (`bench-over-load-time`); `frameHistogram`
  puts every frame in a fixed bucket: 120, 60, 30 and 20 fps or better, and slower. A run over several limits names them
  all. `tests/bench-fixture/heavy.tscn` (a 300 ms `_ready`, 24 boxes with their own materials) checks each.
- **`-GpuValidation`** for `bench`, `shot` and `export -Run`: Godot's `--gpu-validation` and `--accurate-breadcrumbs`,
  and the run fails on the Vulkan validation layer's errors (`gpu-validation-errors`, each VUID in `gpuValidation`). A run
  that could not be validated (Compatibility renderer, headless, no layer installed) fails with `no-gpu-validation`
  instead of passing unchecked; `export -Run` launches the build with a window for it. `tests/Test-GpuValidation.ps1`
  binds a float texture to an unsigned-integer image in a compute shader, which Godot lets through and the layer
  reports as `VUID-vkCmdDispatch-format-07753`; it runs on Mesa's lavapipe in the web job.
- **Plan tasks and the board sync: the six bugs from the connector test.**
  - `plan -Do move`, `add` and `link` take a board list's name as `-Column` ("To Do", "testing", "Done" with an emoji),
    case-insensitive and by prefix as sync matches lists, as well as the column id; `plan.json` stores the id. A name
    that is neither fails with `invalid-arguments` and lists both.
  - `plan -Do remove -Id <task>` deletes a task. Its id is never given again (`lastTaskNumber`), and its card goes on
    the plan's archive list, which the next `plan -Do sync` archives (`sync.archived`).
  - A card a person adds on the board becomes a task in its list's column on `plan -Do sync` (`sync.imported`). A card
    the kit made for a task no task links now (`plan task <id>` in its description) is reported, not imported.
  - `plan -Do sync` records the board's column (`boardColumn`) of a task it moves; the self-test now checks it.
  - `move`, `remove` and `link` return `task` with `-Json`, like `add`.
- **`plan -Do reopen -Id <gate>`** opens a manual gate marked done again, without editing `plan.json` (note 13). An
  automatic gate is refused with `auto-gate`: it opens by itself when the project stops meeting it.
- **Plan gates for what was prose.** `concept.risks` wants `docs/RISKS.md`; `concept.budget` (`docs/BUDGET.md`) is the
  first optional gate (`"optional": true`: listed while open, with `optional` in `nextActions[]`, but it does not hold
  its phase back); `beta.placeholders` uses a new check, `placeholders`, met when no `assets.json` entry has
  `"placeholder": true` and the Placeholders table of `docs/TECH-DEBT.md` has no row (open while neither file exists).
  `file:<path>` checks now want a file with something in it (or a folder): an empty file no longer meets a gate. A plan
  made before keeps its gates (plan.json is the game's); `godot-game-plan` offers to add them.
- **`plan -Do init -Profile jam`**: a plan for a game jam of 2 to 9 days (`ci/godot/templates/plan-jam.json`), five
  phases sized in days (`timeboxDays`, for a 7-day jam) with the gates of `GDD-jam.md`'s day table (`jam.platform`
  first: "browser build?"). `plan -Json` gives `timeboxDays` and `elapsedDays` beside the weeks, PLAN.md sizes jam
  phases in days, and a jam phase over its timebox warns in days.
- **The `placement` runner** (`lib/Placement.ps1`, `tools/placement.gd`): `templates/placement_check.gd` on every level a
  `placement.json` names, each limit read from the GDScript constant it names, with no test to write. One case per
  scene with its findings; the summary per group, exemptions and wayfinding in `placement/placement.txt`. Selected when
  `placement.json` exists. `tests/Test-Placement.ps1` runs it on the fixture after the GUT path, and with a missing
  constant and a limit of the wrong type.
- **The `data` runner checks soft-locks, sinks and translations.**
  - A table of `"kind": "softlock"` holds levels as areas, passages, pickups, supplies and goals, and the runner searches
    each the way Example.Core's `SoftLockCheck` does, with the same counterexample text, so GDScript games get it too;
    `SoftLockTable.Load` reads the same file in C#. The ten levels of `softlock-examples.json` run in both.
  - `"economy": { "currency", "rate" }` on a table of money flows fails a currency with a source and no sink, and, when
    the currency is a `ref`, one no flow moves (`EconomySim.WithoutSink` checked it in code only).
  - `"locales"` on a responses table fails a line missing a locale's text or voice file, or naming a locale the table
    does not list; `ResponseTable.Load(..., locale: "fr")` reads them, and the C# example's barks are in French too.
  - An unknown `kind` now lists both kinds.
- **Playtest telemetry from a real level in the C# example.** `Main` raises `PlaytestTracker`'s events from each floor
  (deaths with the floor as checkpoint, the upgrade taken as the item found, a floor's time as finished, failed or quit),
  `Diagnostics` adds `PlaytestEvents` to its schema, and a playtest build (the custom feature `playtest`, or
  `--playtest`) writes its batches with the new `PlaytestFileSink`, one `<session>.jsonl` line a batch, every 30 s and
  on quit, for `hyperdot.ps1 playtest`. `DiagnosticsTest` plays a floor and checks the file gets the events only after
  consent.
- **The maths conventions pinned in the C# example** (`game/test/gdunit4/MathConventionsTest.cs`): on Godot's types, a
  positive yaw turns `Vector3.Forward` to the left, `Right x Up` is +Z and the book's cross product has area 26.94; and
  where Example.Core's `System.Numerics` differs (no forward axis, matrices composed left first). `godot-math` points to it.
- **`DifficultyDirector` in the C# example** (`Ai/DifficultyDirector.cs`): dynamic difficulty from a window of attempts,
  with a dead band, one bounded step at a time and the window emptied after each change, so two changes are always a
  window apart. In 600 simulated attempts it changed 20 times where moving on every result changed 500 times and
  reversed 311. `godot-progression` points to it.
- **The C# example's replicator packs bits and keeps to the client's rate.** `GhostFormat` gives each state group of
  `GhostReplicator` its own width (a ghost's creation: 14 bytes against 27 at 4 bytes a value) and `GhostReceiver`
  reads the packed payload; a value too wide for its group throws before anything is marked sent. `LinkBudget` holds
  the packets a second and bytes a packet the client asked for, capped by the tick rate and the server's uplink;
  `ReplicationTests` checks that no packet and no second carries more than was asked, through two changes of rate.
- **The C# example draws from `DeterministicRandom` everywhere a run must repeat.** `Steering.Wander` and
  `Aim.Scatter` take it by `ref`, `PacingDirector` and `ResponseSystem` take one at construction (the director exposes
  `RandomState` for saves), as `godot-game-ai` asks; `DeterministicRandom.NextDouble` replaces `EconomySim`'s private copy.
- **The Hyperdot label** (`docs/label.md`, `benchmark/Get-HyperdotLabel.ps1`, `benchmark/label-scale.json`), modelled on
  the EU energy label (Regulation (EU) 2017/1369; washing machines, 2019/2014):
  - an agent-efficiency class from A to G, from the Agent Efficiency Index: tokens per solved task over a standard, per
    task, geometric mean, × 100, with the washing machine's thresholds;
  - a minimum requirement (half the answers pass);
  - a product information sheet and an SVG label per configuration (model, with or without the plugin), and a tested
    class;
  - verification as Annex IX does it: one unit, then three more whose mean decides;
  - a rescale review when 30% of what is rated reaches class A;
  - a new scale reports whether class A starts empty.

  Scale 2026-10 was set from 216 sessions of 0.1.0. Haiku 5.5 rates D (AEI 74.2, 96% of answers pass), Sonnet 5.5 F
  (92.8, 54%, nearly every failure over the stated word limit). The plugin makes both worse on these tasks, which are
  about Hyperdot's own code.
- **The game programme** (`benchmark/game-benchmark.json`): five tasks on a small Godot game, built from `evals/` and
  made deterministic (explain a failing test, fix a bug from a player report, add a feature with tests, write tests
  that catch planted bugs, expose a value to the editor). Each session works in its own copy of the game with Bash,
  Edit and Write, and is graded afterwards by the kit's own `test`: the game's tests and hidden ones, files that must not
  change, and five mutants its tests must catch. The label now has two classes per version, **tool efficiency** and
  **game-making efficiency** (`-Programme tool|game`), each with its own standard tokens. `tests/Test-GameBenchmark.ps1`
  checks the grading with a stand-in that does every task well and badly.
- **CI pipelines, sanity pass.**
  - The web job's 11-minute install of Playwright's system packages (Ubuntu's mirror at 35 kB/s) now comes from the
    Actions cache, through `.github/actions/apt`. That action replaces `.github/actions/ffmpeg` and also serves ffmpeg
    and the evals' sandbox.
  - A push to a branch with an open pull request no longer runs Self-test twice, and a newer push cancels an older
    run (not on main).
  - The game benchmark's self-tests have a job of their own, with Godot set up for them; before, the staged check had
    no `GODOT_BIN` there.
  - Four lint steps ran no-Godot parts of tests that run whole in later jobs; they are gone.
  - A second `doctor` run on Windows is gone.
  - The inline version-update check moved into `tests/Test-UpdatePins.ps1`.
  - Three job comments sat above the wrong job.
  - The runner lists in the workflow and action inputs were missing eight runners.
- **Judged grading for the game programme**: a task can be scored by a pinned judge model against a rubric (median of
  three), and `benchmark/Invoke-SideBySide.ps1` judges each model's work with and without the plugin blind, both ways
  round. The plugin's win rate becomes a quality factor on its index (`Get-HyperdotLabel.ps1 -Preferences`).
  `tests/Test-GameProgramme.ps1` checks every staged task without a model: the planted defect is caught, the reference
  solution passes, the decoy fails.
- **The staged game programme, stage 1** (`benchmark/PLAN.md`): the benchmark runs programmes made of genres, stages
  (prototype to release candidate), languages and task templates, chosen by a tier (min under $10, mid under $50, max)
  and narrowed by genre, stage, language or task. A stage is built from the genre's whole game. Milestones take a game
  to the next stage. The runner estimates a run's cost (`benchmark/cost-model.json`), refuses one over its ceiling, and
  stops starting sessions once the real cost passes it. The workflow runs all four configurations in parallel after a
  dry run of each.
- Token benchmark: a grader that cannot be fooled.
  - Whole-word terms, `re:` regular expressions, `mustAdd` for a diff's added lines, forbidden commands found where a
    statement starts. Markup is not counted as words.
  - A spec whose required term is in the task's own prompt is refused.
  - Sessions run in a copy of the repository without the benchmark, so they cannot read the expected answers.
  - Only an answer that never came is retried. A run with an ungraded session exits 1.
  - Profiles rotate so no profile always meets a cold cache. `maxCalls` holds with retries.
  - CI-PS-003 replaces CI-PS-002, which needed the spec. CI-PS-001 and CODE-PS-001 no longer require a word good
    answers do without.
- Coverage: `HYPERDOT_COVERAGE` makes the kit record the commands, functions and error codes a run reaches.
  - `tests/Get-KitCoverage.ps1` reports them.
  - Every self-test job collects them, and a `coverage` job fails below its floors.
  - The first full run found 27 of the 50 documented error codes raised by no test. `tests/Test-ErrorCodes.ps1` raises
    them.
- An adversarial review of every area (core, planning, measurement, skills and plugin, CI and benchmark, examples and
  docs) found 62 defects. 59 are fixed, each with a regression test. One (a fuzzy PO comment) is how Godot itself
  behaves, so it stays. Binding errors that print no JSON are documented, and a download race is recorded in the roadmap. Among the fixes:
  - **Results folder:** `test -Results` naming a folder inside the project deleted it; now `unsafe-results-dir`.
  - **GUT:** a test script that fails to parse left the gut runner green.
  - **Solution detection:** outside a git checkout, `detect` picked the C# example's csproj instead of its solution, so
    552 of 580 tests never ran. A solution that lists a project of the same name elsewhere was also taken.
  - **Stop hook:** any passing `test` run satisfied it (`-Runners none`, a `-Filter`). It also missed deletions,
    commits, non-ASCII names and data files.
  - **Board sync:**
    - undid a local `plan -Do move`;
    - duplicated cards after a failure halfway;
    - dropped a custom list mapping.
  - **Plan and status:**
    - the `tests` gate and doctor counted the data and l10n runners as tests;
    - `status` failed outright on a plan problem.
  - **Measurement:**
    - the palette check missed off-palette colours close together;
    - `shot` overwrote pictures of scenes that share a file name;
    - `bench -Seconds 0` passed any budget and `audio -Mix -Seconds 0` hung;
    - the hitch count was capped at 50;
    - CSV numbers followed the machine's culture.
  - **Data and soak:**
    - `data` compared `enum` and `pattern` without regard to case;
    - soak metrics in scientific notation were misread.
  - **Error codes and logs:**
    - a game printing "Error:" failed with an empty error list;
    - paths with brackets broke a GUT upgrade;
    - paths with spaces lost their failure location;
    - the time limit was not enforced on a program that closed its output.
  - **Release and canary:**
    - a tag push would have published the C# example as the kit's release;
    - the canary mapped Godot 4.7 to GUT's 4.8 release;
    - anyone's marker comment could stop the PR summary;
    - a fork could set the coverage baseline.
  - **Examples:** the C# example's tests deleted a developer's own telemetry consent and saved key bindings.

  New self-tests: `Test-Detect`, `Test-InstallAddon`, `Test-StopGate`, `Test-ResultsDir`, `Test-HyperdotLabel`,
  `Test-ErrorCodes`.
- Versioning: the first Hyperdot release will be 0.1.0 (Semantic Versioning; 0.x while it is used on its first real
  game, 1.0.0 once the criteria in `docs/roadmap.md` hold). `plugin.json` goes from 0.4.0 to 0.1.0 with the new name.
- Licensed under the Apache License 2.0 (`LICENSE`, `NOTICE`); before this the repository had no licence. The files a
  game receives (`ci/godot/templates/`, the starter tests `init` writes) are MIT No Attribution
  (`ci/godot/templates/LICENSE.md`). `NOTICE` lists the third-party parts and their licences: Sfxr (Apache-2.0 and MIT),
  the University of Washington genre vocabulary (CC BY-NC-SA 4.0, with permission), Wikidata genres (CC0).
- README: a mascot logo (`docs/assets/hyperdot-logo.svg`, a muscular robot in wraparound sports sunglasses, flat clip-art style), a one-line pitch, badges, a sample of the JSON an agent reads,
  collapsible prerequisites and FAQ, and a licence and trademark section.
- **Renamed to Hyperdot (breaking, no aliases).** The script is `ci/godot/hyperdot.ps1`, the plugin `hyperdot`, the
  repository `nick-vas/hyperdot`, the environment variables `HYPERDOT_TIMEOUT`, `HYPERDOT_IGNORE_ERRORS`,
  `HYPERDOT_PLAYWRIGHT`, `HYPERDOT_STOP_GATE`, `HYPERDOT_WEB_HEADED` (`GODOT_BIN`, `GODOT_VERSION` and `GODOT_TOOLS_DIR` keep
  their names), the log prefix `[hyperdot]`, the run log `hyperdot.log` and the JSON `schema` value `hyperdot/1`. Error codes
  keep their names. Old state moves once: `.godot/godot-ci-history.jsonl` to `.godot/hyperdot-history.jsonl`, GUT's
  `.godot-ci-version` stamp and `~/.godot-ci` on any run; on `init`, a game's `godot-ci.yml` workflow becomes `hyperdot.yml`
  calling `nick-vas/hyperdot`, and `.claude/settings.json`'s `godot-agent-kit` plugin entry becomes `hyperdot`. The C#
  example is `examples/csharp` (`Example.sln`, `Example.Core`, project name "CSharp Example"), so it is no longer
  confused with Breakout Roguelike.
- Docs cleanup for the first release. README: a prerequisites section (Node.js for Web runs and two MCP servers, uv, ffmpeg, a
  display), the `-Project` form throughout, 50 skills grouped by area, every page in `docs/` linked, what each command
  writes into a project, and a refreshed status (exports run, eval results). `docs/roadmap.md` keeps only what is open
  (44 KB to 24 KB): the release plan, what was decided, the open sync work (the live run waits for the repository's
  secrets) and three to-do groups. `docs/strategies.md` is retired into the roadmap's decisions. AGENTS.md lists the
  self-tests once, in a table; `docs/reference.md` documents `-Templates` and the environment variables.
- A self-test of `plan -Do sync`: cards created in the right lists (a prefix match on "Done" plus an emoji), a second sync that changes
  nothing, a card moved on the board, an archived card, a short link as `-Board`, a missing list, missing and rejected
  credentials, and no token in the output or a URL. It runs against a stand-in service in the self-test, and live against the
  real API (a manual workflow with repository secrets).
- `plan` works on PCs with a day-first date format (Greek, and most of Europe): every plan command after `init` failed
  with "String '10/23/2026 05:57:27' was not recognized as a valid DateTime", because the phase's start time was read back
  through text in the PC's culture. Stored times now go through `ConvertTo-UtcTime` (Common.ps1), which also keeps
  `status`'s error history from shifting by the UTC offset. `Test-Plan.ps1` runs `plan` under el-GR.
- Fixes before the first release. `bench` and `audio -Mix` split `-Scene` on commas as `shot` does and refuse several scenes with
  `invalid-arguments` before any setup, instead of passing `a.tscn,b.tscn` on as one scene. The run log (`log`,
  `hyperdot.log`) now sits with each command's own results: `bench-results`, `soak-results`, `audio-results`, and `shot`'s
  `-Output`, not `test-results`. `no-display` advises starting Xvfb and setting `DISPLAY` (not `xvfb-run`, which breaks
  `-Json`) and prints the kit's real command. `sfx` no longer counts `<project>-assets/...` as inside the project (no
  `../` entry in `assets.json`). The PR summary comment pages through every comment, so a busy pull request gets its
  summary updated instead of a new one per run. `Update-Versions.ps1` fails on a pinned file that is missing instead of
  skipping it. Errors that fell back to `failed` now carry `export-failed` (an export with no `export_path`, a file not
  created, an exported build exiting non-zero) or `invalid-arguments` (an unknown runner, a bad `HYPERDOT_TIMEOUT` or
  `HYPERDOT_IGNORE_ERRORS`); `docs/json.md` lists `invalid-arguments` as a general code and says `soak` and `credits`
  write the log and history line too. `textsize` and `layout` join the runners that collect no coverage. New self-tests:
  `Test-SceneCount.ps1`, `Test-UpdatePins.ps1`, `Test-PrComment.ps1`; `Test-Sfx.ps1` and `Test-Audio.ps1` cover the path
  check and the log folder.
- Skills cleanup for the first release: 55 skills become 50. `godot-test-frameworks` merged into `godot-test-loop`, `godot-ui-layout`
  into `godot-ui-accessibility` (`layout.md`), `godot-steam-deck` into `godot-console-cert`, `godot-credits` into
  `godot-asset-pipeline`, and `godot-architecture` into `godot-patterns`, its other sections going to `godot-procgen`,
  `godot-progression`, `godot-multiplayer`, `godot-modding`, `godot-shaders-vfx`, `godot-game-design` and
  `godot-algorithms`. Contradictions fixed (Steam Auto-Cloud roots, seeded random in game AI, bot flags only in debug
  builds, MIT credits, hit-stop length, VRAM compression for 3D only, saving on suspend per platform, volume buses, one
  `--capture=nohud` flag); the `playthrough` runner replaces grepping for an ending; `/game` writes board cards the way
  `plan -Do sync` does, and the board sync is marked experimental. Descriptions are narrower and no longer share
  triggers; legal, audio and game AI moved detail to side files; duplicated advice has one owner. The skill validator
  now checks kit commands in side files too (`tests/skill-fixtures/bad-side-file`). `Update-Versions.ps1` and the credits
  error name the merged skills.
- Evals: the cases now run with `TMPDIR` on the runner's temp disk. Under `/tmp`, Claude Code's sandbox refused every
  write in a run's own folder, so no case could run Godot (run 6); with the change, Godot and GUT run (run 7).
  `fix-score-bug`'s `used-kit` grader now matches the kit called by a quoted path. `docs/research.md` records runs 6 and 7.
- Evals: run 5 (after the bwrap fix) found every write in a case refused as `Read-only file system`, the workspace
  included. The setup step's sandbox probe now also needs a writable mount, the run fails when a result mentions a
  read-only file system, and each run's transcript is uploaded with the result (`--keep-temp`). `docs/research.md`
  records run 5.
- `docs/publisher-contracts.md` now covers a second public sample agreement, cited by name with the owner's permission:
  Whitethorn Games' "Generic Whitethorn Service Contract" (2020), shared by its CEO for comments. What it does that the
  Raw Fury draft does not (services not recouped, no markup, a 24-month income term with the rights returning,
  ownership from inception), what to read twice (a share of gross, the pro-rata exit cost, exclusivity scope, soft
  words), and the developer's share at 10%, 20% and 25% of gross next to the Raw Fury draft and Nijman's benchmark.
  `godot-legal` gains the gross-to-net rule (20% of gross is 29% of net after a 30% store cut). The roadmap drops the
  rest of *The Untold History of Japanese Game Developers*, at the owner's request.
- `init -McpAseprite <Aseprite.exe or its folder>` registers [aseprite-mcp](https://github.com/diivi/aseprite-mcp) (MIT) in
  `.mcp.json`, so an agent can draw, animate and export pixel art in Aseprite (batch mode, 123 tools, `view_sprite` to see
  its work). It runs through `uvx` at a pinned commit with MCP SDK 1.30.0: unpinned, the server did not start (its
  `mcp[cli]>=1.6.0` resolved to SDK 2.x, which renamed what it imports). `ASEPRITE_PATH` is set from the path given;
  `aseprite-not-found` when there is no program there. `docs/mcp.md`, `godot-asset-pipeline`.
- `export` runs an export again, up to twice, when Godot crashed (an exit code of 128 or more, or a negative one on
  Windows): Godot 4.7.2 headless aborted with 134 after finished exports 4 times in 23 runs. The crashed run's file is
  deleted first and the entry gets `retried`; an ordinary failure, a hang and a crash on every run still fail. The import
  and the Web debug export share the same `Invoke-GodotRetried` (`Test-CrashRetry.ps1`).
- Rotation as a UI flow, from the roadmap (Elder Scrolls: Blades tested rotating mid-action, during loading and between
  a press and its release): `flows` gains `resize: [width, height]` (sets the root window's size, which headless Godot
  4.7.2 handles as an OS resize: the stretch mode and aspect apply, the viewport's `size_changed` fires once and anchored
  Controls resize; `DisplayServer.window_set_size` does nothing headless), `hold: "action"` (pressed until a later
  step) and `release: "action"`. A flow that ends with an action still held fails, and an `action` step on a held
  action is refused. Each flow now starts at the project's window size: headless Godot opened a 64x64 window, so a
  game with the `expand` aspect saw a square screen, and a resize leaked into the next flow. Bad sizes, an unknown or
  numeric `hold` and a `release` of an action not held fail with their reason. Self-test: `Test-Flows.ps1`
  (`tests/flows-fixture`, needs Godot).
- From the roadmap's art to-do list: `shot` checks every screenshot against the palette table in `docs/STYLE.md`
  (every `#RRGGBB` in its rows). Distances are CIEDE2000 (checked against Sharma, Wu and Dalal's test pairs) with a
  tolerance of 3 (`-PaletteTolerance`; one 8-bit level moves a colour by at most 2.40); anti-aliased edges, filtering
  and translucency pass as blends of two palette colours, in sRGB or linear light; off-palette colours are grouped and
  only groups over 0.1% of the picture count, so noise does not. Each shot gets `palette` (`offPalettePercent`,
  `blendPercent`, `scatteredPercent`, the largest off colours with their nearest palette colour, and
  `<name>.palette.png` with them in magenta); it warns, and `-MaxOffPalettePercent <n>` fails with `shot-off-palette`
  (`no-palette` when there is nothing to check against). The pixels are read by `ci/godot/tools/Palette.cs`, compiled
  with `Add-Type` (no Godot, no Python; about 0.3 s a 1080p picture). The style guide template says the table is read.
  Self-test: `Test-Palette.ps1` (`-NoGodot` for its synthetic part); method and measurements in `docs/art.md`.
- Playtest telemetry, from the roadmap's Valve list: the events `godot-playtest` names (`stuck`, `revisit`,
  `solved_but_stayed`, `item_found`, `death`, `hint_requested`, `level_time`, each with level, position and level time)
  as a ready schema, `ci/godot/templates/playtest-events.json`, and in Example.Core as `PlaytestEvents` for the existing
  `TelemetrySchema` (consent, no free text). `PlaytestTracker` raises them from the player's position and the game's
  progress calls: a stall is no progress and no new ground for 120 s, a revisit is re-entering a cell after 10 s away,
  solved-but-stayed is still near a solved puzzle 30 s later (`PlaytestTests`, with a fake clock). New command
  `playtest -Sessions <folder>`: reads the session files playtest builds wrote (`.json`, `.jsonl`; repeated batches
  counted once, broken files and events that do not fit listed) and writes per-level counts and medians (level time,
  deaths and stalls per session, items found) and a PNG heat map per level and event type, alone or over a level
  screenshot that the new `playtest.json` places in the world. The PNGs are drawn by `ci/godot/tools/Heatmap.cs`, compiled
  with `Add-Type`, so no Godot is needed. New error codes `no-playtest-sessions` and `invalid-playtest-config`;
  `-HotspotCell` also sets the maps' cell. Self-test: `Test-Playtest.ps1` with `tests/playtest-fixture`.
- From the roadmap's Valve list ("never a soft-lock", `docs/valve.md` lesson 30): Example.Core gains `SoftLockCheck`.
  A level is written down as areas, passages (one-way, needing an item held, or using items up once: a key, three
  rounds for a cracked wall), one-time pickups, supplies that top an item back up (Portal's box delivery tubes), items
  that can be lost at any moment, and goals. A breadth-first search over area, items held, pickups taken and ways opened
  (packed into 128 bits, capped by `maxStates` with a clear error) and a backward search from the goal find every
  reachable state the goal cannot be reached from, and return the shortest counterexample ("pick up key in Hall; use
  key on closet door, go Hall -> Closet. Stuck in Closet, holding nothing"). `everyItemCanBeLost` is the stress test.
  A game's test calls `SoftLockCheck.AssertNoSoftLock(level)`; `godot-playtest` gains a section on it. With
  `LookTrigger`, the roadmap item is done.
- Localization, from the roadmap's to-do list: the `l10n` runner gains a seventh case, `missing glyphs`, a glyph-coverage
  check per locale without a display. It reads every translated string from the CSV and PO tables (an imported,
  compressed `.translation` lists no keys, measured), drops placeholders, BBCode tags and invisible characters, and runs
  `ci/godot/tools/glyphs.gd` in headless Godot to check each character with `Font.has_char` against the default font
  (the project theme's, `gui/theme/custom_font` or Godot's Open Sans) and every font of a `.tres` theme, fallbacks
  included. Each finding names the locale, font, characters with code points and up to five keys; characters only a
  `SystemFont` could draw are a `system-font` warning (they depend on the player's OS), and `l10n.json`'s
  `glyphIgnoreFonts` leaves out fonts that never draw translated text. `test -Json` adds `glyphs` to the l10n entry of
  `runnerResults`. Measured on 4.7.2 (`docs/localization.md`): `has_char` walks `FontFile` and `FontVariation`
  fallbacks but never the system fonts `allow_system_fallback` draws from. Fixture: `tests/l10n-fixture/glyphs`
  (text-only bitmap fonts, no font file committed); `tests/Test-Localization.ps1` gains `-NoGodot`.
- Dialogue tables, from the roadmap's Valve list: a `data.json` table of `"kind": "responses"` holds `ResponseSystem`'s
  rules (id, who, concept, criteria, lines with optional voice files, then, remember, once), and the `data` runner fails
  criteria syntax errors with the column, a `then` no rule answers (across all responses tables, with the near name),
  voice files that do not exist (and lines without one when `"voiced": true`), rules with the same who, concept and
  criteria, and criteria that contradict each other; a fact read but never remembered nor listed in `facts` is a
  `fact-never-written` warning. `"type": "criteria"` checks the grammar in any table. Example.Core gains
  `ResponseTable.Load` (rules from the same JSON, every bad row reported at once), `Rule.Voices` and `Rule.VoiceOf`, and
  one strict criteria grammar, `CriteriaSyntax` (`Criterion.Parse` no longer accepts `a=` or `a=1;b=2` as one
  criterion); 37 shared cases in `criteria-examples.json` keep the C# and PowerShell parsers in agreement. The C# example has a
  green dialogue table (`game/data/barks.json`), and `tests/data-fixture` a broken one per check.
- Design and production practice. The GDD template gains audience and expected age rating, a core fantasy, the loop at
  three scales (moment, session, playthrough), the first session step by step (for flows and `playthrough.json`
  milestones), world rules, what failing costs, content counts and length, optional modes, open questions and a change
  log; the parsed parts (pitch, `### F<n>` features) are unchanged. New `templates/GDD-jam.md` and a jam mode in
  `godot-game-plan` (days, not weeks; "browser build?" first, since Godot 4.7 cannot export C# to the Web), with a
  concept risk log, budget and runway categories, a business model and fairness rule, and sharper alpha and beta exit
  criteria (a placeholders table in `templates/TECH-DEBT.md`, bug classes A and B). `godot-store-page` gains a marketing
  cadence and a release ladder; `godot-legal` a checklist of other agreements (unpaid teams, the studio as contractor,
  the game's own source licence, tabletop rules text: SRD 5.1 under CC BY 4.0 or OGL 1.0a, checked at Wizards of the
  Coast's SRD page) and parody permissions; `godot-narrative` character sheets, events from the player's relationships
  and quest templates as `data` tables; `godot-game-design` comparable-game teardowns, world size by traversal time and
  Bartle's player types kept apart from MDA. *Untold History* read again: lessons 16-39 in `docs/studio-lessons.md`
  (quotes checked word for word), each placed in one skill line where it adds something.
- From the TRIBES networking paper, *Mathematics for Game Developers*, a Unity performance checklist and Adam Sawicki's
  GPU debugging talk: Example.Core gains `BitPacker` (`BitWriter`/`BitReader`: bools, ints in the bits their range
  needs, floats quantised in a range; a reader that disagrees with its writer throws) and `EventStream` (TRIBES'
  events in the same packets as ghost state: numbered, a lost packet's events resent ahead of newer ones, and an event
  naming an object sent only once its creation is in the packet or acknowledged; at 20% loss, 0 events before their
  object, 11 without the wait), plus `EconomySim` (currency sources and sinks per hour, seeded over 10 to 1000 hours,
  currencies without a sink, hours a player ran short). Skills: physics interpolation, events with state, bit packing
  and client-set rates in `godot-multiplayer`; the 3D turn direction, the cross product as an area and the exercise
  key's errors in `godot-math` (its worked examples match, its answer key does not); Godot 4.7 counterparts of the Unity
  checklist in `godot-performance`; `--gpu-validation`, `--gpu-abort`, `--accurate-breadcrumbs` and
  `--single-threaded-scene` in `godot-diagnose`; RenderDoc labels in `godot-debug-tools`; currencies in
  `godot-progression`. What could not be run or checked here (Vulkan-only flags, shader precision, Mobile light limits,
  dialogue tool licences) is in `docs/roadmap.md`.
- Publisher contracts: Jan Willem Nijman's red flags from his comments on a 2020 publishing agreement draft
  (`docs/publisher-contracts.md`, clause by clause with what to ask for; `godot-legal` section 6): markups and fixed
  splits, recoup before any revenue, one-sided termination and breach clauses, unpublishing, reserves, sequel fees, and
  a worked example of what a 15% markup and a 50/50 split cost against his 70/30 benchmark.
- Add-ons and GDExtensions (`docs/addons.md`, skill `godot-addons`, `ci/godot/lib/Addons.ps1`): the state of 25 popular
  add-ons on Godot 4.7, cross-checked with garciamarquez.dev's ranking. `doctor`'s GDExtension check now picks each
  library as Godot does (measured on 4.7.2: every tag of a key must be a feature of the build, the most tags wins), for
  each preset's release and debug builds and Android ABIs, with paths relative to the `.gdextension` and multi-line
  `[dependencies]`. Before, it saw only `res://` paths, so the official template's and Debug Draw 3D's libraries were
  never checked, and a build no key fits (Godot exports it with exit code 0 and no library) passed. New: an editor-only
  extension exported, `compatibility_minimum` and `_maximum` against the project's Godot, the Godot Jolt extension on
  4.4+, an add-on autoload the game uses but `project.godot` lacks, test add-ons shipped, and `forced_dd3d` in a preset.
- `doctor` checks the instructions every agent session loads (IBM's context engineering: stale context poisons every
  session): `AGENTS.md`, `CLAUDE.md` and their `@` imports. It warns about kit calls with a command or flag the script
  does not have (read from its own parameters), files and `res://` paths that do not exist, imports that load nothing,
  and files over 200 lines; lines kept from the kit's template are skipped. `tests/Test-Context.ps1` also holds the
  template, skills and docs to the real flags. The kit's own `AGENTS.md` named `licences/` without its folder.
- Evals: bwrap is allowed to make its sandbox on GitHub's Ubuntu 24.04 runners (AppArmor stopped bwrap from making user namespaces, so
  every command in run 4 failed and its scores measured that); the workflow checks the sandbox before any case and fails
  when a result reports a bwrap error. Run 4's scores and what they do and do not show are in `docs/research.md`.
- Release checks from the store, legal and Steam research (`docs/store-and-legal.md`, `docs/steam.md`): plan.json gains
  an optional `release` block (`date`, `steamFeePaid`, `comingSoon`, `storePageSubmitted`, `buildSubmitted`, `nextFest`,
  `demoSubmitted`, `pressPreview`), and `plan` and `status` warn when Steam's dates cannot be kept (21 days after the
  fee, 2 weeks of Coming Soon, 7 business days per review with the page first, the Next Fest demo 3 or 5 weeks ahead);
  `plan -Json` returns the timeline as `release`. `doctor` reads `store/steam/trailer*` with ffprobe (H.264, AAC, 30 or
  60 fps, 44.1 or 48 kHz, up to 1920x1080) and `store/steam/tags.txt` (5 to 20, one per line, no duplicates); warns when
  telemetry, a `policyVersion` or an Android or iOS preset has no privacy policy (`store/privacy-policy.md` or
  `PRIVACY.md`; the C# example now has one, written from what its telemetry records), or the policy does not say the version the code asks consent for; and checks the Steamworks files a
  game keeps in `steam/` against its code with a new VDF reader (`ci/godot/lib/Steam.ps1`): rich presence tokens set as
  `steam_display`, achievement and stat names against `steam/achievements.json`, and steamcmd app build scripts (a
  numeric `AppID`, a `FileMapping` per depot, no secrets, no `SetLive "default"`, no `steam_appid.txt` uploaded).
- CI, more from GameCI's documentation: `export -GameVersion auto` reads the version from git (the nearest `v*` tag and
  the commits since: `1.2.3.4`, `1.2.3+4.gabc1234`; `0.0.0.<commits>` without a tag) and stops with `shallow-checkout`
  in a shallow clone, before Godot is set up. Any `-GameVersion` also sets Android presets' `version/code` for the export
  only (major\*1,000,000 + minor\*1,000 + patch, `gameVersion.androidVersionCode`). The action outputs `version`,
  `android-version-code` and `build-path`, keeps Git LFS objects (`lfs` input) and Android's Gradle caches in the Actions
  cache, and finds export templates on macOS; `setup` downloads the macOS build of Godot instead of stopping. `godot.yml`
  takes optional signing secrets (Android keystore, Windows certificate, macOS certificate and notarization key) and an
  `environment` for its export jobs, a `game-version` for runs that are not for a tag, and sends iOS presets to
  `macos-latest`. New page: `docs/self-hosted-runners.md`. Self-test: `Test-GameVersion.ps1`.
- Audio, from the roadmap's to-do list: a mono option after all. `AudioEffectStereoEnhance` with `pan_pullout` 0 on Master
  makes each side (L+R)/2, measured in the engine by `tests/Test-MonoAudio.ps1` (left-only tone 0.353/0 becomes
  0.177/0.177, centred unchanged, opposite phase cancels), so `godot-audio` now gives the recipe for Xbox Accessibility
  Guideline 105. Example.Core gains `VoiceBudget`: a global voice cap with categories, priorities, oldest-first stealing
  and protected categories, the part Godot leaves to games.
- From the roadmap's to-do list: Example.Core's steering gains `Alignment` and `Cohesion` (with `Separation`, a flock: 30
  boids head the same way within ten seconds without overlapping), `FollowPath` (Reynolds' corridor following, stopping at
  the end) and `AvoidObstacles`; and `LookTrigger` (Valve's look target with a fallback timer: fires when the player has
  looked at a point long enough, or when time runs out). A new architecture rule, `nondeterministic-sim`, flags
  platform maths, `System.Random`, global random, clocks, per-process hashes and `Dictionary` iteration in the folders
  `architecture.json` lists as `simulation`. `validate` fails a `.tres` that keeps a key its class no longer has (a renamed
  export, whose value Godot drops on load).
- Valve, from its own public material (talk slides, the 2012 handbook, the Cabal article, seven games' developer
  commentary; `docs/valve.md`, 115 quotes checked word for word): Example.Core gains `PacingDirector` and `Intensity`
  (Left 4 Dead's AI Director: build up, sustain the peak 3-5 s, fade, relax 30-45 s; pacing, never difficulty) and
  `ResponseSystem` (the dialogue rule database of Left 4 Dead 2, Portal 2 and Dota 2: a flat query, most criteria wins,
  random ties, memory that expires, follow-ups looked up when a line ends, rules that remove themselves). New skill
  `godot-playtest`; Valve's process in `godot-game-plan`; story that serves play and dialogue rules in `godot-narrative`;
  scarce-but-never-empty resources and worst-case drop streaks in `godot-progression`; readability rules in the `STYLE.md`
  template.
- The second-pass test features from Croteam's CI talk: a `playthrough` runner (`playthrough.json`: the game's bot plays at
  a fixed 60 fps of game time and must log every milestone in order, the ending last; `smoke` passed a bot stuck in the first
  room), and the plan gate `production.playthrough` is now checked by it (`runner:<name>`, a new gate check). `smoke
  -FixedFps` runs smoke at fixed game time. `shot -Baseline -MaxChangedPercent` fails a changed screen with the new code
  `shot-changed`. `status` reports `testDuration` (the median of recent passing full test runs against the ten before) and
  warns over `testBudgetSeconds` in `plan.json` (900 in new plans) or when runs grow by half. `Test-LibNames.ps1` fails when
  two lib files define the same function (status had called `Audio.ps1`'s `Get-Median` instead of its own).
- Blizzplanet's interviews (69 posts, 2002 to 2014: Mists of Pandaria's developers, Hellgate: London, the World of
  Warcraft card game, PopCap, voice actors, tie-in writers, mod teams; `docs/studio-lessons.md`): `godot-progression`
  (rewards that become chores, nothing missable, pity and consolation, difficulty tuned on enemies and tested with the
  strongest stats, update cadence) and `godot-narrative` (a bible, timeline, canon tiers, reserved reveals and decisions
  in the repository; voice recorded after content lock). The `data` runner gains `totals` (what a group's rows add up
  to must reach a number or another table's field: the zones that left players 10% short of the next level) and
  `names` (proper nouns one or two letters from a canonical name in dialogue, translations and scenes).
- `sfx`: placeholder sound effects from a seed (coin, laser, explosion, powerup, hit, jump, blip), so a prototype has
  sounds on day one. bfxr2's Bfxr synth ported to C# (`ci/godot/tools/Sfxr.cs`, Apache-2.0 and MIT) and compiled into
  the session, so it needs no Godot; the same seed gives bfxr2's sound sample for sample. WAVs at `-PeakDb` (-6 dBFS),
  `.bfxr` files bfxr2's editor opens, `-Vary` for variations of one sound, and an `assets.json` entry.
- Google for Games' open source (Agones, Open Match, Quilkin, Open Saves, clean-chat, the GenAI demos; Apache-2.0;
  `docs/googleforgames.md`), without their Google Cloud setup: `godot-servers` and `godot-llm` skills; Example.Core
  gains a server lifecycle with a health watchdog, Agones' HTTP SDK, join tokens for Godot's authentication step, a
  matchmaker, a rate limiter and chat moderation. `soak` stops the server with SIGTERM at the end and reports
  `soak.stop` (headless Godot dies at once with 143 unless the game handles it; C# can); `-RequireCleanStop` fails
  `soak-unclean-stop`, and `-StopGraceSeconds` sets the wait.
- CI, from GameCI's documentation: the action's cache keys name the Godot build (.NET or standard) so a repository with
  both no longer restores the wrong one, the import cache's key covers the source assets (a `.import` file does not
  change when its picture does), and Godot, its templates and the import cache are saved when the tests fail too.
  `godot.yml` jobs stop after `timeout-minutes` (60); the self-test's after 45; actionlint is pinned (1.7.12). Tags with
  a hyphen are published as pre-releases; pull requests from forks get a notice instead of a misleading PR-comment
  warning. `doctor` fails on Git LFS pointers left in place of assets, committed keystores, certificates and
  `config.vdf`, names Windows cannot create and paths that differ only in case, and warns on `res://` paths whose case
  differs from the file. `Test-DocLinks.ps1` checks every link and quoted path in the docs and skills. The self-test
  installs ffmpeg through `.github/actions/ffmpeg`, which keeps its packages in the Actions cache: Ubuntu's mirror took
  12 minutes for them in one run.
- Algorithms (TheAlgorithms/C-Sharp, GPL-3.0, studied and measured, not copied; its MIT explanations read too;
  `docs/algorithms.md`): a `godot-algorithms` skill; Example.Core gains a Dijkstra map for crowds and fleeing
  (`DistanceField`), region labelling and union-find (`Regions`, `DisjointSet`) and "did you mean" (`Suggest`). The
  `data` runner reports loops among prerequisites (`"acyclic": true`) and names the near id, enum value, column or
  table for a typo; `test -Runners` suggests the runner a mistyped name meant.
- Fixes found by the first CI runs after the GDC work: `test -Filter` no longer fails when the filter leaves out every
  gdUnit4 test (they were counted as found but not run); a successful command now exits 0 explicitly, instead of
  leaving the exit code of its last `git` call (128 in a repository without commits), which GitHub's PowerShell steps
  report as the step's result.
- GDC talks: 45 talks turned into a pull request each and 76 folded in as a line or two, each read in full from its
  transcript; the index, with what the kit took from each, is `docs/gdc/README.md`.
  - `test`: `failureDelta` names failures that are new, still failing or fixed since the last run of the same scope;
    `-Retry <n>` reruns a failed runner and lists what passed only on a retry in `flaky[]`; `quarantine.json` (owner,
    end date) keeps a known-flaky test from failing the run without hiding it (`invalid-quarantine`); `status` reports
    repeat offenders and quarantines. Godot error lines become error keys (numbers and line numbers taken out) recorded
    with the commit in the run history, `engineErrors[]` items get a `key` and their file, and `status` lists
    `recurringErrors[]` with when and at which commit each was first and last seen.
  - `setup`: a failed Godot or template download stops with `download-failed`.
  - Runners and commands: `bench` hotspots (where a level is slow), `soak -JunkPps` (when an ENet server falls over),
    `shot -ColorVision`, a subtitle size check in `textsize`, `audio`'s `onsetMs` for late action sounds, `layout`
    measures TouchScreenButtons and an opt-in `small-control` minimum (`minControlDp`), and `l10n` checks length
    limits, translation remaps, localized voice, tables Godot cannot read as UTF-8 and Chinese locales without a script.
  - `doctor`: commissioned assets without their agreement, text-to-speech off when the game speaks, screen readers
    disabled, an incomplete press kit in `store/press/`, expired or long quarantines.
  - Plan gates: `slice.debt`, `slice.budget`, `prototype.trailer` (with a `TRAILER.md` template) and `concept.name`.
    The placement checker checks placed objects against the game's limits and landmarks and routes for wayfinding;
    the `data` runner holds puzzle levels to one solution sentence and a purpose.
  - Tested code in Example.Core a game can copy: statistics for comparing versions, Eldritch-style mazes, GOAP costs,
    perception, aim and projectiles, squad decisions, a FrameBudget scheduler, forgiveness timings, stick settings,
    dead reckoning, a rollback session, Overwatch-style input handling, a rewind log, an input log for replays, a voice
    limiter, a beat clock, an assist narrator, a balance report from run data, an expressive-range map, shuffle bags
    and pity timers, an orbit camera, jump arcs, haptic patterns and menu wraps, touch pads.
  - Skills: a new `godot-camera`; most others gained sections, and the largest moved detail into reference files
    beside `SKILL.md` to stay under 16 KB.
- `test`: the `dotnet` runner no longer passes when gdUnit4Net found tests but ran none. When its in-Godot rebuild
  failed or timed out (20 s by default, easily reached on a busy machine), the adapter exited 0 with no results, so a
  green run hid a skipped engine suite. Found-but-not-run tests are now one failure, `gdUnit4 (tests not run)`, with the
  cause; the generated `.runsettings` allows the rebuild 3 minutes.
- Phones, tablets and browsers:
  - `layout` runner (`layout.json`): each screen laid out, headless, on a portrait and a landscape phone, a tablet, an
    ultrawide and custom profiles; controls off screen, under the notch or system bars, or under 48 dp (touch) or 24 CSS
    px (mouse) fail. A game's `SafeArea` autoload gets each profile's notch, so its own safe-area code is what is tested.
  - `export -Run` for Web presets: a debug export opened in real browsers (`-Browser chromium,firefox,webkit,chrome,msedge`)
    through Playwright, served with cross-origin isolation headers only for threads builds; fails on an engine that does
    not start, page errors, failed requests and script errors, which release builds hide (`web-run-failed`,
    `no-browser`). Web exports report their size raw and gzipped. An output folder inside the project gets a `.gdignore`.
  - `doctor`: a C# game with a Web preset, threads builds (no headers on itch.io or GitHub Pages), Android without
    ETC2/ASTC or an icon, C# Android without Gradle on net8.0, presets exporting into the project. 4.7.2's Android "No
    project icon specified" log line no longer fails an export.
  - Skill `godot-mobile-web`; `godot-input` and `godot-ui-layout` point to it. Measurements and sources:
    `docs/mobile-web.md`.
- Store pages, legal basics, credits and release readiness:
  - `credits` command: `CREDITS.md`, `credits.json` (sections with translation-key headings, for a credits screen) and
    `THIRD-PARTY-NOTICES.txt` from `assets.json`, with Godot's MIT text and its third-party components read from the
    engine, and the .NET runtime's notices for C# games (a C# export ships none). It fails (`credits-invalid`) on credits
    without an author or a source URL, MIT, BSD, ISC, OFL and Apache entries without their copyright line or licence text,
    and non-commercial or GPL-family licences. `export` copies the notices next to each executable.
  - `doctor` checks Steam store art in `store/steam/` against the sizes in force since August 2024, at least five 16:9
    screenshots at 1920x1080 or more, and the short description.
  - Plan template: launch gates for credits, privacy and age ratings; the store gate names Steam's two-week Coming Soon
    minimum.
  - Skills: `godot-store-page`, `godot-legal`, `godot-credits` and `godot-release-readiness`. Sources and what was tested:
    `docs/store-and-legal.md`.
- The TRIBES networking model (Frohnmayer and Gift, GDC 2000) in Example.Core (`Net/Replication.cs`): a connection
  layer that reports every packet delivered or dropped, in order, and never resends; a ghost replicator per client with
  scope, priority, a byte budget and per-object state masks, where lost state is resent only if no newer value was sent;
  creations and deletions resent until they arrive. Tested against the paper's four loss cases and a lossy run (5% of the
  bytes of full snapshots, no older value ever applied). `godot-multiplayer` gains the delivery classes and how they map
  to Godot 4.7 (`OnChange` replication is reliable: wrong for state that changes all the time).
- Steam and Steam Deck:
  - Skills: `godot-steam` (which C# binding works in Godot 4.7.2 and which does not, start-up without Steam, achievements,
    stats, leaderboards, rich presence, Cloud conflicts, DLC, demos, dedicated servers, branches) and `godot-steam-deck`
    (Verified criteria, text size, defaults per device, text entry, sleep and resume). Sources: `docs/steam.md`.
  - `textsize` runner: every visible text measured in real pixels at 1280x800 (or the sizes `textsize.json` lists),
    headless; under 9 px fails, capitals under 9 px or text under 12 px warn, integer scaling that cuts the game off fails.
  - Architecture rules `steam-removed-api` and `steam-env-dotnet`. `doctor` fails when a `.gdextension` names a library
    missing for an exported platform, and flags Steam packages that cannot work (Steamworks.NET.AnyCPU 2026.165.0 to .2
    on Linux, the stale Steamworks.NET, Facepunch.Steamworks for Windows only). Runs of a game that uses Steam set
    `SteamAppId=480`, so `RestartAppIfNecessary` cannot end a smoke run early.
  - Example.Core: platform services (achievements, stats, a leaderboard, rich presence) with a local backend that
    behaves like Steam, and `SaveStore.SaveResolved`, which ends a cloud conflict so the next sync goes one way.
  - `godot-console-cert`: PlayStation and Nintendo details are out of scope (NDA); "save on suspend" is now "save often".
- Token benchmark (`benchmark/`, `docs/token-benchmark.md`): tasks from this repository run as read-only `claude -p`
  sessions under three profiles (baseline, scoped, plan then answer), repeated, with tokens counted including cache
  reads and writes, Claude Code's own cost, turns, time and answer checks; medians and 90th percentiles per profile and
  task. A manual workflow (`Token benchmark`) and a self-test against a stand-in CLI.
- Data, determinism, modding, anti-cheat, console certification, debug tools, profiling and release pipelines:
  - Skills: `godot-data`, `godot-determinism`, `godot-modding`, `godot-anti-cheat`, `godot-console-cert` and
    `godot-debug-tools`; `godot-performance` gains C# profiling (`dotnet-trace`, `dotnet-gcdump`, starting the counters
    `dotnet-counters` needs) and measured GC settings, `godot-export-release` versions, signing and store uploads.
    Sources and measurements: `docs/data.md`, `docs/determinism.md`, `docs/modding.md`, `docs/anti-cheat.md`,
    `docs/console-cert.md`, `docs/debug-tools.md`, `docs/profiling-and-builds.md`.
  - `data` runner: tables in JSON or CSV checked against `data.json` (types, ranges, enums, patterns, references between
    tables, unknown columns, duplicate ids), and a CSV still imported as a translation, which the export would drop.
  - Example.Core: a determinism toolkit (`IDeterministic`, `DeterminismCheck.Record`, `Verify` and GGPO's `SyncTest`,
    FNV-1a checksums, a saveable random generator); the server now grants one input per tick of real time, so a client
    that sends extra inputs no longer moves faster (`InputsRejected`). Example.Core has 83 unit tests.
  - `export -GameVersion` (and the action's `game-version`, passed on tags by the release workflow): the numbers go into
    `config/version` for that export only, the whole version into the C# assembly. `export` fails when a desktop C#
    build has no `data_*` folder with the game's assembly. The action caches Godot's import cache.
  - Architecture rules: `untrusted-load` (a Godot resource loaded from `user://` runs any script embedded in it) and
    `culture-parse` (number parsing without an invariant culture reads "0.5" as 5 on a German system).
  - `doctor` warns when `config/version` is not numbers and dots, and when a Windows preset does not write the game's
    version and icon into the exe (the C# example's now does).
- Game AI, multiplayer, crash reports and telemetry:
  - Skills: `godot-game-ai` (choosing a decision structure, behaviour trees that interrupt, utility with momentum,
    GOAP, steering, Godot 4.7 navigation readiness), `godot-multiplayer` (choosing a model, prediction, reconciliation,
    interpolation, lag compensation, rollback, Godot 4.7 specifics) and `godot-telemetry` (consent, no free text,
    catching C# errors through a `Logger`, Sentry's defaults, export and erasure). Sources and measurements:
    `docs/game-ai.md`, `docs/multiplayer.md`, `docs/telemetry.md`.
  - Example.Core: utility scoring, a reactive behaviour tree, a backward-searching GOAP planner and Reynolds steering;
    a netcode model (lossy link, server input queue, prediction, interpolation, lag compensation) tested at 50, 100 and
    250 ms; a telemetry client with consent per purpose, a schema without free text, persistence, sampling, export and
    erasure; crash fingerprints and a session marker. Example.Core now has 73 unit tests.
  - The C# example: crash reports through a Godot `Logger`, with consent, installed only by the running game.
  - `soak` command: one headless server and `-Clients` clients run together for `-Seconds`; fails on a crash, an engine
    error, a process that never got ready (`soak-failed`) or memory that keeps growing (`soak-leak`, `-MaxGrowthMbPerHour`).
  - The `architecture` runner warns when ENet's `create_server` gets a channel count (`enet-server-channels`): Godot 4.7.2
    uses it as the server's incoming bandwidth limit.
  - `doctor` warns when the Sentry addon starts before the player is asked, attaches the whole log, or sends personal data.
  - Release exports of the C# example map source paths to `/_/`, so stack traces do not carry the developer's paths.
- Saves, localization and input:
  - Skills: `godot-saves` (where and how to write so a crash or power cut loses nothing, plain-data formats, migrations
    and golden saves, cloud conflicts decided by lineage, saving without a freeze), `godot-localization` (keys, CSV or
    gettext, plurals, fonts for every script, right-to-left, pseudolocalization) and `godot-input` (actions, rebinding
    and saving bindings, keyboard and controller at once, prompts that follow the device, Steam Input, accessibility).
    Sources and what was measured: `docs/saves.md`, `docs/localization.md`, `docs/input.md`.
  - The C# example saves through a versioned, checksummed `SaveStore`: written to a temporary file, flushed and swapped in
    with a backup; loads recover from an interrupted write or the backup, chosen by a generation counter, and put the
    good copy back. Golden saves from versions 1 to 3 load in CI, and tests truncate and flip a bit at every byte.
  - The C# example's paddle takes keyboard and controller input at once (it still plays itself otherwise), with rebinding,
    bindings saved as JSON, and prompts that follow the device; gdUnit4 tests cover each.
  - `l10n` runner: fails on duplicate keys, untranslated entries (empty, fuzzy, short of plural forms) and keys the code
    uses that no table has. It reads Godot 4.6+ `?context` and `?plural` columns.
  - `shot -Locale fr,ar,ja` and `-Pseudo` take each scene in each language and pseudolocalized, and fail (`shot-text`) on
    text that is cut off, off screen, or has characters none of its fonts can draw.
  - A fresh checkout of a localized game no longer fails its first import: Godot logs "Cannot open file" for the
    `.translation` files it is about to make.
  - The `architecture` runner's `per-frame-alloc` also catches action names passed as string literals in C#
    (`Input.IsActionPressed("jump")` allocates a `StringName` on every call).
- Art and technical art:
  - Skills: `godot-asset-pipeline` (texture compression and pixel art, presets, atlases, Blender to glTF, naming, LODs,
    palettes, free libraries and their licences), `godot-shaders-vfx` (four tested shaders, shader cost, particles,
    post-processing per renderer, Low to Ultra tiers) and `godot-animation` (state machines with interruption rules, blend
    spaces, root motion versus in place, the twelve principles). Sources and what was tested: `docs/art.md`.
  - `assets.json`: `doctor` warns about images, sounds, models, fonts and shaders with no source or licence, and about
    non-commercial, GPL-family and unrecognised licences. It also counts the credits owed.
  - `doctor` also warns, in a pixel art project (Nearest filter), about textures with mipmaps, Lossy or VRAM compression, and
    stretch settings that are not integer.
  - `validate` compiles every `.gdshader`, used or not. Godot exits 0 on a broken shader, and headless loading does not
    compile one. The log scan now also captures `SHADER ERROR` lines, which name the file and line.
  - `bench` reports GPU time per frame, primitives drawn, and texture and video memory.
  - CI compiles every shader quoted in a skill (`tests/Test-SkillShaders.ps1`).
- Audio:
  - `godot-audio` skill: a bus per kind of sound with the player's sliders kept apart from the mix, adaptive music
    (`AudioStreamInteractive`, `AudioStreamSynchronized`, `AudioStreamPlaylist`), variation and voice limits, 3D sound,
    reverb and occlusion, ducking and pause, and loudness targets. Its sources, from FMOD, Wwise and Unreal to the Godot
    source and the loudness recommendations, are in `docs/audio.md`.
  - `audio` command: every sound file's integrated loudness, true peak and range (ffmpeg), by category, with warnings
    for files over -1 dBTP and voice or music files out of step. `-Mix` records the game's own mix with Movie Maker and
    fails it as `audio-off-target` (more than 2 LU from `-TargetLufs`, default -24), `audio-clipping` (over -1 dBTP) or
    `audio-silent`.
  - `doctor` names the kinds of sound with no bus of their own. The `architecture` runner warns about sound players
    left on Master (`audio-on-master`).
  - Godot 4.7.2's "resources still in use at exit" line, printed when a windowed run quits while a sound plays, is ignored.
    Before this, `bench` and `shot` failed on any game whose music played at the end of the run.
- Every program the kit runs has a time limit (30 minutes; `HYPERDOT_TIMEOUT` in seconds, `0` for none). A hung Godot is
  stopped with its child processes and fails with exit code 124, instead of stalling the run and the agent waiting on it.
- Lessons from studios, second pass: the captions of Croteam's Talos Principle post-mortem and Sasko's quest design talk
  replace their press write-ups, Croteam's talk on CI and automated testing is added, and Bohemia's published DayZ Central
  Economy files and Arma Reforger samples stand in for the wiki pages Cloudflare blocks. Folded into
  `godot-automation-hooks` (record a solution as intent and replay it; bug reports with place and view),
  `godot-game-design` (puzzle playtests, a quest review), `godot-game-plan`, `godot-architecture` (a spawn economy as data,
  replicating the smallest state, the headless server, graybox then reskin), `godot-procgen` (two-stage rolls, one label
  vocabulary) and `weekly-review`. New gates `beta.iterate` and `beta.localization`.
- Lessons from studios (`docs/studio-lessons.md`): about 110 lessons, each with a checked quote and its link, from Nintendo's
  Iwata Asks and the Breath of the Wild talks, 15 Shmuplations interviews, an excerpt of *The Untold History of Japanese Game
  Developers*, GSC, Croteam, Techland, CD Projekt Red, Warhorse, Bohemia, Gaijin and 1C, 20 postmortems counted for what
  recurs, and two talk transcripts. Folded into `godot-game-design` (how studios find the fun), `godot-game-plan` (what
  postmortems say goes wrong), `godot-automation-hooks` (what studios test), `godot-architecture` (data, simulation,
  networking) and `weekly-review` (outside eyes, pace).
- `plan.json` template: gates `concept.decisions`, `prototype.variants`, `production.playthrough` and `launch.archive`.
- `doctor` warns about input actions bound only to a keyboard or only to a gamepad, about menus a gamepad cannot confirm or
  leave (Godot's default `ui_accept` and `ui_cancel`), and about a project with no git repository or no remote.
  `tests/doctor-fixture`, written by Godot itself, checks it in CI.

- `godot-math` skill, adapted from Denny Burzynski's *Mathematics for Game Developers* (LibreTexts, CC BY 4.0): its
  vectors, matrices and trigonometry mapped to Godot 4's C# API. Godot's conventions measured in 4.7.2 where they differ
  from the book's: y points down, so a positive 2D angle turns clockwise on screen; radians; forward is -Z; `Bounce`, not
  `Reflect`, bounces off a surface. The book's worked answers match Godot's results; every call named compiles.

- Sources completed:
  - Game Accessibility Guidelines: the 16 basic and intermediate menu, settings and input rules that WCAG and the XAGs miss
    (game speed, settings remembered, one-press start, controls reminder from the input map, windowed mode, stationary
    buttons, subtitles before any sound, and more) in `docs/wcag-ui.md` and `godot-ui-accessibility`, summarised and
    linked, since the site states no licence for its text.
  - Tracery is Apache 2.0 (its repository's `LICENSE.MD`). `godot-procgen` uses its minified build for writing grammars
    and in web exports; it cannot be seeded, so games read the same grammar JSON with the seeded expander.
  - `templates/genres-uw.json`: the University of Washington gameplay and narrative genre vocabularies 1.3 (84 terms with
    scope notes), reused with the university's permission under CC BY-NC-SA 4.0; the GDD pitch uses them.
  - IGDB dropped. Marc LeBlanc's site has an expired certificate and stays optional.

- Sources rechecked once the owner allowed more hosts:
  - All 23 Xbox Accessibility Guidelines (v3.2) mapped to WCAG in `docs/wcag-ui.md`. Where they are stricter for games,
    `godot-ui-accessibility`, `templates/STYLE.md` and `godot-juice` follow them: text size as body height (26 px on
    console, 18 px on PC at 1080p), large text only from 36 or 52 px, flash area and red flashes, menu looping, focus kept
    in dialogs, touch targets in millimetres, no hold-to-confirm.
  - Other W3C documents for games (WCAG2ICT, IMSC subtitles, COGA, MAUR, XAUR, SSML) listed in `docs/wcag-ui.md`.
  - `godot-game-design` corrected against the MDA paper (its own labels; the list is not complete), the 400 Project's
    master list (around 110 rules, with real rule names) and the gameplay design patterns wiki (real pattern names; the
    2003 paper had three authors). New genre section.
  - `templates/genres.json`: 48 genre terms from Wikidata (CC0) with their ids, in gameplay and setting facets, and the
    query that refreshes them. The GDD template's pitch names its genres.
  - Licences confirmed for Kenney (CC0), OpenGameArt (per asset), the Fast WFC add-on (MIT), WaveFunctionCollapse and
    MarkovJunior (MIT). Tracery's is still unconfirmed.

- Procedural generation:
  - `godot-procgen` skill: seeds derived per generator with a fixed mix (SplitMix64), the techniques and where each comes
    from (noise, cellular automata, rooms, Wave Function Collapse and MarkovJunior, both MIT C#, text grammars, weighted
    tables), checking the data before building the scene, and tests that sweep a thousand seeds. Its C# compiles against
    Godot 4.7.2.
  - Fixed in `godot-automation-hooks`: it derived seeds with `HashCode.Combine`, which .NET randomises per process, so
    `--seed=N` did not reproduce a run (three launches gave three different values). It now points to `Seeds.Derive`, as does `godot-architecture`, which also suggested a plain XOR that
    collides (act 1 floor 2 equals act 2 floor 1).
- Fixed: a Godot crash during import on Windows (a negative exit code such as -1073741819) is now retried like a
  crash on Linux, instead of failing the run with `import-failed`.
- Game design:
  - `godot-game-design` skill: the MDA framework and its eight kinds of fun, the 400 Project's design rules of thumb,
    and Bjork and Holopainen's gameplay design patterns, summarised with links, plus a design review.
  - GDD features name the kinds of fun they serve on a `Fun:` line. `status -Json` returns `features[].fun` and warns
    about must and should features without one, or with an unknown kind. The template, the C# example's GDD and `/game`
    (drafting, cutting, new features) use it.
- Accessibility for menus and UI:
  - `docs/wcag-ui.md`: all 86 WCAG 2.2 success criteria read as rules for game menus, HUD and settings screens (31 apply as
    written, 49 in game terms, 6 do not apply), each with the Godot 4.7 property or API that meets it, read from the engine.
  - `godot-ui-accessibility` skill: the working rules (gamepad-only navigation, focus, WCAG contrast in C#, target size,
    screen readers through AccessKit, reduce motion, three flashes a second), with C# compiled against Godot 4.7.2.
  - Found in Godot 4.7.2's defaults: `ui_accept` and `ui_cancel` have no gamepad button, and `Color.Luminance` is not
    WCAG's relative luminance unless the colour goes through `SrgbToLinear()` first.
  - `templates/STYLE.md`: the Danger colour failed its own 4.5:1 rule (4.2:1); now #F2555A at 4.9:1, with each colour's
    ratio in the palette and the WCAG numbers in the readability and motion rules. `godot-juice`, `godot-ui-layout` and
    `look` point at the new rules.
- Look and feel (roadmap phase 4):
  - `shot -Baseline <folder>` compares each screenshot with the earlier one of the same name, inside Godot: `compare`
    (`changedPercent`, `sizeChanged`) and a `<name>.compare.png` with before, after and the changes in red.
  - `juice` runner, detected when the project has `juice.json`: plays the game headless at a fixed 60 fps with the bot's
    flags and checks the game's `[juice] event`/`feedback` lines: every event must get each listed feedback within its window.
    `tests/juice-fixture` and `tests/Test-JuiceLog.ps1` check it in CI.
  - `ci/godot/templates/STYLE.md`: a style guide with a `Resolutions:` line tools read; `status -Json` reports `look`.
  - Skills: `look` (writes the style guide with the user, critiques screens through `godot-verifier`, offers before and
    after as a multiple-choice question and records the choice) and `godot-juice` (the feedback checklist and how to log it).
- Architecture (roadmap phase 3):
  - `architecture` runner, detected for every project: a static scan for fragile node paths, UI scripts writing game state,
    per-frame node lookups and allocations, autoload events never unsubscribed, and too many autoloads. Every rule is a
    warning by default (`runnerResults[].warnings`); `architecture.json` in the project sets rules to `error` or `off`.
    `tests/architecture-fixtures` holds one triggering project per rule and a clean one, checked in CI.
  - `godot-patterns` skill: Game Programming Patterns mapped to Godot 4, with what the engine already provides.
  - `godot-architect` subagent: compares designs before code and records a decision (`templates/ADR.md`) in
    `docs/decisions/` for the user to accept. `status -Json` lists `decisions[]` and warns about proposed ones; `/game`
    shows them and sends new systems through the architect first.
- `/game` (roadmap phase 2):
  - `status -Json`: GDD features with the tests tagged `GDD:F<n>`, the plan, the latest run of each command, git activity and an
    inventory (scenes, autoloads, input actions, TODOs), with warnings. Read-only.
  - `ci/godot/templates/GDD.md`, a GDD format the kit can read; `examples/breakout` has a GDD and tagged tests.
  - `plan -Do add -Feature F3` links a task to a feature; `plan -Do link` records a task's feature, board card and the card's
    list, or the plan's board; `plan -Json` returns `tasks[]` and the board.
  - Skills: `game` (judges each feature with evidence in `plan/STATUS.md`, drafts the GDD the first time, keeps the
    board in step through the connector with the user's moves winning, proposes next tasks) and `weekly-review`.
  - The `AGENTS.md` template adds the scope rule (ask before building what the GDD does not contain) and the test tag.
- Weekly canary (`.github/workflows/canary.yml`, Fridays 18:47 UTC): `ci/godot/tools/Update-Versions.ps1` compares the pinned
  Godot, test-framework packages and GUT with the newest stable releases and rewrites every pin together;
  `ci/godot/tools/Invoke-Canary.ps1` tries the updates on both examples (all together, then one by one). Updates that pass
  become a pull request, failures an issue each, and a Godot minor without a GUT release is reported as blocked.
  First run on real releases: Microsoft.NET.Test.Sdk 18.11.0, Chickensoft.GoDotTest 2.0.48, xunit 2.9.3 and
  xunit.runner.visualstudio 4.0.1 pass; gdUnit4.test.adapter 3.1.1 fails (it needs the pre-release gdUnit4.api 5.1.0-rc5).
- Build diagnostics now include restore and project errors (`NU1605` and the like, with no line or column), not only compiler errors.
- Agent efficiency, each item measured or sourced in [docs/research.md](docs/research.md):
  - `-Quiet`: Godot and dotnet output goes only to `<Results>/hyperdot.log` (named by the new `log` JSON field); stderr drops
    from 7-16 KB to about 1 KB per test run on the examples.
  - Test failures now carry the specific `message`, `file` and `line` (GUT's bare "failed", Godot backtraces, `at line N`,
    C# stack traces) and a few lines of `details`, so the log rarely needs reading.
  - Run history in `.godot/hyperdot-history.jsonl` for `build`, `test`, `export`, `bench` and `shot`.
  - The kit is a Claude Code plugin (`.claude-plugin/`): the skills, a `godot-verifier` subagent for screenshots, benchmarks and
    export launches, and a Stop hook that keeps a turn from ending while Godot files changed after the last passing test run.
    `init -Plugin` enables it for a game; `init -Agents` also copies the subagent and fills in the kit path.
  - `retro` and `kit-review` skills (manual): lessons with evidence become kit pull requests, gated by the validators and evals.
  - `evals/`: `claude plugin eval` cases that compare the kit with no plugin, and a manual `Evals` workflow.
  - Skill validator: a skill may not set `model` outside a forked subagent (it loses the prompt cache); the `AGENTS.md`
    template is capped at 4 KB; subagents' kit commands are checked too. The template lost its skill list and layout section.
- `doctor` reports `GODOT_BIN`: missing file, wrong version, a non-.NET build for C#, a non-console build on Windows. `export`
  uses `GODOT_BIN` when matching export templates are installed. Hints printed by `init`, `doctor` and `plan` show the kit's real
  path and `-Project`, and `init` prints its "Next" line last.
- The kit no longer ships inside games: `.gdignore` files at the repository root and in `ci/godot/` keep Godot from importing and
  exporting the kit's `.gd` tools when it sits inside a project (a 4.7.2 export test found all four in the pack), and detection now
  skips folders with a `.gdignore`, as Godot does, so the kit's own examples no longer add GUT and flow runners to the game.
- The README now recommends cloning the kit outside the game and using `-Project`. `init -Agents` then writes the kit's full
  (quoted, when needed) path into `AGENTS.md` instead of a fragile `../../` path.
- `init -Agents` reports skills that already exist as skipped instead of added.
- From the Breakout Roguelike case study (`docs/case-study-breakout-roguelike.md`):
  - `bench`: frame pacing of a scene (1%/0.1% lows, p50/p99/max, frames over 20/33 ms, hitch log, draw calls, custom monitors such as GC
    counts), a labelled CSV row per run, and a `-BudgetMs` gate (`bench-over-budget`).
  - `shot`: PNG screenshots of scenes at a resolution, for agents to look at (`shot-failed`, `no-display`).
  - `-GameArgs`: the game's own flags, passed after `--` to smoke runs, `export -Run`, `bench` and `shot`.
  - `doctor` warns when a preset's include filter ships `.md`/`.pdf` documents.
  - Skills: `godot-performance`, `godot-automation-hooks`, `godot-ui-layout`, `godot-architecture`; thirteen pitfalls added.
  - Plan gates: automation flags and screenshots (vertical slice), bot balance runs (production), a measured performance gate (beta).
  - The C# example scales with the window (`canvas_items`, aspect `keep`); a 1080p screenshot showed it stuck in a corner.
- `-Json` on every command: one document on stdout, logs on stderr, stable `error.code`, build diagnostics and test failures with file and line ([docs/json.md](docs/json.md)).
- `plan` command and `ci/godot/templates/plan.json`: seven-phase solo plan with automatic and manual gates, timebox and WIP warnings.
- `flows` runner: declarative `*.flow.json` UI flows played headless in the real engine (press, input actions, waits, asserts on node properties).
- Editor-bridge MCP: `init -Mcp godot-mcp` registers satelliteoflove/godot-mcp in `.mcp.json` (adds only, backs up); docs/mcp.md compares it with godot-ai.
- `init -McpDiagnostics`: registers minimal-godot-mcp (GDScript diagnostics and the running game's console) next to the editor bridge; fixed `init -Mcp` failing when `.mcp.json` did not exist yet.
- `plan -Do add|move|sync`: tasks with a work-in-progress limit, and board sync (plan.json stays the source of truth).
- Skill quality: `ci/godot/tools/Test-Skills.ps1` validates structure, budgets, discoverability and that quoted commands, error codes and versions are real; fixtures that must fail; new `godot-verify-before-done`, `godot-ui-flows`, `godot-editor-bridge` skills; original descriptions rewritten to triggers only.
- Nine agent skills in `.agents/skills`, `AGENTS.md`/`CLAUDE.md` templates, and `init -Agents` to install them.
- Godot 4.7.2 as the default and example target; GUT is reinstalled when the Godot minor changes (stamped copies only).
- Docs reorganised: usage, reference, json, plan, strategies.

### Added
- Changes add a fragment under `changelog.d/` instead of editing `CHANGELOG.md`, and `ci/godot/tools/Update-Changelog.ps1` assembles them at release; `tests/Test-Changelog.ps1` covers it.
- Opus joins the staged programme as two more configurations, `opus` and `opus` with the plugin, marked `measuredApart`: they share a tier ceiling with each other only, so the standard four stay under the mid tier's $120. `cost-model.json` prices Opus tasks and milestones as estimates (2.2 times Sonnet, to be replaced by measured means). The dry run prices the mid tier at $43.20 for Opus and $61.65 for Opus with the plugin; no Opus session has run.
- `docs/retro.md` looks back over the 0.1.0 effort from the repository's records: what went well, what cost time (git's background maintenance, the ENet relay race, the usage limit that stopped run 44, CI growth, the `unchanged` rule, the judge calibration), numbers, lessons and what to change in 0.2. It names what the repository does not record.
- `docs/label/` holds the information sheets, JSON and label SVGs of the 0.1.0 tool programme for Haiku (D), Haiku with the plugin (G), Sonnet (F) and Sonnet with the plugin (F), rebuilt with `benchmark/Get-HyperdotLabel.ps1` from the 216 recorded sessions, which `benchmark/reference-runs/` now keeps. They reproduce the recorded indices exactly, and the tested class is A (97.2).

## Earlier
Interchangeable pipelines, gdUnit4Net/GoDotTest/GUT runners, coverage, PowerShell 7 rewrite with a Linux workflow, `doctor`,
`init`, `validate` runner, `export -Run`, PR comment and releases.
