# The `juice` runner: plays the game headless with a bot for a while and checks that every gameplay event got its feedback in
# time. The game prints one line per event and per feedback, with its game time in milliseconds:
#   [juice] event brick_hit 1234.5
#   [juice] feedback flash 1240.1
# and juice.json in the project says what must follow what:
#   { "frames": 1800, "args": ["--autoplay"], "rules": [ { "event": "brick_hit", "feedback": ["flash", "sfx"], "withinMs": 100 } ] }
# The run uses --fixed-fps 60, so game time advances the same on every machine and the bot's run is reproducible.
# A game whose events happen on different stages lists several runs instead, each played and judged on its own:
#   { "runs": [ { "name": "boss", "args": ["--stage=boss"], "frames": 7200, "rules": [...] },
#               { "name": "act2", "args": ["--stage=act2"], "rules": [...] } ] }

# One run of juice.json, checked: its rules, frames (default 1800) and args. $Where names it in error messages.
function Get-JuiceRun($Run, [string]$Name, [string]$Where) {
    if ($Run -isnot [System.Collections.IDictionary]) { Stop-GodotCi "juice.json $Where must be an object with ""rules""" 'invalid-arguments' }
    if (-not $Run.Contains('rules') -or @($Run.rules).Count -eq 0) { Stop-GodotCi "juice.json $Where needs ""rules"": [ { ""event"", ""feedback"", ""withinMs"" } ]" 'invalid-arguments' }
    foreach ($rule in $Run.rules) {
        if ($rule -isnot [System.Collections.IDictionary] -or -not $rule.Contains('event') -or -not $rule.Contains('feedback')) { Stop-GodotCi "Each juice.json rule needs ""event"" and ""feedback"" ($Where)" 'invalid-arguments' }
    }
    # Godot's --quit-after 0 means never quit: the run would hang until the time limit.
    if ($Run.Contains('frames') -and ("$($Run.frames)" -notmatch '^\d+$' -or [long]$Run.frames -le 0)) {
        Stop-GodotCi "juice.json ""frames"" must be a whole number above 0, not $($Run.frames | ConvertTo-Json -Depth 10 -Compress) ($Where)" 'invalid-arguments'
    }
    return [ordered]@{
        name = $Name; rules = @($Run.rules); frames = $(if ($Run.Contains('frames')) { [int]$Run.frames } else { 1800 })
        args = @($(if ($Run.Contains('args')) { @($Run.args) } else { @() }) | ForEach-Object { "$_" } | Where-Object { $_ })
    }
}

# juice.json as a list of runs: the one-run form (rules, frames and args at the top) is a single run with no name.
function Get-JuiceConfig([string]$ProjectDir) {
    $file = Join-Path $ProjectDir 'juice.json'
    if (-not (Test-Path -LiteralPath $file)) { return $null }
    try { $config = Get-Content -LiteralPath $file -Raw | ConvertFrom-Json -AsHashtable }
    catch { Stop-GodotCi "juice.json is not valid JSON: $($_.Exception.Message)" 'invalid-arguments' }
    if ($config -isnot [System.Collections.IDictionary]) { Stop-GodotCi 'juice.json must be an object with "rules" or "runs"' 'invalid-arguments' }
    if (-not $config.Contains('runs')) { return [ordered]@{ runs = @(Get-JuiceRun $config '' 'the top level') } }
    foreach ($key in 'rules', 'frames', 'args') {
        if ($config.Contains($key)) { Stop-GodotCi "juice.json has both ""runs"" and a top-level ""$key"": move ""$key"" into each run" 'invalid-arguments' }
    }
    if (@($config.runs).Count -eq 0) { Stop-GodotCi 'juice.json "runs" is empty: list at least one run with its "rules"' 'invalid-arguments' }
    $runs = [System.Collections.Generic.List[object]]::new()
    $index = 0
    foreach ($run in @($config.runs)) {
        $index++
        $name = if ($run -is [System.Collections.IDictionary] -and $run.Contains('name')) { "$($run.name)" } else { "run$index" }
        # The name goes into a log file name and each JUnit case name.
        if ($name -notmatch '^[A-Za-z0-9._-]+$') { Stop-GodotCi "juice.json run $index has the name '$name': use letters, digits, dots, hyphens and underscores" 'invalid-arguments' }
        if (@($runs | Where-Object { $_.name -eq $name }).Count) { Stop-GodotCi "juice.json has two runs named '$name': give each its own ""name""" 'invalid-arguments' }
        $runs.Add((Get-JuiceRun $run $name "run '$name'"))
    }
    return [ordered]@{ runs = @($runs) }
}

# How many rules juice.json holds, over all its runs (status's look.juiceRules).
function Get-JuiceRuleCount($Config) {
    if (-not $Config) { return 0 }
    return [int](@($Config.runs | ForEach-Object { @($_.rules).Count }) | Measure-Object -Sum).Sum
}

