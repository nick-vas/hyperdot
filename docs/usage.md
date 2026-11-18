# Usage scenarios

Eleven ways to use the kit. The [README](../README.md) has the short version.

### 1. Add the kit to an existing game

Keep the kit outside your game and point it at the game with `-Project`; then none of the kit's own code ends up in your
repository or your exported builds (`init` adds only the files listed below):
```powershell
git clone https://github.com/nick-vas/hyperdot C:\Tools\hyperdot
pwsh C:\Tools\hyperdot\ci\godot\hyperdot.ps1 init -Project 'C:\path\to\your\game'
```
With the kit outside, `init -Agents` writes its full path into `AGENTS.md`, so agents call it from there (the skills come from the plugin; the path only names the script `AGENTS.md`'s commands run, so keep that clone on the version you want).

To share one pinned version with everyone on the game's repository instead, add it as a submodule:
`git submodule add https://github.com/nick-vas/hyperdot tools/hyperdot`. Its folders carry a `.gdignore` file, so
Godot never imports or exports them, and the kit's own detection ignores them. If you copy only the `ci/godot` folder,
keep its `.gdignore`: without it, the kit's `.gd` tool scripts (ten in `ci/godot/tools`, and the templates' `placement_check.gd`) would be exported with your game.
`init` only adds things and never overwrites a file, so it's safe to run again. It adds:
- a starter test: gdUnit4Net for C# projects (packages kept out of release builds), GUT for GDScript;
- `.gitignore` entries and test-folder exclusions in your export presets;
- `solution_directory` in `project.godot` when your `.sln` lives outside the project folder;
- `.github/workflows/hyperdot.yml`, unless a workflow in the repository already calls the kit, under any name. `init` never makes a second one, and
  leaves a workflow that still calls the kit by its old name (`Godot_TestSuite`) as it is when another one calls it too; `doctor` warns when two
  workflows call the kit, since two runs on every push in one concurrency group cancel each other.

  The workflow runs on pull requests and on pushes to `main`, and not for a change to `docs/`, `plan/`, Markdown files or
  `.gitignore` alone (`paths-ignore`): on a private repository every run spends the account's Actions minutes, and a
  status or plan update is not worth one. The push to `main` stays, because it checks the merge (two pull requests that
  pass apart can fail together) and saves the caches (Godot, export templates, the import) that pull requests read: GitHub
  lets a pull request read the default branch's caches, and evicts a cache unused for 7 days. **If branch protection
  requires this check**, a pull request that changes only documents never gets it and cannot merge; then remove
  `paths-ignore` under `pull_request`, or do not require the check. A workflow an older `init` wrote has no
  `paths-ignore`; copy the `on:` block from a new one to adopt it.

