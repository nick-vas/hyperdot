# A-to-Z plan for a solo developer

`hyperdot.ps1 plan` tracks a game from first idea to post-launch as seven phases with gates. This page explains
where the pipeline comes from and why the gates are what they are. Commands: `plan -Do init [-Profile jam] | status | done -Id <gate> | reopen -Id <gate>`, tasks with `add | move | remove | link | sync`,
all with `-Json` (see [json.md](json.md)).

## Where it comes from

Three inputs, cross-referenced:

1. **The Mehendysis GDD [development plan](https://github.com/Mehendysis/GameDevelopment/blob/main/docs/en/document-your-game/gdd/development-plan.md)**:
   a studio-scale template - pre-production (2 mo), production (12 mo, four milestones), testing (3 mo, alpha then
   closed/open beta), polish and launch prep (2 mo), post-launch - with risks (technical, creative, market) and mitigations.
   Its shape is kept; its team of 15 and 19 months are scaled down to one person.
2. **The [Work Loop](https://trello.com/b/vJnMkimq/work-loop) board (a Trello template)**: Backlog -> Design -> To Do -> Doing -> Testing -> Done
   (the template also uses Code Review, with a list limit as a signal to finish reviews before starting work). Kept as the daily
   loop: `plan.json` `tasks` use `backlog, design, todo, doing, verify, done` and `wipLimit` caps `doing`. "Verify" is where the
   test suite and an agent review replace a human code reviewer.
3. **Public solo-dev guidance** (weak evidence, mostly blogs and vendor posts; used for shape, not numbers):
   - milestone ladder prototype -> vertical slice -> content-complete -> beta -> gold, each retiring one risk;
     when one slips, cut scope, not testing ([Bugnet](https://bugnet.io/blog/milestones-for-indie-game-projects),
     [Wayline](https://www.wayline.io/blog/setting-game-development-milestones-concept-launch));
   - prototype tests whether the core loop is fun; a stranger playing 15 minutes and wanting more is the evidence
     ([Bugnet](https://bugnet.io/blog/project-management-for-solo-game-devs));
   - vertical slice as a PROCEED/PIVOT/KILL gate before production
     ([Claude-Code-Game-Studios skill](https://tessl.io/registry/skills/github/Donchitos/Claude-Code-Game-Studios/vertical-slice));
   - a timebox on the slice, and a scope ladder (MoSCoW) set up front ([Wayline](https://www.wayline.io/blog/launch-first-indie-game-roadmap-solo-devs));
   - Steam "Coming soon" page months before launch, because wishlists compound and each becomes a launch-day notification;
     one Next Fest per game ([Wayline checklist](https://www.wayline.io/game-launch-checklist),
     [Presskit field guide](https://presskit.gg/field-guides/steam-next-fest-guide)).

## The phases

| # | Phase | Weeks* | Question it answers | Automatic gates |
|---|---|---|---|---|
| 1 | Concept | 2 | What is it, and what is it not? | `docs/GDD.md` exists; `docs/RISKS.md` written; `docs/BUDGET.md` (optional) |
| 2 | Prototype | 4 | Is the core loop fun? | CI workflow wired; `docs/TRAILER.md` exists; `docs/DECISIONS.md` has the verdict |
| 3 | Vertical slice | 8 | Can I build and ship one polished piece? | a test runner detected; an export preset exists; `docs/TECH-DEBT.md` exists |
| 4 | Production | 24 | Can I build the rest as playable milestones? | `docs/MILESTONES.md` exists |
| 5 | Alpha and beta | 8 | Is it stable, fair, accessible? | no placeholders left; tests green |
| 6 | Release candidate and launch | 4 | Does a clean export run, and can players find it? | export preset |
| 7 | Post-launch | 8 | What do players hit, and what next? | `docs/RETRO.md` exists |

\*Defaults for about 10 hours a week; the slice gate re-sizes the rest from measured velocity. Edit `timeboxWeeks`, add or
remove gates freely: `plan.json` is yours after `init`. A manual gate marked done too early opens again with
`plan -Do reopen -Id <gate>`; an automatic gate opens by itself when the project stops meeting it.

Automatic checks: `tests` (a test framework's runner is detected), `ci` (a GitHub workflow calls the kit's reusable workflow or composite action, or `.gitlab-ci.yml` includes its GitLab template), `preset` (an export
preset exists), `runner:<name>` (that runner is set up), `file:<path>` (a folder, or a file that is not empty: an empty
`docs/RISKS.md` is not a risk log; the path is looked up from the repository root, then the Godot project) and
`placeholders` (nothing is left as a placeholder: no `assets.json` entry has `"placeholder": true` and the Placeholders
table of `docs/TECH-DEBT.md` has no row; with neither file, nothing says what is left, so it stays open). A gate with
`"optional": true` (`concept.budget`) is listed while open but does not hold its phase back.

## Rules baked into the gates

- **Scope is the only variable.** A phase past its timebox produces a warning that says cut scope or kill; testing and the gate stay.
- **Kill criteria are written before the prototype**, so the verdict is not made while attached to the work.
- **Every milestone is a playable build** that someone other than you can run.
- **Quality is automated where it can be**: tests, `validate`, `smoke` and `export -Run` are the gates agents can verify themselves;
  playtests and verdicts are manual gates that need a human.
- **The trailer is written before the game.** `prototype.trailer` wants `docs/TRAILER.md` (template
  `ci/godot/templates/TRAILER.md`): genre in the first 5 seconds, then the hook, content last; three standout moments; every
  core mechanic with the on-screen feedback a viewer would see. A prototype nobody can picture a trailer for is weak, and a
  mechanic with no visible feedback is design work now. Derek Lieu's talk: [docs/gdc/make-the-trailer-before-the-game.md](gdc/make-the-trailer-before-the-game.md).
- **Marketing starts in the vertical slice**, not after the beta.
- **A slice measures, not only impresses.** It lists its tech debt (`slice.debt`: every hacked, stubbed or unstarted system
  and what it costs at the size of the whole game, template `ci/godot/templates/TECH-DEBT.md`) and meets a frame budget on its
  busiest scene filled as the finished game will be (`slice.budget`, manual, with `bench -Scene ... -BudgetMs ...`). The verdict
  says PROCEED only for the intended experience, not a feature list or a tech demo. Volition's record across five games:
  [docs/gdc/vertical-slice-challenge.md](gdc/vertical-slice-challenge.md).

## Tasks and the GitHub Project

Day-to-day work lives in `plan.json` `tasks`, edited with commands so an agent cannot corrupt the file:

```powershell
pwsh ci/godot/hyperdot.ps1 plan -Do add -Title "Paddle feel pass" -Column todo
pwsh ci/godot/hyperdot.ps1 plan -Do move -Id t1 -Column doing      # refused past wipLimit
pwsh ci/godot/hyperdot.ps1 plan -Do move -Id t1 -Column "To Do"    # a column name works too
pwsh ci/godot/hyperdot.ps1 plan -Do remove -Id t1                  # delete a task
```

Columns map onto the Work Loop: `backlog` Backlog, `design` Design, `todo` To Do, `doing` Doing, `verify` Testing, `done` Done.
`-Column` (in `add`, `move` and `link`) takes a column id or the name of the project column it maps to, case-insensitive and by
prefix as sync matches options, so `"to do"` and `"Done 🎉"` work; `plan.json` always stores the id. `remove` deletes a task;
a removed task's id is never given again (`lastTaskNumber`), and its item is archived by the next sync (`project.toArchive`).

**GitHub Project sync** (`plan -Do sync`) is **experimental**: it has met only a stand-in `gh` so far (the live run waits, and
the open items are under GitHub Projects in [roadmap.md](roadmap.md#github-projects)). It keeps the plan the source of truth
and uses a GitHub Project as the place you drag things. It needs the GitHub CLI signed in with the `project` scope
(`gh auth login`, then `gh auth refresh -s project`; or `GH_TOKEN` holding a token with that scope). The kit never reads or
stores the token.

**Setup is one command.** `plan -Do sync -Board @me` (or `-Board <login>` for another user or an organisation) makes a private
project titled "<game> plan", adds a single-select field **Column** with the six columns above, links the project to the game's
GitHub repository when its git `origin` is on github.com, puts one item per task in its column, and saves `project.owner` and
`project.number` in `plan.json`. GitHub's built-in Status field offers only Todo, In Progress and Done and the CLI cannot change
its options, so the kit adds its own field; set the project's Board view to group by **Column** once (`gh project view <number>
--owner <owner> --web`; the CLI cannot create or edit views). To use a project that already exists, `plan -Do link -Board
<owner>/<number>` (a project URL works too) or `plan -Do sync -Board <owner>/<number>`.

After that `plan -Do sync` with no arguments:
- creates a draft item for a task with none, in the matching column;
- moves a task when its item was moved to another column (the board wins on column only);
- moves an item when its task was moved in the plan (`plan -Do move`). Each task records the column its item was in at the last
  sync (`boardColumn`), so an item in another column was moved on the board, and an item still in that column follows the task;
- reports an item that is gone (archived or deleted) and leaves it alone;
- turns an item you added on the board, in a column the plan maps, into a task in that column (in the current phase). An item
  whose body starts `plan task <id>` was made by the kit for a task that no task links now: it is reported, not imported;
- archives the item of a task removed with `plan -Do remove`; nothing is ever deleted.

Item ids are the project's node ids (`PVTI_...`; `gh project item-list <number> --owner <owner> --format json` shows them):
`plan -Do link -Id <task> -Item <id> -Column <column>` ties a task to an item made by hand. Options are matched by name prefix, so
`Done 🎉` matches `done`; override per column under `project.columns` in `plan.json` (sync and `link -Board` keep it). A task in a
column the plan does not have stops the sync before any call.

The plugin's second Stop hook (`hooks/project-sync.ps1`) runs the same sync after a turn that changed the plan's tasks and
the plan has a project, so the board follows without anyone asking. It keeps a hash of what it last synced in
`.godot/hyperdot-project-sync` (an unchanged plan costs no call), never blocks the turn, and turns a failure into a one-line
notice. `HYPERDOT_PROJECT_SYNC=off` disables it.

A game that used the Trello sync this replaced: the first `plan -Do sync -Board @me` drops each task's `cardId` and the
`trello` block and gives every task an item in the column the plan has. The Trello board itself is not touched; archive it by
hand when the project looks right.

`tests/Test-ProjectSync.ps1` runs these steps (and the hook) against a stand-in `gh` on every change, and with `-Live` against
GitHub with a private project it creates and deletes (the Project sync workflow, with a `HYPERDOT_PROJECT_TOKEN` repository
secret: a personal access token with the `project` scope, since the workflow's own token cannot reach a user's projects).

## Release dates

Steam's dates depend on each other, and a missed one moves the release. `plan.json` has an optional `release` block
(dates as `yyyy-MM-dd`, `null` until known), and `plan` and `status` warn when a rule from
[store-and-legal.md](store-and-legal.md) cannot be kept; they never fail:

| Field | Meaning | Warns when |
|---|---|---|
| `date` | The planned release day; nothing is checked without it | - |
| `steamFeePaid` | When the Steam Direct fee was paid | fewer than 21 days before `date`, or unset with fewer than 21 days left |
| `comingSoon` | When the Coming Soon page went (or goes) live | fewer than 14 days before `date`, or unset with fewer than 14 days left |
| `storePageSubmitted` | When the store page went to review | fewer than 7 business days before `comingSoon`, or unset with fewer left |
| `buildSubmitted` | When the build went to review | fewer than 7 business days before `date`, or unset with fewer left; before `storePageSubmitted` (the page is reviewed first) |
| `nextFest` | The first day of the Steam Next Fest the game takes part in | on or after `date` (do the last Next Fest before launch) |
| `demoSubmitted` | When the Next Fest demo went to review | after 3 weeks before `nextFest` (5 with `pressPreview`), or unset once that day has passed |
| `pressPreview` | `true` when the demo is in the press preview | - |

Reviews take 3 to 5 business days, so the kit asks for 7; business days are Monday to Friday (public holidays are not
known to it). From two weeks before `date` the release date is locked on Steam, which `plan` notes. `plan -Json` returns
the timeline as `release` ([json.md](json.md)): days and business days left and each deadline.

## The GDD, `status` and `/game`

`docs/GDD.md` (template: `ci/godot/templates/GDD.md`) is the game's scope. Features are headings of the form
`### F3 Lives and game over`, each with a `Priority:` line (must, should, could, won't) and `Done when:` bullets. Tests that
prove a feature carry a `GDD:F3` tag in their name or a comment; `examples/csharp` shows the convention. The other
sections (audience and expected rating, the loop at three scales, the first session step by step, world rules, what
failing costs, content counts and length, open questions, changes) are for people and agents; `status` reads only the
pitch and the features.

`status -Json` reads all of that, plus the plan, the latest runs, git activity and an inventory of the project, without
judging anything ([json.md](json.md)). The `game` skill (`/game`) does the judging; start every session with it:
1. the first time, it drafts the GDD from the code and confirms it with you section by section;
2. it marks each feature missing, started, works or proven, with evidence, in `plan/STATUS.md`, with a short design and
   architecture review: at most five problems with their evidence (features that serve no kind of fun, scope drift,
   `architecture` warnings, autoloads no decision covers, subagent verdicts nobody acted on);
3. it adds a plan task (`plan -Do add -Feature F3`) for each feature that is not proven;
4. through `plan -Do sync` (experimental), it creates and moves project items. An item you moved since the last run keeps your column: each task
   records the column its item was in (`boardColumn`), so an item that is somewhere else was moved by you;
5. it ends with the three best next tasks to pick from.

Scope rule: before building anything the GDD does not contain, the agent asks whether to add it as a feature or drop it.

The `weekly-review` skill writes `plan/reviews/<date>.md` (done, health, phase, risks) and proposes next week's tasks.
It also reads `docs/kit-notes.md`, the line the agent appends each time the kit got in the way (`init -Agents` or
`-Plugin` creates the file), and proposes up to three kit changes for you to approve; approved ones become kit pull
requests through `/retro`, never on their own.
Run it every Friday as a **local scheduled task in the Claude desktop app**, which can reach the game folder, the kit and the
GitHub CLI at once (a cloud task gets only a fresh clone of a GitHub repository):
1. Code tab → **Scheduled** → **New task** → **Set up manually**.
2. Name `weekly-review`; instructions: `Run the weekly review of this game (the weekly-review skill).`
3. **Advanced settings** → turn on **Only on this computer**; **Local folder**: the game folder.
4. **Trigger**: Weekly, Friday, the time you want (local time, so Athens time on an Athens PC).
5. Create it, then **Run now** once and choose "always allow" for the kit's commands, so later runs do not stall on prompts.

It runs only while the app is open and the computer awake; a missed Friday runs once when the PC wakes. The skill is not
manual-only on purpose: a scheduled prompt can start only skills Claude is allowed to invoke.

## Jam mode, risks, money and exit criteria

`godot-game-plan` also covers what the gates only point to:
- **Jam mode:** a jam of 2 to 9 days starts with `plan -Do init -Profile jam` (`ci/godot/templates/plan-jam.json`):
  five phases sized in days (`timeboxDays`) for a 7-day jam, from the day table of `ci/godot/templates/GDD-jam.md`:
  theme and core feel (1), loop (1), must-haves (3), export and submit (2), then 3 days after the jam for the
  retrospective. Scale `timeboxDays` to the jam; an overrun warns in days. Its gates (`jam.*`) follow the day table:
  `jam.platform` first, `jam.gdd`, `jam.feel`, `jam.loop`, `jam.tests`, `jam.musthaves`, `jam.credits`, `jam.export`,
  `jam.fixes`, `jam.submit`, `jam.retro`. The first question is "browser build?": Godot 4.7 refuses to export C# to the Web
  ([mobile-web.md](mobile-web.md), measured: "Exporting to Web is currently not supported in Godot 4 when using
  C#/.NET"), so a browser jam is made in GDScript.
- **A risk log** at the concept stage (`docs/RISKS.md`, gate `concept.risks`): the top five risks with likelihood,
  impact, and how and when each is retired; a system the developer has never built is one.
- **Budget and runway** (`docs/BUDGET.md`, the optional gate `concept.budget`) as categories the user fills in (people,
  outsourcing, workspace, software, licences, events, marketing, ratings, taxes; cash, payouts, funding), the business
  model, and the fairness rule (never sell an advantage over other players).
- **Sharper alpha and beta exit:** a placeholders table in `docs/TECH-DEBT.md` and `"placeholder": true` entries in
  `assets.json`, both empty for `beta.placeholders`; bug classes A and B, a statement of completion at alpha, and a
  release plan at beta. The marketing cadence and the release ladder are in `godot-store-page`.

## Not covered (yet)

Team roles and live-ops staffing from the studio template (a solo plan has one role). Platform certification for
consoles. Regional ratings. Add them as gates in `plan.json` if they apply.
