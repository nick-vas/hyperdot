# telemetry: one read-only view of the numbers the kit already keeps, .godot/hyperdot-history.jsonl (written by
# Add-RunHistory, one line a run). Nothing is measured or written here: per command the runs, the pass rate and the mean,
# median and 95th percentile duration of the newest runs; for test the slowest runners, the tests that fail most often
# and the flaky ones; the error keys that recur (Get-RecurringErrors, as status uses them); and whether runs got slower.
# A number that the history is too thin for is $null, never a guess (docs/json.md, telemetry).

# The commands whose runs reach the history (hyperdot.ps1 starts a history line for each of them).
$script:TelemetryCommands = @('build', 'test', 'export', 'bench', 'shot', 'audio', 'soak', 'credits', 'deck')
# Fewer timed runs than this give no mean, median, p95 or trend: the numbers would say nothing. The trend also needs two
# runs in each half.
$script:TelemetryMinRuns = 3

function Get-TelemetryField($Entry, [string]$Name) {
    $property = $Entry.PSObject.Properties[$Name]
    if ($property) { return $property.Value }
    return $null
}

function Get-TelemetryStrings($Entry, [string]$Name) {
    return @(Get-TelemetryField $Entry $Name | Where-Object { $_ } | ForEach-Object { [string]$_ })
}

function Test-TelemetryNumber($Value) { return $Value -is [double] -or $Value -is [int] -or $Value -is [long] -or $Value -is [decimal] }

# Nearest rank: the smallest value that at least $Percent percent of the values are at or below.
function Get-TelemetryPercentile([double[]]$Values, [double]$Percent) {
    if ($Values.Count -eq 0) { return $null }
    $sorted = @($Values | Sort-Object)
    $rank = [int][math]::Ceiling($Percent / 100 * $sorted.Count)
    return [math]::Round($sorted[[math]::Max(1, $rank) - 1], 1)
}

function Get-TelemetryMean([double[]]$Values) {
    if ($Values.Count -eq 0) { return $null }
    return [math]::Round(($Values | Measure-Object -Average).Average, 1)
}

# Mean, median and p95 of $Seconds (oldest first), or all $null when there are fewer than the minimum. The trend is the mean
# of the newer half over the mean of the older half (the middle run of an odd count is in neither); above 1 is slower.
function Get-TelemetryDurations([double[]]$Seconds) {
    $stats = [ordered]@{ timedRuns = $Seconds.Count; insufficient = $Seconds.Count -lt $script:TelemetryMinRuns
        meanSeconds = $null; medianSeconds = $null; p95Seconds = $null; trend = $null }
    if ($stats.insufficient) { return $stats }
    $stats.meanSeconds = Get-TelemetryMean $Seconds
    $stats.medianSeconds = Get-RunMedian $Seconds
    $stats.p95Seconds = Get-TelemetryPercentile $Seconds 95
    $half = [int][math]::Floor($Seconds.Count / 2)
    if ($half -ge 2) {
        $older = Get-TelemetryMean @($Seconds | Select-Object -First $half)
        $newer = Get-TelemetryMean @($Seconds | Select-Object -Last $half)
        $stats.trend = [ordered]@{ halfRuns = $half; olderMeanSeconds = $older; newerMeanSeconds = $newer
            ratio = $(if ($older -gt 0) { [math]::Round($newer / $older, 2) } else { $null }) }
    }
    return $stats
}

