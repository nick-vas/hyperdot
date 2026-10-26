#Requires -Version 7.6
<#
.SYNOPSIS
Builds Hyperdot's GitHub Pages site from the repository's Markdown.

.DESCRIPTION
README.md becomes the home page, CHANGELOG.md the changelog, and every docs/**/*.md a page at the same path with .html.
Two pages are made here: docs/index.html lists every doc with its first heading and first sentence, grouped as the
README's "Documentation" section groups them, and benchmark.html gathers the benchmark's results. The label page
(docs/label.md) shows the labels in docs/label/ with their information sheets.

Markdown is read by Markdig, the engine behind PowerShell's ConvertFrom-Markdown, with GitHub's extensions only (pipe
tables, task lists, strikethrough, autolinks, footnotes and GitHub's heading ids). ConvertFrom-Markdown's own pipeline
has Markdig's advanced extensions on, which read `^`, `$`, `==` and `{...}` as markup GitHub does not have.

Links between pages become .html links, keeping their #anchors. Links to other repository files (scripts, JSON,
workflows) become links to GitHub at -Commit; images and docs/label/ files are copied. Every internal link is relative,
so the site works under /hyperdot/ on github.io and under a custom domain alike. Images from other hosts (the README's
badges) are shown as their text: the site makes no request to another host.

.EXAMPLE
pwsh site/Build-Site.ps1 -Serve
pwsh site/Build-Site.ps1 -Out _site -Commit (git rev-parse HEAD)
#>
[CmdletBinding()]
param(
    # Where the site goes (default _site in the repository). It is emptied first, if it holds an earlier build.
    [string]$Out,
    # The commit links to repository files point at (default: git rev-parse HEAD).
    [string]$Commit,
    # The repository to build from (default: the one this script is in).
    [string]$Root = (Split-Path $PSScriptRoot -Parent),
    [string]$Repository = 'https://github.com/nick-vas/hyperdot',
    # After building, serve the site at http://localhost:<Port>/hyperdot/, the path it has on github.io, until Ctrl+C.
    [switch]$Serve,
    [ValidateRange(1, 65535)][int]$Port = 8000
)
Set-StrictMode -Version 3.0
$ErrorActionPreference = 'Stop'

$Root = [System.IO.Path]::GetFullPath($Root)
if (-not $Out) { $Out = Join-Path $Root '_site' }
$Out = [System.IO.Path]::GetFullPath($Out, (Get-Location).Path)
if (-not $Commit) {
    $Commit = @(& git -C $Root rev-parse HEAD 2>$null) -join ''
    if ($Commit -notmatch '^[0-9a-f]{7,64}$') { throw "No -Commit given, and git rev-parse HEAD failed in $Root" }
}
$Commit = $Commit.Trim()
$siteName = 'Hyperdot'
$dot = [char]0x00B7
$marker = '.hyperdot-site'
$utf8 = [System.Text.UTF8Encoding]::new($false)
$warnings = [System.Collections.Generic.List[string]]::new()
$copies = [System.Collections.Generic.HashSet[string]]::new([System.StringComparer]::Ordinal)
$searchEntries = [System.Collections.Generic.List[object]]::new()
$imageExtensions = @('.png', '.jpg', '.jpeg', '.gif', '.svg', '.webp', '.avif', '.ico')

# --- Markdig with GitHub's extensions --------------------------------------------------------------------------------------
# ConvertFrom-Markdown loads Markdig; its pipeline is fixed, so the builder makes its own from the same assembly.
$null = ConvertFrom-Markdown -InputObject ' '
$builder = [Markdig.MarkdownPipelineBuilder]::new()
$builder = [Markdig.MarkdownExtensions]::UsePipeTables($builder)
$builder = [Markdig.MarkdownExtensions]::UseTaskLists($builder)
$builder = [Markdig.MarkdownExtensions]::UseAutoLinks($builder)
$builder = [Markdig.MarkdownExtensions]::UseFootnotes($builder)
$builder = [Markdig.MarkdownExtensions]::UseEmphasisExtras($builder, [Markdig.Extensions.EmphasisExtras.EmphasisExtraOptions]::Strikethrough)
$builder = [Markdig.MarkdownExtensions]::UseAutoIdentifiers($builder, [Markdig.Extensions.AutoIdentifiers.AutoIdentifierOptions]::GitHub)
$pipeline = $builder.Build()

function ConvertTo-HtmlText([string]$Text) { return [System.Net.WebUtility]::HtmlEncode($Text) }
function ConvertTo-PlainText([string]$Html) {
    $text = [regex]::Replace($Html, '<[^>]+>', '')
    return ([System.Net.WebUtility]::HtmlDecode($text) -replace '\s+', ' ').Trim()
}
function Write-SiteFile([string]$RelativePath, [string]$Text) {
    $path = Join-Path $Out $RelativePath
    New-Item -ItemType Directory -Force -Path (Split-Path $path) | Out-Null
    [System.IO.File]::WriteAllText($path, $Text, $utf8)
}

