#!/usr/bin/env pwsh
# Self-test of the dotnet runner's guard against tests that were found but never ran: gdUnit4Net exits 0 with no
# results when its in-Godot rebuild fails or times out, and that must fail the run, not pass it. Synthetic TRX files,
# shaped like the adapter's (gdUnit4.test.adapter 3.0.0); runs without Godot or .NET.
Set-StrictMode -Version 3.0
$ErrorActionPreference = 'Stop'
$root = Split-Path $PSScriptRoot
foreach ($lib in 'Common', 'Report', 'Runners') { . (Join-Path $root "ci/godot/lib/$lib.ps1") }
$failures = @()
$dir = Join-Path ([System.IO.Path]::GetTempPath()) "notrun-$PID"
New-Item -ItemType Directory -Force -Path $dir | Out-Null

function New-Trx([string]$Name, [string[]]$Outcomes, [string]$StdOut) {
    $results = @(for ($i = 0; $i -lt $Outcomes.Count; $i++) {
        "<UnitTestResult testName=`"Suite.Case$i`" outcome=`"$($Outcomes[$i])`" />"
    })
    $path = Join-Path $dir $Name
    Set-Content -LiteralPath $path -Encoding utf8 -Value @"
<?xml version="1.0" encoding="utf-8"?>
<TestRun xmlns="http://microsoft.com/schemas/VisualStudio/TeamTest/2010">
  <Results>$($results -join '')</Results>
  <ResultSummary outcome="Completed"><Output><StdOut>$([System.Security.SecurityElement]::Escape($StdOut))</StdOut></Output></ResultSummary>
</TestRun>
"@
    return $path
}
function Read-One([string]$Path) { $totals = New-TestTotals; Read-Trx $Path $totals; return $totals }

