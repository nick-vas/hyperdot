# Shared helpers: logging, running native programs, scanning Godot logs.

# All console output goes through here so -Json can send it to stderr and keep stdout for the result.
function Write-Console {
    param([Parameter(Position = 0)][string]$Text = '', [switch]$NoNewline, [System.ConsoleColor]$ForegroundColor)
    Write-RunLog $Text -NoNewline:$NoNewline
    if ($script:JsonMode) {
        if ($NoNewline) { [Console]::Error.Write($Text) } else { [Console]::Error.WriteLine($Text) }
        return
    }
    $arguments = @{ Object = $Text; NoNewline = $NoNewline }
    if ($PSBoundParameters.ContainsKey('ForegroundColor')) { $arguments.ForegroundColor = $ForegroundColor }
    Write-Host @arguments
}

function Write-CiLog([string]$Message) { Write-Console "[hyperdot] $Message" }

# HYPERDOT_COVERAGE names a folder: a run started with it set writes there, one line each the first time, the command,
# every function of the kit it enters and the error code it stops with, so tests/Get-KitCoverage.ps1 can tell what the
# self-tests exercise. A breakpoint on each function's name records the entry; nothing changes when it is not set.
$script:CoverageFile = $null
$script:CoverageSeen = $null
function Start-KitCoverage([string]$Command) {
    if (-not $env:HYPERDOT_COVERAGE) { return }
    New-Item -ItemType Directory -Force -Path $env:HYPERDOT_COVERAGE | Out-Null
    $script:CoverageFile = Join-Path $env:HYPERDOT_COVERAGE "$PID-$([guid]::NewGuid().ToString('N').Substring(0, 8)).txt"
    $script:CoverageSeen = [System.Collections.Generic.HashSet[string]]::new()
    Add-KitCoverage "command:$Command"
    # The self-test that started this run (the nearest tests/Test-*.ps1 among the parent processes) and the CI job, so
    # tests/Get-CoverageMap.ps1 can say which test reaches what.
    $process = Get-Process -Id $PID
    for ($depth = 0; $process -and $depth -lt 8; $depth++) {
        $line = try { $process.CommandLine } catch { $null }
        if ($line -match '(?<t>Test-[\w-]+)\.ps1') { Add-KitCoverage "test:$($Matches.t)"; break }
        $process = try { $process.Parent } catch { $null }
    }
    if ($env:GITHUB_JOB) { Add-KitCoverage "job:$env:GITHUB_JOB" }
    $sources = @(Get-ChildItem -LiteralPath $PSScriptRoot -Filter '*.ps1' -File) + @(Get-Item -LiteralPath (Join-Path (Split-Path $PSScriptRoot) 'hyperdot.ps1'))
    $names = foreach ($source in $sources) {
        $ast = [System.Management.Automation.Language.Parser]::ParseFile($source.FullName, [ref]$null, [ref]$null)
        $ast.FindAll({ param($node) $node -is [System.Management.Automation.Language.FunctionDefinitionAst] }, $true) | ForEach-Object { $_.Name }
    }
    $names = @($names | Where-Object { $_ -notin 'Start-KitCoverage', 'Add-KitCoverage' } | Sort-Object -Unique)
    if ($names.Count) { Set-PSBreakpoint -Command $names -Action { Add-KitCoverage "function:$($_.Command)" } | Out-Null }
}
function Add-KitCoverage([string]$Entry) {
    if ($script:CoverageFile -and $script:CoverageSeen.Add($Entry)) { Add-Content -LiteralPath $script:CoverageFile -Value $Entry }
}

# Commands the kit suggests in its own output, written so they can be pasted as they are: the kit's real path, and
# -Project when the project is not the current folder (the kit usually lives outside the game).
$script:KitScript = $null
$script:KitProject = $null
function Format-KitCommand([string]$Arguments) {
    $path = if ($script:KitScript) { $script:KitScript -replace '\\', '/' } else { 'hyperdot.ps1' }
    if ($path -match '\s') { $path = "`"$path`"" }
    $project = ''
    if ($script:KitProject -and [System.IO.Path]::GetFullPath($script:KitProject).TrimEnd('\', '/') -ne $PWD.Path.TrimEnd('\', '/')) {
        $project = " -Project `"$($script:KitProject -replace '\\', '/')`""
    }
    return "pwsh $path $Arguments$project"
}

# Whether $Path is $Root or inside it. A plain StartsWith would count <root>-assets as inside <root>, so the root is compared
# with a trailing separator. Windows and macOS file systems ignore case by default; Linux's does not.
function Test-PathInside([string]$Path, [string]$Root) {
    $full = ([System.IO.Path]::GetFullPath($Path) -replace '\\', '/').TrimEnd('/')
    $base = ([System.IO.Path]::GetFullPath($Root) -replace '\\', '/').TrimEnd('/')
    $comparison = if ($IsWindows -or $IsMacOS) { [StringComparison]::OrdinalIgnoreCase } else { [StringComparison]::Ordinal }
    return $full.Equals($base, $comparison) -or $full.StartsWith("$base/", $comparison)
}

# Every line of a run, the tools' output included, goes to one log file (hyperdot.log in the results folder). With -Quiet
# the console shows only the kit's own [hyperdot] lines, so an agent reading the output pays for the verdict and not for
# thousands of lines of engine and compiler output; the details stay one file away.
$script:QuietMode = $false
$script:RunLogWriter = $null
$script:RunLogPath = $null

function Start-RunLog([string]$Path) {
    New-Item -ItemType Directory -Force (Split-Path $Path) | Out-Null
    $script:RunLogWriter = [System.IO.StreamWriter]::new($Path, $false, [System.Text.UTF8Encoding]::new($false))
    $script:RunLogWriter.AutoFlush = $true
    $script:RunLogPath = $Path
}

function Write-RunLog([string]$Text, [switch]$NoNewline) {
    if (-not $script:RunLogWriter) { return }
    if ($NoNewline) { $script:RunLogWriter.Write($Text) } else { $script:RunLogWriter.WriteLine($Text) }
}

# One line per run of a command that changes or checks the game (test, build, export, bench, shot, audio, soak, credits, deck, doctor), kept in the project's .godot folder (never committed, survives a
# wiped results folder). The Stop hook reads it to tell whether code changed since the last passing test run,
# /retro reads recurring error codes from it, and each test run compares its failures with the previous one's.
$script:HistoryCommand = $null
$script:HistoryProject = $null
$script:HistoryStart = $null
$script:HistoryTestRun = $null

function Start-RunHistory([string]$Command, [string]$ProjectDir) {
    $script:HistoryCommand = $Command
    $script:HistoryProject = $ProjectDir
    $script:HistoryStart = Get-Date
    $script:HistoryTestRun = $null
    $script:RunErrorKeys.Clear()
}

# The commit checked out in $Dir (short hash), or $null outside git. Uncommitted changes are not part of it.
function Get-HeadCommit([string]$Dir) {
    if (-not (Get-Command git -ErrorAction SilentlyContinue)) { return $null }
    $git = Invoke-GitBounded $Dir @('rev-parse', '--short', 'HEAD') 'head commit'
    if ($git.Code -ne 0 -or $git.Lines.Count -eq 0) { return $null }
    return "$($git.Lines[0])".Trim()
}

# The run log as it is now, while the run still writes it (shared read, so Windows does not refuse it).
function Read-RunLogLines {
    if (-not $script:RunLogPath -or -not (Test-Path -LiteralPath $script:RunLogPath)) { return @() }
    $stream = [System.IO.FileStream]::new($script:RunLogPath, [System.IO.FileMode]::Open, [System.IO.FileAccess]::Read, [System.IO.FileShare]::ReadWrite)
    try { $text = [System.IO.StreamReader]::new($stream).ReadToEnd() } finally { $stream.Dispose() }
    return @($text -split '\r?\n')
}

