# AGENTS.md

Godot 4.7.2 game. Tests, builds and checks go through Hyperdot (`{{SUITE}}`, PowerShell 7). Add `-Json -Quiet` and read `ok` and `error.code`;
`-Quiet` keeps Godot's output in the log file the JSON's `log` field names.

Start each session with `/game`: where the game stands and what to do next. `/kit` lists the kit's commands and skills.

```powershell
pwsh {{SUITE}} test -Json -Quiet      # build + every test runner; failures carry file, line, message
pwsh {{SUITE}} doctor -Json           # misconfiguration, each with a fix
pwsh {{SUITE}} help                   # every command, flag and skill
```

## Rules

- Test first: failing test, make it pass, run the whole suite (`godot-test-loop`). Never skip, delete or loosen a test to get green.
- Done means a fresh `test -Json -Quiet` with `ok: true` (`verify-before-done`).
- Engine-free logic lives in plain classes, testable without Godot. Test code and packages stay out of release builds; run `doctor` after touching csproj, `project.godot` or export presets.
- Screenshots, benchmarks and export launches go to the `godot-verifier` subagent, which returns a short verdict.
- A change that adds a system, an autoload or a dependency between scenes goes to the `godot-architect` subagent first; its
  decision in `docs/decisions/` is accepted before code is written.
- `docs/GDD.md` is the scope. Before building anything it does not contain, ask: add it as a feature, or drop it. Tag each test that proves a feature with `GDD:F<n>`.
- Game-specific lessons are in `docs/lessons.md`; read it before changing a system it mentions.
- Push a branch once, when the work is done and the full local test has passed; put a status or plan update in the same push.
- A commit a player would notice gets a `Marketing: <the change, in a player's words>` trailer (and `Marketing-Visual: yes` when it is worth a clip); the weekly brief reads only those.
- When the kit gets in the way (a wrong flag, a confusing error, a missing check), append one line to `docs/kit-notes.md`.
- End each reply with `Certainty: NN%` and a clause saying what it rests on: what was run or read, and what was not checked.