# The slowest runners of the test runs, by mean time (the runnerSeconds of each line; older lines have none).
function Get-TelemetryRunners([object[]]$TestRuns) {
    $times = [ordered]@{}
    foreach ($run in $TestRuns) {
        $perRunner = Get-TelemetryField $run 'runnerSeconds'
        if ($perRunner -isnot [pscustomobject]) { continue }
        foreach ($property in $perRunner.PSObject.Properties) {
            if (-not (Test-TelemetryNumber $property.Value)) { continue }
            if (-not $times.Contains($property.Name)) { $times[$property.Name] = [System.Collections.Generic.List[double]]::new() }
            $times[$property.Name].Add([double]$property.Value)
        }
    }
    $rows = @(foreach ($name in $times.Keys) {
        $d = Get-TelemetryDurations $times[$name].ToArray()
        [ordered]@{ runner = $name; runs = $d.timedRuns; insufficient = $d.insufficient; meanSeconds = $d.meanSeconds
            medianSeconds = $d.medianSeconds; p95Seconds = $d.p95Seconds }
    })
    return @($rows | Sort-Object @{ Expression = { $null -eq $_.meanSeconds }; Ascending = $true }, @{ Expression = { $_.meanSeconds }; Descending = $true }, @{ Expression = { $_.runner } })
}

# The tests that fail most often, and the flaky ones, from the test runs' failure ids ("runner|name").
# A hot spot is a test that failed in at least one of the runs, the most failed runs first.
# A flaky test is one that failed in some runs and passed in others although the code was the same: it passed on a retry
# of test -Retry (the line's flaky ids), or it failed in one run and passed in another at the same commit. A run counts as
# a pass of a test when it ran the test's runner with no -Filter, listed no failure of it, and was not cut short (the line's
# failuresTruncated). Outside git there is no commit, so only the retries show; the fix of a test between two commits is no
# flakiness.
function Get-TelemetryTests([object[]]$TestRuns) {
    $failed = @{}; $retried = @{}; $failedAt = @{}; $passedAt = @{}; $passed = @{}
    $ids = [System.Collections.Generic.HashSet[string]]::new([StringComparer]::Ordinal)
    foreach ($run in $TestRuns) {
        $commit = Get-TelemetryField $run 'commit'
        foreach ($id in @(Get-TelemetryStrings $run 'failures' | Select-Object -Unique)) {
            [void]$ids.Add($id)
            $failed[$id] = 1 + $(if ($failed.ContainsKey($id)) { $failed[$id] } else { 0 })
            if ($commit) {
                if (-not $failedAt.ContainsKey($id)) { $failedAt[$id] = [System.Collections.Generic.HashSet[string]]::new([StringComparer]::Ordinal) }
                [void]$failedAt[$id].Add([string]$commit)
            }
        }
        foreach ($id in @(Get-TelemetryStrings $run 'flaky' | Select-Object -Unique)) {
            [void]$ids.Add($id)
            $retried[$id] = 1 + $(if ($retried.ContainsKey($id)) { $retried[$id] } else { 0 })
        }
    }
    foreach ($run in $TestRuns) {
        $scope = Get-TelemetryField $run 'scope'
        if ($scope -isnot [pscustomobject] -or (Get-TelemetryField $run 'failuresTruncated') -eq $true) { continue }
        if ($scope.PSObject.Properties['filter'] -and $scope.filter) { continue }
        $ran = @(if ($scope.PSObject.Properties['runners']) { $scope.runners | ForEach-Object { [string]$_ } })
        $listed = [System.Collections.Generic.HashSet[string]]::new([string[]]@(
                (Get-TelemetryStrings $run 'failures') + (Get-TelemetryStrings $run 'flaky') + (Get-TelemetryStrings $run 'quarantined')), [StringComparer]::Ordinal)
        $commit = Get-TelemetryField $run 'commit'
        foreach ($id in $ids) {
            $runner = ($id -split '\|', 2)[0]
            if ($runner -cnotin $ran -or $listed.Contains($id) -or $id.EndsWith('|(runner)', [StringComparison]::Ordinal)) { continue }
            $passed[$id] = 1 + $(if ($passed.ContainsKey($id)) { $passed[$id] } else { 0 })
            if ($commit) {
                if (-not $passedAt.ContainsKey($id)) { $passedAt[$id] = [System.Collections.Generic.HashSet[string]]::new([StringComparer]::Ordinal) }
                [void]$passedAt[$id].Add([string]$commit)
            }
        }
    }
    $split = { param($Id) $runner, $name = $Id -split '\|', 2; return @($runner, $name) }
    $count = { param($Table, $Id) if ($Table.ContainsKey($Id)) { [int]$Table[$Id] } else { 0 } }
    $hot = @($failed.Keys | Sort-Object @{ Expression = { $failed[$_] }; Descending = $true }, @{ Expression = { $_ } } | Select-Object -First 10 | ForEach-Object {
            $parts = & $split $_
            [ordered]@{ runner = $parts[0]; name = $parts[1]; failedRuns = $failed[$_] } })
    $flaky = foreach ($id in $ids) {
        $same = 0
        if ($failedAt.ContainsKey($id) -and $passedAt.ContainsKey($id) -and -not $id.EndsWith('|(runner)', [StringComparison]::Ordinal)) {
            $same = @($failedAt[$id] | Where-Object { $passedAt[$id].Contains($_) }).Count
        }
        $retries = & $count $retried $id
        if ($same -eq 0 -and $retries -eq 0) { continue }
        $parts = & $split $id
        [pscustomobject]@{ Id = $id; Weight = (& $count $failed $id) + $retries
            Row = [ordered]@{ runner = $parts[0]; name = $parts[1]; failedRuns = (& $count $failed $id); passedRuns = (& $count $passed $id)
                retryRuns = $retries; commitsFailedAndPassed = $same
                basis = @(@(if ($retries) { 'retry' }) + @(if ($same) { 'same-commit' })) } }
    }
    $flakyRows = @(@($flaky) | Sort-Object @{ Expression = { $_.Weight }; Descending = $true }, @{ Expression = { $_.Id } } | Select-Object -First 10 | ForEach-Object { $_.Row })
    return [ordered]@{ hotSpots = $hot; flakyTests = $flakyRows }
}

