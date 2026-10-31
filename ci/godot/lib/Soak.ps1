# soak: one headless server and -Clients headless clients of the game on this machine for -Seconds, to find what only
# time and load show: crashes, engine errors, memory that keeps growing, and failures the game detects itself (a desync,
# a lost connection). The game takes part through a small contract of command-line flags and printed lines:
#   started with   --soak-role=server|client --soak-port=<port> --soak-id=<n>  (plus -GameArgs)
#   prints         [soak] ready            once listening (server) or connected (client)
#                  [soak] metric <name> <number>
#                  [soak] fail <reason>
# Each process writes its own log (Godot's --log-file), so dozens of them never fight over one pipe.

function Get-FreeUdpPort {
    $socket = [System.Net.Sockets.UdpClient]::new(0)
    try { return ([System.Net.IPEndPoint]$socket.Client.LocalEndPoint).Port } finally { $socket.Dispose() }
}

# The "[soak] metric <name> <value>" lines of a process's log: the values as numbers (the last one of each name), and the
# lines whose value is not one. The value is the whole next word, read in the invariant culture, so Godot's 1e-07 is a
# number, and 1.2.3 (or inf, nan) is reported rather than cut short or thrown on.
function ConvertFrom-SoakMetrics([string[]]$Lines) {
    $metrics = [ordered]@{}
    $unparsed = [System.Collections.Generic.List[string]]::new()
    foreach ($line in $Lines) {
        if ($line -notmatch '^\[soak\] metric (?<n>\S+) (?<v>\S+)') { continue }
        $value = 0.0
        $ok = [double]::TryParse($Matches.v, [System.Globalization.NumberStyles]::Float, [cultureinfo]::InvariantCulture, [ref]$value)
        if ($ok -and [double]::IsFinite($value)) { $metrics[$Matches.n] = $value }
        else { $unparsed.Add($line) }
    }
    return [pscustomobject]@{ Metrics = $metrics; Unparsed = $unparsed.ToArray() }
}

# A loopback-only junk flood for measuring how an ENet server holds up when packets crowd its socket buffer. It sends
# small UDP datagrams to 127.0.0.1 on the server's own port (never any other host) at about -JunkPps a second for the
# run, in a child process so the pacing does not steal the sampler's thread. The child writes how many it sent to a file.
function Start-JunkFlood([int]$Port, [int]$Pps, [double]$Seconds, [string]$ResultsDir) {
    $countFile = Join-Path $ResultsDir 'junk.count'
    if (Test-Path -LiteralPath $countFile) { Remove-Item -LiteralPath $countFile }
    $floodScript = Join-Path $ResultsDir 'junk-flood.ps1'
    # 127.0.0.1 is hard-coded: the flood can only reach a server on this machine, the one soak just started.
    @'
param([int]$Port, [int]$Pps, [double]$Seconds, [string]$CountFile)
$ErrorActionPreference = 'Stop'
$socket = [System.Net.Sockets.Socket]::new('InterNetwork', 'Dgram', 'Udp')
$socket.Connect([System.Net.IPEndPoint]::new([System.Net.IPAddress]::Loopback, $Port))
$buffer = [byte[]]::new(16)
$clock = [System.Diagnostics.Stopwatch]::StartNew()
$sent = [long]0
while ($clock.Elapsed.TotalSeconds -lt $Seconds) {
    $target = [long]($Pps * $clock.Elapsed.TotalSeconds)
    if ($sent -lt $target) {
        $batch = [Math]::Min(500, $target - $sent)
        for ($i = 0; $i -lt $batch; $i++) { [void]$socket.Send($buffer) }
        $sent += $batch
    } else { Start-Sleep -Milliseconds 1 }
}
$socket.Dispose()
[System.IO.File]::WriteAllText($CountFile, $sent.ToString())
'@ | Set-Content -LiteralPath $floodScript -Encoding utf8
    $info = [System.Diagnostics.ProcessStartInfo]::new((Get-Process -Id $PID).Path)
    foreach ($a in @('-NoProfile', '-File', $floodScript, '-Port', $Port, '-Pps', $Pps, '-Seconds', $Seconds, '-CountFile', $countFile)) {
        $info.ArgumentList.Add([string]$a)
    }
    $info.UseShellExecute = $false
    # Keep the child's streams off the parent's stdout so a -Json run stays one clean document (the flood prints nothing).
    $info.RedirectStandardOutput = $true
    $info.RedirectStandardError = $true
    return [pscustomobject]@{ Process = [System.Diagnostics.Process]::Start($info); CountFile = $countFile }
}

