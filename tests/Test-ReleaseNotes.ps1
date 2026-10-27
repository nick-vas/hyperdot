#!/usr/bin/env pwsh
# Self-test of .github/scripts/Get-ChangelogSection.ps1 (the release notes of .github/workflows/release.yml) against a
# temporary changelog: the first, a middle and the last section, a missing version, a version that only starts like another
# (0.1.0 and 0.1.01, 0.1.0 and 10.1.0), an empty section and a malformed version. Needs no Godot.
Set-StrictMode -Version 3.0
$ErrorActionPreference = 'Stop'
$root = Split-Path $PSScriptRoot
$tool = Join-Path $root '.github/scripts/Get-ChangelogSection.ps1'
$failures = @()
function Assert-True([bool]$Condition, [string]$Name) {
    if ($Condition) { Write-Host "ok     $Name" } else { Write-Host "FAIL   $Name"; $script:failures += $Name }
}
function Invoke-Section([string]$Version, [string]$Changelog) {
    $out = & pwsh -NoProfile -NonInteractive -File $tool -Version $Version -Changelog $Changelog 2>&1 | Out-String
    return [pscustomobject]@{ Code = $LASTEXITCODE; Out = $out.Trim() -replace "`r", '' }
}

$base = Join-Path ([System.IO.Path]::GetTempPath()) "relnotes-$([guid]::NewGuid().ToString('n').Substring(0, 8))"
New-Item -ItemType Directory -Force $base | Out-Null
try {
    $log = Join-Path $base 'CHANGELOG.md'
    $text = @'
# Changelog

## Unreleased

## 0.2.0 - 2026-11-01
- **Newest.** First section body.

### Added
- Something.

## 0.1.01 - 2026-10-30
- **Look-alike.** Not 0.1.0.

## 0.1.0 - 2026-10-27
- **Middle.** Body of 0.1.0.
  Second line.

## 10.1.0 - 2026-10-20
- **Look-alike.** Not 0.1.0 either.

## 0.0.9 - 2026-10-01

## Earlier
Old things.
'@
    [System.IO.File]::WriteAllText($log, $text.Replace("`r", ''))

    $r = Invoke-Section '0.2.0' $log
    Assert-True ($r.Code -eq 0 -and $r.Out -eq "- **Newest.** First section body.`n`n### Added`n- Something.") 'the first section: its body up to the next heading, subsections kept'
    $r = Invoke-Section '0.1.0' $log
    Assert-True ($r.Code -eq 0 -and $r.Out -eq "- **Middle.** Body of 0.1.0.`n  Second line.") "a middle section, not 0.1.01 or 10.1.0 ($($r.Out))"
    $r = Invoke-Section '0.1.01' $log
    Assert-True ($r.Code -eq 0 -and $r.Out -eq '- **Look-alike.** Not 0.1.0.') 'the section 0.1.01 is its own'
    $r = Invoke-Section '0.1.1' $log
    Assert-True ($r.Code -ne 0 -and $r.Out -match "no section '## 0\.1\.1 - '") 'a missing version fails, naming the heading'
    $r = Invoke-Section '1.0' $log
    Assert-True ($r.Code -ne 0) 'a version that is not x.y.z is refused'
    $r = Invoke-Section '0.0.9' $log
    Assert-True ($r.Code -ne 0 -and $r.Out -match 'is empty') 'an empty section fails'
    $r = Invoke-Section '0.0.8' (Join-Path $base 'missing.md')
    Assert-True ($r.Code -ne 0) 'a missing changelog fails'
    $r = Invoke-Section "0.1.0`n" $log
    Assert-True ($r.Code -ne 0) 'a version with a trailing newline is refused'
    $r = Invoke-Section "0.1.$([char]0x0663)" $log
    Assert-True ($r.Code -ne 0) 'a version with a non-ASCII digit is refused'
    $r = Invoke-Section '0.1.0' (Join-Path $root 'CHANGELOG.md')
    Assert-True ($r.Code -eq 0 -and $r.Out.Length -gt 100) "the real CHANGELOG.md has a 0.1.0 section ($($r.Out.Length) characters)"
}
finally { Remove-Item -LiteralPath $base -Recurse -Force -ErrorAction SilentlyContinue }

# Whether the major tag may move to a release (.github/scripts/Test-MajorTagMove.ps1).
$mover = Join-Path $root '.github/scripts/Test-MajorTagMove.ps1'
function Get-MajorDecision([string]$Version, [string[]]$Tags) {
    $text = (& pwsh -NoProfile -NonInteractive -File $mover -Version $Version -Tags ($Tags -join ',') 2>&1) -join "`n"
    if ($LASTEXITCODE) { return [pscustomobject]@{ move = $null; reason = $text } }
    return $text | ConvertFrom-Json
}
Assert-True ((Get-MajorDecision '1.3.0' 'v1.2.0', 'v1.2.1').move -eq $true) 'a newer release moves the major tag'
Assert-True ((Get-MajorDecision '1.2.1' 'v1.2.0', 'v1.3.0').move -eq $false) 'an older release after 1.3.0 does not move v1'
Assert-True ((Get-MajorDecision '1.3.0' 'v1.2.0', 'v1.3.0').move -eq $true) 'the release that is already tagged moves the major tag again (a repeated run)'
Assert-True ((Get-MajorDecision '1.2.1' 'v2.0.0', 'v1.2.0').move -eq $true) 'a greater version of another major does not hold v1 back'
Assert-True ((Get-MajorDecision '1.10.0' 'v1.9.0', 'v1.2.0').move -eq $true -and (Get-MajorDecision '1.9.0' 'v1.10.0').move -eq $false) 'versions compare as numbers, not text'
Assert-True ((Get-MajorDecision '0.1.0' @()).move -eq $true -and (Get-MajorDecision '0.2.0' 'v1', 'v0.1.0', 'latest').move -eq $true) 'no tags, or tags that are not versions, hold nothing back'
Assert-True ($null -eq (Get-MajorDecision "1.0.0`n" @()).move) 'a version with a trailing newline is refused'

if ($failures.Count) { Write-Host "$($failures.Count) failed"; exit 1 }
Write-Host 'Release notes: all checks passed'
