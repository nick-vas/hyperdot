#!/usr/bin/env pwsh
# Self-test of `soak` on tests/soak-fixture (GDScript, ENet on localhost): a healthy run passes, a server that never frees
# memory fails as soak-leak, one that quits early fails as soak-failed. Needs Godot (GODOT_BIN, or the kit installs it).
# First, without Godot: the growth rate from synthetic samples (a step is not growth, a steady slope is), then metric values
# in Godot's own formats are read whole, and those that are not numbers are listed; -MaxMetricGrowth pairs, a metric's
# growth and the soak-leak text beside a heap metric. With Godot, each metric's series and a metric that climbs.
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

# -MaxMetricGrowth is read as name=limit pairs (anything else is refused before a process starts, checked below). soak-leak shows how a heap
# metric grew beside memory (issue 310), so a flat managed heap and a leak in it read differently.
$limits = ConvertFrom-MetricLimits 'managed_heap_after_gc_mb=5, entities=1e3'
if ((@($limits.Keys | ForEach-Object { "$_=$($limits[$_])" }) -join ' ') -ne 'managed_heap_after_gc_mb=5 entities=1000') { $failures += "-MaxMetricGrowth pairs: $(@($limits.Keys) -join ',')" }
$series = [ordered]@{ heap = [System.Collections.Generic.List[object]]::new() }
foreach ($i in 0..9) { $series['heap'].Add([pscustomobject]@{ T = 10.0 * $i; V = 40 + 0.001 * $i }) }
$heapGrowth = Get-SoakMetricGrowth $series
if ($heapGrowth['heap'].samples -ne 10 -or $heapGrowth['heap'].first -ne 40 -or [Math]::Abs($heapGrowth['heap'].growthPerHour - 0.36) -gt 0.01) { $failures += "a metric's growth: $($heapGrowth | ConvertTo-Json -Depth 4 -Compress)" }
$leakText = Get-SoakLeakText ([ordered]@{ name = 'server'; memoryMb = [ordered]@{ growthPerHour = 300; residentGrowthPerHour = 310 }; metricGrowth = $heapGrowth })
if ($leakText -notmatch '^server \+300 MB/h' -or $leakText -notmatch 'its heap went 40 to 40\.009, \+0\.36/h \(flat: the growth is outside that heap') { $failures += "soak-leak beside a heap metric: $leakText" }

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
# The three slopes behind the gate are reported too, and a warning says when the gate hides a step or a late leak. For
# each case: the whole-window, first-half and second-half slopes (MB/h, +-5), and the decision at a limit of 200 MB/h:
# 'none', 'warn' (the gate passes, a slope over the limit) or 'fail' (the gate itself is over the limit: soak-leak, no warning).
$limit = 200
$slopeCases = [ordered]@{
    'flat'                     = @{ Memory = { param($i) 50 + $noise[$i % 10] }; Whole = $null; Decision = 'none' }
    'step of 6 MB in the middle' = @{ Memory = { param($i) 50 + ($i -ge 10 ? 6 : 0) }; Whole = $null; Decision = 'warn' }
    'steady leak of 1000 MB/h' = @{ Memory = { param($i) 50 + $i * 1000 / 3600 + $noise[$i % 10] }; Whole = 1000; Decision = 'fail' }
    'leak that starts late'    = @{ Memory = { param($i) 50 + [Math]::Max(0, $i - 6) * 2000 / 3600 }; Whole = $null; Limit = 1000; Decision = 'warn' }   # 558 MB/h as the gate, 2000 in the second half; at 200 the gate itself fails
    'slow leak that starts late' = @{ Memory = { param($i) 50 + [Math]::Max(0, $i - 12) * 1500 / 3600 }; Whole = $null; Decision = 'warn' }
}
foreach ($name in $slopeCases.Keys) {
    $case = $slopeCases[$name]
    $slopes = Get-GrowthSlopes (New-SoakSamples $case.Memory)
    $min = [Math]::Min($slopes.Whole, [Math]::Min($slopes.First, $slopes.Second))
    if ($slopes.Smallest -ne $min -or $slopes.Smallest -ne (Get-GrowthMbPerHour (New-SoakSamples $case.Memory))) { $failures += "'$name': the gate should be the smallest of the three slopes: $($slopes | ConvertTo-Json -Depth 5 -Compress)" }
    if ($case.Whole -and [Math]::Abs($slopes.Whole - $case.Whole) -gt 50) { $failures += "'$name': whole-window slope should be about $($case.Whole): $($slopes.Whole)" }
    $caseLimit = $case.ContainsKey('Limit') ? $case.Limit : $limit
    $warning = Get-SoakGrowthWarning 'server' $slopes $caseLimit
    $decision = if ($slopes.Smallest -gt $caseLimit) { 'fail' } elseif ($warning) { 'warn' } else { 'none' }
    if ($decision -ne $case.Decision) { $failures += "'$name' should be '$($case.Decision)' at $caseLimit MB/h, not '$decision' ($($slopes | ConvertTo-Json -Depth 5 -Compress): $warning)" }
    if ($decision -eq 'warn' -and $warning -notmatch 'soak longer') { $failures += "'$name': the warning should advise a longer -Seconds: $warning" }
    if ($decision -ne 'warn' -and $warning) { $failures += "'$name': no warning expected: $warning" }
}
$stepSlopes = Get-GrowthSlopes (New-SoakSamples { param($i) 50 + ($i -ge 10 ? 6 : 0) })
if ($stepSlopes.Smallest -ne 0 -or $stepSlopes.Whole -le $limit -or $stepSlopes.First -ne 0 -or $stepSlopes.Second -ne 0) { $failures += "a step reads 0 in each half and a rate over the limit over the whole window: $($stepSlopes | ConvertTo-Json -Depth 5 -Compress)" }
$lateSlopes = Get-GrowthSlopes (New-SoakSamples { param($i) 50 + [Math]::Max(0, $i - 6) * 2000 / 3600 })
if ($lateSlopes.Smallest -lt 500 -or $lateSlopes.Smallest -gt 620 -or $lateSlopes.Second -lt 1500) { $failures += "the late leak of 2000 MB/h should read about 558 MB/h as the gate and more in the second half: $($lateSlopes | ConvertTo-Json -Depth 5 -Compress)" }
if (Get-SoakGrowthWarning 'server' $stepSlopes 0) { $failures += 'no limit (0), no warning' }
$onlySecond = [pscustomobject]@{ Smallest = 10.0; Whole = 150.0; Second = 300.0 }
if ((Get-SoakGrowthWarning 'server' $onlySecond 200) -notmatch 'second half \(300') { $failures += 'a second half over the limit alone should warn about the second half' }
$onlyWhole = [pscustomobject]@{ Smallest = 0.0; Whole = 400.0; Second = 0.0 }
$wholeWarning = Get-SoakGrowthWarning 'server' $onlyWhole 200
if ($wholeWarning -notmatch 'whole window \(400' -or $wholeWarning -match 'second half') { $failures += "a whole-window slope over the limit alone should warn about the whole window only: $wholeWarning" }
$few = Get-GrowthSlopes (New-SoakSamples { param($i) 50 + $i * 1000 / 3600 } 6)
if ($few.First -ne $few.Whole -or $few.Second -ne $few.Whole) { $failures += "with fewer than 8 samples the halves should equal the whole window: $($few | ConvertTo-Json -Depth 5 -Compress)" }
if ((Get-GrowthMbPerHour @()) -ne 0 -or (Get-GrowthMbPerHour (New-SoakSamples { param($i) 50 + $i } 2)) -ne 0) { $failures += 'fewer than 3 samples should read as 0 MB/h' }
$few = Get-GrowthMbPerHour (New-SoakSamples { param($i) 50 + $i * 1000 / 3600 } 6)
if ([Math]::Abs($few - 1000) -gt 1) { $failures += "6 samples of a steady leak should read as the whole-window slope, 1000 MB/h: $few" }

