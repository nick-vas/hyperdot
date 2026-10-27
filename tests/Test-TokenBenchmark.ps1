# Self-test for benchmark/Invoke-TokenBenchmark.ps1 against a fake Claude Code CLI (tests/token-benchmark/fake-claude.ps1):
# token counting with cache reads and writes, the grader, retries only for answers that never came, the time limit, steps
# that resume one session, the isolation arguments and the copy the sessions run in, the call limit and the reports.
# Calls no model and costs nothing.
Set-StrictMode -Version 3.0
$ErrorActionPreference = 'Stop'

$root = Split-Path $PSScriptRoot -Parent
$bench = Join-Path $root 'benchmark/Invoke-TokenBenchmark.ps1'
$spec = Join-Path $PSScriptRoot 'token-benchmark/spec.json'
$fake = Join-Path $PSScriptRoot 'token-benchmark/fake-claude.ps1'
$work = Join-Path ([IO.Path]::GetTempPath()) "token-benchmark-$([guid]::NewGuid().ToString('N').Substring(0, 8))"
New-Item -ItemType Directory -Force $work, (Join-Path $work 'state') | Out-Null
$env:FAKE_CLAUDE_STATE = Join-Path $work 'state'
$env:FAKE_CLAUDE_LOG = Join-Path $work 'calls.jsonl'
$env:CLAUDE_CODE_SESSION_ID = 'parent-session-must-not-leak'
$failures = [System.Collections.Generic.List[string]]::new()
function Assert-True([bool]$Condition, [string]$What) {
    if ($Condition) { Write-Host "ok     $What" } else { Write-Host "FAILED $What" -ForegroundColor Red; $failures.Add($What) }
}
function Invoke-Bench([string[]]$Arguments, [switch]$OwnWorkspace) {
    $where = if ($OwnWorkspace) { @() } else { @('-WorkDir', $root) }
    $out = & pwsh -NoProfile -NonInteractive -File $bench -SpecPath $spec -Claude $fake -OutputDir (Join-Path $work 'results') -Json @where @Arguments 2>$null
    $code = $LASTEXITCODE
    $doc = @($out | Where-Object { $_ -match '^\{' }) | Select-Object -Last 1
    return [pscustomobject]@{ Code = $code; Json = $(if ($doc) { $doc | ConvertFrom-Json }) }
}

