#Requires -Version 7.2
<#
.SYNOPSIS
Calibrates the judge (benchmark/PLAN.md, grading layer 4): how often it agrees with a person's blind verdicts on the same
pairs, and how often it agrees with itself when A and B are swapped.

.DESCRIPTION
The person judges the pairs that Invoke-SideBySide.ps1 -ReviewOut wrote, on the review page; the judge judges the same
pairs with Invoke-SideBySide.ps1. A pair's verdict is the plugin's work, the other work, or even. The judge's verdict
is the plugin's or the other's only when it chose the same work in both orders, and even otherwise; it agrees with
itself when it chose the same work both times or "even" both times.

With -Calibration (the folder of the owner's verdicts, benchmark/calibration) it applies the owner's rule of 2026-10-26
over every set at once: the judge must agree with the owner at least as often as the owner agrees with themselves on a
blind re-judge of earlier pairs (the files with "pairs" and "result"), and with itself on at least 90% of every pair it
judged. The verdicts it is measured against are every set's, except a set marked "forAgreement": false, with each
re-judged pair's newer verdict in place of the older one (a re-judged pair of an excluded set counts with its newer
verdict). -Key and -Preferences then take one file per set.

With -Verdicts instead it scores one set against fixed bars (-MinAgreement, 80% unless given).

Below either bar the script exits 1 and the judge's results stay out of the label.

.EXAMPLE
pwsh benchmark/Get-JudgeAgreement.ps1 -Calibration benchmark/calibration -Key set1/review-key.json,set2/review-key.json -Preferences set1/preferences.json,set2/preferences.json

.EXAMPLE
pwsh benchmark/Get-JudgeAgreement.ps1 -Key review/review-key.json -Verdicts verdicts.json -Preferences side-by-side/preferences.json
#>
[CmdletBinding(PositionalBinding = $false)]
param(
    # review-key.json from Invoke-SideBySide.ps1 -ReviewOut, one per set (a list, or one comma-separated string as pwsh -File
    # passes it): which side of each review pair had the plugin.
    [Parameter(Mandatory)][string[]]$Key,
    # preferences.json from Invoke-SideBySide.ps1 over the same results, one per set (the same way), all from one judge.
    [Parameter(Mandatory)][string[]]$Preferences,
    # The person's verdicts: a JSON array of { "id": "p01", "choice": "A" | "B" | "even" }, as the review page keeps them.
    [string]$Verdicts,
    # The folder of the owner's verdict sets and re-judges (benchmark/calibration), instead of -Verdicts.
    [string]$Calibration,
    [ValidateRange(0, 1)][double]$MinAgreement = 0.8,
    [ValidateRange(0, 1)][double]$MinConsistency = 0.9,
    [switch]$Json
)
Set-StrictMode -Version 3.0
$ErrorActionPreference = 'Stop'
$Key = @($Key -split ',' | ForEach-Object Trim | Where-Object { $_ })
$Preferences = @($Preferences -split ',' | ForEach-Object Trim | Where-Object { $_ })
if ([bool]$Verdicts -eq [bool]$Calibration) { throw 'Give -Verdicts (one set, fixed bars) or -Calibration (every set, the owner''s rule), not both or neither' }

function Get-FlippedChoice([string]$Choice) {
    switch ($Choice.ToLowerInvariant()) { 'a' { return 'b' } 'b' { return 'a' } default { return $Choice.ToLowerInvariant() } }
}