function Start-SoakProcess([string]$ProjectDir, [string]$Log, [string[]]$UserArgs) {
    $info = [System.Diagnostics.ProcessStartInfo]::new($env:GODOT_BIN)
    foreach ($a in @('--headless', '--path', $ProjectDir, '--log-file', $Log, '--') + @($UserArgs)) { $info.ArgumentList.Add($a) }
    $info.UseShellExecute = $false
    # The log file holds the output; the pipes are drained and discarded so a chatty process never blocks on a full pipe.
    $info.RedirectStandardOutput = $true
    $info.RedirectStandardError = $true
    $process = [System.Diagnostics.Process]::Start($info)
    $process.BeginOutputReadLine()
    $process.BeginErrorReadLine()
    return $process
}

# Least-squares slope of memory over time for the samples as given, in MB per hour.
function Get-SlopeMbPerHour($Points, [string]$Field) {
    if ($Points.Count -lt 3) { return 0.0 }
    $meanT = ($Points | Measure-Object -Property T -Average).Average
    $meanM = ($Points | Measure-Object -Property $Field -Average).Average
    $num = 0.0; $den = 0.0
    foreach ($p in $Points) { $num += ($p.T - $meanT) * ($p.$Field - $meanM); $den += ($p.T - $meanT) * ($p.T - $meanT) }
    if ($den -eq 0) { return 0.0 }
    return $num / $den * 3600
}

# Steady growth of memory over time, in MB per hour: not the noise of one sample, and not a one-time step. A slope over the
# whole window turns a step (a JIT tier, a GC resizing its heap, a pool filling) into a rate: 1.5 MB in the middle of a 20 s
# window reads as 400 MB/h. A leak grows through the whole window, so the growth is the smallest of the slope over all samples
# and over each half; a step shows in one half or between them, a leak in both. $Field picks the sample's value: Mb (the
# memory a leak shows in) or Resident (everything resident).
# All three slopes behind the growth, in MB per hour, rounded to 0.1: over the whole window (Whole), over its first half
# (First) and over its second (Second). With fewer than 8 samples a half is too short to read, so both halves equal the
# whole. Smallest is the gate.
function Get-GrowthSlopes($Samples, [string]$Field = 'Mb') {
    $points = @($Samples)
    $whole = Get-SlopeMbPerHour $points $Field
    $first = $whole; $second = $whole
    if ($points.Count -ge 8) {
        $half = [int][Math]::Floor($points.Count / 2)
        $first = Get-SlopeMbPerHour @($points[0..($half - 1)]) $Field
        $second = Get-SlopeMbPerHour @($points[$half..($points.Count - 1)]) $Field
    }
    return [ordered]@{
        Whole = [Math]::Round($whole, 1); First = [Math]::Round($first, 1); Second = [Math]::Round($second, 1)
        Smallest = [Math]::Round([Math]::Min($whole, [Math]::Min($first, $second)), 1)
    }
}
function Get-GrowthMbPerHour($Samples, [string]$Field = 'Mb') { return (Get-GrowthSlopes $Samples $Field).Smallest }

# The warning for a process whose smallest slope passes the limit while the whole-window or the second-half slope does not:
# a one-time step, or a leak that started late. $null when there is nothing to say: no limit, a failing gate (soak-leak says
# it), or no slope over the limit. $Growth is a Get-GrowthSlopes result (or a process's memoryMb entry, same numbers).
function Get-SoakGrowthWarning([string]$Name, $Growth, [double]$Limit) {
    if ($Limit -le 0 -or $Growth.Smallest -gt $Limit) { return $null }
    $over = @()
    if ($Growth.Whole -gt $Limit) { $over += "over the whole window ($($Growth.Whole) MB/h)" }
    if ($Growth.Second -gt $Limit) { $over += "in the second half ($($Growth.Second) MB/h)" }
    if (-not $over) { return $null }
    return "$Name's memory grew $($over -join ' and ') against a limit of $Limit MB/h, but the smallest slope is $($Growth.Smallest) MB/h: a one-time step or a leak that started late; soak longer (-Seconds) to tell them apart"
}
# The memory a leak grows, in MB: on Linux the anonymous resident memory (RssAnon: heaps and stacks), not the pages of
# the binary, libraries and .NET assemblies mapped from files, which fill in as code first runs and grew a C# server's
# working set about 370 MB/h for minutes on GitHub's runners with nothing leaking; elsewhere the working set.
function Get-LeakMemoryMb([System.Diagnostics.Process]$Process) {
    if ($IsLinux) {
        try {
            foreach ($line in [System.IO.File]::ReadAllLines("/proc/$($Process.Id)/status")) {
                if ($line -match '^RssAnon:\s+(\d+)\s+kB') { return [double]$Matches[1] / 1024 }
            }
        } catch [System.IO.IOException] { Write-Verbose "$($Process.Id) has no status to read" }
    }
    return $Process.WorkingSet64 / 1MB
}

