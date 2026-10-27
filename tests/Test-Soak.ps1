#!/usr/bin/env pwsh
# Self-test of `soak` on tests/soak-fixture (GDScript, ENet on localhost): a healthy run passes, a server that never frees
# memory fails as soak-leak, one that quits early fails as soak-failed. Needs Godot (GODOT_BIN, or the kit installs it).
# First, without Godot: the growth rate from synthetic samples (a step is not growth, a steady slope is), then metric values
# in Godot's own formats are read whole, and those that are not numbers are listed.
Set-StrictMode -Version 3.0
$ErrorActionPreference = 'Stop'
$root = Split-Path $PSScriptRoot
$fixture = Join-Path $PSScriptRoot 'soak-fixture'
$failures = @()

foreach ($lib in 'Common', 'Soak') { . (Join-Path $root "ci/godot/lib/$lib.ps1") }
$parsed = ConvertFrom-SoakMetrics @('[soak] metric rtt_ms 1e-07', '[soak] metric bytes 3000000000000000000000.0', '[soak] metric delta -2.5',
    '[soak] metric version 1.2.3', '[soak] metric ratio inf', 'noise')
$read = @($parsed.Metrics.GetEnumerator() | ForEach-Object { "$($_.Key)=$($_.Value.ToString([cultureinfo]::InvariantCulture))" }) -join ' '
if ($read -ne 'rtt_ms=1E-07 bytes=3E+21 delta=-2.5') { $failures += "metric values should be read whole: $read" }
if ((@($parsed.Unparsed) -join ' | ') -ne '[soak] metric version 1.2.3 | [soak] metric ratio inf') { $failures += "values that are not numbers should be listed: $(@($parsed.Unparsed) -join ' | ')" }

# The growth rate, from synthetic samples (one a second for 20 s, as a 20 s run takes them). A one-time step reads as no
# growth, whatever the window: a warm-up step, a step in the middle, one at either end, and a decaying warm-up. A steady
# leak keeps its rate, with noise on it, and one that starts after a flat stretch too. Slopes over the whole window gave
# 400 MB/h for a 1.5 MB step and failed the C# case on a GitHub runner.
function New-SoakSamples([scriptblock]$Memory, [int]$Count = 20) {
    return @(0..($Count - 1) | ForEach-Object { [pscustomobject]@{ T = [double](15 + $_); Mb = [double](& $Memory $_); Resident = [double](& $Memory $_) } })
}
$noise = @(0.02, -0.03, 0.01, 0.04, -0.02, 0.0, -0.04, 0.03, -0.01, 0.02)
$growthCases = [ordered]@{
    'flat'                       = @{ Memory = { param($i) 50 + $noise[$i % 10] }; Min = -20; Max = 20 }
    'step of 6 MB in the middle'  = @{ Memory = { param($i) 50 + ($i -ge 10 ? 6 : 0) }; Min = -1; Max = 1 }
    'step of 6 MB at the start'   = @{ Memory = { param($i) 50 + ($i -ge 2 ? 6 : 0) }; Min = -1; Max = 1 }
    'step of 6 MB at the end'     = @{ Memory = { param($i) 50 + ($i -ge 17 ? 6 : 0) }; Min = -1; Max = 1 }
    'warm-up decaying to flat'    = @{ Memory = { param($i) 50 + 8 * (1 - [Math]::Exp(-$i / 3.0)) }; Min = -1; Max = 100 }
    'steady leak of 1000 MB/h'    = @{ Memory = { param($i) 50 + $i * 1000 / 3600 + $noise[$i % 10] }; Min = 900; Max = 1100 }
    'steady leak of 400 MB/h'     = @{ Memory = { param($i) 50 + $i * 400 / 3600 + $noise[$i % 10] }; Min = 300; Max = 500 }
    'leak that starts late'       = @{ Memory = { param($i) 50 + [Math]::Max(0, $i - 6) * 2000 / 3600 }; Min = 400; Max = 2100 }   # still over a 200 MB/h limit
}
foreach ($name in $growthCases.Keys) {
    $case = $growthCases[$name]
    $rate = Get-GrowthMbPerHour (New-SoakSamples $case.Memory)
    if ($rate -lt $case.Min -or $rate -gt $case.Max) { $failures += "growth for '$name' should be $($case.Min) to $($case.Max) MB/h: $rate" }
}
if ((Get-GrowthMbPerHour @()) -ne 0 -or (Get-GrowthMbPerHour (New-SoakSamples { param($i) 50 + $i } 2)) -ne 0) { $failures += 'fewer than 3 samples should read as 0 MB/h' }
$few = Get-GrowthMbPerHour (New-SoakSamples { param($i) 50 + $i * 1000 / 3600 } 6)
if ([Math]::Abs($few - 1000) -gt 1) { $failures += "6 samples of a steady leak should read as the whole-window slope, 1000 MB/h: $few" }

