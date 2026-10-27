#!/usr/bin/env pwsh
# Stage 0 of the Self-test cache (docs/ci-cache.md): what the input hashes say about this run, and which results may be
# recorded. Nothing is skipped. Run by the `record` job after every job, with $env:NEEDS = toJSON(needs).
#
# For each job it writes, to cache-observations.jsonl, one line: job, hash, whether a marker for that hash was found
# before the run (`hit`), whether Select-Jobs selected the job, its result, the event, the run attempt and the run id (the
# job's minutes are read from the API with that id when the lines are analysed). It appends a table to the step summary.
# It outputs `save-<job>=true` for the jobs whose result is to be recorded: the job succeeded, no marker existed, and the
# run is not a pull request from a fork (a fork's workflow code is not trusted to write a marker the base would read).
param(
    [string]$Needs = $env:NEEDS,
    [string]$OutputDirectory = $env:RUNNER_TEMP,
    [string]$EventName = $env:GITHUB_EVENT_NAME,
    [string]$RunId = $env:GITHUB_RUN_ID,
    [string]$RunAttempt = $env:GITHUB_RUN_ATTEMPT,
    # 'true' when the run may write markers (not a fork's pull request).
    [string]$MayWrite = $env:MAY_WRITE
)
Set-StrictMode -Version 3.0
$ErrorActionPreference = 'Stop'

$jobResults = $Needs | ConvertFrom-Json -AsHashtable
$changes = $jobResults['changes']['outputs']
$jobs = 'lint', 'zero-config', 'csharp', 'explicit-runners', 'action', 'local-windows', 'init', 'measure', 'game-benchmark', 'field-test', 'web'
$lines = [System.Collections.Generic.List[string]]::new()
$rows = [System.Collections.Generic.List[string]]::new()
$outputs = [System.Collections.Generic.List[string]]::new()
foreach ($job in $jobs) {
    $hash = if ($changes.ContainsKey("hash-$job")) { [string]$changes["hash-$job"] } else { '' }
    $hit = $changes.ContainsKey("hit-$job") -and [string]$changes["hit-$job"] -eq 'true'
    $selected = if ($job -eq 'lint') { $true } elseif ($changes.ContainsKey($job)) { [string]$changes[$job] -eq 'true' } else { $false }
    $result = if ($jobResults.ContainsKey($job)) { [string]$jobResults[$job]['result'] } else { 'unknown' }
    $save = $result -eq 'success' -and -not $hit -and $hash -and $MayWrite -eq 'true'
    $outputs.Add("save-$job=$("$save".ToLowerInvariant())")
    $lines.Add((ConvertTo-Json -Compress -Depth 3 -InputObject ([ordered]@{ job = $job; hash = $hash; hit = $hit; selected = $selected; result = $result
        event = $EventName; runAttempt = [int]$RunAttempt; runId = [string]$RunId })))
    $rows.Add("| ``$job`` | ``$(if ($hash) { $hash.Substring(0, 12) } else { '-' })`` | $(if ($hit) { 'hit' } else { 'miss' }) | $(if ($selected) { 'yes' } else { 'no' }) | $result |")
}
Set-Content -LiteralPath (Join-Path $OutputDirectory 'cache-observations.jsonl') -Value $lines -Encoding utf8
# The marker's body: which run proved the hash.
Set-Content -LiteralPath (Join-Path $OutputDirectory 'ci-marker') -Value "run $RunId attempt $RunAttempt" -Encoding utf8

$table = @('### Input hashes (stage 0: measured, nothing is skipped)', '',
    '| Job | Hash | A green marker before this run | Selected | Result |', '|---|---|---|---|---|') + $rows
if ($env:GITHUB_STEP_SUMMARY) { Add-Content -LiteralPath $env:GITHUB_STEP_SUMMARY -Value ($table -join "`n") }
else { $table | ForEach-Object { Write-Host $_ } }
if ($env:GITHUB_OUTPUT) { Add-Content -LiteralPath $env:GITHUB_OUTPUT -Value $outputs }
else { $outputs | ForEach-Object { Write-Host $_ } }
