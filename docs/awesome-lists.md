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
| [awesome-learn-gamedev](https://github.com/notpresident35/awesome-learn-gamedev) | CC0 | 2026-06-01 | ~47 | Learning links for people (Reddit wikis, textures, cheatsheets); the skills already cover the topics, so nothing was taken |
| [awesome-game-production](https://github.com/vhladiienko/awesome-game-production) | CC0 | 2026-05-04 | ~71 | Production reading for `godot-game-plan`; not read in full |
| [magictools](https://github.com/ellisonleao/magictools) | MIT | 2026-10-28 | ~68 sections | A directory of game-making tools; not read in full |
| [awesome-open-source-games](https://github.com/michelpereira/awesome-open-source-games) | CC0 | 2026-10-21 | ~459 | Candidates for field tests; no Godot subset was extracted |
| [game-datasets](https://github.com/leomaurodesenv/game-datasets) | CC BY 4.0 | 2026-10-25 | ~204 | Data for game AI research; no use found |
| [awesome-game-engine-dev](https://github.com/stevinz/awesome-game-engine-dev) | CC0 | 2026-08-17 | ~76 | Engine internals; the kit does not build engines |
| [awesome-steam-deck](https://github.com/airscripts/awesome-steam-deck) | CC0 | 2026-09-12 | ~178 | Deck tools for players; `deck` and `godot-steam-deck` cover a developer's side; not read in full |
| [awesome-a11y](https://github.com/brunopulis/awesome-a11y) | CC0 | 2026-08-03 | ~35 | Web accessibility; `godot-ui-accessibility` follows WCAG and the Game Accessibility Guidelines already |
| [awesome-testing](https://github.com/TheJambo/awesome-testing) | CC0 | 2026-10-28 | ~239 | General testing links; not read in full |
| [awesome-gametalks](https://github.com/hzoo/awesome-gametalks) | MIT | **2016-07-07** | ~260 | Stale; `docs/gdc` already holds the talks that matter |
| [godot-ci](https://github.com/aBARICHELLO/godot-ci) | MIT | 2026-10-20 | - | A Docker image and workflow for Godot CI that the kit's own workflow replaces; not compared |
| [awesome-claude-code](https://github.com/hesreallyhim/awesome-claude-code) | its own notice, not a CC licence | 2026-10-29 | ~284 | Not reused, because the licence was not checked against what the kit could copy |

The lists whose clones were incomplete (the analyst reading them was stopped) are not in the table. "Not read in full"
means exactly that: the entries were not assessed, so nothing from them is in the kit.

## Not done

- Reading the remaining lists entry by entry (production, magictools, open-source games, steam-deck, testing).
- An `addons-status.json` entry for godot-luaAPI: its folder name has to be confirmed from a release zip first, as the other
  entries were (`roadmap.md`).
- A field test on the C# template and the two GDScript templates above.
