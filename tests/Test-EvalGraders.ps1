#Requires -Version 7.6
<#
.SYNOPSIS
Self-test: the eval graders that need no model (regex and tool_used) against real sessions from past Evals runs.

.DESCRIPTION
Each fixture in tests/eval-grader-fixtures/<case>/ is one real session from an Evals run (tests/New-EvalGraderFixture.ps1
makes them from the workflow's artifact): its tool calls, its last message and the files its regex graders read, the
verdicts `claude plugin eval` gave it then, and what a person judged each grader should say about it.

1. The stand-in below gives every recorded verdict again, with the grader's configuration then: it reads the session as
   `claude plugin eval` does.
2. Every regex and tool_used grader in evals/*/graders, as it is now, agrees with the person on every fixture that names
   it ("<case>/<grader>" in expect).
3. Every such grader has a real session it must pass and one it must fail, unless gaps.json says why there is none yet.

Model graders (type llm) need a model and are not checked here.
#>
[CmdletBinding()] param()
Set-StrictMode -Version 3.0
$ErrorActionPreference = 'Stop'
$root = Split-Path $PSScriptRoot -Parent
$fixtureRoot = Join-Path $PSScriptRoot 'eval-grader-fixtures'
$failures = [System.Collections.Generic.List[string]]::new()
function Assert-True([bool]$Condition, [string]$Message) {
    if ($Condition) { Write-Host "ok     $Message" } else { Write-Host "FAIL   $Message"; $failures.Add($Message) }
}

# A grader file's front matter: key: value lines, single-quoted strings ('' is a quote), numbers, and one-line maps
# such as { source: file, path: score.gd }.
function ConvertFrom-GraderValue([string]$Text) {
    $t = $Text.Trim()
    if ($t -match "^'(.*)'$") { return $Matches[1].Replace("''", "'") }
    if ($t -match '^"(.*)"$') { return $Matches[1] }
    if ($t -match '^-?\d+$') { return [int]$t }
    if ($t -match '^\{(.*)\}$') {
        $map = [ordered]@{}
        foreach ($pair in @($Matches[1] -split ',')) {
            if ($pair -notmatch '^\s*([\w-]+)\s*:\s*(.*?)\s*$') { throw "Cannot read '$pair' in '$Text'" }
            $map[$Matches[1]] = ConvertFrom-GraderValue $Matches[2]
        }
        return $map
    }
    return $t
}
function Read-Grader([string]$Path) {
    $lines = @(Get-Content -LiteralPath $Path)
    if ($lines.Count -lt 2 -or $lines[0] -ne '---') { throw "$Path has no front matter" }
    $config = [ordered]@{}
    for ($i = 1; $i -lt $lines.Count -and $lines[$i] -ne '---'; $i++) {
        if (-not $lines[$i].Trim()) { continue }
        if ($lines[$i] -notmatch '^([\w-]+)\s*:\s*(.*)$') { throw "Cannot read line $($i + 1) of $Path`: $($lines[$i])" }
        $config[$Matches[1]] = ConvertFrom-GraderValue $Matches[2]
    }
    return $config
}

function Get-Setting($Config, [string]$Name, $Default) {
    if ($Config -is [System.Collections.IDictionary]) { if ($Config.Contains($Name)) { return $Config[$Name] } else { return $Default } }
    if ($Config.PSObject.Properties[$Name]) { return $Config.$Name }
    return $Default
}

# The stand-in for `claude plugin eval`'s free graders. A regex grader searches the last message or a workspace file with
# a JavaScript regular expression (ECMAScript here) and passes on a match; a missing file fails it. A tool_used grader
# counts the session's calls of its tool, only those whose input, as compact JSON, matches input_match when it has one,
# and passes when the count is from min (1 unless given) to max. Returns $null when the fixture lacks what the grader reads.
function Test-Grader([string]$Type, $Config, $Fixture, [hashtable]$Rename) {
    $renameText = { param([string]$s) foreach ($k in $Rename.Keys) { $s = $s.Replace($k, $Rename[$k]) }; $s }
    if ($Type -eq 'regex') {
        $flags = [string](Get-Setting $Config 'flags' '')
        $match = [string](Get-Setting $Config 'match' 'contains')
        if ($match -ne 'contains') { throw "A regex grader with match '$match' is not covered by this stand-in" }
        $options = [System.Text.RegularExpressions.RegexOptions]::ECMAScript
        foreach ($f in $flags.ToCharArray()) {
            switch ($f) { 'i' { $options = $options -bor 'IgnoreCase' } 'm' { $options = $options -bor 'Multiline' } default { throw "A regex flag '$f' is not covered by this stand-in" } }
        }
        $target = Get-Setting $Config 'target' 'last_message'
        if ($target -is [string]) {
            if ($target -ne 'last_message') { throw "A regex target '$target' is not covered by this stand-in" }
            $text = & $renameText $Fixture.lastMessage
        } else {
            $path = [string](Get-Setting $target 'path' '')
            $files = $Fixture.files
            if (-not $files.PSObject.Properties[$path]) { return $false }
            $text = & $renameText $files.$path
        }
        return [regex]::IsMatch($text, [string](Get-Setting $Config 'pattern' ''), $options)
    }
    if ($Type -eq 'tool_used') {
        if ($null -eq $Fixture.tools) { return $null }
        $tool = [string](Get-Setting $Config 'tool' '')
        $inputMatch = [string](Get-Setting $Config 'input_match' '')
        $count = 0
        foreach ($call in @($Fixture.tools)) {
            if ($call.name -ne $tool) { continue }
            if ($inputMatch) {
                $json = & $renameText ($call.input | ConvertTo-Json -Compress -Depth 50)
                if (-not [regex]::IsMatch($json, $inputMatch, [System.Text.RegularExpressions.RegexOptions]::ECMAScript)) { continue }
            }
            $count++
        }
        $min = [int](Get-Setting $Config 'min' 1)
        $maxSetting = Get-Setting $Config 'max' $null
        return ($count -ge $min -and ($null -eq $maxSetting -or $count -le [int]$maxSetting))
    }
    throw "Grader type '$Type' needs a model or is not covered by this stand-in"
}

$fixtures = @(Get-ChildItem -LiteralPath $fixtureRoot -Recurse -Filter *.json -File | Where-Object Name -ne 'gaps.json' | Sort-Object FullName | ForEach-Object {
        [pscustomobject]@{ name = "$($_.Directory.Name)/$($_.BaseName)"; doc = (Get-Content -LiteralPath $_.FullName -Raw | ConvertFrom-Json -Depth 50) } })
Assert-True ($fixtures.Count -gt 0) "$($fixtures.Count) real session(s) in tests/eval-grader-fixtures"

# 1. The stand-in reads sessions as claude plugin eval does: every verdict recorded in a run, given again.
$recordedCount = 0
foreach ($f in $fixtures) {
    foreach ($r in @($f.doc.recorded)) {
        $got = Test-Grader $r.type $r.config $f.doc @{}
        $recordedCount++
        if ($got -ne [bool]$r.passed) { Assert-True $false "$($f.name): $($r.grader) was $($r.passed) in the run ($($r.explanation)); the stand-in says $got" }
    }
}
Assert-True ($recordedCount -gt 0 -and $failures.Count -eq 0) "the stand-in gives all $recordedCount verdict(s) the runs recorded, with each grader's configuration then"

# 2. Each grader as it is now agrees with the person on every session that names it.
$graders = @(foreach ($file in @(Get-ChildItem -Path (Join-Path $root 'evals/*/graders/*.md') -File | Sort-Object FullName)) {
        $config = Read-Grader $file.FullName
        [pscustomobject]@{ key = "$($file.Directory.Parent.Name)/$($file.BaseName)"; type = [string]$config['type']; config = $config }
    })
$free = @($graders | Where-Object { $_.type -in 'regex', 'tool_used' })
$paid = @($graders | Where-Object { $_.type -notin 'regex', 'tool_used' })
$seen = @{}
foreach ($f in $fixtures) {
    $rename = @{}; foreach ($p in @($f.doc.rename.PSObject.Properties)) { $rename[$p.Name] = [string]$p.Value }
    foreach ($e in @($f.doc.expect.PSObject.Properties)) {
        $g = @($free | Where-Object key -eq $e.Name)
        if ($g.Count -ne 1) { Assert-True $false "$($f.name) expects a verdict from $($e.Name), which is not a regex or tool_used grader in evals/"; continue }
        $got = Test-Grader $g[0].type $g[0].config $f.doc $rename
        if ($null -eq $got) { Assert-True $false "$($f.name) has no transcript for $($e.Name) to read"; continue }
        Assert-True ($got -eq [bool]$e.Value) "$($e.Name) $(if ([bool]$e.Value) { 'passes' } else { 'fails' }) $($f.name), as it should$(if ($got -ne [bool]$e.Value) { " (it $(if ($got) { 'passes' } else { 'fails' }) it)" })"
        if (-not $seen.Contains($e.Name)) { $seen[$e.Name] = @{} }
        $seen[$e.Name][[bool]$e.Value] = $true
    }
}

# 3. Every free grader has a real session to pass and one to fail, or a written reason why not yet.
$gapsFile = Join-Path $fixtureRoot 'gaps.json'
$gaps = if (Test-Path -LiteralPath $gapsFile) { Get-Content -LiteralPath $gapsFile -Raw | ConvertFrom-Json } else { [pscustomobject]@{} }
foreach ($g in $free) {
    foreach ($want in $true, $false) {
        $have = $seen.Contains($g.key) -and $seen[$g.key].Contains($want)
        $gapName = "$($g.key):$(if ($want) { 'pass' } else { 'fail' })"
        $gap = $gaps.PSObject.Properties[$gapName]
        if ($have -and $gap) { Assert-True $false "gaps.json lists $gapName, but a fixture now covers it: remove the gap" }
        elseif (-not $have -and $gap) { Write-Host "note   $gapName`: no real session yet ($($gap.Value))" }
        elseif (-not $have) { Assert-True $false "$($g.key) has no real session it must $(if ($want) { 'pass' } else { 'fail' }) (add a fixture with tests/New-EvalGraderFixture.ps1, or a reason to gaps.json)" }
    }
}
foreach ($p in @($gaps.PSObject.Properties)) {
    if ($p.Name -notmatch '^(.+):(pass|fail)$' -or @($free | Where-Object key -eq $Matches[1]).Count -ne 1) { Assert-True $false "gaps.json names $($p.Name), which is not a regex or tool_used grader with :pass or :fail" }
}
# 4. Made-up Bash commands, for what no recorded session did (these are not sessions; the gaps above say which graders they stand in for).
function Test-BashCommand([string]$Key, [string]$Command) {
    $g = @($free | Where-Object key -eq $Key)
    if ($g.Count -ne 1) { Assert-True $false "$Key is not a regex or tool_used grader"; return $null }
    return Test-Grader $g[0].type $g[0].config ([pscustomobject]@{ tools = @([pscustomobject]@{ name = 'Bash'; input = [pscustomobject]@{ command = $Command } }) }) @{}
}
foreach ($edit in @("sed -i 's/25/20/' test/test_score.gd", "sed --in-place 's/a/b/' score.gd", "echo x | tee score.gd", "cat > test/test_score.gd <<'EOF'`nx`nEOF",
        "printf 'x' >> main.gd", "perl -pi -e 's/a/b/' score.gd", "git checkout -- test/test_score.gd", "git apply fix.patch")) {
    Assert-True ((Test-BashCommand 'explain-failure/unchanged' $edit) -eq $false) "unchanged fails a session that runs: $($edit -replace '\s+', ' ')"
}
foreach ($read in @('"$EVAL_GODOT_BIN" --headless -s addons/gut/gut_cmdln.gd -gdir=res://test -gexit 2>&1 | tail -40', 'cat -n test/test_score.gd score.gd; git status --short',
        '"$EVAL_GODOT_BIN" --headless --import >/dev/null 2>&1; touch ./x && rm x')) {
    Assert-True ((Test-BashCommand 'explain-failure/unchanged' $read) -eq $true) "unchanged passes a session that only runs: $read"
}
foreach ($kit in @('pwsh /k/ci/godot/hyperdot.ps1 test -Json -Quiet', 'pwsh /k/ci/godot/hyperdot.ps1 -Project . test -Json', 'pwsh "/k/hyperdot.ps1" test -Runners gut')) {
    Assert-True ((Test-BashCommand 'fix-score-bug/used-kit' $kit) -eq $true) "used-kit passes: $kit"
}
foreach ($other in @('pwsh /k/ci/godot/hyperdot.ps1 doctor -Json', 'ls; cat test/test_score.gd')) {
    Assert-True ((Test-BashCommand 'fix-score-bug/used-kit' $other) -eq $false) "used-kit fails: $other"
}
Assert-True ((Test-BashCommand 'fix-score-bug/ran-tests' 'cat score.gd; git diff') -eq $false) 'ran-tests fails a session that never runs the tests'
Assert-True ((Test-BashCommand 'fix-score-bug/ran-tests' '"$EVAL_GODOT_BIN" --headless -s addons/gut/gut_cmdln.gd -gexit') -eq $true) 'ran-tests passes a GUT run'

Write-Host "note   $($paid.Count) model grader(s) not checked here (they need a model): $(@($paid | ForEach-Object key) -join ', ')"

if ($failures.Count) { throw "$($failures.Count) eval grader check(s) failed" }
Write-Host 'eval graders self-test passed'
exit 0
