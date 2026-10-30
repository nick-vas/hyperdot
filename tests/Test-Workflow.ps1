#!/usr/bin/env pwsh
# Self-test of the "which command now" guide: the rules in ci/godot/workflow.json (Get-SuggestedCommands), their result in
# `status -Json` as suggestedCommands[], and docs/workflow.md holding every row of the table. Times are given to the rules,
# so the cases are exact; the status part uses a temporary project. No Godot is needed.
Set-StrictMode -Version 3.0
$ErrorActionPreference = 'Stop'
$root = Split-Path $PSScriptRoot
$ci = Join-Path $root 'ci/godot/hyperdot.ps1'
$failures = @()
function Assert-True([bool]$Condition, [string]$Name) {
    if ($Condition) { Write-Host "ok     $Name" } else { Write-Host "FAIL   $Name"; $script:failures += $Name }
}
. (Join-Path $root 'ci/godot/lib/Common.ps1')
. (Join-Path $root 'ci/godot/lib/Workflow.ps1')

$table = Read-WorkflowTable
$now = [datetime]'2026-10-20T12:00:00Z'
function New-File([string]$Name, [string]$Time) {
    return [pscustomobject]@{ Name = $Name; LastWriteTimeUtc = [datetime]$Time }
}
function New-Run([bool]$Ok, [string]$Time) { return [pscustomobject]@{ ok = $Ok; time = [datetime]$Time } }
function Get-Names($Suggested) { return @($Suggested | ForEach-Object { $_.command }) }
function Invoke-Rules($Runs, $Files, $Stage) { return ,@(Get-SuggestedCommands $table $Runs $Files $Stage $now) }

$files = @((New-File 'Player.gd' '2026-10-10T10:00:00Z'), (New-File 'Main.tscn' '2026-10-10T10:00:00Z'), (New-File 'project.godot' '2026-10-10T10:00:00Z'))

# Nothing recorded: test and doctor, always; the stage rules wait for their stage.
$got = Invoke-Rules ([ordered]@{}) $files 0
Assert-True ((Get-Names $got) -join ',' -eq 'test,doctor') 'a project with no history is told to run test and doctor, nothing else at the concept stage'
$got = Invoke-Rules ([ordered]@{}) $files 2
Assert-True ((Get-Names $got) -join ',' -eq 'test,doctor,shot,export') 'at the vertical slice shot and export join (a scene exists)'
Assert-True (@($got | Where-Object { $_.command -eq 'export' })[0].args -eq '-Run') 'export is suggested with -Run'
$got = Invoke-Rules ([ordered]@{}) $files $null
Assert-True ((Get-Names $got) -join ',' -eq 'test,doctor') 'without a plan (no stage) only the stage-free rules apply'
$got = Invoke-Rules ([ordered]@{}) $files 3
Assert-True ('bench' -in (Get-Names $got) -and 'audio' -notin (Get-Names $got)) 'bench joins in production; audio needs sound files'
$got = Invoke-Rules ([ordered]@{}) ($files + (New-File 'hit.wav' '2026-10-10T10:00:00Z')) 3
Assert-True ('audio' -in (Get-Names $got)) 'audio joins in production once the project has a sound'
$got = Invoke-Rules ([ordered]@{}) $files 5
Assert-True ('credits' -in (Get-Names $got) -and 'deck' -in (Get-Names $got)) 'launch adds credits and deck'

# Runs recorded after the files: quiet. A file edited after a run: that command.
$runs = [ordered]@{ test = (New-Run $true '2026-10-12T10:00:00Z'); doctor = (New-Run $true '2026-10-12T10:00:00Z') }
Assert-True ((Invoke-Rules $runs $files 0).Count -eq 0) 'runs newer than every file suggest nothing'
$edited = @($files[0], (New-File 'Main.tscn' '2026-10-15T10:00:00Z'), $files[2])
Assert-True ((Get-Names (Invoke-Rules $runs $edited 0)) -join ',' -eq 'test') 'a scene edited after the last test run suggests test, not doctor'
$edited = @($files[0], $files[1], (New-File 'project.godot' '2026-10-15T10:00:00Z'))
Assert-True ((Get-Names (Invoke-Rules $runs $edited 0)) -join ',' -eq 'test,doctor') 'project.godot edited after the runs suggests test and doctor'
$edited = @($files[0], $files[1], $files[2], (New-File 'plugin.cfg' '2026-10-15T10:00:00Z'))
Assert-True ((Get-Names (Invoke-Rules $runs $edited 0)) -join ',' -eq 'doctor') 'a changed add-on suggests doctor only'

# A failed run comes first with its own reason and is reported once.
$runs = [ordered]@{ test = (New-Run $false '2026-10-18T10:00:00Z'); doctor = (New-Run $true '2026-10-18T10:00:00Z') }
$got = Invoke-Rules $runs $files 0
Assert-True ($got.Count -eq 1 -and $got[0].rule -eq 'test.failed' -and $got[0].reason -match 'failed') 'a failed test run is suggested once, with the failure as the reason'

