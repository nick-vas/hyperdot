#!/usr/bin/env pwsh
# Self-test of the GitHub Pages site (site/Build-Site.ps1): builds it into a temporary folder (or checks -Site, the
# workflow's output) and checks that every Markdown source has its page; every internal href and src leads to a file and
# every #fragment to an id on its page; no relative link still ends in .md; every link to the repository names a file or
# folder that exists; every page has one h1, a title, lang and the viewport meta; nothing is fetched from another host;
# the label SVGs are shown; and the colours pass WCAG 2.2 AA in light and dark. A made-up repository with a broken link
# and a broken anchor proves the checks fail, and shows the builder's fixes for where Markdig differs from GitHub.
# No Godot.
param(
    # A built site to check instead of building one (the Pages workflow's output).
    [string]$Site
)
Set-StrictMode -Version 3.0
$ErrorActionPreference = 'Stop'
$root = Split-Path $PSScriptRoot
$builder = Join-Path $root 'site/Build-Site.ps1'
$failures = [System.Collections.Generic.List[string]]::new()
function Assert-True([bool]$Condition, [string]$What) {
    if ($Condition) { Write-Host "ok     $What" } else { Write-Host "FAIL   $What" -ForegroundColor Red; $failures.Add($What) }
}
function Format-Problems([string[]]$Items, [int]$Max = 8) {
    $shown = @($Items | Select-Object -First $Max)
    return ($shown -join ' | ') + $(if ($Items.Count -gt $Max) { " | ... $($Items.Count - $Max) more" })
}

# The pages a repository's Markdown should give.
function Get-ExpectedPages([string]$RepoRoot) {
    $expected = [System.Collections.Generic.List[string]]::new()
    if (Test-Path -LiteralPath (Join-Path $RepoRoot 'README.md')) { $expected.Add('index.html') }
    if (Test-Path -LiteralPath (Join-Path $RepoRoot 'CHANGELOG.md')) { $expected.Add('changelog.html') }
    $docs = Join-Path $RepoRoot 'docs'
    if (Test-Path -LiteralPath $docs) {
        foreach ($f in @(Get-ChildItem -LiteralPath $docs -Recurse -File -Filter '*.md')) {
            $expected.Add(([System.IO.Path]::GetRelativePath($RepoRoot, $f.FullName) -replace '\\', '/' -replace '\.md$', '.html'))
        }
    }
    $expected.Add('docs/index.html')
    $expected.Add('benchmark.html')
    return $expected
}

