# What the kit took from awesome-godot and the awesome project

Two sources were read on 2026-10-29: [Calinou/awesome-godot](https://github.com/Calinou/awesome-godot) (a list of Godot
projects, tools and add-ons; **CC BY 4.0**, last commit 2026-10-27, 349 entries) and
[sindresorhus/awesome](https://github.com/sindresorhus/awesome) (the list of lists and the rules a list has to meet; last
commit 2026-09-02). Names came from the lists; every fact in the kit's documents was read from the repository it
describes, not from the list. Nothing was built or run, because the permission check refuses to build third-party code in
this setup.

## awesome-godot

Its Godot 4 plugins, modules, editor-support, tools and template sections were compared with
[addons.md](addons.md) and the skills. About 80 entries were not mentioned anywhere. About 60 of those repositories were
read (licence file, newest tag, last commit, the Godot version it states, `.gdextension` or `plugin.cfg`, whether a C# API
exists). What came of it:

- **[addons.md](addons.md) has a new section, "More add-ons, from awesome-godot"**: 24 rows in three tables (systems a game
  ships, world and physics tools, developer tools a game must never ship), a list of what was read and left out with the
  reason, and one note: the kit sets up official Godot, so a game that needs a custom engine module cannot be tested or
  exported with it. godot-luaAPI is marked do-not-use ("Archived!" on its first README line).