# Age rules.
$runs = [ordered]@{ test = (New-Run $true '2026-10-12T10:00:00Z'); doctor = (New-Run $true '2026-10-10T10:00:00Z'); bench = (New-Run $true '2026-10-01T10:00:00Z')
    export = (New-Run $true '2026-09-01T10:00:00Z'); shot = (New-Run $true '2026-10-12T10:00:00Z'); credits = (New-Run $true '2026-10-12T10:00:00Z')
    deck = (New-Run $true '2026-10-12T10:00:00Z') }
$names = Get-Names (Invoke-Rules $runs $files 5)
Assert-True ('doctor' -in $names -and 'export' -in $names -and 'bench' -in $names) 'at launch an old doctor, export and bench run are suggested again'
$names = Get-Names (Invoke-Rules $runs $files 3)
Assert-True ('doctor' -notin $names -and 'export' -notin $names -and 'bench' -notin $names) 'the same ages say nothing before their stage'

# The stage of a phase: every phase of both shipped plans is known.
foreach ($plan in 'plan.json', 'plan-jam.json') {
    $doc = Get-Content -LiteralPath (Join-Path $root "ci/godot/templates/$plan") -Raw | ConvertFrom-Json -Depth 10
    $unknown = @($doc.phases | Where-Object { $null -eq (Get-WorkflowStage $table $_.id) } | ForEach-Object { $_.id })
    Assert-True ($unknown.Count -eq 0) "every phase of $plan has a stage in workflow.json ($($unknown -join ', '))"
}
Assert-True ($null -eq (Get-WorkflowStage $table 'my-own-phase')) 'a phase the table does not know has no stage'

# Every rule names a command the kit has, and every command in the table is documented in docs/workflow.md.
$help = Get-Content -LiteralPath (Join-Path $root 'docs/help.md') -Raw
foreach ($rule in $table.rules) {
    Assert-True ($help -match "(?m)^### $([regex]::Escape($rule.command))\s*$") "rule $($rule.id) names a command help.md describes"
}
$page = (Get-Content -LiteralPath (Join-Path $root 'docs/workflow.md') -Raw) -replace '`', ''
foreach ($row in $table.cadence) {
    Assert-True ($page.Contains($row.when) -and $page.Contains($row.run)) "docs/workflow.md has the row: $($row.when)"
}

# End to end: status -Json in a temporary project.
$dir = Join-Path ([System.IO.Path]::GetTempPath()) "workflow-$([guid]::NewGuid().ToString('n').Substring(0, 8))"
New-Item -ItemType Directory -Force (Join-Path $dir '.godot') | Out-Null
Set-Content -LiteralPath (Join-Path $dir 'project.godot') "config_version=5`n`n[application]`n`nconfig/name=`"Workflow`"`n"
try {
    $out = & pwsh -NoProfile -NonInteractive -File $ci status -Json -Project $dir 2>$null | Out-String
    $doc = $out | ConvertFrom-Json
    Assert-True (@($doc.suggestedCommands | ForEach-Object { $_.command }) -join ',' -eq 'test,doctor') 'status -Json lists test and doctor for a project that never ran them'
    Assert-True ($doc.suggestedCommands[0].rule -eq 'test.never' -and $doc.suggestedCommands[0].reason) 'each suggestion carries its rule and reason'
    $history = [ordered]@{ time = (Get-Date).ToUniversalTime().AddMinutes(1).ToString('o'); command = 'test'; ok = $true; code = ''; seconds = 1 } | ConvertTo-Json -Compress -Depth 4
    $history2 = [ordered]@{ time = (Get-Date).ToUniversalTime().AddMinutes(1).ToString('o'); command = 'doctor'; ok = $true; code = ''; seconds = 1 } | ConvertTo-Json -Compress -Depth 4
    Set-Content -LiteralPath (Join-Path $dir '.godot/hyperdot-history.jsonl') @($history, $history2)
    $doc = (& pwsh -NoProfile -NonInteractive -File $ci status -Json -Project $dir 2>$null | Out-String) | ConvertFrom-Json
    Assert-True (@($doc.suggestedCommands).Count -eq 0) 'status -Json suggests nothing once both ran after every file'
    $text = & pwsh -NoProfile -NonInteractive -File $ci status -Project $dir 2>&1 | Out-String
    Assert-True ($text -notmatch 'Run next') 'plain status prints no Run next line then'
} finally { Remove-Item -LiteralPath $dir -Recurse -Force -ErrorAction SilentlyContinue }

if ($failures.Count) { Write-Host "`n$($failures.Count) failed"; exit 1 }
Write-Host "`nall passed"
