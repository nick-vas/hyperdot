#Requires -Version 7.6
<#
.SYNOPSIS
    The -MaxMinutes of a Token benchmark job: the requested max_minutes (empty or 0 for none) held to the job's limit minus
    45 minutes, the longest session (a milestone) that can still be running when the last one starts. Always a number, so a
    job never runs without a time limit. Run by .github/workflows/token-benchmark.yml and tests/Test-TokenBenchmark.ps1.

.EXAMPLE
    pwsh .github/scripts/Get-BenchmarkMinutes.ps1 -MaxMinutes 300 -JobMinutes 330   # 285
#>
param(
    [string]$MaxMinutes = '',
    [Parameter(Mandatory)][int]$JobMinutes
)
Set-StrictMode -Version 3.0
$ErrorActionPreference = 'Stop'

$margin = 45
if ($MaxMinutes -and $MaxMinutes -notmatch '\A[0-9]+\z') { throw "max_minutes '$MaxMinutes' is not a whole number of minutes" }
$requested = if ($MaxMinutes) { [int]$MaxMinutes } else { 0 }
$cap = $JobMinutes - $margin
if ($cap -lt 1) { throw "A job of $JobMinutes minutes leaves no time for sessions after the $margin-minute margin" }
if ($requested -gt 0) { [Math]::Min($requested, $cap) } else { $cap }