# A relative URL from one page of the site to another file of it ('docs/a.html' to 'index.html' is '../index.html').
function Get-RelativeUrl([string]$FromPage, [string]$To) {
    $targetPath, $fragment = $To -split '#', 2
    $fromDirs = @($FromPage -split '/' | Select-Object -SkipLast 1)
    $toParts = @($targetPath -split '/')
    $common = 0
    while ($common -lt $fromDirs.Count -and $common -lt ($toParts.Count - 1) -and $fromDirs[$common] -ceq $toParts[$common]) { $common++ }
    $up = @(for ($i = $common; $i -lt $fromDirs.Count; $i++) { '..' })
    $rest = @(for ($i = $common; $i -lt $toParts.Count; $i++) { [uri]::EscapeDataString($toParts[$i]) })
    $url = (@($up) + @($rest)) -join '/'
    if ($null -ne $fragment) { $url += "#$fragment" }
    return $url
}
function Get-RootPrefix([string]$Page) { return '../' * (@($Page -split '/').Count - 1) }
function Get-RepositoryUrl([string]$Kind, [string]$RepoPath) {
    $escaped = @($RepoPath -split '/' | Where-Object { $_ } | ForEach-Object { [uri]::EscapeDataString($_) }) -join '/'
    return "$Repository/$Kind/$Commit/$escaped"
}

# --- The pages -----------------------------------------------------------------------------------------------------------
$pages = [System.Collections.Generic.List[object]]::new()
$pageOf = [System.Collections.Generic.Dictionary[string, string]]::new([System.StringComparer]::Ordinal)   # repo .md -> page
function Add-SourcePage([string]$Source, [string]$Page, [string]$Kind) {
    $pages.Add([pscustomobject]@{ Source = $Source; Page = $Page; Kind = $Kind; Title = ''; Summary = ''; Html = '' })
    $pageOf[$Source] = $Page
}
if (Test-Path -LiteralPath (Join-Path $Root 'README.md')) { Add-SourcePage 'README.md' 'index.html' 'home' }
if (Test-Path -LiteralPath (Join-Path $Root 'CHANGELOG.md')) { Add-SourcePage 'CHANGELOG.md' 'changelog.html' 'changelog' }
$docsDir = Join-Path $Root 'docs'
if (Test-Path -LiteralPath $docsDir) {
    foreach ($file in @(Get-ChildItem -LiteralPath $docsDir -Recurse -File -Filter '*.md' | Sort-Object FullName)) {
        $source = [System.IO.Path]::GetRelativePath($Root, $file.FullName) -replace '\\', '/'
        $kind = if ($source -like 'docs/label/*') { 'sheet' } else { 'doc' }
        Add-SourcePage $source ($source -replace '\.md$', '.html') $kind
    }
}
$docsIndexPage = 'docs/index.html'
$benchmarkPage = 'benchmark.html'
if ($pageOf.ContainsValue($docsIndexPage) -or $pageOf.ContainsValue($benchmarkPage)) { throw "A Markdown file would become $docsIndexPage or $benchmarkPage, which the builder makes itself" }

# --- Links -----------------------------------------------------------------------------------------------------------------
# The repository path a link in a file of $SourceDir points at, or $null when it leaves the repository.
function Resolve-RepoPath([string]$SourceDir, [string]$Path) {
    $parts = [System.Collections.Generic.List[string]]::new()
    if (-not $Path.StartsWith('/') -and $SourceDir) { foreach ($p in $SourceDir -split '/') { if ($p) { $parts.Add($p) } } }
    foreach ($p in $Path -split '/') {
        if ($p -eq '' -or $p -eq '.') { continue }
        if ($p -eq '..') { if ($parts.Count -eq 0) { return $null }; $parts.RemoveAt($parts.Count - 1); continue }
        $parts.Add($p)
    }
    return $parts -join '/'
}

