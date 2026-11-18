# The interchangeable test runners. Each writes JUnit or TRX into its own results folder and is then
# summarised the same way (Write-TestSummary).
#
#   dotnet     dotnet test on the solution: xUnit, NUnit, MSTest and any gdUnit4Net suites in it
#   gdunit4    gdUnit4Net only, on the Godot project's csproj; [RequireGodotRuntime] tests run in headless Godot
#   godottest  Chickensoft GoDotTest: the game runs its own suites from a runner scene
#   gut        GUT (GDScript): .gutconfig.json if present, else test_*.gd next to any GutTest script
#   smoke      plays the main scene for N frames and fails on any engine or script error
#   validate   loads every script, scene and resource and instantiates every scene (tools/validate.gd)
#   architecture  a static scan of the scripts for structural problems (lib/Architecture.ps1); warnings unless configured
#   juice      a bot run that checks each gameplay event got its feedback in time (lib/Juice.ps1, juice.json)
#   playthrough  the game's bot plays to the ending; fails unless every milestone line is logged, in order
#              (lib/Playthrough.ps1, playthrough.json)
#   l10n       translation tables: duplicate, untranslated, missing and too long keys; translation remaps and localized
#              sounds against their source, with ffmpeg (lib/Localization.ps1); every character of every translation
#              against the project's fonts, in headless Godot (tools/glyphs.gd)
#   data       data tables against data.json: ids, fields, types, ranges, references (lib/Data.ps1); no Godot needed
#   textsize   text sizes in real pixels on a small screen such as the Steam Deck's (lib/TextSize.ps1, textsize.json)
#   layout     screens on phones, a tablet and an ultrawide: off screen, notch, touch target size (lib/Layout.ps1, layout.json)
#   placement  where levels put AI points, interactables, zip lines and landmarks, against limits read from the game's
#              script constants (lib/Placement.ps1, placement.json, templates/placement_check.gd)
#
# -Filter means: dotnet/gdunit4 `dotnet test --filter`; godottest suite name; gut test name.

# gdUnit4Net reads GODOT_BIN and the Godot arguments from here; other frameworks ignore the GdUnit4
# section. No TreatNoTestsAsError: with a filter, projects without a match would fail the run, and
# Write-TestSummary already fails runs that report nothing. CompileProcessTimeout: gdUnit4Net rebuilds the project in
# the editor before running, and its 20 s default runs out on a loaded machine or a cold Windows runner; the kit
# then runs no Godot test and only the exit code says so. TempDir, when given, is the test host's TMPDIR (New-DotnetTempDir).
# FixedFps above 0 adds --fixed-fps to the Godot gdUnit4Net starts: each frame is then 1/FixedFps s of game time, run as fast
# as the CPU allows, so a test that waits for physics ticks no longer waits for the wall clock (test -FixedFps).
function New-RunSettings([string]$ResultsDir, [string]$TempDir, [int]$FixedFps = 0) {
    $path = Join-Path $ResultsDir 'godot.runsettings'
    Set-Content -LiteralPath $path -Encoding utf8 -Value @"
<?xml version="1.0" encoding="utf-8"?>
<RunSettings>
  <RunConfiguration>
    <MaxCpuCount>1</MaxCpuCount>
    <TestSessionTimeout>1800000</TestSessionTimeout>
    <EnvironmentVariables>
      <GODOT_BIN>$([System.Security.SecurityElement]::Escape($env:GODOT_BIN))</GODOT_BIN>$(if ($TempDir) { "`n      <TMPDIR>$([System.Security.SecurityElement]::Escape($TempDir))</TMPDIR>" })
    </EnvironmentVariables>
  </RunConfiguration>
  <GdUnit4>
    <Parameters>--headless$(if ($FixedFps -gt 0) { " --fixed-fps $FixedFps" })</Parameters>
    <DisplayName>FullyQualifiedName</DisplayName>
    <CaptureStdOut>true</CaptureStdOut>
    <CompileProcessTimeout>180000</CompileProcessTimeout>
  </GdUnit4>
</RunSettings>
"@
    return $path
}

