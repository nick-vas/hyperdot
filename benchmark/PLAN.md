# The game-making benchmark: plan

The owner's decisions (2026-10-23) and the design that follows from them. The pilot programme
(`game-benchmark.json`, five tasks on one prototype) stays until stage 7 introduces this one.

## What the pilot showed

60 sessions at commit c190ddc, the five prototype tasks:

| Configuration | Pass | Tokens per solved task | Class (pilot scale) |
|---|---:|---:|---|
| Sonnet 5.5 | 93% | 91k | C (64.9) |
| Sonnet 5.5 + plugin | 100% | 150k | G (103.2) |
| Haiku 5.5 | 100% | 137k | F (94.8) |
| Haiku 5.5 + plugin | 100% | 233k | G (158.9) |

- The tasks are too easy. Three configurations solve everything, so passing cannot tell them apart and only cost can.
  Work where a missed problem costs something is where the plugin should help, and the pilot has none of it.
- The plugin's overhead is measurable: about 1.7 times the tokens on small tasks. Most of it is the skill list and the Stop
  hook, which makes every session that changed code run the whole suite before it may finish. That is worth paying only
  when it catches something. The staged programme has to contain things for it to catch.

## The staged programme's first pilot

The min tier on 2026-10-23 (token-benchmark run 29, commit de84416): arcade, GDScript, the first two tasks of each
stage, one run per task and configuration, 32 sessions for $1.89 (the runner estimated $3.52).

| Task | Sonnet | Sonnet + plugin | Haiku | Haiku + plugin |
|---|---|---|---|---|
| prototype fix-bug | pass | pass | pass | pass |
| prototype write-tests | pass | pass | fail (missed the hp mutant) | pass |
| alpha add-content | pass | pass | pass | pass |
| alpha fix-architecture | pass | fail (hidden score-label test) | pass | pass |
| beta fix-playthrough | fail (246 words, limit 220) | pass | timed out twice | timed out twice |
| beta add-feedback | pass | pass | pass | pass |
| release fix-export | pass | pass | pass | pass |
| release fix-store | pass | pass | pass | pass |
| **Median tokens per session** | 123k | 239k | 315k | 562k |
| **Cost** | $0.71 | $0.99 | $0.08 | $0.11 |

- **Difficulty.** Five of the eight tasks were solved by every configuration, so by the rule in section 2 they measure
  only cost. One run per configuration cannot apply the rule, though: it is applied on the mid tier (three runs), and
  the four tasks per stage not piloted yet (explain-failure, add-feature, migrate-save, the pause bug, translations,
  performance, the settings flow, cut-version) go into that run too. Hardening candidates if they stay easy: the
  prototype fix-bug, add-content, add-feedback and both release tasks.
- **Time.** Haiku's fix-playthrough sessions used their whole 900 s twice (each check runs the bot through five levels),
  so the template now allows 1800 s. Sonnet with the plugin solved it in 68 s; without it, Sonnet fixed it in 660 s but
  wrote 26 words too many, the verbosity seen in the tool programme.
- **The plugin.** About twice the tokens again (1.9 times for Sonnet, 1.8 for Haiku) and the same pass count for Sonnet
  (one task won, one lost); for Haiku it turned the write-tests failure into a pass. Too few runs to call either way.
- **Cost model.** Median sessions cost $0.077 (Sonnet), $0.121 (Sonnet + plugin), $0.011 (Haiku) and $0.017 (Haiku +
  plugin); `cost-model.json` now uses these with a quarter added, so estimates stay above spend.

## The second pilot

The other eight arcade GDScript tasks on 2026-10-24 (token-benchmark run 32, commit c7e9aa7), one run per task and
configuration, the first run with every session isolated as its own user on GitHub's runner: 32 sessions for $1.62
(the runner estimated $2.28).

