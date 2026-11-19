#Requires -Version 7.6
# Self-test for the juice runner's log check, without Godot: feedback in time passes, late or missing feedback fails, an
# event that never happens fails, an event at the very end of the run is not held against the game, and "frames": 0 is
# refused; several runs per juice.json are read, named and checked, and their mistakes refused.
$ErrorActionPreference = 'Stop'
Set-StrictMode -Version 3.0
$root = Split-Path $PSScriptRoot
foreach ($lib in 'Common', 'Juice') { . (Join-Path $root "ci/godot/lib/$lib.ps1") }
$config = @{ rules = @(@{ event = 'hit'; feedback = @('flash', 'sfx'); withinMs = 100 }, @{ event = 'death'; feedback = @('shake') }) }
$frames = 300   # 5000 ms of game time at 60 fps
$lines = @(
    '[juice] event hit 1000.0', '[juice] feedback flash 1016.7', '[juice] feedback sfx 1000.0',
    '[juice] event hit 2000.0', '[juice] feedback flash 2250.0', '[juice] feedback sfx 2033.3',
    'unrelated output', '[juice] event hit 4950.0'
)
$cases = @(Test-JuiceLog $lines $config $frames)
$byName = @{}; foreach ($case in $cases) { $byName[$case.Name] = $case.Failure }
$failed = 0
function Assert-Case([string]$Name, [string]$Pattern) {
    $failure = $byName[$Name]
    $ok = if ($Pattern) { $failure -match $Pattern } else { -not $failure }
    if ($ok) { Write-Host "ok       $Name" } else { Write-Host "WRONG    $Name -> '$failure'" -ForegroundColor Red; $script:failed++ }
}
Assert-Case 'hit -> flash within 100 ms' "^1 of 2 'hit' events had no 'flash'.*2000"
Assert-Case 'hit -> sfx within 100 ms' ''
Assert-Case 'death -> shake within 100 ms' "^No 'death' event"
# "frames": 0 would be Godot's --quit-after 0, which never quits: juice.json refuses it.
$temp = Join-Path ([System.IO.Path]::GetTempPath()) "juice-$([guid]::NewGuid().ToString('n').Substring(0, 8))"
New-Item -ItemType Directory $temp | Out-Null
Set-Content -LiteralPath (Join-Path $temp 'juice.json') '{ "frames": 0, "rules": [ { "event": "hit", "feedback": ["flash"] } ] }'
$refused = & pwsh -NoProfile -NonInteractive -Command ". '$root/ci/godot/lib/Common.ps1'; . '$root/ci/godot/lib/Juice.ps1'; try { Get-JuiceConfig '$temp' | Out-Null; 'accepted' } catch { `$_.Exception.Message }" 2>&1 | Out-String
Remove-Item -Recurse -Force $temp
if ($refused -match '"frames" must be a whole number above 0') { Write-Host 'ok       juice.json "frames": 0 is refused' }
else { Write-Host "WRONG    juice.json ""frames"": 0 should be refused -> '$($refused.Trim())'" -ForegroundColor Red; $failed++ }