$found = "Discover:  TestSuite Example.Tests.ControlsTest with 8 TestCases found.`nDiscover tests done, 2 TestSuites and total 3 Tests found."
try {
    # The rebuild failed: three found, none ran, the adapter exited 0. One failure that names the cause.
    $t = Read-One (New-Trx 'failed-build.trx' @() "$found`nCleaning up runner file at x/GdUnit4TestRunnerScene.cs due to compilation failure`nTest execution stopped.")
    if ($t.Failed -ne 1) { $failures += "a rebuild failure should count as one failure, got $($t.Failed)" }
    elseif ($t.Failures[0].Message -notmatch 'found 3 tests but ran 0: .*compilation failure') { $failures += "message should give the counts and the cause: $($t.Failures[0].Message)" }

    # Only some ran (the session died part way): still a failure.
    $t = Read-One (New-Trx 'partial.trx' @('Passed') $found)
    if ($t.Failed -ne 1 -or $t.Passed -ne 1) { $failures += "1 of 3 ran: expected 1 passed and 1 failure, got $($t.Passed) passed, $($t.Failed) failed" }

    # Every found test ran: no extra failure.
    $t = Read-One (New-Trx 'healthy.trx' @('Passed', 'Passed', 'Failed') $found)
    if ($t.Total -ne 3 -or $t.Failed -ne 1) { $failures += "healthy run: expected 3 results and only the real failure, got $($t.Total) and $($t.Failed)" }

    # With -Filter, tests the filter left out are found but never run (a Windows CI run with FullyQualifiedName~RunState
    # matched no gdUnit4 test): not a failure, unless the rebuild names its failure.
    $totals = New-TestTotals; Read-Trx (New-Trx 'filtered.trx' @() "$found`nCompleted tests for assembly: x/Example.dll") $totals $true
    if ($totals.Failed -ne 0) { $failures += "a filter that matches no gdUnit4 test is not a failure, got $($totals.Failed)" }
    $totals = New-TestTotals; Read-Trx (New-Trx 'filtered-broken.trx' @() "$found`nCleaning up runner file at x/GdUnit4TestRunnerScene.cs due to compilation failure") $totals $true
    if ($totals.Failed -ne 1) { $failures += "a filtered run whose rebuild failed still fails, got $($totals.Failed)" }

    # Each way the rebuild names its failure counts for a filtered run too.
    foreach ($line in 'Test project build fails with 2 errors', 'Godot did not complete within 120 s', 'Godot compilation TIMEOUT') {
        $totals = New-TestTotals; Read-Trx (New-Trx 'filtered-named.trx' @() "$found`n$line") $totals $true
        if ($totals.Failed -ne 1) { $failures += "a filtered run whose log says '$line' still fails, got $($totals.Failed)" }
    }

    # Other frameworks' TRX (xUnit, no discovery line) are read as before.
    $t = Read-One (New-Trx 'xunit.trx' @('Passed', 'Passed') 'xUnit.net VSTest Adapter v2.8.2')
    if ($t.Total -ne 2 -or $t.Failed -ne 0) { $failures += "xUnit run: expected 2 passed, got $($t.Total) total, $($t.Failed) failed" }

    # The runner as a whole: exit code 0 and 291 passing core tests do not hide the in-Godot suite that never ran.
    $runner = Join-Path $dir 'runner'
    New-Item -ItemType Directory -Force -Path $runner | Out-Null
    Move-Item (Join-Path $dir 'failed-build.trx') $runner
    Move-Item (Join-Path $dir 'xunit.trx') $runner
    $summary = Write-TestSummary 'dotnet' $runner 0 2>$null
    if ($summary.Ok) { $failures += 'the dotnet runner should fail when found tests never ran, even with exit code 0' }

    # Results below a folder named coverage (a checkout in ~/coverage) are still read: only a coverage folder inside the
    # results counts. A failure's path with spaces (C:\Users\Jane Doe) still gives its file and line.
    $nested = Join-Path $dir 'coverage/My Game/test-results/dotnet'
    New-Item -ItemType Directory -Force -Path $nested | Out-Null
    $trace = 'at Game.Tests.ScoreTest.Hit() in /home/jane/My Game/test/ScoreTest.cs:line 12'
    Set-Content -LiteralPath (Join-Path $nested 'spaces.trx') -Encoding utf8 -Value @"
<?xml version="1.0" encoding="utf-8"?>
<TestRun xmlns="http://microsoft.com/schemas/VisualStudio/TeamTest/2010">
  <Results><UnitTestResult testName="Game.Tests.ScoreTest.Ok" outcome="Passed" /><UnitTestResult testName="Game.Tests.ScoreTest.Hit" outcome="Failed"><Output><ErrorInfo><Message>Expected 2 but was 1</Message><StackTrace>$trace</StackTrace></ErrorInfo></Output></UnitTestResult></Results>
</TestRun>
"@
    $summary = Write-TestSummary 'dotnet' $nested 1 2>$null
    if ($summary.Total -ne 2) { $failures += "results below a parent folder named coverage should be read, got $($summary.Total) results" }
    elseif ("$($summary.Failures[0].File):$($summary.Failures[0].Line)" -ne '/home/jane/My Game/test/ScoreTest.cs:12') {
        $failures += "a stack trace path with spaces should give its file and line, got '$($summary.Failures[0].File):$($summary.Failures[0].Line)'"
    }
    foreach ($trace in 'at A.B() in C:\Users\Jane Doe\game\test\ScoreTest.cs:line 7', 'at A.B() in /home/jane/game/ScoreTest.cs:line 7') {
        $at = Get-FailureLocation $trace
        if (-not $at -or $at.Line -ne 7 -or $at.File -notlike '*ScoreTest.cs') { $failures += "no file and line in: $trace" }
    }

    # An error an autoload prints at startup is outside every file: the project-startup case keeps the "at:" line under it, so
    # the failure names the add-on's file and line. The testing frameworks' own frames still name nothing.
    $startupLog = Join-Path $dir 'validate.log'
    Set-Content -LiteralPath $startupLog -Value @(
        'SCRIPT ERROR: Invalid access to property or key ''scene_file_path'' on a base object of type ''null instance''.',
        '          at: _ready (res://addons/ggt-core/ggt.gd:20)',
        '@@validate begin res://main.tscn', '@@validate end res://main.tscn ok')
    $startup = @(ConvertFrom-ValidateLog $startupLog | Where-Object { $_.Name -eq 'project startup' })
    $location = if ($startup.Count -eq 1) { Get-FailureLocation $startup[0].Failure } else { $null }
    if (-not $location -or $location.File -ne 'addons/ggt-core/ggt.gd' -or $location.Line -ne 20) {
        $failures += "a startup error of an autoload should name its file and line, got '$($startup | ForEach-Object { $_.Failure })'"
    }
    # A runner that found no test says so in `Reason`, and a normal failing run has none.
    $empty = Join-Path $dir 'empty-results'
    New-Item -ItemType Directory -Force -Path $empty | Out-Null
    $summary = Write-TestSummary 'dotnet' $empty 0 2>$null
    if ($summary.Ok -or $summary.Reason -notmatch 'no test results \(exit code 0\).*static class') { $failures += "a dotnet run with no results should give a reason, got '$($summary.Reason)'" }
    $summary = Write-TestSummary 'gut' $empty 0 2>$null
    if ($summary.Reason -notmatch '^reported no test results' -or $summary.Reason -match 'static') { $failures += "another runner's reason should not blame static classes, got '$($summary.Reason)'" }
    if (Get-FailureLocation 'at: _run (res://addons/gut/gut.gd:100)') { $failures += 'a GUT frame should not be a failure location' }
    $own = Get-FailureLocation "at: _run (res://addons/gut/gut.gd:100)`nat: f (res://game/player.gd:5)"
    if (-not $own -or $own.File -ne 'game/player.gd') { $failures += 'a project frame should win over an add-on frame' }
} finally {
    Remove-Item -Recurse -Force -LiteralPath $dir -ErrorAction SilentlyContinue
}

if ($failures.Count -gt 0) {
    foreach ($failure in $failures) { Write-Host "FAIL: $failure" }
    exit 1
}
Write-Host 'found-but-not-run gdUnit4 tests fail the dotnet runner, a filter that skips them does not; healthy, partial and xUnit runs read as before'
exit 0