| Task | Sonnet | Sonnet + plugin | Haiku | Haiku + plugin |
|---|---|---|---|---|
| prototype add-feature | pass | pass | pass | pass |
| prototype explain-failure | pass | pass | pass | pass |
| alpha migrate-save | pass | pass | pass | pass |
| alpha fix-bug (the pause bug) | pass | pass | pass | pass |
| beta fill-translations | pass | pass | pass | pass |
| beta fix-performance | fail (hidden many-shots test; 225 words, limit 220) | pass | fail (hidden test; 244 words; 1324 s with a retry) | fail (hidden test; out of turns at 41) |
| beta fix-flow | pass | pass | pass | pass |
| release cut-version | pass | pass | pass | pass |
| **Median tokens per session** | 92k | 237k | 263k | 463k |
| **Cost** | $0.51 | $0.88 | $0.09 | $0.14 |

- **Difficulty.** Seven of the eight were solved by every configuration; with the first pilot, 12 of the 16 arcade
  tasks were. Only fix-performance told the configurations apart: the hidden test fires many shots and counts the
  collision checks, and only Sonnet with the plugin made them scale. The mid tier's three runs decide which of the 12
  are hardened or dropped by the rule in section 2; until then, the tasks that need a measured or hidden behaviour
  (performance, the hidden tests behind write-tests and fix-architecture) are the model for hardening the rest.
- **Length again.** Both failed answers without the plugin were also over their word limit (Sonnet by 5, Haiku by 24),
  as in the first pilot and the tool programme.
- **The plugin.** 2.6 times Sonnet's tokens and 1.8 times Haiku's; it won the one task that discriminated, for Sonnet.
- **Cost model.** Median sessions cost $0.059 (Sonnet), $0.107 (Sonnet + plugin), $0.008 (Haiku) and $0.013 (Haiku +
  plugin), all under `cost-model.json`'s figures, which stay as they are.
- **Isolation.** The fix that lets a runner that is not root start sessions through sudo (the session user enters its
  game folder itself) held for all 32 sessions; the run before it (31) had failed on that before any session started.

## Decisions

| Question | Decision |
|---|---|
| What the game label says | Two results, reported apart: **task efficiency** (tokens per solved everyday task) and **milestones** (how often, and at what cost, an agent takes a game through a stage) |
| Stages | Prototype, alpha, beta, release candidate |
| Fixtures | Four stages for every genre; no main game; as many genres as possible; any subset selectable per run |
| Languages | GDScript and C# for every stage |
| Grading | All of it: hard checks, measured stand-ins, a model judge with a rubric, blind side-by-side, and human rating (judge calibration and a blind review page) |
| Judged results | Count inside the class |
| Cost | Selectable tiers: min under $10, mid under $50, max above $50 |
| Genres | The ten below |
| Judge | The best value for money: the cheapest model that passes calibration (section 3) |
| Quality factor | Side-by-side preference moves the index by a factor between 0.75 and 1.25 |
| Real games | Also a private field test on the owner's machine, numbers only |

## 1. Fixtures: genres x stages x languages

