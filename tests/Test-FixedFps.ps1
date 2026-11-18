#!/usr/bin/env pwsh
# Self-test of test -FixedFps beyond smoke: the run settings gdUnit4Net reads give its Godot --fixed-fps only when asked,
# the game's physics tick rate is read from project.godot (60 when unset), a rate that differs from it is a warning, and
# -FixedFps is refused on other commands and below 0. No Godot is needed. The speed-up itself was measured on the C#
# example (docs/research.md): gdUnit4 from 36 s to 13 s with the same 33 tests passing and planted bugs still caught.
Set-StrictMode -Version 3.0
$ErrorActionPreference = 'Stop'
$root = Split-Path $PSScriptRoot
$ci = Join-Path $root 'ci/godot/hyperdot.ps1'
$failures = @()
function Assert-True([bool]$Condition, [string]$Name) {
    if ($Condition) { Write-Host "ok     $Name" } else { Write-Host "FAIL   $Name"; $script:failures += $Name }
}
foreach ($lib in 'Common', 'Runners') { . (Join-Path $root "ci/godot/lib/$lib.ps1") }
$work = Join-Path ([System.IO.Path]::GetTempPath()) "fixedfps-$([guid]::NewGuid().ToString('n').Substring(0, 8))"
New-Item -ItemType Directory -Force $work | Out-Null
try {
    # --- The run settings ---
    $plain = [xml](Get-Content -LiteralPath (New-RunSettings $work '' 0) -Raw)
    Assert-True ($plain.RunSettings.GdUnit4.Parameters -eq '--headless') "without -FixedFps gdUnit4's Godot runs in real time: '$($plain.RunSettings.GdUnit4.Parameters)'"
    $fixed = [xml](Get-Content -LiteralPath (New-RunSettings $work '' 60) -Raw)
    Assert-True ($fixed.RunSettings.GdUnit4.Parameters -eq '--headless --fixed-fps 60') "with -FixedFps 60 it gets --fixed-fps 60: '$($fixed.RunSettings.GdUnit4.Parameters)'"

    # --- The tick rate ---
    $game = Join-Path $work 'game'
    New-Item -ItemType Directory -Force $game | Out-Null
    Assert-True ((Get-PhysicsTickRate $game) -eq 60) 'no project.godot: Godot''s default, 60'
    Set-Content -LiteralPath (Join-Path $game 'project.godot') -Value "config_version=5`n`n[application]`n`nconfig/name=`"T`"`n"
    Assert-True ((Get-PhysicsTickRate $game) -eq 60) 'a project that does not set it: 60'
    Set-Content -LiteralPath (Join-Path $game 'project.godot') -Value "config_version=5`n`n[rendering]`n`ncommon/physics_ticks_per_second=30`n`n[physics]`n`ncommon/physics_ticks_per_second=120`n"
    Assert-True ((Get-PhysicsTickRate $game) -eq 120) 'the [physics] value is read, not a key of the same name in another section'

    # --- The warning ---
    Assert-True ($null -eq (Get-FixedFpsWarning $game 0)) '-FixedFps 0 (real time): no warning'
    Assert-True ($null -eq (Get-FixedFpsWarning $game 120)) 'the game''s own rate: no warning'
    $warning = Get-FixedFpsWarning $game 60
    Assert-True ($warning -match '^-FixedFps 60 differs from the game''s physics tick rate \(120 per second' -and $warning -match 'each frame runs 2 physics ticks' -and $warning -match 'Use -FixedFps 120$') "another rate is a warning naming the right one: $warning"

    # --- Refusals, before any setup ---
    $gdscript = Join-Path $root 'examples/gdscript'
    $out = & pwsh -NoProfile -NonInteractive -File $ci doctor -FixedFps 60 -Json -Project $gdscript 2>$null | Out-String
    $doc = $out | ConvertFrom-Json
    Assert-True ($doc.error.code -eq 'invalid-arguments' -and $doc.error.message -match 'for test') "-FixedFps on another command is invalid-arguments: $($doc.error.message)"
    $out = & pwsh -NoProfile -NonInteractive -File $ci test -FixedFps -5 -Json -Project $gdscript -Results (Join-Path $work 'r') 2>$null | Out-String
    $doc = $out | ConvertFrom-Json
    Assert-True ($doc.error.code -eq 'invalid-arguments' -and $doc.error.message -match 'not -5') "a negative -FixedFps is invalid-arguments: $($doc.error.message)"
} finally { Remove-Item -LiteralPath $work -Recurse -Force -ErrorAction SilentlyContinue }

if ($failures.Count) { Write-Host "`n$($failures.Count) failed"; exit 1 }
Write-Host "`nFixedFps self-test passed"
exit 0