# A test run's part of its history line: the runners that failed, the scope (runners and -Filter) and the failing test
# ids (Get-FailureIds), which the next run with the same scope compares itself with (Get-FailureDelta). -Extra adds more
# keys to the line (test -Retry's flaky and quarantined ids); readers skip keys they do not know, so lines only grow.
function Set-TestRunHistory($Scope, $Failing, [string[]]$FailedRunners, [System.Collections.IDictionary]$Extra = @{}) {
    $script:HistoryTestRun = [ordered]@{
        failedRunners = @($FailedRunners | Where-Object { $_ }); scope = $Scope
        failures = @($Failing.Ids); failuresTruncated = [bool]$Failing.Truncated
    }
    foreach ($key in $Extra.Keys) { $script:HistoryTestRun[$key] = $Extra[$key] }
}

function Add-RunHistory([bool]$Ok, [string]$Code) {
    if (-not $script:HistoryCommand) { return }
    $file = Join-Path $script:HistoryProject '.godot/hyperdot-history.jsonl'
    $entry = [ordered]@{
        time = (Get-Date).ToUniversalTime().ToString('o'); command = $script:HistoryCommand; ok = $Ok; code = $Code
        seconds = [math]::Round(((Get-Date) - $script:HistoryStart).TotalSeconds, 1)
    }
    if ($script:HistoryTestRun) {
        foreach ($key in $script:HistoryTestRun.Keys) { $entry[$key] = $script:HistoryTestRun[$key] }
    } elseif ($script:JsonDoc.Contains('runnerResults')) {
        $entry['failedRunners'] = @($script:JsonDoc['runnerResults'] | Where-Object { -not $_.ok } | ForEach-Object { $_.runner })
    }
    # Where and with what errors: status groups runs by error key (Get-RecurringErrors).
    try {
        $entry['commit'] = Get-HeadCommit $script:HistoryProject
        # The tree of the working folder: the Stop hook compares it with the tree in front of it, not file times.
        if ($script:HistoryCommand -eq 'test') { $entry['tree'] = Get-WorkingTreeId $script:HistoryProject }
        $entry['errorKeys'] = @(Get-RunErrorKeys @(Read-RunLogLines) @($script:RunErrorKeys))
    } catch {
        Write-RunLog "[hyperdot] Could not read the run's error keys: $_"
        if (-not $entry.Contains('errorKeys')) { $entry['errorKeys'] = @() }
    }
    try {
        New-Item -ItemType Directory -Force (Split-Path $file) | Out-Null
        Add-Content -LiteralPath $file -Value ($entry | ConvertTo-Json -Compress -Depth 4) -Encoding utf8
        # Over 2,500 lines, the newest 2,000 are kept: status and telemetry read the whole file.
        $kept = @(Get-Content -LiteralPath $file)
        if ($kept.Count -gt 2500) { [System.IO.File]::WriteAllLines($file, [string[]]@($kept | Select-Object -Last 2000)) }
    } catch {
        # History is a convenience; a read-only project must not fail the run.
        Write-RunLog "[hyperdot] Could not record the run in ${file}: $_"
    }
    $script:HistoryCommand = $null
    $script:HistoryTestRun = $null
}

# -Json: stdout carries exactly one JSON document (schema "hyperdot/1"); every log line goes to stderr.
# Functions add their part with Set-JsonField; the entry point prints the result at the end.
$script:JsonMode = $false
$script:JsonDoc = [ordered]@{}

function Enable-JsonMode([string]$Command) {
    $script:JsonMode = $true
    $script:JsonDoc = [ordered]@{ schema = 'hyperdot/1'; command = $Command; ok = $true }
}
function Set-JsonField([string]$Name, $Value) { if ($script:JsonMode) { $script:JsonDoc[$Name] = $Value } }
# Set by a command that runs Godot on the project: adds what the run changed in the game's files (Get-NewProjectChanges).
$script:ChangeProbe = $null
function Write-JsonResult {
    if ($script:RunLogPath) { Set-JsonField log $script:RunLogPath }
    if ($script:ChangeProbe) { & $script:ChangeProbe }
    if ($script:JsonMode) { [Console]::Out.WriteLine(($script:JsonDoc | ConvertTo-Json -Depth 8)) }
}

# Code is a stable, machine-readable reason: callers can branch on it, while Message is for people.
# A command made of other commands' checks (deck) sets $script:CatchStops while it runs one of them: a stop is then thrown
# as an exception carrying its code (Data['HyperdotCode']), so that command can record the part and go on to the next.
$script:CatchStops = $false
function Stop-GodotCi([string]$Message, [string]$Code = 'failed') {
    Add-KitCoverage "error:$Code"
    if ($script:CatchStops) {
        $stop = [System.Exception]::new($Message)
        $stop.Data['HyperdotCode'] = $Code
        throw $stop
    }
    Write-Console "[hyperdot] ERROR: $Message" -ForegroundColor Red
    if ($script:RunLogPath -and $script:QuietMode) { Write-Console "[hyperdot] Full log: $script:RunLogPath" }
    Add-RunHistory $false $Code
    if ($script:JsonMode) {
        $script:JsonDoc['ok'] = $false
        $script:JsonDoc['error'] = [ordered]@{ code = $Code; message = $Message }
        Write-JsonResult
    }
    exit 1
}

# Collapsible log groups on GitHub Actions, plain headers elsewhere.
function Start-LogGroup([string]$Title) {
    if ($script:QuietMode) { Write-RunLog "== $Title ==" }
    elseif ($env:GITHUB_ACTIONS) { Write-Console "::group::$Title" } else { Write-Console "== $Title ==" }
}
function Stop-LogGroup { if ($env:GITHUB_ACTIONS -and -not $script:QuietMode) { Write-Console '::endgroup::' } }

# Runs a program, streaming its output (stdout and stderr) to the console (the run log only, with -Quiet) and, if given,
# a log file. Returns the exit code instead of throwing, so callers decide what a failure means.
# Seconds a program may run before it counts as hung (a deadlock, an await that never resumes). Without a limit a hung
# Godot stalls a local run, and the agent waiting on it, forever. HYPERDOT_TIMEOUT overrides it; 0 turns it off.
function Get-ProcessTimeout {
    if (-not $env:HYPERDOT_TIMEOUT) { return 1800 }
    $seconds = 0
    if (-not [int]::TryParse($env:HYPERDOT_TIMEOUT, [ref]$seconds) -or $seconds -lt 0) {
        Stop-GodotCi "HYPERDOT_TIMEOUT must be a whole number of seconds: $env:HYPERDOT_TIMEOUT" 'invalid-arguments'
    }
    return $seconds
}

