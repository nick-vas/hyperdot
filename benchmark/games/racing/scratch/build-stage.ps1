# Builds a stage of the racing game into a folder: pwsh build-stage.ps1 <stage> <out>
param([string]$Stage, [string]$Out)
$ErrorActionPreference = 'Stop'
$root = '/home/user/wt-racing'
. "$root/benchmark/GameProgramme.ps1"
$cell = [pscustomobject]@{ Genre = @{ id = 'racing' }; Language = 'gdscript'; Stage = $Stage; Dir = "$root/benchmark/games/racing/gdscript" }
$manifest = Read-JsonFile "$($cell.Dir)/stages/$Stage.json"
$dir = New-StageFixture $cell $manifest
if (Test-Path $Out) { Remove-Item -Recurse -Force $Out }
Copy-Item -Recurse $dir $Out
Remove-StageFixtures
Write-Host "built $Stage in $Out"
