# Retrospective: the 0.1.0 effort

A look back over the work from the first commit on 2026-10-05 to 2026-10-27 (433 commits on `main`, 126 of them merged
pull requests), written from the repository's own records: `CHANGELOG.md`, [roadmap.md](roadmap.md),
[../benchmark/PLAN.md](../benchmark/PLAN.md), [ci.md](ci.md), [powershell.md](powershell.md) and `git log`. Where a
number was asked for and no source in the repository holds it, this page says so instead of repeating it.

## What went well

- **The benchmark became a measurement that resists the thing it measures.** Sessions run as a separate user in a copy
  without `benchmark/`, the grader reads saved answers with one rule, and the label's declared values are computed, never
  typed ([label.md](label.md)). The tool programme has a rating from 216 sessions for $5.95.
- **The staged game programme is complete in both languages.** Ten genres, each in GDScript and C#, four stages each, 17
  tasks and three milestones per game, every task with a reference solution and most with a decoy, all checked without a
  model by `tests/Test-GameProgramme.ps1`.
- **Cheap runs found the faults before the expensive one.** The min tier over all ten genres (run 43) found that no task
  failed for every configuration and one session user's HOME broke `validate`; the mid run (run 44) found the grading
  rule below. Both were fixed with a test.
- **Reviews paid for themselves.** The adversarial review of every area fixed 59 of its 62 findings with
  regression tests. The PowerShell review ([powershell.md](powershell.md)) then fixed real bugs (a `bench -Sweep` message
  naming `' '`, `Resolve-Path` on a kit under a folder with brackets, a self-test calling a function that does not
  exist) and turned the rest into syntax-tree rules.
- **The judge was calibrated against the owner, not against a bar picked in advance.** Five calibration rounds ended in a
  rule the owner set: the judge must agree with the owner as often as the owner agrees with themselves on a blind re-judge
  (6 of 10), and with itself at least 90% of the time. Only Opus passed.

## What cost time

- **Git's background maintenance (git 2.54 and later).** After a commit, git packs loose objects in a detached process.
  The benchmark's copy of a freshly committed game lost files under it ("Could not find a part of the path
  .git/objects/..."). It ended four parts of run 44 (92 sessions never started) and two self-test jobs on the runners'
  git 2.55. Fixed in nick-vas/hyperdot#134: `New-GameWorkspace` and every CI job turn maintenance off ([ci.md](ci.md#git-background-maintenance)).
- **The ENet `server_relay` race.** The GDScript arena game left `SceneMultiplayer.server_relay` on, so the engine sent
  news of a newcomer to a peer whose disconnect it had received but not yet reported: "Unable to send packet on channel
  0, max channels: 0", and `soak` failed with `engine-errors` in 2 runs of 20 on one reference. The C# port had it off
  already; the GDScript game was fixed in #136.
