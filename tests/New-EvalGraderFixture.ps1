#Requires -Version 7.6
<#
.SYNOPSIS
Makes a grader fixture for tests/Test-EvalGraders.ps1 from one run of a real `claude plugin eval` result.

.DESCRIPTION
Reads the Evals workflow's artifact: result.json (or aggregate-result.json) and, when the run kept it, the run's
transcript (traces/<case>-<arm>-<n>.jsonl). The fixture keeps what the free graders read: the tool calls (name and input),
the last message, and the files the regex graders read, replayed from the session's Edit and Write calls on -StartFiles
(a file changed by a shell command is not replayed). Without a transcript the last message comes from a model grader's
evidence, which is the whole answer, and the tool calls stay unknown.

It also records each free grader's verdict in that run with the grader's configuration then, so the self-test can show
its stand-in reproduces `claude plugin eval`. -Expect is the person's judgement of the session, grader by grader
("<case>/<grader>" = true or false), which the graders as they are now must agree with.

.EXAMPLE
pwsh tests/New-EvalGraderFixture.ps1 -Result run6/result.json -Trace run6/traces/fix-score-bug-with-1.jsonl -Case fix-score-bug -Arm with -Run 1 -StartFiles @{ 'score.gd' = 'start/score.gd' } -Expect @{ 'fix-score-bug/fixed' = $true } -Source 'Evals run 6' -Note '...' -Out tests/eval-grader-fixtures/fix-score-bug/run6-with-1.json
#>
[CmdletBinding(PositionalBinding = $false)]
param(
    [Parameter(Mandatory)][string]$Result,
    [string]$Trace,
    [Parameter(Mandatory)][string]$Case,
    [Parameter(Mandatory)][ValidateSet('with', 'without')][string]$Arm,
    [Parameter(Mandatory)][int]$Run,
    # Workspace files as the scaffold left them (name in the workspace = file on disk), for the Edit and Write replay.
    [hashtable]$StartFiles = @{},
    [Parameter(Mandatory)][hashtable]$Expect,
    # Names the kit has had since the run ("old" = "new"), applied before the graders as they are now judge the session.
    [hashtable]$Rename = @{},
    [Parameter(Mandatory)][string]$Source,
    [Parameter(Mandatory)][string]$Note,
    [Parameter(Mandatory)][string]$Out
)
Set-StrictMode -Version 3.0
$ErrorActionPreference = 'Stop'

$doc = Get-Content -LiteralPath $Result -Raw | ConvertFrom-Json -Depth 50
$caseDoc = @($doc.cases | Where-Object { $_.name -eq $Case })
if ($caseDoc.Count -ne 1) { throw "No case '$Case' in $Result" }
$runs = @($caseDoc[0].arms.$Arm)
if ($Run -lt 1 -or $Run -gt $runs.Count) { throw "Case '$Case' has $($runs.Count) run(s) in the $Arm arm, not $Run" }
$runDoc = $runs[$Run - 1]

$tools = $null; $lastMessage = $null
if ($Trace) {
    $tools = [System.Collections.Generic.List[object]]::new()
    foreach ($line in [System.IO.File]::ReadLines((Resolve-Path -LiteralPath $Trace))) {
        if (-not $line.Trim()) { continue }
        $entry = $line | ConvertFrom-Json -Depth 50
        if ($entry.type -eq 'assistant') {
            foreach ($block in @($entry.message.content)) {
                if ($block.type -eq 'tool_use') { $tools.Add([ordered]@{ name = $block.name; input = $block.input }) }
            }
        } elseif ($entry.type -eq 'result' -and $entry.PSObject.Properties['result']) { $lastMessage = [string]$entry.result }
    }
} else {
    # A model grader's evidence is the session's whole last message (the same text as the transcript's result).
    $evidence = @($runDoc.graders | Where-Object { $_.PSObject.Properties['evidence'] -and $_.evidence } | ForEach-Object evidence)
    if ($evidence.Count) { $lastMessage = [string]$evidence[0] }
}
if ($null -eq $lastMessage) { throw "No last message for $Case/$Arm/$Run`: give -Trace, or use a run with a model grader's evidence" }

# The files the regex graders read, as the session left them: the scaffold's, then its Edit and Write calls in order.
$files = [ordered]@{}
foreach ($name in $StartFiles.Keys) { $files[$name] = [System.IO.File]::ReadAllText((Resolve-Path -LiteralPath $StartFiles[$name])) }
if ($null -ne $tools) {
    foreach ($call in $tools) {
        if ($call.name -notin 'Edit', 'Write' -or -not $call.input.PSObject.Properties['file_path']) { continue }
        $name = Split-Path ([string]$call.input.file_path) -Leaf
        if ($call.name -eq 'Write') { $files[$name] = [string]$call.input.content; continue }
        if (-not $files.Contains($name)) { continue }
        $old = [string]$call.input.old_string; $new = [string]$call.input.new_string
        $text = [string]$files[$name]; $at = $text.IndexOf($old, [StringComparison]::Ordinal)
        if ($at -lt 0) { continue }
        $all = $call.input.PSObject.Properties['replace_all'] -and $call.input.replace_all
        $files[$name] = if ($all) { $text.Replace($old, $new) } else { $text.Substring(0, $at) + $new + $text.Substring($at + $old.Length) }
    }
}

# The free graders' verdicts in that run, each with its configuration then.
$recorded = [System.Collections.Generic.List[object]]::new()
foreach ($grader in @($caseDoc[0].graders | Where-Object { $_.type -in 'regex', 'tool_used' })) {
    $verdict = @($runDoc.graders | Where-Object { $_.name -eq $grader.name })
    if ($verdict.Count -ne 1) { continue }
    if ($grader.type -eq 'tool_used' -and $null -eq $tools) { continue }
    $recorded.Add([ordered]@{ grader = $grader.name; type = $grader.type; config = $grader.config; passed = [bool]$verdict[0].passed; explanation = [string]$verdict[0].explanation })
}

$expectOut = [ordered]@{}
foreach ($k in @($Expect.Keys | Sort-Object)) {
    if ($k -notmatch '^[\w-]+/[\w-]+$') { throw "-Expect keys are <case>/<grader>, not '$k'" }
    $expectOut[$k] = [bool]$Expect[$k]
}
$fixture = [ordered]@{
    schema = 'hyperdot-eval-grader-fixture/1'; case = $Case; arm = $Arm; run = $Run; source = $Source; note = $Note
    rename = $Rename; expect = $expectOut; recorded = $recorded.ToArray(); lastMessage = $lastMessage; tools = $null; files = $files
}
# Assigned, not written in the literal: a subexpression would turn a session with no tool calls into no transcript.
if ($null -ne $tools) { $fixture.tools = $tools.ToArray() }
New-Item -ItemType Directory -Force -Path (Split-Path $Out -Parent) | Out-Null
$fixture | ConvertTo-Json -Depth 50 | Set-Content -LiteralPath $Out -Encoding utf8NoBOM
Write-Host "Wrote $Out ($(if ($null -ne $tools) { "$($tools.Count) tool call(s)" } else { 'no transcript' }), $($recorded.Count) recorded verdict(s))"