With `-Agents` it also writes `AGENTS.md`, `CLAUDE.md` and `docs/kit-notes.md` (where the agent notes each
time the kit got in the way), and enables the kit as a Claude Code plugin in `.claude/settings.json`. The plugin supplies the
skills, the subagents and the hooks, so nothing is copied into the game and nothing there goes stale; the skills are named
`/hyperdot:game` and so on. It comes from GitHub (`-PluginSource github`, the default: any machine, cloud sessions; every commit on `main` is a new plugin
version, fetched with `claude plugin update hyperdot@hyperdot` or by the marketplace's auto-update) or from the kit's folder (`-PluginSource local`: a `git pull` there updates every
game). `-CopySkills` copies the skills and subagents instead, for a host that loads no plugins; it is refused in a game that
already enables the plugin, because each skill would load twice. `docs/kit-help.md` is no longer written: `help` and `/kit` write
`.godot/kit-help.md`, which no repository tracks. Start every Claude Code session in the game with `/game`: it reads where the game stands and
ends with the next tasks to pick from ([plan.md](plan.md#the-gdd-status-and-game)).

**One script for the whole setup, and a second working copy for a parallel chat.** `ci/godot/tools/Initialize-HyperdotGame.ps1`
checks the game's Git repository, git and the .NET 8 SDK, finds the kit, runs `doctor`, adds the kit on a branch
(`init -Plugin`, the same as `init -Agents`), runs the tests, commits and merges the branch, and makes a Git worktree on a new branch so a second
Claude Code chat can work on the game while you keep working in the editor:
```powershell
pwsh C:\Tools\hyperdot\ci\godot\tools\Initialize-HyperdotGame.ps1 -Game 'C:\path\to\your\game' -DryRun   # prints what it would do
pwsh C:\Tools\hyperdot\ci\godot\tools\Initialize-HyperdotGame.ps1 -Game 'C:\path\to\your\game'
```
It looks for local copies before it downloads anything, and downloads nothing unless you pass `-AllowDownload`:
- the kit: `-Kit`, the clone the script is in, `HYPERDOT_KIT`, `C:\Tools\hyperdot`, `~/hyperdot` (never updated unless `-UpdateKit`);
- Godot: `GODOT_BIN`, the kit's own folder `~/.hyperdot`, then Godot executables in `-GodotSearchPath` (several: separate with commas)
  and the usual folders (`-NoDefaultSearch` leaves those out). Each is run with `--version`, and only a copy of the
  game's version is kept (the .NET build for a C# game; on Windows the `_console.exe`). One match is used. Several are
  listed with their paths and you choose, or pass `-GodotChoice <number>` or `-Godot <path>`. None: it stops before
  changing anything, and with `-AllowDownload` lets the kit download the version on its first run.

A Godot found outside the kit's folder is written to `.claude/settings.local.json` (`env.GODOT_BIN`) in the game and in the
worktree, and that file is excluded in `.git/info/exclude`; `GODOT_BIN` is not set for the machine, because the kit uses it
without checking its version. A second run skips what is done. In the Claude desktop app, open a local session on the
worktree folder the script prints and send `/game`.

### 2. Run the tests locally, and check your setup

```powershell
pwsh ci/godot/hyperdot.ps1            # build + every detected test
pwsh ci/godot/hyperdot.ps1 doctor     # tools and project checks, each with a fix
pwsh ci/godot/hyperdot.ps1 detect     # show what it found, change nothing
Get-Help ci/godot/hyperdot.ps1 -Detailed
```
`doctor` catches the mistakes that break CI or ship broken builds. Examples: no `solution_directory`
(exports would silently drop your C# code), test packages or test folders going into release builds, GUT
files that won't run, a GDExtension with no library for a build a preset exports (picked as Godot picks it,
[docs/addons.md](addons.md)) or for the machine the kit runs on (the editor and `test` need one too), C# files with no project to compile them, a `Godot.NET.Sdk` pin or a workflow's `godot-version` that names another Godot, and a missing .NET SDK. Godot is downloaded once to `~/.hyperdot`. Among its warnings:
copies of one asset file, `OccluderInstance3D` nodes with occlusion culling off, and bodies moved per physics tick with
physics interpolation off ([docs/profiling-and-builds.md](profiling-and-builds.md#kit-changes)).

It also reads the instructions every agent session loads: `AGENTS.md`, `CLAUDE.md` and `CLAUDE.local.md` at the
repository root (and in the project folder), with the files they import (`@path`, up to four hops, as Claude Code
does). It warns about a kit call with a command or flag the script does not have (read from the script's own
parameters, so `-Quite` and an ambiguous `-Re` are caught and `-Runn` is not), a file or `res://` path that does not
exist, an import that loads nothing, and a file over 200 lines. Lines a game kept unchanged from the kit's template are
the kit's to keep right and are skipped. These are warnings: a stale line does not break the build, but every session
follows it.

### 3. The same tests on a GitHub Linux runner, with a PR comment

```yaml
on: [push, pull_request]
jobs:
  godot:
    permissions:
      contents: read
      pull-requests: write     # lets it comment; without this it just warns
    uses: nick-vas/hyperdot/.github/workflows/godot.yml@v1
```
The workflow runs the same script, with the same detection, on `ubuntu-latest`, the cheapest runner. On
pull requests it keeps a single comment up to date with the results table, failures, and coverage compared
with the base branch. You don't need the submodule for CI; the workflow brings its own copy of the script,
pinned to the `@ref` you use.

`@v1` is what `init` writes. It is a moving tag on this repository that points at the release games should run, so a
change on the kit's `main` reaches no game until a release moves the tag, and a game moves up (to another tag, or a commit)
on purpose, in a commit of its own. A workflow `init` wrote earlier keeps the ref it has.

### 4. A GDScript-only game with GUT

Write `test_*.gd` files that `extends GutTest`, and the kit installs the GUT version for your Godot
release; you don't commit `addons/gut`. See [`examples/gdscript`](../examples/gdscript).

### 5. A C# game with unit tests, scene tests and in-engine tests

Keep engine-free logic in a class library tested with xUnit, add gdUnit4Net scene tests, and optionally
GoDotTest suites. All of them are detected and run. See [`examples/csharp`](../examples/csharp) and the
[framework setup notes](godot-pipelines.md#setting-each-one-up).

### 6. Fast pull-request checks, full runs on `main`

```yaml
on:
  pull_request:
  push:
    branches: [main]
jobs:
  godot:
    permissions: { contents: read, pull-requests: write }
    uses: nick-vas/hyperdot/.github/workflows/godot.yml@v1
    with:
      # Unit tests only on PRs; every framework once merged.
      runners: ${{ github.event_name == 'pull_request' && 'dotnet' || '' }}
```

### 7. Windows builds, checked and released on every tag

```yaml
on:
  push:
    tags: ['v*']
jobs:
  release:
    permissions:
      contents: write          # to create the release
    uses: nick-vas/hyperdot/.github/workflows/godot.yml@v1
    with:
      exports: Windows         # a preset name from export_presets.cfg, or "all"
      run-exports: true        # launch the .exe on a Windows runner and fail on errors
      release: true            # zip it and publish a GitHub Release with generated notes
```
Tests run first. Then each preset is exported, launched headless on a runner of its own OS, and zipped
as `<game>-<tag>-<preset>.zip` into a GitHub Release. Launching the export catches what the editor hides:
missing assets, code trimmed from the build, and release-only bugs. On a non-tag run, `release: true` builds
the zips but doesn't publish them (a dry run).

Locally: `pwsh ci/godot/hyperdot.ps1 export -Preset Windows -Run` exports to `build/` and launches the
`.exe`.

### 8. Coverage report and a minimum

```powershell
pwsh ci/godot/hyperdot.ps1 -Coverage            # report: test-results/coverage/index.html
pwsh ci/godot/hyperdot.ps1 -MinCoverage 60      # fail below 60% line coverage
```
In the workflow: `coverage: true` or `min-coverage: 60`. GoDotTest measures code that only runs inside the
engine. dotnet coverage needs `coverlet.collector` in the test project, and covers code tested outside
the engine: gdUnit4Net's `[RequireGodotRuntime]` tests run inside Godot, where the collector can't see them.

### 9. Run a subset of tests

```powershell
pwsh ci/godot/hyperdot.ps1 -Runners dotnet -Filter 'FullyQualifiedName~Combo'   # dotnet test filter
pwsh ci/godot/hyperdot.ps1 -Runners gut -Filter test_combo                       # GUT test name
pwsh ci/godot/hyperdot.ps1 -Runners godottest -Filter PlayerTest                 # GoDotTest suite
pwsh ci/godot/hyperdot.ps1 -Runners validate                                     # just the load check
pwsh ci/godot/hyperdot.ps1 -Runners none                                         # build only
```
The workflow takes the same values as `runners` and `filter` inputs, e.g. for a manual `workflow_dispatch`.

A test that fails now and then: `-Retry 1` (workflow input `retry: 1`) runs a failed runner once more and passes if the
retry does, but lists every test that passed only on the retry in `flaky[]` and `summary.md` and records it, so `status`
can name the repeat offenders. A test that keeps failing can go into the project's `quarantine.json` for a few weeks, with
an owner: it still runs and is reported, but does not fail the run; after its date `doctor` fails until it is fixed or
deleted. The policy is Rare's for Sea of Thieves ([gdc/sea-of-thieves-automated-testing.md](gdc/sea-of-thieves-automated-testing.md)).

Tests that wait for physics ticks: `-FixedFps 60` (workflow input `fixed-fps: 60`; use the game's physics tick rate) runs
`smoke` and the Godot that gdUnit4 starts at fixed game time, so each tick costs CPU time instead of 1/60 s of wall clock. On
the C# example the gdUnit4 tests went from 36 s to 13 s and the whole run from 59 s to 36 s, with the same tests passing and
planted bugs still caught ([research.md](research.md#test--fixedfps-on-the-c-example)). With `-Coverage` the gain was 2 s: coverage
collection made the plain .NET tests the slowest part instead. Off by default, because audio, the network and .NET timers
(`Task.Delay`, `Stopwatch`, `Time.GetTicksMsec`) still follow the wall clock: a test tied to them sees much less time pass.

### 10. Several games in one repository

```powershell
pwsh ci/godot/hyperdot.ps1 -Project games/arena
```
```yaml
jobs:
  godot:
    strategy:
      matrix:
        project: [games/arena, games/puzzle]
    permissions: { contents: read, pull-requests: write }
    uses: nick-vas/hyperdot/.github/workflows/godot.yml@v1
    with:
      project: ${{ matrix.project }}
```
Artifacts and PR comments are per game (named after `config/name`), so they don't collide. A test results artifact also
names the `runners` input when it is set, so two jobs that test one game with different runners keep apart.

### 11. GitLab CI

Untested on GitLab: [`ci/gitlab/hyperdot.gitlab-ci.yml`](../ci/gitlab/hyperdot.gitlab-ci.yml) is written against GitLab's
documented keywords and checked by `tests/Test-GitLabTemplate.ps1` (it parses the file, checks its keys, and matches its
report paths against what the kit writes), but it has never run on a GitLab runner. Reports of a first run are welcome.

```yaml
include:
  - remote: https://raw.githubusercontent.com/nick-vas/hyperdot/v1/ci/gitlab/hyperdot.gitlab-ci.yml
variables:
  HYPERDOT_PROJECT: game        # the folder with project.godot, if not found by itself
  HYPERDOT_COVERAGE: "true"
```

It adds two jobs, the same steps as the GitHub action: `hyperdot-test` (stage `test`, every pipeline) sets up Godot and
runs `test`; `hyperdot-export` (stage `deploy`, the default branch and tags) runs `export` and keeps `build/` as the job's
artifact. Both run in `mcr.microsoft.com/dotnet/sdk:8.0`, which holds .NET 8 and git. Its PowerShell is the global tool
that follows .NET 8 (7.4), older than the kit's 7.6, and PowerShell 7.6 is built on .NET 10, so `before_script` unpacks
PowerShell's self-contained Linux build (`HYPERDOT_PWSH_VERSION`, 7.6.9; cached in `.hyperdot-cache/pwsh/`), puts it first on
PATH and stops the job if `pwsh` is still older than 7.6; games still build with the image's .NET 8 SDK. The kit
clones itself into `/tmp/hyperdot` at `HYPERDOT_REF` (set `HYPERDOT_KIT` to a folder that holds it, such as a submodule,
to skip the clone) and downloads Godot like anywhere else. The GitHub action's inputs are variables, upper case with
underscores: `HYPERDOT_PROJECT`, `HYPERDOT_GODOT_VERSION`, `HYPERDOT_RUNNERS`, `HYPERDOT_FILTER`, `HYPERDOT_RETRY`,
`HYPERDOT_COVERAGE`, `HYPERDOT_MIN_COVERAGE`, `HYPERDOT_PRESET`, `HYPERDOT_RUN_EXPORTS`, `HYPERDOT_GAME_VERSION`
(`ci/gitlab/Invoke-Hyperdot.ps1` turns them into `hyperdot.ps1`'s parameters).

- **Tests in merge requests:** `test` also writes every runner's results as JUnit into `test-results/junit/` (JUnit runners
  copied, the TRX of `dotnet` and `gdunit4` converted, failed `-Retry` attempts left out; `junitDir` in `-Json`), which the
  job reports through `artifacts:reports:junit`. `test-results/` is kept as an artifact, also when the tests fail.
- **Coverage:** with `HYPERDOT_COVERAGE` or `HYPERDOT_MIN_COVERAGE`, each runner's Cobertura file
  (`test-results/<runner>/coverage/*.cobertura.xml`) goes to `artifacts:reports:coverage_report`, and the job's `coverage`
  regex reads the kit's `Line coverage: 85.2%` line for the badge.
- **Caches:** Godot and NuGet packages in `.hyperdot-cache/tools` and `.hyperdot-cache/nuget` (`GODOT_TOOLS_DIR`,
  `NUGET_PACKAGES`), export templates in `.hyperdot-cache/data` (`XDG_DATA_HOME`): inside the checkout, the only place
  GitLab caches, with a `.gdignore` so Godot skips it. The tools cache is saved even when the job fails.
- **Exports:** one job for every preset by default; extend `.hyperdot` with `HYPERDOT_PRESET` for one job per platform.
  `GIT_DEPTH: "0"` lets `HYPERDOT_GAME_VERSION: auto` read the tags. Git LFS files are fetched by GitLab's runner before the job.
- **Not covered:** the GitHub workflow's PR comment, the import cache, and the Android Gradle cache. A smaller image with
  Godot already in it is on the roadmap.

### 12. A weekly marketing brief

```powershell
pwsh ci/godot/hyperdot.ps1 init -Promo
```

adds `.github/workflows/hyperdot-promo.yml` and `docs/promo.json`. Every Monday at 08:17 UTC the workflow runs `promo` on
`ubuntu-latest` (it reads git and the API and never runs Godot: about a minute of Actions time) and opens an issue labelled
`marketing-brief`: the player-facing changes that are in a build whose tests passed, a checklist (a clip for each change marked
visual, a post for each channel, Steam news once plan.json's `release` has a store page) and drafts to paste. Changes reach it
only through trailers, in the commit message or, for a squash merge, in the pull request's description:

```
Marketing: Meteor storms can now rain down on your base
Marketing-Priority: high        (high, normal or low; normal when left out)
Marketing-Visual: yes           (worth a clip)
```

- **What counts as shipped:** walking back the main line from the newest commit, the first whose kit check (`godot / Test`,
  the job named in the workflow `init` wrote) passed, or, for a merge or squash commit with no run of it, whose pull request's
  head passed. That commit and everything older shipped; newer changes are listed as waiting and come next week.
- **Weeks:** the brief covers the changes since the newest `mkt/N` tag (the first one, the last 7 days). It opens the issue,
  tags `mkt/N` at the green commit, then closes last week's brief, whose unticked tasks it carries over.
- **Coming up:** the dates of the next 4 weeks: Steam's seasonal sales, Next Fests and themed fests once the game has a store
  page (Steam's event page, read like `calendar`), and the release deadlines in plan.json not done yet (app fee, store page and
  build reviews, Coming Soon, the Next Fest demo), a missed one marked overdue for a week. Each deadline is a task, and so is
  an opt-in: a themed fest's or a seasonal sale the game can join (looked for 8 weeks ahead, since registration closes before
  the start), and a Next Fest while the game is unreleased, dated at its demo review. Tick a task and it is not asked again.
- **Quiet weeks:** nothing shipped and no date to act on within 7 days: nothing is written. A date to act on within 7 days
  opens a short "Marketing dates" brief instead, with the dates, the tasks and the changes still waiting, and no tag.
- **Mentions:** an `@name` in a commit gets a zero-width space after the `@` in the issue, so the brief notifies no one; the
  drafts keep it as written, in code blocks, ready to paste. Trailers inside HTML comments (a pull request template's hints)
  or fenced code are not read.
- **First run:** with no `mkt/N` tag the brief covers the last 7 days. Changes that are still waiting for a green build that
  week leave the window the next: tag the commit before them `mkt/0` to start there instead.
- **By hand:** a real (not dry) run by hand runs only from the default branch, and two runs never overlap.
- **Dry run:** *Actions > Marketing brief > Run workflow* is ticked as a dry run: the brief goes to the run's summary only.
- **Settings** (`docs/promo.json`): `channels` (`discord`, `bluesky`, `steam`), `hashtags`, `calendar` (the Coming up dates, on
  by default), `ai` and `model`. With
  `"ai": true` the drafts are reworded by GitHub Models (the workflow's `models: read`, no key; free and rate-limited), marked
  "check every claim"; on any error, or a Bluesky post over 300 graphemes, the brief keeps the template drafts. Off by default.
- **Clips:** set `clips: true` in the caller to record a first take of each shipped change that names its scene in a
  `Marketing-Scene: res://levels/storm.tscn` trailer (`Marketing-Args: --seed=3` for the game's flags, with no comma, `Marketing-Seconds: 8` for
  the length, 5 by default). Clips are drawn with the Compatibility renderer, what the runner's virtual display can draw. A second job sets Godot up at the commit the brief shipped, records each scene with `clip` under Xvfb
  (Movie Maker at 30 fps, an MP4 and a GIF), keeps them as the `marketing-clips` artifact for 14 days, and comments on the brief
  with the link and any scene it could not record. It adds several minutes of Actions time a week; off by default.
- **Permissions:** the caller grants `contents: write` (the tag), `issues: write`, `checks: read`, `pull-requests: read` and
  `models: read`; a reusable workflow cannot raise them itself.