# One JUnit case per rule (and per feedback it requires): failed when an event had no such feedback within the window, or when
# the event never happened (the bot never reached it, so nothing was checked).
function Test-JuiceLog([string[]]$Lines, $Config, [int]$Frames) {
    $events = @{}; $feedback = @{}
    foreach ($line in $Lines) {
        if ($line -match '^\s*\[juice\]\s+(?<kind>event|feedback)\s+(?<name>\S+)\s+(?<ms>-?\d+(?:\.\d+)?)\s*$') {
            $table = if ($Matches.kind -eq 'event') { $events } else { $feedback }
            if (-not $table.ContainsKey($Matches.name)) { $table[$Matches.name] = [System.Collections.Generic.List[double]]::new() }
            $table[$Matches.name].Add([double]::Parse($Matches.ms, [cultureinfo]::InvariantCulture))
        }
    }
    # At --fixed-fps 60 the run ends at a known game time; an event too close to the end had no chance to be answered.
    $endMs = $Frames * 1000.0 / 60
    $cases = [System.Collections.Generic.List[object]]::new()
    foreach ($rule in $Config.rules) {
        $within = if ($rule.Contains('withinMs')) { [double]$rule.withinMs } else { 100 }
        $times = @($events.ContainsKey($rule.event) ? @($events[$rule.event]) : @() | Where-Object { $_ + $within -lt $endMs })
        foreach ($name in @($rule.feedback)) {
            $caseName = "$($rule.event) -> $name within $within ms"
            if ($times.Count -eq 0) {
                $cases.Add(@{ Name = $caseName; Failure = "No '$($rule.event)' event in $Frames frames, so its feedback was never checked; does the bot reach it (juice.json ""args"", ""frames"")?" })
                continue
            }
            $answers = $feedback.ContainsKey($name) ? @($feedback[$name]) : @()
            $missed = @($times | Where-Object { $t = $_; -not ($answers | Where-Object { $_ -ge $t -and $_ -le $t + $within }) })
            $failure = if ($missed.Count -gt 0) {
                "$($missed.Count) of $($times.Count) '$($rule.event)' events had no '$name' within $within ms (first at $([math]::Round($missed[0], 1)) ms)"
            } else { '' }
            $cases.Add(@{ Name = $caseName; Failure = $failure })
        }
    }
    return $cases
}

# What the run itself adds to the rule cases: a failure, or a warning (Get-ShutdownCrashVerdict says when a crash is only a warning).
function Get-JuiceRunVerdict([int]$Code, [string[]]$Lines, [object[]]$Cases) {
    $fatal = [array]::FindIndex($Lines, [Predicate[string]]{ param($l) $l -match 'FATAL:' })
    $before = if ($fatal -ge 0) { @($Lines[0..([Math]::Max(0, $fatal - 1))]) } else { @($Lines) }
    $judgedAll = @($Cases | Where-Object { $_.Failure }).Count -eq 0
    return Get-ShutdownCrashVerdict $Code $Lines $judgedAll @(Select-GodotErrors $before) 'rule'
}

# Plays every run of juice.json and judges each on its own. One run keeps the plain names (case "run", juice.log); with
# several, each case starts with its run's name ("boss: run", "boss: hit -> flash within 100 ms") and each has its own log.
function Invoke-JuiceRunner($Info, [string]$ResultsDir, [string[]]$GameArgs) {
    $config = Get-JuiceConfig $Info.ProjectDir
    if (-not $config) { Stop-GodotCi "juice runner: no juice.json in $($Info.ProjectDir)" 'invalid-arguments' }
    $allCases = [System.Collections.Generic.List[object]]::new()
    $failed = $false
    foreach ($run in $config.runs) {
        $prefix = if ($run.name) { "$($run.name): " } else { '' }
        $gameArgs = @(@($run.args) + @($GameArgs) | Where-Object { $_ })
        $log = Join-Path $ResultsDir $(if ($run.name) { "juice-$($run.name).log" } else { 'juice.log' })
        Start-LogGroup "Juice $(if ($run.name) { "$($run.name) " })($($run.frames) frames$(if ($gameArgs) { ', ' + ($gameArgs -join ' ') }))"
        $engine = @('--headless', '--path', $Info.ProjectDir, '--fixed-fps', '60', '--quit-after', "$($run.frames)")
        $attempt = 0
        do {
            $attempt++
            $code = Invoke-Logged $env:GODOT_BIN ($engine + $(if ($gameArgs) { @('--') + $gameArgs })) $log
            $cases = @(Test-JuiceLog @(Get-Content -LiteralPath $log) $run $run.frames)
            $verdict = Get-JuiceRunVerdict $code @(Get-Content -LiteralPath $log) $cases
            # A crash that cost a rule its verdict may be the engine's, not the game's: the run is repeated once, and a second crash fails.
            $again = $verdict.Failure -and (Test-GodotCrashCode $code) -and $attempt -lt 2
            if ($again) { Write-CiLog "Godot crashed during the juice run $(if ($run.name) { "'$($run.name)' " })(exit $code) before every rule was judged; running it once more" }
        } while ($again)
        Stop-LogGroup
        if ($verdict.Warning) { Write-CiLog "WARN: $prefix$($verdict.Warning)" }
        # As with one run, a failed rule counts through its JUnit case; the exit code says whether a run itself failed.
        if ($verdict.Failure) { $failed = $true }
        $allCases.Add(@{ Name = "${prefix}run"; Failure = $verdict.Failure })
        foreach ($case in $cases) { $allCases.Add(@{ Name = "$prefix$($case.Name)"; Failure = $case.Failure }) }
    }
    Write-JUnitCases (Join-Path $ResultsDir 'juice.junit.xml') 'juice' @($allCases)
    return ($failed ? 1 : 0)
}
