# Changelog fragments

Every change adds one small file here instead of editing `CHANGELOG.md`, so pull requests do not conflict on its top
lines. `ci/godot/tools/Update-Changelog.ps1 -Version <x.y.z>` assembles the fragments into a dated section at release and
deletes them. This file is not a fragment.

## Format

`changelog.d/<slug>.md`, the slug in lower-case letters, digits and hyphens (for example `bench-sweep-message.md`):

```
Fixed: `bench -Sweep` named ' ' instead of the values.
```

- The first line is `<Category>: <entry>`. Category is one of `Added`, `Changed`, `Fixed`, `Removed`, `Deprecated`,
  `Security` (capitalised). The entry is one line of Markdown.
- Lines after the first continue the entry; they are indented under its bullet.
- At release the entries sit under `### <Category>` in that order, sorted by slug. The text under the old `## Unreleased`
  heading of `CHANGELOG.md` stays first in the new section.

`pwsh ci/godot/tools/Update-Changelog.ps1 -Check` validates the fragments and shows the result without changing anything.
