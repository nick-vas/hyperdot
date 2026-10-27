#!/usr/bin/env pwsh
# What a change needs of the Self-test workflow. Run by its `changes` job and by tests/Test-SelectJobs.ps1, which holds it
# to the rules below. Outputs, for every job that can be skipped, `<job>=true|false`, plus `pairs` (the staged programme's
# genre and language pairs to check, as JSON), `full` and `all`.
#
# Everything runs (every job, every written pair, the steps kept for the nightly run) when the event is workflow_dispatch,
# a push to main or the nightly schedule, and when the base commit cannot be fetched or compared: rather skip nothing than
# a check. On a pull request, from the files it changes against its base:
#   lint        always: it holds every test that needs no Godot, and the tests that read the docs.
#   docs only   (docs/ except docs/json.md, Markdown outside the skills, subagents and templates, site/, the licence files)
#               runs nothing else.
#   shared core (the workflow, its actions and scripts, hyperdot.ps1, Common, Runners, Setup, Detect and Report, validate
#               and flows, the examples) runs every job but the field test, which follows the benchmark's code, its own
#               tests and the workflow (the nightly run checks it against the rest).
#   otherwise   each job runs for the files it exercises (the patterns below), for the tests it runs (read from the
#               workflow: tests/Test-X.ps1 for a job that names it, and a fixture folder or helper for the jobs of the
#               tests that name it; a file no test names runs every job), and for nothing else.
# The staged programme's pairs: a pair whose game folder changed runs (benchmark/games/<genre>/<language>/, or a file of the
# genre outside both language folders that is not prose); a change to the check's own code (benchmark/templates/,
# GameProgramme.ps1, game-programme.json, tests/Test-GameProgramme.ps1, this script) runs a sample of three pairs:
# platformer in C# (it caught a git race on release-stage games), arena in GDScript (it caught an ENet race) and cards in
# GDScript, a third genre. The nightly run checks every pair.
#
# -Files stands in for the changed files (the tests give them; the workflow lets git list them against -Base).
# -Json prints the result; otherwise it is appended to $GITHUB_OUTPUT, with a ::notice::.
param(
    [string]$EventName = $env:GITHUB_EVENT_NAME,
    [string]$Base = $env:BASE,
    [string[]]$Files,
    [string]$Root = (Split-Path (Split-Path $PSScriptRoot)),
    [switch]$Json
)
Set-StrictMode -Version 3.0
$ErrorActionPreference = 'Stop'

# The jobs a change can skip; lint and coverage always run.
$gated = 'zero-config', 'csharp', 'explicit-runners', 'action', 'local-windows', 'init', 'measure', 'game-benchmark', 'field-test', 'web'

$sample = @(@{ genre = 'platformer'; language = 'csharp' }, @{ genre = 'arena'; language = 'gdscript' }, @{ genre = 'cards'; language = 'gdscript' })
$pairsCode = '^benchmark/templates/|^benchmark/(GameProgramme\.ps1|game-programme\.json)$|^tests/Test-GameProgramme\.ps1$|^\.github/(workflows/self-test\.yml|scripts/(?!Get-ChangelogSection\.ps1))'

# Used by every job, so a change to them runs every job. (The release workflow and its changelog script belong to no job:
# a change to them runs lint, which holds their test.)
$core = '^\.github/(workflows/self-test\.yml|actions/|scripts/(?!Get-ChangelogSection\.ps1))', '^ci/godot/hyperdot\.ps1$',
    '^ci/godot/lib/(Common|Runners|Setup|Detect|Report)\.ps1$', '^ci/godot/tools/(validate|validate_logger|flows)\.gd$',
    '^examples/', '^\.gdignore$', '^ci/godot/\.gdignore$'
