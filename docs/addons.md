# Add-ons and GDExtensions

Which popular Godot add-ons to use, their real state on 2026-10-22, how a C# game reaches them, and what `doctor`
checks in a game that uses them. The list started from a user's list of 25 repositories and was cross-checked with
[garciamarquez.dev's ranking](https://garciamarquez.dev/posts/godot-popular-assets/) (Asset Library entries by GitHub
stars, November 2024). Stars, licences and releases were read from GitHub and Codeberg that day; READMEs and
`.gdextension` files from the repositories. Library matching was measured on Godot 4.7.2 (below). Nothing else was
installed or run. A second pass over [awesome-godot](https://github.com/Calinou/awesome-godot) added the section [More add-ons, from awesome-godot](#more-add-ons-from-awesome-godot); [awesome-lists.md](awesome-lists.md) says how.

## How Godot picks a GDExtension's library (measured on 4.7.2)

A `.gdextension` names one library per build in `[libraries]`, keyed by tags such as `linux.release.x86_64`. A key fits
an export when **every** tag is one of the build's features, and the fitting key with the **most tags** wins. Paths are
`res://` or relative to the `.gdextension`'s folder; `[dependencies]` values may span lines:

```ini
[libraries]
linux.release.x86_64 = "libs/rel.so"
linux.template_release.x86_64.mytag = "libs/custom.so"

[dependencies]
linux.release.x86_64 = {
"libs/tr.so": ""
}
```

Exported with Godot 4.7.2 (a throwaway project, the standard build, `--export-release` and `--export-debug`):

- The release export copied `rel.so` and `tr.so`; a preset with `custom_features="mytag"` copied `custom.so` instead (four
  tags beat three).
- The **debug** export, which no key fits, exited 0 with only `WARNING: GDExtension: No "x86_64" library found for
  GDExtension: "res://addons/x/x.gdextension". Possible feature flags for your platform: pc, linux, linuxbsd, s3tc,
  bptc, x86_64, template, debug, template_debug, single`, and shipped no library: the game runs without the extension.

The features each export has, as Godot printed them (every build also has `template`, `debug` or `release`,
`template_debug` or `template_release`, `single`, and the preset's `custom_features`):

| Platform | Features |
|---|---|
| Windows | `pc, windows, s3tc, bptc` and the architecture (`x86_64`, `arm64`) |
| Linux | `pc, linux, linuxbsd, s3tc, bptc` and the architecture |
| macOS (universal) | `pc, s3tc, macos, universal, bptc, x86_64, arm64` |
| Web | `web, s3tc, bptc, wasm32, web_noextensions`, and `threads` or `nothreads` (the default, `variant/thread_support=false`) |
| Android | `mobile, android, etc2, astc` and each enabled ABI (`arm32`, `arm64`, `x86_64`; arm64 alone by default), looked up once per ABI |
| iOS | `mobile, apple_embedded, ios, etc2, astc, arm64` |

Not measured: macOS with one architecture, and Web with `variant/extensions_support` on.

Godot also refuses an extension outside `compatibility_minimum` and `compatibility_maximum`, or without a minimum
(4.7.2's `gdextension_library_loader.cpp`: `"GDExtension configuration file must contain a
\"configuration/compatibility_minimum\" key"`).

## What `doctor` checks

`ci/godot/lib/Addons.ps1`, for each export preset that does not exclude the add-on's folder:

| Finding | Status |
|---|---|
| No `[libraries]` key fits a release build (per architecture) | FAIL |
| No key fits a debug build | WARN |
| The chosen library, or a `[dependencies]` file, does not exist | FAIL |
| An editor-only extension (every key has `editor`, e.g. the git plugin) is exported | WARN |
| No `compatibility_minimum`, a minimum above the project's Godot, or a maximum below it | FAIL |
| `3d/physics_engine="Jolt Physics (Extension)"` on Godot 4.4 or later | WARN |
| The game uses an autoload an add-on's plugin registers, and `project.godot` lacks it | WARN |
| `addons/gut`, `addons/gdUnit4` or `addons/godot-git-plugin` in a preset without an exclusion | WARN |
| `forced_dd3d` in a preset's custom features (Debug Draw 3D drawing in release builds) | WARN |
| An add-on from the known-status list below (`ci/godot/addons-status.json`), by its folder in any letter case or, renamed, by its `.gdextension` file name and `entry_symbol`; one with a Godot range only above it | WARN |
| `addons/<name>/LICENSE*` (or `LICENCE*`, `COPYING*`) and no `assets.json` entry covering the add-on's code; the fix is the entry, with the licence read from the text and `copyright` from its first `Copyright` line (`lib/Assets.ps1`; GUT, gdUnit4 and the git plugin are left out) | WARN |

The autoload rule replaces "plugin not enabled", which would be wrong: `examples/gdscript` keeps `addons/gut` disabled
and GUT's command-line runner works. What breaks a game is an autoload such as Dialogue Manager's `DialogueManager` that
the plugin adds only when enabled; the game's code then finds nothing in an export.

## The add-ons

"C#" is how a C# game uses it. A GDExtension without a wrapper has no typed C# API: `ClassDB.Instantiate`, `Call`,
`Get` and `Set`, as Terrain3D's docs show (`var terrain = ClassDB.Instantiate("Terrain3D");
terrain.AsGodotObject().Call("set_show_region_grid", true);`).

| Add-on | Stars | Licence | Latest (date) | Godot 4.7 | C# | Use it for |
|---|---:|---|---|---|---|---|
| [GodotSteam](https://codeberg.org/godotsteam/godotsteam) | 3,761 (GitHub, archived) | MIT | v4.23.2-gde (2026-10-20) | 4.4+ | `Call`, or community bindings (`godot-steam`) | Steam; it moved to Codeberg on 2026-10-20 |
| [Phantom Camera](https://github.com/ramokz/phantom-camera) | 3,609 | MIT | v0.11.0.3 (2026-07-19) | 4.4+ | Wrapper ships (`PhantomCamera2D.cs`, `PhantomCamera3D.cs`) | Cinemachine-style cameras |
| [Terrain3D](https://github.com/TokisanGames/Terrain3D) | 4,383 | MIT | v1.0.2 (2026-10-17, "4.4 through 4.7") | Yes | `ClassDB`/`Call` | Large editable 3D terrain; its Web libraries are release-only |
| [Dialogue Manager](https://github.com/nathanhoad/godot_dialogue_manager) | 3,935 | MIT | v4.1.0 (2026-09-04, "for Godot 4.7") | Yes | Wrapper: `DialogueManager.ShowDialogueBalloon(...)` | Branching dialogue as text |
| [ProtonScatter](https://codeberg.org/hungryproton/proton_scatter) | 3,017 (GitHub mirror) | MIT; bundled textures are not redistributable | "4.0" (2023) | Not stated | Editor tool | Scattering props and foliage |
| [Beehave](https://github.com/bitbrain/beehave) | 3,307 | MIT | v2.9.3 (2026-08-18, "latest Godot 4.7") | Yes | GDScript only | Behaviour trees in GDScript; C# games use `Example.Core/Ai` patterns or LimboAI |
| [GUT](https://github.com/bitwes/Gut) | 2,764 | MIT | 9.7.1 (2026-07-10) | Yes | GDScript tests | The kit's GDScript test runner |
| [Heightmap terrain](https://github.com/Zylann/godot_heightmap_plugin) | 2,283 | MIT | No releases | 4.6+ | `Call` | Terrain without native libraries (Web) |
| [Debug Draw 3D](https://github.com/DmitriySalnikov/godot_debug_draw_3d) | 1,074 | MIT | 1.7.3 (2026-04-04) | `compatibility_minimum` 4.4.1 | Yes | 3D debug shapes (`godot-debug-tools`) |
| [godot-git-plugin](https://github.com/godotengine/godot-git-plugin) | 960 | MIT, plus THIRDPARTY | v3.3.0 (2026-10-20) | 4.3+ | Editor only | Committing from the editor; never exported |
| [fmod-gdextension](https://github.com/utopia-rise/fmod-gdextension) | 945 | MIT binding; FMOD's own terms (not read) | 6.1.0-4.5.0 (2025-09-20) | Not stated | "This plugin doesn't provide C# bindings to FMOD" | FMOD Studio projects; no Web libraries |
| [Epic Online Services](https://github.com/3ddelano/epic-online-services-godot) | 325 | MIT, plus Epic's SDK terms | 2.3.1 (2026-09-15) | Yes | "GDScript, C#, etc" | Cross-store accounts, lobbies, P2P |
| [lua-gdextension](https://github.com/gilzoide/lua-gdextension) | 469 | MIT | 0.8.2 (2026-07-12) | 4.5+ | Yes | Modding with sandboxed scripts (`godot-modding`) |
| [gdTree3D](https://github.com/JekSun97/gdTree3D) | 383 | MIT | v1.1.0 (2026-09-14) | 4.5+ | `Call` | Procedural trees; desktop only |
| [EIRTeam.FFmpeg](https://github.com/EIRTeam/EIRTeam.FFmpeg) | 318 | MIT, plus FFmpeg | Auto-build (2026-10-07) | Built against 4.7.2 | Not checked | Video beyond Theora; h264 is "patent-encumbered" |
| [iree.gd](https://github.com/iree-gd/iree.gd) | 73 | MIT | v0.1.0 (2026-06-13) | Not stated | Not checked | On-device inference of trained models |

Do not use on Godot 4.7:

- **Godot Jolt** ([godot-jolt/godot-jolt](https://github.com/godot-jolt/godot-jolt), 2,580 stars): "As of Godot 4.4, this
  integration of Jolt Physics is built into Godot itself", and "the only supported versions of Godot are between 4.3 and
  4.6". Set `3d/physics_engine="Jolt Physics"`; the extension's own name is `"Jolt Physics (Extension)"`.
- **godot-steam-audio** ([stechyo/godot-steam-audio](https://github.com/stechyo/godot-steam-audio)): archived on
  2026-10-07, and its README says "Don't expect to be able to ship a game with this extension right now".
- **Godot-PerfBullets** ([Moonzel/Godot-PerfBullets](https://github.com/Moonzel/Godot-PerfBullets)): "works with Godot 4.1
  and 4.2", Windows builds only. Use a `MultiMeshInstance2D` in the game's own code.
- **py4godot** ([niklas2902/py4godot](https://github.com/niklas2902/py4godot)): "don't use this for bigger projects".

### More add-ons, from awesome-godot

The names come from [Calinou/awesome-godot](https://github.com/Calinou/awesome-godot) (the list is CC BY 4.0), checked
against what this page already covered. Everything below was read from each repository on 2026-10-29: the licence file, the
newest tag, the last commit, the Godot version it states and its `.gdextension` or `plugin.cfg`. Dates are the commit date of
the newest tag, not a release page. **Nothing was built or run, so "works on 4.7.2" is unverified for every row**, and the C#
column is judged from `.cs` files and READMEs.

Systems a game ships:

| Add-on | Licence | Latest (date) | Godot | C# | Use it for |
|---|---|---|---|---|---|
| [Input Helper](https://github.com/nathanhoad/godot_input_helper) | MIT | v4.7.0 (2025-06-08) | project 4.4 | `InputHelper.cs`, `using NathanHoad;` | Device detection and rebinding; last commit June 2025, so check it on 4.7 first. Overlaps what `godot-input` teaches |
| [Questify](https://github.com/TheWalruzz/godot-questify) | MIT | 1.6.0 (2025-07-03) | 4.4 in the README, 4.5 in the project | `Questify.cs` wrapper | A graph quest editor and runtime; the best C# quest option of five |
| [DotnetQuestSystem](https://github.com/TRUINGLol/DotnetQuestSystem) | MIT | v1.1.0 (2025-05-08) | 4.4 | C# first, with a `test/` project | A quest system as a .NET library with a thin Godot layer, which `dotnet test` can run without the engine (its tests were not opened) |
| [Health, HitBoxes, HurtBoxes, HitScans](https://github.com/cluttered-code/godot-health-hitbox-hurtbox) | MIT | v5.0.4 (2026-07-21) | 4.5+ | GDScript only | Composable damage nodes in 2D and 3D; about 72 gdUnit4 test files, which run through the kit's `gdunit4` runner |
| [Maaack's Game Template](https://github.com/Maaack/Godot-Game-Template) (with its Menus Template and Scene Loader) | MIT | v1.7.1 (2026-10-28) | 4.7 | GDScript only | Main, options, pause and credits menus, a loading screen and a scene loader; `flows` can drive the menus |
| [Scene Manager](https://github.com/glass-brick/Scene-Manager) | MIT | v2.1.0 (2026-08-20) | 4.7 | GDScript only | Scene transitions through an autoload; its GUT suite runs headless in its CI |
| [GATO](https://github.com/Nokorpo/gato-godot-accessibility-toolkit) | MPL-2.0 (file-level copyleft; graphics under a CC licence; the name is a trademark) | no tags (2026-10-15) | 4.6 | GDScript only | Accessibility parts: input remapper, text to speech, colour-blind filters. `credits` ships the MPL-2.0 text. Pin it by commit |
| [ThemeGen](https://github.com/Inspiaaa/ThemeGen) | MIT | v1.4.0 (2026-05-02) | "4.x" | GDScript at build time | A Theme written as code; the `.tres` it produces is checked by `textsize` and `layout` like any other |
| [Juicee](https://github.com/Kelpekk/Juicee) | MIT | v2.0.0 (2026-10-13) | 4.3 | `csharp/Juicee.cs` singleton | Shake, hit stop and camera effects; young, pin the tag. Overlaps `godot-juice` |
| [NobodyWho](https://github.com/nobodywho-ooo/nobodywho) | EUPL-1.2 (copyleft) | `nobodywho-godot-v12.1.0` (2026-10-09, from its changelog) | 4.6+ | GDScript API, no C# wrapper found | A language model that runs on the player's machine (Rust GDExtension); needs model files. See `godot-llm` |
| [Subtitles Importer](https://github.com/Rubonnek/subtitles-importer) | MIT | v1.1.4 (2026-07-05) | 4.2 | GDScript only | Timed subtitle formats with `AnimationPlayer` links |
| [friflo ECS](https://github.com/friflo/Friflo.Engine.ECS) | MIT | `engine-v4.0.0-preview.2` (2026-05-01); the newest non-preview is `engine-v3.6.0` (date not fetched) | Godot listed, .NET Standard 2.1 to .NET 10 | C# only | An entity component system as a NuGet library; plain C#, so `dotnet test` reaches it |
| [HCoroutines](https://github.com/Inspiaaa/HCoroutines) | MIT | v2.0.1 (2025-03-31) | 4.x | C# only | Coroutines for C#; idle for 19 months, not archived |
| [Godot Google Play Game Services](https://github.com/Iakobs/godot-play-game-services) | MIT | v3.4.0 (2026-07-20) | 4.3+, Android | GDScript-facing Kotlin plugin; C# not documented | Android sign-in and achievements; needs a device and a Google account, so nothing here is CI-checkable |

World, level and physics tools:

| Add-on | Licence | Latest (date) | Godot | Platforms | Use it for |
|---|---|---|---|---|---|
| [godot-rapier-2d](https://github.com/appsinacup/godot-rapier-2d) | MIT | v0.36.0 (2026-10-02) | `compatibility_minimum` 4.7 | A Rust GDExtension for 2D and 3D physics. The checked-in `.gdextension` lists windows, linux, android and macos but no `web` or `ios` key (the README claims web through release builds, which was not read) | A physics server swap, so C# uses the normal API; the one here that changes physics for tests |
| [TerraBrush](https://github.com/spimort/TerraBrush) | MIT | 0.15.0Beta (2026-10-20) | 4.5+ | C++ GDExtension with web (experimental), android and ios keys | Editable terrain with C# wrapper nodes; sits next to Terrain3D |
| [godot-voxel](https://github.com/Zylann/godot_voxel) | MIT | v1.7x (2026-08-20) | the GDExtension edition needs 4.4.1+ | Mostly an engine module, which needs a custom Godot build; the GDExtension edition is "less tested", with no web in its platform list | Voxel terrain; C# with the extension is "not well defined" |
| [YATI](https://github.com/Kiamo2/YATI) | MIT | v2.2.10 (2026-10-05) | "tested on 4.7.2", needs 4.3+ | Pure script, with a GDScript and a C# build | Tiled map import |
| [func_godot](https://github.com/func-godot/func_godot_plugin) | MIT | 2025.12 (2025-12-27) | "Godot 4" | Pure GDScript | Quake-style `.map` levels (TrenchBroom). GodotVMF does the same for Source maps |
| [Cyclops Level Builder](https://github.com/blackears/cyclopsLevelBuilder) | MIT-style text without a title | v1.5.2 (2026-10-24) | 1.5.x needs 4.7+ | GDScript editor plugin; the repository uses Git LFS, so clone with LFS | Brush-based level building in the editor |

Developer tools, which a game must never ship:

| Tool | Licence | Latest (date) | Use it for |
|---|---|---|---|
| [godot-gdscript-toolkit](https://github.com/Scony/godot-gdscript-toolkit) | MIT | 4.5.0 (2025-10-09) | `gdlint` and `gdformat --check` for the GDScript half, in CI; idle for a year |
| [Godot Doctor](https://github.com/codevogel/godot_doctor) | MIT | 2.2.0 (2026-07-23) | Scene and resource validation in the editor and from a CLI, with GDScript and C# validations. It overlaps `validate` and `doctor`; `doctor` could look for `addons/godot_doctor/` |
| [gdvm](https://gdvm.io) | GPL-3.0-or-later | v0.16.0 (2026-08-10) | A Godot version manager with C# variants and a `setup-gdvm` action. GPL is fine for a tool and wrong for a game |
| [ShipThis](https://github.com/shipth-is/cli) | MIT | v0.1.61 (2026-10-14) | Mobile builds and store uploads through a paid hosted service (prices and terms not read); C# on 4.3+ with the .NET editor |

Authoring tools, also never shipped (read from their repositories on 2026-10-29; none was run, and whether they run headless
was not checked):

| Tool | Licence | Last commit | Use it for |
|---|---|---|---|
| [Sprite Fusion pixel snapper](https://github.com/Hugo-Dz/spritefusion-pixel-snapper) | MIT | 2026-10-20 | A command line (`spritefusion-pixel-snapper <input> <output> [colours]`) that snaps AI-made pixel art to a true pixel grid, before `shot`'s palette check |
| [Sprite Fusion sprite normals](https://github.com/Hugo-Dz/spritefusion-sprite-normals) | MIT | 2026-10-20 | Normal maps for pixel-art sprites (2D lighting) |
| [Material Maker](https://github.com/RodZill4/material-maker) | MIT | 2026-10-24 | Procedural textures, made in Godot |
| [LDtk](https://github.com/deepnight/ldtk) | MIT | 2026-10-06 | A 2D level editor with a JSON project file; no Godot importer was assessed |
| [Tiled](https://github.com/mapeditor/tiled) | GPL app, BSD-2 library | 2026-10-24 | Tile maps, next to YATI; the maps you make are your own files |
| [Folded Paper Engine](https://github.com/papercraftgames/folded-paper-engine) | MIT | 2026-10-27 | Gameplay defined in Blender, Godot 4.4+ and Blender 4.4+; its README calls it an MVP |

Two things to know about all of them. The kit sets up official Godot, so a game that needs a **custom engine module**
(godot-voxel's module edition, Voxelman, Texture Packer, Godex, FMOD GD4) cannot be tested or exported with it, and `doctor`
finds nothing to check because such a game has no `addons/` folder for it. And where an extension lacks a platform key,
`doctor`'s library check already reports it for the presets the game exports.

Do not use: **godot-luaAPI** ([WeaselGames/godot_luaAPI](https://github.com/WeaselGames/godot_luaAPI)) says "Archived!" on its first
README line and was built for Godot 4.1 (last commit 2024-12-28); use lua-gdextension above. `doctor` now flags
`addons/luaAPI` from the known-status list; the folder inside a release zip is not confirmed yet (`roadmap.md`).

Read and left out, with the reason: Quest Manager (Questify covers it), QuestSystem (another GDScript quest manager),
Inventory Manager (trivial to write), Shaker (unmaintained since 2024-09), Godot Radial Menu (shader-drawn, poor for gamepad
focus and screen readers), Nodot (pre-1.0 and too broad), Importality (the kit says to export PNGs from Aseprite),
License Manager (`assets.json` and `credits` do this), GodotVMF (func_godot's sibling), Godot SQLite (named further down this page),
godot-actions (pins Godot 3.5), asdf-godot, Godot Package Manager (Godot 3, abandoned since 2022), godot-launcher
(deprecated), GodotSx, Gedis, godot-playfab (0.0.x tags, last tag 2022), Godot Shader Warmup (a Windows research
project), Script-IDE (editor only), gd2cs.py and codetranslator (regex ports of old Godot), Godot Torrent, Godot NDI and
spout-gd (desktop only, with their own runtimes), obs-websocket-gd (tested on 4.0.2), Polygon 2D Fracture, AntialiasedLine2D,
SimpleGodotCRTShader, PixelPen, AnimSheet, 3D Auto Collision Generator.

### The known-status list

`doctor` finds the four above in a game from `ci/godot/addons-status.json`: each entry's folder under `addons/`, its
`.gdextension` file name and `entry_symbol` (for a copy in another folder), the Godot it stops at (`godotMax`), why and
the fix. Each name was confirmed on 2026-10-23 from the add-on's repository at its newest commit, read with git (the
`confirmed` field of each entry says which files):

| Add-on | Folder | `.gdextension` | `entry_symbol` | From |
|---|---|---|---|---|
| Godot Jolt | `addons/godot-jolt` | `godot-jolt.gdextension` | `godot_jolt_main` | `CMakeLists.txt`, `cmake/GodotJoltUtilities.cmake`, `cmake/GodotJoltVersionInfo.cmake` (4.3 to 4.6) |
| godot-steam-audio | `addons/godot-steam-audio` | `libgodot-steam-audio.gdextension` | `init_extension` | the `.gdextension` in `project/addons/godot-steam-audio/bin/` |
| Godot-PerfBullets | `addons/PerfBullets` | `spawner.gdextension` | `spawner_library_init` | `addons/PerfBullets/bin/spawner.gdextension` (no tags or releases) |
| py4godot | `addons/py4godot` | `python.gdextension` | `initialize_pythonscript` | `create_plugin.py`, `build_resources/gdextension_template.gdextension` |

On 2026-10-29 the names were checked again against the newest release zip of each add-on that has one (listed with Python's
`zipfile`, never extracted or run; the `releaseZip` field of each entry records the tag, the asset, the folder prefix
inside the zip and the date): `godot-jolt_v0.16.0-stable.zip` holds `addons/godot-jolt/godot-jolt.gdextension`,
`godot-steam-audio-v0.3.1.zip` holds `addons/godot-steam-audio/bin/libgodot-steam-audio.gdextension`, and `py4godot.zip`
(4.7-alpha21, 243 MB) holds `install_dir/addons/py4godot/python.gdextension`, so the folder to copy sits under a wrapper
folder (`prefix` is `install_dir/`). Each `entry_symbol` read from the zip's `.gdextension` is the recorded one. Godot-PerfBullets
has no tags or releases, so its names stay those of the repository.

Not confirmed: whether Godot Jolt, Godot-PerfBullets and py4godot are archived. From the sandbox that ran the check GitHub's
API and the repository pages answered 403 (only `raw.githubusercontent.com`, `git` and release downloads by their exact URL
were reachable), so `archived` is `null` until the canary reads it. Nor could the newest release be looked up there: the
asset names above were found by trying the names the repositories' own workflows suggest.

The weekly canary runs `ci/godot/tools/Update-AddonStatus.ps1`: it records each repository's newest commit (`head`) and
`archived`, checks that the file each entry names still holds its `entry_symbol`, and reads the newest release's zip. It
downloads the asset the entry's `releaseZip.asset` names (`{tag}` stands for the release's tag, up to 600 MB, to a new
temporary folder that is deleted after), lists its files and compares them with the entry: a folder under another prefix is
applied, a new tag whose zip still matches is applied (`releaseZip.tag`, `checked`), and a missing `addons/<name>/` folder or
`.gdextension` file, an asset that is gone, or a repository that now has a release and no `releaseZip` is reported. It builds
the download URL from the repository, tag and asset name, not from the API's answer. Without a token the API allows 60 calls
an hour, which is enough; an API or download that fails is a note and the entry stays as it was. It opens an issue for what needs a
person, such as new commits on an add-on that may now support Godot 4.7. Statuses are changed by hand.

Not add-ons: [gdext](https://github.com/godot-rust/gdext) (Rust, 5,319 stars, MPL-2.0), [graphics.gd](https://github.com/quaadgras/graphics.gd)
(Go), [godot-cpp-template](https://github.com/godotengine/godot-cpp-template) (the reference for writing a GDExtension;
[nathanfranke/gdextension](https://github.com/nathanfranke/gdextension) is older and has no macOS or iOS) and
[godot-lang-support](https://github.com/Godot-Languages-Support/godot-lang-support) (a list).

Corrections to the list as received: Terrain3D is `TokisanGames/Terrain3D`; `Konclan/iree.gd` does not exist (the
project is `iree-gd/iree.gd`); ProtonScatter's GitHub repository is a mirror of Codeberg.

On garciamarquez.dev's page but not above, all Asset Library add-ons: [LimboAI](https://github.com/limbonaut/limboai)
(behaviour trees and state machines; C# needs its module build, `docs/game-ai.md`), [Godot State Charts](https://github.com/derkork/godot-statecharts),
[Gaea](https://github.com/gaea-godot/gaea) (procedural generation, `godot-procgen`), [SmartShape2D](https://github.com/SirRamEsq/SmartShape2D),
[Metroidvania System](https://github.com/KoBeWi/Metroidvania-System), [Panku Console](https://github.com/Ark2000/PankuConsole)
(`godot-debug-tools`), [Orchestrator](https://github.com/CraterCrash/godot-orchestrator) (visual scripting),
[Godot-SQLite](https://github.com/2shady4u/godot-sqlite) (`godot-saves`, `godot-data`), [Aseprite Wizard](https://github.com/viniciusgerevini/godot-aseprite-wizard)
(`godot-asset-pipeline`), COGITO (moved to [Codeberg](https://codeberg.org/Phazorknight/Cogito)), Kenney's starter kits
and a tactical RPG demo. Rivet, 7th on the page, now describes itself as "the primitive for stateful workloads. Built
for AI agents", not a game backend.

## Licences

Every add-on's code ships with the game, so its licence notice does too: an `assets.json` entry for `addons/<name>/**`
lets `credits` write it (`godot-asset-pipeline`), and `doctor` writes that entry for an add-on with a licence file and none. Some add-ons wrap SDKs with their own terms (FMOD, Steamworks, Epic Online
Services, Steam Audio's "proprietary libraries"), ProtonScatter's textures "cannot redistribute them on their own", and
EIRTeam.FFmpeg's h264 needs a check of patent law where the game sells.
