#!/usr/bin/env pwsh
# Self-test of `telemetry`, the one view over .godot/hyperdot-history.jsonl: per command the runs, pass rate and mean,
# median and p95 duration with their trend, the slowest runners, hot spots and flaky tests of test, the recurring error
# keys, damaged lines skipped and counted, a project with no history, and too few runs. The history is written by this
# script into temporary projects, so the numbers are known; no Godot is needed.
Set-StrictMode -Version 3.0
$ErrorActionPreference = 'Stop'
$root = Split-Path $PSScriptRoot
$ci = Join-Path $root 'ci/godot/hyperdot.ps1'
$failures = @()
function Assert-True([bool]$Condition, [string]$Name) {
    if ($Condition) { Write-Host "ok     $Name" } else { Write-Host "FAIL   $Name"; $script:failures += $Name }
}
function Invoke-Kit([string]$Dir, [string[]]$KitArgs) {
    $out = & pwsh -NoProfile -NonInteractive -File $ci @KitArgs -Json -Project $Dir 2>$null | Out-String
    return [pscustomobject]@{ Code = $LASTEXITCODE; Doc = ($out.Trim() ? ($out | ConvertFrom-Json) : $null) }
}
function New-TelemetryProject([string[]]$Lines) {
    $dir = Join-Path ([System.IO.Path]::GetTempPath()) "telemetry-$([guid]::NewGuid().ToString('n').Substring(0, 8))"
    New-Item -ItemType Directory -Force (Join-Path $dir '.godot') | Out-Null
    Set-Content -LiteralPath (Join-Path $dir 'project.godot') "config_version=5`n`n[application]`n`nconfig/name=`"Telemetry`"`n"
    if ($null -ne $Lines) { Set-Content -LiteralPath (Join-Path $dir '.godot/hyperdot-history.jsonl') $Lines }
    return $dir
}
$script:minute = 0
function New-Line([string]$Command, [bool]$Ok, [double]$Seconds, [hashtable]$Extra = @{}) {
    $script:minute++
    $entry = [ordered]@{ time = ([datetime]'2026-10-01T10:00:00Z').AddMinutes($script:minute).ToString('o'); command = $Command; ok = $Ok
        code = $(if ($Ok) { '' } else { 'tests-failed' }); seconds = $Seconds }
    foreach ($key in $Extra.Keys) { $entry[$key] = $Extra[$key] }
    return ($entry | ConvertTo-Json -Compress -Depth 6)
}
$scope = @{ runners = @('gut', 'validate'); filter = '' }

