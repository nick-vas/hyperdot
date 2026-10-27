# The kit's own CI

What `.github/workflows/self-test.yml` runs, when, and what that costs. The workflow is the kit's own check; the
reusable workflow games call is [godot.yml](godot-pipelines.md). To see which self-test covers what, read
[coverage.md](coverage.md).

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

### Demoting more to the nightly run: not done, and what is missing

The task was to move every job that never failed to the nightly run. The numbers above do not show that safely, so
nothing more was demoted. The sample is 22 runs read step by step, mostly failing ones, over three days of one burst of
work, and a zero count there is "no failure seen", not "cannot fail". The steps and jobs that never failed (error codes, the
plan's gates, Web `export -Run`, `audio -Mix`, the placement checker, `-GpuValidation`, Firefox) were weighed above and kept
on purpose, as they guard contracts a pull request should not break; the three that were redundant with a nearer check
are already kept for the full runs. To demote more, the decision needs, from the run history of `self-test.yml`
(`gh run list` and `gh run view --json jobs`, which this change could not reach): per job and step over at least the last
60 days, the count of runs it was in and of failures (split by pull request and `main`), how many failures were found
only after merge, and the runner-minutes it cost. A job qualifies at zero failures in about 100 runs that included its
files; `Test-SelectJobs.ps1` then needs the demotion added to its expectations. This is listed in the roadmap's To do.

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
`@v1`): `v<major>` by default, or the `major_tag` input, which a 0.x release sets to `v1`; it pushes both as `github-actions[bot]`, and runs `gh release create v<version> --verify-tag` with the changelog section
as the notes (cut near 120000 characters, the limit of a release body, with a link to the changelog). Tags pushed with the
workflow's token start no other workflow. A change to `release.yml` or the script runs `lint` alone.

## Running everything locally

```
pwsh tests/Test-SelectJobs.ps1                                   # what a change would run (no Godot)
pwsh .github/scripts/Select-Jobs.ps1 -EventName pull_request -Base <sha> -Json   # for the current checkout
for t in tests/Test-*.ps1; do pwsh $t; done                      # every self-test (several need Godot, a display or ffmpeg: see AGENTS.md)
```

`AGENTS.md` has the table of what each self-test needs. `gh workflow run self-test.yml` starts the full run.
