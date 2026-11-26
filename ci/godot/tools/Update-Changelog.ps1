#Requires -Version 7.6
<#
.SYNOPSIS
    Assembles the fragments in changelog.d/ into CHANGELOG.md for a release, and deletes them.

.DESCRIPTION
    Every change adds one small file, changelog.d/<slug>.md, so pull requests no longer collide on the top lines of
    CHANGELOG.md. A fragment is Markdown whose first line is `<Category>: <entry>`, with Category one of Added, Changed,
    Fixed, Removed, Deprecated or Security; later lines continue the entry (indent them). The slug is lower-case letters,
    digits and hyphens. changelog.d/README.md is not a fragment.

    The new section is `## <Version> - <Date>`. It takes the text under the current `## Unreleased` heading first (the
    entries written before fragments existed stay as they are), then one `### <Category>` group per category in the order
    above, each with its entries sorted by slug. A fresh, empty `## Unreleased` heading is left above it. With no fragments
    nothing is changed. Any bad fragment (no category, unknown category, empty entry, bad file name) stops the run before
    anything is written or deleted, naming the file.

.EXAMPLE
    pwsh ci/godot/tools/Update-Changelog.ps1 -Version 0.1.0
.EXAMPLE
    pwsh ci/godot/tools/Update-Changelog.ps1 -Version 0.1.0 -Check     # only validate the fragments
.EXAMPLE
    pwsh ci/godot/tools/Update-Changelog.ps1 -Next                     # print the next version (nothing without fragments)

.NOTES
    The next version (-Next, or -Version next) follows the newest `## x.y.z - ` section: the minor goes up when a fragment
    is Added, Removed or Deprecated (something a game can start or stop using), the patch when all are Changed, Fixed or
    Security. The major never goes up on its own; pass that version by hand.
#>
[CmdletBinding()]
param(
    [string]$Version,
    [string]$Date = [datetime]::UtcNow.ToString('yyyy-MM-dd', [cultureinfo]::InvariantCulture),
    [string]$Root = (Join-Path $PSScriptRoot '../../..'),
    # Validate the fragments and print what would be written; change nothing. -Version is not needed.
    [switch]$Check,
    # Print only the next version (see .NOTES), or nothing when there are no fragments; change nothing.
    [switch]$Next
)
Set-StrictMode -Version 3.0
$ErrorActionPreference = 'Stop'

$categories = 'Added', 'Changed', 'Fixed', 'Removed', 'Deprecated', 'Security'
$Root = (Resolve-Path -LiteralPath $Root).Path
$dir = Join-Path $Root 'changelog.d'
$changelog = Join-Path $Root 'CHANGELOG.md'

function Read-Fragment([System.IO.FileInfo]$File) {
    $slug = $File.BaseName
    if ($slug -notmatch '^[a-z0-9][a-z0-9-]*$' -or $File.Extension -ne '.md') {
        throw "changelog.d/$($File.Name): the file name must be <slug>.md with a slug of lower-case letters, digits and hyphens"
    }
    $lines = @([System.IO.File]::ReadAllText($File.FullName).Replace("`r`n", "`n").Trim() -split "`n")
    if ($lines.Count -eq 0 -or -not $lines[0].Trim()) { throw "changelog.d/$($File.Name): the fragment is empty" }
    if ($lines[0] -notmatch '^([A-Za-z]+):\s*(.*)$') {
        throw "changelog.d/$($File.Name): the first line must be '<Category>: <entry>' with Category one of $($categories -join ', ')"
    }
    $category = $categories | Where-Object { $_ -ceq $Matches[1] }
    if (-not $category) { throw "changelog.d/$($File.Name): unknown category '$($Matches[1])'; use one of $($categories -join ', ')" }
    $text = $Matches[2].Trim()
    if (-not $text) { throw "changelog.d/$($File.Name): the entry after '$category`:' is empty" }
    $rest = @($lines | Select-Object -Skip 1 | ForEach-Object { $_.TrimEnd() })
    $body = "- $text" + $(if ($rest.Count) { "`n" + (($rest | ForEach-Object { if ($_) { '  ' + $_.TrimStart() } else { $_ } }) -join "`n") } else { '' })
    return [pscustomobject]@{ Slug = $slug; Category = $category; Text = $body; Path = $File.FullName }
}