# One href or src of a page: a page link to its .html, an image or label file to its copy, another repository file to
# GitHub at the commit. Links to other hosts and to anchors on the same page stay as they are.
function Convert-Link([string]$Value, [string]$SourceDir, [string]$SourcePage, [string]$Page, [string]$Attribute) {
    $raw = [System.Net.WebUtility]::HtmlDecode($Value)
    if ($raw -match '^[A-Za-z][A-Za-z0-9+.-]*:' -or $raw.StartsWith('//') -or $raw -eq '') { return $Value }
    if ($raw.StartsWith('#')) {
        # An anchor on the source's own page: a section shown on another page (the benchmark page) still points there.
        $prefix = if ($SourcePage -cne $Page) { Get-RelativeUrl $Page $SourcePage } else { '' }
        return ConvertTo-HtmlText ($prefix + '#' + $raw.Substring(1).ToLowerInvariant())
    }
    $path, $fragment = $raw -split '#', 2
    $path = ($path -split '\?', 2)[0]
    $repoPath = Resolve-RepoPath $SourceDir ([uri]::UnescapeDataString($path))
    if ($null -eq $repoPath) { $warnings.Add("${Page}: $raw leaves the repository"); return $Value }
    $full = if ($repoPath) { Join-Path $Root $repoPath } else { $Root }
    $target = $null
    $isPage = $false
    if ($pageOf.ContainsKey($repoPath)) { $target = $pageOf[$repoPath]; $isPage = $true }
    elseif ($repoPath -eq '') { $target = 'index.html'; $isPage = $true }
    elseif ($repoPath -eq 'docs') { $target = $docsIndexPage; $isPage = $true }
    elseif ($pageOf.ContainsKey("$repoPath/README.md")) { $target = $pageOf["$repoPath/README.md"]; $isPage = $true }
    elseif (Test-Path -LiteralPath $full -PathType Leaf) {
        $extension = [System.IO.Path]::GetExtension($repoPath).ToLowerInvariant()
        if ($Attribute -eq 'src' -or $extension -in $imageExtensions -or $repoPath -like 'docs/label/*') {
            [void]$copies.Add($repoPath); $target = $repoPath
        } else {
            return ConvertTo-HtmlText ((Get-RepositoryUrl 'blob' $repoPath) + $(if ($null -ne $fragment) { "#$fragment" }))
        }
    } elseif (Test-Path -LiteralPath $full -PathType Container) {
        return ConvertTo-HtmlText (Get-RepositoryUrl 'tree' $repoPath)
    } else {
        $warnings.Add("${Page}: $raw does not exist"); return $Value
    }
    $url = if ($target -ceq $Page -and $null -ne $fragment) { '' } else { Get-RelativeUrl $Page $target }
    if ($null -ne $fragment) { $url += '#' + $(if ($isPage) { $fragment.ToLowerInvariant() } else { $fragment }) }
    return ConvertTo-HtmlText $url
}

# The rendered Markdown of one source, with its links rewritten for $Page and the differences from GitHub fixed.
function Convert-Markdown([string]$Markdown, [string]$Source, [string]$Page) {
    $html = [Markdig.Markdown]::ToHtml($Markdown, $pipeline)
    $sourceDir = if ($Source.Contains('/')) { $Source.Substring(0, $Source.LastIndexOf('/')) } else { '' }
    $sourcePage = if ($pageOf.ContainsKey($Source)) { $pageOf[$Source] } else { $Page }
    # GitHub reads \| in a table cell as a pipe, inside code spans too; Markdig keeps the backslash there.
    $html = [regex]::Replace($html, '(?s)<table>.*?</table>', {
            param($m) [regex]::Replace($m.Value, '(?s)<code>.*?</code>', { param($c) $c.Value.Replace('\|', '|') })
        })
    # Images from other hosts (badges) become their text, so the site requests nothing from another host.
    $html = [regex]::Replace($html, '<img\b[^>]*>', {
            param($m)
            $src = [regex]::Match($m.Value, '\ssrc="([^"]*)"').Groups[1].Value
            if ($src -notmatch '^(https?:)?//') { return $m.Value }
            $alt = [regex]::Match($m.Value, '\salt="([^"]*)"').Groups[1].Value
            return "<span class=`"badge`">$alt</span>"
        })
    $html = [regex]::Replace($html, '(?<=<[a-zA-Z][^>]*\s)(href|src)="([^"]*)"', {
            param($m) "$($m.Groups[1].Value)=`"$(Convert-Link $m.Groups[2].Value $sourceDir $sourcePage $Page $m.Groups[1].Value)`""
        })
    # Wide tables scroll in their own box, not the page.
    $html = $html.Replace('<table>', '<div class="table-wrap"><table>').Replace('</table>', '</table></div>')
    return $html
}