# Eight test runs at four commits. Passing ones: 10, 20, 60, 70 and 80 s (the failed runs are not timed).
#   gut|test_hot fails in runs 3, 4 and 5 (commits c2 and c3), passes at c1 and c4: broken and fixed, not flaky.
#   gut|test_flaky fails in run 3 and passes in run 4, both at c2: flaky. gut|test_retry passed only on a retry in run 7.
$lines = @(
    New-Line 'test' $true 10 @{ scope = $scope; commit = 'c1'; failures = @(); errorKeys = @('E1'); runnerSeconds = @{ gut = 8; validate = 1 } }
    New-Line 'test' $true 20 @{ scope = $scope; commit = 'c1'; failures = @(); errorKeys = @('E1'); runnerSeconds = @{ gut = 10; validate = 1 } }
    New-Line 'test' $false 5 @{ scope = $scope; commit = 'c2'; failures = @('gut|test_flaky', 'gut|test_hot'); errorKeys = @('E1') }
    New-Line 'test' $false 5 @{ scope = $scope; commit = 'c2'; failures = @('gut|test_hot') }
    New-Line 'test' $false 5 @{ scope = $scope; commit = 'c3'; failures = @('gut|test_hot'); errorKeys = @('E1', 'E2') }
    New-Line 'test' $true 60 @{ scope = $scope; commit = 'c4'; failures = @(); runnerSeconds = @{ gut = 14; validate = 1 } }
    New-Line 'test' $true 70 @{ scope = $scope; commit = 'c4'; failures = @(); flaky = @('gut|test_retry'); runnerSeconds = @{ gut = 16; validate = 1; smoke = 100 } }
    New-Line 'test' $true 80 @{ scope = $scope; commit = 'c4'; failures = @(); runnerSeconds = @{ gut = 18; validate = 1; smoke = 100 } }
    New-Line 'build' $true 12
    New-Line 'build' $true 14
    New-Line 'export' $true 100
    New-Line 'export' $true 200
    New-Line 'export' $true 300
    New-Line 'export' $true 400
    'this is not json'
    '5'
    '{"seconds": 1}'
)
$dir = New-TelemetryProject $lines
try {
    $r = Invoke-Kit $dir @('telemetry')
    $t = $r.Doc.telemetry
    Assert-True ($r.Code -eq 0 -and $r.Doc.ok -and $r.Doc.command -eq 'telemetry' -and $r.Doc.schema -eq 'hyperdot/1') "telemetry answers ok: $($r.Doc | ConvertTo-Json -Compress -Depth 8)"
    Assert-True ($t.skipped -eq 3 -and $t.entries -eq 14 -and $t.runs -eq 14) "a damaged line, a number and an object with no command are skipped and counted ($($t.skipped) skipped, $($t.entries) read)"
    Assert-True ($t.last -eq 50 -and $null -eq $t.command -and $t.minRuns -eq 3 -and -not $t.insufficient) 'the window defaults to 50 and the view is not insufficient'
    Assert-True ((@($t.commands | ForEach-Object command) -join ',') -eq 'build,export,test') 'commands: build, export, test'

    $test = @($t.commands | Where-Object command -eq 'test')[0]
    Assert-True ($test.runs -eq 8 -and $test.passed -eq 5 -and $test.failed -eq 3 -and $test.passRate -eq 0.625) "test: 8 runs, 5 passed, pass rate 0.625 ($($test.passRate))"
    Assert-True ($test.timedRuns -eq 5 -and -not $test.insufficient -and $test.meanSeconds -eq 48 -and $test.medianSeconds -eq 60 -and $test.p95Seconds -eq 80) "test: mean 48, median 60, p95 80 from the passing runs ($($test.meanSeconds), $($test.medianSeconds), $($test.p95Seconds))"
    Assert-True ($test.trend.halfRuns -eq 2 -and $test.trend.olderMeanSeconds -eq 15 -and $test.trend.newerMeanSeconds -eq 75 -and $test.trend.ratio -eq 5) "test: the newer half is 5 times the older ($($test.trend | ConvertTo-Json -Compress -Depth 8))"
    Assert-True (([datetime]$test.firstRun).ToUniversalTime().ToString('HH:mm') -eq '10:01' -and ([datetime]$test.lastRun).ToUniversalTime().ToString('HH:mm') -eq '10:08') "test: first and last run in UTC ($($test.firstRun), $($test.lastRun))"

    $export = @($t.commands | Where-Object command -eq 'export')[0]
    Assert-True ($export.meanSeconds -eq 250 -and $export.medianSeconds -eq 250 -and $export.p95Seconds -eq 400 -and $export.trend.ratio -eq 2.33) "export: mean 250, median 250, p95 400, trend 2.33 ($($export | ConvertTo-Json -Compress -Depth 8))"
    $build = @($t.commands | Where-Object command -eq 'build')[0]
    Assert-True ($build.runs -eq 2 -and $build.passRate -eq 1 -and $build.insufficient -and $null -eq $build.meanSeconds -and $null -eq $build.medianSeconds -and $null -eq $build.p95Seconds -and $null -eq $build.trend) 'build: two runs say insufficient and invent no mean, median, p95 or trend'

    $runners = @($t.test.slowestRunners)
    Assert-True ($runners.Count -eq 3 -and $runners[0].runner -eq 'gut' -and $runners[0].meanSeconds -eq 13.2 -and $runners[0].medianSeconds -eq 14 -and $runners[0].p95Seconds -eq 18) "slowest runner: gut, mean 13.2, median 14, p95 18 ($($runners[0] | ConvertTo-Json -Compress -Depth 8))"
    Assert-True ($runners[1].runner -eq 'validate' -and $runners[1].meanSeconds -eq 1) 'then validate'
    Assert-True ($runners[2].runner -eq 'smoke' -and $runners[2].insufficient -and $null -eq $runners[2].meanSeconds -and $runners[2].runs -eq 2) 'a runner timed twice is insufficient and last'

    $hot = @($t.test.hotSpots)
    Assert-True ($hot.Count -eq 2 -and $hot[0].runner -eq 'gut' -and $hot[0].name -eq 'test_hot' -and $hot[0].failedRuns -eq 3 -and $hot[1].name -eq 'test_flaky' -and $hot[1].failedRuns -eq 1) "hot spots: test_hot 3 runs, test_flaky 1 ($($hot | ConvertTo-Json -Compress -Depth 8))"
    $flaky = @($t.test.flakyTests)
    $same = @($flaky | Where-Object name -eq 'test_flaky')
    $retry = @($flaky | Where-Object name -eq 'test_retry')
    Assert-True ($flaky.Count -eq 2 -and $same.Count -eq 1 -and $retry.Count -eq 1) "flaky tests: test_flaky and test_retry only, not test_hot ($($flaky | ConvertTo-Json -Compress -Depth 8))"
    Assert-True ($same[0].failedRuns -eq 1 -and $same[0].passedRuns -eq 7 -and $same[0].retryRuns -eq 0 -and $same[0].commitsFailedAndPassed -eq 1 -and (@($same[0].basis) -join ',') -eq 'same-commit') 'test_flaky failed and passed at the same commit'
    Assert-True ($retry[0].failedRuns -eq 0 -and $retry[0].retryRuns -eq 1 -and (@($retry[0].basis) -join ',') -eq 'retry') 'test_retry passed on a retry'

    $errors = @($t.recurringErrors)
    $e1 = @($errors | Where-Object key -eq 'E1')
    Assert-True ($errors.Count -eq 2 -and $e1.Count -eq 1 -and $e1[0].count -eq 4 -and $e1[0].failedRuns -eq 2) "recurring errors reuse status's: E1 in 4 runs, 2 failed ($($errors | ConvertTo-Json -Compress -Depth 4))"
    Assert-True (@($errors | Where-Object key -eq 'E2')[0].count -eq 1) 'E2 is new (count 1)'

    # The history is read, never written: telemetry leaves no run of its own.
    Assert-True (@(Get-Content -LiteralPath (Join-Path $dir '.godot/hyperdot-history.jsonl')).Count -eq $lines.Count) 'telemetry writes nothing to the history'

    # The window and the command.
    $r = Invoke-Kit $dir @('telemetry', '-Last', '3')
    $w = $r.Doc.telemetry
    $wt = @($w.commands | Where-Object command -eq 'test')[0]
    Assert-True ($w.last -eq 3 -and $wt.runs -eq 3 -and $wt.passed -eq 3 -and $wt.insufficient -eq $false -and $wt.meanSeconds -eq 70 -and $w.test.hotSpots.Count -eq 0) "-Last 3 reads the newest 3 runs of each command ($($wt | ConvertTo-Json -Compress -Depth 8))"
    Assert-True (@($w.commands | Where-Object command -eq 'export')[0].runs -eq 3 -and $w.runs -eq 8) '-Last applies to each command'
    $r = Invoke-Kit $dir @('telemetry', 'export', '-Last', '2')
    Assert-True ($r.Doc.telemetry.command -eq 'export' -and $r.Doc.telemetry.runs -eq 2 -and @($r.Doc.telemetry.commands).Count -eq 1 -and $null -eq $r.Doc.telemetry.test -and $r.Doc.telemetry.commands[0].insufficient) 'telemetry export -Last 2 reports export only; two runs are insufficient'
    $r = Invoke-Kit $dir @('telemetry', 'bench')
    Assert-True ($r.Code -eq 0 -and $r.Doc.ok -and $r.Doc.telemetry.runs -eq 0 -and @($r.Doc.telemetry.commands).Count -eq 0 -and $r.Doc.telemetry.insufficient) 'a command with no runs gives zero runs, ok'

    # Refusals.
    foreach ($case in @(
            @{ Name = 'a command that leaves no history'; Args = @('telemetry', 'status') },
            @{ Name = '-Last 0'; Args = @('telemetry', '-Last', '0') },
            @{ Name = '-Last on another command'; Args = @('status', '-Last', '5') },
            @{ Name = 'a topic on another command'; Args = @('detect', 'test') })) {
        $r = Invoke-Kit $dir $case.Args
        Assert-True ($r.Code -ne 0 -and -not $r.Doc.ok -and $r.Doc.error.code -eq 'invalid-arguments') "$($case.Name) is invalid-arguments"
    }
} finally { Remove-Item -LiteralPath $dir -Recurse -Force -ErrorAction SilentlyContinue }

