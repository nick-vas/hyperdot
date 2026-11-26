#!/usr/bin/env pwsh
# Self-test of Invoke-Logged's time limit: a program that hangs is stopped, with its child processes, and returns 124;
# one that finishes keeps its exit code and its output. And every program the kit starts sees HYPERDOT_RUN=1. pwsh itself is the test program, so this runs on every OS.
Set-StrictMode -Version 3.0
$ErrorActionPreference = 'Stop'
. (Join-Path $PSScriptRoot '../ci/godot/lib/Common.ps1')

$pwshPath = (Get-Process -Id $PID).Path
$log = Join-Path ([IO.Path]::GetTempPath()) "process-timeout-$PID.log"
$failures = @()

$env:HYPERDOT_TIMEOUT = '3'
$clock = [Diagnostics.Stopwatch]::StartNew()
# The child starts a grandchild that would outlive it, as a game's helper process might.
$hang = "Write-Output started; Start-Process '$pwshPath' -ArgumentList '-NoProfile', '-Command', '`"Start-Sleep 120`"' -NoNewWindow; Start-Sleep 120"
$code = Invoke-Logged $pwshPath @('-NoProfile', '-Command', $hang) $log
$seconds = $clock.Elapsed.TotalSeconds
$text = Get-Content -LiteralPath $log -Raw
if ($code -ne 124) { $failures += "hung program returned $code, expected 124" }
if ($seconds -gt 15) { $failures += "hung program was stopped after $([int]$seconds) s, expected about 3" }
if ($text -notmatch 'started' -or $text -notmatch 'was still running after 3 s') { $failures += "hung program's log: $text" }

# A program that closes its output and then hangs: both pipes reach their end, and the wait for its exit has the limit too.
if (-not $IsWindows) {
    $clock.Restart()
    $code = Invoke-Logged sh @('-c', 'echo started; exec >/dev/null 2>&1; sleep 60') $log
    $seconds = $clock.Elapsed.TotalSeconds
    if ($code -ne 124 -or $seconds -gt 15) { $failures += "a program that closed its output and hung returned $code after $([int]$seconds) s, expected 124 after about 3" }
}

Remove-Item Env:HYPERDOT_TIMEOUT
$code = Invoke-Logged $pwshPath @('-NoProfile', '-Command', 'Write-Output out; [Console]::Error.WriteLine(''err''); exit 3') $log
$lines = @(Get-Content -LiteralPath $log)
if ($code -ne 3) { $failures += "finished program returned $code, expected 3" }
if ('out' -notin $lines -or 'err' -notin $lines) { $failures += "finished program's log: $($lines -join ' | ')" }

# Every program the kit starts sees HYPERDOT_RUN=1, so a game can tell a kit run from a player's (issue 309); the kit's own
# process does not get it, so a shell that ran the kit does not keep it.
[Environment]::SetEnvironmentVariable('HYPERDOT_RUN', $null)
$code = Invoke-Logged $pwshPath @('-NoProfile', '-Command', 'Write-Output "run=$env:HYPERDOT_RUN"') $log
if ('run=1' -notin @(Get-Content -LiteralPath $log)) { $failures += "a program Invoke-Logged starts should see HYPERDOT_RUN=1: $(Get-Content -LiteralPath $log -Raw)" }
$bounded = Invoke-ExternalBounded $pwshPath @('-NoProfile', '-Command', 'Write-Output "run=$env:HYPERDOT_RUN"')
if ('run=1' -notin @($bounded.Lines)) { $failures += "a program Invoke-ExternalBounded starts should see HYPERDOT_RUN=1: $($bounded.Lines -join ' | ')" }
if ($env:HYPERDOT_RUN) { $failures += "the kit's own process should not get HYPERDOT_RUN: $env:HYPERDOT_RUN" }
Remove-Item -LiteralPath $log

if ($failures) {
    foreach ($failure in $failures) { Write-Host "FAIL $failure" }
    exit 1
}
Write-Host "Invoke-Logged stops a hung program after its time limit (code 124 in $([int]$seconds) s) and keeps a finished one's exit code; the programs the kit starts see HYPERDOT_RUN=1"