# Runs a program, shows (or logs) stdout and stderr line by line, and returns its exit code. A program that outlives
# Get-ProcessTimeout is stopped with its child processes and returns 124, the exit code of coreutils' timeout.
function Invoke-Logged {
    param([string]$FilePath, [string[]]$ArgumentList = @(), [string]$LogFile)
    $show = if ($script:QuietMode) { { Write-RunLog $_ } } else { { Write-Console $_ } }
    $command = @(Get-Command $FilePath -CommandType Application -ErrorAction SilentlyContinue)
    if ($command.Count -eq 0) { Stop-GodotCi "Program not found: $FilePath" }
    $info = [System.Diagnostics.ProcessStartInfo]::new($command[0].Source)
    foreach ($argument in $ArgumentList) { $info.ArgumentList.Add($argument) }
    $info.UseShellExecute = $false
    $info.RedirectStandardOutput = $true
    $info.RedirectStandardError = $true
    $info.StandardOutputEncoding = [System.Text.UTF8Encoding]::new($false)
    $info.StandardErrorEncoding = [System.Text.UTF8Encoding]::new($false)
    $timeout = Get-ProcessTimeout
    $writer = if ($LogFile) { [System.IO.StreamWriter]::new($LogFile, $false, [System.Text.UTF8Encoding]::new($false)) }
    $process = [System.Diagnostics.Process]::Start($info)
    $clock = [System.Diagnostics.Stopwatch]::StartNew()
    $readers = @($process.StandardOutput, $process.StandardError)
    $pending = @($readers[0].ReadLineAsync(), $readers[1].ReadLineAsync())
    $timedOut = $false
    try {
        while ($null -ne $pending[0] -or $null -ne $pending[1]) {
            $wait = 1000
            if ($timeout -gt 0) {
                $left = $timeout * 1000 - $clock.ElapsedMilliseconds
                if ($left -le 0) { $timedOut = $true; break }
                $wait = [Math]::Min($wait, $left)
            }
            $open = @(foreach ($i in 0, 1) { if ($null -ne $pending[$i]) { $i } })
            $tasks = [System.Threading.Tasks.Task[]]@(foreach ($i in $open) { $pending[$i] })
            $done = [System.Threading.Tasks.Task]::WaitAny($tasks, [int]$wait)
            if ($done -lt 0) {
                # A child the program started (a build server) can keep the pipes open after the program itself exits.
                if ($process.HasExited) { break }
                continue
            }
            $stream = $open[$done]
            $line = $pending[$stream].Result
            if ($null -eq $line) { $pending[$stream] = $null; continue }
            $pending[$stream] = $readers[$stream].ReadLineAsync()
            if ($writer) { $writer.WriteLine($line) }
            $line | ForEach-Object $show
        }
        # Both pipes can close while the program runs on (it redirected its output elsewhere): wait only for the time left.
        if (-not $timedOut -and $timeout -gt 0) {
            $left = [Math]::Min([int]::MaxValue, [Math]::Max(0, $timeout * 1000 - $clock.ElapsedMilliseconds))
            if (-not $process.WaitForExit([int]$left)) { $timedOut = $true }
        }
        if ($timedOut) {
            try { $process.Kill($true) } catch [System.InvalidOperationException] { Write-Verbose 'It exited meanwhile.' }
            $message = "[hyperdot] $FilePath was still running after $timeout s and was stopped (raise HYPERDOT_TIMEOUT if it needs longer)"
            if ($writer) { $writer.WriteLine($message) }
            Write-Console $message -ForegroundColor Red
        }
    } finally {
        if ($writer) { $writer.Dispose() }
    }
    $process.WaitForExit()
    if ($timedOut) { return 124 }
    return $process.ExitCode
}

# A time limit for a read-only command (status, plan), set by -TimeoutSec: every step that can wait on something outside the script (git, gh,
# a long folder walk) is bounded by what is left of it, and a step that ran out is skipped and listed in the result's "partial" field, with
# what it was waiting for, so a hang on one thing (an editor holding git, a GitHub call) costs the limit and not the whole run.
$script:CommandDeadline = $null
$script:PartialSteps = [System.Collections.Generic.List[object]]::new()
function Set-CommandDeadline([int]$Seconds) {
    $script:PartialSteps.Clear()
    $script:CommandDeadline = if ($Seconds -gt 0) { [pscustomobject]@{ Seconds = $Seconds; Clock = [System.Diagnostics.Stopwatch]::StartNew() } } else { $null }
}
# Milliseconds left, 0 when the limit has passed, $null without a limit.
function Get-DeadlineLeftMs {
    if (-not $script:CommandDeadline) { return $null }
    return [long][Math]::Max(0, $script:CommandDeadline.Seconds * 1000 - $script:CommandDeadline.Clock.ElapsedMilliseconds)
}
function Test-DeadlinePassed { $left = Get-DeadlineLeftMs; return ($null -ne $left -and $left -le 0) }
# Notes a step that was cut short or skipped; the same step is listed once.
function Add-PartialStep([string]$Step, [string]$WaitingOn) {
    if (@($script:PartialSteps | Where-Object { $_.step -eq $Step }).Count -gt 0) { return }
    $script:PartialSteps.Add([ordered]@{ step = $Step; waitingOn = $WaitingOn })
}
# The result's "partial" field: $null when nothing was cut short.
function Get-PartialResult {
    if ($script:PartialSteps.Count -eq 0) { return $null }
    return [ordered]@{ reason = 'timeout'; timeoutSec = $script:CommandDeadline.Seconds
        skipped = @($script:PartialSteps); note = "The time limit (-TimeoutSec $($script:CommandDeadline.Seconds)) ran out: the facts below are what was gathered; raise -TimeoutSec, or run the command again once what it waited for answers" }
}

# Runs a program for its output, bounded by what is left of the command's time limit (none: it waits as long as the program runs). Returns
# Lines (stdout, with stderr after it when $MergeStderr), the exit code, and TimedOut: a program that outlives the limit is stopped with its
# children and returns 124; with the limit already passed nothing is started. Never throws for a missing program: Code is 127.
function Invoke-ExternalBounded([string]$FilePath, [string[]]$ArgumentList = @(), [switch]$MergeStderr) {
    if (Test-DeadlinePassed) { return [pscustomobject]@{ Lines = @(); Code = 124; TimedOut = $true } }
    $command = @(Get-Command $FilePath -CommandType Application -ErrorAction SilentlyContinue)
    if ($command.Count -eq 0) { return [pscustomobject]@{ Lines = @(); Code = 127; TimedOut = $false } }
    $info = [System.Diagnostics.ProcessStartInfo]::new($command[0].Source)
    foreach ($argument in $ArgumentList) { $info.ArgumentList.Add($argument) }
    $info.UseShellExecute = $false
    $info.RedirectStandardOutput = $true
    $info.RedirectStandardError = $true
    $info.StandardOutputEncoding = [System.Text.UTF8Encoding]::new($false)
    $info.StandardErrorEncoding = [System.Text.UTF8Encoding]::new($false)
    $process = [System.Diagnostics.Process]::Start($info)
    $out = $process.StandardOutput.ReadToEndAsync()
    $err = $process.StandardError.ReadToEndAsync()
    $left = Get-DeadlineLeftMs
    $exited = if ($null -eq $left) { $process.WaitForExit(); $true } else { $process.WaitForExit([int][Math]::Min([int]::MaxValue, $left)) }
    if (-not $exited) {
        try { $process.Kill($true) } catch [System.InvalidOperationException] { Write-Verbose 'It exited meanwhile.' }
        $process.WaitForExit()
        return [pscustomobject]@{ Lines = @(); Code = 124; TimedOut = $true }
    }
    $process.WaitForExit()   # the reads finish once the pipes close
    $text = $out.GetAwaiter().GetResult()
    if ($MergeStderr) { $text += $err.GetAwaiter().GetResult() }
    return [pscustomobject]@{ Lines = @($text -split "`r?`n" | Where-Object { $_ -ne '' }); Code = $process.ExitCode; TimedOut = $false }
}

# git in $Dir, bounded by the command's time limit; a call that ran out is noted as a partial step ($What names the step, the git
# subcommand is what it waited for). Returns the same object as Invoke-ExternalBounded.
function Invoke-GitBounded([string]$Dir, [string[]]$GitArgs, [string]$What) {
    $result = Invoke-ExternalBounded 'git' (@('-C', $Dir) + $GitArgs)
    if ($result.TimedOut) { Add-PartialStep $What "git $($GitArgs[0])" }
    return $result
}

# Godot 4.7's C# asks for .NET 8 with rollForward LatestMajor (GodotSharp/Api/*/GodotPlugins.runtimeconfig.json), so a Godot
# the kit starts runs on the newest .NET runtime installed. On .NET 11 (GitHub's ubuntu-26.04 image 20261111) godottest under
# coverlet hit a CLR assert at shutdown, "Attempt to reattach detached thread" (ebr.cpp:144), after every test passed (#264).
# DOTNET_ROLL_FORWARD=Major, which takes precedence over the runtimeconfig's setting (seen in the host trace), keeps the runtime Godot was built for when it is
# installed and still allows the lowest newer major when it is not. Every process the kit starts inherits it; a value the user
# set is kept. Returns the value in force.
function Set-DotnetRollForward {
    if (-not $env:DOTNET_ROLL_FORWARD) { $env:DOTNET_ROLL_FORWARD = 'Major' }
    return $env:DOTNET_ROLL_FORWARD
}