function Invoke-Soak {
    param($Info, [int]$Clients, [double]$Seconds, [double]$Warmup, [string]$ResultsDir, [string[]]$GameArgs, [double]$MaxGrowthMbPerHour, [int]$JunkPps,
        [double]$StopGraceSeconds = 30, [switch]$RequireCleanStop)
    if ($Clients -lt 1) { Stop-GodotCi '-Clients must be 1 or more' 'invalid-arguments' }
    if ($JunkPps -lt 0) { Stop-GodotCi '-JunkPps must be 0 or more' 'invalid-arguments' }
    New-Item -ItemType Directory -Force $ResultsDir | Out-Null
    $port = Get-FreeUdpPort
    $extra = @(Split-GameArgs $GameArgs)
    $procs = [System.Collections.Generic.List[object]]::new()
    $flood = $null
    $stop = $null
    $sampleEvery = [Math]::Max(1.0, [Math]::Min(30.0, $Seconds / 20))
    # Growth is a slope, which needs 3 samples (Get-SlopeMbPerHour); the loop checks the clock every 0.25 s. A window too short
    # for them would report 0 MB/h and pass any -MaxGrowthMbPerHour, so refuse it rather than gate on nothing.
    $shortest = 2 * $sampleEvery + 0.5
    if ($MaxGrowthMbPerHour -gt 0 -and $Seconds -lt $shortest) {
        Stop-GodotCi "-MaxGrowthMbPerHour needs at least 3 memory samples, one every $sampleEvery s, so -Seconds of $shortest or more (not $Seconds)" 'invalid-arguments'
    }

    Start-LogGroup "Soak: 1 server and $Clients client(s) for $Seconds s (port $port)$(if ($JunkPps) { ", junk flood $JunkPps pps" })"
    try {
        $serverLog = Join-Path $ResultsDir 'server.log'
        $procs.Add([pscustomobject]@{ Name = 'server'; Log = $serverLog; Samples = [System.Collections.Generic.List[object]]::new()
            Process = Start-SoakProcess $Info.ProjectDir $serverLog (@('--soak-role=server', "--soak-port=$port", "--soak-clients=$Clients") + $extra) })
        Start-Sleep -Milliseconds 500   # the server listens before the first client knocks
        for ($i = 1; $i -le $Clients; $i++) {
            $log = Join-Path $ResultsDir "client-$i.log"
            $procs.Add([pscustomobject]@{ Name = "client-$i"; Log = $log; Samples = [System.Collections.Generic.List[object]]::new()
                Process = Start-SoakProcess $Info.ProjectDir $log (@('--soak-role=client', "--soak-port=$port", "--soak-id=$i") + $extra) })
        }

        $clock = [System.Diagnostics.Stopwatch]::StartNew()
        $end = $Warmup + $Seconds
        # Flood for the whole run, the warm-up included, so the measured window is entirely under load.
        if ($JunkPps -gt 0) { $flood = Start-JunkFlood $port $JunkPps $end $ResultsDir }
        $nextSample = $Warmup
        while ($clock.Elapsed.TotalSeconds -lt $end) {
            Start-Sleep -Milliseconds 250
            if (@($procs | Where-Object { $_.Process.HasExited }).Count -gt 0) { break }   # a crash ends the run early
            if ($clock.Elapsed.TotalSeconds -ge $nextSample) {
                $t = $clock.Elapsed.TotalSeconds
                foreach ($p in $procs) {
                    try { $p.Process.Refresh(); $p.Samples.Add([pscustomobject]@{ T = $t; Mb = (Get-LeakMemoryMb $p.Process); Resident = $p.Process.WorkingSet64 / 1MB; Cpu = $p.Process.TotalProcessorTime.TotalSeconds }) }
                    catch [System.InvalidOperationException] { Write-Verbose "$($p.Name) exited while sampled" }
                }
                $nextSample += $sampleEvery
            }
        }
        $ranFor = [Math]::Round($clock.Elapsed.TotalSeconds, 1)
    } finally {
        # The flood ends with the run; wait a moment for it to write its count, then make sure it is gone.
        if ($flood) {
            $flood.Process.WaitForExit(3000) | Out-Null
            if (-not $flood.Process.HasExited) { try { $flood.Process.Kill($true) } catch [System.InvalidOperationException] { Write-Verbose 'flood already gone' } }
        }
        $exited = @{}
        foreach ($p in $procs) { if ($p.Process.HasExited) { $exited[$p.Name] = $p.Process.ExitCode } }
        # Clients first, so the server does not report them as lost.
        foreach ($p in @($procs | Select-Object -Skip 1)) {
            if (-not $p.Process.HasExited) { try { $p.Process.Kill($true) } catch [System.InvalidOperationException] { Write-Verbose 'already gone' } }
            $p.Process.WaitForExit(5000) | Out-Null
        }
        # Then the server, the way a host stops it: SIGTERM, and a grace period before the kill. Godot has no handler of
        # its own, so without one in the game (C#'s PosixSignalRegistration) it dies at once, mid-match, with 143.
        $server = $procs[0].Process
        if (-not $server.HasExited -and -not $IsWindows) {
            $clock = [System.Diagnostics.Stopwatch]::StartNew()
            & kill -s TERM $server.Id 2>$null
            $quit = $server.WaitForExit([int]($StopGraceSeconds * 1000))
            if (-not $quit) { try { $server.Kill($true) } catch [System.InvalidOperationException] { Write-Verbose 'already gone' }; $server.WaitForExit(5000) | Out-Null }
            $stop = [ordered]@{
                signal = 'SIGTERM'; graceSeconds = $StopGraceSeconds
                exitCode = $quit ? $server.ExitCode : $null
                seconds = $quit ? [Math]::Round($clock.Elapsed.TotalSeconds, 2) : $null
                clean = $quit -and $server.ExitCode -eq 0
            }
        } elseif (-not $server.HasExited) {
            try { $server.Kill($true) } catch [System.InvalidOperationException] { Write-Verbose 'already gone' }   # Windows: no SIGTERM to send
            $server.WaitForExit(5000) | Out-Null
        }
        Stop-LogGroup
    }

    $report = @(); $problems = @(); $errors = @(); $errorDetails = @()
    foreach ($p in $procs) {
        $lines = if (Test-Path -LiteralPath $p.Log) { @(Get-Content -LiteralPath $p.Log) } else { @() }
        $parsed = ConvertFrom-SoakMetrics $lines
        $metrics = $parsed.Metrics
        foreach ($bad in $parsed.Unparsed) { Write-CiLog "$($p.Name): not a number, so not in metrics: $bad" }
        $fails = @($lines | Where-Object { $_ -match '^\[soak\] fail ' } | ForEach-Object { $_ -replace '^\[soak\] fail ', '' })
        $ready = @($lines | Where-Object { $_ -eq '[soak] ready' }).Count -gt 0
        $samples = @($p.Samples)
        $slopes = Get-GrowthSlopes $samples
        $entry = [ordered]@{
            name = $p.Name; ready = $ready
            exitCode = $exited.ContainsKey($p.Name) ? $exited[$p.Name] : $null
            memoryMb = [ordered]@{
                start = $samples ? [Math]::Round($samples[0].Mb, 1) : $null
                end = $samples ? [Math]::Round($samples[-1].Mb, 1) : $null
                growthPerHour = $slopes.Smallest
                growthWholeWindowPerHour = $slopes.Whole
                growthFirstHalfPerHour = $slopes.First
                growthSecondHalfPerHour = $slopes.Second
                residentGrowthPerHour = Get-GrowthMbPerHour $samples 'Resident'
            }
            cpuPercent = if ($samples.Count -ge 2 -and $samples[-1].T -gt $samples[0].T) { [Math]::Round(100 * ($samples[-1].Cpu - $samples[0].Cpu) / ($samples[-1].T - $samples[0].T), 1) } else { $null }
            metrics = $metrics
            unparsedMetrics = $parsed.Unparsed
            fails = $fails
            log = $p.Log
        }
        $report += $entry
        if ($exited.ContainsKey($p.Name)) { $problems += "$($p.Name) exited with $($exited[$p.Name]) after about $ranFor s" }
        if (-not $ready) { $problems += "$($p.Name) never printed [soak] ready" }
        foreach ($f in $fails) { $problems += "$($p.Name): $f" }
        $errors += @(Select-GodotErrors $lines | ForEach-Object { "$($p.Name): $_" })
        $errorDetails += @(Get-GodotErrorDetails $lines | ForEach-Object { $_.Text = "$($p.Name): $($_.Text)"; $_ })
    }
    $server = $report[0]
    $clientsReport = @($report | Select-Object -Skip 1)
    $summary = [ordered]@{
        clients = $Clients; seconds = $ranFor; port = $port
        server = $server
        clientMemoryMb = [ordered]@{
            average = $clientsReport ? [Math]::Round((@($clientsReport | ForEach-Object { $_.memoryMb.end } | Where-Object { $null -ne $_ }) | Measure-Object -Average).Average, 1) : $null
        }
        processes = $report
    }
    $growthWarnings = @(foreach ($r in $report) {
        $text = Get-SoakGrowthWarning $r.name ([pscustomobject]@{ Smallest = $r.memoryMb.growthPerHour; Whole = $r.memoryMb.growthWholeWindowPerHour; Second = $r.memoryMb.growthSecondHalfPerHour }) $MaxGrowthMbPerHour
        if ($text) { [ordered]@{ process = $r.name; message = $text } }
    })
    # A run cut short (a crash, a stop) can still end with fewer than 3 samples; then growth reads 0 and gates nothing.
    if ($MaxGrowthMbPerHour -gt 0 -and $procs[0].Samples.Count -lt 3) {
        $growthWarnings += [ordered]@{ process = $server.name; message = "too few samples to measure growth: $($procs[0].Samples.Count) of the 3 needed, so growthPerHour is 0 and -MaxGrowthMbPerHour checked nothing" }
    }
    $summary['warnings'] = $growthWarnings
    $summary['stop'] = $stop
    if ($stop -and -not $stop.clean) {
        $how = if ($null -eq $stop.exitCode) { "it was still running after $StopGraceSeconds s and was killed" } elseif ($stop.exitCode -eq 143) { 'it died at once with 143, so the game has no handler' } else { "it exited with $($stop.exitCode)" }
        Write-CiLog "The server did not stop cleanly on SIGTERM: $how. A deploy or scale-down would end its matches mid-play and lose what was not saved; servers shows the handler."
    }
    if ($JunkPps -gt 0) {
        $sent = if ($flood -and (Test-Path -LiteralPath $flood.CountFile)) { [long](Get-Content -LiteralPath $flood.CountFile -Raw).Trim() } else { 0 }
        $summary['junk'] = [ordered]@{ pps = $JunkPps; packetsSent = $sent }
        Write-CiLog ("Junk flood: {0} pps requested, {1:N0} packets sent to 127.0.0.1:{2}" -f $JunkPps, $sent, $port)
    }
    $summary | ConvertTo-Json -Depth 8 | Set-Content -LiteralPath (Join-Path $ResultsDir 'soak.json') -Encoding utf8
    Set-JsonField soak $summary

    Write-CiLog ("Ran {0} s: server {1} MB ({2:+0.0;-0.0} MB/h, {3}% CPU), clients {4} MB each on average" -f
        $ranFor, $server.memoryMb.end, $server.memoryMb.growthPerHour, $server.cpuPercent, $summary.clientMemoryMb.average)
    foreach ($w in $growthWarnings) { Write-CiLog "WARNING: $($w.message)" }
    foreach ($m in $server.metrics.GetEnumerator()) { Write-CiLog "  server $($m.Key): $($m.Value)" }

    # engineErrors[] (and the error keys in the history line) when a process crashed as much as when it only logged errors.
    if ($errorDetails) { Set-EngineErrors $errorDetails }
    if ($problems) { Stop-GodotCi "Soak failed: $(($problems | Select-Object -First 10) -join '; ')" 'soak-failed' }
    if ($RequireCleanStop -and $stop -and -not $stop.clean) {
        Stop-GodotCi "The server did not quit with 0 within $StopGraceSeconds s of SIGTERM (exit code $($stop.exitCode))" 'soak-unclean-stop'
    }
    if ($errors) {
        Stop-GodotCi "Soak: $($errors.Count) engine error(s), first: $($errors[0])" 'engine-errors'
    }
    $leaks = @($report | Where-Object { $_.memoryMb.growthPerHour -gt $MaxGrowthMbPerHour })
    if ($MaxGrowthMbPerHour -gt 0 -and $leaks) {
        Stop-GodotCi "Memory keeps growing: $(($leaks | ForEach-Object { "$($_.name) +$($_.memoryMb.growthPerHour) MB/h (all resident memory +$($_.memoryMb.residentGrowthPerHour) MB/h)" }) -join ', ') (limit $MaxGrowthMbPerHour MB/h)" 'soak-leak'
    }
}
