# Dialogue tools for Godot 4.7: what each is, read from its repository

Checked on 2026-10-29 from a shallow clone of each repository's default branch (files read, nothing built or run).
Release dates are the date of the tag's commit. **None of them has been tried in a game here**: the trial in a copy of the
C# example (build, import, play one conversation headless) was blocked in this session, so "works on 4.7.2 with C#" below
means what the project's own files and README say, not a result. The roadmap keeps the trial.

| | [Dialogue Manager](https://github.com/nathanhoad/godot_dialogue_manager) | [Yarn Spinner for Godot (C#)](https://github.com/YarnSpinnerTool/YarnSpinner-Godot) | [godot-ink](https://github.com/paulloz/godot-ink) | [Dialogic 2](https://github.com/dialogic-godot/dialogic) | [inkgd](https://github.com/ephread/inkgd) |
|---|---|---|---|---|---|
| Licence (the repository's `LICENSE`) | MIT, Nathan Hoad and contributors | MIT, Secret Lab and Yarn Spinner contributors; the core library repository is MIT too | MIT, Paul Joannon | MIT, Emilio Coppola | MIT, inkle Ltd (the ink runtime it ports) |
| Latest release | v4.1.0, 2026-09-04 (last commit 2026-10-25) | v0.3.23, 2026-10-06 (last commit 2026-10-22) | v1.1.2, 2024-02-12 (last commit 2026-07-04, an authors file) | tag 2.0-alpha-20; `plugin.cfg` says "2.0-Alpha-21 WIP" (last commit 2026-08-30) | 0.5.0, 2023-08-28 (last commit 2023-12-08) |
| Godot it states | "for Godot 4.6+"; older majors for 4.4 and 4.5 (v3.10) and for 4.3 | its project file uses `Godot.NET.Sdk/4.7.2`; the changelog says the sample moved to 4.7.2 | its project file uses `Godot.NET.Sdk/4.4.1`; the README says Godot 4 | "requires at least Godot 4.5" | "compatible with Godot 4.2+, but has no official releases yet": use the `godot4` branch |
| C# | a C# wrapper (`DialogueManagerRuntime`, `addons/dialogue_manager/DialogueManager.cs`, `docs/CSharp.md`) over a GDScript runtime | C# only (a separate GDScript project exists) | C# only | no C# mentioned in its README | none: pure GDScript, which its README says is slower than the C# runtime |
| What a project takes on | the add-on folder | NuGet packages: YarnSpinner and YarnSpinner.Compiler 3.2.2, Antlr4.Runtime.Standard 4.13.1, Google.Protobuf 3.31.1, CsvHelper 12.3.2, System.Text.Json 8.0.6, FileSystemGlobbing 8.0.0 | the add-on folder; its `GodotInk.props` downloads the ink compiler and runtime v1.2.0 from GitHub releases during the build | the add-on folder and its auto-updater | the add-on folder |
| Dialogue lives in | `.dialogue` text files | `.yarn` text files and a `.yarnproject` | `.ink` text files | its own timeline and character resources, edited in the editor | `.ink` text files |

## Reading it

- **Licence is not the deciding factor:** all five repositories are MIT. The NuGet packages Yarn Spinner pulls in have their own
  licences, which were not read.
- **For a C# game on 4.7.2**, two are current and say they support it: Dialogue Manager (a C# wrapper over its GDScript
  runtime, 4.6 or newer) and Yarn Spinner for Godot (written in C#, already on 4.7.2, with more NuGet dependencies).
- **godot-ink** is C# but its last release is from February 2024 against Godot 4.4.1, and its build downloads from GitHub:
  a CI runner with no network, or an export without internet, fails. Treat it as at risk until it is tried.
- **Dialogic 2** is an alpha, GDScript-first, with its own editor resources instead of text files, so neither the `data`
  nor the `l10n` runner can read its dialogue.
- **inkgd** has no release for Godot 4 and no commit since 2023.
- **Text formats help the kit.** `.dialogue`, `.yarn` and `.ink` are plain text: the `data` runner's `names` rule can check
  character names in them, and a line's translation key can be checked as the `l10n` runner checks translations. Nothing
  here has wired that up yet.

## Dialogue Manager 4 and Yarn Spinner for Godot, side by side

The two current choices for a C# game on 4.7.2. The snippets follow the patterns of each project's own docs and samples
(Dialogue Manager's `docs/*.md`, Yarn Spinner's `Samples/`); they were **not compiled or run** here.

### The same scene in each

Dialogue Manager, `guard.dialogue`:

```
~ start
Guard: Halt, {{Player.Name}}. State your business.
- Deliver a parcel [if Quest.HasParcel /]
	Guard: Pass. [ID:GUARD_PASS]
	$> Quest.Deliver()
	=> END
- Bribe the guard [if Player.Coins >= 10 /]
	Guard: I saw nothing.
	=> END
- Leave
	=> END
```

Yarn Spinner, `guard.yarn`:

```
title: Guard
---
<<declare $coins = 0 as number>>
<<declare $has_parcel = false as bool>>
Guard: Halt. State your business.    #line:guard01
-> Deliver a parcel <<if $has_parcel>>
    Guard: Pass, {get_random_string()}.    #line:guard02
    <<Unlock WorldNode north_gate>>
-> Bribe the guard <<if $coins >= 10>>
    <<set $coins = $coins - 10>>
    Guard: I saw nothing.    #line:guard03
-> Leave
===
```

### Running it from C#

```csharp
// Dialogue Manager: you walk the lines yourself (or call ShowDialogueBalloon for its example balloon).
using DialogueManagerRuntime;
var dialogue = GD.Load<Resource>("res://guard.dialogue");
var line = await DialogueManager.GetNextDialogueLine(dialogue, "start");
while (line != null)
{
    GD.Print($"{line.Character}: {line.Text}");
    var next = line.Responses.Count > 0
        ? line.Responses.First(r => r.IsAllowed).NextId     // a real UI lets the player choose
        : line.NextId;
    line = await DialogueManager.GetNextDialogueLine(dialogue, next);
}
DialogueManager.DialogueEnded += (Resource r) => GD.Print("done");
```

```csharp
// Yarn Spinner: a DialogueRunner node drives line and option views; you start a node and listen.
_dialogueRunner = GetNode<DialogueRunner>(_dialogueRunnerPath);
_dialogueRunner.onDialogueComplete += OnDialogueComplete;
_dialogueRunner.StartDialogue("Guard").Forget();
```

### Giving the dialogue game state and actions

```csharp
// Dialogue Manager: state is whatever the dialogue can reach (autoloads, DialogueStateContext nodes, [GlobalClass] types).
[GlobalClass]
public partial class Player : RefCounted
{
    public static string Name = "Mira";
    public static int Coins = 3;
}
```

```csharp
// Yarn Spinner: variables live in a variable storage, actions are attributes on public methods.
[YarnCommand]                         // <<Unlock WorldNode north_gate>>: WorldNode is the name of the node that owns the method
public void Unlock(string doorId) { /* ... */ }

[YarnFunction("get_random_string")]   // {get_random_string()} in a line
public static string GetRandomString() => "friend";

// _storage.TryGetValue<float>("$coins", out var coins);   // InMemoryVariableStorage; GetAllVariables / SetAllVariables for saves
```

### Capabilities and weaknesses

| | Dialogue Manager 4.1.0 | Yarn Spinner for Godot 0.3.23 |
|---|---|---|
| Language | Its own script-like text: `Name: line`, `- response`, nesting by indent, `~ cue` and `=> jump`, `=> END` | The Yarn language: nodes with a `title:` header, `-> options`, `<<commands>>`, `{expressions}`; shared with Yarn Spinner for Unity |
| Branching and logic | `if`/`elif`/`else`, `match`, `while`, conditions on a response, inline `[if]`, random lines with weights (`%`) | `<<if>>`/`<<elseif>>`, `<<set>>`, typed `<<declare>>`, `<<jump>>`, `<<once>>`, line groups (`=>`) for barks, `visited("Node")`, conditions on an option |
| Game state | Stateless runtime: the game is the authority; dialogue reads autoloads, scene nodes and `[GlobalClass]` types by name | Variable storage (in memory by default; a SQLite sample); `GetAllVariables` / `SetAllVariables` for saving |
| Calling the game | `$> Thing.Method()`, async C# methods that the dialogue awaits | `[YarnCommand]` and `[YarnFunction]` attributes, with a source generator; typed arguments, arrays |
| Text effects | BBCode, `[wait=N]`, `[speed=N]`, `[next=auto]`, random inline `[[a\|b]]` | Yarn markup; BBCode only through a view that converts; a palette resource for colours |
| Translations | Godot's own `tr` with CSV or PO files; stable keys with `[ID:KEY]`; the dialogue files join the template export | Auto-generated line IDs (`#line:...`) and a per-language CSV in Yarn Spinner's own format, not Godot's |
| Tooling | An in-editor dialogue editor with error checking, a debugger tab with line history | A `.yarnproject` resource and import that compiles all scripts on change, a VS Code extension, per-line metadata tags |
| UI | An example balloon scene to copy | `LineView`/`OptionsView` and several themed samples (visual novel, space, characters) |
| C# fit | A wrapper (`DialogueManagerRuntime`) over a GDScript runtime; members are found by name at run time | Written in C# on the YarnSpinner 3.2.2 library; typed attributes |
| **Weaknesses** | Targets Godot 4.6+ only (older Godot needs 3.10 or 3.3); a GDScript runtime inside a C# game; names are resolved at run time, so a wrong member name fails when the line plays; no visual graph; being stateless, saving dialogue progress is the game's job | Its README calls the project work in progress with no official support, and it is pre-1.0 (0.3.x); a long NuGet list (Antlr, protobuf, CsvHelper, System.Text.Json and more); scripts must be compiled by the editor plugin, so a headless import is part of CI; custom CSV, not Godot's; `[YarnCommand]` is addressed by node name in the script, which is fragile; documentation is mostly on an external site that points at the Unity docs |
| What a check can read | The dialogue is plain text: the `data` runner's `names` rule and a line-ID check work on it; conditions are free-form GDScript-like code a check cannot evaluate | The scripts are plain text too, and each line has an ID in the file, which suits an `l10n` check; the compiler reports script errors at import |

## Not done

- Building any of them in a copy of the C# example on Godot 4.7.2, importing a dialogue and playing one conversation headless.
- Reading the licences of the NuGet packages Yarn Spinner depends on.
- The fallback the roadmap names, a JSON dialogue graph checked by the `data` and `l10n` runners, because it only makes sense
  if no tool survives the trial.