# True for an exit code that is a crash: 128 and up is a signal (134 is an abort), a negative one is a Windows NTSTATUS code.
function Test-GodotCrashCode([int]$Code) { return ($Code -ge 128 -or $Code -lt 0) }

# What a runner's exit code adds to the cases it judged: a failure, or a warning. A Godot that crashed after everything had been judged
# ($JudgedAll) is a crash in its shutdown (observed: exit 134, `FATAL: Condition "csharp_lang && !csharp_lang->script_bindings.is_empty()"`
# in the mono teardown, followed by hundreds of "Leaked unsafe reference" lines), nothing the change under test did: a warning with the FATAL
# line. A crash with something not judged, or with $ErrorsBefore (errors printed before the crash), still fails, and so does any other nonzero
# exit. $What names what was judged ('rule', 'flow'), for the message.
function Get-ShutdownCrashVerdict([int]$Code, [string[]]$Lines, [bool]$JudgedAll, [string[]]$ErrorsBefore, [string]$What) {
    if ($Code -eq 0) { return [pscustomobject]@{ Failure = (@($ErrorsBefore) -join "`n"); Warning = '' } }
    if ((Test-GodotCrashCode $Code) -and $JudgedAll -and @($ErrorsBefore).Count -eq 0) {
        $fatal = [array]::FindIndex($Lines, [Predicate[string]]{ param($l) $l -match 'FATAL:' })
        $line = if ($fatal -ge 0) { $Lines[$fatal].Trim() } else { 'no FATAL line in the log' }
        return [pscustomobject]@{ Failure = ''; Warning = "Godot crashed at shutdown (exit $Code) after every $What was judged: $line" }
    }
    return [pscustomobject]@{ Failure = "Godot exited with $Code"; Warning = '' }
}

# Runs Godot for a job that is safe to repeat (an import, an export) and runs it again, up to twice, when Godot crashed:
# an exit code of 128 and up is a signal (observed: 134, an abort, on 4.7.2 when the import cache is stale and, 4 times
# in 23 headless runs, at shutdown after a finished export: `Parameter "singleton" is null`); on Windows a crash is a
# negative NTSTATUS code (observed: -1073741819, an access violation). An ordinary failure is never repeated, and a
# crash that happens every time still fails after the third run. -Output, the file the job writes, is deleted before a
# repeat, so a file left by the crashed run is never mistaken for the repeat's. Returns the last exit code and how many
# repeats ran.
function Invoke-GodotRetried {
    param([string[]]$ArgumentList, [string]$LogFile, [string]$What, [string]$Output, [string]$FilePath = $env:GODOT_BIN)
    $code = Invoke-Logged $FilePath $ArgumentList $LogFile
    $retries = 0
    while (($code -ge 128 -or $code -lt 0) -and $retries -lt 2) {
        $retries++
        Write-CiLog "Godot crashed during $What (exit $code); retry $retries of 2"
        if ($Output -and (Test-Path -LiteralPath $Output)) { Remove-Item -LiteralPath $Output -Recurse -Force }
        $code = Invoke-Logged $FilePath $ArgumentList $LogFile
    }
    return [pscustomobject]@{ Code = $code; Retries = $retries }
}

# Runs a program and stops the whole run if it fails.
function Invoke-Checked {
    param([string]$FilePath, [string[]]$ArgumentList = @())
    $code = Invoke-Logged -FilePath $FilePath -ArgumentList $ArgumentList
    if ($code -ne 0) { Stop-GodotCi "$FilePath $($ArgumentList -join ' ') exited with $code" }
}

function Get-ToolsDir {
    if ($env:GODOT_TOOLS_DIR) { return $env:GODOT_TOOLS_DIR }
    $dir = Join-Path $HOME '.hyperdot'
    # Before Hyperdot the downloads lived in ~/.godot-ci: moved once, so Godot and .NET are not fetched again.
    $old = Join-Path $HOME '.godot-ci'
    if (-not (Test-Path -LiteralPath $dir) -and (Test-Path -LiteralPath $old)) {
        Move-Item -LiteralPath $old -Destination $dir
        Write-CiLog "Moved $old to $dir (the kit is now Hyperdot)"
    }
    return $dir
}

# Before Hyperdot the kit kept a game's run history and its GUT stamp under godot-ci names. Each is moved once to its new
# name, so the Stop hook, status and the failure delta keep the history, and an installed GUT stays the kit's own.
function Move-OldKitState([string]$ProjectDir) {
    $renames = @(
        @('.godot/godot-ci-history.jsonl', '.godot/hyperdot-history.jsonl'),
        @('addons/gut/.godot-ci-version', 'addons/gut/.hyperdot-version')
    )
    foreach ($rename in $renames) {
        $old = Join-Path $ProjectDir $rename[0]
        $new = Join-Path $ProjectDir $rename[1]
        if ((Test-Path -LiteralPath $old) -and -not (Test-Path -LiteralPath $new)) {
            Move-Item -LiteralPath $old -Destination $new
            Write-CiLog "Moved $($rename[0]) to $($rename[1]) (the kit is now Hyperdot)"
        }
    }
}

# Engine-internal messages that say nothing about the project. Extend per project with the
# HYPERDOT_IGNORE_ERRORS environment variable (a regex).
$script:KnownNoise = @(
    # The Android export plugin can read editor settings during headless shutdown (timing-dependent).
    'EditorSettings not instantiated yet when getting setting',
    # Seen once on a cold 4.7.2 import: a C++ engine singleton read during editor shutdown. No script or file is named.
    '^\s*ERROR: Parameter "singleton" is null\.$',
    # 4.7.2, with a window and the Dummy audio driver (bench, shot) or Movie Maker (audio -Mix): quitting while a sound
    # plays leaves its stream (an AudioStreamWAV) referenced at shutdown. Any game with music hits it; headless runs do not.
    '^\s*ERROR: \d+ resources? still in use at exit',
    # The godot-mcp editor bridge starts a server on a fixed port; with the editor open on the same project the port is taken.
    '^\s*ERROR: \[godot-mcp\] Failed to start server on 127\.0\.0\.1:\d+: Already in use',
    # 4.7.2 Android exports of a project without application/config/icon: the build uses Godot's icon. doctor warns.
    '^\s*ERROR: No project icon specified'
)

# Godot's own prefixes, matched case-sensitively (-cmatch): a game that prints "Error: no save file yet" is not an engine error.
$script:GodotErrorPattern = '^\s*(SCRIPT ERROR|SHADER ERROR|ERROR|USER ERROR):|Unhandled [Ee]xception|Failed to load script'

# One regex for the error lines to leave out: the known noise and HYPERDOT_IGNORE_ERRORS. An invalid HYPERDOT_IGNORE_ERRORS
# stops the run; -Lenient leaves it out instead (for the run history, which must never stop a run).
function Get-IgnoredErrorsRegex([switch]$Lenient) {
    $ignore = @($script:KnownNoise)
    if ($env:HYPERDOT_IGNORE_ERRORS) {
        $valid = $true
        try { [void][regex]::new($env:HYPERDOT_IGNORE_ERRORS) } catch { $valid = $false }
        if ($valid) { $ignore += $env:HYPERDOT_IGNORE_ERRORS }
        elseif (-not $Lenient) { Stop-GodotCi "HYPERDOT_IGNORE_ERRORS is not a valid regex: $env:HYPERDOT_IGNORE_ERRORS" 'invalid-arguments' }
    }
    return ($ignore | ForEach-Object { "(?:$_)" }) -join '|'
}

# Godot often exits 0 after printing errors, so builds, exports and smoke runs also scan the log.
# Returns the offending lines (empty when clean).
function Select-GodotErrors([string[]]$Lines) {
    $pattern = $script:GodotErrorPattern
    $ignoreRegex = Get-IgnoredErrorsRegex
    $errors = @()
    foreach ($raw in $Lines) {
        $line = $raw -replace "`e\[[0-9;]*m", ''
        if ($line -cmatch $pattern) {
            if ($line -match $ignoreRegex) { Write-CiLog "Ignored known engine noise: $line" }
            else { $errors += $line }
        }
    }
    return $errors
}

