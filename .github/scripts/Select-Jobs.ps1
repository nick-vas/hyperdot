#!/usr/bin/env pwsh
# Which parts of the Self-test workflow a change needs. Run by the workflow's `programme-pairs` job and by
# tests/Test-SelectJobs.ps1, which holds it to the rules below.
#
# The staged programme's check (benchmark/game-programme.json) runs one job per genre and language pair. Every written
# pair runs when the event is workflow_dispatch, a push to main or a schedule, and when the base commit cannot be
# fetched (rather skip nothing than a check). On a pull request:
#   - a pair whose game folder changed runs (benchmark/games/<genre>/<language>/, or a file of the genre outside both
#     language folders that is not prose);
#   - a change to the kit code the check is made of (benchmark/templates/, GameProgramme.ps1, game-programme.json,
#     tests/Test-GameProgramme.ps1) runs a sample of three pairs, not all of them: platformer in C# (it caught a git race
#     on release-stage games), arena in GDScript (it caught an ENet race) and cards in GDScript, a third genre.
#     The nightly run checks every pair.
#
# -Files stands in for the changed files (the tests give them; the workflow lets git list them against -Base).
# Prints the result as JSON with -Json; otherwise appends `pairs=<json>` to $GITHUB_OUTPUT and writes a ::notice.
param(
    [string]$EventName = $env:GITHUB_EVENT_NAME,
    [string]$Ref = $env:GITHUB_REF,
    [string]$Base = $env:BASE,
    [string[]]$Files,
    [string]$Root = (Split-Path (Split-Path $PSScriptRoot)),
    [switch]$Json
)
Set-StrictMode -Version 3.0
$ErrorActionPreference = 'Stop'

$sample = @(@{ genre = 'platformer'; language = 'csharp' }, @{ genre = 'arena'; language = 'gdscript' }, @{ genre = 'cards'; language = 'gdscript' })
$kitCode = '^benchmark/templates/|^benchmark/(GameProgramme\.ps1|game-programme\.json)$|^tests/Test-GameProgramme\.ps1$'

$spec = Get-Content -Raw -LiteralPath (Join-Path $Root 'benchmark/game-programme.json') | ConvertFrom-Json
$written = @(foreach ($g in $spec.programme.genres) { foreach ($l in $g.languages) {
    if (Test-Path -LiteralPath (Join-Path $Root "benchmark/games/$($g.id)/$l")) { [ordered]@{ genre = $g.id; language = $l } } } })

# Everything, unless this is a pull request whose changed files could be listed.
$full = $EventName -ne 'pull_request' -or -not $Base -or $Base -match '^0+$'
$changed = @()
if (-not $full) {
    if ($PSBoundParameters.ContainsKey('Files')) { # (-File hands a comma list over as one string.)
        $changed = @($Files | ForEach-Object { $_ -split ',' } | Where-Object { $_ }) }
    else {
        git -C $Root fetch -q --depth=1 origin $Base 2>$null
        $listed = @(git -C $Root diff --name-only $Base HEAD 2>$null)
        # Not fetched (a force push, a deleted base): check everything rather than skip.
        if ($LASTEXITCODE -ne 0) { $full = $true } else { $changed = $listed }
    }
}

$sampled = -not $full -and @($changed | Where-Object { $_ -match $kitCode }).Count -gt 0
$pairs = @(foreach ($p in $written) {
    # A pair changed when its language's folder did, or a file of the genre outside both languages that is not prose (its
    # DESIGN.md is read by people, not by the check).
    $mine = "^benchmark/games/$($p.genre)/($($p.language)/|(?!gdscript/|csharp/).*(?<!\.md)$)"
    $inSample = $sampled -and @($sample | Where-Object { $_.genre -eq $p.genre -and $_.language -eq $p.language }).Count -gt 0
    if ($full -or $inSample -or @($changed | Where-Object { $_ -match $mine }).Count -gt 0) { $p } })

$result = [ordered]@{ full = $full; pairs = $pairs }
if ($Json) { $result | ConvertTo-Json -Depth 4; return }
if ($env:GITHUB_OUTPUT) { "pairs=$(ConvertTo-Json -InputObject $pairs -Compress)" >> $env:GITHUB_OUTPUT }
$why = if ($full) { 'every pair: this is not a pull request, or its base could not be compared' } elseif ($sampled) { 'a sample, as only the check''s own code changed' } else { 'the pairs whose game changed' }
Write-Host "::notice::The staged programme's check runs $($pairs.Count) of $($written.Count) genre and language pairs ($why)"