# Every problem of a built site, as text: the checks the self-test and the workflow rely on.
function Get-SiteProblems([string]$SiteDir, [string]$RepoRoot) {
    $problems = [System.Collections.Generic.List[string]]::new()
    $ids = @{}
    $readPage = {
        param($Rel)
        if (-not $ids.ContainsKey($Rel)) {
            $set = [System.Collections.Generic.HashSet[string]]::new([System.StringComparer]::Ordinal)
            $text = [System.IO.File]::ReadAllText((Join-Path $SiteDir $Rel))
            foreach ($m in [regex]::Matches($text, '\sid="([^"]+)"')) { [void]$set.Add([System.Net.WebUtility]::HtmlDecode($m.Groups[1].Value)) }
            $ids[$Rel] = $set
        }
        return $ids[$Rel]
    }
    # A link from page $From (site-relative) to $Url: the problem, or $null.
    $checkLink = {
        param($From, $Url)
        $path, $fragment = $Url -split '#', 2
        if ($path -match '\.md$') { return "${From}: $Url still ends in .md" }
        $target = $From
        if ($path) {
            $dir = Split-Path $From
            $base = if ($dir) { Join-Path $SiteDir $dir } else { $SiteDir }
            $full = [System.IO.Path]::GetFullPath((Join-Path $base ([uri]::UnescapeDataString($path))))
            $siteFull = [System.IO.Path]::GetFullPath($SiteDir).TrimEnd([System.IO.Path]::DirectorySeparatorChar) + [System.IO.Path]::DirectorySeparatorChar
            if (-not $full.StartsWith($siteFull)) { return "${From}: $Url leaves the site" }
            if (-not (Test-Path -LiteralPath $full -PathType Leaf)) { return "${From}: $Url does not exist" }
            $target = [System.IO.Path]::GetRelativePath($SiteDir, $full) -replace '\\', '/'
        }
        if ($fragment -and $target -like '*.html' -and -not (& $readPage $target).Contains([uri]::UnescapeDataString($fragment))) {
            return "${From}: $Url has no id #$fragment"
        }
        return $null
    }

    $pages = @(Get-ChildItem -LiteralPath $SiteDir -Recurse -File -Filter '*.html' | ForEach-Object { [System.IO.Path]::GetRelativePath($SiteDir, $_.FullName) -replace '\\', '/' })
    foreach ($expected in Get-ExpectedPages $RepoRoot) {
        if ($expected -notin $pages) { $problems.Add("no page $expected") }
    }
    foreach ($page in $pages) {
        $text = [System.IO.File]::ReadAllText((Join-Path $SiteDir $page))
        $h1 = [regex]::Matches($text, '<h1\b').Count
        if ($h1 -ne 1) { $problems.Add("${page}: $h1 h1 headings") }
        $title = [regex]::Match($text, '<title>([^<]*)</title>')
        if (-not $title.Success -or -not $title.Groups[1].Value.Trim()) { $problems.Add("${page}: no title") }
        elseif ([System.Net.WebUtility]::HtmlDecode($title.Groups[1].Value) -notmatch "(^| $([char]0x00B7) )Hyperdot$") { $problems.Add("${page}: title '$($title.Groups[1].Value)' does not end in Hyperdot") }
        if ($text -notmatch '<html lang="[a-z]{2}') { $problems.Add("${page}: no lang") }
        if ($text -notmatch '<meta name="viewport" content="width=device-width') { $problems.Add("${page}: no viewport meta") }
        foreach ($m in [regex]::Matches($text, '<(img|script|link|iframe|source|video|audio|embed|object)\b[^>]*\s(src|href|data)="((https?:)?//[^"]*)"')) {
            $problems.Add("${page}: fetches $($m.Groups[3].Value) from another host")
        }
        foreach ($m in [regex]::Matches($text, '\s(href|src)="([^"]*)"')) {
            $url = [System.Net.WebUtility]::HtmlDecode($m.Groups[2].Value)
            $repo = [regex]::Match($url, '^https://github\.com/nick-vas/hyperdot/(?<kind>blob|tree)/[0-9a-f]{7,40}/(?<path>[^#?]+)')
            if ($repo.Success) {
                $repoPath = Join-Path $RepoRoot ([uri]::UnescapeDataString($repo.Groups['path'].Value))
                $type = if ($repo.Groups['kind'].Value -eq 'blob') { 'Leaf' } else { 'Container' }
                if (-not (Test-Path -LiteralPath $repoPath -PathType $type)) { $problems.Add("${page}: $url names a $($type.ToLowerInvariant()) the repository does not have") }
                continue
            }
            if ($url -match '^[A-Za-z][A-Za-z0-9+.-]*:' -or $url.StartsWith('//') -or $url -eq '') { continue }
            $problem = & $checkLink $page $url
            if ($problem) { $problems.Add($problem) }
        }
    }
    $index = Join-Path $SiteDir 'static/search-index.json'
    if (Test-Path -LiteralPath $index) {
        foreach ($entry in @(Get-Content -LiteralPath $index -Raw | ConvertFrom-Json)) {
            $problem = & $checkLink 'index.html' $entry[1]
            if ($problem) { $problems.Add("search index: $problem") }
        }
    } else { $problems.Add('no static/search-index.json') }

    # The labels: every SVG in docs/label/ is copied and shown on the label page; with none, the page says so.
    $labelPage = Join-Path $SiteDir 'docs/label.html'
    $labelHtml = if (Test-Path -LiteralPath $labelPage) { [System.IO.File]::ReadAllText($labelPage) } else { '' }
    $svgs = @(if (Test-Path -LiteralPath (Join-Path $RepoRoot 'docs/label')) { Get-ChildItem -LiteralPath (Join-Path $RepoRoot 'docs/label') -File -Filter '*.svg' })
    foreach ($svg in $svgs) {
        if (-not (Test-Path -LiteralPath (Join-Path $SiteDir "docs/label/$($svg.Name)"))) { $problems.Add("label $($svg.Name) not copied") }
        if (-not $labelHtml.Contains("src=`"label/$($svg.Name)`"")) { $problems.Add("label $($svg.Name) not shown on docs/label.html") }
    }
    if (-not $svgs.Count -and $labelHtml -and -not $labelHtml.Contains('No version has been rated yet')) { $problems.Add('docs/label.html neither shows labels nor says there are none') }
    return $problems
}

# WCAG 2.x relative luminance and contrast ratio of two #rrggbb colours.
function Get-Luminance([string]$Hex) {
    $channels = foreach ($i in 1, 3, 5) {
        $c = [Convert]::ToInt32($Hex.Substring($i, 2), 16) / 255
        if ($c -le 0.04045) { $c / 12.92 } else { [Math]::Pow(($c + 0.055) / 1.055, 2.4) }
    }
    return 0.2126 * $channels[0] + 0.7152 * $channels[1] + 0.0722 * $channels[2]
}
function Get-ContrastRatio([string]$A, [string]$B) {
    $la = Get-Luminance $A; $lb = Get-Luminance $B
    return ([Math]::Max($la, $lb) + 0.05) / ([Math]::Min($la, $lb) + 0.05)
}

$temp = Join-Path ([System.IO.Path]::GetTempPath()) "site-$([guid]::NewGuid().ToString('N').Substring(0, 8))"
try {
    # --- This repository's site ---------------------------------------------------------------------------------------
    if (-not $Site) {
        $Site = Join-Path $temp 'site'
        $commit = @(& git -C $root rev-parse HEAD 2>$null) -join ''
        if ($commit -notmatch '^[0-9a-f]{40}$') { $commit = '0' * 40 }
        & pwsh -NoProfile -File $builder -Out $Site -Commit $commit | Out-Host
        Assert-True ($LASTEXITCODE -eq 0) 'the builder builds this repository''s site'
    }
    $problems = @(Get-SiteProblems $Site $root)
    $expected = @(Get-ExpectedPages $root)
    Assert-True ($problems.Count -eq 0) "$($expected.Count) pages, every link, anchor, repository link, heading, title and label check passes$(if ($problems) { ': ' + (Format-Problems $problems) })"
    $homeHtml = if (Test-Path -LiteralPath (Join-Path $Site 'index.html')) { [System.IO.File]::ReadAllText((Join-Path $Site 'index.html')) } else { '' }
    Assert-True ($homeHtml -match 'aria-current="page">Home<' -and $homeHtml -match 'href="index.html#quick-start">Quick start<' -and $homeHtml -match 'href="docs/label.html">Label<' -and
        $homeHtml -match 'href="benchmark.html">Benchmark<' -and $homeHtml -match 'href="docs/index.html">Docs<' -and $homeHtml -match 'href="changelog.html">Changelog<') 'the header links Home, Quick start, Label, Benchmark, Docs and Changelog'
    Assert-True ($homeHtml -match '<span class="badge">Self-test</span>' -and $homeHtml -notmatch 'img\.shields\.io') 'the README''s badges are shown as text, not fetched'
    $docsIndex = if (Test-Path -LiteralPath (Join-Path $Site 'docs/index.html')) { [System.IO.File]::ReadAllText((Join-Path $Site 'docs/index.html')) } else { '' }
    $listed = @(Get-ChildItem -LiteralPath (Join-Path $root 'docs') -Recurse -File -Filter '*.md' | Where-Object {
            $rel = [System.IO.Path]::GetRelativePath((Join-Path $root 'docs'), $_.FullName) -replace '\\', '/' -replace '\.md$', '.html'
            -not $docsIndex.Contains("href=`"$rel`"")
        } | ForEach-Object Name)
    Assert-True ($listed.Count -eq 0 -and $docsIndex -match '<h2 id="using-the-kit">') "the docs index lists every doc, grouped as the README groups them$(if ($listed) { '; missing: ' + (Format-Problems $listed) })"
    $js = Join-Path $Site 'static/site.js'
    Assert-True ((Test-Path -LiteralPath $js) -and (Get-Item -LiteralPath $js).Length -lt 3072) "the optional script stays under 3 KB ($(if (Test-Path -LiteralPath $js) { (Get-Item -LiteralPath $js).Length }) bytes)"
    $css = [System.IO.File]::ReadAllText((Join-Path $root 'site/site.css'))
    Assert-True ($css -notmatch 'url\(\s*["'']?(https?:)?//' -and $css -notmatch '@import') 'the stylesheet fetches nothing'

    # --- Contrast: WCAG 2.2 AA, 4.5:1 for text and 3:1 for focus rings and control borders, light and dark ------------
    $light = @{}; $dark = @{}
    foreach ($m in [regex]::Matches([regex]::Match($css, '(?s)^.*?:root\s*\{(.*?)\}').Groups[1].Value, '--([\w-]+):\s*(#[0-9a-fA-F]{6})')) { $light[$m.Groups[1].Value] = $m.Groups[2].Value }
    foreach ($m in [regex]::Matches([regex]::Match($css, '(?s)prefers-color-scheme:\s*dark\)\s*\{\s*:root\s*\{(.*?)\}').Groups[1].Value, '--([\w-]+):\s*(#[0-9a-fA-F]{6})')) { $dark[$m.Groups[1].Value] = $m.Groups[2].Value }
    $pairs = @(
        @('fg', 'bg', 4.5), @('fg', 'surface', 4.5), @('fg', 'code-bg', 4.5), @('muted', 'bg', 4.5), @('muted', 'surface', 4.5),
        @('link', 'bg', 4.5), @('link', 'surface', 4.5), @('link', 'code-bg', 4.5), @('bg', 'fg', 4.5), @('focus', 'bg', 3), @('focus', 'surface', 3)
    )
    foreach ($scheme in @(@('light', $light), @('dark', $dark))) {
        $tokens = $scheme[1]
        $results = foreach ($pair in $pairs) {
            if (-not ($tokens.ContainsKey($pair[0]) -and $tokens.ContainsKey($pair[1]))) { [pscustomobject]@{ Text = "$($pair[0])/$($pair[1]) missing"; Ok = $false }; continue }
            $ratio = Get-ContrastRatio $tokens[$pair[0]] $tokens[$pair[1]]
            [pscustomobject]@{ Text = ('{0}/{1} {2:0.00}' -f $pair[0], $pair[1], $ratio); Ok = $ratio -ge $pair[2] }
        }
        Assert-True (@($results | Where-Object { -not $_.Ok }).Count -eq 0) "$($scheme[0]) colours meet WCAG 2.2 AA: $(@($results | ForEach-Object Text | Select-Object -Unique) -join ', ')"
    }

    # --- A made-up repository: a broken link and a broken anchor fail; Markdig's differences from GitHub are fixed ----
    $repo = Join-Path $temp 'repo'
    New-Item -ItemType Directory -Force (Join-Path $repo 'docs/label'), (Join-Path $repo 'scripts'), (Join-Path $repo 'site') | Out-Null
    # What every page's header and footer link to: the licence, the builder (the generated pages' source) and the quick start.
    Set-Content -LiteralPath (Join-Path $repo 'LICENSE') 'Licence'
    Set-Content -LiteralPath (Join-Path $repo 'site/Build-Site.ps1') '# the builder'
    Set-Content -LiteralPath (Join-Path $repo 'scripts/tool.ps1') '# a script'
    Set-Content -LiteralPath (Join-Path $repo 'README.md') @'
# Made up

The home page. <img src="https://img.shields.io/badge/x-y-blue" alt="Badge text">

## Quick start

Run it.

## Documentation

**Using it**
- [docs/a.md](docs/a.md): the one doc

See [the doc](docs/a.md#c-and-net-8--gut-v971), [a missing page](docs/missing.md), [a missing anchor](docs/a.md#no-such-heading),
[the script](scripts/tool.ps1), [the scripts](scripts/) and the [changelog](CHANGELOG.md).
'@
    Set-Content -LiteralPath (Join-Path $repo 'CHANGELOG.md') "# Changelog`n`n## Unreleased`n- Nothing yet.`n"
    Set-Content -LiteralPath (Join-Path $repo 'docs/a.md') @'
# A doc

The base rate is 1 - (1 - p)^9 of them:
1 - 0.98^9 = 0.166, ==not marked==.

## Setup {#custom}

## C# and .NET 8 / GUT v9.7.1

| Command | Result |
|---|---|
| `plan -Do add\|move` | moves |

- [x] done
- [ ] open

Back to [the home page](../README.md#documentation).
'@
    Set-Content -LiteralPath (Join-Path $repo 'docs/token-benchmark.md') "# Token benchmark`n`n## Reference runs (made up)`n`nSee [the method](#the-method) and [the label](label.md).`n`n## The method`n`nCounted.`n"
    Set-Content -LiteralPath (Join-Path $repo 'docs/label/hyperdot-9.9.9-tool-m.svg') '<svg xmlns="http://www.w3.org/2000/svg" width="400" height="560"><rect width="400" height="560" fill="#1f4e79"/></svg>'
    Set-Content -LiteralPath (Join-Path $repo 'docs/label/hyperdot-9.9.9-tool-m.json') '{ "name": "hyperdot-9.9.9-tool-m", "version": "9.9.9", "programmeName": "Tool efficiency", "modelName": "Model 9", "plugin": false, "class": "C", "coverage": { "class": "B" } }'
    Set-Content -LiteralPath (Join-Path $repo 'docs/label/hyperdot-9.9.9-tool-m.md') "# Product information sheet: Hyperdot 9.9.9`n`n![label](hyperdot-9.9.9-tool-m.svg)`n`n[Method](../label.md)`n"
    Set-Content -LiteralPath (Join-Path $repo 'docs/label.md') "# The label`n`nRated like an appliance.`n`n<!-- RATING -->`n`n## The method`n`nSee [the sheet](label/hyperdot-9.9.9-tool-m.md).`n"
    $made = Join-Path $temp 'made-up'
    $buildLog = & pwsh -NoProfile -File $builder -Root $repo -Out $made -Commit ('a' * 40) 6>&1 2>&1 | Out-String
    Assert-True ($LASTEXITCODE -eq 0 -and $buildLog -match 'warning: index\.html: docs/missing\.md does not exist') 'the builder builds a made-up repository and warns of the missing page'
    $madeProblems = @(Get-SiteProblems $made $repo)
    $text = $madeProblems -join "`n"
    Assert-True ($text -match 'index\.html: docs/missing\.md still ends in \.md') "the checker fails a link to a page that does not exist: $(Format-Problems $madeProblems)"
    Assert-True ($text -match 'index\.html: docs/a\.html#no-such-heading has no id') 'the checker fails an anchor no heading has'
    Assert-True ($madeProblems.Count -eq 2) "nothing else fails in the made-up site ($($madeProblems.Count) problems)"
    $a = [System.IO.File]::ReadAllText((Join-Path $made 'docs/a.html'))
    $madeHome = [System.IO.File]::ReadAllText((Join-Path $made 'index.html'))
    Assert-True ($a -match '<h2 id="c-and-net-8--gut-v971">') 'headings get GitHub''s ids (Markdig''s default keeps the dots: c-and.net-8-gut-v9.7.1)'
    Assert-True ($a -notmatch '<sup>|<mark>' -and $a -match '\(1 - p\)\^9' -and $a -match '==not marked==') 'carets and == stay text (Markdig''s advanced extensions read them as superscript and highlight)'
    Assert-True ($a -match '<h2 id="setup-custom">Setup \{#custom\}</h2>') '{#id} after a heading stays text, as on GitHub (Markdig''s generic attributes take it as the id)'
    Assert-True ($a -match '<code>plan -Do add\|move</code>') 'an escaped pipe in a table''s code span is a pipe, as on GitHub'
    Assert-True ($a -match 'class="task-list-item"><input disabled="disabled" type="checkbox" checked="checked"') 'task lists render'
    Assert-True ($a -match 'href="../index.html#documentation"' -and $madeHome -match 'href="changelog.html"') 'page links become relative .html links and keep their anchors'
    Assert-True ($madeHome -match "href=`"https://github.com/nick-vas/hyperdot/blob/$('a' * 40)/scripts/tool.ps1`"" -and $madeHome -match "href=`"https://github.com/nick-vas/hyperdot/tree/$('a' * 40)/scripts`"") 'repository files and folders become GitHub links at the commit'
    Assert-True ($madeHome -match '<span class="badge">Badge text</span>') 'an image from another host becomes its text'
    $bench = [System.IO.File]::ReadAllText((Join-Path $made 'benchmark.html'))
    Assert-True ($bench -match '<h2 id="reference-runs-made-up">' -and $bench -match 'href="docs/token-benchmark.html#the-method"' -and $bench -match 'href="docs/label.html"') 'the benchmark page shows the reference runs, their anchors still pointing at their own page'
    $label = [System.IO.File]::ReadAllText((Join-Path $made 'docs/label.html'))
    Assert-True ($label -match 'src="label/hyperdot-9.9.9-tool-m.svg"' -and $label -match 'Model 9, class C' -and $label -match 'href="label/hyperdot-9.9.9-tool-m.html">Information sheet' -and
        $label -match 'Tested class of Hyperdot 9.9.9: <strong>B</strong>' -and (Test-Path -LiteralPath (Join-Path $made 'docs/label/hyperdot-9.9.9-tool-m.json'))) 'the label page shows each label with its sheet, its JSON and the tested class'
    Assert-True ([System.IO.File]::ReadAllText((Join-Path $made 'docs/index.html')) -match '<h2 id="using-it">Using it</h2>') 'the docs index takes its groups from the README'
    $title = [regex]::Match($a, '<title>([^<]*)</title>').Groups[1].Value
    Assert-True ([System.Net.WebUtility]::HtmlDecode($title) -eq "A doc $([char]0x00B7) Hyperdot") "a page's title is its heading and the site's name ($title)"

    # The local preview: -Serve answers under /hyperdot/, as github.io does, and sends other paths there.
    $port = Get-Random -Minimum 20000 -Maximum 60000
    $server = Start-Process -FilePath (Get-Process -Id $PID).Path -ArgumentList @('-NoProfile', '-File', $builder, '-Root', $repo, '-Out', (Join-Path $temp 'served'), '-Commit', ('a' * 40), '-Serve', '-Port', $port) -PassThru -RedirectStandardOutput (Join-Path $temp 'serve.log')
    try {
        $served = $null
        foreach ($i in 1..60) {
            try { $served = Invoke-WebRequest -Uri "http://localhost:$port/hyperdot/docs/a.html" -TimeoutSec 2; break } catch { Start-Sleep -Milliseconds 250 }
        }
        $missing = try { (Invoke-WebRequest -Uri "http://localhost:$port/hyperdot/nothing.html" -TimeoutSec 2 -SkipHttpErrorCheck).StatusCode } catch { 0 }
        Assert-True ($null -ne $served -and $served.StatusCode -eq 200 -and $served.Content -match '<h1 id="a-doc">' -and $missing -eq 404) 'the -Serve preview serves the site under /hyperdot/ and answers 404 for what it does not have'
    } finally {
        Stop-Process -Id $server.Id -Force -ErrorAction SilentlyContinue
    }

    # A folder that is not an earlier build is never emptied.
    $other = Join-Path $temp 'not-a-site'
    New-Item -ItemType Directory -Force $other | Out-Null
    Set-Content -LiteralPath (Join-Path $other 'keep.txt') 'mine'
    & pwsh -NoProfile -File $builder -Root $repo -Out $other -Commit ('a' * 40) *> $null
    Assert-True ($LASTEXITCODE -ne 0 -and (Test-Path -LiteralPath (Join-Path $other 'keep.txt'))) 'the builder refuses to empty a folder that holds no earlier build'
} finally {
    Remove-Item -LiteralPath $temp -Recurse -Force -ErrorAction SilentlyContinue
}

if ($failures.Count) { Write-Host "$($failures.Count) site check(s) failed" -ForegroundColor Red; exit 1 }
Write-Host 'site self-test passed'
exit 0
