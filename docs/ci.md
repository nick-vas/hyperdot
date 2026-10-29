# The kit's own CI

What `.github/workflows/self-test.yml` runs, when, and what that costs. The workflow is the kit's own check; the
reusable workflow games call is [godot.yml](godot-pipelines.md). To see which self-test covers what, read
[coverage.md](coverage.md). A design for skipping a job whose inputs already passed (awaiting the owner's decision):
[ci-cache.md](ci-cache.md).

## What runs when

| Event | What runs |
|---|---|
| Pull request into `main` | The jobs the change needs (below). A new push to the branch cancels the run of the older commit. |
| Push to `main` (a merge) | Everything: every job, every pair of the staged programme, the steps kept for it, and the coverage floors. Each merge keeps its own run. |
| Nightly (02:23 UTC), and `workflow_dispatch` | The same as a push to `main`. The nightly run also catches what a pull request's filter let past. |
| Push to any other branch | Nothing: the pull request tests it. |

On a pull request `.github/scripts/Select-Jobs.ps1` (the `changes` job) lists the changed files against the base with plain
`git diff` and decides, with no third-party action. If the base cannot be fetched, everything runs.

| Change | Runs |
|---|---|
| Documentation only (`docs/` except `docs/json.md`, Markdown outside the skills, subagents and templates, `site/`) | `lint` alone. It holds every test that needs no Godot and the tests that read the docs. |
| The shared core: the workflow, its actions and scripts, `hyperdot.ps1`, `Common`, `Runners`, `Setup`, `Detect` and `Report`, `validate.gd`, `flows.gd`, `examples/` | Every job, except the field test (which follows the benchmark's code) and the staged programme (below). |
| A lib or tool | The jobs that exercise it: `measure` (Measure, Audio, TextSize, Layout, Deck, Palette, Playthrough, Soak, Credits, Localization and the tools they start, `docs/json.md`), `web` (Web, BuildSize, Measure, Platforms), `game-benchmark` (the libs a game's checks and doctor reach), and `init` and the reusable-workflow jobs for any change under `ci/godot/`. |
| A test, or its fixture | The jobs that run it. This is read from the workflow, so a test added to a job selects that job; a file no test names runs every job. |
| `benchmark/` outside `benchmark/games/` | `game-benchmark` and `field-test`. |
| The staged programme's own code (`benchmark/templates/`, `GameProgramme.ps1`, `game-programme.json`, `Test-GameProgramme.ps1`) | A sample of three pairs: platformer in C# (it caught a git race on release-stage games), arena in GDScript (it caught an ENet race) and cards in GDScript. |
| A game folder (`benchmark/games/<genre>/<language>/`) | That pair. |

Alongside, every run measures an *input hash* per job and records which jobs went green on which hash (the `record` job and the `cache-observations` artifact; [ci-cache.md](ci-cache.md), stage 0). It skips nothing yet.

Skipped jobs report as skipped, which satisfies a required check. The `coverage` job enforces its floors only on the full
runs; on a pull request it reports what was reached, since a skipped job's records are missing by design.
`tests/Test-SelectJobs.ps1` holds all of this, and checks that every test a skippable job runs selects that job.

### Kept for the full runs

A few steps run only when the event is not a pull request (`if: github.event_name != 'pull_request'`). Each had no failure in
the sampled runs (below), is expensive, and is redundant with a cheaper or nearer check:

| Step | Cost per run | Failures in the sample | Why it is safe to wait for main |
|---|---|---|---|
| `lint`: the stand-in Trello sync (`Test-TrelloSync.ps1`) | 196 s | 0 of 15 | Only `plan -Do sync` reaches it; `Test-Plan.ps1` still runs on every pull request. |
| `game-benchmark`: every task of the test programme (`Test-GameProgramme.ps1 -SpecPath ...`) | 106 s | 0 of 16 | The staged programme's pairs check the same thing on the real games, and `Test-GameBenchmark.ps1` runs the test programme through the runner. |
| The `field-test` job, for a change outside `benchmark/` | 1031 s | 0 of 14 | It exercises the benchmark's field-test code; a kit change that breaks it shows in `game-benchmark` and the pairs. |

## Measured

A full run before these changes (nick-vas/hyperdot#134, run 40360421024): 35 jobs, 513 runner-minutes, 84% of them in the
20 jobs of the `game-programme` matrix (C# pairs 27 minutes on average, GDScript 16). Estimated after, in runner-minutes
(the jobs' own averages from that run; the pairs' from the sampled runs):

| Change | Jobs before | Minutes before | Jobs after | Minutes after (about) |
|---|---|---|---|---|
| Documentation only (`docs/`, a README) | 35 | 513 | `changes`, `lint`, `coverage` | 14 |
| The staged programme's own code (`GameProgramme.ps1`) | 35 | 513 | those three, `game-benchmark`, `field-test`, 3 pairs | 100 |
| A game (`benchmark/games/racing/csharp/`) | 35 | 513 | those three and 1 pair | 45 |
| A kit lib (`Measure.ps1`) | 35 | 513 | `lint`, the 4 reusable-workflow jobs, `init`, `measure`, `web`, `game-benchmark`, `local-windows`, `coverage` | 65 |
| The shared core (`Common.ps1`) | 35 | 513 | as a lib, plus `field-test` only if the workflow changed | 65 |
| A push to `main`, the nightly run | 35 | 513 | all | 513 |

Before, every push to a pull request branch also started a second run (`push` and `pull_request`), which the shared
concurrency group cancelled after both had queued: in the 100 sampled runs, 47 were cancelled.

### Faster game jobs: measured, nothing shipped

A C# staged-programme task builds and tests three workspaces (the untouched game, the reference, the decoy). On this
machine (4 cores, Godot 4.7.2 mono, .NET 8.0.131), cards in C# at the prototype stage, 6 checks: 8 min 3 s with a warm NuGet
folder. One task, with a `dotnet` stand-in that logs each call:

| | Warm NuGet folder | Cold (a fresh `NUGET_PACKAGES`, 388 MB) |
|---|---|---|
| The task, three workspaces | 131 s | 146 s |
| First `dotnet build` | 4.9 s | 20.2 s |
| Later `dotnet build` / `dotnet test` per workspace | 2.8 s / 15-16 s | 2.8 s / 15-16 s |

A whole `test` on one workspace takes 57 s: the build 9 s (4.7 s of it start-up), the gdUnit4 run 27.5 s (Godot start-up
and the 55 tests), the 11 other runners about 20 s. Restore from NuGet is paid once per job (the packages folder is shared by
the job's workspaces), 15 s of a 25-minute job, so a cache saves less than restoring it costs. `DOTNET_TieredPGO=0` and
`DOTNET_CLI_TELEMETRY_OPTOUT`, `DOTNET_SKIP_FIRST_TIME_EXPERIENCE`, `DOTNET_NOLOGO` against the baseline, three runs each of
the `dotnet` runner: 31.25 s, 31.12 s and 30.72 s, which is noise. The Roslyn compiler server is already shared. What would
cut the time is running the three workspaces of a task at once, which collides on ports (the arena's ENet) and on the
runner's four cores; that is not a safe change to a test harness here, so none of this was shipped.

### Git background maintenance

Every job of `self-test.yml` and `godot.yml` runs with `GIT_CONFIG_COUNT=3` setting `gc.auto=0`, `gc.autoDetach=false` and
`maintenance.auto=false`: git 2.54 and later runs maintenance after a commit, which packs and deletes loose objects and has
raced tests that commit and then clone or copy a repository (the staged programme's game workspaces, `Test-UpdatePins.ps1`).
`actions/checkout` is unaffected.

## Which tests ever caught anything

The 100 most recent completed runs of `self-test.yml` (23-26 October 2026): 32 succeeded, 21 failed, 47 were cancelled
(82 were `push` events, 17 `pull_request`, 1 `workflow_dispatch`). Jobs and steps were read for 19 of the 21 failed runs
(two requests failed) and 3 others, so a step's "runs" below counts those 22 runs, which are mostly failing ones: the
failure rates are upper bounds, the zero counts are not. A run that failed shows its failing step; the `coverage` job's
step failed 5 times only because a job before it had.

| Failing step | Runs | Note |
|---|---|---|
| `game-programme (platformer, csharp)` | 3 | the git race on release-stage games |
| `game-programme (arena, gdscript)` | 1 | the ENet race |
| `measure`: soak | 4 | a server and clients (the logs were not read, so real or flaky is unknown) |
| `measure` / `game-benchmark`: the game benchmark's grading (`Test-GameBenchmark.ps1`) | 5 | all on 23 October |
| `game-benchmark`: isolated sessions (`Test-BenchmarkIsolation.ps1`) | 1 | |
| `local-windows`: C# example with coverage | 2 | |
| `lint`: PSScriptAnalyzer, version updates, `status` reads the GDD | 1 each | |
| `measure`: bench hotspots | 1 | |
| `action`, `csharp`, `explicit-runners`: the Godot action | 1 run, all three | looks like the network |

Steps that ran in the sample and never failed, by cost per run: the `field-test` job (1031 s, 0 of 14), the game
benchmark's test programme (106 s, 0 of 16), the stand-in Trello sync (196 s, 0 of 15), every documented error code
(191 s, 0 of 11), the plan's gates (123 s, 0 of 15), Web `export -Run` (138 s, 0 of 16), `audio -Mix` (79 s, 0 of 11),
the placement checker (66 s, 0 of 16), `-GpuValidation` (65 s, 0 of 16), Firefox under Xvfb (63 s, 0 of 16).

Three days in one burst of work is a small sample, so only three were moved to the full runs: the Trello sync and the
test programme (cheap to lose, redundant with a nearer check) and the field test for changes outside `benchmark/` (the
largest, with the least to say about a kit change). The rest stay, as the error codes, the plan's gates, the web and GPU
checks guard contracts a pull request should not break, and a quiet sample is not a reason to stop looking.

### Demoting more to the nightly run: the history, and a recommendation

The task was to move every job that never failed to the nightly run, and the first attempt had no history to decide on (a
sample of 22 runs, mostly failing ones). This section is the history. **Nothing was demoted**: no workflow file changed, and
the owner decides from the numbers below.

**Coverage.** Every run of `self-test.yml` there is: 842 runs from 5 October 2026 12:07 to 28 October 2026 22:43 UTC (23.4
days: the workflow is that young, so the 60 days the criterion asks for do not exist yet; the 100-run mark is passed by most
jobs and steps). 305 were pull request runs (on 160 branches), 169 pushes to `main`, 365 pushes to other branches (the workflow ran
on every push until 26 October, so a pull request used to have two runs), 2 nightly runs and 1 `workflow_dispatch`. Of the 842
runs 556 passed, 178 failed and 108 were cancelled; the jobs and steps of all 842 were read
(14,092 job attempts, 160 of them second attempts of 7 re-run runs; no read failed). Raw JSON came from `gh api
repos/nick-vas/hyperdot/actions/workflows/<id>/runs` and `.../actions/runs/<id>/jobs` and is not kept in the repository.

**Method.** A *run* of a job is an attempt that ended in `success` or `failure` (cancelled and skipped attempts are not
outcomes; a cancelled attempt's minutes still count). *Branch push* is the old push-to-any-branch run. A failure is *flaky*
when the same job at the same head commit and for the same event later succeeded in another run or attempt. Only 7 runs were
re-run, so this finds few, and a failure nobody re-ran is "real" here only in the sense that it was not shown to be flaky; the
logs were not read. A failure is *only after merge* when the job failed on the push to `main`, was not flaky, and the last run
of that job on the pull request of that merge (found with the commit's pull request) had passed, or the job had not run on the
pull request. The pull request's head is not the merge commit, so this is the closest the history allows. Minutes are a job's
wall-clock duration (start to end of the job, not rounded up to the minute and not weighted: the Windows job bills at a higher
rate), summed over all attempts including cancelled ones. Median is of the successful runs.

**What the 23 days cost.** 49,839 runner-minutes (831 hours): 23,290 (47%) on `main`, 14,174 (28%) on pull requests, 11,269
(23%) on branch pushes (the old double run), 1,106 (2%) in the nightly and manual runs. The 20 jobs of the `game-programme`
matrix alone took 47% of all of it (23,412 minutes), and `measure` 11%.

| Job | Runs | Failed | PR runs / failed | `main` runs / failed | Branch push runs / failed | Flaky | After merge only (sequences) | Median min | Total min | Share | PR min |
|---|---|---|---|---|---|---|---|---|---|---|---|
| `game-programme` (20 pairs) | 1043 | 9 (0.9%) | 192 / 4 | 735 / 2 | 74 / 2 | 1 | 2 (2) | 22.0 | 23412 | 47.0% | 4453 |
| `measure` | 688 | 63 (9.2%) | 253 / 15 | 162 / 12 | 270 / 35 | 2 | 11 (7) | 6.8 | 5485 | 11.0% | 1955 |
| `lint` | 768 | 55 (7.2%) | 292 / 22 | 168 / 11 | 305 / 22 | 0 | 0 | 2.2 | 3427 | 6.9% | 1327 |
| `local-windows` | 734 | 93 (12.7%) | 269 / 34 | 167 / 25 | 295 / 34 | 1 | 1 (1) | 4.4 | 3404 | 6.8% | 1239 |
| `web` | 500 | 13 (2.6%) | 182 / 6 | 138 / 4 | 177 / 3 | 0 | 3 (2) | 4.2 | 2691 | 5.4% | 953 |
| `field-test` | 100 | 0 | 40 / 0 | 40 / 0 | 18 / 0 | 0 | 0 | 18.7 | 1954 | 3.9% | 773 |
| `csharp / Export` | 731 | 8 (1.1%) | 269 / 1 | 165 / 0 | 294 / 7 | 0 | 0 | 2.4 | 1829 | 3.7% | 682 |
| `init` | 731 | 34 (4.7%) | 267 / 13 | 166 / 7 | 295 / 14 | 0 | 0 | 1.3 | 1682 | 3.4% | 602 |
| `csharp / Test` | 749 | 8 (1.1%) | 273 / 2 | 167 / 1 | 306 / 5 | 1 | 0 | 2.1 | 1676 | 3.4% | 609 |
| `explicit-runners / Test` | 752 | 3 (0.4%) | 273 / 0 | 168 / 0 | 308 / 3 | 0 | 0 | 1.5 | 1259 | 2.5% | 450 |
| `game-benchmark` | 125 | 4 (3.2%) | 49 / 0 | 41 / 0 | 32 / 4 | 0 | 0 | 9.3 | 1215 | 2.4% | 454 |
| `action` | 757 | 4 (0.5%) | 270 / 0 | 168 / 0 | 316 / 4 | 0 | 0 | 0.8 | 810 | 1.6% | 293 |
| `zero-config / Test` | 768 | 0 | 275 / 0 | 168 / 0 | 322 / 0 | 0 | 0 | 0.6 | 564 | 1.1% | 208 |
| `csharp / Release` | 707 | 2 (0.3%) | 262 / 1 | 164 / 0 | 278 / 1 | 0 | 0 | 0.3 | 218 | 0.4% | 83 |
| `coverage` | 180 | 37 (20.6%) | 68 / 2 | 43 / 3 | 66 / 31 | 1 | 3 (2) | 0.3 | 57 | 0.1% | 23 |
| `changes` | 96 | 0 | 56 / 0 | 38 / 0 | - | 0 | 0 | 0.2 | 25 | 0.1% | 16 |
| `macos / Test` | 27 | 4 (14.8%) | 9 / 0 | 4 / 0 | 14 / 4 | 0 | 0 | 1.2 | 30 | 0.1% | 12 |
| `ci / Test`, `ci / Export`, `ci / Build`, `build-only`, `smoke-only`, `cli`, `record`, `programme-pairs` | 188 | 3 | 76 / 0 | 38 / 0 | 73 / 3 | 0 | 0 | 0.2 to 1.4 | 103 | 0.2% | 41 |

"Runs" adds the nightly and manual runs, which the columns leave out (3 runs, one of them red: `measure`, one racing pair and
`coverage` on 27 October, the same failures `main` had). `zero-config` and `explicit-runners` have `Export` and `Release` jobs that are skipped by design (0 runs), so they are not
listed. `game-programme` is one row for its 20 pairs (22 minutes median, 15 to 36 by pair).

**How the failures read.**

- *One burst makes the failure column look worse than it is.* 175 of the 340 failed job attempts are on 22 October, when 57
  pull requests were merged between 05:13 and 09:10. Three steps account for 134 of them (`local-windows` "Filtered run" 76,
  `lint` "A failed Godot download stops with download-failed" 35, `init` "bare-game" 23): they failed on the pull requests too
  (44 of the 65 failed job runs on `main` had failed on their pull request too), so a pull request run did show them. They say
  that merging on red was possible, not that a pull request run missed something.
- *Of the 65 failed job runs on `main`*, 44 had failed on their pull request too, 1 was flaky (`csharp / Test`), and **20 failed
  only after merge**: 18 had passed on the pull request, 2 (the racing pair on 27 October, `web` on 27 October) had not run
  there. They come in 14 sequences. By job: `measure` 11 (the capture-mode step, 10 times in 22 October's burst, and soak
  once), `coverage` 3 (its floors are enforced only on full runs, by design), `web` 3 (Firefox under Xvfb once; the
  Playwright system packages twice), `game-programme` 2 (the racing pair in C#, in `main` on 26 and 27 October and in the
  nightly run), `local-windows` 1 (the C# example with coverage). The capture-mode step is intermittent: it failed 30 of 404
  times (6 of 154 on pull requests, 11 of 114 on `main`) and passed in between, so it is flaky rather than missed.
- *Pull request runs did catch things.* Failures on pull request runs (flaky ones included): `lint` 22, `local-windows` 34, `init` 13,
  `measure` 15 (2 of them flaky), `web` 6, `game-programme` 4 (1 flaky), `csharp / Test` 2, `csharp / Export` 1, `csharp / Release`
  1, `coverage` 2. Only `field-test`, `zero-config / Test`, `changes`, `explicit-runners / Test`, `action` and `game-benchmark` have none (0 of
  40, 275, 56, 273, 270 and 49 pull request runs).
- *Since the selection (26 October 19:55) a pull request runs what its change can affect.* Of the 54 pull request runs since,
  `measure` was skipped in 21, `init` in 20, `action` in 20, `local-windows` in 19, `game-benchmark` in 13, and 24 pair
  jobs of `game-programme` (the sample). Job failures on those runs: 8 (`lint` 3, `measure` 3, `coverage` 1,
  `game-programme` 1). That is the history that shows what the selection costs, and it is too short to say much.

**Where the time goes inside the slow jobs** (steps, all runs of the 23 days; "PR / main" are runs on those events):

| Job, step | Runs | Failed | PR failed / `main` failed | Median | Minutes |
|---|---|---|---|---|---|
| `local-windows`: C# example with coverage | 734 | 8 | 3 / 1 | 148 s | 1743 |
| `field-test`: the field test | 100 | 0 | 0 / 0 | 1106 s | 1776 |
| `measure`: soak | 585 | 8 | 3 / 1 | 89 s | 1124 |
| `web`: `export -Run` | 494 | 4 | 2 / 0 | 127 s | 1086 |
| `measure`: bench, headless and with a window | 688 | 10 | 2 / 0 | 59 s | 694 |
| `local-windows`: Windows export and launch | 638 | 0 | 0 / 0 | 60 s | 664 |
| `measure`: `audio -Mix` | 465 | 2 | 1 / 0 | 50 s | 618 |
| `web`: Playwright's browsers | 494 | 0 | 0 / 0 | 29 s | 584 |
| `web`: Firefox under Xvfb | 488 | 1 | 0 / 1 | 66 s | 516 |
| `measure`: every documented error code | 115 | 0 | 0 / 0 | 193 s | 355 |
| `lint`: PSScriptAnalyzer | 749 | 11 | 5 / 0 | 25 s | 345 |
| `measure`: `shot` | 677 | 0 | 0 / 0 | 29 s | 333 |
| `measure`: capture mode | 404 | 30 | 6 / 11 | 36 s | 235 |
| `game-benchmark`: isolated sessions | 113 | 3 | 0 / 0 | 96 s | 171 |

**Steps that never failed.** Steps with at least 100 runs, no failure in any of them and a median of 20 s or more, by what
they cost on pull requests (the 15 steps cost 2,033 of the 14,174 pull request minutes, 14%; the stand-in Trello sync and the
test programme are already full-run steps, and their pull request minutes come from before that):

| Job, step | Runs | PR / `main` runs | Median | PR min | All min |
|---|---|---|---|---|---|
| `field-test`: the whole job | 100 | 40 / 40 | 1106 s | 716 | 1776 |
| `local-windows`: Windows export and launch | 638 | 234 / 141 | 60 s | 242 | 664 |
| `web`: Playwright's Chromium and Firefox (the install) | 494 | 179 / 135 | 29 s | 210 | 584 |
| `lint`: the plan's vertical-slice gates | 249 | 105 / 67 | 78 s | 128 | 286 |
| `measure`: every documented error code | 115 | 39 / 40 | 193 s | 125 | 355 |
| `measure`: `shot` | 677 | 251 / 162 | 29 s | 125 | 333 |
| `lint`: the token benchmark's counting (stand-in CLI) | 553 | 222 / 130 | 20 s | 113 | 259 |
| `init`: `test -Retry` and `quarantine.json` | 318 | 122 / 82 | 47 s | 101 | 265 |
| `init`: the placement checker | 427 | 160 / 114 | 29 s | 99 | 260 |
| `measure`: audio files and buses; `-Mix` | 104 | 39 / 40 | 85 s | 50 | 136 |
| `lint`: stand-in Trello sync (already a full-run step) | 126 | 23 / 45 | 148 s | 40 | 283 |
| `measure`: `bench -Sweep` | 108 | 43 / 41 | 38 s | 27 | 68 |
| `measure`: the palette check | 104 | 39 / 40 | 35 s | 21 | 58 |
| `measure`: `deck` | 107 | 42 / 41 | 30 s | 20 | 51 |
| `init`: `test` refuses a `-Results` folder inside the project | 136 | 45 / 42 | 21 s | 15 | 46 |

None of the 20 failures that appeared only after merge came from one of these steps.

**Recommendation.** The criterion is zero failures in about 100 runs that included the job's files. What the history can
show is zero failures in at least 100 runs of the step, whatever the change. It cannot show that a run "included its files",
because that needs each run's changed files, which this collection did not read; before 26 October a pull request ran every
job whatever it changed, so most of those runs were not about the step's files, and zero in 100 of them is weaker evidence
than zero in 100 relevant ones. With that said:

*May move to the full runs (pull request minutes saved of 14,174):*

1. **`field-test`** (716 min, 5% of pull request minutes): 0 failures in 100 runs (40 on pull requests, 40 on `main`, 18 on
   branches), 18.7 minutes median, the largest step outside the pairs; pull requests already run it only for changes under
   `benchmark/`. `game-benchmark` (0 failures in 49 pull request runs, 4 on branch pushes) still runs on those pull requests,
   and a kit change that breaks the field test shows there and in the pairs.
2. **`measure`: every documented error code** (125 min): 0 failures in 115 runs, 193 s a run. It raises the codes no other self-test raises, and
   the earlier text kept it on purpose as a contract check; the history gives no case where it fired.
3. **`lint`: the plan's gates** (128 min) and **`init`: `test -Retry`** (101 min) and **the placement checker** (99 min):
   0 failures in 249, 318 and 427 runs. The plan's gates and the retry check guard what a plan or a flaky test does to a game,
   which the earlier text also kept on purpose: the case for them is the numbers alone.
4. **`measure`: `shot`, `audio` (files, buses, `-Mix`), `bench -Sweep`, the palette check and `deck`** (about 243 min together):
   0 failures in 104 to 677 runs each. They need a display, which is what makes `measure` slow (6.8 minutes median).
5. **`local-windows`: Windows export and launch** (242 min): 0 in 638 runs; `Windows` is the one job that runs the script as a
   developer runs it, so keep the GDScript example and the C# example with coverage (8 failures, 3 on pull requests) and move
   only the export.

Moving all of 1 to 5 would take about 1,650 of the 14,174 pull request minutes (12%) off the pull request and leave them on
`main` and the nightly run.

*Must stay on pull requests:*

- **`lint`** (22 failures on pull requests, none flaky, none found only after merge; 2.2 minutes median): the cheapest job
  and the one that catches the most.
- **`init`** (13 on pull requests, 0 after merge), **`local-windows`** (34 on pull requests, 1 after merge), **`csharp`**,
  **`explicit-runners`** and **`action`** (the reusable workflow games call: 1 to 3 failures each, each in 2 minutes or less;
  these are the product), and **`coverage`** (floors are enforced only on full runs; it costs 0.3 minutes).
- **`measure`** minus the steps above (11 failures found only after merge, 15 on pull requests; soak, bench and capture mode
  are intermittent: 8 of 585, 10 of 688 and 30 of 404 runs failed). Moving more of it would make soak and capture mode fail
  for the first time on `main`, as they already did.
- **`web`** (`export -Run`: 4 failures in 494; Firefox, GPU validation and the Playwright system packages fail now and then:
  6 on the packages step, 2 of them only after merge) and **`game-benchmark`** (the grading, 1 failure in 125;
  isolated sessions, 3 on branch pushes).
- **`game-programme`** already runs a sample of 3 pairs on a pull request (192 pair runs on pull requests against 735 on
  `main`, 47% of all minutes and 4,453 pull request minutes, mostly before the selection). Its failures: 4 on pull requests (1
  flaky), 2 on `main`, 2 after merge. Nothing here argues for dropping the sample.
- **`changes`, `record`, `programme-pairs`** (plumbing; 0.1% of minutes). `zero-config / Test` (0 in 768 runs, 0.6 minutes,
  1.1% of minutes) meets the criterion but saves almost nothing, and it is the same action as the three jobs beside it:
  leave it.

Before moving anything, `Test-SelectJobs.ps1` needs the demotion added to its expectations. Re-collect when the history reaches 60 days (about 4 December 2026): the
window is short, a burst of one day carries half the failures, and the logs of the 20 after-merge failures were not read.

### Changelog fragments

`CHANGELOG.md` is edited only at release. Each change adds `changelog.d/<slug>.md` (format: `changelog.d/README.md`) and
`ci/godot/tools/Update-Changelog.ps1` assembles them; `tests/Test-Changelog.ps1` runs in `lint`, and a change to the fragments
is Markdown, so it runs `lint` alone. The repository has no rule that a pull request must change the changelog, so CI does
not require a fragment.

## Releasing

`.github/workflows/release.yml` ("Release") tags and publishes a release. Tags cannot be pushed from the cloud session (its
git proxy answers 403 for tag pushes), so a workflow makes them. Run it from Actions > Release > Run workflow, or
`gh workflow run release.yml -f version=0.1.0 [-f sha=<commit>]`:

| Input | |
|---|---|
| `version` | Required, `x.y.z` without the `v`. |
| `sha` | Optional; the head of the branch the run is dispatched on when empty. |

It stops before changing anything unless: the commit is reachable from `origin/main` and has a successful `Self-test` run for
a push to `main` (read with `gh api`; this needs read access to workflow runs, the default for a public repository, and on a
private one the check fails closed until `actions: read` is added to the workflow's permissions); `CHANGELOG.md` has a
`## <version> - ` section (`.github/scripts/Get-ChangelogSection.ps1`, held by `tests/Test-ReleaseNotes.ps1`); and
`.claude-plugin/plugin.json` has the same version. Then it creates the annotated tag `v<version>` (it fails if that tag
exists at another commit: version tags are never moved; at this commit it is left alone, so a run can be repeated), creates or force-moves the moving tag (the one tag that moves, as games pin
`@v1`; `.github/scripts/Test-MajorTagMove.ps1` leaves it where it is, with a notice, when a tag of a greater version of the same major exists, so releasing 1.2.1 after 1.3.0 does not move `v1` backwards; the repeated run of the version already tagged still moves it): `v<major>` by default, or the `major_tag` input, which a 0.x release sets to `v1`; it pushes both as `github-actions[bot]`, and runs `gh release create v<version> --verify-tag` with the changelog section
as the notes (cut near 120000 characters, the limit of a release body, with a link to the changelog). Tags pushed with the
workflow's token start no other workflow. A change to `release.yml` or its scripts (`Get-ChangelogSection.ps1`, `Test-MajorTagMove.ps1`) runs `lint` alone. The version and the major tag are matched whole (`\A[0-9]+\.[0-9]+\.[0-9]+\z`): `$` accepts a trailing newline and `\d` Unicode digits in .NET.

`tests/Test-WorkflowLint.ps1` (in `lint`) reads the workflows as text for what cannot run here: a pull request's concurrency group is `pr-<number>` (the branch name alone made pull requests of two forks cancel each other), `release: true` with no `exports` fails the `test` job of `godot.yml` instead of ending green without a release, and `canary.yml` runs the upstream code (the `try` job) with read permission, no token and no stored credentials, while `propose`, which has the write permissions, applies the patch it made and runs none of that code. Every action from another repository is pinned to a commit SHA with its version in a comment (`actions/checkout@<sha> # v7`), the Claude Code CLI and `uv` are installed at a version, and `.github/dependabot.yml` proposes the weekly bumps of the actions; the lint fails on a tag.

## Running everything locally

```
pwsh tests/Test-SelectJobs.ps1                                   # what a change would run (no Godot)
pwsh .github/scripts/Select-Jobs.ps1 -EventName pull_request -Base <sha> -Json   # for the current checkout
for t in tests/Test-*.ps1; do pwsh $t; done                      # every self-test (several need Godot, a display or ffmpeg: see AGENTS.md)
```

`AGENTS.md` has the table of what each self-test needs. `gh workflow run self-test.yml` starts the full run.
