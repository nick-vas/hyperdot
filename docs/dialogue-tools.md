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

## Not done

- Building any of them in a copy of the C# example on Godot 4.7.2, importing a dialogue and playing one conversation headless.
- Reading the licences of the NuGet packages Yarn Spinner depends on.
- The fallback the roadmap names, a JSON dialogue graph checked by the `data` and `l10n` runners, because it only makes sense
  if no tool survives the trial.
