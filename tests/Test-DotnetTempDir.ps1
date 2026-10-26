#!/usr/bin/env pwsh
# Self-test of the dotnet runner's own temp folder. gdUnit4Net's adapter reaches the Godot it starts over a pipe with a
# fixed name, which .NET on Linux and macOS makes a socket in TMPDIR; two runs that shared TMPDIR shared that socket, and
# one of them reported "gdUnit4 found N tests but ran 0" although its tests were fine. Two Invoke-DotnetTest runs at
# once, with one TMPDIR, against a stand-in dotnet: it gives itself the run settings' environment as the test host
# does, starts a stand-in Godot serving that pipe, waits for the other run's, then connects and records which run
# answered. Each run must reach its own; a TMPDIR too long for a socket path must still work; the per-run folders must
# go when the runs end. pwsh stands in for dotnet and Godot, so this needs neither. Windows names pipes globally, not in
# a folder: there it passes with a note.
Set-StrictMode -Version 3.0
$ErrorActionPreference = 'Stop'
$root = Split-Path $PSScriptRoot
if ($IsWindows) {
    Write-Host 'Windows names its pipes globally rather than in the temp folder; nothing to check here'
    exit 0
}

$pwshPath = (Get-Process -Id $PID).Path
$dir = Join-Path ([IO.Path]::GetTempPath()) "dotnet-tmp-$PID"
$bin = Join-Path $dir 'bin'
New-Item -ItemType Directory -Force -Path $bin | Out-Null
$failures = @()

# The stand-in Godot: serves gdunit4-message-pipe as GdUnit4TestRunnerScene does, answers the first client with its
# run's name, and gives up after 20 s.
$server = Join-Path $dir 'server.ps1'
Set-Content -LiteralPath $server -Encoding utf8 -Value @'
param([string]$Name, [string]$Ready)
$pipe = [System.IO.Pipes.NamedPipeServerStream]::new('gdunit4-message-pipe', 'InOut', 1, 'Byte', 'Asynchronous')
Set-Content -LiteralPath $Ready -Value ([System.IO.Path]::GetTempPath())
if (-not $pipe.WaitForConnectionAsync().Wait(20000)) { exit 1 }
$writer = [System.IO.StreamWriter]::new($pipe)
$writer.WriteLine($Name); $writer.Flush()
Start-Sleep -Milliseconds 500
'@

# The stand-in test host: starts the stand-in Godot, waits until the other run's is up too (as when two runs overlap),
# then connects as the adapter does and records which run answered.
$testhost = Join-Path $dir 'testhost.ps1'
Set-Content -LiteralPath $testhost -Encoding utf8 -Value @'
param([string]$Name, [string]$Results, [string]$Server)
$ready = Join-Path $Results "server-ready.txt"
$godot = Start-Process -FilePath (Get-Process -Id $PID).Path -ArgumentList @("-NoProfile", "-File", $Server, $Name, $ready) -PassThru
$clock = [Diagnostics.Stopwatch]::StartNew()
while (-not (Test-Path -LiteralPath $ready) -and $clock.ElapsedMilliseconds -lt 20000) { Start-Sleep -Milliseconds 100 }
Set-Content -LiteralPath (Join-Path $env:HYPERDOT_TEST_BARRIER $Name) -Value "up"
while (@(Get-ChildItem -LiteralPath $env:HYPERDOT_TEST_BARRIER).Count -lt 2 -and $clock.ElapsedMilliseconds -lt 30000) { Start-Sleep -Milliseconds 100 }
$answer = try {
    $client = [System.IO.Pipes.NamedPipeClientStream]::new(".", "gdunit4-message-pipe", "InOut")
    $client.Connect(5000)
    [System.IO.StreamReader]::new($client).ReadLine()
} catch { "no answer: $($_.Exception.Message)" }
Set-Content -LiteralPath (Join-Path $Results "answer.txt") -Value $answer
$godot.WaitForExit(25000) | Out-Null
'@

