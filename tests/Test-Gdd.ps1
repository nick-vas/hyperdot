#!/usr/bin/env pwsh
# Self-test of the GDD feature grammar (Get-GddProblems): one "Priority:" line (must, should, could, won't) and one
# "Fun:" line per feature, the kinds comma-separated and alone on their line, or "Fun: none" at any priority. The
# deliberately broken tests/gdd-fixture/GDD.md must give exactly the problems listed below, each with its fix; doctor
# fails on them (doctor-problems) and status lists them as warnings, and lists must and should features with "Fun: none"
# as supportFeatures; the C# example's GDD and the shipped templates have none. No Godot is needed.
Set-StrictMode -Version 3.0
$ErrorActionPreference = 'Stop'
$root = Split-Path $PSScriptRoot
$ci = Join-Path $root 'ci/godot/hyperdot.ps1'
$failures = @()
function Assert-True([bool]$Condition, [string]$Name) {
    if ($Condition) { Write-Host "ok     $Name" } else { Write-Host "FAIL   $Name"; $script:failures += $Name }
}
foreach ($lib in 'Common', 'Status') { . (Join-Path $root "ci/godot/lib/$lib.ps1") }

# --- The rules, on the broken fixture ---
$fixture = Join-Path $PSScriptRoot 'gdd-fixture/GDD.md'
$gdd = Read-Gdd $fixture
$problems = @(Get-GddProblems $gdd)
function Find-Problem([string]$Feature, [string]$Pattern) { return @($problems | Where-Object { $_.problem -like "$Feature *" -and $_.problem -match $Pattern }) }
$expected = @(
    @('F2', "'challenge — the timer makes every second count' is not a kind of fun", 'Write "Fun: challenge" and put the rest on a line of its own', 13, 'an explanation after the kind on the Fun line names the kind to keep'),
    @('F3', 'carries on onto the next line', 'leave a blank line before any explanation', 20, 'a Fun line that carries on onto the next line is a problem'),
    @('F6', 'has no "Fun:" line', 'or "Fun: none" when it serves none', 32, "a won't feature with no Fun line is told to add the kinds or Fun: none"),
    @('F7', "'high' is not a priority", "Priority: won't", 36, 'an unknown priority lists the four'),
    @('F7', "'fun' is not a kind of fun", 'Use only these words', 37, 'an unknown kind lists the eight'),
    @('F7', '2 features have the id F7', 'renumber the later ones', 43, 'a duplicate feature id'),
    @('F7', 'has 2 "Fun:" lines', 'Merge them into one', 46, 'two Fun lines'),
    @('F7', '"Fun: none" is combined with other kinds', 'not both', 45, 'none with kinds'))
foreach ($case in $expected) {
    $found = @(Find-Problem $case[0] ([regex]::Escape($case[1])))
    Assert-True ($found.Count -eq 1 -and $found[0].fix.Contains($case[2]) -and $found[0].line -eq $case[3]) "$($case[4]) (line $($case[3])): $(if ($found.Count) { "$($found[0].problem) | $($found[0].fix) | line $($found[0].line)" } else { 'not reported' })"
}
Assert-True ($problems.Count -eq $expected.Count) "the fixture gives exactly $($expected.Count) problems, no more: $($problems.Count)"
Assert-True (@(Find-Problem 'F1' '.').Count -eq 0 -and @(Find-Problem 'F5' '.').Count -eq 0 -and @(Find-Problem 'F8' '.').Count -eq 0) "a valid must feature, a could with Fun: none and a won't (curly apostrophe) with Fun: none are clean"
Assert-True (@(Find-Problem 'F4' '.').Count -eq 0) 'a must feature with Fun: none is clean (credits, crash reports, cloud saves: work that serves no kind of fun)'
$support = @(Get-SupportFeatures $gdd)
Assert-True ($support.Count -eq 1 -and $support[0].id -eq 'F4' -and $support[0].priority -eq 'must' -and $support[0].title -eq 'Saving') "supportFeatures lists the must and should features with Fun: none, and not the could or won't ones: $(@($support | ForEach-Object { $_.id }) -join ', ')"
Assert-True (@(Find-Problem 'F3' "''").Count -eq 0) 'a trailing comma gives no empty kind'
$priorities = @($gdd.features | ForEach-Object { "$($_.id)=$($_.priority)" }) -join ' '
Assert-True ($priorities -match "F6=won't" -and $priorities -match "F8=won't") "won't is read whole, with a straight or curly apostrophe (not 'won'): $priorities"
$f2 = @($gdd.features | Where-Object { $_.id -eq 'F1' })[0]
Assert-True (($f2.fun -join ',') -eq 'challenge,sensation') 'a valid Fun line gives its kinds'