# The report for $History (oldest first, as Read-RunHistory returns it): the newest $Last runs of each command, or of
# $Command alone. $Skipped is the count of damaged lines the reader dropped.
function Get-TelemetryReport([object[]]$History, [int]$Last, [string]$Command, [int]$Skipped = 0) {
    $usable = [System.Collections.Generic.List[object]]::new()
    foreach ($entry in $History) {
        if ($entry -isnot [pscustomobject] -or -not ((Get-TelemetryField $entry 'command') -is [string]) -or -not (Get-TelemetryField $entry 'command')) { $Skipped++; continue }
        $usable.Add($entry)
    }
    # The newest $Last of each command, kept in the order they ran.
    $byCommand = [ordered]@{}
    for ($i = 0; $i -lt $usable.Count; $i++) {
        $name = [string]$usable[$i].command
        if ($Command -and $name -cne $Command) { continue }
        if (-not $byCommand.Contains($name)) { $byCommand[$name] = [System.Collections.Generic.List[int]]::new() }
        $byCommand[$name].Add($i)
    }
    $keep = [System.Collections.Generic.HashSet[int]]::new()
    foreach ($name in $byCommand.Keys) { foreach ($i in @($byCommand[$name] | Select-Object -Last $Last)) { [void]$keep.Add($i) } }
    $window = @(for ($i = 0; $i -lt $usable.Count; $i++) { if ($keep.Contains($i)) { $usable[$i] } })
    $toTime = { param($Value) try { (ConvertTo-UtcTime $Value).ToString('o', [cultureinfo]::InvariantCulture) } catch { $null } }

    $commands = @(foreach ($name in @($byCommand.Keys | Sort-Object)) {
        $runs = @($window | Where-Object { $_.command -ceq $name })
        $okRuns = @($runs | Where-Object { (Get-TelemetryField $_ 'ok') -eq $true })
        $timed = @($okRuns | ForEach-Object { Get-TelemetryField $_ 'seconds' } | Where-Object { Test-TelemetryNumber $_ } | ForEach-Object { [double]$_ })
        $row = [ordered]@{ command = $name; runs = $runs.Count; passed = $okRuns.Count; failed = $runs.Count - $okRuns.Count
            passRate = [math]::Round($okRuns.Count / $runs.Count, 3) }
        foreach ($pair in (Get-TelemetryDurations $timed).GetEnumerator()) { $row[$pair.Key] = $pair.Value }
        $row['firstRun'] = & $toTime (Get-TelemetryField $runs[0] 'time')
        $row['lastRun'] = & $toTime (Get-TelemetryField $runs[$runs.Count - 1] 'time')
        $row
    })

    $testRuns = @($window | Where-Object { $_.command -ceq 'test' })
    $test = $null
    if ($testRuns.Count -gt 0) {
        $tests = Get-TelemetryTests $testRuns
        $test = [ordered]@{ runs = $testRuns.Count; slowestRunners = @(Get-TelemetryRunners $testRuns); hotSpots = @($tests.hotSpots); flakyTests = @($tests.flakyTests) }
    }
    $recurring = @(Get-RecurringErrors $window | Select-Object -First 10)
    return [ordered]@{
        last = $Last; command = $(if ($Command) { $Command } else { $null }); minRuns = $script:TelemetryMinRuns
        entries = $usable.Count; skipped = $Skipped; runs = $window.Count
        insufficient = @($commands | Where-Object { -not $_.insufficient }).Count -eq 0
        commands = $commands; test = $test; recurringErrors = $recurring
    }
}