# gdUnit4Net's adapter talks to the Godot it starts over a pipe with a fixed name, gdunit4-message-pipe. On Linux and
# macOS .NET makes that pipe a socket in the temp folder (TMPDIR/CoreFxPipe_gdunit4-message-pipe), so two test runs that
# share TMPDIR share the socket: the second run's Godot replaces the first's, both adapters reach the second Godot, and
# the first run reports "gdUnit4 found N tests but ran 0" although its tests were fine. Each dotnet test therefore gets a
# temp folder of its own, given to the test host (and through it to Godot) by the run settings. A socket path holds at
# most 103 characters on macOS (107 on Linux), so under a long TMPDIR the folder goes in /tmp. Windows names its pipes
# globally, not in a folder: there it returns nothing and the run keeps the inherited temp folder.
function New-DotnetTempDir {
    if ($IsWindows) { return $null }
    $name = "hd-$([guid]::NewGuid().ToString('N').Substring(0, 8))"
    $dir = Join-Path ([System.IO.Path]::GetTempPath()) $name
    if ("$dir/CoreFxPipe_gdunit4-message-pipe".Length -gt 103) { $dir = Join-Path '/tmp' $name }
    New-Item -ItemType Directory -Force -Path $dir | Out-Null
    return $dir
}

function Invoke-DotnetTest([string]$Target, [string]$ResultsDir, [string]$Filter, [bool]$Coverage, [string]$Prefix, [int]$FixedFps = 0) {
    $temp = New-DotnetTempDir
    try {
        $arguments = @('test', $Target, '--settings', (New-RunSettings $ResultsDir $temp $FixedFps), '--results-directory', $ResultsDir,
            '--logger', "trx;LogFilePrefix=$Prefix")
        if ($Filter) { $arguments += '--filter', $Filter }
        if ($Coverage) { $arguments += '--collect', 'XPlat Code Coverage' }
        Start-LogGroup "dotnet test $Target"
        # The output is kept in the results folder: a build that cannot write its dll leaves no test result, and the report names the locked file from it.
        $code = Invoke-Logged dotnet $arguments (Join-Path $ResultsDir "$Prefix.log")
        Stop-LogGroup
        return $code
    } finally {
        if ($temp) { Remove-Item -LiteralPath $temp -Recurse -Force -ErrorAction SilentlyContinue }
    }
}