# Several runs (stages) per juice.json: each with its own args, frames and rules; the one-run form stays as it was.
$temp = Join-Path ([System.IO.Path]::GetTempPath()) "juice-$([guid]::NewGuid().ToString('n').Substring(0, 8))"
New-Item -ItemType Directory $temp | Out-Null
function Assert-True([bool]$Condition, [string]$Name) {
    if ($Condition) { Write-Host "ok       $Name" } else { Write-Host "WRONG    $Name" -ForegroundColor Red; $script:failed++ }
}
function Read-JuiceJson([string]$Json) {
    Set-Content -LiteralPath (Join-Path $temp 'juice.json') $Json
    return Get-JuiceConfig $temp
}
function Get-JuiceRefusal([string]$Json) {
    Set-Content -LiteralPath (Join-Path $temp 'juice.json') $Json
    return (& pwsh -NoProfile -NonInteractive -Command ". '$root/ci/godot/lib/Common.ps1'; . '$root/ci/godot/lib/Juice.ps1'; try { Get-JuiceConfig '$temp' | Out-Null; 'accepted' } catch { `$_.Exception.Message }" 2>&1 | Out-String).Trim()
}
try {
    $one = Read-JuiceJson '{ "args": ["--autoplay"], "rules": [ { "event": "hit", "feedback": ["flash"] } ] }'
    Assert-True (@($one.runs).Count -eq 1 -and $one.runs[0].name -eq '' -and $one.runs[0].frames -eq 1800 -and ($one.runs[0].args -join ' ') -eq '--autoplay') 'the one-run form is one run with no name, 1800 frames by default and its args'
    $two = Read-JuiceJson '{ "runs": [ { "name": "boss", "args": ["--stage=boss"], "frames": 7200, "rules": [ { "event": "slow", "feedback": ["sfx"] }, { "event": "mend", "feedback": ["flash"] } ] }, { "args": ["--stage=act2"], "rules": [ { "event": "blast", "feedback": ["shake"] } ] } ] }'
    Assert-True (@($two.runs).Count -eq 2 -and $two.runs[0].name -eq 'boss' -and $two.runs[0].frames -eq 7200 -and $two.runs[1].name -eq 'run2' -and $two.runs[1].frames -eq 1800 -and ($two.runs[1].args -join ' ') -eq '--stage=act2') "runs keep their own name (run<n> when unnamed), frames and args: $(@($two.runs | ForEach-Object { "$($_.name)/$($_.frames)" }) -join ', ')"
    Assert-True ((Get-JuiceRuleCount $two) -eq 3 -and (Get-JuiceRuleCount $one) -eq 1 -and (Get-JuiceRuleCount $null) -eq 0) 'the rule count (status look.juiceRules) adds up every run'
    $boss = @(Test-JuiceLog @('[juice] event slow 100.0', '[juice] feedback sfx 110.0') $two.runs[0] $two.runs[0].frames)
    Assert-True ($boss.Count -eq 2 -and -not $boss[0].Failure -and $boss[1].Failure -match "^No 'mend' event") 'each run is judged on its own rules'
    foreach ($case in @(
            @('{ "runs": [ { "rules": [ { "event": "a", "feedback": ["b"] } ] } ], "rules": [ { "event": "a", "feedback": ["b"] } ] }', 'both "runs" and a top-level "rules"', 'runs and top-level rules together'),
            @('{ "runs": [] }', '"runs" is empty', 'an empty runs list'),
            @('{ "runs": [ { "name": "x", "rules": [ { "event": "a", "feedback": ["b"] } ] }, { "name": "x", "rules": [ { "event": "a", "feedback": ["b"] } ] } ] }', "two runs named 'x'", 'two runs with one name'),
            @('{ "runs": [ { "name": "boss fight", "rules": [ { "event": "a", "feedback": ["b"] } ] } ] }', "the name 'boss fight'", 'a name that cannot be a file name'),
            @('{ "runs": [ { "name": "x", "args": ["--y"] } ] }', "run 'x' needs ""rules""", 'a run without rules'),
            @('{ "runs": [ { "name": "x", "frames": 0, "rules": [ { "event": "a", "feedback": ["b"] } ] } ] }', 'must be a whole number above 0, not 0 \(run ''x''\)', 'frames 0 in a run'))) {
        $message = Get-JuiceRefusal $case[0]
        Assert-True ($message -match $case[1]) "refused: $($case[2]) -> $message"
    }
} finally { Remove-Item -LiteralPath $temp -Recurse -Force -ErrorAction SilentlyContinue }
# Godot crashing in its shutdown after every rule was judged is a warning; a crash before that, or an engine error, still fails.
$ok = @(@{ Name = 'hit -> flash'; Failure = '' })
$bad = @(@{ Name = 'hit -> flash'; Failure = "1 of 2 'hit' events had no 'flash'" })
$teardown = @('[juice] event hit 1000.0', '[juice] feedback flash 1010.0', 'FATAL: Condition "csharp_lang && !csharp_lang->script_bindings.is_empty()" is true.', 'ERROR: Leaked unsafe reference to object 1234')
function Assert-Verdict([string]$Name, $Verdict, [bool]$Fails, [string]$WarningPattern) {
    $ok = ([bool]$Verdict.Failure -eq $Fails) -and (($WarningPattern -and $Verdict.Warning -match $WarningPattern) -or (-not $WarningPattern -and -not $Verdict.Warning))
    if ($ok) { Write-Host "ok       $Name" } else { Write-Host "WRONG    $Name -> failure '$($Verdict.Failure)' warning '$($Verdict.Warning)'" -ForegroundColor Red; $script:failed++ }
}
Assert-Verdict 'a clean exit passes' (Get-JuiceRunVerdict 0 $teardown[0..1] $ok) $false ''
Assert-Verdict 'exit 134 in the teardown after every rule passed is a warning with the FATAL line' (Get-JuiceRunVerdict 134 $teardown $ok) $false 'exit 134\) after every rule was judged: FATAL: Condition'
Assert-Verdict 'a Windows crash code after every rule passed is a warning too' (Get-JuiceRunVerdict -1073741819 $teardown $ok) $false 'after every rule was judged'
Assert-Verdict 'a crash with a rule not judged still fails' (Get-JuiceRunVerdict 134 $teardown $bad) $true ''
Assert-Verdict 'an ordinary nonzero exit still fails' (Get-JuiceRunVerdict 1 $teardown $ok) $true ''
$early = @('SCRIPT ERROR: Parse Error: bad thing', '[juice] event hit 1000.0', '[juice] feedback flash 1010.0', 'FATAL: x')
Assert-Verdict 'a crash after an engine error before the FATAL line still fails' (Get-JuiceRunVerdict 134 $early $ok) $true ''
exit ($failed -gt 0 ? 1 : 0)