function Invoke-Telemetry($Info, [string]$Command, [int]$Last) {
    if ($Last -lt 1) { Stop-GodotCi "-Last must be at least 1, not $Last" 'invalid-arguments' }
    if ($Command -and $Command -cnotin $script:TelemetryCommands) {
        Stop-GodotCi "telemetry reads the runs of $($script:TelemetryCommands -join ', '); '$Command' leaves none in the history" 'invalid-arguments'
    }
    $skipped = 0
    $history = @(Read-RunHistory $Info.ProjectDir ([ref]$skipped))
    $report = Get-TelemetryReport $history $Last $Command $skipped
    $document = [ordered]@{ historyFile = (Join-Path $Info.ProjectDir '.godot/hyperdot-history.jsonl') }
    foreach ($key in $report.Keys) { $document[$key] = $report[$key] }
    Set-JsonField telemetry $document
    if (-not $script:JsonMode) {
        Write-Console ''
        Format-TelemetryReport $report
    }
}

function Format-TelemetryReport($Report) {
    if ($Report.runs -eq 0) {
        Write-Console "No runs in the history$(if ($Report.command) { " for $($Report.command)" }) yet; run test, build or export and ask again"
    }
    foreach ($c in $Report.commands) {
        $line = "{0,-8} {1,3} run(s), {2:P0} passed" -f $c.command, $c.runs, $c.passRate
        if ($c.insufficient) { $line += "; too few passing runs to time ($($c.timedRuns) of $($Report.minRuns))" }
        else {
            $line += "; mean $($c.meanSeconds) s, median $($c.medianSeconds) s, p95 $($c.p95Seconds) s"
            if ($c.trend) { $line += "; newer half $($c.trend.ratio)x the older" }
        }
        Write-Console $line
    }
    if ($Report.test) {
        foreach ($r in $Report.test.slowestRunners | Select-Object -First 3) {
            Write-Console "Slow runner $($r.runner): $(if ($r.insufficient) { "too few runs ($($r.runs))" } else { "mean $($r.meanSeconds) s, p95 $($r.p95Seconds) s" })"
        }
        foreach ($h in $Report.test.hotSpots | Select-Object -First 3) { Write-Console "Fails often: $($h.runner) $($h.name) in $($h.failedRuns) run(s)" }
        foreach ($f in $Report.test.flakyTests | Select-Object -First 3) {
            Write-Console "Flaky: $($f.runner) $($f.name) (failed in $($f.failedRuns), passed in $($f.passedRuns), $($f.retryRuns) retry(ies))"
        }
    }
    foreach ($e in $Report.recurringErrors | Select-Object -First 3) { Write-Console "Error in $($e.count) run(s), $($e.failedRuns) failed: $($e.key)" }
    if ($Report.skipped) { Write-Console "$($Report.skipped) damaged line(s) in the history were skipped" }
}
