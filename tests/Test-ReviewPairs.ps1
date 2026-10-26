#!/usr/bin/env pwsh
# Self-test of the blind review and the judge's calibration (benchmark/PLAN.md, grading layer 4), with made-up runs and
# no model: Invoke-SideBySide.ps1 -ReviewOut pairs each task's work with and without the plugin, shows them as A and B
# with nothing that names the plugin, and keeps which was which in a separate key; Get-JudgeAgreement.ps1 scores a
# judge against a person's verdicts and against itself, for one set at fixed bars or for every set by the owner's rule.
Set-StrictMode -Version 3.0
$ErrorActionPreference = 'Stop'

$root = Split-Path $PSScriptRoot
$dir = Join-Path ([IO.Path]::GetTempPath()) "review-pairs-$PID"
$failures = [System.Collections.Generic.List[string]]::new()
function Assert-True([bool]$Condition, [string]$What) {
    if ($Condition) { Write-Host "ok     $What" } else { Write-Host "FAILED $What" -ForegroundColor Red; $failures.Add($What) }
}

# One run folder: a results.json row per task and its saved prompt, answer and diff.
function New-Run([string]$Name, [bool]$Plugin, [string]$Model, [string[]]$Tasks) {
    $run = Join-Path $dir "$Name/20261023-000000"
    New-Item -ItemType Directory -Force (Join-Path $run 'responses') | Out-Null
    $rows = foreach ($task in $Tasks) {
        $stem = Join-Path $run "responses/A-baseline-$task-r1"
        Set-Content -LiteralPath "$stem.prompt.md" -Value "Fix the bug in $task."
        Set-Content -LiteralPath "$stem-a0-s0.md" -Value "WORK OF $Name ON $task"
        Set-Content -LiteralPath "$stem-a0.diff" -Value "+ change by $Name"
        [ordered]@{ profile = 'A-baseline'; task = $task; repetition = 1; retries = 0; steps = 1; model = $Model; plugin = $Plugin; infrastructure = $false }
    }
    ConvertTo-Json -InputObject @($rows) -Depth 3 | Set-Content -LiteralPath (Join-Path $run 'results.json')
    return (Join-Path $dir $Name)
}