function Get-Headings([string]$Html, [int[]]$Levels) {
    $found = [System.Collections.Generic.List[object]]::new()
    foreach ($m in [regex]::Matches($Html, '(?s)<h([1-6])\b[^>]*\bid="([^"]+)"[^>]*>(.*?)</h\1>')) {
        $level = [int]$m.Groups[1].Value
        if ($level -notin $Levels) { continue }
        $inner = [regex]::Replace($m.Groups[3].Value, '<(?!/?code\b)[^>]+>', '')
        $found.Add([pscustomobject]@{ Level = $level; Id = $m.Groups[2].Value; Html = $inner; Text = ConvertTo-PlainText $inner })
    }
    return $found
}
function Get-PageTitle([string]$Html) {
    $m = [regex]::Match($Html, '(?s)<h1\b[^>]*>(.*?)</h1>')
    if ($m.Success) { return ConvertTo-PlainText $m.Groups[1].Value }
    return ''
}
# The first sentence of the first paragraph with text after the page's heading.
function Get-FirstSentence([string]$Html) {
    $start = [regex]::Match($Html, '(?s)</h1>')
    $from = if ($start.Success) { $start.Index } else { 0 }
    foreach ($m in [regex]::Matches($Html.Substring($from), '(?s)<p\b[^>]*>(.*?)</p>')) {
        $text = ConvertTo-PlainText $m.Groups[1].Value
        if ($text.Length -lt 3) { continue }
        $sentence = [regex]::Match($text, '^(.{12,}?[.!?:])(?=\s+[A-Z(\[`"]|$)')
        $text = if ($sentence.Success) { $sentence.Groups[1].Value } else { $text }
        $text = $text.TrimEnd(':') + $(if ($text.EndsWith(':')) { '.' })
        if ($text.Length -gt 240) { $text = $text.Substring(0, $text.LastIndexOf(' ', 236)) + ' ...' }
        return $text
    }
    return ''
}