# --- The shipped GDDs are clean ---
foreach ($path in 'ci/godot/templates/GDD.md', 'ci/godot/templates/GDD-jam.md', 'examples/csharp/game/docs/GDD.md') {
    $clean = @(Get-GddProblems (Read-Gdd (Join-Path $root $path)))
    Assert-True ($clean.Count -eq 0) "$path follows the grammar: $(@($clean | ForEach-Object { $_.problem }) -join ' | ')"
}

# --- doctor fails on them, status lists them ---
$dir = Join-Path ([System.IO.Path]::GetTempPath()) "gdd-$([guid]::NewGuid().ToString('n').Substring(0, 8))"
Copy-Item -LiteralPath (Join-Path $root 'examples/gdscript') -Destination $dir -Recurse
New-Item -ItemType Directory -Force (Join-Path $dir 'docs') | Out-Null
try {
    Copy-Item -LiteralPath $fixture (Join-Path $dir 'docs/GDD.md')
    $out = & pwsh -NoProfile -NonInteractive -File $ci doctor -Json -Project $dir 2>$null | Out-String
    $doc = $out | ConvertFrom-Json -Depth 20
    $gddChecks = @($doc.checks | Where-Object { $_.message -match 'GDD\.md line \d+:' })
    Assert-True ($LASTEXITCODE -ne 0 -and $doc.error.code -eq 'doctor-problems' -and $gddChecks.Count -eq $expected.Count -and @($gddChecks | Where-Object { $_.status -ne 'FAIL' -or -not $_.fix }).Count -eq 0) "doctor fails with doctor-problems, one FAIL with its fix per problem: $($gddChecks.Count) GDD checks"
    $out = & pwsh -NoProfile -NonInteractive -File $ci status -Json -Project $dir 2>$null | Out-String
    $status = $out | ConvertFrom-Json -Depth 20
    Assert-True ($status.ok -and @($status.gdd.problems).Count -eq $expected.Count -and @($status.warnings | Where-Object { $_ -match '^GDD line \d+: .* Fix: ' }).Count -eq $expected.Count) 'status never fails on them, and lists each as a warning with its fix'
    Assert-True (@($status.gdd.supportFeatures).Count -eq 1 -and @($status.gdd.supportFeatures)[0].id -eq 'F4') 'status -Json reports gdd.supportFeatures'
    Copy-Item -LiteralPath (Join-Path $root 'examples/csharp/game/docs/GDD.md') (Join-Path $dir 'docs/GDD.md') -Force
    $out = & pwsh -NoProfile -NonInteractive -File $ci doctor -Json -Project $dir 2>$null | Out-String
    $doc = $out | ConvertFrom-Json -Depth 20
    Assert-True (@($doc.checks | Where-Object { $_.message -match '^GDD: 5 feature\(s\), each with one Priority and one Fun line' -and $_.status -eq 'OK' }).Count -eq 1 -and @($doc.checks | Where-Object { $_.message -match 'GDD\.md line' }).Count -eq 0) 'a clean GDD is one OK line in doctor'
} finally { Remove-Item -LiteralPath $dir -Recurse -Force -ErrorAction SilentlyContinue }

if ($failures.Count) { Write-Host "`n$($failures.Count) failed"; exit 1 }
Write-Host "`nGDD grammar self-test passed"
exit 0