function Get-LibPattern([string[]]$Names) { return '^ci/godot/lib/(' + ($Names -join '|') + ')\.ps1$' }
$measureLibs = Get-LibPattern 'Measure', 'Audio', 'TextSize', 'Layout', 'Deck', 'Palette', 'Playthrough', 'Soak', 'Credits', 'Localization'
# What a game's own checks and doctor reach: every lib except the ones for sounds, trailers, plans, the web and help.
$gameLibs = Get-LibPattern 'Doctor', 'Context', 'Addons', 'Architecture', 'Assets', 'Juice', 'Playthrough', 'Placement', 'Soak', 'Platforms', 'Steam', 'Store', 'Audio', 'Localization', 'Data', 'Measure', 'Version'
$patterns = @{
    'zero-config' = '^ci/godot/', '^\.github/workflows/godot\.yml$'
    'init'        = '^ci/godot/', '^hooks/', '^agents/', '^\.agents/', '^\.claude-plugin/'
    'measure'     = $measureLibs, '^ci/godot/tools/(bench|shot|textsize|layout|notices|glyphs|Palette)\.(gd|cs)$', '^docs/json\.md$'
    'web'         = (Get-LibPattern 'Web', 'BuildSize', 'Measure', 'Platforms'), '^ci/godot/tools/(web-smoke\.mjs|bench\.gd|shot\.gd)$'
    'field-test'  = '^benchmark/(?!games/)'
    'game-benchmark' = '^benchmark/(?!games/)', $gameLibs
}
$patterns['csharp'] = $patterns['zero-config']; $patterns['explicit-runners'] = $patterns['zero-config']
$patterns['action'] = $patterns['zero-config']; $patterns['local-windows'] = $patterns['zero-config']
# The jobs that run the kit on the examples take any kit change; the others the libs and tools they exercise.

function Test-Documentation([string]$File) {
    if ($File -match '^docs/json\.md$') { return $false }       # Test-ErrorCodes reads the table of codes
    if ($File -match '^(\.agents/|agents/|ci/godot/templates/)') { return $false }   # skills, subagents and templates are shipped
    return $File -match '^docs/' -or $File -match '\.md$' -or $File -match '^site/' -or $File -match '^(LICENSE|NOTICE|CODEOWNERS)$'
}

# The jobs of the workflow and the text of each, to find the jobs that run a test.
$workflow = Get-Content -LiteralPath (Join-Path $Root '.github/workflows/self-test.yml')
$blocks = [ordered]@{}
$name = $null
foreach ($line in $workflow) {
    if ($line -match '^jobs:\s*$') { $blocks = [ordered]@{}; $name = ''; continue }
    if ($null -eq $name -or $line -match '^\s*#') { continue }   # a comment above the next job belongs to it
    if ($line -match '^  ([a-z][a-z0-9-]*):\s*$') { $name = $Matches[1]; $blocks[$name] = [System.Text.StringBuilder]::new(); continue }
    if ($name) { [void]$blocks[$name].AppendLine($line) }
}
$blockText = [ordered]@{}
foreach ($key in $blocks.Keys) { $blockText[$key] = $blocks[$key].ToString() }

# The jobs a changed file under tests/ runs, or $null when nothing names it.
function Get-TestJobs([string]$File) {
    $parts = $File -split '/'
    $key = if ($parts.Count -gt 2) { $parts[1] } else { $parts[-1] }
    $mention = [regex]::Escape($key)
    $found = [System.Collections.Generic.HashSet[string]]::new()
    $named = $false
    foreach ($job in $blockText.Keys) { if ($blockText[$job] -match "tests/$mention") { $named = $true; [void]$found.Add($job) } }
    # A fixture or a helper is named by test scripts, whose jobs run it (a test script is named by its jobs above).
    if ($parts.Count -gt 2 -or $key -notmatch '^Test-.*\.ps1$') {
        foreach ($test in Get-ChildItem -LiteralPath (Join-Path $Root 'tests') -Filter 'Test-*.ps1' -File -ErrorAction SilentlyContinue) {
            if ([System.IO.File]::ReadAllText($test.FullName).Contains($key)) {
                $named = $true
                foreach ($job in $blockText.Keys) { if ($blockText[$job] -match "tests/$([regex]::Escape($test.Name))") { [void]$found.Add($job) } }
            }
        }
    }
    if (-not $named) { return $null }
    return @($found)
}