# The owner's verdicts by review id, the agreement bar and where it came from.
$verdictById = [ordered]@{}
$minAgreementSource = 'given'
$ownerSelf = $null
if ($Verdicts) {
    foreach ($vote in @(Get-Content -LiteralPath $Verdicts -Raw | ConvertFrom-Json -AsHashtable)) { $verdictById[[string]$vote.id] = [string]$vote.choice }
} else {
    $original = @{}
    $sets = [System.Collections.Generic.List[object]]::new()
    $retests = [System.Collections.Generic.List[object]]::new()
    foreach ($file in @(Get-ChildItem -LiteralPath $Calibration -Filter *.json -File | Sort-Object Name)) {
        $doc = Get-Content -LiteralPath $file.FullName -Raw | ConvertFrom-Json -AsHashtable
        if ($doc.Contains('verdicts')) { $sets.Add(@{ name = $file.Name; doc = $doc }) }
        elseif ($doc.Contains('pairs') -and $doc.Contains('result')) { $retests.Add(@{ name = $file.Name; doc = $doc }) }
        else { throw "$($file.Name) in $Calibration is neither a verdict set (verdicts) nor a re-judge (pairs and result)" }
    }
    if ($sets.Count -eq 0) { throw "No verdict set in $Calibration" }
    foreach ($set in $sets) {
        foreach ($vote in @($set.doc.verdicts)) {
            $id = [string]$vote.id
            if ($original.Contains($id)) { throw "Review id $id is in two verdict sets" }
            $original[$id] = [string]$vote.choice
            if (-not ($set.doc.Contains('forAgreement') -and -not $set.doc.forAgreement)) { $verdictById[$id] = [string]$vote.choice }
        }
    }
    # A re-judged pair was shown with A and B swapped where "swapped" is true: its verdict is turned back before use.
    $same = 0; $rejudged = 0
    foreach ($retest in $retests) {
        $sameHere = 0
        foreach ($pair in @($retest.doc.pairs)) {
            $id = [string]$pair.original
            if (-not $original.Contains($id)) { throw "$($retest.name) re-judges $id, which no verdict set has" }
            $newer = if ($pair.swapped) { Get-FlippedChoice ([string]$pair.choice) } else { ([string]$pair.choice).ToLowerInvariant() }
            if ($newer -eq $original[$id].ToLowerInvariant()) { $sameHere++ }
            $verdictById[$id] = $newer
        }
        $stated = $retest.doc.result.sameAsBefore
        if ($null -ne $stated -and [int]$stated -ne $sameHere) { throw "$($retest.name) says $stated of its pairs kept their verdict; its pairs give $sameHere" }
        $same += $sameHere; $rejudged += @($retest.doc.pairs).Count
    }
    if ($rejudged) {
        $ownerSelf = [ordered]@{ same = $same; compared = $rejudged; agreement = [Math]::Round($same / $rejudged, 4) }
        if (-not $PSBoundParameters.ContainsKey('MinAgreement')) {
            $MinAgreement = $same / $rejudged
            $minAgreementSource = "the owner's own agreement on a blind re-judge, $same of $rejudged"
        }
    } elseif (-not $PSBoundParameters.ContainsKey('MinAgreement')) {
        throw "No re-judge in $Calibration to set the agreement bar from; add one or give -MinAgreement"
    }
}

$keyPairs = @{}
foreach ($k in $Key) {
    $doc = Get-Content -LiteralPath $k -Raw | ConvertFrom-Json -AsHashtable
    foreach ($id in $doc.pairs.Keys) {
        if ($keyPairs.Contains($id)) { throw "Review id $id is in two keys" }
        $keyPairs[$id] = $doc.pairs[$id]
    }
}
$judged = @{}
$allJudged = [System.Collections.Generic.List[object]]::new()
$judgeModels = [System.Collections.Generic.List[string]]::new()
foreach ($file in $Preferences) {
    $prefs = Get-Content -LiteralPath $file -Raw | ConvertFrom-Json -AsHashtable
    if ([string]$prefs.judgeModel -notin $judgeModels) { $judgeModels.Add([string]$prefs.judgeModel) }
    foreach ($p in @($prefs.pairs)) {
        $allJudged.Add($p)
        if ($p.Contains('pair')) { $judged[$p.pair] = $p }
    }
}
if ($judgeModels.Count -ne 1) { throw "The preferences come from $($judgeModels.Count) judges ($($judgeModels -join ', ')), not one" }