function New-Toc([string]$Html) {
    $headings = @(Get-Headings $Html 2, 3)
    if ($headings.Count -lt 4 -or (ConvertTo-PlainText $Html).Length -lt 4000) { return '' }
    $sb = [System.Text.StringBuilder]::new()
    [void]$sb.Append('<details class="toc"><summary>On this page</summary><nav aria-label="On this page"><ul>')
    $open = $false
    $openSub = $false
    foreach ($h in $headings) {
        if ($h.Level -eq 2 -or -not $open) {
            if ($openSub) { [void]$sb.Append('</ul>'); $openSub = $false }
            if ($open) { [void]$sb.Append('</li>') }
            [void]$sb.Append("<li><a href=`"#$($h.Id)`">$($h.Html)</a>")
            $open = $true
        } else {
            if (-not $openSub) { [void]$sb.Append('<ul>'); $openSub = $true }
            [void]$sb.Append("<li><a href=`"#$($h.Id)`">$($h.Html)</a></li>")
        }
    }
    if ($openSub) { [void]$sb.Append('</ul>') }
    if ($open) { [void]$sb.Append('</li>') }
    [void]$sb.Append('</ul></nav></details>')
    return $sb.ToString()
}

# --- The labels ------------------------------------------------------------------------------------------------------------
$labelDir = Join-Path $Root 'docs/label'
$labelSvgs = @(if (Test-Path -LiteralPath $labelDir) { Get-ChildItem -LiteralPath $labelDir -File -Filter '*.svg' | Sort-Object Name -Descending })
function Get-Field($Object, [string]$Name) {
    if ($null -ne $Object -and $Object.PSObject.Properties[$Name]) { return $Object.$Name }
    return $null
}
function New-LabelGallery([string]$Page) {
    if (-not $labelSvgs.Count) {
        return '<p class="note">No version has been rated yet. When <code>benchmark/Get-HyperdotLabel.ps1 -OutDir docs/label</code> has written a version''s labels, they appear here with their information sheets.</p>'
    }
    $groups = [ordered]@{}
    $tested = $null
    foreach ($svg in $labelSvgs) {
        $name = $svg.BaseName
        $jsonPath = Join-Path $labelDir "$name.json"
        $sheet = if (Test-Path -LiteralPath $jsonPath) { Get-Content -LiteralPath $jsonPath -Raw | ConvertFrom-Json } else { $null }
        $programme = Get-Field $sheet 'programmeName'
        if (-not $programme) { $programme = 'Labels' }
        $version = Get-Field $sheet 'version'
        $model = Get-Field $sheet 'modelName'
        if (-not $model) { $model = Get-Field $sheet 'model' }
        $class = Get-Field $sheet 'class'
        $coverage = Get-Field $sheet 'coverage'
        if (-not $tested -and (Get-Field $coverage 'class')) { $tested = [pscustomobject]@{ Class = $coverage.class; Version = $version } }
        $caption = @(
            $(if ($version) { "$siteName $version" })
            $(if ($model) { "$model$(if (Get-Field $sheet 'plugin') { ' with the plugin' })" })
            $(if ($sheet) { if ($class) { "class $class" } else { 'no class' } })
        ) | Where-Object { $_ }
        if (-not $caption) { $caption = @($name) }
        $alt = "$siteName label: $($programme.ToLowerInvariant()), $(@($caption) -join ', ')"
        $links = [System.Collections.Generic.List[string]]::new()
        if ($pageOf.ContainsKey("docs/label/$name.md")) { $links.Add("<a href=`"$(Get-RelativeUrl $Page $pageOf["docs/label/$name.md"])`">Information sheet</a>") }
        if (Test-Path -LiteralPath $jsonPath) { [void]$copies.Add("docs/label/$name.json"); $links.Add("<a href=`"$(Get-RelativeUrl $Page "docs/label/$name.json")`">JSON</a>") }
        [void]$copies.Add("docs/label/$($svg.Name)")
        $figure = "<figure class=`"label`"><img src=`"$(Get-RelativeUrl $Page "docs/label/$($svg.Name)")`" alt=`"$(ConvertTo-HtmlText $alt)`" width=`"400`" height=`"560`" loading=`"lazy`">" +
            "<figcaption>$(ConvertTo-HtmlText (@($caption) -join ", "))$(if ($links.Count) { '<br>' + ($links -join " $dot ") })</figcaption></figure>"
        if (-not $groups.Contains($programme)) { $groups[$programme] = [System.Collections.Generic.List[string]]::new() }
        $groups[$programme].Add($figure)
    }
    $sb = [System.Text.StringBuilder]::new()
    if ($tested) { [void]$sb.Append("<p class=`"note`">Tested class of $siteName $(ConvertTo-HtmlText $tested.Version): <strong>$(ConvertTo-HtmlText $tested.Class)</strong>, from what the self-tests reach.</p>") }
    foreach ($programme in $groups.Keys) {
        [void]$sb.Append("<h3>$(ConvertTo-HtmlText $programme)</h3><div class=`"labels`">$($groups[$programme] -join '')</div>")
    }
    return $sb.ToString()
}

# A section of a Markdown file: the heading that matches $Pattern at $Level, to the next heading at that level or above.
function Get-MarkdownSection([string]$Source, [int]$Level, [string]$Pattern) {
    $path = Join-Path $Root $Source
    if (-not (Test-Path -LiteralPath $path)) { return @() }
    $sections = [System.Collections.Generic.List[string]]::new()
    $current = $null
    $inFence = $false
    foreach ($line in [System.IO.File]::ReadAllLines($path)) {
        if ($line -match '^\s*(```|~~~)') { $inFence = -not $inFence }
        $heading = if (-not $inFence -and $line -match '^(#{1,6})\s+(.*)$') { [pscustomobject]@{ Level = $Matches[1].Length; Text = $Matches[2] } } else { $null }
        if ($heading -and $null -ne $current -and $heading.Level -le $Level) { $sections.Add($current.ToString()); $current = $null }
        if ($heading -and $heading.Level -eq $Level -and $heading.Text -match $Pattern) { $current = [System.Text.StringBuilder]::new() }
        if ($null -ne $current) { [void]$current.AppendLine($line) }
    }
    if ($null -ne $current) { $sections.Add($current.ToString()) }
    return $sections
}

# --- The page around the content -------------------------------------------------------------------------------------------
$template = [System.IO.File]::ReadAllText((Join-Path $PSScriptRoot 'template.html'))
$iconPath = 'docs/assets/hyperdot-logo.svg'
if (Test-Path -LiteralPath (Join-Path $Root $iconPath) -PathType Leaf) { [void]$copies.Add($iconPath) } else { $iconPath = $null }
$navItems = @(
    @{ Text = 'Home'; Target = 'index.html'; Current = { param($p) $p.Page -eq 'index.html' } }
    @{ Text = 'Quick start'; Target = 'index.html#quick-start'; Current = { param($p) $false } }
    @{ Text = 'Label'; Target = 'docs/label.html'; Current = { param($p) $p.Page -eq 'docs/label.html' -or $p.Kind -eq 'sheet' } }
    @{ Text = 'Benchmark'; Target = $benchmarkPage; Current = { param($p) $p.Page -in $benchmarkPage, 'docs/token-benchmark.html' } }
    @{ Text = 'Docs'; Target = $docsIndexPage; Current = { param($p) $p.Kind -in 'doc', 'docs-index' -and $p.Page -notin 'docs/label.html', 'docs/token-benchmark.html' } }
    @{ Text = 'Changelog'; Target = 'changelog.html'; Current = { param($p) $p.Page -eq 'changelog.html' } }
)
function New-PageHtml($PageInfo, [string]$Content, [string]$Toc, [string]$SourceUrl) {
    $page = $PageInfo.Page
    $nav = [System.Text.StringBuilder]::new()
    foreach ($item in $navItems) {
        $current = if (& $item.Current $PageInfo) { ' aria-current="page"' } else { '' }
        [void]$nav.Append("<li><a href=`"$(Get-RelativeUrl $page $item.Target)`"$current>$($item.Text)</a></li>")
    }
    [void]$nav.Append("<li><a href=`"$Repository`">GitHub</a></li>")
    $title = if ($PageInfo.Title -and $PageInfo.Title -ne $siteName) { "$(ConvertTo-HtmlText $PageInfo.Title) $dot $siteName" } else { $siteName }
    $short = $Commit.Substring(0, [Math]::Min(7, $Commit.Length))
    $values = [ordered]@{
        '{{TITLE}}'       = $title
        '{{DESCRIPTION}}' = ConvertTo-HtmlText $PageInfo.Summary
        '{{ROOT}}'        = Get-RootPrefix $page
        '{{HOME}}'        = Get-RelativeUrl $page 'index.html'
        '{{NAV}}'         = $nav.ToString()
        '{{PAGECLASS}}'   = "page page-$($PageInfo.Kind)$(if ($Toc) { ' has-toc' })"
        '{{ICON}}'        = $(if ($iconPath) { "<link rel=`"icon`" href=`"$(Get-RelativeUrl $page $iconPath)`" type=`"image/svg+xml`">" } else { '' })
        '{{TOC}}'         = $Toc
        '{{SOURCE}}'      = ConvertTo-HtmlText $SourceUrl
        '{{COMMITURL}}'   = ConvertTo-HtmlText "$Repository/tree/$Commit"
        '{{COMMIT}}'      = $short
        '{{LICENCEURL}}'  = ConvertTo-HtmlText (Get-RepositoryUrl 'blob' 'LICENSE')
    }
    $html = $template
    foreach ($key in $values.Keys) { $html = $html.Replace($key, [string]$values[$key]) }
    return $html.Replace('{{CONTENT}}', $Content)
}

# --- Build -------------------------------------------------------------------------------------------------------------------
if (Test-Path -LiteralPath $Out) {
    $rootWithSep = $Root.TrimEnd([System.IO.Path]::DirectorySeparatorChar) + [System.IO.Path]::DirectorySeparatorChar
    if ($Out -eq $Root -or $rootWithSep.StartsWith($Out.TrimEnd([System.IO.Path]::DirectorySeparatorChar) + [System.IO.Path]::DirectorySeparatorChar)) {
        throw "-Out $Out holds the repository; give a folder of its own"
    }
    $existing = @(Get-ChildItem -LiteralPath $Out -Force)
    if ($existing.Count -and -not (Test-Path -LiteralPath (Join-Path $Out $marker))) {
        throw "-Out $Out is not empty and holds no earlier build ($marker); give an empty or new folder"
    }
    foreach ($item in $existing) { Remove-Item -LiteralPath $item.FullName -Recurse -Force }
}
New-Item -ItemType Directory -Force -Path $Out | Out-Null
[System.IO.File]::WriteAllText((Join-Path $Out $marker), "Built by site/Build-Site.ps1; the folder is emptied by the next build.`n", $utf8)

foreach ($p in $pages) {
    $markdown = [System.IO.File]::ReadAllText((Join-Path $Root $p.Source))
    $p.Html = Convert-Markdown $markdown $p.Source $p.Page
    $p.Title = Get-PageTitle $p.Html
    if (-not $p.Title) { $warnings.Add("$($p.Source) has no level-1 heading"); $p.Title = [System.IO.Path]::GetFileNameWithoutExtension($p.Source) }
    $p.Summary = Get-FirstSentence $p.Html
}

# The label page shows the labels where docs/label.md marks the rating, or before its first section.
foreach ($p in @($pages | Where-Object { $_.Page -eq 'docs/label.html' })) {
    $gallery = "<section class=`"rating`" aria-labelledby=`"labels`"><h2 id=`"labels`">Labels</h2>$(New-LabelGallery $p.Page)</section>"
    if ($p.Html.Contains('<!-- RATING -->')) { $p.Html = $p.Html.Replace('<!-- RATING -->', $gallery) }
    else {
        $at = $p.Html.IndexOf('<h2')
        $p.Html = if ($at -ge 0) { $p.Html.Insert($at, $gallery) } else { $p.Html + $gallery }
    }
}

foreach ($p in $pages) {
    $toc = New-Toc $p.Html
    $searchEntries.Add(@($p.Title, $p.Page, ''))
    foreach ($h in @(Get-Headings $p.Html 2, 3)) { $searchEntries.Add(@($h.Text, "$($p.Page)#$($h.Id)", $p.Title)) }
    Write-SiteFile $p.Page (New-PageHtml $p $p.Html $toc (Get-RepositoryUrl 'blob' $p.Source))
}

# The docs index: groups from the README's "Documentation" section, then the GDC notes, the label sheets and the rest.
$groups = [ordered]@{}
$groupOf = @{}
$readmeGroups = [System.Collections.Generic.List[string]]::new()
$rankOf = @{}
$readme = Join-Path $Root 'README.md'
if (Test-Path -LiteralPath $readme) {
    $inDocs = $false
    $group = $null
    foreach ($line in [System.IO.File]::ReadAllLines($readme)) {
        if ($line -match '^##\s') { $inDocs = $line -match '^##\s+Documentation\s*$'; continue }
        if (-not $inDocs) { continue }
        if ($line -match '^\*\*(?<g>[^*]+)\*\*\s*$') { $group = $Matches.g.Trim(); continue }
        if ($group -and $line -match '^\s*[-*]\s+\[[^\]]*\]\((?<p>docs/[^)#\s]+\.md)') {
            if (-not $groupOf.ContainsKey($Matches.p)) { $groupOf[$Matches.p] = $group; $rankOf[$Matches.p] = $rankOf.Count }
            if (-not $readmeGroups.Contains($group)) { $readmeGroups.Add($group) }
        }
    }
}
foreach ($p in @($pages | Where-Object { $_.Kind -in 'doc', 'sheet' })) {
    $group = if ($groupOf.ContainsKey($p.Source)) { $groupOf[$p.Source] }
    elseif ($p.Source -like 'docs/gdc/*') { 'GDC talks' }
    elseif ($p.Kind -eq 'sheet') { 'Label information sheets' }
    else { 'More' }
    if (-not $groups.Contains($group)) { $groups[$group] = [System.Collections.Generic.List[object]]::new() }
    $groups[$group].Add($p)
}
$order = @(@($readmeGroups) + @('More', 'GDC talks', 'Label information sheets') | Where-Object { $groups.Contains($_) })
$index = [System.Text.StringBuilder]::new()
[void]$index.Append('<h1 id="documentation">Documentation</h1>')
[void]$index.Append("<p>Every page of $siteName's documentation, each with its first sentence, grouped as the README groups them. The <a href=`"../index.html#quick-start`">quick start</a> is the place to begin.</p>")
[void]$index.Append('<form class="search" role="search" hidden><label for="search-q">Search titles and headings</label><input id="search-q" type="search" autocomplete="off" spellcheck="false"><ul id="search-results" aria-live="polite"></ul></form>')
[void]$index.Append('<nav aria-label="Groups" class="groups"><ul>')
$groupIds = @{}
foreach ($group in $order) {
    $id = ($group.ToLowerInvariant() -replace '[^\p{L}\p{M}\p{N}\p{Pc}\- ]', '' -replace ' ', '-')
    $groupIds[$group] = $id
    [void]$index.Append("<li><a href=`"#$id`">$(ConvertTo-HtmlText $group)</a></li>")
}
[void]$index.Append('</ul></nav>')
foreach ($group in $order) {
    $items = @($groups[$group])
    $items = if ($group -in $readmeGroups) { @($items | Sort-Object { $rankOf[$_.Source] }) } else { @($items | Sort-Object { $_.Source -notlike '*/README.md' }, Title) }
    [void]$index.Append("<h2 id=`"$($groupIds[$group])`">$(ConvertTo-HtmlText $group)</h2><ul class=`"doc-list`">")
    foreach ($p in $items) {
        [void]$index.Append("<li><a href=`"$(Get-RelativeUrl $docsIndexPage $p.Page)`">$(ConvertTo-HtmlText $p.Title)</a>$(if ($p.Summary) { "<p>$(ConvertTo-HtmlText $p.Summary)</p>" })</li>")
    }
    [void]$index.Append('</ul>')
}
$indexInfo = [pscustomobject]@{ Source = ''; Page = $docsIndexPage; Kind = 'docs-index'; Title = 'Documentation'; Summary = "Every page of $siteName's documentation, grouped."; Html = $index.ToString() }
$searchEntries.Add(@('Documentation', $docsIndexPage, ''))
Write-SiteFile $docsIndexPage (New-PageHtml $indexInfo $indexInfo.Html '' (Get-RepositoryUrl 'blob' 'site/Build-Site.ps1'))

# The benchmark page: the labels, the reference runs from docs/token-benchmark.md and the field test from docs/label.md.
$bench = [System.Text.StringBuilder]::new()
[void]$bench.Append('<h1 id="benchmark-results">Benchmark results</h1>')
[void]$bench.Append("<p>How many tokens an AI agent spends per task it gets right, measured by $siteName's token benchmark and rated by its label. ")
[void]$bench.Append("The method is on the <a href=`"$(Get-RelativeUrl $benchmarkPage 'docs/label.html')`">label page</a>; how to run the benchmark, in <a href=`"$(Get-RelativeUrl $benchmarkPage 'docs/token-benchmark.html')`">Token benchmark</a>.</p>")
[void]$bench.Append("<section aria-labelledby=`"labels`"><h2 id=`"labels`">Labels</h2>$(New-LabelGallery $benchmarkPage)</section>")
$extracts = @(
    @{ Source = 'docs/token-benchmark.md'; Level = 2; Pattern = '^Reference runs' }
    @{ Source = 'docs/label.md'; Level = 3; Pattern = '^Field test' }
)
foreach ($extract in $extracts) {
    foreach ($section in @(Get-MarkdownSection $extract.Source $extract.Level $extract.Pattern)) {
        $html = Convert-Markdown ($section -replace '^#{2,6}', '##') $extract.Source $benchmarkPage
        $from = if ($pageOf.ContainsKey($extract.Source)) { "<p class=`"from`">From <a href=`"$(Get-RelativeUrl $benchmarkPage $pageOf[$extract.Source])`">$(ConvertTo-HtmlText (@($pages | Where-Object Source -eq $extract.Source)[0].Title))</a>.</p>" } else { '' }
        [void]$bench.Append("<section>$html$from</section>")
    }
}
$benchInfo = [pscustomobject]@{ Source = ''; Page = $benchmarkPage; Kind = 'benchmark'; Title = 'Benchmark results'; Summary = 'How many tokens an AI agent spends per task it gets right, measured by the token benchmark and rated by the label.'; Html = $bench.ToString() }
$searchEntries.Add(@('Benchmark results', $benchmarkPage, ''))
Write-SiteFile $benchmarkPage (New-PageHtml $benchInfo $benchInfo.Html (New-Toc $benchInfo.Html) (Get-RepositoryUrl 'blob' 'site/Build-Site.ps1'))

# Static files, the search index, the label files and the images the pages use.
foreach ($name in 'site.css', 'site.js') {
    New-Item -ItemType Directory -Force -Path (Join-Path $Out 'static') | Out-Null
    Copy-Item -LiteralPath (Join-Path $PSScriptRoot $name) -Destination (Join-Path $Out "static/$name")
}
Write-SiteFile 'static/search-index.json' (ConvertTo-Json -InputObject @($searchEntries) -Compress -Depth 3)
if (Test-Path -LiteralPath $labelDir) {
    foreach ($file in @(Get-ChildItem -LiteralPath $labelDir -Recurse -File | Where-Object Extension -ne '.md')) {
        [void]$copies.Add(([System.IO.Path]::GetRelativePath($Root, $file.FullName) -replace '\\', '/'))
    }
}
foreach ($repoPath in $copies) {
    $to = Join-Path $Out $repoPath
    New-Item -ItemType Directory -Force -Path (Split-Path $to) | Out-Null
    Copy-Item -LiteralPath (Join-Path $Root $repoPath) -Destination $to -Force
}

foreach ($w in $warnings) { Write-Host "warning: $w" }
Write-Host "Built $($pages.Count + 2) pages ($($pages.Count) from Markdown) and copied $($copies.Count) files into $Out (commit $Commit)"
if (-not $Serve) { exit 0 }

# -Serve: the built site at http://localhost:<Port>/hyperdot/, the path it has on github.io, until Ctrl+C.
$types = @{ '.html' = 'text/html; charset=utf-8'; '.css' = 'text/css; charset=utf-8'; '.js' = 'text/javascript; charset=utf-8'
    '.json' = 'application/json'; '.svg' = 'image/svg+xml'; '.png' = 'image/png'; '.jpg' = 'image/jpeg'; '.jpeg' = 'image/jpeg'; '.gif' = 'image/gif'; '.webp' = 'image/webp' }
$listener = [System.Net.HttpListener]::new()
$listener.Prefixes.Add("http://localhost:$Port/")
$listener.Start()
Write-Host "Serving $Out at http://localhost:$Port/hyperdot/ (Ctrl+C stops it)"
$outRoot = $Out.TrimEnd([System.IO.Path]::DirectorySeparatorChar) + [System.IO.Path]::DirectorySeparatorChar
try {
    while ($listener.IsListening) {
        $context = $listener.GetContext()
        $response = $context.Response
        $path = [uri]::UnescapeDataString($context.Request.Url.AbsolutePath)
        if (-not $path.StartsWith('/hyperdot/')) { $response.Redirect('/hyperdot/'); $response.Close(); continue }
        $relative = $path.Substring('/hyperdot/'.Length)
        if ($relative -eq '' -or $relative.EndsWith('/')) { $relative += 'index.html' }
        $file = [System.IO.Path]::GetFullPath((Join-Path $Out $relative))
        if ($file.StartsWith($outRoot) -and (Test-Path -LiteralPath $file -PathType Leaf)) {
            $extension = [System.IO.Path]::GetExtension($file).ToLowerInvariant()
            $response.ContentType = if ($types.ContainsKey($extension)) { $types[$extension] } else { 'application/octet-stream' }
            $bytes = [System.IO.File]::ReadAllBytes($file)
        } else {
            $response.StatusCode = 404
            $response.ContentType = 'text/plain; charset=utf-8'
            $bytes = [System.Text.Encoding]::UTF8.GetBytes("Not found: $path")
        }
        $response.ContentLength64 = $bytes.Length
        $response.OutputStream.Write($bytes, 0, $bytes.Length)
        $response.Close()
    }
} finally {
    $listener.Stop()
}
exit 0