$spec = Get-Content -Raw -LiteralPath (Join-Path $Root 'benchmark/game-programme.json') | ConvertFrom-Json
$written = @(foreach ($g in $spec.programme.genres) { foreach ($l in $g.languages) {
    if (Test-Path -LiteralPath (Join-Path $Root "benchmark/games/$($g.id)/$l")) { [ordered]@{ genre = $g.id; language = $l } } } })

# Everything, unless this is a pull request whose changed files could be listed.
$full = $EventName -ne 'pull_request' -or -not $Base -or $Base -match '^0+$'
$changed = @()
if (-not $full) {
    if ($PSBoundParameters.ContainsKey('Files')) {
        # (-File hands a comma list over as one string.)
        $changed = @($Files | ForEach-Object { $_ -split ',' } | Where-Object { $_ })
    } else {
        git -C $Root fetch -q --depth=1 origin $Base 2>$null
        $listed = @(git -C $Root diff --name-only $Base HEAD 2>$null)
        # Not fetched (a force push, a deleted base): check everything rather than skip.
        if ($LASTEXITCODE -ne 0) { $full = $true } else { $changed = $listed }
    }
}

$run = [ordered]@{}
foreach ($job in $gated) { $run[$job] = $full }
if (-not $full) {
    $code = @($changed | Where-Object { -not (Test-Documentation $_) })
    $everything = @($code | Where-Object { $f = $_; @($core | Where-Object { $f -match $_ }).Count -gt 0 }).Count -gt 0
    # The field test (about 17 minutes, no failure in the sampled runs, docs/ci.md) follows the benchmark's code and its own
    # tests, and the workflow and scripts that run it; the nightly run checks it against the rest of the kit.
    $everythingForFieldTest = @($code | Where-Object { $_ -match '^\.github/(workflows/self-test\.yml|scripts/(?!Get-ChangelogSection\.ps1))' }).Count -gt 0
    foreach ($job in $gated) {
        if ($everything -and ($job -ne 'field-test' -or $everythingForFieldTest)) { $run[$job] = $true; continue }
        foreach ($file in $code) {
            if (@($patterns[$job] | Where-Object { $file -match $_ }).Count -gt 0) { $run[$job] = $true; break }
            if ($file -match '^tests/') {
                $jobs = Get-TestJobs $file
                if ($null -eq $jobs -or $job -in $jobs) { $run[$job] = $true; break }
            }
        }
    }
}

$sampled = -not $full -and @($changed | Where-Object { $_ -match $pairsCode }).Count -gt 0
$pairs = @(foreach ($p in $written) {
    # A pair changed when its language's folder did, or a file of the genre outside both languages that is not prose (its
    # DESIGN.md is read by people, not by the check).
    $mine = "^benchmark/games/$($p.genre)/($($p.language)/|(?!gdscript/|csharp/).*(?<!\.md)$)"
    $inSample = $sampled -and @($sample | Where-Object { $_.genre -eq $p.genre -and $_.language -eq $p.language }).Count -gt 0
    if ($full -or $inSample -or @($changed | Where-Object { $_ -match $mine }).Count -gt 0) { $p } })

$result = [ordered]@{ full = $full }
foreach ($job in $gated) { $result[$job] = $run[$job] }
$result['all'] = @($gated | Where-Object { -not $run[$_] }).Count -eq 0
$result['pairs'] = $pairs
if ($Json) { $result | ConvertTo-Json -Depth 4; return }

if ($env:GITHUB_OUTPUT) {
    foreach ($key in $result.Keys) {
        $value = if ($key -eq 'pairs') { ConvertTo-Json -Depth 10 -InputObject $pairs -Compress } else { "$($result[$key])".ToLowerInvariant() }
        "$key=$value" >> $env:GITHUB_OUTPUT
    }
}
$skipped = @($gated | Where-Object { -not $run[$_] })
$why = if ($full) { 'everything: this is not a pull request, or its base could not be compared' } elseif ($sampled) { 'a sample of the staged programme, as only its own code changed' } else { 'what the changed files exercise' }
Write-Host "::notice::Self-test runs $($gated.Count - $skipped.Count) of $($gated.Count) skippable jobs ($why)$(if ($skipped) { "; skipped: $($skipped -join ', ')" }) and $($pairs.Count) of $($written.Count) staged-programme pairs"