try {
    $tasks = @('t.one', 't.two', 't.three', 't.four')
    $runs = @(
        (New-Run 'base' $false 'm-1' $tasks), (New-Run 'withkit' $true 'm-1' $tasks),
        # A task run only without the plugin has no pair.
        (New-Run 'lone' $false 'm-1' @('t.five'))
    )
    $review = Join-Path $dir 'review'
    & (Get-Process -Id $PID).Path -NoProfile -File (Join-Path $root 'benchmark/Invoke-SideBySide.ps1') -Results ($runs -join ',') -ReviewOut $review | Out-Null
    Assert-True ($LASTEXITCODE -eq 0) "-ReviewOut writes the pairs without a judge (exit $LASTEXITCODE)"
    $pairsText = Get-Content -LiteralPath (Join-Path $review 'review-pairs.json') -Raw
    $pairs = $pairsText | ConvertFrom-Json
    $key = Get-Content -LiteralPath (Join-Path $review 'review-key.json') -Raw | ConvertFrom-Json -AsHashtable
    Assert-True (@($pairs.pairs).Count -eq 4) "one pair per task run both ways, none for a task run once: $(@($pairs.pairs).Count)"
    Assert-True ($pairsText -notmatch '(?i)"(model|plugin|profile|pluginIs)"' -and $pairsText -notmatch 'm-1') 'the page''s pairs name no model, profile or plugin side'
    Assert-True ($pairs.rubric -match 'judge reads the task') 'the pairs carry the rubric the judge reads'
    $second = Join-Path $dir 'review-q'
    & (Get-Process -Id $PID).Path -NoProfile -File (Join-Path $root 'benchmark/Invoke-SideBySide.ps1') -Results ($runs -join ',') -ReviewOut $second -ReviewIdPrefix q | Out-Null
    $qIds = @((Get-Content -LiteralPath (Join-Path $second 'review-pairs.json') -Raw | ConvertFrom-Json).pairs | ForEach-Object id)
    Assert-True (($qIds -join ',') -eq 'q01,q02,q03,q04') "a second set's pairs are numbered apart from the first's: $($qIds -join ',')"
    $sides = @(foreach ($p in $pairs.pairs) {
        $entry = $key.pairs[$p.id]
        $pluginWork = if ($entry.pluginIs -eq 'A') { $p.a } else { $p.b }
        $otherWork = if ($entry.pluginIs -eq 'A') { $p.b } else { $p.a }
        ($pluginWork -match 'WORK OF withkit') -and ($otherWork -match 'WORK OF base')
        $entry.pluginIs
    })
    Assert-True (@($sides | Where-Object { $_ -is [bool] -and -not $_ }).Count -eq 0) 'the key says which side had the plugin, for every pair'
    $order = @($sides | Where-Object { $_ -is [string] })
    Assert-True ($order -contains 'A' -and $order -contains 'B') "the plugin's work is not always on one side: $($order -join '')"

    # The judge: plugin both times on p01 and p02, the other both times on p03, split on p04.
    $byId = @{}; foreach ($id in $key.pairs.Keys) { $byId[$id] = $key.pairs[$id].pair }
    $prefs = [ordered]@{ judgeModel = 'judge-1'; pairs = @(
        [ordered]@{ pair = $byId['p01']; choices = @('A', 'B'); pluginOutcome = 1.0 }
        [ordered]@{ pair = $byId['p02']; choices = @('B', 'A'); pluginOutcome = 1.0 }
        [ordered]@{ pair = $byId['p03']; choices = @('A', 'B'); pluginOutcome = 0.0 }
        [ordered]@{ pair = $byId['p04']; choices = @('A', 'A'); pluginOutcome = 0.5 }) }
    $prefsFile = Join-Path $dir 'preferences.json'; $prefs | ConvertTo-Json -Depth 4 | Set-Content -LiteralPath $prefsFile
    # The person, in the page's A/B terms: agrees on p01, p02 and p03, picks the plugin on p04.
    $pick = { param($id, $side) if ($side -eq 'plugin') { $key.pairs[$id].pluginIs } else { @('A', 'B') | Where-Object { $_ -ne $key.pairs[$id].pluginIs } } }
    $votes = @(
        @{ id = 'p01'; choice = (& $pick 'p01' 'plugin') }, @{ id = 'p02'; choice = (& $pick 'p02' 'plugin') },
        @{ id = 'p03'; choice = (& $pick 'p03' 'other') }, @{ id = 'p04'; choice = (& $pick 'p04' 'plugin') })
    $votesFile = Join-Path $dir 'verdicts.json'; ConvertTo-Json -Depth 10 -InputObject $votes | Set-Content -LiteralPath $votesFile
    $agreementScript = Join-Path $root 'benchmark/Get-JudgeAgreement.ps1'
    $out = & (Get-Process -Id $PID).Path -NoProfile -File $agreementScript -Key (Join-Path $review 'review-key.json') -Verdicts $votesFile -Preferences $prefsFile -Json
    $code = $LASTEXITCODE; $d = ($out -join "`n") | ConvertFrom-Json
    Assert-True ($d.compared -eq 4 -and $d.agreement -eq 0.75 -and $d.consistency -eq 0.75) "agreement 3 of 4, consistency 3 of 4: $($d.agreement), $($d.consistency)"
    Assert-True (-not $d.passes -and $code -eq 1) "below 80% and 90% the judge is not calibrated (exit $code)"
    Assert-True (@($d.disagreements).Count -eq 1 -and $d.disagreements[0].id -eq 'p04' -and $d.disagreements[0].judge -eq 'even') 'the disagreement is named, with both verdicts'

    # A judge that gave no verdict (a failed session, a reply with no choice) is no judgement: not even, not consistent.
    $broken = [ordered]@{ judgeModel = 'judge-broken'; pairs = @(foreach ($id in 'p01', 'p02', 'p03', 'p04') { [ordered]@{ pair = $byId[$id]; choices = @('error', 'error'); pluginOutcome = $null } }) }
    $brokenFile = Join-Path $dir 'broken.json'; $broken | ConvertTo-Json -Depth 4 | Set-Content -LiteralPath $brokenFile
    $out = & (Get-Process -Id $PID).Path -NoProfile -File $agreementScript -Key (Join-Path $review 'review-key.json') -Verdicts $votesFile -Preferences $brokenFile -Json
    $b = ($out -join "`n") | ConvertFrom-Json
    Assert-True ($LASTEXITCODE -eq 1 -and $b.agreement -eq 0 -and $b.consistency -eq 0) "a judge with no verdicts agrees with no one and not with itself: $($b.agreement), $($b.consistency)"

    # The side-by-side itself: a judge whose replies name no choice fails the run, and its pairs stay out of the win rate.
    $stand = Join-Path $dir 'stand-in-judge.ps1'
    Set-Content -LiteralPath $stand -Value "Write-Output (@{ type = 'result'; subtype = 'success'; is_error = `$false; result = 'I cannot decide.'; total_cost_usd = 0 } | ConvertTo-Json -Depth 10 -Compress)"
    $judged = Join-Path $dir 'judged'
    & (Get-Process -Id $PID).Path -NoProfile -File (Join-Path $root 'benchmark/Invoke-SideBySide.ps1') -Results ($runs -join ',') -Model judge-x -OutDir $judged -Claude $stand | Out-Null
    $code = $LASTEXITCODE
    $p = Get-Content -LiteralPath (Join-Path $judged 'preferences.json') -Raw | ConvertFrom-Json
    Assert-True ($code -eq 1 -and $p.failedPairs -eq 4 -and @($p.pairs | Where-Object { $null -ne $_.pluginOutcome }).Count -eq 0 -and @($p.pluginWinRate.PSObject.Properties).Count -eq 0) "replies with no choice are errors, not even, and fail the run (exit $code, $($p.failedPairs) failed)"

    # -Votes: each order judged several times, the majority deciding. A stand-in judge that answers A, A, B in turn gives
    # every order (3 votes) a majority of A; one that alternates A and B gives every order (2 votes) a tie, which is even.
    foreach ($case in @(@{ votes = 3; cycle = "@('A', 'A', 'B')"; expect = 'A' }, @{ votes = 2; cycle = "@('A', 'B')"; expect = 'even' })) {
        $counter = Join-Path $dir "votes-$($case.votes).txt"
        $voter = Join-Path $dir "stand-in-voter-$($case.votes).ps1"
        Set-Content -LiteralPath $voter -Value @"
`$cycle = $($case.cycle)
`$n = if (Test-Path -LiteralPath '$counter') { [int](Get-Content -LiteralPath '$counter') } else { 0 }
Set-Content -LiteralPath '$counter' -Value (`$n + 1)
`$reply = '{"better": "' + `$cycle[`$n % `$cycle.Count] + '", "why": "stand-in"}'
Write-Output (@{ type = 'result'; subtype = 'success'; is_error = `$false; result = `$reply; total_cost_usd = 0.001 } | ConvertTo-Json -Depth 10 -Compress)
"@
        $out = Join-Path $dir "voted-$($case.votes)"
        & (Get-Process -Id $PID).Path -NoProfile -File (Join-Path $root 'benchmark/Invoke-SideBySide.ps1') -Results ($runs -join ',') -Model judge-v -OutDir $out -Claude $voter -Votes $case.votes | Out-Null
        $code = $LASTEXITCODE
        $p = Get-Content -LiteralPath (Join-Path $out 'preferences.json') -Raw | ConvertFrom-Json
        $calls = [int](Get-Content -LiteralPath $counter)
        $choices = @($p.pairs | ForEach-Object { $_.choices } | Sort-Object -Unique)
        $voteCounts = @($p.pairs | ForEach-Object { $_.votes } | ForEach-Object { @($_).Count } | Sort-Object -Unique)
        Assert-True ($code -eq 0 -and $p.votes -eq $case.votes -and $calls -eq 8 * $case.votes) "$($case.votes) votes per order: $calls judge calls for 4 pairs (exit $code)"
        Assert-True ($choices.Count -eq 1 -and $choices[0] -eq $case.expect) "$($case.votes) votes per order decide $($case.expect): $($choices -join ', ')"
        Assert-True ($voteCounts.Count -eq 1 -and $voteCounts[0] -eq $case.votes -and [Math]::Abs($p.costUsd - 0.008 * $case.votes) -lt 1e-9) "each order keeps its $($case.votes) votes and every vote's cost: $($p.costUsd)"
    }

    # Lower bars: the same numbers pass.
    & (Get-Process -Id $PID).Path -NoProfile -File $agreementScript -Key (Join-Path $review 'review-key.json') -Verdicts $votesFile -Preferences $prefsFile -MinAgreement 0.7 -MinConsistency 0.7 | Out-Null
    Assert-True ($LASTEXITCODE -eq 0) "at bars of 70% it is calibrated (exit $LASTEXITCODE)"

    # -Calibration: the owner's rule over every set at once. The first set (p01-p04, the verdicts above) is marked
    # "forAgreement": false; a second set (q01, q02) comes from other tasks. The re-judge shows p04 and q01 again with A and
    # B swapped: p04 is now even (changed), q01 the plugin's work again (kept), so the owner agrees with themselves on 1 of
    # 2 and the bar is 50%. The judge is measured on q01, q02 and p04 with its newer verdict, and with itself on all six.
    $runs2 = @((New-Run 'base2' $false 'm-1' @('t.six', 't.seven')), (New-Run 'withkit2' $true 'm-1' @('t.six', 't.seven')))
    $review2 = Join-Path $dir 'review-2'
    & (Get-Process -Id $PID).Path -NoProfile -File (Join-Path $root 'benchmark/Invoke-SideBySide.ps1') -Results ($runs2 -join ',') -ReviewOut $review2 -ReviewIdPrefix q | Out-Null
    $key2 = Get-Content -LiteralPath (Join-Path $review2 'review-key.json') -Raw | ConvertFrom-Json -AsHashtable
    $side2 = { param($id, $side) if ($side -eq 'plugin') { $key2.pairs[$id].pluginIs } else { @('A', 'B') | Where-Object { $_ -ne $key2.pairs[$id].pluginIs } } }
    $flip = { param($c) if ($c -eq 'A') { 'B' } else { 'A' } }
    $calDir = Join-Path $dir 'calibration'; New-Item -ItemType Directory -Force $calDir | Out-Null
    [ordered]@{ run = 1; keySha256 = 'x'; forAgreement = $false; verdicts = $votes } | ConvertTo-Json -Depth 4 | Set-Content -LiteralPath (Join-Path $calDir 'pilot-1.json')
    [ordered]@{ run = 2; idPrefix = 'q'; keySha256 = 'y'; verdicts = @(@{ id = 'q01'; choice = (& $side2 'q01' 'plugin') }, @{ id = 'q02'; choice = (& $side2 'q02' 'other') }) } |
        ConvertTo-Json -Depth 4 | Set-Content -LiteralPath (Join-Path $calDir 'pilot-2.json')
    $retest = [ordered]@{ pairs = @(
            [ordered]@{ id = 'r01'; original = 'p04'; swapped = $true; choice = 'even' }
            [ordered]@{ id = 'r02'; original = 'q01'; swapped = $true; choice = (& $flip (& $side2 'q01' 'plugin')) })
        result = [ordered]@{ sameAsBefore = 1; compared = 2 } }
    $retest | ConvertTo-Json -Depth 4 | Set-Content -LiteralPath (Join-Path $calDir 'retest-1.json')
    $byId2 = @{}; foreach ($id in $key2.pairs.Keys) { $byId2[$id] = $key2.pairs[$id].pair }
    $prefs1 = [ordered]@{ judgeModel = 'judge-1'; pairs = @(
            [ordered]@{ pair = $byId['p01']; choices = @('A', 'B'); pluginOutcome = 1.0 }
            [ordered]@{ pair = $byId['p02']; choices = @('B', 'A'); pluginOutcome = 1.0 }
            [ordered]@{ pair = $byId['p03']; choices = @('A', 'B'); pluginOutcome = 0.0 }
            [ordered]@{ pair = $byId['p04']; choices = @('even', 'even'); pluginOutcome = 0.5 }) }
    $prefs2 = [ordered]@{ judgeModel = 'judge-1'; pairs = @(
            [ordered]@{ pair = $byId2['q01']; choices = @('A', 'B'); pluginOutcome = 1.0 }
            [ordered]@{ pair = $byId2['q02']; choices = @('A', 'A'); pluginOutcome = 0.5 }) }
    $prefs1File = Join-Path $dir 'prefs-1.json'; $prefs1 | ConvertTo-Json -Depth 4 | Set-Content -LiteralPath $prefs1File
    $prefs2File = Join-Path $dir 'prefs-2.json'; $prefs2 | ConvertTo-Json -Depth 4 | Set-Content -LiteralPath $prefs2File
    $keys = "$(Join-Path $review 'review-key.json'),$(Join-Path $review2 'review-key.json')"
    $out = & (Get-Process -Id $PID).Path -NoProfile -File $agreementScript -Calibration $calDir -Key $keys -Preferences "$prefs1File,$prefs2File" -Json
    $code = $LASTEXITCODE; $c = ($out -join "`n") | ConvertFrom-Json
    Assert-True ($c.minAgreement -eq 0.5 -and $c.ownerSelfAgreement.same -eq 1 -and $c.ownerSelfAgreement.compared -eq 2) "the agreement bar is the owner's own on the re-judge, 1 of 2: $($c.minAgreement) ($($c.minAgreementSource))"
    Assert-True ($c.compared -eq 3 -and [Math]::Abs($c.agreement - 0.6667) -lt 1e-9) "measured on the second set and the re-judged pair of the first, with its newer verdict: $($c.agreement) of $($c.compared)"
    Assert-True (@($c.disagreements | ForEach-Object id) -join ',' -eq 'q02') "a swapped re-judge is turned back before use, and the first set's other pairs are not compared: $(@($c.disagreements | ForEach-Object id) -join ',')"
    Assert-True ($c.pairsJudged -eq 6 -and [Math]::Abs($c.consistency - 0.8333) -lt 1e-9 -and -not $c.passes -and $code -eq 1) "agreement with itself over every pair of every set, 5 of 6, under 90%: not calibrated (exit $code)"
    & (Get-Process -Id $PID).Path -NoProfile -File $agreementScript -Calibration $calDir -Key $keys -Preferences "$prefs1File,$prefs2File" -MinConsistency 0.8 | Out-Null
    Assert-True ($LASTEXITCODE -eq 0) "at 80% with itself it is calibrated, still held to the owner's bar (exit $LASTEXITCODE)"
    $retest.result.sameAsBefore = 2; $retest | ConvertTo-Json -Depth 4 | Set-Content -LiteralPath (Join-Path $calDir 'retest-1.json')
    $out = & (Get-Process -Id $PID).Path -NoProfile -File $agreementScript -Calibration $calDir -Key $keys -Preferences "$prefs1File,$prefs2File" 2>&1
    Assert-True ($LASTEXITCODE -ne 0 -and ($out -join ' ') -match 'pairs give 1') "a re-judge whose stated result its pairs do not give is refused (exit $LASTEXITCODE)"
} finally {
    Remove-Item -LiteralPath $dir -Recurse -Force -ErrorAction SilentlyContinue
}

if ($failures.Count) { throw "$($failures.Count) review check(s) failed" }
Write-Host 'review pairs self-test passed'
exit 0