# One case per file from tools/validate.gd's markers; errors printed between a file's markers fail it. With $EngineErrors (a list), the
# errors Godot's own C# bindings log (see EngineInternalPattern) do not fail the file that was running: they are added to the list as
# @{ where = <the file, or $null outside every file>; text = <the error line> }, to be reported as warnings. A file fails on its own end marker
# (anything but ok) or on an error of its own printed between its markers.
function ConvertFrom-ValidateLog([string]$LogFile, [string]$Marker = 'validate', [System.Collections.Generic.List[object]]$EngineErrors = $null) {
    $cases = @(); $current = $null; $buffer = @(); $outside = @(); $since = @()
    # The project's own errors among some lines; the engine's are noted in $EngineErrors against $where.
    $select = {
        param([string[]]$Lines, $where)
        if ($null -eq $EngineErrors) { return @(Select-GodotErrors $Lines) }
        $split = Split-GodotErrors $Lines
        foreach ($text in $split.Engine) { $EngineErrors.Add([ordered]@{ where = $where; text = $text.Trim() }) }
        return @($split.Own)
    }
    $lines = @(Get-Content -LiteralPath $LogFile | ForEach-Object { $_ -replace "`e\[[0-9;]*m", '' })
    # Godot 4.5+: validate.gd's logger prints each file's errors on stdout before its end marker ("@@validate error").
    # stderr reaches the log out of order with stdout, so its lines between a file's markers may be another file's: then
    # only the logger's lines are the file's, and stderr counts as outside any file.
    $logged = @($lines | Where-Object { $_.StartsWith("@@$Marker error ") }).Count -gt 0
    foreach ($line in $lines) {
        # What follows the runner's "done" line is the engine shutting down (a crash there is not a verdict on any file).
        if ($line -match "^@@$Marker done\b") { break }
        if ($line -match "^@@$Marker begin (?<path>.+)`$") {
            $current = $Matches.path; $buffer = @(); $since = @()
        } elseif ($current -and $line.StartsWith("@@$Marker end $current ")) {
            # Matched by the known path rather than a regex: paths may contain spaces.
            $status = $line.Substring("@@$Marker end $current ".Length)
            $problems = @(& $select $buffer $current)
            if ($status -ne 'ok') { $problems = @($status) + $problems }
            $cases += @{ Name = $current; Failure = ($problems -join "`n") }
            $current = $null
        } elseif ($current) {
            $since += $line
            if ($line.StartsWith("@@$Marker error ")) { $buffer += $line.Substring("@@$Marker error ".Length) }
            elseif ($logged) { $outside += $line }
            else { $buffer += $line }
        } else {
            $outside += $line
        }
    }
    # A file whose end marker never came stopped Godot (a crash, OS.crash, a time-out): it fails, with what was printed
    # after its begin marker, rather than being left out.
    if ($current) {
        $crash = @($since | Where-Object { $_ -match 'Program crashed with signal|was still running after' } | ForEach-Object { $_.Trim() })
        $cases += @{ Name = $current; Failure = (@("Godot stopped while checking this file") + $crash + @(& $select $since $current)) -join "`n" }
    }
    # Errors outside any file (before the first: autoloads, project settings; with the logger, all of stderr) belong to the
    # project as a whole, unless a file already reported the same error (stderr can reach the log away from its file's markers).
    $reported = ($cases | ForEach-Object { $_.Failure }) -join "`n"
    $startup = @(& $select $outside $null | Where-Object { -not $reported.Contains(($_ -replace '^\s*(SHADER ERROR|SCRIPT ERROR|ERROR):\s*', '').Trim()) })
    # An error's "at: _ready (res://addons/x/y.gd:20)" line follows it: keep it, so the failure names its file and line.
    $startup = @(foreach ($text in $startup) {
        $text
        $index = [array]::IndexOf($outside, $text)
        if ($index -ge 0 -and $index + 1 -lt $outside.Count -and $outside[$index + 1] -match '^\s*at: ') { $outside[$index + 1].Trim() }
    })
    if ($startup.Count -gt 0) { $cases += @{ Name = 'project startup'; Failure = ($startup -join "`n") } }
    return $cases
}

# What Godot prints at exit about objects nobody freed (4.7.2: `5 ObjectDB instances were leaked at exit`, `1 RID of type "CanvasItem"
# was leaked`, `N resources still in use at exit`): the lines of $Lines that say so, without colour codes. Mono's teardown noise
# ("Leaked unsafe reference") is not one of them.
function Get-ExitLeakLines([string[]]$Lines) {
    return @($Lines | ForEach-Object { ($_ -replace "`e\[[0-9;]*m", '').Trim() } |
        Where-Object { $_ -match '(?i)\bleaked at exit\b|\bRIDs? (?:allocations )?of type .+ (?:was|were) leaked\b|resources? still in use at exit' })
}

