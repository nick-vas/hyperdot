# AGENTS.md

This repository is a toolkit that lets AI coding agents build, test, export and plan Godot 4.7 games (GDScript or C#),
for any genre. One PowerShell 7 script runs locally on Windows and, packed into a workflow, on GitHub Linux runners.

## Layout

- `ci/godot/hyperdot.ps1` entry point: `test build export setup detect doctor init plan bench shot status audio soak credits sfx playtest help deck telemetry calendar brief promo clip`, all with `-Json`.
- `ci/godot/lib/*.ps1` one concern per file: Common, Setup, Detect, Report, Runners, Doctor, Init, Plan, Measure, Status, Architecture, Juice, Audio, Assets, Localization, Soak, Data, TextSize, Layout, Credits, Store, Web, Platforms, Sfx, Playthrough, Version, Steam, Context, Addons, Playtest, Palette, BuildSize, Help, Deck, Placement, Telemetry, Workflow, WorkingTree, Calendar, Brief, Promo, Clip.
- `ci/godot/workflow.json` the rules behind `status`'s `suggestedCommands` and the table in `docs/workflow.md` (when to run which command).
- `ci/godot/tools/` `validate.gd`, `flows.gd`, `bench.gd`, `shot.gd`, `textsize.gd`, `layout.gd`, `placement.gd`, `notices.gd`, `glyphs.gd` (run inside Godot), `web-smoke.mjs` (Node.js and Playwright, for `export -Run` of Web presets), `Sfxr.cs` (bfxr2's sound synth in C#, compiled by `sfx` with `Add-Type`; Apache-2.0 and MIT), `Heatmap.cs` (PNG heat maps for `playtest`, compiled with `Add-Type`), `Palette.cs` (PNG reader and CIEDE2000 palette check, compiled by `shot` with `Add-Type`), `Test-Skills.ps1` (skill validator),
  `Initialize-HyperdotGame.ps1` (sets the kit up for a game from local copies of the kit and Godot and makes a worktree for a parallel chat; [docs/usage.md](docs/usage.md)),
  `Update-Changelog.ps1` (assembles the `changelog.d/` fragments into `CHANGELOG.md` at release), `Update-Versions.ps1`, `Update-AddonStatus.ps1` and `Invoke-Canary.ps1` (the weekly check against new releases, and of the
  add-ons in `ci/godot/addons-status.json`, the known-status list `doctor` reads), release/PR-comment tools.
- `tests/` self-tests, most with a deliberately broken fixture (`tests/<name>-fixture`); the table under "Self-tests" says what each covers and needs.
- `ci/godot/templates/` files `init`, `plan`, `/game` and the architect copy into a game (`plan.json`, `plan-jam.json` for `plan -Do init -Profile jam`, `AGENTS.md`, `GDD.md`, `GDD-jam.md` for jams, `ADR.md`, `ARCHITECTURE.md` (kept by the architect), `STYLE.md`, `TECH-DEBT.md`, `TRAILER.md`, `kit-notes.md`, `placement_check.gd`, a test a game copies to check where levels place things, and `xr_math.gd` and `xr_rig.gd`, the `xr` skill's tested numbers and origin script), `ci/godot/templates/addons/hyperdot_report_pins/` (an editor add-on a game copies: `bug_report.gd` saves a report with its scene, place and view, and the add-on pins each on its scene), `ci/godot/templates/playtest-events.json` (the playtest telemetry schema `playtest` reads and games copy), `ci/godot/templates/licences/` (SPDX texts `credits` ships for MIT, ISC, BSD, Apache-2.0, MPL-2.0, OFL-1.1 and Zlib), and `genres-uw.json` (University of Washington, CC BY-NC-SA 4.0 with permission) and `genres.json` (Wikidata, CC0), the genre vocabularies.
- `.agents/skills/*/SKILL.md` the skills shipped to games (`init -Agents` enables the plugin that loads them; `-CopySkills` copies them for a host without plugins).
- `.claude-plugin/`, `agents/`, `hooks/` the Claude Code plugin: manifest and marketplace, the `godot-verifier` and `godot-architect` subagents, the Stop hook.
- `evals/` `claude plugin eval` cases (with and without the plugin); `docs/research.md` the measurements behind them.
- `benchmark/` the token benchmark (`Invoke-TokenBenchmark.ps1`; programmes `token-benchmark.json`, Hyperdot's own code, and
  `game-benchmark.json`, work on a small game graded by its tests, with hidden tests in `benchmark/game/`; the staged game programme
  of `PLAN.md` in `GameProgramme.ps1`, priced by `cost-model.json`; sessions as a separate user in `Isolation.ps1`; the private
  field test on an owner's game in `FieldTest.ps1` and `field-test.json`); each real run costs money, `-DryRun` does not.
  `Get-HyperdotLabel.ps1` and `label-scale.json` rate a version from its runs, like the EU energy label, one class per programme ([docs/label.md](docs/label.md)).
  Nothing outside `benchmark/`, `docs/token-benchmark.md`, `docs/label*` and their tests may name a benchmark task or profile:
  the sessions must not be able to recognise the test.
- `.github/actions/godot`, `.github/workflows/godot.yml` composite action and reusable workflow; `.github/workflows/self-test.yml` and `.github/scripts/Select-Jobs.ps1` decide what runs for a change ([docs/ci.md](docs/ci.md)); `ci/gitlab/` the GitLab CI
  template (`hyperdot.gitlab-ci.yml`, untested on GitLab) and `Invoke-Hyperdot.ps1`, its run step.
- `.github/workflows/promo.yml` the reusable weekly marketing brief (`promo`); `init -Promo` writes its caller into a game.
- `.github/workflows/release.yml` (run by hand) tags a release and publishes it, with `.github/scripts/Get-ChangelogSection.ps1` for the notes ([docs/ci.md](docs/ci.md)).
- `examples/csharp` (C#, every framework) and `examples/gdscript` (GUT): the integration fixtures.
- `docs/` per-topic documentation; `docs/json.md` is the output contract; `docs/help.md` is the text of `help` and `/kit`
  (a new command, skill or subagent needs an entry there).
- `site/` the GitHub Pages site: `Build-Site.ps1` builds it from `README.md`, `CHANGELOG.md` and `docs/**/*.md` (Markdig, as in
  `ConvertFrom-Markdown`, with GitHub's extensions) into `_site` (ignored) with `template.html`, `site.css` and `site.js`;
  `.github/workflows/pages.yml` publishes it ([docs/site.md](docs/site.md)).

## Working here

- PowerShell 7.6+, strict mode 3.0, `$ErrorActionPreference = 'Stop'`. Wrap results that may be empty or single in `@(...)`
  and iterate with `foreach`; never index a pipeline result (PowerShell unrolls one-item arrays). Under strict mode `.Count` on a
  scalar or `$null` throws, and so does dot access to a missing key or property: `@(...).Count`, `$h['k']`, `.ContainsKey()`.
- Short helper names collide with built-in aliases (`r` is Invoke-History, `rp` is Remove-ItemProperty, `h` is Get-History): use
  Verb-Noun names. In array literals `,` binds tighter than `+`: `@(1, 2 + 3)` is `(1, 2) + 3`, three items `1, 2, 3`; write `@(1, (2 + 3))` for `1, 5`. Overwrite a zip with
  `Compress-Archive -Force` instead of deleting wildcard paths. Windows machines have no Python: keep tooling in PowerShell or GDScript.
- Never `Write-Output` from helpers; return values are the pipeline. Logs go through `Write-CiLog`/`Write-Console` (stderr in `-Json`):
  in a child `pwsh` every stream but Error reaches stdout, so a direct `Write-Host`, a warning or a `ConvertTo-Json` without
  `-Depth` (it truncates at 2 and warns) breaks the JSON. Arrays go out as `-InputObject @(...)`, dictionaries as `[ordered]`.
- Fail with `Stop-GodotCi "message" 'stable-code'`. Codes are API: add to `docs/json.md`, never rename. Never pass
  `-ErrorAction SilentlyContinue` to the kit's own functions or lower `$ErrorActionPreference` (a `throw` is skipped),
  and never `continue` or `break` in `ForEach-Object`/`Where-Object`/`.ForEach()`: it ends the script with exit code 0; use `return`.
- A native program's non-zero exit code never throws: read `$LASTEXITCODE` on the next line. Pass arguments as an array,
  quote variables (`"$v"`: Linux globs them) and start child PowerShell as `pwsh -NoProfile -NonInteractive -File`.
- Paths from data take `-LiteralPath` (`-Path` reads `[ ]` as a wildcard and finds nothing, silently); .NET file APIs get absolute
  paths. Machine-read numbers and dates use `[cultureinfo]::InvariantCulture`. Never read and write one file in one pipeline.
  The rest, with sources: [docs/powershell.md](docs/powershell.md); PSScriptAnalyzer and `Test-PowerShellPatterns.ps1` hold part.
- `$script:JsonDoc` is the `-Json` result; add fields with `Set-JsonField`. The `-Json` switch and state must not share a name
  (PowerShell variables are case-insensitive).
- Scripts run inside Godot (`-s tools/x.gd`) cannot see the scene's `_ready` until the first frame: `await process_frame` after
  `add_child` before reading anything the scene sets up.
- `bench`, `shot` and `audio -Mix` need a display (and `audio` needs ffmpeg). Here, start `Xvfb :99 &` and set `DISPLAY=:99`; do not use `xvfb-run`, which merges stderr into
  stdout and breaks `-Json`.
- The `.gdignore` files at the repository root and in `ci/godot/` keep the kit out of a game it is placed inside (Godot neither
  imports nor exports it, and `Find-ProjectFiles` skips folders that have one). Do not remove them.
- Verify with the examples: `pwsh ci/godot/hyperdot.ps1 test -Project examples/csharp/game` and `-Project examples/gdscript`
  must be green, and `doctor` must report no problems on both (each example keeps one gamepad warning). The examples have no plan, so `plan` on them gives `no-plan` as expected; check
  `plan` the way the Plan step of `.github/workflows/self-test.yml` does: copy `examples/gdscript` to a temporary folder,
  `git init` it, run `plan -Do init -Project <copy>`, then `plan -Json -Project <copy>` (phase `concept`, at least one next
  action). Changing a version matrix entry means re-running both on that Godot.
- Run the self-test for what you change (table below; `.github/workflows/self-test.yml` runs them all). For skills,
  `pwsh ci/godot/tools/Test-Skills.ps1` and `pwsh tests/Test-SkillFixtures.ps1` must pass. A skill description says only when
  to use it, never how. Commands, flags, error codes and versions quoted in a skill are checked against the real script,
  `docs/json.md` and `examples/csharp`.
- Changelog: add a fragment, `changelog.d/<slug>.md`, whose first line is `Added|Changed|Fixed|Removed|Deprecated|Security: <entry>`,
  instead of editing `CHANGELOG.md` (every pull request would conflict on its top lines); the format is in `changelog.d/README.md`.
- Commit as the repository owner. Do not add AI attribution trailers to commits or PR descriptions.
- After a push or a merge, list the queued and in-progress workflow runs and cancel the ones a newer push has made redundant:
  older runs of the same branch or pull request, and push runs of main commits that a later merge supersedes. Keep the run of
  the newest head and the one that gates a pending merge. Redundant runs crowd the runners and delay the checks that matter;
  say what you cancelled.
- Do not rewrite pushed history.
- Code is written in the main conversation; a subagent is for volume or for independence, not for "it is code"
  ([docs/research.md](docs/research.md): many agents cost about 15 times the tokens and suit coding poorly). Delegate
  (1) watching CI and reading its logs, and any other read whose output is large and whose answer is short; (2) the review
  of a finished change, to an agent that has not seen the reasoning behind it; (3) issues that do not touch the same
  files, each in its own worktree and branch. The brief says what is already ruled out; the answer comes back as a
  verdict with its evidence, not as the log.
- Blocked access (a site, tool, credential or permission out of reach) is never a reason to drop a good idea: ask the
  owner for help, do what does not depend on it, and write down what could not be done and why in `docs/roadmap.md`.

## Self-tests

Each runs as `pwsh tests/<script>`; [docs/self-tests.md](docs/self-tests.md) says what each covers and needs (add a row for a new one),
and `.github/workflows/self-test.yml` runs them all. Run the ones for what you change. After adding a command, error code, lib file, tool,
skill, subagent or workflow job, run `tests/Get-CoverageMap.ps1`: it writes `docs/coverage.md`, and `Test-CoverageMap.ps1` fails on a missing or stale row.

## Targets

Godot 4.7.2 mono, .NET 8, PowerShell 7.6+. gdUnit4.api 5.0.0, gdUnit4.test.adapter 3.0.0, Chickensoft.GoDotTest 2.0.49,
GUT v9.7.1, coverlet.collector 10.1.0.