try {
    $dry = Invoke-Bench @('-DryRun')
    Assert-True ($dry.Code -eq 0 -and $dry.Json.calls -eq 40) "dry run counts 40 sessions (5 tasks x 2 runs x 1 + 1 + 2 steps)"
    Assert-True (-not (Test-Path -LiteralPath $env:FAKE_CLAUDE_LOG)) 'dry run calls nothing'

    $tooMany = Invoke-Bench @('-MaxCalls', '5')
    Assert-True ($tooMany.Code -ne 0) 'a run over the call limit stops before calling anything'

    $run = Invoke-Bench @('-TaskId', 'T-GOOD,T-MISS,T-FLAKY', '-SaveResponses')
    Assert-True ($run.Code -eq 0) 'the run completes'
    $rows = @(Get-Content -LiteralPath (Join-Path $run.Json.folder 'results.json') -Raw | ConvertFrom-Json)
    Assert-True ($rows.Count -eq 18) "18 results (3 profiles x 3 tasks x 2 runs), got $($rows.Count)"

    $good = @($rows | Where-Object task -eq 'T-GOOD')
    Assert-True (@($good | Where-Object { -not $_.success }).Count -eq 0) 'answers with every keyword pass'
    $plain = @($good | Where-Object profile -eq 'P1-plain')[0]
    Assert-True ($plain.tokensTotal -eq 6043 -and $plain.tokensCacheRead -eq 5000 -and $plain.tokensInput -eq 3) 'tokens include cache reads and writes (3 + 1000 + 5000 + 40)'
    Assert-True ($plain.costUsd -eq 0.01 -and $plain.model -eq 'claude-fake-1' -and $plain.ttftMs -eq 150) 'cost, model and time to first token come from the CLI output'
    $steps = @($good | Where-Object profile -eq 'P3-steps')[0]
    Assert-True ($steps.steps -eq 2 -and $steps.tokensTotal -eq 12086 -and $steps.turns -eq 4) 'a two-step profile adds up both sessions'

    $miss = @($rows | Where-Object task -eq 'T-MISS')
    Assert-True (@($miss | Where-Object { $_.profile -ne 'P3-steps' -and -not $_.success -and $_.reasons -match "missing 'beta'" }).Count -eq 4) 'a missing keyword fails the answer and says which'
    Assert-True (@($miss | Where-Object { $_.profile -eq 'P3-steps' -and $_.success }).Count -eq 2) 'the resumed step answers in the same session'

    $flaky = @($rows | Where-Object task -eq 'T-FLAKY')
    Assert-True (@($flaky | Where-Object { $_.success -and $_.retries -eq 1 }).Count -eq 6) 'output that is not JSON is retried once, then passes'

    $calls = @(Get-Content -LiteralPath $env:FAKE_CLAUDE_LOG | ForEach-Object { $_ | ConvertFrom-Json })
    $firstOfGood = @($calls | Where-Object { $_.prompt -match 'ANSWER-GOOD' -and $_.args -notcontains '--resume' })
    $profileOf = { param($c) if ($c.args -contains '--append-system-prompt') { 'P2' } elseif ($c.prompt -match 'Plan first') { 'P3' } else { 'P1' } }
    Assert-True ($firstOfGood.Count -eq 6 -and (& $profileOf $firstOfGood[0]) -eq 'P1' -and (& $profileOf $firstOfGood[3]) -eq 'P2') 'the profile that runs first changes with each repetition (a cold cache is shared out)'

    $turnsRun = Invoke-Bench @('-TaskId', 'T-TURNS', '-ProfileId', 'P1-plain', '-Repeat', '1')
    $turnsRow = @(Get-Content -LiteralPath (Join-Path $turnsRun.Json.folder 'results.json') -Raw | ConvertFrom-Json)[0]
    Assert-True ($turnsRun.Code -eq 0 -and -not $turnsRow.success -and $turnsRow.retries -eq 0 -and $turnsRow.tokensTotal -eq 6043 -and $turnsRow.reasons -match 'error_max_turns') 'running out of turns is a result: not retried, failed, its tokens counted'

    Assert-True (@($calls | Where-Object { $_.args -notcontains '--strict-mcp-config' }).Count -eq 0) 'every session skips the user''s MCP servers'
    Assert-True (@($calls | Where-Object { $_.args -contains 'Bash' -and [Array]::IndexOf($_.args, '--disallowedTools') -lt 0 }).Count -eq 0) 'no session may run Bash or edit'
    Assert-True (@($calls | Where-Object { $_.sessionEnv }).Count -eq 0) 'the parent session id does not reach the benchmark sessions'
    Assert-True (@($calls | Where-Object { $_.args -contains '--plugin-dir' -or $_.args -contains 'Skill' }).Count -eq 0) 'without -Plugin no session loads the plugin or its skills'
    $resumed = @($calls | Where-Object { $_.args -contains '--resume' })
    $started = @($calls | Where-Object { $_.args -contains '--session-id' } | ForEach-Object { $_.args[[Array]::IndexOf($_.args, '--session-id') + 1] })
    Assert-True ($resumed.Count -gt 0 -and @($resumed | Where-Object { $_.args[[Array]::IndexOf($_.args, '--resume') + 1] -notin $started }).Count -eq 0) 'the second step resumes the first step''s session'
    Assert-True (@($calls | Where-Object { $_.args -contains '--append-system-prompt' -and $_.prompt -notmatch 'GARBAGE' -and $_.prompt -notmatch 'Context \(paths' }).Count -eq 0) 'the scoped profile lists the task''s files'
    Assert-True (@($calls | Where-Object { $_.args -notcontains '--append-system-prompt' -and $_.args -notcontains '--resume' -and $_.prompt -match 'Context \(paths' -and $_.prompt -notmatch 'Plan first' }).Count -eq 0) 'the plain profile does not'
    $firstSteps = @($calls | Where-Object { $_.args -notcontains '--resume' -and $_.prompt -match 'Task: ' })
    $good = @($firstSteps | Where-Object { $_.prompt -match 'ANSWER-GOOD' })
    Assert-True ($good.Count -gt 0 -and @($good | Where-Object { $_.prompt -notmatch 'ANSWER-GOOD please Answer in at most 20 words\.' }).Count -eq 0) 'a task''s word limit is stated in its prompt'
    Assert-True (@($firstSteps | Where-Object { $_.prompt -match 'Say something' -and $_.prompt -match 'Answer in at most' }).Count -eq 0) 'a task without a word limit gets none'

    $summary = $run.Json
    $p1 = @($summary.profiles | Where-Object profile -eq 'P1-plain')[0]
    $p2 = @($summary.profiles | Where-Object profile -eq 'P2-scoped')[0]
    Assert-True ($p2.medianTokensTotal -lt $p1.medianTokensTotal) 'the summary compares profiles by median tokens'
    Assert-True ([Math]::Abs($p1.successRate - 66.7) -lt 0.01 -and $p1.runs -eq 6) "success rate per profile (got $($p1.successRate))"
    Assert-True (@($summary.cells).Count -eq 9) 'one summary cell per task and profile'
    foreach ($file in 'results.csv', 'summary.json', 'summary.md') { Assert-True (Test-Path -LiteralPath (Join-Path $summary.folder $file)) "writes $file" }
    Assert-True (@(Get-ChildItem -LiteralPath (Join-Path $summary.folder 'responses') -Filter '*.md').Count -gt 18) 'keeps every answer with -SaveResponses'

    $before = @(Get-Content -LiteralPath $env:FAKE_CLAUDE_LOG).Count
    $withPlugin = Invoke-Bench @('-TaskId', 'T-GOOD', '-ProfileId', 'P1-plain', '-Repeat', '1', '-Plugin')
    $pluginCalls = @(Get-Content -LiteralPath $env:FAKE_CLAUDE_LOG | Select-Object -Skip $before | ForEach-Object { $_ | ConvertFrom-Json })
    $pluginDir = @($pluginCalls | ForEach-Object { $_.args[[Array]::IndexOf($_.args, '--plugin-dir') + 1] })
    Assert-True ($pluginCalls.Count -eq 1 -and $pluginCalls[0].args -contains 'Skill' -and $pluginDir[0] -eq $root) "-Plugin loads this repository as a plugin and allows the Skill tool (got $($pluginDir -join ', '))"
    $pluginRow = @(Get-Content -LiteralPath (Join-Path $withPlugin.Json.folder 'results.json') -Raw | ConvertFrom-Json)[0]
    Assert-True ($pluginRow.plugin -eq $true -and $withPlugin.Json.meta.plugin -eq $true -and (Get-Content -LiteralPath (Join-Path $withPlugin.Json.folder 'summary.md') -Raw) -match 'loaded as a plugin') 'rows and the summary say the plugin was loaded'

    # The grader, on answers built to fool it (the adversarial review's cases).
    $parsed = [System.Management.Automation.Language.Parser]::ParseFile($bench, [ref]$null, [ref]$null)
    foreach ($name in 'Test-BenchmarkTerm', 'Test-BenchmarkAnswer') {
        $fn = $parsed.Find({ param($n) $n -is [System.Management.Automation.Language.FunctionDefinitionAst] -and $n.Name -eq $name }, $true)
        . ([scriptblock]::Create($fn.Extent.Text))
    }
    $fence = '`' * 3
    $rule = @{ forbid = @('Write-Output', 'echo') }
    Assert-True ((Test-BenchmarkAnswer "${fence}powershell`nfunction Get-X { 1 }`n${fence}`nNo ``Write-Output``: the value is returned." $rule).Count -eq 0) 'a forbidden command named in a note passes'
    Assert-True ((Test-BenchmarkAnswer "${fence}powershell`n    Write-Output 1`n${fence}" $rule) -contains "uses 'Write-Output'") 'a forbidden command in the code fails'
    Assert-True ((Test-BenchmarkAnswer "${fence}`nfunction Get-X { 1 }`n${fence}`nfunction Get-Y {`n    Get-Thing | echo`n}" $rule) -contains "uses 'echo'") 'a decoy code block does not hide one written outside it, nor an alias'
    Assert-True ((Test-BenchmarkAnswer 'It is specific to this repository.' @{ mustInclude = @('CI') }) -contains "missing 'CI'") '"CI" is not found inside "specific"'
    Assert-True ((Test-BenchmarkAnswer 'Runs on CI, every push.' @{ mustInclude = @('CI') }).Count -eq 0) 'a whole word is found'
    Assert-True ((Test-BenchmarkAnswer 'see test/test_score.gd' @{ mustInclude = @('test_') }).Count -eq 0) 'a term ending in _ still finds a prefix'
    Assert-True ((Test-BenchmarkAnswer 'Keep the context scoped.' @{ mustInclude = @('re:\bscop(e|ed)\b') }).Count -eq 0) 'a re: term is a regular expression'
    $diff = "--- a/x.ps1`n+++ b/x.ps1`n@@ -1 +1 @@`n     [ValidateSet('a')]`n-    [int]`$n`n+    [int]`$m"
    $added = @{ mustAdd = @('re:\[Validate[A-Za-z]+\(') }
    Assert-True ((Test-BenchmarkAnswer $diff $added) -contains "does not add '$($added.mustAdd[0])'") 'a term on an unchanged context line of a diff is not an addition'
    Assert-True ((Test-BenchmarkAnswer ($diff + "`n+    [ValidateRange(1, 9)]") $added).Count -eq 0) 'a term on an added line is'
    Assert-True ((Test-BenchmarkAnswer '+ ValidateRange' @{ mustInclude = @('Validate') }) -contains "missing 'Validate'") 'a plain term is a whole word, not a prefix'
    Assert-True ((Test-BenchmarkAnswer "| a | b |`n|---|---|`n- **c** d" @{ maxWords = 4 }).Count -eq 0) 'table pipes, list dashes and ** do not count as words (4 words)'
    Assert-True ((Test-BenchmarkAnswer 'one two three four five' @{ maxWords = 4 }) -contains '5 words, limit 4') 'five words are over a limit of four'
    $echoSpec = Join-Path $work 'echo-spec.json'
    $echo = Get-Content -LiteralPath $spec -Raw | ConvertFrom-Json -AsHashtable
    $echo.tasks[0].expected.mustInclude = @('please')
    $echo | ConvertTo-Json -Depth 6 | Set-Content -LiteralPath $echoSpec
    & pwsh -NoProfile -NonInteractive -File $bench -SpecPath $echoSpec -Claude $fake -DryRun 2>$null | Out-Null
    Assert-True ($LASTEXITCODE -ne 0) 'a spec that requires a word its own prompt holds is refused (echoing the question would pass)'

    # The staged programme's Opus configurations are priced apart: the standard four stay within the mid tier's ceiling
    # and Opus has a ceiling of its own, so neither run is refused (and Opus costs more than Sonnet).
    $staged = Join-Path $root 'benchmark/game-programme.json'
    $dryOf = { param($m, $p) $a = @('-NoProfile', '-NonInteractive', '-File', $bench, '-SpecPath', $staged, '-Tier', 'mid', '-Model', $m, '-DryRun', '-Json'); if ($p) { $a += '-Plugin' }
        $o = & pwsh @a 2>$null; $c = $LASTEXITCODE; [pscustomobject]@{ Code = $c; Json = (@($o | Where-Object { $_ -match '^\{' }) | Select-Object -Last 1 | ConvertFrom-Json) } }
    $sonnetDry = & $dryOf 'sonnet' $false; $opusDry = & $dryOf 'opus' $false; $opusPlugDry = & $dryOf 'opus' $true
    Assert-True ($sonnetDry.Code -eq 0 -and $opusDry.Code -eq 0 -and $opusPlugDry.Code -eq 0) 'the mid tier dry run is within its ceiling for Sonnet, Opus and Opus with the plugin'
    Assert-True ($opusDry.Json.estimateUsd -gt $sonnetDry.Json.estimateUsd -and $opusDry.Json.tierEstimateUsd -lt 120 -and $sonnetDry.Json.tierEstimateUsd -lt 120) 'Opus is priced above Sonnet, and each group of configurations is under the tier ceiling'

    $slow = Invoke-Bench @('-TaskId', 'T-SLOW', '-ProfileId', 'P1-plain', '-Repeat', '1')
    $slowRow = @(Get-Content -LiteralPath (Join-Path $slow.Json.folder 'results.json') -Raw | ConvertFrom-Json)[0]
    Assert-True (-not $slowRow.success -and $slowRow.reasons -eq 'timed out' -and $slowRow.retries -eq 1 -and $slowRow.durationMs -ge 16000) 'a hung session is stopped at the time limit and retried once'
    Assert-True ($slow.Code -ne 0 -and $slowRow.spendKnown -eq $false) 'a run with a session that never answered is incomplete (exit 1), and that spend is marked unknown'

    # The sessions run in a copy without the benchmark: its spec holds every expected answer.
    $before = @(Get-Content -LiteralPath $env:FAKE_CLAUDE_LOG).Count
    $own = Invoke-Bench @('-TaskId', 'T-GOOD', '-ProfileId', 'P1-plain', '-Repeat', '1') -OwnWorkspace
    $ownCall = @(Get-Content -LiteralPath $env:FAKE_CLAUDE_LOG | Select-Object -Skip $before | ForEach-Object { $_ | ConvertFrom-Json })[0]
    Assert-True ($own.Code -eq 0 -and $ownCall.cwd -ne $root -and $ownCall.seesAgents -and -not $ownCall.seesSpec) "by default a session runs in a copy with AGENTS.md but not benchmark/ (ran in $($ownCall.cwd))"
    Assert-True (-not (Test-Path -LiteralPath $ownCall.cwd)) 'the copy is deleted after the run'

    # A run cut by -MaxMinutes, and its continuation with -SkipDone: only the sessions that did not run, each exactly once.
    $key = { param($row) "$($row.configuration)|$($row.profile)|$($row.task)|$($row.repetition)" }
    $readRows = { param($folder) @(Get-Content -LiteralPath (Join-Path $folder 'results.json') -Raw | ConvertFrom-Json) }
    $pick = @('-TaskId', 'T-GOOD,T-MISS')
    $full = Invoke-Bench $pick
    $fullKeys = @(& $readRows $full.Json.folder | ForEach-Object { & $key $_ })
    Assert-True ($full.Code -eq 0 -and $fullKeys.Count -eq 12 -and $full.Json.meta.continuation -eq $false) 'a whole run of 2 tasks, 3 profiles and 2 repetitions has 12 sessions and is no continuation'
    $cut = Invoke-Bench ($pick + @('-MaxMinutes', '0.001'))
    $cutRows = @(& $readRows $cut.Json.folder)
    $cutFile = Join-Path $cut.Json.folder 'not-reached.json'
    $left = @(if (Test-Path -LiteralPath $cutFile) { Get-Content -LiteralPath $cutFile -Raw | ConvertFrom-Json })
    Assert-True ($cut.Code -eq 2) "a run stopped by -MaxMinutes exits 2, not 0 or 1 (got $($cut.Code))"
    Assert-True ($cutRows.Count -ge 1 -and $left.Count -ge 1 -and $cutRows.Count + $left.Count -eq 12) "the session running finishes: $($cutRows.Count) ran and $($left.Count) are listed in not-reached.json, together all 12"
    Assert-True ($left.Count -gt 0 -and $left[0].PSObject.Properties.Name -contains 'configuration' -and $left[0].PSObject.Properties.Name -contains 'profile' -and $left[0].PSObject.Properties.Name -contains 'task' -and $left[0].PSObject.Properties.Name -contains 'repetition') 'not-reached.json names each session by configuration, profile, task and repetition'
    Assert-True ($cut.Json.meta.notReached -eq $left.Count -and $cut.Json.meta.standard -eq $false -and (Get-Content -LiteralPath (Join-Path $cut.Json.folder 'summary.md') -Raw) -match 'Stopped at the time limit') 'the summary says how many were not reached'
    $rest = Invoke-Bench ($pick + @('-SkipDone', $cut.Json.folder))
    $restRows = @(& $readRows $rest.Json.folder)
    Assert-True ($rest.Code -eq 0 -and $restRows.Count -eq $left.Count -and $rest.Json.folder -ne $cut.Json.folder) 'the continuation runs exactly the sessions not reached, in a fresh folder'
    $cutKeys = @($cutRows | ForEach-Object { & $key $_ })
    $restKeys = @($restRows | ForEach-Object { & $key $_ })
    Assert-True (@($restKeys | Where-Object { $_ -in $cutKeys }).Count -eq 0 -and @(@($cutKeys) + @($restKeys) | Sort-Object -Unique).Count -eq 12 -and (@($fullKeys | Sort-Object) -join ',') -eq (@(@($cutKeys) + @($restKeys) | Sort-Object) -join ',')) 'the two runs together are the whole run, no session twice (the key does not depend on the rotating order)'
    Assert-True ($rest.Json.meta.continuation -eq $true -and $rest.Json.meta.skipped -eq $cutRows.Count -and $rest.Json.meta.standard -eq $false -and (Get-Content -LiteralPath (Join-Path $rest.Json.folder 'summary.md') -Raw) -match 'A continuation' -and -not (Test-Path -LiteralPath (Join-Path $rest.Json.folder 'not-reached.json'))) 'the continuation says it is one, how many it skipped, and has nothing not reached'
    Assert-True (@(Get-ChildItem -LiteralPath $cut.Json.folder -Filter 'results.json').Count -eq 1 -and @(& $readRows $cut.Json.folder).Count -eq $cutRows.Count) 'the earlier run''s results are not changed'

    # A continuation names the runs it continues, and must be the same selection as them (model, plugin, repeat, narrowing).
    Assert-True (@($rest.Json.meta.continues).Count -eq 1 -and $rest.Json.meta.continues[0] -eq $cut.Json.meta.runId) 'the continuation records the run it continues'
    $refused = { param($extra) $o = & pwsh -NoProfile -NonInteractive -File $bench -SpecPath $spec -Claude $fake -DryRun -SkipDone $cut.Json.folder @extra 2>&1; [pscustomobject]@{ Code = $LASTEXITCODE; Text = ($o | Out-String) } }
    foreach ($case in @(@('another task', @('-TaskId', 'T-GOOD')), @('another repeat', @('-TaskId', 'T-GOOD,T-MISS', '-Repeat', '1')), @('another model', @('-TaskId', 'T-GOOD,T-MISS', '-Model', 'opus')), @('plugin', @('-TaskId', 'T-GOOD,T-MISS', '-Plugin')))) {
        $r = & $refused $case[1]
        Assert-True ($r.Code -ne 0 -and $r.Text -match 'not the same selection') "a continuation with $($case[0]) is refused, naming what differs"
    }
    $r = & $refused $pick
    Assert-True ($r.Code -eq 0) 'a continuation of the same selection is accepted'
    # A row with no tokens, or an infrastructure failure, counts as not done; a failed answer that spent tokens does.
    $copy = Join-Path $work 'earlier'
    New-Item -ItemType Directory -Force (Join-Path $copy 'run-1'), (Join-Path $copy 'run-2') | Out-Null
    $fullRows = @(& $readRows $full.Json.folder)
    $fullRows[0].tokensTotal = 0
    $fullRows[1].infrastructure = $true
    $fullRows[2].success = $false; $fullRows[2].reasons = 'missing x'
    ConvertTo-Json -InputObject @($fullRows[0..5]) -Depth 5 | Set-Content -LiteralPath (Join-Path $copy 'run-1/results.json')
    ConvertTo-Json -InputObject @($fullRows[6..7]) -Depth 5 | Set-Content -LiteralPath (Join-Path $copy 'run-2/results.json')
    $dryRest = Invoke-Bench ($pick + @('-DryRun', '-SkipDone', $copy))
    # 12 sessions; rows 2 to 7 ran (6 skipped, in two folders; row 2 failed its answer but spent tokens); rows 0 (no tokens) and 1 (infrastructure) run again.
    Assert-True ($dryRest.Code -eq 0 -and $dryRest.Json.skipped -eq 6 -and @($dryRest.Json.sessions).Count -eq 6 -and $dryRest.Json.continuation -eq $true) 'a row with no tokens or an infrastructure failure is run again; a failed answer is not (6 left of 12, 6 skipped)'
    $dryAll = Invoke-Bench ($pick + @('-DryRun'))
    Assert-True ($dryAll.Json.skipped -eq 0 -and $dryAll.Json.continuation -eq $false -and @($dryAll.Json.sessions).Count -eq 12) 'without -SkipDone the dry run skips nothing'
    $shard1 = Invoke-Bench ($pick + @('-DryRun', '-SkipDone', $copy, '-Shard', '1/2'))
    $shard2 = Invoke-Bench ($pick + @('-DryRun', '-SkipDone', $copy, '-Shard', '2/2'))
    Assert-True (@($shard1.Json.sessions).Count + @($shard2.Json.sessions).Count -eq 6 -and [Math]::Abs(@($shard1.Json.sessions).Count - @($shard2.Json.sessions).Count) -le 1) 'shards split what is left evenly (3 and 3), the skip coming first'
    Assert-True ($shard1.Json.skipped -eq 6 -and $shard2.Json.skipped -eq 6 -and $shard1.Json.shard -eq '1/2') 'each shard reports the skipped sessions'
    & pwsh -NoProfile -NonInteractive -File $bench -SpecPath $spec -Claude $fake -DryRun -SkipDone (Join-Path $work 'no-such-folder') 2>$null | Out-Null
    Assert-True ($LASTEXITCODE -ne 0) '-SkipDone with a folder that does not exist is refused'
    & pwsh -NoProfile -NonInteractive -File $bench -SpecPath $spec -Claude $fake -DryRun -SkipDone (New-Item -ItemType Directory -Force (Join-Path $work 'empty')).FullName 2>$null | Out-Null
    Assert-True ($LASTEXITCODE -ne 0) '-SkipDone with a folder holding no results.json is refused (a wrong artifact path would otherwise skip nothing)'

    # The dry run of a continuation prices only what is left (the staged programme's cost model).
    $dryStaged = { param($extra) $a = @('-NoProfile', '-NonInteractive', '-File', $bench, '-SpecPath', $staged, '-Tier', 'mid', '-Model', 'haiku', '-DryRun', '-Json') + $extra
        $o = & pwsh @a 2>$null; $c = $LASTEXITCODE; [pscustomobject]@{ Code = $c; Json = (@($o | Where-Object { $_ -match '^\{' }) | Select-Object -Last 1 | ConvertFrom-Json) } }
    $wholeStaged = & $dryStaged @()
    $stagedSpec = Get-Content -LiteralPath $staged -Raw | ConvertFrom-Json -AsHashtable
    $stagedProfile = $stagedSpec.profiles[0].id
    $doneRows = @(foreach ($s in @($wholeStaged.Json.sessions | Select-Object -First 90)) {
            $id, $rep = $s -split '#'
            [ordered]@{ configuration = 'haiku'; profile = $stagedProfile; task = $id; repetition = [int]$rep; tokensTotal = 1000; infrastructure = $false }
        })
    $stagedDone = Join-Path $work 'staged-done/20260101-000000'
    New-Item -ItemType Directory -Force $stagedDone | Out-Null
    ConvertTo-Json -InputObject $doneRows -Depth 4 | Set-Content -LiteralPath (Join-Path $stagedDone 'results.json')
    $remainder = & $dryStaged @('-SkipDone', (Join-Path $work 'staged-done'))
    Assert-True ($wholeStaged.Code -eq 0 -and $remainder.Code -eq 0 -and $remainder.Json.skipped -eq 90 -and @($remainder.Json.sessions).Count -eq @($wholeStaged.Json.sessions).Count - 90) 'the staged dry run of a continuation counts the sessions skipped and the ones left'
    Assert-True ($remainder.Json.estimateUsd -gt 0 -and $remainder.Json.estimateUsd -lt $wholeStaged.Json.estimateUsd -and $remainder.Json.tierEstimateUsd -eq $wholeStaged.Json.tierEstimateUsd -and $remainder.Json.budgetUsd -lt $wholeStaged.Json.budgetUsd) 'it prices only the remainder (and its ceiling is the remainder''s share)'
    $part1 = & $dryStaged @('-SkipDone', (Join-Path $work 'staged-done'), '-Shard', '1/2')
    $part2 = & $dryStaged @('-SkipDone', (Join-Path $work 'staged-done'), '-Shard', '2/2')
    Assert-True ([Math]::Abs(@($part1.Json.sessions).Count - @($part2.Json.sessions).Count) -le 1 -and [Math]::Abs($part1.Json.estimateUsd + $part2.Json.estimateUsd - $remainder.Json.estimateUsd) -lt 0.01) 'the remainder splits evenly over shards and their estimates add up to the remainder'

    function Get-WorkflowText { return Get-Content -Raw -LiteralPath (Join-Path $root '.github/workflows/token-benchmark.yml') }
    # The -MaxMinutes the workflow passes: always a number, never later than 45 minutes before the job's limit.
    $minutesTool = Join-Path $root '.github/scripts/Get-BenchmarkMinutes.ps1'
    function Get-JobMinutes([string]$Requested, [int]$Job) { $text = (& pwsh -NoProfile -NonInteractive -File $minutesTool -MaxMinutes $Requested -JobMinutes $Job 2>&1) -join "`n"; return $(if ($LASTEXITCODE) { 'error' } else { $text.Trim() }) }
    Assert-True ((Get-JobMinutes '' 330) -eq '285') 'no max_minutes: the cap of the job, not no limit'
    Assert-True ((Get-JobMinutes '0' 330) -eq '285') 'max_minutes 0: the cap of the job, not no limit'
    Assert-True ((Get-JobMinutes '300' 330) -eq '285') 'max_minutes 300 in a 330-minute job: 285'
    Assert-True ((Get-JobMinutes '100' 330) -eq '100') 'max_minutes under the cap is kept'
    Assert-True ((Get-JobMinutes '' 120) -eq '75' -and (Get-JobMinutes '90' 120) -eq '75') 'a 120-minute job: 75'
    Assert-True ((Get-JobMinutes 'abc' 330) -eq 'error' -and (Get-JobMinutes '-5' 330) -eq 'error') 'max_minutes that is not a whole number is refused'
    Assert-True ((Get-WorkflowText) -match 'Get-BenchmarkMinutes\.ps1' -and (Get-WorkflowText) -notmatch 'if \(\$minutes -gt 0\)') 'the workflow uses that script and always passes -MaxMinutes'
} finally {
    Remove-Item Env:CLAUDE_CODE_SESSION_ID, Env:FAKE_CLAUDE_STATE, Env:FAKE_CLAUDE_LOG -ErrorAction SilentlyContinue
    Remove-Item -LiteralPath $work -Recurse -Force -ErrorAction SilentlyContinue
}

if ($failures.Count) { throw "$($failures.Count) token benchmark check(s) failed" }
Write-Host 'Token benchmark self-test passed'
# Some runs above failed on purpose; GitHub's pwsh wrapper would end the step with their exit code.
exit 0