# Errors Godot's own C# bindings log when a managed wrapper is collected under the engine ("Handle is not initialized." from
# SwapGCHandleForType, godotengine/godot#124587). Whatever was running when one was logged did not cause it: a flow in progress has not failed
# because of it, and a rerun usually passes. The lines under an error (its managed stack trace) can name the bindings when its first line does not.
$script:EngineInternalPattern = 'Handle is not initialized|\bSwapGCHandleForType\b|\bGCHandle\b|\bScriptManagerBridge\b'

# Select-GodotErrors, with the engine's own errors told apart: Own are the project's errors, Engine the bindings' (see EngineInternalPattern).
function Split-GodotErrors([string[]]$Lines) {
    $pattern = $script:GodotErrorPattern
    $ignoreRegex = Get-IgnoredErrorsRegex
    $clean = @($Lines | ForEach-Object { $_ -replace "`e\[[0-9;]*m", '' })
    $own = @(); $engine = @()
    for ($i = 0; $i -lt $clean.Count; $i++) {
        $line = $clean[$i]
        if ($line -cnotmatch $pattern) { continue }
        if ($line -match $ignoreRegex) { Write-CiLog "Ignored known engine noise: $line"; continue }
        $block = $line
        for ($j = $i + 1; $j -lt [math]::Min($clean.Count, $i + 12); $j++) {
            if ($clean[$j] -notmatch '^\s' -or $clean[$j] -cmatch $pattern) { break }
            $block += "`n" + $clean[$j]
        }
        if ($block -match $script:EngineInternalPattern) { $engine += $line } else { $own += $line }
    }
    return [pscustomobject]@{ Own = @($own); Engine = @($engine) }
}

# The path Godot says it looked at for a missing export template ("No export template found at the expected path: ..."),
# or $null when the log does not say so.
function Get-MissingExportTemplate([string]$LogFile) {
    # Godot 4.7.2 prints the path on the line after the message, older and other builds on the same line.
    $text = (Get-Content -LiteralPath $LogFile -Raw) -replace "`e\[[0-9;]*m", ''
    $hit = [regex]::Match($text, 'No export template found at the expected path:[ \t]*\r?\n?[ \t]*(?<path>[^\r\n]*\S)')
    return $hit.Success ? $hit.Groups['path'].Value : $null
}

# Which Android keystore an export could not sign with, 'release' or 'debug', or $null when the log does not say so.
# Godot 4.7.2: "Code Signing: Could not find release keystore, unable to export." (and the same for debug).
function Get-MissingExportKeystore([string]$LogFile) {
    $text = (Get-Content -LiteralPath $LogFile -Raw) -replace "`e\[[0-9;]*m", ''
    $hit = [regex]::Match($text, '(?i)could not find (?<kind>release|debug) keystore')
    return $hit.Success ? $hit.Groups['kind'].Value.ToLowerInvariant() : $null
}

# The message for an export that has no keystore to sign with ($Kind from Get-MissingExportKeystore): the variables Godot
# reads, and for a release build the debug build that needs none of them.
function Get-KeystoreHint([string]$Preset, [string]$Kind) {
    $upper = $Kind.ToUpperInvariant()
    $vars = "set GODOT_ANDROID_KEYSTORE_${upper}_PATH, _USER and _PASSWORD"
    if ($Kind -eq 'release') {
        return "Export '$Preset' needs a release keystore: $vars (godot-export-release), or pass -DebugBuild for a debug build signed with the debug keystore"
    }
    return "Export '$Preset' needs a debug keystore: $vars, or set export/android/debug_keystore in the editor settings"
}

# The error lines of a log (Get-GodotLogErrors), each followed by where Godot said it happened ("at res://x.gd:20") when the
# backtrace under it names a file; an error from an autoload at startup then carries its place into the failure.
function Get-GodotErrorsLocated([string[]]$Lines) {
    @(foreach ($d in Get-GodotErrorDetails $Lines) { if ($d.File) { "$($d.Text) at $($d.File):$($d.Line)" } else { $d.Text } })
}

# Always wrap calls in @(...): an empty result comes back as nothing.
function Get-GodotLogErrors([string]$LogFile) { return Select-GodotErrors @(Get-Content -LiteralPath $LogFile) }

# Error keys, after Activision's build server for Call of Duty (docs/gdc/call-of-duty-error-keys.md): every failure got a
# one-sentence summary made from the error lines of its log, and failures were grouped by it, so anyone could see whether
# an error had happened before, how often, and since when. Here a key is the error line with what changes from run to
# run taken out: numbers become N (line numbers, sizes, object ids, node names like @Node2D@23), hex addresses X. res://
# and user:// paths are kept, without their line number, and when the line names no path, the first project frame of the
# "at:"/backtrace lines under it is added ("... at res://player.gd"), so the same message from two scripts stays apart.
function Get-ErrorKey([string]$Text, [string]$File) {
    $text = (($Text -replace "`e\[[0-9;]*m", '') -replace '\s+', ' ').Trim()
    # Odd items are the paths (the capture group), kept as they are; their ":<line>" starts the item after them.
    $parts = [regex]::Split($text, '((?:res|user)://[^\s:''"()<>,\[\]]+)')
    $key = -join @(for ($i = 0; $i -lt $parts.Count; $i++) {
        if ($i % 2) { $parts[$i]; continue }
        $part = if ($i -gt 0) { $parts[$i] -replace '^:\d+', '' } else { $parts[$i] }
        $part -replace '\b0[xX][0-9A-Fa-f]+\b', 'X' -replace '(?<![A-Za-z_\d.])\d+(?:\.\d+)*', 'N'
    })
    if ($File -and $key -notmatch '(res|user)://') { $key = "$key at $File" }
    if ($key.Length -gt 240) { $key = $key.Substring(0, 240) }
    return $key
}

# The Godot error lines of a log (Select-GodotErrors' lines, known noise left out without a word), each with Text (the line,
# trimmed), File and Line (the res:// location on the line, or else the first one in the indented "at:"/backtrace lines
# under it, frames in addons/ only when there is no other), Key (Get-ErrorKey) and Index (its line number in $Lines, from 0).
function Get-GodotErrorDetails([string[]]$Lines, [switch]$Lenient) {
    $ignoreRegex = Get-IgnoredErrorsRegex -Lenient:$Lenient
    $location = '(?<file>res://[^\s:()''"]+):(?<line>\d+)'
    for ($i = 0; $i -lt $Lines.Count; $i++) {
        # A cheap test first: a log can run to many thousands of lines, and few are errors.
        if ($Lines[$i] -cnotmatch 'ERROR|xception|Failed to load') { continue }
        $line = $Lines[$i] -replace "`e\[[0-9;]*m", ''
        if ($line -cnotmatch $script:GodotErrorPattern -or $line -match $ignoreRegex) { continue }
        $at = [regex]::Match($line, $location)
        if (-not $at.Success) {
            $frames = @(for ($j = $i + 1; $j -lt [math]::Min($Lines.Count, $i + 8); $j++) {
                $next = $Lines[$j] -replace "`e\[[0-9;]*m", ''
                if ($next -notmatch '^\s' -or $next -cmatch $script:GodotErrorPattern) { break }
                foreach ($m in [regex]::Matches($next, $location)) { $m }
            })
            $own = @($frames | Where-Object { $_.Groups['file'].Value -notlike 'res://addons/*' })
            $at = if ($own) { $own[0] } elseif ($frames) { $frames[0] } else { $at }
        }
        $file = $at.Success ? $at.Groups['file'].Value : $null
        # "Cannot export project with preset ... due to configuration errors:" says why on the lines under it, which carry no ERROR prefix.
        $text = $line.Trim()
        if ($line -match 'configuration errors:\s*$') {
            $why = @(for ($j = $i + 1; $j -lt [math]::Min($Lines.Count, $i + 6); $j++) {
                $next = ($Lines[$j] -replace "`e\[[0-9;]*m", '').Trim()
                if (-not $next -or $next -cmatch $script:GodotErrorPattern) { break }
                $next
            })
            if ($why) { $text = "$text $($why -join ' ')" }
        }
        [pscustomobject]@{ Text = $text; File = $file; Line = $at.Success ? [int]$at.Groups['line'].Value : $null; Key = (Get-ErrorKey $line $file); Index = $i }
    }
}

