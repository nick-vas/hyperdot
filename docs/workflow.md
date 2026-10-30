# Which command, when

The kit has many commands and no fixed order. This page says when to run each one, and in which combinations.
`status` answers the same question for your game right now: it lists `suggestedCommands` with a reason each
(`hyperdot.ps1 status`, "Run next:" lines in the text, `suggestedCommands[]` in `-Json`; [json.md](json.md)).
Both read one table, [`ci/godot/workflow.json`](../ci/godot/workflow.json), and `Test-Workflow.ps1` holds this page to it.

## By moment

| When | Run | Why |
|---|---|---|
| After every change | `test` | Builds and runs every runner the project has. Done means a fresh full run with ok: true. |
| After editing project.godot, a csproj, export presets or an add-on | `doctor` | Finds setup mistakes that break CI or ship a broken build. |
| After a UI, scene or text change | `shot` | Real screenshots, text cut off in other languages, colour-blind views, the palette. |
| After a sound change | `audio` | Loudness of each sound and of the mix. |
| Before opening a pull request | `test` and `doctor` | The CI workflow runs the same two. |
| At the end of a milestone | `export -Run`, `bench`, `playtest` | A build that starts, frame times and draw calls, then heat maps from play sessions. |
| Before an alpha or beta, and for a Steam Deck or server game | `deck`, `soak` | The Deck check at 1280x800, and memory over a long session. |
| Before a release | `doctor`, `credits`, `export` | Store art and Steam files, the credits file, a versioned build. |
| Once a week | `status`, `plan`, `telemetry` | Where the game stands, the next gates, and how the kit's own runs are going. |

## By phase

Each phase adds commands to the ones before it ([plan.md](plan.md) has the gates).

| Phase | Add |
|---|---|
| Concept, prototype | `plan`, `test`, `doctor` |
| Vertical slice | `export -Run`, `shot` |
| Production | `bench`, `audio`, `playtest` |
| Alpha and beta | `deck`, `soak`, `shot -Locale`, `shot -ColorVision` |
| Launch | `credits`, and the store and Steam checks in `doctor` |

A game jam plan has five phases (loop, build, ship, after); they map to the same stages, so the same list applies.

## Combinations

- **`test` first.** A red `test` makes every other result noise; fix it, then run the rest.
- **`doctor` before `export`.** It names a missing preset, template or icon in seconds; an export finds it after the build.
- **`bench`, `shot` and `audio -Mix` need a display** (a headless Linux box needs Xvfb; see [usage.md](usage.md)). `test`, `doctor`, `plan`, `status` and `credits` do not.
- **One change, two commands:** a scene edit is `test` then `shot`; a csproj or preset edit is `doctor` then `test`.
- **A milestone is a bundle:** `test`, `doctor`, `export -Run`, `bench`, `status`. `status` last, so it reads the runs you just made.

## What `status` suggests

A rule fires when a command's last run (`.godot/hyperdot-history.jsonl`) is missing, failed, older than the files it covers
(for example a `.tscn` edited after the last `shot`), or older than a set number of days (`bench` after two weeks in alpha, `export` after 30 days at launch).
Rules for a later phase wait until the plan reaches it; without a plan only the rules that apply to every phase run.
Each command is suggested once, with the first reason that applies. It does not run anything.

To change a rule, edit `ci/godot/workflow.json`; the shipped plans' phases must keep a stage in it.