$files = @()
if (Test-Path -LiteralPath $dir) {
    $files = @(Get-ChildItem -LiteralPath $dir -File | Where-Object { $_.Name -ne 'README.md' -and $_.Name -ne '.gitkeep' } | Sort-Object { $_.Name } -Culture ([cultureinfo]::InvariantCulture))
}
$fragments = @(foreach ($file in $files) { Read-Fragment $file })

# The newest released version in CHANGELOG.md (0.0.0 before the first), bumped by the kinds of change the fragments hold.
function Get-NextVersion {
    $latest = [version]'0.0.0'
    if (Test-Path -LiteralPath $changelog) {
        foreach ($m in [regex]::Matches([System.IO.File]::ReadAllText($changelog), '(?m)^## ([0-9]+)\.([0-9]+)\.([0-9]+) - ')) {
            $v = [version]::new([int]$m.Groups[1].Value, [int]$m.Groups[2].Value, [int]$m.Groups[3].Value)
            if ($v -gt $latest) { $latest = $v }
        }
    }
    $minor = @($fragments | Where-Object { $_.Category -in 'Added', 'Removed', 'Deprecated' }).Count -gt 0
    if ($minor) { return "$($latest.Major).$($latest.Minor + 1).0" }
    return "$($latest.Major).$($latest.Minor).$($latest.Build + 1)"
}
if ($Next) {
    if ($fragments.Count) { Get-NextVersion }
    return
}
if ($Version -eq 'next' -and $fragments.Count) { $Version = Get-NextVersion }

if ($fragments.Count -eq 0) { Write-Host 'No fragments in changelog.d/: CHANGELOG.md is unchanged.'; return }

$groups = foreach ($category in $categories) {
    $mine = @($fragments | Where-Object { $_.Category -eq $category } | Sort-Object { $_.Slug } -Culture ([cultureinfo]::InvariantCulture))
    if ($mine.Count) { "### $category`n" + (($mine | ForEach-Object { $_.Text }) -join "`n") }
}
$assembled = $groups -join "`n`n"

if ($Check) { Write-Host "$($fragments.Count) fragment(s) are valid:`n`n$assembled"; return }

if ($Version -notmatch '\A[0-9]+\.[0-9]+\.[0-9]+(-[0-9A-Za-z.-]+)?\z') { throw "-Version must be a semantic version such as 0.1.0, not '$Version'" }
if ($Date -notmatch '^\d{4}-\d{2}-\d{2}$') { throw "-Date must be yyyy-MM-dd, not '$Date'" }

$text = [System.IO.File]::ReadAllText($changelog).Replace("`r`n", "`n")
$m = [regex]::Match($text, '(?m)^## Unreleased[ \t]*\n')
if (-not $m.Success) { throw 'CHANGELOG.md has no "## Unreleased" heading to turn into the new version' }
$tail = $text.Substring($m.Index + $m.Length)
$nextHeading = [regex]::Match($tail, '(?m)^## ')
$legacy = $(if ($nextHeading.Success) { $tail.Substring(0, $nextHeading.Index) } else { $tail }).Trim()
$after = if ($nextHeading.Success) { $tail.Substring($nextHeading.Index) } else { '' }
if ([regex]::IsMatch($text, "(?m)^## $([regex]::Escape($Version))( |$)")) { throw "CHANGELOG.md already has a section for $Version" }

$section = "## $Version - $Date`n" + $(if ($legacy) { "$legacy`n`n" } else { '' }) + "$assembled`n"
$new = $text.Substring(0, $m.Index) + "## Unreleased`n`n" + $section + $(if ($after) { "`n$after" } else { '' })
[System.IO.File]::WriteAllText($changelog, $new, [System.Text.UTF8Encoding]::new($false))
foreach ($fragment in $fragments) { Remove-Item -LiteralPath $fragment.Path }
Write-Host "CHANGELOG.md: $Version - $Date from $($fragments.Count) fragment(s) and the old Unreleased text; fragments deleted."