# The distinct error keys of a run's log, in the order they first appear, at most $Cap: Godot's error lines, a Godot crash
# ("Program crashed with signal 11", the signal kept) and a program the kit stopped for running too long. $Extra (keys
# already made, such as soak's) come first. A key without a location is dropped when the same error also appears with
# one (the kit prints an error line again, without the backtrace under it, when it fails a run).
function Get-RunErrorKeys([string[]]$Lines, [string[]]$Extra = @(), [int]$Cap = 20) {
    $keys = [System.Collections.Generic.List[string]]::new()
    $seen = [System.Collections.Generic.HashSet[string]]::new([StringComparer]::Ordinal)
    foreach ($key in $Extra | Where-Object { $_ }) { if ($seen.Add($key)) { $keys.Add($key) } }
    $details = @{}
    foreach ($d in Get-GodotErrorDetails $Lines -Lenient) { $details[$d.Index] = $d }
    $located = [System.Collections.Generic.HashSet[string]]::new([string[]]@($details.Values | Where-Object File | ForEach-Object { Get-ErrorKey $_.Text '' }), [StringComparer]::Ordinal)
    for ($i = 0; $i -lt $Lines.Count; $i++) {
        if (-not $details.ContainsKey($i) -and $Lines[$i] -cnotmatch 'crashed|still running') { continue }
        $line = $Lines[$i] -replace "`e\[[0-9;]*m", ''
        $key = $null
        if ($details.ContainsKey($i)) {
            if ($details[$i].File -or -not $located.Contains($details[$i].Key)) { $key = $details[$i].Key }
        } elseif ($line -match 'Program crashed with signal (?<s>\d+)') {
            $key = "Program crashed with signal $($Matches.s)"
        } elseif ($line -match '^\[hyperdot\] (?<p>.+) was still running after \d+ s and was stopped') {
            $key = "$(Split-Path -Leaf $Matches.p) was still running at the time limit and was stopped"
        }
        if ($key -and $seen.Add($key)) { $keys.Add($key) }
    }
    return @($keys | Select-Object -First $Cap)
}

# engineErrors[] in the JSON (message, file, line, key; the first 30) from Get-GodotErrorDetails. The keys also go to the
# run's history line, for errors read from logs the run log does not hold (soak's processes).
$script:RunErrorKeys = [System.Collections.Generic.List[string]]::new()
function Set-EngineErrors([object[]]$Details) {
    foreach ($d in $Details) { $script:RunErrorKeys.Add($d.Key) }
    Set-JsonField engineErrors @($Details | Select-Object -First 30 | ForEach-Object { [ordered]@{ message = $_.Text; file = $_.File; line = $_.Line; key = $_.Key } })
}

# -Expected: error lines that are known to be harmless in this run (compared after trimming).
function Assert-GodotLogClean([string]$LogFile, [string]$What, [string[]]$Expected = @()) {
    $errors = @(Get-GodotLogErrors $LogFile | Where-Object { $_.Trim() -notin $Expected })
    if ($errors.Count -gt 0) {
        Write-Console '[hyperdot] Godot reported errors:' -ForegroundColor Red
        $errors | Select-Object -First 30 | ForEach-Object { Write-Console "  $_" }
        Set-EngineErrors @(Get-GodotErrorDetails @(Get-Content -LiteralPath $LogFile) | Where-Object { $_.Text -notin $Expected })
        Stop-GodotCi "$What produced errors (set HYPERDOT_IGNORE_ERRORS to ignore a known message)" 'engine-errors'
    }
}

# File search that skips folders which never hold the user's own files (and are often huge).
$script:PrunedDirs = @('.git', '.godot', 'addons', 'bin', 'obj', 'node_modules', '.godot-pipelines',
    'test-results', 'TestResults', 'audio-results')

# Godot imports whatever lands inside the project, and the next export packs it (screenshots, a whole previous build):
# an output folder the kit writes inside the project gets an empty .gdignore first. Find-ProjectFiles then skips it
# too, so the next audio run does not measure the last one's mix.wav.
function Add-OutputGdignore([string]$Dir, [string]$ProjectDir) {
    $full = [System.IO.Path]::GetFullPath($Dir)
    $relative = [System.IO.Path]::GetRelativePath($ProjectDir, $full)
    if ($relative -eq '.' -or $relative.StartsWith('..') -or [System.IO.Path]::IsPathRooted($relative)) { return }
    $marker = Join-Path $full '.gdignore'
    if (Test-Path -LiteralPath $marker) { return }
    New-Item -ItemType Directory -Force $full | Out-Null
    New-Item -ItemType File -Path $marker | Out-Null
    Write-CiLog "Added $($marker): the output folder is inside the project"
}

$script:PrunedDirSet = [System.Collections.Generic.HashSet[string]]::new([string[]]$script:PrunedDirs, [System.StringComparer]::OrdinalIgnoreCase)

# The files under a folder that match a filter, folder by folder (breadth first), each folder's files and subfolders by name.
# Subfolders that are never the user's own are skipped: the PrunedDirs, every folder whose name starts with a dot (.git, .godot,
# .claude, whose worktrees are whole copies of the game, as Godot skips them too), and a folder with a .gdignore file (this kit's
# own folder has one), the way Godot does. Only subfolders are checked: the root is where the search was asked to look.
# Walked with .NET's enumeration, not Get-ChildItem: detect, plan and status walk the project half a dozen times, and the
# pipeline per folder made each walk about a second for 4,500 files (tens of seconds in all). Like Get-ChildItem without -Force,
# it skips hidden and system entries and folders it cannot read.
function Find-ProjectFiles {
    param([string]$Root, [string]$Filter)
    $options = [System.IO.EnumerationOptions]::new()
    $options.MatchCasing = [System.IO.MatchCasing]::CaseInsensitive      # as -Filter was: *.CS finds a.cs on Linux too
    $comparer = [System.StringComparer]::CurrentCultureIgnoreCase
    $queue = [System.Collections.Generic.Queue[System.IO.DirectoryInfo]]::new()
    $queue.Enqueue([System.IO.DirectoryInfo]::new((Resolve-Path -LiteralPath $Root).Path))
    while ($queue.Count -gt 0) {
        # Past the command's time limit the walk stops where it is: the files found so far are all there is.
        if (Test-DeadlinePassed) { Add-PartialStep 'project files' "reading folder $($queue.Peek().FullName)"; break }
        $dir = $queue.Dequeue()
        $files = [System.IO.FileInfo[]]@($dir.EnumerateFiles($Filter, $options))
        if ($files.Count -gt 1) {
            $names = [string[]]::new($files.Count)
            for ($i = 0; $i -lt $files.Count; $i++) { $names[$i] = $files[$i].Name }
            [System.Array]::Sort($names, $files, $comparer)
        }
        $files
        $subs = [System.IO.DirectoryInfo[]]@($dir.EnumerateDirectories('*', $options))
        if ($subs.Count -gt 1) {
            $names = [string[]]::new($subs.Count)
            for ($i = 0; $i -lt $subs.Count; $i++) { $names[$i] = $subs[$i].Name }
            [System.Array]::Sort($names, $subs, $comparer)
        }
        foreach ($sub in $subs) {
            $name = $sub.Name
            if ($name.StartsWith('.') -or $script:PrunedDirSet.Contains($name) -or $name.StartsWith('gdunit4_testadapter', [System.StringComparison]::OrdinalIgnoreCase)) { continue }
            if ([System.IO.File]::Exists((Join-Path $sub.FullName '.gdignore'))) { continue }
            $queue.Enqueue($sub)
        }
    }
}