# No history file at all.
$bare = New-TelemetryProject $null
try {
    $r = Invoke-Kit $bare @('telemetry')
    $t = $r.Doc.telemetry
    Assert-True ($r.Code -eq 0 -and $r.Doc.ok -and $t.runs -eq 0 -and $t.entries -eq 0 -and $t.skipped -eq 0 -and @($t.commands).Count -eq 0 -and $t.insufficient -and $null -eq $t.test -and @($t.recurringErrors).Count -eq 0) "no history file: zero runs, ok ($($r.Doc | ConvertTo-Json -Compress -Depth 8))"
    $text = & pwsh -NoProfile -NonInteractive -File $ci telemetry -Project $bare 2>&1 | Out-String
    Assert-True ($LASTEXITCODE -eq 0 -and $text -match 'No runs in the history') 'the text says there are no runs'
} finally { Remove-Item -LiteralPath $bare -Recurse -Force -ErrorAction SilentlyContinue }

# Too few test runs: counts only.
$few = New-TelemetryProject @((New-Line 'test' $true 30 @{ scope = $scope; failures = @() }), (New-Line 'test' $false 5 @{ scope = $scope; failures = @('gut|test_x') }))
try {
    $r = Invoke-Kit $few @('telemetry')
    $t = $r.Doc.telemetry
    $c = $t.commands[0]
    Assert-True ($t.insufficient -and $c.runs -eq 2 -and $c.passed -eq 1 -and $c.passRate -eq 0.5 -and $c.insufficient -and $c.timedRuns -eq 1 -and $null -eq $c.meanSeconds -and $null -eq $c.medianSeconds -and $null -eq $c.p95Seconds -and $null -eq $c.trend) "two test runs: insufficient, no durations ($($c | ConvertTo-Json -Compress -Depth 8))"
    Assert-True ($t.test.hotSpots[0].name -eq 'test_x' -and @($t.test.flakyTests).Count -eq 0) 'what the history does show is still shown'
    $text = & pwsh -NoProfile -NonInteractive -File $ci telemetry -Project $few 2>&1 | Out-String
    Assert-True ($text -match 'too few passing runs to time' -and $text -match 'Fails often: gut test_x') 'the text says so'
} finally { Remove-Item -LiteralPath $few -Recurse -Force -ErrorAction SilentlyContinue }

# The trend needs four timed runs (two and two); three give the durations and no trend (read in-process, in a scope of its own).
& {
    foreach ($lib in 'Common', 'Report', 'Status', 'Telemetry') { . (Join-Path $root "ci/godot/lib/$lib.ps1") }
    $three = Get-TelemetryDurations ([double[]]@(10, 20, 30))
    Assert-True (-not $three.insufficient -and $three.meanSeconds -eq 20 -and $null -eq $three.trend) 'three timed runs: durations, no trend'
    $four = Get-TelemetryDurations ([double[]]@(10, 20, 30, 40))
    Assert-True ($null -ne $four.trend -and $four.trend.halfRuns -eq 2 -and $four.trend.ratio -eq 2.33) 'four timed runs: a trend over two and two'
}

if ($failures) { Write-Host "$($failures.Count) check(s) failed"; exit 1 }
Write-Host 'telemetry reads the run history: per-command pass rate, mean, median, p95 and trend, slowest runners, hot spots, flaky tests, recurring errors; thin or missing history is said so'
exit 0