$rows = [System.Collections.Generic.List[object]]::new()
foreach ($id in $verdictById.Keys) {
    if (-not $keyPairs.Contains($id)) { throw "Verdict for $id, which no review key has" }
    $entry = $keyPairs[$id]
    $choice = ([string]$verdictById[$id]).ToLowerInvariant()
    if ($choice -notin 'a', 'b', 'even') { throw "Verdict for $id is '$($verdictById[$id])': A, B or even" }
    $person = if ($choice -eq 'even') { 'even' } elseif ($choice -eq $entry.pluginIs.ToLowerInvariant()) { 'plugin' } else { 'other' }
    if (-not $judged.ContainsKey($entry.pair)) { continue }
    $j = $judged[$entry.pair]
    $choices = @($j.choices)
    # A judgement that failed ("error", outcome null) is no verdict: it neither agrees nor counts as consistent.
    $judge = if ($null -eq $j.pluginOutcome -or 'error' -in $choices) { 'error' } else { switch ([double]$j.pluginOutcome) { 1 { 'plugin' } 0 { 'other' } default { 'even' } } }
    $consistent = $judge -notin 'even', 'error' -or ($choices.Count -eq 2 -and $choices[0] -eq 'even' -and $choices[1] -eq 'even')
    $rows.Add([ordered]@{ id = $id; pair = $entry.pair; person = $person; judge = $judge; agree = ($person -eq $judge); consistent = $consistent })
}

$compared = $rows.Count
$agreed = @($rows | Where-Object { $_.agree }).Count
$agreement = if ($compared) { [Math]::Round($agreed / $compared, 4) } else { $null }
$pairsJudged = $allJudged.Count
$selfSame = @($allJudged | Where-Object { $null -ne $_.pluginOutcome -and 'error' -notin @($_.choices) -and ([double]$_.pluginOutcome -ne 0.5 -or (@($_.choices) -join ',') -eq 'even,even') }).Count
$consistency = if ($pairsJudged) { [Math]::Round($selfSame / $pairsJudged, 4) } else { $null }
# Compared unrounded, so 13 of 21 is not held to a rounded bar (a small margin absorbs the bar's own division).
$passes = $compared -gt 0 -and $pairsJudged -gt 0 -and ($agreed / $compared) -ge ($MinAgreement - 1e-9) -and ($selfSame / $pairsJudged) -ge ($MinConsistency - 1e-9)
$document = [ordered]@{
    schema = 'hyperdot-judge-agreement/1'; judgeModel = $judgeModels[0]; compared = $compared; agreement = $agreement
    pairsJudged = $pairsJudged; consistency = $consistency; minAgreement = [Math]::Round($MinAgreement, 4); minAgreementSource = $minAgreementSource
    minConsistency = $MinConsistency; ownerSelfAgreement = $ownerSelf; passes = $passes
    disagreements = @($rows | Where-Object { -not $_.agree } | ForEach-Object { [ordered]@{ id = $_.id; pair = $_.pair; person = $_.person; judge = $_.judge } })
}
if ($Json) { $document | ConvertTo-Json -Depth 5 } else {
    if (-not $compared) { Write-Host 'No pair has both a verdict and a judgement' }
    else {
        Write-Host ("{0}: agrees with the person on {1:P0} of {2} pair(s) (needs {3:P0}, {4}), with itself on {5:P0} of {6} (needs {7:P0}): {8}" -f
            $judgeModels[0], $agreement, $compared, $MinAgreement, $minAgreementSource, $consistency, $pairsJudged, $MinConsistency, $(if ($passes) { 'calibrated' } else { 'not calibrated' }))
        foreach ($d in $document.disagreements) { Write-Host "  $($d.id) $($d.pair): the person chose $($d.person), the judge $($d.judge)" }
    }
}
exit $(if ($passes) { 0 } else { 1 })