# The exit code of a runner that prints `@@<marker> done` when it has judged everything (validate, flows): a crash after that line, with
# every case ok, is the engine's shutdown (Get-ShutdownCrashVerdict) and becomes a warning in $EngineErrors; anything else keeps its failure.
# A leak Godot reports at exit (Get-ExitLeakLines) belongs to no single case: it is always a warning, named with the last case that ran,
# and when the exit code fails the runner it is also part of that failure, so a failed runner never comes without a reason.
function Get-RunnerExitVerdict([int]$Code, [string]$LogFile, [string]$Marker, [object[]]$Cases, $EngineErrors, [string]$What) {
    $lines = @(Get-Content -LiteralPath $LogFile)
    $done = @($lines | Where-Object { $_ -match "^@@$Marker done\b" }).Count -gt 0
    $judgedAll = $done -and @($Cases | Where-Object { $_.Failure }).Count -eq 0
    $verdict = Get-ShutdownCrashVerdict $Code $lines $judgedAll @() $What
    if ($verdict.Warning) {
        Write-CiLog "WARN: $($verdict.Warning)"
        $EngineErrors.Add([ordered]@{ where = $null; text = $verdict.Warning })
    }
    $leaks = @(Get-ExitLeakLines $lines)
    if ($leaks.Count -gt 0) {
        $begun = @($lines | ForEach-Object { if ($_ -match "^@@$Marker begin (?<path>.+)`$") { $Matches.path } })
        $last = if ($begun.Count -gt 0) { $begun[-1] } else { $null }
        $text = "Godot reported a leak at exit$(if ($last) { " (the last $What to run: $last; any $What may have caused it)" }): $($leaks -join '; ')"
        Write-CiLog "WARN: $text"
        $EngineErrors.Add([ordered]@{ where = $last; text = $text; rule = 'exit-leak' })
        if ($verdict.Failure) { $verdict.Failure = "$($verdict.Failure); at exit: $($leaks -join '; ')" }
    }
    return $verdict
}

# The errors Godot's own C# bindings logged while a runner ran (ConvertFrom-ValidateLog's $EngineErrors): they fail nothing, so they go to
# findings.json as warnings (rule engine-internal-error; runnerResults[].warnings, and the pull request comment) with the file that was running.
function Write-EngineErrorFindings($EngineErrors, [string]$Runner, [string]$ResultsDir) {
    if ($EngineErrors.Count -eq 0) { return }
    # An entry may name its rule (exit-leak); the rest are engine-internal-error.
    $findings = @($EngineErrors | ForEach-Object { [ordered]@{ rule = ($_.Contains('rule') ? $_['rule'] : 'engine-internal-error'); severity = 'warning'; file = $_.where; line = $null; message = $_.text } })
    ConvertTo-Json -InputObject $findings -Depth 4 | Set-Content -LiteralPath (Join-Path $ResultsDir 'findings.json') -Encoding utf8
    $internal = @($EngineErrors | Where-Object { -not $_.Contains('rule') })
    if ($internal.Count -eq 0) { return }
    $where = @($internal | Group-Object { $_.where ? $_.where : 'outside every file' } | ForEach-Object { "$($_.Name) x$($_.Count)" })
    Write-CiLog "${Runner}: Godot's own C# bindings logged $($internal.Count) error(s) ($($where -join ', ')): warnings, not failures (godotengine/godot#124587); $(Format-KitCommand 'test') again, or load every C# resource through a cache"
}

