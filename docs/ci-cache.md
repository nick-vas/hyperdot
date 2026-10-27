# A cache keyed by the inputs, for the kit's CI: a design

Status: **stage 0 is built (owner's decision of 2026-10-27); nothing is skipped.** The rest is a design awaiting the owner's decisions
(section 7). What stage 0 is: [Stage 0, as built](#stage-0-as-built), at the end.
It answers the roadmap entry "A cache keyed by a hash of the inputs, for CI" ([roadmap.md](roadmap.md), "After 0.1.0"),
which asked first for a note on which jobs are deterministic. Every number below is quoted from [ci.md](ci.md), the
workflows or the tests, with the file named; where the repository has no number, the page says so.

The idea: hash exactly what a `self-test.yml` job reads, plus the versions it runs on; if a job with the same hash already
passed, show it as skipped and say which run proved it.

## 1. What it solves that `Select-Jobs.ps1` does not

`.github/scripts/Select-Jobs.ps1` answers "which jobs does this change touch?" from the files that differ between the pull
request and its base ([ci.md](ci.md), "What runs when"). It has no memory: it does not know that a job already passed on
the same inputs. Four cases it cannot see:

| Case | Why Select-Jobs runs the job again |
|---|---|
| **Run all jobs again** (or `workflow_dispatch`) on a commit that passed | The diff against the base is the same as the first time, so the same jobs are selected. ("Re-run failed jobs" already keeps the green jobs of the run; only "re-run all" and a new dispatch repeat them.) |
| **A new push to a pull request that leaves a job's inputs unchanged** (the new commit touches only docs, or reverts a file) | The selection is against the *base*, not against the previous commit, so every job the whole branch ever touched runs again. A new push cancels the older run (`cancel-in-progress` in `self-test.yml`), so a job that was green in the cancelled run is thrown away. |
| **A merge to `main` of an already-tested branch** | `main` runs everything by design: "Push to `main` (a merge): Everything" ([ci.md](ci.md)). |
| **A squash merge whose tree equals the pull request's merge-ref tree** | Same as above: a new commit id, an identical tree. |

How much that could save, from what the repository records:

- A full run is 35 jobs and 513 runner-minutes, 84% of them (about 431) in the 20 jobs of the `game-programme` matrix
  (C# pairs 27 minutes on average, GDScript 16) ([ci.md](ci.md), "Measured"). A pull request costs about 14 minutes
  (documentation only) to 100 (the staged programme's own code) after `Select-Jobs`, estimated in the same table.
- So on a **pull request** the ceiling for a repeated job is small in absolute terms (14 to 100 minutes), and the largest
  single prizes are the `field-test` job (1031 s, about 17 minutes, `ci.md`) and the pairs (16 to 27 minutes each).
- On **`main` and the nightly run** the bill is 513 minutes per run. That is where the money is, and it is exactly where this
  design, as asked ("main always runs everything as now"), saves nothing. Letting `main` reuse a green result is a
  separate, bigger decision (section 6, stage 3, and the questions at the end).

What the repository does **not** record, so the real saving is unknown:

- how many runs were repeats of a commit already green ("run all again" shows as `run_attempt` above 1; `ci.md`'s sample of
  100 runs lists events only: 82 `push`, 17 `pull_request`, 1 `workflow_dispatch`, and 47 cancelled);
- for the 47 cancelled runs, which jobs had already finished green before the cancel;
- how often two successive commits of one pull request have the same inputs for a job.

[ci.md](ci.md) says the same of its history ("`gh run list` and `gh run view --json jobs`, which this change could not
reach"). Stage 0 below exists to fill these three gaps before anything is skipped.

## 2. The key

For a job J on a commit C:

```text
key(J, C) = sha256 of
    1. the git object ids of J's input files at C        (git ls-tree -r C, filtered to J's file set)
    2. the workflow definition: self-test.yml, godot.yml, .github/actions/**, .github/scripts/**
    3. the tools: Godot version, kit version, PowerShell version, runner image
    4. the job id and the event kind where it changes behaviour (pull_request or not)
```

**Git object ids as the content hash.** `git ls-tree -r <commit> -- <paths>` prints one blob id per file; hashing that
listing (sorted) is a hash of the files' content and modes, costs milliseconds on a shallow checkout, and needs no file
reads. A tree id of one directory would do for a job that reads a whole folder (`git rev-parse C:benchmark/games/arena/gdscript`),
but a job's set is rarely one folder, so the listing is the general form. Git LFS files are pointers in the tree, which is
the content id LFS itself uses.

**The tools.** The kit pins Godot 4.7.2 mono, .NET 8, PowerShell 7.6+, gdUnit4, GUT and coverlet in files that are part of
the tree (`AGENTS.md` "Targets", `Update-Versions.ps1`), so a version change is already a change of input files. What
is *not* in the tree is the runner: the `apt` action already keys on `$env:ImageOS` and `$env:ImageVersion`
(`.github/actions/apt/action.yml`), `RUNNER_OS` and `RUNNER_ARCH` are in the Godot cache keys, and `pwsh --version`
can be read in the step. These go into the key, so a new runner image is a miss. `ubuntu-latest` and `windows-latest`
are labels that move; the version is what is recorded.

**The workflow's own definition.** `Select-Jobs.ps1` already treats the workflow, its actions and its scripts as the
"shared core" that runs every job (`$core`). The key does the same: any change to those files changes every key. A
narrower rule (hash only the job's own block of `self-test.yml`) is possible, because `Select-Jobs` already cuts the
file into job blocks, but it adds a way to be wrong for little gain; start with the whole file.

### How a job's file set is found

Two ways, and the page recommends deciding between them only after stage 0:

**A. Derived from `Select-Jobs.ps1` (no second list).** A file is an input of job J exactly when `Select-Jobs.ps1`, given
that file as the only change, selects J. The script already holds the three sources of that rule: the pattern table
(`$patterns`, `$core`), the tests each job runs (read from the workflow by `Get-TestJobs`) and the "a file no test names
runs every job" fallback. The key function would run that predicate over `git ls-files`. Advantages: the set cannot drift
from the selection, and a missing path is a bug that exists today in `Select-Jobs` (`tests/Test-SelectJobs.ps1` already
holds it), not a new class of risk. Cost: the script's decision has to be callable as a function, which is a change to the
script (not made here). Limit: the set is a selection rule, tuned to be *safe to over-select*, so for most jobs it
is large (a lib change selects `init` and the reusable jobs; `.github/` selects everything). The hit rate is bounded by
how coarse `Select-Jobs` is.

**B. A declared list per job in one data file** (proposed: `ci/godot/job-inputs.json`, glob lists keyed by job id).
More precise, and readable by a person. It needs a test that fails when a job reads a file outside its list. Options,
cheapest first:

1. *Consistency with `Select-Jobs`:* the list for J must contain every path pattern that selects J. A self-test
   (`Test-JobInputs.ps1`, proposed) runs the selection over every tracked file and fails if a file selects J but J's list
   does not match it. This catches the common error (a new test added to a job) because the selection already reads
   the workflow.
2. *Tracing, run in the nightly build only:* wrap one job's Godot and PowerShell runs in `strace -f -e trace=openat,execve`
   (or `fatrace`), collect the paths opened under the workspace, and fail if one is outside the list. Cost is real
   (the staged programme runs Godot "hundreds of times", `self-test.yml`), unmeasured, and it can only prove a job
   *did* read a file, not that it never would. Use it as an audit, not as the definition.
3. *Convention:* a job reads only its own folders plus the shared core, written down in `AGENTS.md`. Cheap, unverified.

Neither way is built. A is the smaller change; B is the more precise one. Both need the consistency test.

### What a tree hash of the selected paths gives

Two commits with different ids but the same hash for J are indistinguishable to J. That is the point: a docs-only commit
leaves `measure`'s hash unchanged (`docs/json.md` aside, which `measure` does read for the error-code test). It also
makes the hash a precise statement of what was tested, which a commit id is not.

### The squash-merge case

A squash merge creates a new commit on `main` whose tree is the merge of the pull request into `main`. The pull request's
`pull_request` run checked out GitHub's merge commit (`refs/pull/N/merge`), whose tree is also the merge of the pull request
into `main`. If `main` has not moved since that merge commit was made, the two trees are equal, so every job's hash is
equal and every PR-green result is valid for the merge commit. If `main` moved, the trees differ in exactly the files the
other merge changed, and J's hash differs only if one of those is in J's set.

This case only pays if `main` is allowed to skip, and it exposes a storage problem (next section): a result saved by a
pull request run cannot be read by a run on `main` with the Actions cache.

## 3. Where results live

| Store | Written by | Read by | For | Against |
|---|---|---|---|---|
| **Actions cache entry**, key `job-<id>-<hash>`, a one-line marker file | a step after a green job (`actions/cache/save`, as `.github/actions/godot/action.yml` already saves Godot, templates, import, LFS and Gradle) | `actions/cache/restore` with `lookup-only: true` | Re-runs and later pushes of one pull request; a pull request reading what `main` saved | GitHub scopes caches by ref. A run can read its own ref's caches and the default branch's, not a sibling branch's. A run on `main` therefore cannot read a pull request's marker, so **the squash-merge case does not work** with it. Entries are immutable and are evicted (7 days unused, a size cap per repository: GitHub's rules, to confirm in stage 0) |
| **Check run or commit status** on the tested commit | the `record` job, with `checks: write` | the key step, by `gh api` on the commit | Readable from any ref; shows in the PR UI | Keyed by commit id, so a squash commit has none unless the marker is copied; needs a write permission the workflow does not have today (`permissions: contents: read`) |
| **A small JSON on a results branch** (or a release asset) | the `record` job | a `git fetch` | Readable everywhere; a tree-hash index is exactly the right shape | Needs `contents: write` and a push from CI, races between concurrent runs, and the cloud session's git proxy refuses some pushes; pollutes the repository |

Recommendation: the Actions cache marker for stages 0 and 1 (pull-request re-runs, the repository's existing pattern, no
new permission), and a decision about a second store only if the owner wants `main` to skip (stage 3).

**Reading a hit.** A step in the existing `changes` job, after `Select-Jobs.ps1`: one script (proposed
`.github/scripts/Get-InputHash.ps1`, not `ci/godot/lib`, because it is CI-only and not part of what games run) prints
`<job>=<hash>`; one `actions/cache/restore` with `lookup-only` per gated job (ten steps; the key is dynamic, so a matrix
does not help); then `<job>-hit=true|false` outputs. Each job's `if:` becomes
`needs.changes.outputs.<job> == 'true' && needs.changes.outputs.<job>-hit != 'true'`. The reusable-workflow jobs
(`zero-config`, `csharp`, `explicit-runners`) need no edit inside `godot.yml`: the marker is saved by a final `record`
job (`needs:` all, `if: always()`, saving a marker for each job whose `needs.<job>.result == 'success'`), the way the
`coverage` job already collects from all of them.

**Reporting.** A skipped-by-cache job shows as skipped, which satisfies a required check, as skipped-by-selection already
does. The `changes` job writes a table to `$GITHUB_STEP_SUMMARY`: job, hash (first 12 characters), hit or miss, the run id
that proved it, and the minutes that run took. A skipped job with no explanation would be indistinguishable from a
broken `if:`.

**Telemetry.** The `telemetry` command ([roadmap.md](roadmap.md)) exists in a pending pull request and reads
`.godot/hyperdot-history.jsonl`, a per-game file. CI hit rates are a CI fact, not a game's, so the `record` job should
upload a small `cache-observations` artifact (one JSON line per job per run: job, hash, hit, event, `run_attempt`,
minutes), the same way jobs upload `coverage-*` today (`retention-days: 14`). `telemetry` would read that and add the hit
rate as a field, as the roadmap says it will; this page does not design that field.

## 4. Which jobs may be skipped

Read from `self-test.yml` and `godot.yml` as they are. "Deterministic" means: the same inputs give the same verdict, so a
green result for the same hash is a green result for this one.

| Job | Verdict | Why (from the job) |
|---|---|---|
| `changes` | never | It computes the selection and the keys; it must run to decide anything. About one minute. |
| `lint` | **yes** | About 60 steps: pinned PSScriptAnalyzer 1.25.0 and actionlint 1.7.12, text and fixture self-tests, no Godot. Its inputs are most of the tree (it reads docs, tests, every `.ps1`), so its hit needs an exact tree match. The stand-in Trello sync is `main`-only already. Its network steps (`Test-DownloadFailed`, 15 s) assert a failure, not a download. |
| `zero-config` | **yes** | Calls `godot.yml` on the shallowest example; Godot download is pinned by version; gdscript + GUT. Skipping loses nothing but the PR comment from this run (the previous one stays). |
| `csharp` | **yes, with a note** | Same, plus exports, a Windows launch on a Windows runner, coverage minimum 40, a release dry run. Deterministic; it posts the pull request comment, which stays from the earlier green run. Its coverage figure is a measurement but gated by a minimum, not a timing. |
| `explicit-runners` | **yes** | The same workflow with `runners: gdunit4,gut`; no comment. |
| `action` | **yes** | The composite action with `command: build`, nothing timed. |
| `init` | **yes** | Fixtures and generated files; the listed tests (`Test-SkillShaders`, `Test-Placement`, `Test-ReportPins`, `Test-Flaky`, `Test-Localization`, `Test-ErrorKeys`, `Test-ResultsDir`) have fixed expectations. `Test-Flaky` tests the *retry* of a fixture, which is deterministic by design. |
| `measure` | **measuring, never** | `bench` (headless and windowed, a frame budget, `bench-over-budget`), `Test-BenchHotspots`, `Test-BenchSweep`, `Test-Deck`, `soak` (`Test-Soak`: a leak check on memory growth, whose C# server "has failed there twice", [roadmap.md](roadmap.md)), `shot` compares (`changedPercent`), `Test-ShotChanged`. The job's own comment says the software-GL "numbers only prove the commands work, not how fast anything is", but the steps still assert against limits and timings, and four `soak` failures in the sample have "real or flaky unknown" ([ci.md](ci.md)). Could be split later into a deterministic half (`Test-ErrorCodes`, `Test-Credits`, `Test-StaleTres`, ...) and a measuring half; not proposed now. |
| `game-benchmark` | **yes, later** | A stand-in for the model, a copy of the game per session, grading by tests, hidden tests and mutants; `Test-BenchmarkIsolation` needs passwordless `sudo` for a separate user. No model call and no download after Godot. But 5 of the sampled failures were its grading on one day (23 October), which is an unfinished test, not luck: wait until it is quiet. |
| `game-programme` (20 pairs) | **yes per pair, with a flake caveat** | 84% of a full run, so the biggest prize. Deterministic by design (reference passes, decoy fails), but it has failed for races: `platformer/csharp` three times (the git race, fixed in #134) and `arena/gdscript` once (an ENet port race); the roadmap lists "the arena soak race must be fixed". A race means a green can be luck. Start with the pairs that have no failure in the record, keep `arena` out until its race is fixed, and key each pair on its game folder, the harness (`benchmark/templates/`, `GameProgramme.ps1`, `game-programme.json`) and the core. |
| `field-test` | **yes** | A stand-in for the model, a mutant planter, runs on copies of both examples. 0 of 14 failures; 1031 s, already `main`-only for changes outside `benchmark/` ([ci.md](ci.md)). |
| `web` | **yes, later** | Real browsers (Playwright 1.56.1 pinned, Edge from the image, Firefox under Xvfb), `export -Run`, `-GpuValidation` with Mesa's lavapipe. Results depend on apt packages (`mesa-vulkan-drivers`, `vulkan-validationlayers`) that are not pinned, so the runner image version in the key matters most here. 0 of 16 failures for Web `export -Run`. |
| `local-windows` | **yes, later** | `Test-ProcessTimeout` and `Test-CrashRetry` are about time limits and crashes; the process-timeout test is a timing test whose pass is only ever a *lack* of a false positive. The C# example with coverage failed twice in the sample. Needs the Windows image version in the key. |
| `coverage` | **never** | It adds up every job's records and, on `main`, nightly and dispatch, enforces floors (`WHOLE_SUITE`); skipped jobs have no records. It is cheap (10-minute timeout), `if: always()`. |

Other workflows:

| Workflow | Verdict | Why |
|---|---|---|
| `canary.yml` (Fridays) | never | Its job is to download the *latest* Godot, test packages and add-ons and see what breaks; a hit is the opposite of its purpose. It also opens pull requests and issues. |
| The nightly `Self-test` | never | The nightly run "catches what a pull request's filter let past" (`self-test.yml`); it is the periodic full run in section 5. |
| `evals.yml` | **opt-in only** | Calls a model (`CLAUDE_CODE_OAUTH_TOKEN`), manual only, installs the unpinned `@anthropic-ai/claude-code`. A hit would *save money* (a result for identical case files and the same plugin), but model output is a sample, not a function of the inputs, and the point of a repeat is a new sample. Reuse only if the owner asks for it per run. |
| `token-benchmark.yml` | **opt-in only** | The same. Each real run costs money (`AGENTS.md`); a repeated run is a measurement of variance. A cache would need a `reuse` input, off by default. |
| `release.yml`, `pages.yml`, `trello-sync.yml` | never | Side effects (tags, a published site, a board), not tests. |
| `godot.yml` as games call it | out of scope | A game's own CI; the same idea could be offered there later. |

## 5. Risks and their mitigations

| Risk | Detail | Mitigation |
|---|---|---|
| **A false skip**: a green reused for a different effective input | A file a job reads is outside its set (a new test, a new fixture, a file read through a path built at run time). | The consistency test of section 2; derive the set from `Select-Jobs` (way A) so a miss is a bug the repository already has; the nightly run and every merge run everything, so a false skip is found within a day and cannot reach a release (`release.yml` requires a successful push-to-`main` run). |
| **A flaky job whose green is luck** | The C# soak (`measure`) "has failed there twice"; `arena` raced on ENet ports; `platformer` on git. Reusing a lucky green hides the next failure. | The verdict table: measuring jobs never; a pair with a race stays out until fixed. Add a *failure memory*: if a job failed on a hash and passed on the same hash (a flake), its marker is never written for that hash. |
| **Cache poisoning from a fork** | A fork's pull request runs workflow code it controls; if it could write a marker the base trusts, it could make a job look green. | Markers are written only when `github.event.pull_request.head.repo.full_name == github.repository`, never on forks; GitHub also scopes a pull request's caches to its own merge ref, so `main` cannot read them. The workflow has `permissions: contents: read` and would need nothing more for the cache. |
| **Stale results after a runner image change** | A new image changes Mesa, Chrome, Edge, .NET or `git` (the 2.54 maintenance race in `ci.md` came from an image update). | `ImageOS`, `ImageVersion`, `RUNNER_OS`, `RUNNER_ARCH` and the `pwsh` version in the key; a time-to-live (a marker older than 7 days is ignored, whatever the cache says). |
| **Marker for work that did not finish** | `cancel-in-progress` ends a run mid-job. | The marker is written only by the `record` job when `needs.<job>.result == 'success'`; a cancelled job is not `success`. |
| **A hidden skip** | Someone reads "skipped" as "not needed". | The summary table with the run that proved each skip; stage 0 changes nothing visible. |
| **Cost of the feature** | A data file, a script, ten lookup steps, a `record` job, a new self-test, and a CI behaviour a contributor must understand. Not measured. | Stage 0 measures the real hit rate before any of this is relied on. |
| **Main always runs everything** | By design the cache can only save pull-request minutes; a periodic full run remains. | Keep `push` to `main` and the schedule as they are (`self-test.yml`). |

## 6. A staged plan

| Stage | What | Rollback |
|---|---|---|
| **0. Measure only** | Compute every selected job's key on every run; look it up; log whether an identical key had a green marker (and which run); write the marker after a green job; write the summary table and the `cache-observations` artifact. **Nothing is skipped.** Run for two weeks. The question it answers: out of the jobs `Select-Jobs` selected, what share would have been skipped, split by event, `run_attempt` and by job, and how many runner-minutes that was (from the jobs' own durations, `gh api`). Also answers the missing data of section 1 and checks the cache's scope and eviction rules. | Delete the `record` job and the `changes` steps; the markers are cache entries that expire by themselves. No job's behaviour changed. |
| **1. Skip a small safe set on pull-request re-runs** | `lint`, `zero-config`, `explicit-runners`, `action`, `init` and `field-test`, on `pull_request` events only, same repository only, markers up to 7 days old. `main`, the schedule and `workflow_dispatch` run everything. Keep stage 0's logging so the hit rate stays visible. | One input, `cache-skip: false` (or one edit of the `if:` expressions) returns to stage 0; the table in the summary names every skip, so a wrong skip can be traced. |
| **2. More jobs** | `csharp`, `game-benchmark`, `web`, `local-windows`, and the `game-programme` pairs one at a time (not `arena`), each added only when the record shows no flake on its hash. | Remove a job from the list; each addition is one line. |
| **3. (only if the owner wants it) Let `main` reuse** | `main` skips a job when a marker for its exact hash exists from a pull request run, with a nightly full run kept. Needs a store `main` can read (check run or results branch). Saves up to the 513 minutes of a merge, which is the real money, and carries the real risk. | Back to stage 2: `main` runs everything again. |

## 7. Decision for the owner

1. **Is stage 0 enough for now?** It costs a little CI time, changes no behaviour, and replaces three missing numbers
   (repeat rate, cancelled-but-green jobs, identical-input pushes) with measured ones. The alternative is to decide on the
   estimates of section 1, which are only ceilings.
2. **Which jobs may a green be reused for, and is the false-skip risk accepted for them?** The table proposes `lint`,
   `zero-config`, `explicit-runners`, `action`, `init`, `field-test` first; `measure` never; the pairs only after their
   races are fixed. Say if the list should be shorter, or if `csharp` (which posts the pull request comment) should wait.
3. **Is it worth the complexity at 14 to 100 minutes per pull request?** On a pull request the ceiling is small, and
   `Select-Jobs` already took the bill from 513. The case for the cache is stronger if `main` may use it (stage 3), which
   is a separate risk decision, or if re-runs and incremental pushes turn out to be common (stage 0 will say). If neither,
   "not now" is a sound answer, and this page stays as the record.
4. **How should a job's file set be defined**: derived from `Select-Jobs` (smaller change, coarser) or a declared list
   with a self-test (more precise, a second list to maintain)?
5. **Opt-in for the model workflows** (`evals.yml`, `token-benchmark.yml`): never, or an input that is off by default?
6. **Where would `main` read results from**, if stage 3 is wanted: a check run (needs `checks: write`) or a results
   branch (needs `contents: write`)?

## Stage 0, as built

The owner chose stage 0 on 2026-10-27, with the file set derived from `Select-Jobs.ps1` (way A of section 2). It measures; **no job's
`if:` changed and nothing is skipped.**

| Piece | What it does |
|---|---|
| `Select-Jobs.ps1 -Inputs` | The decision "which jobs does a change to this file run" is now a function of one file (`Get-FileJobs`); the selection of a pull request calls it for each changed file, and `-Inputs` calls it for every tracked file that is not documentation and prints job -> files as JSON. `tests/Test-SelectJobs.ps1` holds the selection to the same rules as before. |
| `Get-InputHash.ps1` | Per job, the sha256 of the job id, the event kind (pull request or not), the runner image (`ImageOS-ImageVersion`), the PowerShell version and the git mode and object id of each file in the job's set, read from the commit's tree. `lint` is hashed over the whole tree id. |
| `changes` job | Computes the hashes and looks each one up with `actions/cache/restore` (`lookup-only`), key `ci-job-<job>-<hash>`. The outputs `hash-<job>` and `hit-<job>` go to `record`. |
| `record` job | After every job (`if: always()`): writes `cache-observations.jsonl` (job, hash, hit, selected, result, event, run attempt, run id), uploads it as the `cache-observations` artifact (14 days), appends a table to the step summary and saves a one-line marker for each job that succeeded without a marker for its hash. A pull request from a fork saves none. |
| `tests/Test-InputHash.ps1` | A temporary repository: a change moves the hash of the jobs that read the file; a documentation commit moves lint's alone; the event and the runner image move every hash; what `record` saves and what it does not. |

Not in stage 0: the `game-programme` pairs (a matrix job; keyed later, per game folder), `coverage`, and every `if:` that would skip.

**Reading the result after two weeks.** For each `cache-observations` artifact (`gh run download`), a line with `hit: true`
and `selected: true` is a job that would have been skipped. Group by job, `event` and `runAttempt`; the minutes are the
jobs' own durations (`gh api repos/<repo>/actions/runs/<id>/jobs`, joined on `runId`). That answers the three gaps of section 1
and the cache's scope and eviction rules. Markers are Actions cache entries, so a pull request run reads its own earlier
runs' and the default branch's, not another branch's, which is the scope stage 1 would have.
