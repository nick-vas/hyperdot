#!/usr/bin/env pwsh
<#
.SYNOPSIS
    Says what the automatic run of .github/workflows/release.yml releases after Self-test passed on a commit of main: the
    highest `## x.y.z - ` section of CHANGELOG.md at that commit, when v<x.y.z> is not a tag on origin yet and that commit
    is the one that added the section (the merged release pull request). Held by tests/Test-ReleasePr.ps1.

.DESCRIPTION
    Prints one line of JSON: {"release": true|false, "version": "x.y.z", "sha": "...", "reason": "..."}. Only the commit
    that added the section is released, so its own Self-test run decides: a later commit whose run ends first does not get
    the tag (its changes would ship in a release whose notes leave them out). When that commit's run failed, re-run it, or
    run Release by hand with the version and the commit.

.EXAMPLE
    pwsh .github/scripts/Get-PendingRelease.ps1 -Sha $sha
#>
param(
    [Parameter(Mandatory)][ValidatePattern('\A[0-9a-f]{40}\z')][string]$Sha,
    [string]$Remote = 'origin'
)
Set-StrictMode -Version 3.0
$ErrorActionPreference = 'Stop'

function Write-Decision([bool]$Release, [string]$Version, [string]$Reason) {
    ConvertTo-Json -Compress -Depth 3 -InputObject ([ordered]@{ release = $Release; version = $Version; sha = $Sha; reason = $Reason })
}
$text = (git show "$($Sha):CHANGELOG.md") -join "`n"
if ($LASTEXITCODE -ne 0) { throw "git show $($Sha):CHANGELOG.md failed (exit code $LASTEXITCODE)" }
$latest = $null
foreach ($m in [regex]::Matches($text, '(?m)^## ([0-9]+)\.([0-9]+)\.([0-9]+) - ')) {
    $v = [version]::new([int]$m.Groups[1].Value, [int]$m.Groups[2].Value, [int]$m.Groups[3].Value)
    if ($null -eq $latest -or $v -gt $latest) { $latest = $v }
}
if ($null -eq $latest) { Write-Decision $false '' 'CHANGELOG.md has no released section'; exit 0 }
$version = "$latest"

$tagged = @(git ls-remote --tags $Remote "refs/tags/v$version")
if ($LASTEXITCODE -ne 0) { throw "git ls-remote $Remote failed (exit code $LASTEXITCODE)" }
if ($tagged.Count -gt 0) { Write-Decision $false $version "v$version is already released"; exit 0 }

# -S finds the commit that changed how often the heading occurs: the one that added it. --first-parent keeps to main's own
# commits, so a release pull request merged with a merge commit (not squashed) names the merge, the commit Self-test ran on.
$added = "$(git log -1 --first-parent --format=%H -S "## $version - " $Sha -- CHANGELOG.md)".Trim()
if ($LASTEXITCODE -ne 0) { throw "git log -S failed (exit code $LASTEXITCODE)" }
if ($added -ne $Sha) {
    Write-Decision $false $version "the $version section came with $added, so the Self-test run of that commit releases it; if that run failed, re-run it, or run Release by hand with version $version and sha $added"
    exit 0
}
Write-Decision $true $version "$Sha added the $version section, which has no tag yet"