# A stored time as UTC. ConvertFrom-Json turns ISO 8601 strings into DateTime values, and PowerShell turns those back
# into US-format text ("10/23/2026 05:57:27") that the PC's culture may not parse (day-first cultures fail on month 23),
# so never round-trip a time through text: take the DateTime as it is, and parse strings with the invariant culture.
function ConvertTo-UtcTime($Value) {
    if ($Value -is [datetime]) { return $Value.ToUniversalTime() }
    if ($Value -is [System.DateTimeOffset]) { return $Value.UtcDateTime }
    return [datetime]::Parse([string]$Value, [cultureinfo]::InvariantCulture, [System.Globalization.DateTimeStyles]::AdjustToUniversal -bor [System.Globalization.DateTimeStyles]::AssumeUniversal)
}

# Rows to a CSV file with numbers as 59.5 under every culture: Export-Csv writes them in the current one (59,5 in de-DE),
# which a spreadsheet or script in another culture misreads, and which the next run's rows would then disagree with.
function Export-InvariantCsv([object[]]$Rows, [string]$Path, [switch]$Append) {
    $culture = [cultureinfo]::CurrentCulture
    try {
        [cultureinfo]::CurrentCulture = [cultureinfo]::InvariantCulture
        $Rows | Export-Csv -LiteralPath $Path -Append:$Append -NoTypeInformation -Encoding utf8
    } finally { [cultureinfo]::CurrentCulture = $culture }
}

# res:// path of a file inside the project.
function ConvertTo-ResPath([string]$ProjectDir, [string]$File) {
    $relative = [System.IO.Path]::GetRelativePath($ProjectDir, $File) -replace '\\', '/'
    return "res://$relative"
}

function ConvertTo-SafeName([string]$Text) { return ($Text -replace '[^A-Za-z0-9._-]+', '-').Trim('-') }

# Repository root, or $null outside a repository or when Git isn't installed (`& git` would otherwise
# throw under $ErrorActionPreference = 'Stop').
# The files git reports as changed or new (not ignored) under a folder, path -> status ("M", "??"), or $null outside a repository.
function Get-ProjectChangeSet([string]$Dir) {
    if (-not (Get-GitRoot $Dir)) { return $null }
    $git = Invoke-GitBounded $Dir @('status', '--porcelain=v1', '--untracked-files=all', '--', '.') 'changed files'
    if ($git.Code -ne 0) { return $null }
    $set = [ordered]@{}
    foreach ($line in $git.Lines) { if ($line.Length -gt 3) { $set[$line.Substring(3).Trim('"')] = $line.Substring(0, 2).Trim() } }
    return $set
}

# What a run changed: entries of $After that $Before lacked or had with another status, without the kit's own results folders and
# the build output. A mono editor adds [dotnet] to project.godot and writes .cs.uid files; this is where a user sees it.
function Get-NewProjectChanges($Before, $After) {
    if ($null -eq $Before -or $null -eq $After) { return @() }
    @(foreach ($path in $After.Keys) {
        if ($path -match '(^|/)(test-results|[\w-]+-results|\.godot|bin|obj)/') { continue }
        if (-not $Before.Contains($path) -or $Before[$path] -ne $After[$path]) { [ordered]@{ path = $path; status = $After[$path] } }
    })
}

# A repository found stays found for the run (status and plan ask for it a dozen times), as long as its .git is still there; a miss is
# never remembered, since a command can start a repository.
$script:GitRootCache = @{}
function Get-GitRoot([string]$Dir) {
    if ($script:GitRootCache.ContainsKey($Dir)) {
        $cached = $script:GitRootCache[$Dir]
        $marker = Join-Path $cached '.git'
        if ([System.IO.Directory]::Exists($marker) -or [System.IO.File]::Exists($marker)) { return $cached }
        $script:GitRootCache.Remove($Dir)
    }
    if (-not (Get-Command git -ErrorAction SilentlyContinue)) { return $null }
    $git = Invoke-GitBounded $Dir @('rev-parse', '--show-toplevel') 'git repository'
    if ($git.Code -ne 0 -or $git.Lines.Count -eq 0) { return $null }
    $script:GitRootCache[$Dir] = $git.Lines[0]
    return $git.Lines[0]
}

# Godot's release tags drop a .0 patch and write prereleases as rc1, not rc.1: Godot.NET.Sdk 4.6.0 is
# tag 4.6-stable and 4.7.0-rc.1 is 4.7-rc1.
function ConvertTo-GodotVersion([string]$Version) {
    $v = $Version -replace '-(rc|beta|dev|alpha)\.(\d)', '-$1$2'
    return $v -replace '^(\d+\.\d+)\.0(?=-|$)', '$1'
}

# "src/Foo.cs(12,5): error CS1002: ; expected [proj]" lines from dotnet build -> structured errors.
function Get-DotnetDiagnostics([string]$LogFile) {
    $seen = @{}
    foreach ($line in Get-Content -LiteralPath $LogFile) {
        # Compiler errors name a file, line and column; restore and project errors (NU1605, MSB...) only the project.
        $m = [regex]::Match($line, '^\s*(?<file>.+?)(?:\((?<line>\d+),(?<col>\d+)\))? : error (?<code>\w+): (?<msg>.*?)(?: \[[^\]]+\])?$')
        if (-not $m.Success) { $m = [regex]::Match($line, '^\s*(?<file>.+?)\((?<line>\d+),(?<col>\d+)\): error (?<code>\w+): (?<msg>.*?)(?: \[[^\]]+\])?$') }
        if ($m.Success -and -not $seen.ContainsKey($m.Value)) {
            $seen[$m.Value] = $true
            [ordered]@{ file = $m.Groups['file'].Value
                line = $m.Groups['line'].Success ? [int]$m.Groups['line'].Value : $null
                column = $m.Groups['col'].Success ? [int]$m.Groups['col'].Value : $null
                code = $m.Groups['code'].Value; message = $m.Groups['msg'].Value.Trim() }
        }
    }
}

# Where a failure happened: the first .cs/.gd location with a line number in the text, as an absolute path (C# stack
# traces) or a res:// path (Godot backtraces). Frames inside addons/ (GUT, gdUnit4) are the framework, not the failure.
# A .NET frame's path ("in C:\Users\Jane Doe\game\Test.cs:line 12") may hold spaces, so after " in " the path runs to
# the first .cs:line N.
function Get-FailureLocation([string]$Text) {
    $pattern = '(?<![\w:/])(?<file>(?:[A-Za-z]:[\\/]|/)[^\s:]+\.(?:cs|gd))(?::line |:)(?<line>\d+)|(?<=\bin )(?<file>(?:[A-Za-z]:[\\/]|/)[^:\r\n]+?\.cs):line (?<line>\d+)|res://(?<res>[^\s:()]+\.(?:gd|cs|tscn|tres)):(?<rline>\d+)'
    $inAddon = $null
    foreach ($m in [regex]::Matches($Text, $pattern)) {
        if ($m.Groups['res'].Success) {
            if ($m.Groups['res'].Value -like 'addons/*') {
                # Only the testing frameworks' own frames are never the failure; another add-on's file is better than none
                # (an autoload in addons/ that fails at startup).
                if (-not $inAddon -and $m.Groups['res'].Value -notmatch '^addons/(gut|gdUnit4|gdunit4)/') { $inAddon = [pscustomobject]@{ File = $m.Groups['res'].Value; Line = [int]$m.Groups['rline'].Value } }
                continue
            }
            return [pscustomobject]@{ File = $m.Groups['res'].Value; Line = [int]$m.Groups['rline'].Value }
        }
        $file = $m.Groups['file'].Value
        if ($file -match '[\\/]addons[\\/]') { continue }
        if ($env:GITHUB_WORKSPACE) {
            $relative = [System.IO.Path]::GetRelativePath($env:GITHUB_WORKSPACE, $file)
            if (-not $relative.StartsWith('..')) { $file = $relative -replace '\\', '/' }
        }
        return [pscustomobject]@{ File = $file; Line = [int]$m.Groups['line'].Value }
    }
    return $inAddon
}

