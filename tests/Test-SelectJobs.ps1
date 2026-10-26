#!/usr/bin/env pwsh
# Self-test of .github/scripts/Select-Jobs.ps1, which decides what the Self-test workflow runs for a change. No Godot.
# The selection is run with the changed files given (-Files), and once through git against a temporary repository.
Set-StrictMode -Version 3.0
$ErrorActionPreference = 'Stop'
$root = Split-Path $PSScriptRoot
$script = Join-Path $root '.github/scripts/Select-Jobs.ps1'
$failures = [System.Collections.Generic.List[string]]::new()

function Assert-True([bool]$Condition, [string]$Message) {
    if (-not $Condition) { $failures.Add($Message); Write-Host "FAIL $Message" -ForegroundColor Red } else { Write-Host "ok   $Message" }
}

function Get-Selection([string]$EventName = 'pull_request', [string[]]$Files = @(), [string]$Base = ('a' * 40), [string]$Where = $root, [switch]$NoFiles) {
    $arguments = @('-NoProfile', '-File', $script, '-EventName', $EventName, '-Base', $Base, '-Root', $Where, '-Json')
    if (-not $NoFiles) { $arguments += '-Files'; $arguments += $(if ($Files.Count) { $Files -join ',' } else { '' }) }
    $text = (& pwsh @arguments 2>&1) -join "`n"
    if ($LASTEXITCODE) { throw "Select-Jobs failed: $text" }
    return $text | ConvertFrom-Json
}
function Get-PairNames($Selection) { return @($Selection.pairs | ForEach-Object { "$($_.genre)/$($_.language)" }) }

$spec = Get-Content -Raw (Join-Path $root 'benchmark/game-programme.json') | ConvertFrom-Json
$written = @(foreach ($g in $spec.programme.genres) { foreach ($l in $g.languages) { if (Test-Path (Join-Path $root "benchmark/games/$($g.id)/$l")) { "$($g.id)/$l" } } })
Assert-True ($written.Count -ge 20) "the programme has its written pairs ($($written.Count))"

# Docs and unrelated files: no pair.
$s = Get-Selection -Files 'docs/ci.md', 'README.md', 'benchmark/games/arena/DESIGN.md'
Assert-True (@(Get-PairNames $s).Count -eq 0) 'prose changes run no pair of the matrix'

# The check's own code: a sample of three, one of them platformer in C# and one arena in GDScript.
foreach ($file in 'benchmark/GameProgramme.ps1', 'benchmark/game-programme.json', 'tests/Test-GameProgramme.ps1', 'benchmark/templates/csharp/Foo.cs') {
    $names = @(Get-PairNames (Get-Selection -Files $file))
    Assert-True ($names.Count -eq 3 -and 'platformer/csharp' -in $names -and 'arena/gdscript' -in $names) "$file runs the sample of three ($($names -join ', '))"
}

# A game folder: that pair, whatever else the change holds; a sample pair is not added twice.
$names = @(Get-PairNames (Get-Selection -Files 'benchmark/games/racing/csharp/Game.cs'))
Assert-True ($names.Count -eq 1 -and $names[0] -eq 'racing/csharp') "a game's folder runs its pair ($($names -join ', '))"
$names = @(Get-PairNames (Get-Selection -Files 'benchmark/games/racing/gdscript/main.gd', 'benchmark/games/arena/gdscript/main.gd', 'benchmark/GameProgramme.ps1'))
Assert-True ($names.Count -eq 4 -and 'racing/gdscript' -in $names) "a game and the check's code: the sample plus the changed pair ($($names -join ', '))"
$names = @(Get-PairNames (Get-Selection -Files 'benchmark/games/idle/shared.json'))
Assert-True ($names.Count -eq 2 -and 'idle/csharp' -in $names -and 'idle/gdscript' -in $names) "a genre's file outside both languages runs both its pairs ($($names -join ', '))"

# Everything: dispatch, push to main, schedule, no base, and a base that cannot be fetched.
foreach ($trigger in 'workflow_dispatch', 'push', 'schedule') {
    $s = Get-Selection -EventName $trigger -Files 'README.md'
    Assert-True ($s.full -and @(Get-PairNames $s).Count -eq $written.Count) "$trigger runs every pair"
}
$s = Get-Selection -Base ('0' * 40) -Files 'README.md'
Assert-True ($s.full -and @(Get-PairNames $s).Count -eq $written.Count) 'an all-zero base (a new branch) runs every pair'
$s = Get-Selection -Base '' -Files 'README.md'
Assert-True ($s.full) 'no base runs every pair'

# Through git: the files come from the diff against the base; a base git cannot fetch means everything. A repository of
# its own whose origin is itself, so nothing leaves this machine.
$temp = Join-Path ([IO.Path]::GetTempPath()) "select-jobs-$PID"
try {
    New-Item -ItemType Directory $temp | Out-Null
    foreach ($file in 'benchmark/game-programme.json') { New-Item -ItemType Directory -Force (Join-Path $temp (Split-Path $file)) | Out-Null; Copy-Item (Join-Path $root $file) (Join-Path $temp $file) }
    New-Item -ItemType Directory -Force (Join-Path $temp 'benchmark/games/arena/gdscript'), (Join-Path $temp 'benchmark/games/platformer/csharp') | Out-Null
    Set-Content (Join-Path $temp 'benchmark/games/arena/gdscript/main.gd') 'extends Node'
    Set-Content (Join-Path $temp 'benchmark/games/platformer/csharp/Game.cs') 'class A {}'
    git -C $temp init -q
    git -C $temp remote add origin $temp
    git -C $temp add -A
    git -C $temp -c user.name=ci -c user.email=ci@example.com commit -qm base
    $base = (git -C $temp rev-parse HEAD).Trim()
    Set-Content (Join-Path $temp 'benchmark/games/arena/gdscript/main.gd') 'extends Node2D'
    git -C $temp -c user.name=ci -c user.email=ci@example.com commit -qam change
    $names = @(Get-PairNames (Get-Selection -Base $base -Where $temp -NoFiles))
    Assert-True ($names.Count -eq 1 -and $names[0] -eq 'arena/gdscript') "git diff against the base finds the changed game ($($names -join ', '))"
    $s = Get-Selection -Base ('b' * 40) -Where $temp -NoFiles
    Assert-True ($s.full) 'a base git cannot fetch runs every pair'
} finally { Remove-Item -LiteralPath $temp -Recurse -Force -ErrorAction SilentlyContinue }

if ($failures.Count) { Write-Host "`n$($failures.Count) failed" -ForegroundColor Red; exit 1 }
Write-Host "`nAll passed"