# The stand-in dotnet: `dotnet test <name> --settings <file> --results-directory <dir> ...`. Like vstest it starts the
# test host with the run settings' environment variables (a process's own pipe folder is fixed when it starts).
$dotnet = Join-Path $bin 'dotnet'
Set-Content -LiteralPath $dotnet -Encoding utf8 -Value @"
#!$pwshPath
`$settings = `$args[[array]::IndexOf(`$args, '--settings') + 1]
`$results = `$args[[array]::IndexOf(`$args, '--results-directory') + 1]
[xml]`$doc = Get-Content -LiteralPath `$settings -Raw
foreach (`$var in `$doc.SelectNodes('/RunSettings/RunConfiguration/EnvironmentVariables/*')) {
    [Environment]::SetEnvironmentVariable(`$var.Name, `$var.InnerText)
}
& '$pwshPath' -NoProfile -File '$testhost' `$args[1] `$results '$server'
exit `$LASTEXITCODE
"@
& chmod +x $dotnet

# Two runs at once under one TMPDIR; returns each run's answer and temp folder.
function Invoke-TwoRuns([string]$Label, [string]$SharedTemp) {
    New-Item -ItemType Directory -Force -Path $SharedTemp | Out-Null
    $barrier = Join-Path $dir "barrier-$Label"
    New-Item -ItemType Directory -Force -Path $barrier | Out-Null
    $saved = @{ PATH = $env:PATH; TMPDIR = $env:TMPDIR; HYPERDOT_TEST_BARRIER = $env:HYPERDOT_TEST_BARRIER }
    $env:PATH = "$bin$([IO.Path]::PathSeparator)$env:PATH"
    $env:TMPDIR = $SharedTemp
    $env:HYPERDOT_TEST_BARRIER = $barrier
    try {
        $runs = @(foreach ($name in 'A', 'B') {
            $results = Join-Path $dir "$Label-$name"
            New-Item -ItemType Directory -Force -Path $results | Out-Null
            $command = "foreach (`$lib in 'Common', 'Report', 'Runners') { . (Join-Path '$root' `"ci/godot/lib/`$lib.ps1`") }; " +
                "Start-KitCoverage 'test'; exit (Invoke-DotnetTest '$name' '$results' '' `$false 'dotnet')"
            $process = Start-Process -FilePath $pwshPath -ArgumentList @('-NoProfile', '-Command', $command) -PassThru `
                -RedirectStandardOutput (Join-Path $dir "$Label-$name.out") -RedirectStandardError (Join-Path $dir "$Label-$name.err")
            [pscustomobject]@{ Name = $name; Results = $results; Process = $process }
        })
    } finally {
        foreach ($key in $saved.Keys) { [Environment]::SetEnvironmentVariable($key, $saved[$key]) }
    }
    foreach ($run in $runs) {
        if (-not $run.Process.WaitForExit(90000)) { $run.Process.Kill($true); $script:failures += "${Label}: run $($run.Name) did not finish" }
    }
    return @(foreach ($run in $runs) {
        $answer = Join-Path $run.Results 'answer.txt'
        $ready = Join-Path $run.Results 'server-ready.txt'
        [pscustomobject]@{
            Name = $run.Name
            Answer = if (Test-Path -LiteralPath $answer) { (Get-Content -LiteralPath $answer -Raw).Trim() } else { '(none)' }
            Temp = if (Test-Path -LiteralPath $ready) { (Get-Content -LiteralPath $ready -Raw).Trim().TrimEnd('/') } else { '' }
        }
    })
}

try {
    $cases = @(
        @{ Label = 'shared'; Temp = (Join-Path $dir 'tmp'); What = 'one TMPDIR' }
        # 110 characters before the socket's own name: no socket fits there, so the runs' folders must go elsewhere.
        @{ Label = 'long'; Temp = (Join-Path $dir ('t' * [Math]::Max(1, 110 - $dir.Length))); What = 'one TMPDIR too long for a socket' }
    )
    foreach ($case in $cases) {
        $runs = Invoke-TwoRuns $case.Label $case.Temp
        foreach ($run in $runs) {
            if ($run.Answer -ne $run.Name) {
                $failures += "$($case.What): run $($run.Name) reached $(if ($run.Answer -in 'A', 'B') { "run $($run.Answer)'s Godot" } else { $run.Answer }), not its own"
            }
            if ($run.Temp -and $run.Temp -ne $case.Temp -and (Test-Path -LiteralPath $run.Temp)) { $failures += "$($case.What): run $($run.Name)'s temp folder $($run.Temp) is left behind" }
        }
        $temps = @($runs | ForEach-Object Temp | Where-Object { $_ } | Sort-Object -Unique)
        if ($temps.Count -ne 2) { $failures += "$($case.What): the two runs should have a temp folder each, got $($temps -join ', ')" }
    }
} finally {
    Remove-Item -LiteralPath $dir -Recurse -Force -ErrorAction SilentlyContinue
}

if ($failures) {
    foreach ($failure in $failures) { Write-Host "FAIL $failure" }
    exit 1
}
Write-Host 'Two dotnet test runs at once under one TMPDIR each reach their own Godot, also under a TMPDIR too long for a socket, and leave no temp folder'
exit 0
