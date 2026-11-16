---
name: new-game
description: Use when the user starts a new game from an idea, describes a game they want to make, or has a folder with no GDD and little or no code yet.
---

# New game: from a description to a draft GDD

The user describes the game in their own words; the kit asks what that leaves open, from a fixed bank of questions
(`${CLAUDE_PLUGIN_ROOT}/ci/godot/templates/brief-questions.json`), and writes a draft `docs/GDD.md` and `docs/STYLE.md`.
You do not choose questions, word them, guess answers or skip any: `brief` decides, you relay.

```powershell
pwsh ${CLAUDE_PLUGIN_ROOT}/ci/godot/hyperdot.ps1 brief -Do start -TextFile <file> -Project <folder> -Json
pwsh ${CLAUDE_PLUGIN_ROOT}/ci/godot/hyperdot.ps1 brief -Project <folder> -Json                      # the next questions
pwsh ${CLAUDE_PLUGIN_ROOT}/ci/godot/hyperdot.ps1 brief -Do answer -Id <id> -Value "<answer>" [-Quote "<sentence>"] -Project <folder> -Json
pwsh ${CLAUDE_PLUGIN_ROOT}/ci/godot/hyperdot.ps1 brief -Do gdd -Project <folder> -Json             # once complete
```

`brief` needs no Godot project: the folder can be empty. `-Project` is the game's folder (default: the current one).

## 1. The description

1. Ask the user to describe the game in their own words, as much or as little as they like. Do not prompt with a list.
2. Save their reply word for word to a file (e.g. `docs/idea.txt`) and run `brief -Do start -TextFile docs/idea.txt`.

## 2. Answers the description already gives

Run `brief -Json` and read `brief.next`. For each question listed there, answer it from the description only when a
sentence in it states the answer outright: pass that sentence, copied exactly, as `-Quote`, and the option it states as
`-Value`. `brief` refuses a quote that is not in the description word for word, and a value that is not an option.

- An answer that needs inference ("a puzzle game" does not say "single player") is not stated: leave it to step 3.
- Never quote for one question a sentence that answers a different one.
- Repeat `brief -Json` after each round: answers open new questions (`when`), and close others.

## 3. Ask the rest, as written

Ask `brief.next` with the AskUserQuestion tool, all of them in one call (at most four): `question` as the question,
`header` as the header, each of `options` as an option with its `label` and `description` unchanged, `multiSelect` as
given. A `text` question has no options: ask it in plain words and take the reply as written. Record each reply with
`brief -Do answer -Id <id> -Value "<reply>"` (no `-Quote`); several options are comma-separated. For "Other", pass the
user's words: `brief` refuses anything outside the options (a `term` question takes any gameplay genre from the kit's
list, and suggests the nearest on a typo), and you ask that question again with its refusal. Repeat until
`brief.complete` is true.

`brief.conflicts` lists answers that cannot stand together (C# with a Web export, touch controls with no touch screen,
no kind of fun at all), each with its `fix`: tell the user, ask the question the fix names, and record the new answer.

## 4. The draft

Run `brief -Do gdd`. It writes `docs/GDD.md` (draft, following the feature grammar `doctor` checks) and, when there is
none, `docs/STYLE.md`, then lists `nextSteps`: create the Godot project if there is none (the .NET build for C#), run
`plan -Do init` with the profile it names (`jam` or `full`), then `/game` to confirm the GDD section by section. Tell
the user `weeklyHours` from the result: it goes into `plan/plan.json` with them. The sections the brief does not cover
(core fantasy, audience, the first session, world rules, content) stay as the template's prompts for `/game`.