# GUT skips a test script that does not load (a parse error) with a warning, "Ignoring script ... because it does not
# extend GutTest", and the run still passes. Such a script fails as a case named after the file, with its parse error when
# the log has one: one that extends GutTest on disk, or that the log says failed to load (it may extend another test).
function Get-GutLoadFailures([string]$LogFile, [string]$ProjectDir) {
    $lines = @(Get-Content -LiteralPath $LogFile | ForEach-Object { $_ -replace "`e\[[0-9;]*m", '' })
    $seen = @{}
    foreach ($line in $lines) {
        if ($line -notmatch 'Ignoring script (?<res>res://.+?) because it does not extend GutTest') { continue }
        $res = $Matches.res
        if ($seen.ContainsKey($res)) { continue }
        $seen[$res] = $true
        $why = @(for ($i = 0; $i -lt $lines.Count - 1; $i++) {
            if ($lines[$i] -match '^\s*SCRIPT ERROR:' -and $lines[$i + 1].Contains("($res`:")) { "$($lines[$i].Trim()) $($lines[$i + 1].Trim())" }
        })
        $failedToLoad = @($lines | Where-Object { $_.Contains("Failed to load script `"$res`"") }).Count -gt 0
        $file = Join-Path $ProjectDir $res.Substring(6)
        $isTest = (Test-Path -LiteralPath $file) -and (Get-Content -LiteralPath $file -Raw) -match '(?m)^extends\s+GutTest\b'
        if (-not ($isTest -or $failedToLoad -or $why)) { continue }
        @{ Name = $res; Failure = (@("$res does not load, so GUT skipped its tests") + $why) -join "`n" }
    }
}

# The game's physics tick rate (project.godot physics/common/physics_ticks_per_second; Godot's default 60).
function Get-PhysicsTickRate([string]$ProjectDir) {
    $file = Join-Path $ProjectDir 'project.godot'
    if (-not (Test-Path -LiteralPath $file)) { return 60 }
    $section = ''
    foreach ($line in @(Get-Content -LiteralPath $file)) {
        if ($line -match '^\s*\[(?<s>[^\]]+)\]\s*$') { $section = $Matches.s; continue }
        if ($section -eq 'physics' -and $line -match '^\s*common/physics_ticks_per_second\s*=\s*(?<n>\d+)\s*$') { return [int]$Matches.n }
    }
    return 60
}

# test -FixedFps against the game's tick rate: at another rate a rendered frame is not one physics tick, so tests that wait
# for frames and tests that wait for ticks no longer see the same time. Returns a warning, or $null when they match.
function Get-FixedFpsWarning([string]$ProjectDir, [int]$FixedFps) {
    if ($FixedFps -le 0) { return $null }
    $ticks = Get-PhysicsTickRate $ProjectDir
    if ($ticks -eq $FixedFps) { return $null }
    return "-FixedFps $FixedFps differs from the game's physics tick rate ($ticks per second, project.godot physics/common/physics_ticks_per_second): each frame runs $([math]::Round($ticks / $FixedFps, 2)) physics ticks, so tests that wait for frames and tests that wait for ticks see different times. Use -FixedFps $ticks"
}

function Invoke-TestRunner {
    param([string]$Runner, $Info, [string]$ResultsDir, [string]$Filter, [bool]$Coverage, [int]$Frames, [string[]]$GameArgs, [int]$FixedFps = 0)

    if (Test-Path -LiteralPath $ResultsDir) { Remove-Item -LiteralPath $ResultsDir -Recurse -Force }
    New-Item -ItemType Directory -Force $ResultsDir | Out-Null
    $godot = $env:GODOT_BIN
    $project = $Info.ProjectDir
    $code = 0

    switch ($Runner) {
        'dotnet' {
            if (-not $Info.Solution) { Stop-GodotCi "dotnet runner: no .sln/.csproj found (pass -Solution)" }
            $code = Invoke-DotnetTest $Info.Solution $ResultsDir $Filter $Coverage 'dotnet' $FixedFps
        }
        'gdunit4' {
            $csproj = if ($Info.Solution -like '*.csproj') { $Info.Solution } else {
                (Get-ChildItem -LiteralPath $project -File -Filter '*.csproj' | Select-Object -First 1).FullName }
            if (-not $csproj) { Stop-GodotCi "gdunit4 runner: no .csproj in $project" }
            if ((Get-Content -LiteralPath $csproj -Raw) -notmatch 'gdUnit4\.test\.adapter') {
                Stop-GodotCi "gdunit4 runner: $csproj does not reference gdUnit4.test.adapter"
            }
            $code = Invoke-DotnetTest $csproj $ResultsDir $Filter $Coverage 'gdunit4' $FixedFps
        }
        'godottest' {
            $log = Join-Path $ResultsDir 'godottest.log'
            $sceneArgs = if ($Info.GoDotTestScene) { @($Info.GoDotTestScene) } else { @() }
            $testArgs = @('--headless', '--path', $project) + $sceneArgs + @("--run-tests$(if ($Filter) { "=$Filter" })", '--quit-on-finish')
            Start-LogGroup "GoDotTest $($Info.GoDotTestScene)"
            if ($Coverage) {
                # The editor runs the Debug build; an ExportRelease folder left by an export must not be used.
                $bin = Join-Path $project '.godot/mono/temp/bin/Debug'
                if (-not (Test-Path -LiteralPath $bin)) { Stop-GodotCi "godottest: no Debug build in $bin" }
                $coverlet = Get-DotnetTool 'coverlet.console' 'coverlet'
                New-Item -ItemType Directory -Force (Join-Path $ResultsDir 'coverage') | Out-Null
                # coverlet hands --targetargs to Godot as one string, so quote the path.
                $targetArgs = (($testArgs + '--coverage') | ForEach-Object { if ($_ -match '\s') { """$_""" } else { $_ } }) -join ' '
                $code = Invoke-Logged $coverlet @($bin, '--target', $godot, '--targetargs', $targetArgs,
                    '--format', 'cobertura', '--output', (Join-Path $ResultsDir 'coverage/godottest.cobertura.xml'),
                    '--exclude-by-file', '**/test/**/*.cs', '--exclude-assemblies-without-sources', 'MissingAll') $log
            } else {
                $code = Invoke-Logged $godot $testArgs $log
            }
            Stop-LogGroup
            ConvertFrom-GoDotTestLog $log (Join-Path $ResultsDir 'godottest.junit.xml')
        }
        'gut' {
            if (-not (Test-Path -LiteralPath (Join-Path $project 'addons/gut/gut_cmdln.gd'))) {
                Stop-GodotCi "gut runner: addons/gut is missing"
            }
            $gutArgs = @('--headless', '--path', $project, '-s', 'addons/gut/gut_cmdln.gd', '-gexit', '-gdisable_colors',
                "-gjunit_xml_file=$(Join-Path $ResultsDir 'gut.junit.xml')")
            if (-not (Test-Path -LiteralPath (Join-Path $project '.gutconfig.json'))) {
                # Search every folder that holds a script extending GutTest.
                Get-GutTestFiles $project | ForEach-Object { ConvertTo-ResPath $project $_.DirectoryName } |
                    Sort-Object -Unique | ForEach-Object { $gutArgs += "-gdir=$_" }
            }
            if ($Filter) { $gutArgs += "-gunit_test_name=$Filter" }
            Start-LogGroup 'GUT'
            $code = Invoke-Logged $godot $gutArgs (Join-Path $ResultsDir 'gut.log')
            Stop-LogGroup
            $unloaded = @(Get-GutLoadFailures (Join-Path $ResultsDir 'gut.log') $project)
            if ($unloaded.Count -gt 0) { Write-JUnitCases (Join-Path $ResultsDir 'gut-load.junit.xml') 'gut' $unloaded }
        }
        'validate' {
            $log = Join-Path $ResultsDir 'validate.log'
            $tool = (Resolve-Path -LiteralPath (Join-Path $PSScriptRoot '../tools/validate.gd')).Path -replace '\\', '/'
            Start-LogGroup 'Validate scripts, scenes and resources'
            $code = Invoke-Logged $godot @('--headless', '--path', $project, '-s', $tool) $log
            Stop-LogGroup
            $engineErrors = [System.Collections.Generic.List[object]]::new()
            $cases = @(ConvertFrom-ValidateLog $log 'validate' $engineErrors)
            $verdict = Get-RunnerExitVerdict $code $log 'validate' $cases $engineErrors 'file'
            if ($verdict.Failure) { $cases += @{ Name = 'validate'; Failure = $verdict.Failure } }
            Write-EngineErrorFindings $engineErrors 'validate' $ResultsDir
            Write-JUnitCases (Join-Path $ResultsDir 'validate.junit.xml') 'validate' $cases
        }
        'flows' {
            $log = Join-Path $ResultsDir 'flows.log'
            $tool = (Resolve-Path -LiteralPath (Join-Path $PSScriptRoot '../tools/flows.gd')).Path -replace '\\', '/'
            Start-LogGroup 'UI flows'
            # A throwaway user:// folder (Linux: XDG_DATA_HOME, Windows: APPDATA; macOS keeps its own): a setting saved by whoever ran the flows
            # last (a camera-sway toggle once turned menu_navigation red on one machine) must not reach them, and what they save is not left behind.
            $userHome = Join-Path ([System.IO.Path]::GetTempPath()) "hyperdot-user-$([guid]::NewGuid().ToString('N').Substring(0, 8))"
            $savedData = $env:XDG_DATA_HOME; $savedAppData = $env:APPDATA
            try {
                New-Item -ItemType Directory -Force $userHome | Out-Null
                if ($IsWindows) { $env:APPDATA = $userHome } elseif (-not $IsMacOS) { $env:XDG_DATA_HOME = $userHome }
                $attempt = 0
                do {
                    $attempt++
                    $code = Invoke-Logged $godot @('--headless', '--path', $project, '-s', $tool, '--', $Filter) $log
                    # A crash before the "done" line may be the engine's, not a flow's: the flows are run once more, and a second crash fails.
                    $again = (Test-GodotCrashCode $code) -and -not (Select-String -LiteralPath $log -Pattern '^@@flow done\b' -Quiet) -and $attempt -lt 2
                    if ($again) { Write-CiLog "Godot crashed during the flows (exit $code) before the last one ended; running them once more" }
                } while ($again)
            } finally {
                $env:XDG_DATA_HOME = $savedData; $env:APPDATA = $savedAppData
                Remove-Item -LiteralPath $userHome -Recurse -Force -ErrorAction SilentlyContinue
            }
            Stop-LogGroup
            # A flow fails on its own end line or on an error of its own between its markers; the engine's own errors are warnings.
            $engineErrors = [System.Collections.Generic.List[object]]::new()
            $cases = @(ConvertFrom-ValidateLog $log 'flow' $engineErrors)
            $verdict = Get-RunnerExitVerdict $code $log 'flow' $cases $engineErrors 'flow'
            if ($verdict.Failure) { $cases += @{ Name = 'flows'; Failure = $verdict.Failure } }
            Write-EngineErrorFindings $engineErrors 'flows' $ResultsDir
            Write-JUnitCases (Join-Path $ResultsDir 'flows.junit.xml') 'flows' $cases
        }
        'juice' {
            $code = Invoke-JuiceRunner $Info $ResultsDir $GameArgs
        }
        'playthrough' {
            $code = Invoke-PlaythroughRunner $Info $ResultsDir $GameArgs
        }
        'architecture' {
            $code = Invoke-ArchitectureRunner $project $ResultsDir
        }
        'l10n' {
            $code = Invoke-LocalizationRunner $project $ResultsDir
        }
        'data' {
            $code = Invoke-DataRunner $project $ResultsDir
        }
        'layout' {
            $code = Invoke-LayoutRunner $Info $ResultsDir
        }
        'textsize' {
            $code = Invoke-TextSizeRunner $Info $ResultsDir
        }
        'placement' {
            $code = Invoke-PlacementRunner $Info $ResultsDir
        }
        'smoke' {
            $log = Join-Path $ResultsDir 'smoke.log'
            Start-LogGroup "Smoke run ($Frames frames$(if ($FixedFps -gt 0) { " at a fixed $FixedFps fps" }))"
            $smokeArgs = @('--headless', '--path', $project, '--quit-after', "$Frames") + $(if ($FixedFps -gt 0) { @('--fixed-fps', "$FixedFps") }) + $(if ($GameArgs) { @('--') + $GameArgs })
            $code = Invoke-Logged $godot $smokeArgs $log
            Stop-LogGroup
            $errors = @(Get-GodotLogErrors $log)
            $message = if ($code -ne 0) { "Godot exited with $code" }
                elseif ($errors.Count -gt 0) { $errors -join "`n" }
                else { "Main scene ran $Frames frames without errors" }
            if ($errors.Count -gt 0 -and $code -eq 0) { $code = 1 }
            Write-SingleCaseJUnit (Join-Path $ResultsDir 'smoke.junit.xml') 'smoke' ($code -eq 0) $message
        }
    }

    # dotnet's coverage collector writes into per-run GUID folders; gather it in one place.
    if ($Coverage) {
        $coverageDir = Join-Path $ResultsDir 'coverage'
        New-Item -ItemType Directory -Force $coverageDir | Out-Null
        # Matched below the results folder only, as in Write-TestSummary.
        $base = (Get-Item -LiteralPath $ResultsDir).FullName.TrimEnd('\', '/').Length
        Get-ChildItem -LiteralPath $ResultsDir -Recurse -File -Filter 'coverage.cobertura.xml' |
            Where-Object { $_.FullName.Substring($base) -notmatch '[\\/](coverage|In)[\\/]' } |
            ForEach-Object { Move-Item -LiteralPath $_.FullName (Join-Path $coverageDir "$Runner-$($_.Directory.Name).cobertura.xml") }
    }

    $summary = Write-TestSummary $Runner $ResultsDir $code ([bool]$Filter)
    $findings = Join-Path $ResultsDir 'findings.json'
    $warnings = @(if (Test-Path -LiteralPath $findings) {
        Get-Content -LiteralPath $findings -Raw | ConvertFrom-Json | Where-Object { $_ -and $_.severity -eq 'warning' }
    })
    $summary | Add-Member -NotePropertyName Warnings -NotePropertyValue $warnings
    # The l10n runner's glyph check, per locale and font, for -Json (runnerResults[].glyphs).
    $glyphs = Join-Path $ResultsDir 'glyphs.json'
    if ($Runner -eq 'l10n' -and (Test-Path -LiteralPath $glyphs)) {
        $summary | Add-Member -NotePropertyName Glyphs -NotePropertyValue (Get-Content -LiteralPath $glyphs -Raw | ConvertFrom-Json)
    }
    return $summary
}

# Invoke-TestRunner with test -Retry and quarantine.json. A runner that still fails after its quarantined tests are set
# aside is run again, whole and with the same -Filter, up to $Retry more times, until an attempt passes; each failed
# attempt's results are kept next to the last one as <runner>.attempt<N>. The result is the last attempt's, plus Attempts
# and Flaky: the tests that failed in an earlier attempt but not in the last, which the run reports and records, so a pass
# on a retry is never a silent green. The whole runner is rerun because not every framework's filter can name a list of
# tests, and the run's own -Filter must still apply.
function Invoke-TestRunnerWithRetry {
    param([string]$Runner, $Info, [string]$ResultsDir, [string]$Filter, [bool]$Coverage, [int]$Frames, [string[]]$GameArgs,
        [int]$Retry = 0, [object[]]$Quarantine = @(), [int]$FixedFps = 0)

    $attempts = [System.Collections.Generic.List[object]]::new()
    while ($true) {
        $result = Invoke-TestRunner -Runner $Runner -Info $Info -ResultsDir $ResultsDir -Filter $Filter -Coverage $Coverage -Frames $Frames -GameArgs $GameArgs -FixedFps $FixedFps
        $result = Set-RunQuarantine $result $Quarantine
        $attempts.Add($result)
        if ($result.Ok -or $attempts.Count -gt $Retry) { break }
        $kept = "$ResultsDir.attempt$($attempts.Count)"
        if (Test-Path -LiteralPath $kept) { Remove-Item -LiteralPath $kept -Recurse -Force }
        Move-Item -LiteralPath $ResultsDir -Destination $kept
        Write-CiLog "$Runner failed on attempt $($attempts.Count) of $($Retry + 1); running it again (-Retry $Retry). That attempt's results: $kept"
    }
    $flaky = @(Get-FlakyTests $attempts.ToArray())
    foreach ($f in $flaky) { Write-CiLog "FLAKY ${Runner}: $($f.Name) failed on attempt $($f.FailedAttempt) and passed on attempt $($attempts.Count)$(if ($f.Message) { " ($($f.Message))" })" }
    foreach ($q in $result.Quarantined) { Write-CiLog "QUARANTINED ${Runner}: $($q.Name) failed; not counted until $($q.Until) (owner $($q.Owner))" }
    $result | Add-Member -Force -NotePropertyName Attempts -NotePropertyValue $attempts.Count
    $result | Add-Member -Force -NotePropertyName Flaky -NotePropertyValue $flaky
    return $result
}
