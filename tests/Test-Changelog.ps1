#!/usr/bin/env pwsh
# Self-test of ci/godot/tools/Update-Changelog.ps1 in temporary folders: fragments grouped by category in the fixed
# order and sorted by slug, an empty or missing changelog.d/ changing nothing, a bad fragment refused with its file name
# and nothing written or deleted, the old Unreleased text kept first in the new section, a repeated version refused,
# and the real changelog.d/ of this repository valid. Needs no Godot.
Set-StrictMode -Version 3.0
$ErrorActionPreference = 'Stop'
$root = Split-Path $PSScriptRoot
$tool = Join-Path $root 'ci/godot/tools/Update-Changelog.ps1'
$failures = @()
function Assert-True([bool]$Condition, [string]$Name) {
    if ($Condition) { Write-Host "ok     $Name" } else { Write-Host "FAIL   $Name"; $script:failures += $Name }
}
function Invoke-Tool([string]$Repo, [string[]]$ToolArgs) {
    $out = & pwsh -NoProfile -NonInteractive -File $tool @ToolArgs -Root $Repo 2>&1 | Out-String
    return [pscustomobject]@{ Code = $LASTEXITCODE; Out = $out }
}
function New-Repo([string]$Name) {
    $repo = Join-Path $script:base $Name
    New-Item -ItemType Directory -Force (Join-Path $repo 'changelog.d') | Out-Null
    Set-Content -LiteralPath (Join-Path $repo 'CHANGELOG.md') "# Changelog`n`n## Unreleased`n- **Old entry.** Written before fragments.`n  Second line.`n`n## Earlier`nOlder things.`n" -NoNewline
    return $repo
}
function Set-Fragment([string]$Repo, [string]$Name, [string]$Text) { Set-Content -LiteralPath (Join-Path $Repo "changelog.d/$Name") $Text -NoNewline }

