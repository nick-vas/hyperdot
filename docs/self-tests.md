# Self-tests

What each `tests/Test-*.ps1` covers and needs. `tests/Get-KitCoverage.ps1` checks that every self-test has a row.
Each runs as `pwsh tests/<script>`. "Godot" means the kit downloads or finds Godot; "display" means Xvfb (see [AGENTS.md](../AGENTS.md), "Working here").

| Script | Covers | Needs |
|---|---|---|
| `Test-Changelog.ps1` | `Update-Changelog.ps1`: fragments grouped and sorted, an empty `changelog.d/`, bad fragments refused by name, the old Unreleased text kept (temporary folders) | - |
| `Test-ReleaseNotes.ps1` | `.github/scripts/Get-ChangelogSection.ps1`, the release notes of `release.yml`: first, middle and missing sections, `0.1.0` against `0.1.01` and `10.1.0`, an empty section, a trailing newline or a Unicode digit in the version, and `Test-MajorTagMove.ps1` (the major tag never moves backwards) (temporary changelog) | - |
| `Test-WorkflowLint.ps1` | the workflows read as text: a pull request's concurrency group is its number, `release` without exports fails, the canary's upstream code runs with no write permission or token, versions matched whole (`\A..\z`), `-MaxMinutes` always set; lists unpinned installs without failing | - |
| `Test-SkillFixtures.ps1` | the skill validator against broken skills (`skill-fixtures`) | - |
| `Test-ArchitectureFixtures.ps1` | the architecture rules (`architecture-fixtures`) | - |
| `Test-JuiceLog.ps1` | the juice runner (`juice-fixture`) | - |
| `Test-Audio.ps1` | `audio`'s loudness checks (`audio-fixture`, sounds it generates); `-Mix` records the mix | ffmpeg; `-Mix` a display |
| `Test-AssetManifest.ps1` | the asset manifest (`assets-fixture`) | - |
| `Test-Localization.ps1` | the `l10n` runner and `shot -Locale` (`l10n-fixture`) | Godot for glyphs; `-NoGodot` for the rest |
| `Test-ColorVision.ps1` | `shot -ColorVision` (`colorvision-fixture`) | Godot, display |
| `Test-Palette.ps1` | `shot`'s palette check against a style guide | Godot, display; `-NoGodot` for the synthetic part |
| `Test-Soak.ps1` | `soak` (`soak-fixture`, an ENet game; `soak-fixture-cs`, a C# server that catches SIGTERM) | Godot |
| `Test-Data.ps1` | the `data` runner (`data-fixture`) | - |
| `Test-TextSize.ps1` | the `textsize` runner (`textsize-fixture`) | Godot |
| `Test-Layout.ps1` | the `layout` runner (`layout-fixture`) | Godot |
| `Test-Flows.ps1` | the `flows` runner's rotation steps (`resize`, `hold`, `release`) and errors (`flows-fixture`); a flow failing on its own end line or error only, the engine's C# binding errors (`Handle is not initialized.`) as warnings with the flow that was running (fake logs), and `user://` a throwaway folder during the run | Godot; `-NoGodot` for the fake logs |
| `Test-Playthrough.ps1` | the `playthrough` runner (`playthrough-fixture`) | Godot; `-NoGodot` for the log part |
| `Test-Placement.ps1` | `ci/godot/templates/placement_check.gd` (`placement-fixture`), from a GUT test and as the `placement` runner; limits read from GDScript and C# | Godot |
| `Test-Typography.ps1` | the `typography` skill's Godot claims: every engine name its `godot.md` quotes against ClassDB (a made-up name must fail), and line pitch as font height plus `line_spacing`, `spacing_glyph` in pixels, tabular and proportional figures, `Label.uppercase`, feature names to OpenType tags (`typography-fixture`, GUT) | Godot |
| `Test-Xr.ps1` | the `xr` skill: every engine name it quotes against ClassDB and project settings (a made-up name must fail), a scene with an `XROrigin3D` running with no XR interface, a tracker standing in for a controller, and the tested numbers of `xr_math.gd` (`xr-fixture`, GUT) | Godot |
| `Test-ReportPins.ps1` | the report pins add-on: reports saved in 3D and 2D, found once, kept to their scene, placed on the camera's screen; the editor loading it headless (a project made in a temporary folder) | Godot |
| `Test-StaleTres.ps1` | `validate`'s stale `.tres` keys (`tres-fixture`) | Godot |
| `Test-Flaky.ps1` | `test -Retry` and `quarantine.json` (`flaky-fixture`, GUT) | Godot; `-NoGodot` for the synthetic part |
| `Test-ErrorKeys.ps1` | error keys and `status`'s `recurringErrors` (`errorkeys-fixture`) | Godot, git; `-NoGodot` for the synthetic part |
| `Test-TestsNotRun.ps1` | the `dotnet` runner's guard against gdUnit4 tests found but not run (synthetic TRX) | - |
| `Test-DotnetTempDir.ps1` | the `dotnet` and `gdunit4` runners giving each `dotnet test` its own temp folder: two runs at once under one TMPDIR reach their own Godot over gdUnit4Net's pipe, also under a TMPDIR too long for a socket, and leave no folder behind (pwsh stands in for dotnet and Godot; passes with a note on Windows) | - |
| `Test-FailureDelta.ps1` | `test`'s failure delta against the previous run (synthetic history) | - |
| `Test-Workflow.ps1` | the "which command now" rules of `ci/godot/workflow.json` (never run, failed, file newer, older than; stage gates; a phase every shipped plan needs), `status`'s `suggestedCommands` in a temporary project, and `docs/workflow.md` holding every row | - |
| `Test-Calendar.ps1` | `calendar`: the parsers on snapshots of Valve's Upcoming Steam Events, itch.io's jam calendar, Epic's free-games feed and LootRadar's `catalog.game` (`tests/calendar-fixture`); plan.json's discount schedule against Steam's rules; the release against the events (seasonal sales joined in full or part-way, Next Fest matched or suggested); the command end to end with `-Offline` on temporary projects whose cache it writes, with dates from today (`calendar.ics`, the history line, a missing source, nothing cached, the refusals) | - |
| `Test-Telemetry.ps1` | `telemetry`: per-command pass rate, mean, median, p95 and trend, the slowest runners, hot spots, flaky tests and recurring errors of a synthetic history (temporary projects); a missing file, a damaged line, too few runs, the window and the refusals | - |
| `Test-TestDuration.ps1` | `status`'s test duration (synthetic history) | - |
| `Test-Handoffs.ps1` | the handoff log: `status -Handoff` writes one line with the commit, cuts the text at 500 and 300 characters, keeps the newest 200, refuses bad arguments; `status` reads it back | git |
| `Test-ProcessTimeout.ps1` | the process time limit | - |
| `Test-CrashRetry.ps1` | the repeat of a crashed import or export (pwsh stands in for Godot); a Godot the kit starts gets `DOTNET_ROLL_FORWARD=Major` unless the user set one | - |
| `Test-DownloadFailed.ps1` | the `download-failed` code (about 15 s), and a download checked against Godot's `SHA512-SUMS.txt`: a match, a mismatch (`checksum-mismatch`, the file deleted), a release without the file or not listing the archive (a stand-in server on 127.0.0.1) | - |
| `Test-InstallLock.ps1` | two installs of one Godot taking turns, a dead run freeing the lock, `install-busy` | - |
| `Test-InitializeGame.ps1` | `ci/godot/tools/Initialize-HyperdotGame.ps1`: a dry run changes nothing; the setup commit, merge and worktree; a local Godot of the game's version found and others skipped with the reason, several listed with their paths and chosen (`-GodotChoice`, `-Godot`); `.claude/settings.local.json` written and excluded from Git; refusals leave the game untouched; a second run does no harm (a stub kit and fake Godot scripts; passes with a note on Windows) | git |
| `Test-SceneCount.ps1` | `bench`'s and `audio`'s refusal of several scenes | - |
| `Test-ShotChanged.ps1` | `shot -MaxChangedPercent`; scenes that share a file name get their own pictures | Godot, display |
| `Test-BenchSweep.ps1` | `bench -Sweep`: one run per value, labelled CSV rows, a value over the budget marked, a run with engine errors failing the sweep (`tests/bench-fixture/sweep.tscn`, headless) | Godot |
| `Test-BenchHotspots.ps1` | `bench`'s hotspots, load time, draw calls, frame-time histogram and their limits (`bench-fixture`) | Godot, display |
| `Test-GpuValidation.ps1` | `-GpuValidation` for `bench`, `shot` and `export -Run` (`gpuvalidation-fixture`, a deliberate Vulkan misuse; canned logs) | Godot, display, Vulkan and its validation layer (`mesa-vulkan-drivers`, `vulkan-validationlayers`); the export part Godot's templates (`-NoExport` skips it); `-NoGodot` for the log reading |
| `Test-Deck.ps1` | `deck`, the Steam Deck check: every part runs, one verdict (`deck-fixture`, a 1080p UI at 1280x800) | Godot, display |
| `Test-MonoAudio.ps1` | the mono option measured in the engine (`mono-fixture`) | Godot |
| `Test-Capture.ps1` | the skill's capture mode (`capture-fixture`, C#) | Godot, display |
| `Test-Credits.ps1` | `credits` (`credits-fixture`) | Godot |
| `Test-Sfx.ps1` | `sfx`'s sounds against values recorded from bfxr2 | - |
| `Test-Steam.ps1` | the Steam checks (`steam-fixture`, Steamworks files and calls that misname them) | - |
| `Test-Store.ps1` | `doctor`'s store art, trailer, tag and privacy checks (generated images, ffmpeg videos) | ffmpeg |
| `Test-Platforms.ps1` | `doctor`'s Web and Android checks | - |
| `Test-Web.ps1` | Web `export -Run` (`web-fixture`) | Godot's templates, Node.js, a Playwright browser |
| `Test-Addons.ps1` | `doctor`'s add-on and GDExtension checks (a project made in a temporary folder), the known-status list and its refresh (made-up repositories) | - |
| `Test-DoctorFixture.ps1` | `doctor`'s copies of one file, occluders with occlusion culling off and bodies moved without physics interpolation, each way (`doctor-fixture` and copies of it) | - |
| `Test-RepoHygiene.ps1` | `doctor`'s repository checks (a broken project made in a temporary folder, since reserved names or case twins committed here would break Windows checkouts), the warning about kit files that are not committed, and `-ReportIssue` against a stand-in `gh` (nothing created without a yes, no file contents or paths in the text, an open issue not duplicated; Linux and macOS) | git |
| `Test-Help.ps1` | `help` and `docs/help.md`: an entry for every command, skill and subagent, none for what does not exist, quoted calls that bind | - |
| `Test-Context.ps1` | `doctor`'s check of agent instructions; holds the template, skills and docs to the kit's real flags | - |
| `Test-Plan.ps1` | the plan template's gates (only test frameworks count as tests), `plan -Do move` with several ids (all move or none), the release timeline, `plan` under a day-first culture, `init` keeping an existing starter test and pinning its workflow at `@v1`, `init -Agents` / `-Plugin` writing the kit notes (`ci/godot/templates/kit-notes.md`) into the game, enabling the plugin from GitHub or the local folder and copying no skill, `-CopySkills` refusing a game that enables the plugin, and no `docs/kit-help.md`, a plan `plan` and `status` cannot read, `plan -Do reopen`, the risk, optional budget and placeholder gates, the jam plan sized in days, `status`'s first-session steps (tests, stubs, warnings), and `-TimeoutSec` (a fake git and gh that never answer: `status` and `plan` return in seconds with `partial` naming what they waited for, `plan -Do sync` stops with `command-timeout`, the flag is refused on other commands; Linux and macOS) | - |
| `Test-ProjectSync.ps1` | `plan -Do sync` and the project-sync Stop hook against a stand-in `gh` (a new project with its Column field and repository link, moves both ways, a failure halfway, a missing option, refused credentials, items added on the board, removed tasks, column names, `-Board` forms); `-Live` against GitHub on a private project it deletes | `-Live`: `gh` signed in with the `project` scope |
| `Test-Playtest.ps1` | `playtest`'s report and heat maps (`playtest-fixture`, synthetic sessions), and the limits of the shipped event definitions | - |
| `Test-BuildSize.ps1` | `export -Json`'s size breakdown: a synthetic pack read as a file, embedded and zipped; a real Linux export of a copy of `examples/gdscript` | Godot's templates; `-NoGodot` for the synthetic part |
| `Test-GitLabTemplate.ps1` | the GitLab CI template: parsed, held to GitLab's keywords, its report paths matched against the kit's JUnit (TRX converted) and Cobertura files, its variables against the action's inputs | - |
| `Test-GameVersion.ps1` | `export -GameVersion auto`, Android version codes, download names (temporary git repositories) | git |
| `Test-UpdatePins.ps1` | `Update-Versions.ps1`: a missing pinned file fails, fixture pins move with Godot, GUT stays with its Godot minor, a new minor with its GUT release and a package update rewrite every pin and keep the skills valid; the canary's exit checks and pairing, aseprite-mcp's pins tried through a stand-in uvx, the add-on status refresh (copies of the repository) | - |
| `Test-PrComment.ps1` | the PR comment's paging, ignoring others' marker comments, the push-only coverage baseline (a stand-in GitHub API on 127.0.0.1) | - |
| `Test-SkillShaders.ps1` | shaders quoted in skills compile | Godot |
| `Test-DocLinks.ps1` | links and quoted paths in the docs and skills | - |
| `Test-Site.ps1` | the GitHub Pages site: a page for every Markdown source, every internal link, anchor and repository link resolving, no `.md` links left, one h1, a title, lang and the viewport meta on every page, nothing fetched from another host, the label SVGs shown, the colours at WCAG 2.2 AA in light and dark; a made-up repository with a broken link and anchor, and the builder's fixes where Markdig differs from GitHub (`-Site` checks a built site) | - |
| `Test-CoverageMap.ps1` | `docs/coverage.md` has a row for every command, error code, lib file, tool, skill, subagent and workflow job; `-Check` catches missing, stale and wrong rows; records are credited to the test they name | - |
| `Test-LibNames.ps1` | function names across `ci/godot` (unique, also inside blocks; no clash with a built-in alias, cmdlet or function) | - |
| `Test-PowerShellPatterns.ps1` | every tracked `.ps1` free of the anti-patterns of `docs/powershell.md` that have no use left (`continue` in a pipeline block, `Resolve-Path` without `-LiteralPath`, unquoted `Start-Process -ArgumentList`, an interpolated `-replace` replacement, `ConvertTo-Json` without `-Depth`, a path cmdlet without `-LiteralPath`, a parameter given twice, a command that does not exist, a child `pwsh` without `-NonInteractive`, `$null` on the right, `Invoke-Expression`, `[IO.Path]::Combine`, `$PSBoundParameters.Name`, a lowered `$ErrorActionPreference`, relative literal paths to .NET, `-Version Latest`, Windows-only aliases, one file read and written in one pipeline), read from the syntax tree; each check fires on its file in `powershell-patterns-fixture` and not on its clean file | - |
| `Test-KitPaths.ps1` | the kit run from a folder named `kit [v2]` (a runner finds its tool), a `$` in project.godot's version line and `solution_directory` | Godot; `-NoGodot` for the text part |
| `Test-OldState.ps1` | the one-time move of state from the names before Hyperdot (history, GUT stamp, tools folder, workflow, plugin entry) | - |
| `Test-TokenBenchmark.ps1` | the token benchmark's counting, grader, retries and the copy its sessions run in (a stand-in CLI) | - |
| `Test-HyperdotLabel.ps1` | the label: index, classes, minimum, verification, rescaling and the tool and game programmes (`label-fixture`, made-up runs) | - |
| `Test-EvalGraders.ps1` | the regex and tool_used eval graders against real sessions from past Evals runs (`eval-grader-fixtures`, made by `New-EvalGraderFixture.ps1` from the workflow's artifact): a stand-in gives every verdict the runs recorded, each grader as it is now agrees with a person's reading, and each has a session to pass and one to fail or a reason in `gaps.json` | - |
| `Test-ReviewPairs.ps1` | `Invoke-SideBySide.ps1 -ReviewOut` (blind pairs and their key), `-Votes` (each order judged several times, the majority or a tie deciding; stand-in judges) and `Get-JudgeAgreement.ps1` (made-up runs and verdicts; `-Calibration`: two sets, one kept out of the agreement, a swapped re-judge setting the bar) | - |
| `Test-GameBenchmark.ps1` | the game programme (`benchmark/game-benchmark.json`): a copy of the game per session, grading by the kit's tests, hidden tests and mutants (`game-benchmark`, a stand-in CLI doing each task well and badly) | Godot |
| `Test-BenchmarkIsolation.ps1` | `-Isolate`: sessions as a user made for the run cannot read the benchmark, a hidden test or the checkout and are still graded; credentials pass and nothing else; leftover processes, links and git settings die with the session; `runuser` and `sudo` | Godot; Linux with root or passwordless sudo (elsewhere it passes with a note) |
| `Test-FieldTest.ps1` | the field test (`-GameSource`): the mutant planter, runs on copies of both examples with good and bad work, `doctor-green`, a report of numbers only | Godot (.NET build); `-NoCSharp` skips the C# game |
| `Test-SelectJobs.ps1` | `.github/scripts/Select-Jobs.ps1`, what a change runs in `self-test.yml`: the sample of staged-programme pairs for the check's own code, the pair of a changed game, everything on main, schedule and dispatch, and when the base cannot be fetched (a temporary repository for the git part) | - |
| `Test-InputHash.ps1` | the input hash of each Self-test job (`Select-Jobs.ps1 -Inputs`, `Get-InputHash.ps1`): a change moves the hash of the jobs that read the file and lint's, a docs-only commit lint's alone, the event and runner image every hash; `Write-CacheObservations.ps1` (what is recorded, never for a fork); a temporary repository | - |
| `Test-GameProgramme.ps1` | every task of a staged game programme, without a model: the untouched game fails its grading, the task's reference solution passes, its decoy fails (`-SpecPath` for another programme; the self-test runs it on `game-benchmark/programme`) | Godot |
| `Test-ErrorCodes.ps1` | every documented error code no other self-test raises, raised and checked in the JSON; `invalid-arguments` for an unknown command or flag, a value outside its set and a word too many | Godot, display, ffmpeg; `-NoGodot` for plan, init, detect, doctor, audio and the arguments |
| `Test-Detect.ps1` | the solution `detect` picks, in and out of git, past unrelated and empty solutions and scenes; the project file walk (`Find-ProjectFiles`): order by name, skipped folders (addons, bin, obj, dot folders, `.gdignore`), case-insensitive filter, brackets in names | - |
| `Test-InstallAddon.ps1` | replacing GUT in a path with brackets (a stand-in git) | - |
| `Test-StopGate.ps1` | the Stop hook: only a full passing run counts; deletions, commits, non-ASCII names, data files | git |
| `Test-ResultsDir.ps1` | `test` refusing a `-Results` folder inside the project it did not make | Godot; `-NoGodot` for the refusals |

`tests/Get-KitCoverage.ps1 -From <folder>` reports what the self-tests reach when run with `HYPERDOT_COVERAGE` set to that
folder; the `coverage` job of `self-test.yml` collects every job's records and fails below its floors.
`tests/Get-CoverageMap.ps1` writes `docs/coverage.md`: the tests behind each command, error code, lib file, tool, skill,
subagent and workflow job, and the gaps (`-From <folder>` first refreshes `tests/coverage-records.json` from such records;
a kit run names the `Test-*.ps1` that started it). Run it after adding any of those; its `-Check`, run by
`Test-CoverageMap.ps1`, fails on a missing or stale row.