$tempDirs = [System.Collections.Generic.List[string]]::new()   # every results folder, removed at the end
function Invoke-Soak([string[]]$Extra, [string]$Project = $fixture, [double]$Warmup = 2, [double]$Seconds = 20) {
    $results = Join-Path ([System.IO.Path]::GetTempPath()) "soak-$([guid]::NewGuid().ToString('n').Substring(0, 8))"
    $tempDirs.Add($results)
    $json = & pwsh -NoProfile -NonInteractive -File (Join-Path $root 'ci/godot/hyperdot.ps1') soak -Project $Project -Seconds $Seconds -Warmup $Warmup `
        -MaxGrowthMbPerHour 200 -Results $results -Json @Extra 2>$null
    return ($json | Out-String | ConvertFrom-Json)
}

try {
$healthy = Invoke-Soak @('-Clients', '4', '-MaxMetricGrowth', 'backlog=100,nosuch=1')
if (-not $healthy.ok) { $failures += "a healthy run failed: $($healthy.error.code) $($healthy.error.message)" }
else {
    if (@($healthy.soak.processes | Where-Object { -not $_.ready }).Count) { $failures += 'a process never became ready' }
    foreach ($f in 'growthPerHour', 'growthWholeWindowPerHour', 'growthFirstHalfPerHour', 'growthSecondHalfPerHour') {
        if ($null -eq $healthy.soak.server.memoryMb.$f) { $failures += "soak.server.memoryMb.$f is missing" }
    }
    if ($null -eq $healthy.soak.warnings) { $failures += 'soak.warnings should be a list (empty when nothing grew)' }
    if ($healthy.soak.server.metrics.clients -ne 4) { $failures += "the server reported $($healthy.soak.server.metrics.clients) clients" }
    # Each metric is a series: read at every sample, past the warm-up. The fixture prints every 5 s, so 4 values in 20 s.
    $backlog = $healthy.soak.server.metricGrowth.backlog
    if ($null -eq $backlog -or $backlog.samples -lt 3 -or $backlog.growthPerHour -ne 0) { $failures += "the server's flat backlog metric: $($backlog | ConvertTo-Json -Depth 5 -Compress)" }
    if (@($healthy.soak.processes | Where-Object { $_.name -like 'client-*' -and $_.metricGrowth.rtt_ms.samples -lt 3 }).Count) { $failures += 'each client''s rtt_ms should be a series of 3 or more' }
    if (-not @($healthy.soak.warnings | Where-Object { $_.message -match 'nosuch=1 checked nothing' }).Count) { $failures += "a limit on a metric no process prints should be a warning: $($healthy.soak.warnings | ConvertTo-Json -Depth 4 -Compress)" }
}

# A window too short for 3 memory samples reads 0 MB/h and would pass any limit: refused up front, before a process starts.
$short = Invoke-Soak @('-Clients', '1') $fixture 0.5 1
if ($short.ok -or $short.error.code -ne 'invalid-arguments' -or $short.error.message -notmatch '3 memory samples') {
    $failures += "-Seconds 1 with -MaxGrowthMbPerHour should be refused as invalid-arguments: $($short.error.code) $($short.error.message)"
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
    # (Whether a flat server draws a growth warning is not asserted: the warning flags a window whose slopes disagree, which a
    # 30 s window on a shared runner does now and then - 293 and 446 MB/h against a smallest slope of 108 - and it is only a
    # warning. A real leak fails on the smallest slope, checked below.)
    elseif (-not $cs.soak.stop.clean -or $cs.soak.stop.exitCode -ne 0) { $failures += "the C# server should stop cleanly: $($cs.soak.stop | ConvertTo-Json -Depth 10 -Compress)" }
}

$leak = Invoke-Soak @('-Clients', '2', '-GameArgs', '--leak')
if ($leak.ok -or $leak.error.code -ne 'soak-leak') { $failures += "a leaking server should fail as soak-leak: $($leak.error.code) $($leak.error.message)" }
# A process with no heap metric of its own gets the hint to print one: process memory also grows when a runtime only holds
# what it freed (issue 310).
elseif ($leak.error.message -notmatch 'managed_heap_after_gc_mb') { $failures += "soak-leak should suggest a heap metric: $($leak.error.message)" }

# A metric that climbs fails -MaxMetricGrowth as soak-metric-growth, with no memory behind it: the fixture's --grow adds 10
# to its backlog a second, 36000 an hour.
$grow = Invoke-Soak @('-Clients', '1', '-GameArgs', '--grow', '-MaxMetricGrowth', 'backlog=1000')
if ($grow.ok -or $grow.error.code -ne 'soak-metric-growth' -or $grow.error.message -notmatch 'server backlog \+') { $failures += "a climbing metric should fail as soak-metric-growth: $($grow.error.code) $($grow.error.message)" }
$measured = if ($grow.soak) { $grow.soak.server.metricGrowth.backlog.growthPerHour } else { $null }
if ($null -eq $measured -or [Math]::Abs($measured - 36000) -gt 3600) { $failures += "backlog grew 36000 an hour, measured $measured" }
foreach ($bad in 'backlog', 'backlog=', 'backlog=fast', 'backlog=inf') {
    $malformed = Invoke-Soak @('-Clients', '1', '-MaxMetricGrowth', $bad)
    if ($malformed.ok -or $malformed.error.code -ne 'invalid-arguments' -or $malformed.error.message -notmatch 'name=limit') { $failures += "-MaxMetricGrowth '$bad' should be refused as invalid-arguments: $($malformed.error.code)" }
}

# Several players per client process (issue 304): each client is told its players, the server the whole count, and the
# report counts players as well as processes.
$many = Invoke-Soak @('-Clients', '2', '-PlayersPerClient', '3')
if (-not $many.ok) { $failures += "a run with 3 players per client failed: $($many.error.code) $($many.error.message)" }
else {
    $clientPlayers = @($many.soak.processes | Where-Object { $_.name -like 'client-*' } | ForEach-Object { $_.metrics.players })
    if ($many.soak.players -ne 6 -or $many.soak.playersPerClient -ne 3 -or $many.soak.clients -ne 2 -or $many.soak.server.metrics.players -ne 6 -or ($clientPlayers -join ',') -ne '3,3') {
        $failures += "2 clients of 3 players: the report should count 6 players, the server be told 6 and each client 3: players=$($many.soak.players) server=$($many.soak.server.metrics.players) clients=$($clientPlayers -join ',')"
    }
}
$refused = Invoke-Soak @('-Clients', '1', '-PlayersPerClient', '0')
if ($refused.ok -or $refused.error.code -ne 'invalid-arguments') { $failures += "-PlayersPerClient 0 should be refused as invalid-arguments: $($refused.error.code)" }

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
} finally {
    foreach ($temp in $tempDirs) { Remove-Item -LiteralPath $temp -Recurse -Force -ErrorAction SilentlyContinue }
}

if ($failures) { $failures | ForEach-Object { Write-Host "FAIL $_" -ForegroundColor Red }; exit 1 }
Write-Host 'soak passes a healthy server and clients, catches a leak, a climbing metric and a crash, a junk flood degrades the server, and the SIGTERM stop tells a server with a handler from one without'
exit 0