$base = Join-Path ([System.IO.Path]::GetTempPath()) "changelog-$([guid]::NewGuid().ToString('n').Substring(0, 8))"
try {
    # Grouping, ordering, the old text, deletion.
    $repo = New-Repo 'ok'
    Set-Fragment $repo 'b-fix.md' 'Fixed: second fix'
    Set-Fragment $repo 'a-fix.md' "Fixed: first fix`ncontinues here"
    Set-Fragment $repo 'new-thing.md' 'Added: a thing'
    Set-Fragment $repo 'tweak.md' 'Changed: a tweak'
    Set-Fragment $repo 'README.md' 'not a fragment at all'
    $r = Invoke-Tool $repo @('-Version', '0.1.0', '-Date', '2026-11-01')
    $text = Get-Content -Raw -LiteralPath (Join-Path $repo 'CHANGELOG.md')
    Assert-True ($r.Code -eq 0) "assembles: $($r.Out)"
    Assert-True ($text -match '(?s)^# Changelog\n\n## Unreleased\n\n## 0\.1\.0 - 2026-11-01\n') 'an empty Unreleased heading above the dated version'
    Assert-True ($text.IndexOf('### Added') -lt $text.IndexOf('### Changed') -and $text.IndexOf('### Changed') -lt $text.IndexOf('### Fixed')) 'categories in the fixed order'
    Assert-True ($text.Contains("- first fix`n  continues here`n- second fix")) 'entries sorted by slug, continuation lines indented'
    Assert-True ($text.IndexOf('Old entry') -lt $text.IndexOf('### Added') -and $text.Contains("Second line.`n`n### Added")) 'the old Unreleased text stays first in the new section'
    Assert-True ($text.IndexOf('## 0.1.0') -lt $text.IndexOf('## Earlier') -and $text.Contains("## Earlier`nOlder things.")) 'the previous sections stay below'
    Assert-True (-not (Test-Path -LiteralPath (Join-Path $repo 'changelog.d/a-fix.md')) -and (Test-Path -LiteralPath (Join-Path $repo 'changelog.d/README.md'))) 'fragments deleted, README kept'
    Assert-True ($text -notmatch 'not a fragment') 'README.md is not read as a fragment'
    $r = Invoke-Tool $repo @('-Version', '0.1.0')
    Assert-True ($r.Code -eq 0 -and $text -eq (Get-Content -Raw -LiteralPath (Join-Path $repo 'CHANGELOG.md'))) 'a second run without fragments changes nothing'

    # Empty directory, missing directory.
    $repo = New-Repo 'empty'
    $before = Get-Content -Raw -LiteralPath (Join-Path $repo 'CHANGELOG.md')
    $r = Invoke-Tool $repo @('-Version', '0.1.0')
    Assert-True ($r.Code -eq 0 -and $r.Out -match 'No fragments' -and $before -eq (Get-Content -Raw -LiteralPath (Join-Path $repo 'CHANGELOG.md'))) 'an empty changelog.d/ leaves CHANGELOG.md alone'
    Remove-Item -LiteralPath (Join-Path $repo 'changelog.d') -Recurse
    $r = Invoke-Tool $repo @('-Version', '0.1.0')
    Assert-True ($r.Code -eq 0 -and $r.Out -match 'No fragments') 'no changelog.d/ at all is the same'

    # Bad fragments: refused with the file name, nothing written or deleted.
    foreach ($case in @(
            @{ Name = 'no category'; File = 'x.md'; Text = 'just some words'; Match = 'x\.md.*first line must be' },
            @{ Name = 'unknown category'; File = 'x.md'; Text = 'Improved: stuff'; Match = "x\.md.*unknown category 'Improved'" },
            @{ Name = 'lower-case category'; File = 'x.md'; Text = 'fixed: stuff'; Match = "x\.md.*unknown category 'fixed'" },
            @{ Name = 'empty entry'; File = 'x.md'; Text = 'Added:   '; Match = 'x\.md.*is empty' },
            @{ Name = 'empty file'; File = 'x.md'; Text = ''; Match = 'x\.md.*is empty' },
            @{ Name = 'bad file name'; File = 'Bad Name.md'; Text = 'Added: fine'; Match = 'Bad Name\.md.*file name' },
            @{ Name = 'wrong extension'; File = 'x.txt'; Text = 'Added: fine'; Match = 'x\.txt.*file name' })) {
        $repo = New-Repo 'bad'
        Set-Fragment $repo 'good.md' 'Added: good one'
        Set-Fragment $repo $case.File $case.Text
        $before = Get-Content -Raw -LiteralPath (Join-Path $repo 'CHANGELOG.md')
        $r = Invoke-Tool $repo @('-Version', '0.2.0')
        Assert-True ($r.Code -ne 0 -and $r.Out -match $case.Match) "refused, naming the file: $($case.Name) ($($r.Out.Trim() -replace '\s+', ' '))"
        Assert-True ($before -eq (Get-Content -Raw -LiteralPath (Join-Path $repo 'CHANGELOG.md')) -and (Test-Path -LiteralPath (Join-Path $repo 'changelog.d/good.md'))) "nothing written or deleted: $($case.Name)"
        Remove-Item -LiteralPath $repo -Recurse -Force
    }

    # Version and date arguments, a repeated version, a missing heading, -Check.
    $repo = New-Repo 'args'
    Set-Fragment $repo 'one.md' 'Added: one'
    $r = Invoke-Tool $repo @('-Version', 'v1')
    Assert-True ($r.Code -ne 0 -and $r.Out -match 'semantic version') 'a bad -Version is refused'
    $r = Invoke-Tool $repo @()
    Assert-True ($r.Code -ne 0 -and $r.Out -match 'semantic version') 'a missing -Version is refused'
    $r = Invoke-Tool $repo @('-Check')
    Assert-True ($r.Code -eq 0 -and $r.Out -match '1 fragment' -and (Test-Path -LiteralPath (Join-Path $repo 'changelog.d/one.md'))) '-Check validates and changes nothing'
    $r = Invoke-Tool $repo @('-Version', '0.3.0', '-Date', '2026-12-01')
    Assert-True ($r.Code -eq 0) 'a release'
    Set-Fragment $repo 'two.md' 'Added: two'
    $r = Invoke-Tool $repo @('-Version', '0.3.0', '-Date', '2026-12-02')
    Assert-True ($r.Code -ne 0 -and $r.Out -match 'already has a section for 0\.3\.0' -and (Test-Path -LiteralPath (Join-Path $repo 'changelog.d/two.md'))) 'a repeated version is refused'
    $r = Invoke-Tool $repo @('-Version', '0.4.0', '-Date', '2026-12-02')
    $text = Get-Content -Raw -LiteralPath (Join-Path $repo 'CHANGELOG.md')
    Assert-True ($r.Code -eq 0 -and $text.IndexOf('## 0.4.0') -lt $text.IndexOf('## 0.3.0')) 'a later release goes above the earlier one'
    Set-Content -LiteralPath (Join-Path $repo 'CHANGELOG.md') "# Changelog`n"
    Set-Fragment $repo 'three.md' 'Added: three'
    $r = Invoke-Tool $repo @('-Version', '0.5.0')
    Assert-True ($r.Code -ne 0 -and $r.Out -match 'no "## Unreleased" heading') 'a changelog without Unreleased is refused'

    # This repository's own fragments are valid.
    $r = Invoke-Tool $root @('-Check')
    Assert-True ($r.Code -eq 0) "the fragments in changelog.d/ are valid: $($r.Out.Trim())"
}
finally {
    if (Test-Path -LiteralPath $base) { Remove-Item -LiteralPath $base -Recurse -Force }
}
if ($failures.Count) { Write-Host "`n$($failures.Count) failed"; exit 1 }
Write-Host "`nAll checks passed."