**Genres** (first wave, each chosen for the kit's parts it exercises):

| Genre | Exercises |
|---|---|
| Arcade shooter | juice, bench, flows, playthrough bot, saves |
| Platformer | movement feel, camera, `placement_check.gd`, physics determinism |
| Puzzle | `data` runner, level JSON, procgen seeds |
| Card or turn-based | rules tests, data, AI (utility, behaviour trees) |
| Top-down roguelite | procgen, AI, saves, performance with many entities |
| Tower defence | pathfinding, economy data, balance, bench |
| Narrative | dialogue data, localisation, `textsize`, saves |
| Racing | input, physics, camera, frame pacing |
| Multiplayer arena | ENet, `soak`, netcode core |
| Idle or incremental | economy, long-run saves, mobile and Web layout |

**Stages**, each a frozen state of the same game:

| Stage | The game has | Typical defects planted |
|---|---|---|
| Prototype | the core loop, a few tests | a logic bug, missing tests |
| Alpha | several scenes, menus, a plan at the alpha gate, content missing | a failing gate, fragile node paths, a save that loses data |
| Beta | all content | a frame-time regression, a broken UI flow, a missing translation, feedback missing on an event, a bot that cannot finish |
| Release candidate | export presets, store page, credits, version | an export that fails to start, store art the wrong size, a missing licence, an unversioned build |

**Building them without writing 80 games.** Each genre is written once per language, complete at release-candidate
level. A stage is that game minus features and content plus planted defects, described by a *stage manifest*
(`benchmark/games/<genre>/<language>/stages/<stage>.json`). A generator (`New-StageFixture`) builds a stage
deterministically from the full game and the manifest. That is 20 games for 10 genres, not 80, and a fix to a game
reaches all four of its stages.

**The same game in both languages** is held to one behaviour: language-neutral checks (flows, playthrough logs, the
kit's runners) run against both, so a C# and a GDScript stage differ only in code.

## 2. Tasks

**Task templates** apply to every genre. A template names a kind of work and how it is graded; each genre's manifest
fills in the details (which file, which defect, which hidden test).

| Stage | Templates |
|---|---|
| Prototype | explain a failing test; fix a reported bug; add a feature with tests; write tests that catch planted bugs; expose a value to the editor |
| Alpha | pass the alpha gate (`plan -Json`); add a level with its flow and placement check; fix an architecture warning without changing behaviour; make saves survive a version change; add input rebinding |
| Beta | find and fix a frame-time regression (`bench`); repair a broken UI flow; fill a translation gap (`l10n`, `textsize`); add missing feedback (`juice`); make the bot finish (`playthrough`); fix a flaky test without hiding it |
| Release candidate | export and run the build (`export -Run`, Web too); clear `doctor`'s store, legal and credits problems; cut a version (`-GameVersion`); pass the colour-vision and layout checks; write store text (judged) |

**Milestone runs**: one long session per stage boundary (prototype to alpha, alpha to beta, beta to release
candidate) with a larger budget. It is graded by the next stage's gate and acceptance suite. It reports whether the
milestone was reached and its tokens. Milestones are the second result on the label.

**Difficulty is measured, not guessed.** A task stays in the standard programme only if, in its pilot, at least one
configuration passes it less than 90% of the time and at least one passes it more than 20%. Tasks everyone solves
measure only cost (the pilot's problem); tasks nobody solves measure nothing.

## 3. Grading

Every task names the layers it uses; a session passes when every layer it uses passes.

| Layer | What | Example |
|---|---|---|
| 1 Hard checks | tests, hidden tests, the kit's runners, unchanged files, mutants | the beta flow passes; `doctor` has no store errors |
| 2 Measured stand-ins | numbers for qualities | "jump feels better": feedback within 100 ms, frame time under budget; "fair level": the bot finishes in 60-120 s with 1-3 deaths |
| 3 Model judge | a pinned judge model (section 3) scores 1-5 against a written rubric, median of three; 4 or more passes | store text: accurate to the GDD, no false claims, the hook in the first sentence |
| 4 Blind side-by-side | the judge sees two configurations' results unlabelled and picks one | the same store text task, with and without the plugin |
| 5 Human rating | see below | |

**Judged results inside the class.** Layer 3 is a pass or a fail like the others. Layer 4 gives each configuration a
win rate against the same model without the plugin. It enters the class as a bounded quality factor: the index is
divided by `0.75 + 0.5 x win rate`, between 0.75 and 1.25. A configuration whose work is preferred every time gets an
index 20% lower, and one never preferred gets 33% higher.

**Choosing the judge: the best value for money.** Stage 3 runs every candidate (Haiku 5.5 and Sonnet 5.5 first, a
larger model only if both fail) over the same pilot results that you also rated blind. The judge is the cheapest
candidate that:

- agrees with you on at least 80% of them;
- gives the same pass or fail on at least 90% of repeated judgings of one result.

It is pinned in the scale by its full model id.

**Keeping a judged class honest.**

- The judge model and its rubrics are part of the scale; changing either is a new scale, as the EU rescales.
- The judge never sees which configuration made what. The order is randomised and the pair judged both ways.
- **Judge calibration** (human): about 10 judged results per run go to you blind. If you and the judge agree less than
  80% of the time, the class is printed as *unconfirmed* until the rubric is fixed.
- **Blind review page** (human): after a run, an artifact page shows the unlabelled pairs (screenshots, store text,
  short clips). You pick the better one or score 1-5, in about 5 minutes. The page keeps the ratings, and the label tool
  reads them as layer 5 and as calibration.

## 4. Choosing what runs

Every run can be narrowed: `-Genre`, `-Stage`, `-Language`, `-Task`, `-Model`, `-Plugin`. A tier fixes the rest and
carries a cost ceiling. The runner estimates a run's cost before it starts, from the median cost of each kind of
session in earlier runs (the pilot's until there are more). It refuses a run whose estimate is over the tier's
ceiling, as `maxCalls` refuses too many sessions now. During the run it adds up what the sessions actually cost (the
CLI's own figure), and it stops starting new ones once that passes the ceiling. The sessions it did not run are listed
as not run, so such a run is incomplete and sets no class.

| Tier | Runs (4 configurations: Sonnet and Haiku, with and without the plugin) | Ceiling | Use |
|---|---|---:|---|
| min | all 10 genres, 1 stage each, 2 tasks, 1 repeat, no milestones (every language and stage pair at least once) | $10 | a quick check after changing a skill (estimate $5.70) |
| mid | all 10 genres, 1 stage in each language, 2 tasks a stage, 3 repeats, 5 milestones | $120 | **the standard programme: the only run that sets a class** (estimate $100.20) |
| max | any selection up to every genre, stage, language, task and milestone, 5 repeats | above $120, shown before it starts | a release, wider coverage, tighter tolerances |

The tiers were widened on 2026-10-26 from one genre (min) and three (mid, then $50 with an estimate of $60) to all ten,
once every genre was written in both languages. The estimates come from `cost-model.json`, whose milestone figures are
still guesses (about ten times a task) until a run measures them; milestones are about two thirds of the mid estimate.

**The mid tier covers both languages without doubling its cost.** Each genre runs one stage in GDScript and the stage
two after it in C#, rotating through the genres, so every stage is measured in both languages and no language always
gets the harder stages (2 or 3 cells for each language and stage). The milestones start from five of those cells:
arcade from the prototype and platformer from the alpha in GDScript, puzzle from the prototype in C#, narrative from the
beta in GDScript and the arena from the beta in C#; the runner refuses a tier milestone that starts from none of the
tier's cells.

| Genre | GDScript | C# | Milestone |
|---|---|---|---|
| Arcade shooter | prototype | beta | GDScript, prototype to alpha |
| Platformer | alpha | release candidate | GDScript, alpha to beta |
| Puzzle | beta | prototype | C#, prototype to alpha |
| Card game | release candidate | alpha | |
| Roguelite | prototype | beta | |
| Tower defence | alpha | release candidate | |
| Narrative | beta | prototype | GDScript, beta to release candidate |
| Racing | release candidate | alpha | |
| Multiplayer arena | prototype | beta | C#, beta to release candidate |
| Idle | alpha | release candidate | |

The milestone for each genre also rotates: prototype to alpha, alpha to beta, and beta to release candidate.

The estimate for mid: 24 tasks x 3 repeats x 4 configurations, about $32 at $0.20 a Sonnet session and $0.02 a Haiku
one. Three milestones x 4 configurations add about $13, at about $2 for Sonnet and $0.20 for Haiku. A Haiku judge adds
cents. The total is about $45. Stage 2's pilot replaces these guesses with measured costs. If mid would go over, it
drops to 2 tasks in some stages, never below the three genres.

A run through the subscription token counts against the plan's usage, not a bill. A large max run may need several days.

A narrowed or custom run gives informative results, never a class. The EU label rates only the standard programme,
however many others a machine has.

## 5. The private field test

`-GameSource <folder>` runs generic templates (fix a mutant the tool plants, write tests that catch planted bugs, make
`doctor` green, make the bot finish) on a game on your machine, in a copy. It reports numbers only: pass, tokens, cost,
time per template and configuration. It never reports file names, code or text. Nothing is committed. You paste the
summary here and it goes in a field-test table beside the label, marked as one owner's game, not part of the class.

## 6. Isolation

Sessions that can run commands could read the checkout the benchmark runs from, hidden tests included. The staged
programme closes that:

- sessions run as a separate user;
- their game copy is the only folder that user can read;
- hidden tests and graders stay in a folder only the runner's user can read.

The workflow does this with `useradd` and file modes; the field test does the same locally, or warns where it cannot.

## 7. Stages of the work

| # | Work | Done when |
|---|---|---|
| 1 | Runner: programmes made of fixtures x templates; tiers and selectors; cost estimate, ceiling and stop; a matrix of jobs in the workflow; per-session saves. **Done**: `GameProgramme.ps1`, `cost-model.json`, the workflow's `staged` programme; the label tool reading several jobs' results is stage 7 | `-DryRun` lists a mid run; the self-test covers selectors, tiers, the ceiling and milestones |
| 2 | `tests/Test-GameProgramme.ps1` (done): every task's untouched game fails, its reference passes, its decoy fails, no model needed. First genre (arcade shooter) in both languages; stage manifests; the generator; every template on it; a pilot run to measure difficulty and cost | each template passes its good stand-in and fails its bad one; the pilot keeps or drops each task by the difficulty rule |
| 3 | Grading layers 2-4; pinned judge; rubrics; the blind review page; calibration. **Done**: layer 3 (`judge` on a task, in the runner), layer 4 (`Invoke-SideBySide.ps1`), the quality factor in the label tool. **Since**: the review page (`benchmark/review-page.html`, fed by `Invoke-SideBySide.ps1 -ReviewOut` with the first pilot's 15 pairs) and `Get-JudgeAgreement.ps1`. **Since**: the owner's 15 blind verdicts (`calibration/pilot-1.json`: the plugin's work preferred in 5, the other in 7, 3 even) and the calibration job (`token-benchmark.yml`, `calibrate`). **First calibration** (token-benchmark run 33, $0.77): Haiku agreed with the owner on 53% and with itself on 73%, Sonnet on 53% and 87%; neither passes. Both disagree on nearly the same pairs and the same way, favouring the plugin's work where the owner preferred the other or called it even, so the gap is the rubric, not the model: the owner's notes reward an explanation of the change and its context, which the rubric's "length is not quality" and "as small as the task allows" discount, and call a pair even when each side did a different part. **Since**: the rubric rewritten from those notes (`rubrics/side-by-side.md`), and the owner's blind verdicts on the second pilot's 16 pairs, judged without the rubric shown (`calibration/pilot-2.json`: the plugin's work preferred in 11, the other in 5). **Second calibration** (token-benchmark run 34, $0.76, the rewritten rubric on the second set): Haiku agreed with the owner on 56% and with itself on 81%, Sonnet on 50% and 63%; neither passes. The misses are now mostly the order the work is shown in: a judge picking the same position in both orders counts as even, which Sonnet did on 6 pairs and Haiku on 3, and where Sonnet's two orders agreed it matched the owner on 8 of 10. Only two pairs (q01 and q08) are firm disagreements both judges share, each preferring the other work where the owner preferred the plugin's. The owner confirmed the second set's verdicts are their own judgement. **Third calibration** (token-benchmark runs 35 and 36, $3.12, Opus with the rewritten rubric on both sets): Opus agreed with the owner on 53% of the first set and with itself on 100%, and on 69% and 88% of the second; it does not pass. Order no longer decides (2 flips in 31 pairs, against Sonnet's 6 in 16), so what is left is a steady difference of judgement: on the first set 6 of its 7 disagreements prefer the plugin's work where the owner preferred the other or called it even, and it never answers even although the rubric allows it. The judge reads the same work the owner read (no piece of work in either set reaches the 12,000-character cut). **The owner's re-judge** (`calibration/retest-1.json`): ten earlier pairs again, blind, reshuffled and with A and B swapped in half: 6 of 10 the same. From the first set 2 of 5 (judged with the old rubric shown; all three changes moved to the plugin's work, as Opus had judged them), from the second 4 of 5. So the first set's verdicts carry the old rubric and count only for a judge's agreement with itself; a judge is measured against the second set's verdicts, with the re-judged pairs' newer verdicts (21 pairs). **Fourth calibration** (token-benchmark runs 37-40, $1.54, Haiku and Sonnet with the rewritten rubric on both sets): on the 21 pairs Haiku agrees with the owner on 62% (57% on a second run), Sonnet 62% (57%), Opus 71%; with itself over all 31 pairs Haiku 84%, Sonnet 74%, Opus 94%. Haiku and Sonnet gave the same outcome on only 10 of 16 pairs from one run of the second set to the next. Per judgement Haiku costs $0.0013, Sonnet $0.023, Opus $0.050. Held to the owner's own agreement with themselves (60%) and 90% with itself, only Opus passes. **Fifth calibration** (token-benchmark runs 41 and 42, $0.25, Haiku with ten votes per order, `Invoke-SideBySide.ps1 -Votes 10`): 62% with the owner on the 21 pairs and 81% with itself on the 31, no better than one vote. Its majorities are firm (51 of 62 orders had 8 or more of 10 votes the same, 2 were ties) and it chose the second position 353 times to the first's 246: the order changes its answer the same way every time, which a vote cannot average out, as it can noise. **Left**: the owner's choice: pin Opus, the only judge that passes the relative bar, at about $0.10 a pair (two judgements) | the label tool reads judged and human results; the self-test fakes a judge |
| 4 | Milestone runs | prototype to alpha graded by the alpha gate, in both languages |
| 5 | Isolation as separate users. **Done**: `-Isolate` (`Isolation.ps1`), on in the workflow; `tests/Test-BenchmarkIsolation.ps1` | a test session cannot read a hidden test |
| 6 | Genres 2-10, written in parallel by agents, one genre each, reviewed against the first. **Platformer** (Glowmoss Ridge, `games/platformer/DESIGN.md`): done in both languages, the C# port from the design's language-neutral contract. **Puzzle** (Frostmote, `games/puzzle/DESIGN.md`): GDScript and C# done, every task checked in both. **Card game** (Lanternfen, `games/cards/DESIGN.md`): done in both languages, the C# port from the design's language-neutral contract. **Narrative game** (Saltmere Crossing, `games/narrative/DESIGN.md`): done in both languages, the C# port from the design's language-neutral contract. **Roguelite** (Wickerdeep, `games/roguelite/DESIGN.md`): done in both languages, the C# port from the design's language-neutral contract, its floors and bot run checked against the GDScript version's. **Tower defence** (Bramblegate, `games/towerdefence/DESIGN.md`): done in both languages, the C# port from the design's language-neutral contract. **Idle game** (Duskhive, `games/idle/DESIGN.md`): done in both languages, the C# port from the design's language-neutral contract. **Racing** (Cinderloop, `games/racing/DESIGN.md`): done in both languages, the C# port from the design's language-neutral contract. **Multiplayer arena** (Glimmerpit, `games/arena/DESIGN.md`): done in both languages, the C# port from the design's language-neutral contract. | each passes its stage checks in both languages |
| 7 | Introduce the new scale on the mid tier; labels for the current version | class A empty at introduction, tolerances from the bootstrap |
| 8 | Field test mode. **Done**: `-GameSource` (`FieldTest.ps1`, `field-test.json`), tested on both examples with a stand-in (`tests/Test-FieldTest.ps1`). **Left**: the owner's run and its summary in `docs/label.md` | you run it on a game of yours and paste the summary |

## Settled questions

The owner answered on 2026-10-23:

- **Genres:** the ten.
- **Judge:** the best value for money.
- **Quality factor:** 0.75 to 1.25.
- **Budget:** min under $10, mid under $50, max above $50.
