#Requires -Version 7.6
# Stop hook: keeps the game's GitHub Project in step with plan/plan.json. When the plan has a project (plan -Do sync -Board
# <owner> made one, or plan -Do link -Board <owner>/<number> chose one) and its tasks changed since the last sync, it runs
# `plan -Do sync`, so a task added or moved during the turn shows on the board without anyone asking. It never blocks the
# turn: a failure (gh missing or not signed in with the project scope, no network) becomes a one-line notice and exit 0.
# The last synced state is a hash in .godot/hyperdot-project-sync, so an unchanged plan costs no call. Set
# HYPERDOT_PROJECT_SYNC=off to disable it.
$ErrorActionPreference = 'Stop'
Set-StrictMode -Version 3.0

function Exit-Quiet { exit 0 }
function Write-Notice([string]$Message) { [Console]::Out.WriteLine((ConvertTo-Json -InputObject ([ordered]@{ systemMessage = $Message }) -Compress -Depth 3)); exit 0 }

if ($env:HYPERDOT_PROJECT_SYNC -eq 'off') { Exit-Quiet }
$projectDir = $env:CLAUDE_PROJECT_DIR
if (-not $projectDir) {
    try { $projectDir = ([Console]::In.ReadToEnd() | ConvertFrom-Json).cwd } catch { Exit-Quiet }
}
if (-not $projectDir -or -not (Test-Path -LiteralPath $projectDir -PathType Container)) { Exit-Quiet }
$projectDir = (Get-Item -LiteralPath $projectDir).FullName
$planPath = Join-Path $projectDir 'plan/plan.json'
if (-not (Test-Path -LiteralPath $planPath -PathType Leaf)) { Exit-Quiet }

# A hash of what the sync mirrors: each task's id, title, column and item, and the project itself.
function Get-PlanHash([string]$Path) {
    try { $plan = Get-Content -LiteralPath $Path -Raw | ConvertFrom-Json -Depth 20 } catch { return $null }
    if (-not $plan.PSObject.Properties['project'] -or $plan.project -isnot [pscustomobject]) { return $null }
    if (-not $plan.project.PSObject.Properties['number'] -or -not $plan.project.number) { return $null }
    $rows = @(@($plan.tasks) | Where-Object { $_ } | ForEach-Object {
        "$($_.id)|$($_.title)|$($_.column)|$($_.PSObject.Properties['itemId'] ? $_.itemId : '')" })
    $text = "$($plan.project.owner)/$($plan.project.number)`n" + ($rows -join "`n") + "`n" + (@($plan.project.PSObject.Properties['toArchive'] ? $plan.project.toArchive : @()) -join ',')
    return [Convert]::ToHexString([Security.Cryptography.SHA256]::HashData([Text.Encoding]::UTF8.GetBytes($text)))
}

$before = Get-PlanHash $planPath
if (-not $before) { Exit-Quiet }
$stampPath = Join-Path $projectDir '.godot/hyperdot-project-sync'
$stamp = (Test-Path -LiteralPath $stampPath) ? (Get-Content -LiteralPath $stampPath -Raw).Trim() : ''
if ($stamp -eq $before) { Exit-Quiet }

$kit = Join-Path $PSScriptRoot '../ci/godot/hyperdot.ps1'
$out = & (Get-Process -Id $PID).Path -NoProfile -NonInteractive -File $kit plan -Do sync -Json -Project $projectDir 2>$null
$result = $null
try { $result = ($out -join "`n") | ConvertFrom-Json } catch { Write-Verbose "the sync printed no JSON: $($_.Exception.Message)" }
if (-not $result) { Write-Notice 'The GitHub Project sync printed no result; run `plan -Do sync` to see why.' }
if (-not $result.ok) { Write-Notice "The GitHub Project sync failed ($($result.error.code)): $($result.error.message)" }

# The sync rewrites plan.json (item ids), so the stamp is the hash of the file as it is now.
$after = Get-PlanHash $planPath
New-Item -ItemType Directory -Force (Split-Path $stampPath) | Out-Null
Set-Content -LiteralPath $stampPath -Value $after -NoNewline
$s = $result.sync
$changed = [int]$s.created + [int]$s.moved + [int]$s.itemsMoved + [int]$s.imported + [int]$s.archived
if ($changed -gt 0) {
    Write-Notice "GitHub Project $($s.board) synced: $($s.created) item(s) created, $($s.itemsMoved + $s.moved) moved, $($s.imported) added from the board, $($s.archived) archived."
}
Exit-Quiet
