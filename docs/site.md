# The website

Hyperdot's documentation is also a website, <https://nick-vas.github.io/hyperdot/> (the default github.io address of
the repository's GitHub Pages). It is built from the repository's Markdown on every push to `main` that changes it, so it
says what the repository says.

## What it is made of

- `README.md` is the home page, `CHANGELOG.md` the changelog, and every `docs/**/*.md` a page at the same path with
  `.html`.
- `docs/index.html` lists every doc with its first heading and first sentence, grouped as the README's "Documentation"
  section groups them, with a search over page titles and headings.
- The label page ([label.md](label.md)) shows the labels in `docs/label/` (the SVG, the information sheet and its JSON),
  where the page has its `<!-- RATING -->` marker. `benchmark.html` shows the labels again, the reference runs from
  [token-benchmark.md](token-benchmark.md) and the field test from the label page.
- Links between pages become `.html` links and keep their anchors. Links to other repository files (scripts, JSON,
  workflows) go to GitHub at the commit the site was built from; images and the label files are copied. Every link
  inside the site is relative, so it works under `/hyperdot/` and under a custom domain alike.
- No JavaScript framework and nothing from another host: system fonts, one stylesheet, and a 2 KB script for the search
  and the contents beside wide pages, which the site works without. The README's badges are shown as their text.

`site/Build-Site.ps1` does the building with Markdig, the Markdown engine `ConvertFrom-Markdown` loads, so there is
nothing to install. `ConvertFrom-Markdown`'s own pipeline turns on Markdig's extensions that GitHub does not have (it
read `(1 - p)^9 ... 0.98^9` in [anti-cheat.md](anti-cheat.md) as superscript, and `{#id}`, `==text==` and `$x$` as
markup), so the builder makes its pipeline from the same assembly with GitHub's extensions only: tables, task lists,
strikethrough, autolinks, footnotes and GitHub's heading ids (Markdig's default ids keep dots, so `.NET 8` gave
`.net-8` where GitHub has `net-8`). An escaped pipe in a table's code span (`` `a\|b` ``) shows as a pipe, as on
GitHub. `site/template.html`, `site/site.css` and `site/site.js` are the page around the content.

`.github/workflows/pages.yml` builds the site, checks it with `tests/Test-Site.ps1 -Site _site` and publishes it.
The check fails on a doc without its page, a link or `#anchor` that leads nowhere, a link still ending in `.md`, a link
to a repository file that does not exist, a page without one `h1`, a title, `lang` or the viewport meta, a request to
another host, a label not shown, or colours under WCAG 2.2 AA (it computes the contrast ratios of the light and dark
colours). The self-test workflow runs the same test on every push.

## Preview it

```powershell
pwsh site/Build-Site.ps1 -Serve
```

builds the site into `_site` (ignored by git) and serves it at <http://localhost:8000/hyperdot/>, the path it has on
github.io, until Ctrl+C. `-Port` picks another port, `-Out` another folder. Without `-Serve`, the pages can also be
opened from the folder, except the search, which needs a server.

## The one setting

The first deployment needs the repository's owner to choose the workflow as the publisher: **Settings → Pages → Build
and deployment → Source: GitHub Actions**. After that every push to `main` that changes the docs publishes them, and
the workflow can be started by hand from the Actions tab.