# Edits (insert, delete, substitute, swap two neighbours) between two names, ignoring case; anything above $Max comes back
# as $Max + 1. The same measure as Example.Core's Suggest.Distance (docs/algorithms.md).
function Get-EditDistance([string]$A, [string]$B, [int]$Max = 1000) {
    $A = $A.ToUpperInvariant(); $B = $B.ToUpperInvariant()
    $Max = [Math]::Min($Max, [Math]::Max($A.Length, $B.Length))
    if ([Math]::Abs($A.Length - $B.Length) -gt $Max) { return $Max + 1 }
    $before = [int[]]::new($B.Length + 1); $previous = [int[]]::new($B.Length + 1); $current = [int[]]::new($B.Length + 1)
    for ($j = 0; $j -le $B.Length; $j++) { $previous[$j] = $j }
    for ($i = 1; $i -le $A.Length; $i++) {
        $current[0] = $i; $rowBest = $i
        for ($j = 1; $j -le $B.Length; $j++) {
            $d = [Math]::Min([Math]::Min($previous[$j] + 1, $current[$j - 1] + 1), $previous[$j - 1] + [int]($A[$i - 1] -cne $B[$j - 1]))
            if ($i -gt 1 -and $j -gt 1 -and $A[$i - 1] -ceq $B[$j - 2] -and $A[$i - 2] -ceq $B[$j - 1]) { $d = [Math]::Min($d, $before[$j - 2] + 1) }
            $current[$j] = $d
            if ($d -lt $rowBest) { $rowBest = $d }
        }
        if ($rowBest -gt $Max) { return $Max + 1 }
        $before, $previous, $current = $previous, $current, $before
    }
    return [Math]::Min($previous[$B.Length], $Max + 1)
}

# "Did you mean": the candidate closest to a mistyped name, or $null when none is near enough to be the same word (one edit
# up to six letters, two up to nine, ...). The first of equally close candidates wins.
function Get-ClosestName([string]$Typed, [string[]]$Candidates) {
    $max = [Math]::Max(1, [Math]::Floor(($Typed.Length - 1) / 3))
    $best = $null; $bestDistance = $max + 1
    foreach ($candidate in $Candidates) {
        $d = Get-EditDistance $Typed $candidate ([Math]::Min($max, $bestDistance))
        if ($d -lt $bestDistance) { $best = $candidate; $bestDistance = $d }
        if ($bestDistance -eq 0) { break }
    }
    return $best
}

# The sets of values hyperdot.ps1's parameters take, read from its param block: parameter name -> its values. The sets are
# [ArgumentCompletions] (tab completion, which PowerShell does not enforce while it binds), so a wrong value reaches the
# script, where Assert-KitArguments answers it; the help, the skill and context checks and the coverage report read the
# same attributes, so each set is written once.
function Get-KitParameterSets($ParamBlock) {
    $sets = [ordered]@{}
    foreach ($p in $ParamBlock.Parameters) {
        $attribute = @($p.Attributes | Where-Object { $_.TypeName.Name -in 'ArgumentCompletions', 'ValidateSet' })
        if ($attribute.Count) { $sets[$p.Name.VariablePath.UserPath] = @($attribute[0].PositionalArguments | ForEach-Object { "$($_.Value)" }) }
    }
    return $sets
}

# The flag a parameter is written as: its alias when it has one (-Profile binds to $PlanProfile), else its name.
function Get-KitFlagName($Parameter) {
    $alias = @($Parameter.Attributes | Where-Object { $_.TypeName.Name -eq 'Alias' } | ForEach-Object { $_.PositionalArguments } | ForEach-Object { $_.Value })
    if ($alias.Count) { return $alias[0] }
    return $Parameter.Name.VariablePath.UserPath
}

# What PowerShell would have refused before the script started, refused here with invalid-arguments so -Json still gives
# one document: a flag hyperdot.ps1 does not have, a word too many, a command or a value outside its set. (A flag left
# without its value, or a value of the wrong type such as -Retry abc, still fails in PowerShell's binding.)
function Assert-KitArguments($ParamBlock, [hashtable]$Bound) {
    $flags = @{}   # variable name -> the flag as written
    foreach ($p in $ParamBlock.Parameters) { if ($p.Name.VariablePath.UserPath -ne 'UnboundArguments') { $flags[$p.Name.VariablePath.UserPath] = Get-KitFlagName $p } }
    $names = @($flags.Values | Sort-Object)
    if ($Bound.ContainsKey('UnboundArguments')) {
        $words = @($Bound['UnboundArguments'] | ForEach-Object { "$_" })
        $flag = @($words | Where-Object { $_ -match '^-[A-Za-z]' })
        if ($flag.Count) {
            $name = $flag[0].TrimStart('-').TrimEnd(':')
            $closest = Get-ClosestName $name.ToLowerInvariant() @($names | ForEach-Object { $_.ToLowerInvariant() })
            $suggestion = if ($closest) { " (did you mean -$(@($names | Where-Object { $_ -eq $closest })[0])?)" } else { '' }
            Stop-GodotCi "-$name is not a parameter of hyperdot.ps1$suggestion; docs/reference.md lists them all" 'invalid-arguments'
        }
        $gameFlag = @($words | Where-Object { $_.StartsWith('--') })
        if ($gameFlag.Count) {
            Stop-GodotCi "'$($gameFlag[0])' belongs to no parameter: the game's own flags go to -GameArgs as one list, e.g. -GameArgs '--seed=3','$($gameFlag[0])'" 'invalid-arguments'
        }
        Stop-GodotCi "'$($words -join ' ')' belongs to no parameter: name the parameter it is for (e.g. -Project <folder>) and quote a value with spaces" 'invalid-arguments'
    }
    $sets = Get-KitParameterSets $ParamBlock
    foreach ($name in $sets.Keys) {
        if (-not $Bound.ContainsKey($name)) { continue }
        $value = "$($Bound[$name])"
        if ($value -in $sets[$name]) { continue }
        $closest = if ($value -match "[A-Za-z]") { Get-ClosestName $value.ToLowerInvariant() $sets[$name] } else { $null }
        $suggestion = if ($closest) { " (did you mean ${closest}?)" } else { '' }
        if ($name -eq 'Command') { Stop-GodotCi "'$value' is not a command of hyperdot.ps1$suggestion; the commands: $($sets[$name] -join ', ')" 'invalid-arguments' }
        Stop-GodotCi "-$($flags[$name]) $value is not one of: $($sets[$name] -join ', ')$suggestion" 'invalid-arguments'
    }
}

# A build that cannot write its output because a process still holds it (a game a bot run left open keeps its dll):
# MSBuild reports MSB3027 or MSB3021, or the operating system's own words, and `dotnet test` then fails with no test
# result at all. The text for the first such line, naming the file and, when MSBuild says, the process holding it; $null
# when the lines hold none.
function Get-LockedFileProblem([string[]]$Lines) {
    foreach ($line in $Lines) {
        $m = [regex]::Match($line, 'MSB3027: Could not copy "(?<src>[^"]+)" to "(?<dst>[^"]+)"\..*?locked by: "(?<who>[^"]+)"')
        if ($m.Success) { return "the build could not write $($m.Groups['dst'].Value): it is locked by $($m.Groups['who'].Value); close that process (a game a bot run left open?) and run again" }
        $m = [regex]::Match($line, "(?:MSB3021|MSB3027)[^']*(?:Unable to copy file|Could not copy) ""(?<src>[^""]+)"" to ""(?<dst>[^""]+)""[^']*'(?<file>[^']+)' because it is being used by another process")
        if ($m.Success) { return "the build could not write $($m.Groups['dst'].Value): '$($m.Groups['file'].Value)' is being used by another process; close it (a game a bot run left open?) and run again" }
        $m = [regex]::Match($line, "The process cannot access the file '(?<file>[^']+)' because it is being used by another process")
        if ($m.Success) { return "the build could not write '$($m.Groups['file'].Value)': it is being used by another process; close it (a game a bot run left open?) and run again" }
    }
    return $null
}