- **The usage limit stopped run 44.** Twenty parallel jobs on the owner's subscription used the window up in 65 minutes
  (13:48 UTC): 154 sessions did not run, 12 were cut off, and the owner's own work stopped too. 294 of 540 sessions were
  graded, for $34.53. A complete mid run was postponed until after 0.1.0 ([roadmap.md](roadmap.md#after-010)).
- **CI that grew with every game.** A full self-test run (run 40360421024) was 35 jobs and 513 runner-minutes, 84% of
  them in the 20 jobs of the staged programme, and every push to a pull request branch started two runs (47 of the 100
  sampled runs were cancelled). Selecting jobs from the changed files gives about 14 runner-minutes for documentation,
  45 for one game, 65 for a kit library and 100 for the programme's own code; `main` and the nightly run still run all
  513. These are estimates from the jobs' averages ([ci.md](ci.md#measured)).
- **A grading rule that punished good work.** `racing.alpha.csharp.fix-bug` passed 0 of 10 because the `unchanged` rule
  failed any change to `test/CameraTest.cs`, and every session had added tests to it. Of 14 sessions failed for changing a
  test file, 12 only added tests. The grader now lets a kept file gain lines, puts the original back before the suite
  runs, and counts the additions (#135). It was seen only because a mid run existed to see it.
- **Judge calibration took five rounds and $6.44 of runs.** Haiku and Sonnet agreed with the owner on 50 to 62% and changed
  their answer with the order the work was shown in; ten votes per order did not help, since the order bias is steady
  (353 votes for the second position against 246 for the first). The owner's re-judge of ten earlier pairs showed their own
  agreement with themselves was 60%, which moved the bar from 80% to 60% and made Opus the pinned judge. The first set's
  verdicts turned out to carry the old rubric and count only for self-agreement.

## Numbers

| What | Value | Source |
|---|---|---|
| Tool programme, 0.1.0 rating | 216 sessions, $5.95, GitHub runs 39930259189 to 39930286282 | [token-benchmark.md](token-benchmark.md#reference-runs-october-2026) |
| Run 43, min tier over ten genres | 66 of 80 sessions passed, $6.58 (estimated $5.70) | PLAN.md |
| Run 43 passes, of 20 | Sonnet 12, Sonnet + plugin 19, Haiku 16, Haiku + plugin 19 | PLAN.md |
| Run 44, first mid run | 294 of 540 sessions graded, $34.53 (the whole run was estimated at $105.96) | PLAN.md |
| Mid tier price after run 44 | $67.71 ($19.20, $27.75, $10.14 and $10.62 per configuration) | `benchmark/cost-model.json`, PLAN.md |
| Mean cost of a task, measured | $0.108, $0.154, $0.016, $0.022 (Sonnet, Sonnet + plugin, Haiku, Haiku + plugin) | PLAN.md, run 44 |
| Mean cost of a milestone, measured | $0.387, $0.450, $0.520, $0.456 (same order; Haiku's from three sessions each) | PLAN.md, run 44 |
| Judge cost per judgement | Haiku $0.0013, Sonnet $0.023, Opus $0.050 | PLAN.md |
| Self-test run | 35 jobs, 513 runner-minutes before selection; about 14 to 100 for a pull request after | [ci.md](ci.md#measured) |
| PowerShell review | 71 `ConvertTo-Json` calls given a `-Depth` in one commit (e7c014a); 18 named checks in `tests/Test-PowerShellPatterns.ps1` today (the pull request title said 17); 154 tracked `.ps1` files, 135 of them outside the fixtures | `git`, the test file |

The same 38 sessions that all four configurations completed in run 44 are the only fair comparison it offers: the plugin
lifted both models from 27 to 32 of 36 tasks, for $4.29 against $6.21 with Sonnet and $1.19 against $1.30 with Haiku.

**Not recorded in the repository:** the `bench` run on the C# example that item 5 of the 0.1.0 list names. No result
for it (frames per second, p99, draw calls or hitch count) is in the changelog, the docs or the benchmark records, so none
is quoted here. Running `bench` on `examples/csharp` and writing the numbers where they can be found is still to do.

## Lessons

1. **A sampled run before the full run.** Run 43 cost $6.58 and found a kit fault; run 44 cost $34.53 and found a grading
   fault and a race. Each full run should be preceded by a cheaper one on the same code.
2. **Parallelism has a price that is not money.** Twenty jobs finished their allowance in 65 minutes. The plan's usage
   window is a resource like runner time and has to be budgeted ([PLAN.md](../benchmark/PLAN.md#the-first-mid-run-stopped-halfway)).
3. **A grader needs the same review as the code.** The `unchanged` rule was written to stop weakened tests and stopped
   extended ones. A grader should be tried against the work a model is likely to do, not only against the reference
   solution and the decoy.
4. **Races hide in the harness.** Both races (git maintenance, ENet relay) appeared only under load or repeated runs. A
   repeat count and a failure record per job ([ci.md](ci.md#which-tests-ever-caught-anything)) found them; reading the code did not.
5. **Set the bar for a human-calibrated judge from the human.** The 80% bar was a guess; the owner's own agreement with
   themselves (60%) was a measurement.
6. **Selecting what CI runs needs its own test.** `tests/Test-SelectJobs.ps1` checks that every test a skippable job runs
   selects that job; without it a thinned CI silently stops covering something.
7. **Syntax-tree rules beat reminders.** A rule that fires on its fixture and not on its clean file stays true; a line
   in `AGENTS.md` is forgotten. The PowerShell review moved patterns with no use left into `Test-PowerShellPatterns.ps1`.
8. **Write down what was not measured.** The `bench` numbers above are the example: a step marked done in the roadmap
   without a result anyone can find.

## What to do differently in 0.2

- Run the complete mid run first, in fewer parallel jobs or over several usage windows, after the `unchanged` rule and
  the arena fix (both done), and then Opus as a run of its own ([roadmap.md](roadmap.md#after-010)).
- Record every roadmap step's result (a number or a link) where the step is marked done.
- Keep the raw runs of a benchmark that sets a label in the repository or a release asset. The tool programme's 216
  sessions lived only as GitHub Actions artifacts. The label files were rebuilt from them after the release work (the
  numbers matched the recorded table) and the runs are now kept in `benchmark/reference-runs/`, so a clone can repeat it.
- Decide the order of work by what the next paid run would find: run the cheap checks that could fail it first.
- Look at the Sonnet word-limit habit before the next measurement ([roadmap.md](roadmap.md#from-the-label-and-the-adversarial-review-2026-10-23)):
  6 of its 8 failures in run 43 and 12 in run 44's graded sessions were the 220-word limit alone.