function Invoke-Soak([string[]]$Extra, [string]$Project = $fixture, [double]$Warmup = 2, [double]$Seconds = 20) {
    $results = Join-Path ([System.IO.Path]::GetTempPath()) "soak-$([guid]::NewGuid().ToString('n').Substring(0, 8))"
    $json = & pwsh -NoProfile -NonInteractive -File (Join-Path $root 'ci/godot/hyperdot.ps1') soak -Project $Project -Seconds $Seconds -Warmup $Warmup `
        -MaxGrowthMbPerHour 200 -Results $results -Json @Extra 2>$null
    return ($json | Out-String | ConvertFrom-Json)
}

$healthy = Invoke-Soak @('-Clients', '4')
if (-not $healthy.ok) { $failures += "a healthy run failed: $($healthy.error.code) $($healthy.error.message)" }
else {
    if (@($healthy.soak.processes | Where-Object { -not $_.ready }).Count) { $failures += 'a process never became ready' }
    if ($healthy.soak.server.metrics.clients -ne 4) { $failures += "the server reported $($healthy.soak.server.metrics.clients) clients" }
}

# The stop at the end: SIGTERM, as a host sends it. The GDScript fixture has no way to catch it and dies with 143; the C#
# fixture catches it (PosixSignalRegistration), drains and quits with 0.
if ($healthy.ok -and -not $IsWindows) {
    if ($healthy.soak.stop.clean -or $healthy.soak.stop.exitCode -ne 143) { $failures += "the GDScript server should die on SIGTERM with 143: $($healthy.soak.stop | ConvertTo-Json -Depth 10 -Compress)" }
}
if (-not $IsWindows) {
    $strict = Invoke-Soak @('-Clients', '1', '-RequireCleanStop')
    if ($strict.ok -or $strict.error.code -ne 'soak-unclean-stop') { $failures += "-RequireCleanStop should fail a server SIGTERM kills: $($strict.error.code) $($strict.error.message)" }
    # A .NET server's memory grows for its first seconds (the JIT tiering code up, the GC sizing its heap): a 2 s warm-up
    # measured 50 MB/h here and 374 MB/h on a GitHub runner (run 697), a 10 s one 36 MB/h. Measure it warm, and for 30 s:
    # a one-time step of 2 MB is 400 MB/h over a 20 s window (the growth ignores steps, but a longer window halves the rest).
    $cs = Invoke-Soak @('-Clients', '1', '-RequireCleanStop') (Join-Path $PSScriptRoot 'soak-fixture-cs') 15 30
    if (-not $cs.ok) { $failures += "the C# server that handles SIGTERM failed: $($cs.error.code) $($cs.error.message)" }
    elseif (-not $cs.soak.stop.clean -or $cs.soak.stop.exitCode -ne 0) { $failures += "the C# server should stop cleanly: $($cs.soak.stop | ConvertTo-Json -Depth 10 -Compress)" }
}

$leak = Invoke-Soak @('-Clients', '2', '-GameArgs', '--leak')
if ($leak.ok -or $leak.error.code -ne 'soak-leak') { $failures += "a leaking server should fail as soak-leak: $($leak.error.code) $($leak.error.message)" }

$crash = Invoke-Soak @('-Clients', '2', '-GameArgs', '--crash-after=5')
if ($crash.ok -or $crash.error.code -ne 'soak-failed' -or $crash.error.message -notmatch 'server exited with 3') {
    $failures += "a server that quits should fail as soak-failed: $($crash.error.code) $($crash.error.message)"
}

# -JunkPps floods the server's own port on 127.0.0.1. 100k packets a second crowd legitimate input out of the ENet
# socket buffer: the server loses a large share of its input or drops clients outright (the soak run then fails).
$flood = Invoke-Soak @('-Clients', '2', '-JunkPps', '100000')
if ($flood.soak.junk.pps -ne 100000) { $failures += "a junk flood should record its rate: $($flood.soak.junk | ConvertTo-Json -Depth 10 -Compress)" }
if ($flood.soak.junk.packetsSent -le 0) { $failures += "a junk flood should send packets to the server: $($flood.soak.junk.packetsSent)" }
$degraded = (-not $flood.ok -and $flood.error.code -eq 'soak-failed') -or ($flood.soak.server.metrics.input_loss_pct -gt 5)
if (-not $degraded) {
    $failures += "a 100k-pps flood should degrade the server: ok $($flood.ok), input loss $($flood.soak.server.metrics.input_loss_pct)%, $($flood.soak.junk.packetsSent) packets sent in $($flood.soak.seconds) s"
}

if ($failures) { $failures | ForEach-Object { Write-Host "FAIL $_" -ForegroundColor Red }; exit 1 }
Write-Host 'soak passes a healthy server and clients, catches a leak and a crash, a junk flood degrades the server, and the SIGTERM stop tells a server with a handler from one without'
exit 0