- **Four skills got one short note each**: `godot-ui-accessibility` (GATO, Subtitles Importer, ThemeGen),
  `godot-ui-flows` (Maaack's menus), `godot-juice` (Juicee), `godot-llm` (NobodyWho and its copyleft licence). `godot-input`
  has no note because it is within 150 bytes of the 16 KB limit; Input Helper is in the table.
- **No `doctor` check was added.** None of the add-ons has a failure that the existing add-on and GDExtension checks would
  miss; the one candidate (a model file for NobodyWho) would be a guess.
- **Licences to watch**: GPL-3.0 for gdvm (a developer tool, never shipped), MPL-2.0 for GATO (file-level copyleft; `credits`
  ships the text), EUPL-1.2 for NobodyWho, the NDI and FMOD SDKs' own terms. The list's own text is CC BY 4.0, so this page
  and the addons.md section credit it.

Projects the kit could use as targets for a field test (`doctor`, `test` and `export` on someone else's real game), from the
list's Templates section, read from clones: [Godot C# Template](https://github.com/CSharpGodotTools/Template) (MIT, Godot 4.7,
about 450 C# files, a build-and-test workflow that is disabled), [Maaack's Game Template](https://github.com/Maaack/Godot-Game-Template)
(MIT, 4.7, GDScript) and [Crystal Bit's template](https://github.com/crystal-bit/godot-game-template) (MIT, 4.7, GDScript).
None was run: this session has no Godot. It is the owner's call whether to spend a session on it (`roadmap.md`).

## sindresorhus/awesome

The list itself is an index of topic lists, so it contributes pointers and rules, not facts.

**Rules worth keeping** (from its manifesto and pull request template): say *why* an entry is on the list, not only what it
is (the "Use it for" column of [addons.md](addons.md) does); keep a narrow scope and link to the list that covers the rest;
keep entries consistent; leave stuff out rather than include too much. These match how the kit's tables are written.

**What the kit will not do**: submit itself to the list. Its pull request template says fully AI-generated pull requests are
not accepted, asks for a reviewed list at least 30 days old, and wants reviews of four other pull requests from the
submitter. That is for the owner to decide, as a person.

**Related lists, by their own repositories** (licence file and last commit read from a clone; entries were counted, not
judged one by one):

| List | Licence | Last commit | Entries | Use for the kit |
|---|---|---|---|---|
| [awesome-learn-gamedev](https://github.com/notpresident35/awesome-learn-gamedev) | CC0 | 2026-06-01 | ~257 | Read by keyword (about 70 of 257 link lines): learning links for people; a few leads: Open Dyslexic (a font), Polyglot Gamedev (translation words) and Is This Arabic (RTL pitfalls), none opened; nothing Godot-specific or usable from a CLI |
| [awesome-game-production](https://github.com/vhladiienko/awesome-game-production) | CC0 | 2026-05-04 | ~71 | Read entry by entry (86 links): no QA, playtesting or CI section; the useful entries are a few scheduling and project-method pages, listed below |
| [magictools](https://github.com/ellisonleao/magictools) | MIT | 2026-10-28 | ~68 sections | Read entry by entry (428 links): about 150 are other engines and libraries, about 120 are art tools for humans; six authoring tools are in [addons.md](addons.md) |
| [awesome-open-source-games](https://github.com/michelpereira/awesome-open-source-games) | CC0 | 2026-10-21 | ~459 | The list marks no engine; only four Godot games are named, see below |
| [game-datasets](https://github.com/leomaurodesenv/game-datasets) | CC BY 4.0 | 2026-10-25 | ~198 | Read by keyword (about 60 of 198): Kaggle-style data; Steam Database and the Steam Web API are the only pointers for the Steam skill; the LICENSE file is CC BY 4.0 but the README footer says CC BY-SA 4.0, so treat it as the stricter |
| [awesome-game-engine-dev](https://github.com/stevinz/awesome-game-engine-dev) | CC0 | 2026-08-17 | ~1,028 | Read in part (the audio, asset, debugging and format sections, about 90 entries): engine internals; its legend marks each entry public domain, permissive, copyleft or unknown, a scheme `assets.json` already has |
| [awesome-steam-deck](https://github.com/airscripts/awesome-steam-deck) | CC0 | 2026-09-12 | ~178 | Mostly for players. For a developer: Gamescope, MangoHud, ProtonDB, Deck Verified, the official site and nine more entries; the kit's `deck` and `godot-steam-deck` already cover the Steamworks side |
| [awesome-a11y](https://github.com/brunopulis/awesome-a11y) | CC0 | 2026-08-03 | ~100 | Read: tools, spec, laws and guides (about 100 entries): web only (axe-core, pa11y, Lighthouse); a11y-contrast and Color Oracle overlap what `shot` already does |
| [awesome-testing](https://github.com/TheJambo/awesome-testing) | CC0 | 2026-10-28 | ~239 | Read: nothing on game accessibility or flaky tests; none of its entries is used |
| [awesome-gametalks](https://github.com/hzoo/awesome-gametalks) | MIT | **2016-07-07** | ~258 | Stale and read by keyword: no Godot talk; three talks `docs/gdc` does not hold, Hamilton on accessibility (GDC 2013), Overwatch "Play by Sound" (GDC 2016) and Lemarchand on playtesting (GDC 2012), links not opened |
| [godot-ci](https://github.com/aBARICHELLO/godot-ci) | MIT | 2026-10-20 | - | A Docker image and workflow for Godot CI that the kit's own workflow replaces; not compared |
| [awesome-claude-code](https://github.com/hesreallyhim/awesome-claude-code) | its own notice, not a CC licence | 2026-10-29 | ~284 | Not reused, because the licence was not checked against what the kit could copy |

The lists whose clones were incomplete are not in the table. Production, magictools, open-source games, Steam Deck and
testing were read entry by entry (below); learn-gamedev, game datasets, game engine development, a11y and gametalks were
then read by section and keyword, not every line (the counts in the table are what the files hold, more than the lists
claim), and the links were not opened except two status checks. Nothing from them is in the kit.

## Read entry by entry

Facts as read from files in clones (read only; nothing was built or run). Anything on a site that did not resolve in this
session (quaternius.com, game-icons.net, polyhaven.com) was not read.

- **Open-source Godot games** (the list marks no engine; four are named): [OpenLiberty](https://github.com/OpenLiberty-Project/OpenLiberty)
  is MIT, active (2026-10-13), Godot 4.7, GDScript, no tests and no CI, and the player must supply GTA3's files, so it is the one
  field-test target here. Reia is AGPL-3.0, Godot 4.7 with a Rust GDExtension, 4 workflows, no test framework, and needs Git LFS,
  submodules (one over ssh) and downloaded binaries before it imports. DynaDungeons (GPL-3.0, last commit 2024) and Pimple Popper
  (MIT, 2026-01) are Godot 3 projects: negative cases only.
- **Steam Deck:** ten developer-side entries: Gamescope, MangoHud, Deck Verified, the official site, Great On Deck, ProtonDB, the
  ArchWiki page, ShareDeck, HandheldHQ and Distrobox. The list has no developer documentation beyond the two Steam pages the
  kit already cites.
- **Testing:** ten entries looked at (Drengr, qmax-mcp, QASkills.sh, junit-collision-check, flight-recorder, Lastest, a colour
  blindness simulator, the Explore It! book, the Big List of Naughty Strings, How They Test); none is for games or for an agent's
  JSON-driven loop, so none is used.
- **Production and tools:** the kit already names Kenney, OpenGameArt, Freesound, jsfxr/bfxr2, Sonniss, Lospec and Aseprite.
  New and read from a repository: Sprite Fusion's pixel snapper and sprite normals (MIT, 2026-10-20), Material Maker (MIT,
  2026-10-24), LDtk (MIT, 2026-10-06), Tiled (GPL app, BSD-2 library, 2026-10-24) and Folded Paper Engine (MIT, an MVP): these are
  in [addons.md](addons.md). Pages only: Evidence-Based Scheduling (Joel Spolsky) and Game Programming Patterns, which fit
  `docs/plan.md` and an architecture reading list but were not read here.
- **Asset sources, licence pages read on 2026-10-29** (the sites' own statements; no file was downloaded or checked):
  - Quaternius: the list says CC0, but the site now carries the Quaternius Asset License v1.0 (updated 2026-08-28): free for
    personal, educational and commercial games, no credit required, no reselling or redistributing the assets as assets. Not
    CC0, so `assets.json` should record it as its own licence. Older downloads may be CC0; check the file you took.
  - Game-icons.net: CC BY 3.0, so credit the author in the game (`credits` must list it), not "free" without terms.
  - Poly Haven: all assets CC0.
  - GameAsset.net and SFXMint: the sites state CC0 / public domain. These are claims on the front page; no licence file or
    per-asset terms were read, so record the source URL per asset.
  - RespawnStack: a ledger of AI tools' commercial-use terms (61 tools), not an asset source; its quotes were not checked
    against the vendors.
  - Poly Pizza: dropped by the owner (2026-10-29); its site blocks scripts and its licences were never read.
  The skill `godot-asset-pipeline` names none of these sources, so nothing there changed.

## Not done

- Per-asset terms of GameAsset.net and SFXMint.
- Every line of learn-gamedev, game datasets, game engine development and gametalks, and the pages their leads point to.
- Three gametalks, as candidates for `docs/gdc` (titles from the list, not opened): Ian Hamilton on accessibility (GDC 2013, gdcvault.com/play/1020377), Overwatch "Play by Sound" (GDC 2016) and Lemarchand on playtesting (GDC 2012, gdcvault.com/play/1015745).
- An `addons-status.json` entry for godot-luaAPI: its folder name has to be confirmed from a release zip first, as the other
  entries were (`roadmap.md`).
- A field test on OpenLiberty and on the C# template and the two GDScript templates above.
