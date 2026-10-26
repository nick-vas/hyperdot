#Requires -Version 7.6
# Self-test for Test-Skills.ps1: every deliberately broken fixture must trigger its rule, and the real skills must pass.
$ErrorActionPreference = 'Stop'
Set-StrictMode -Version 3.0
$root = Split-Path $PSScriptRoot
$validator = Join-Path $root 'ci/godot/tools/Test-Skills.ps1'
$expected = Get-Content -LiteralPath (Join-Path $PSScriptRoot 'skill-fixtures/expected.json') -Raw | ConvertFrom-Json -AsHashtable

$real = & pwsh -NoProfile -NonInteractive -File $validator -Json | ConvertFrom-Json
if (-not $real.ok) { throw "The real skills fail validation ($($real.errors) error(s)); run ci/godot/tools/Test-Skills.ps1" }

$all = & pwsh -NoProfile -NonInteractive -File $validator -Json -IncludeFixtures | ConvertFrom-Json
$failed = 0
foreach ($fixture in $expected.Keys) {
    $hit = @($all.findings | Where-Object { $_.skill -eq $fixture -and $_.rule -eq $expected[$fixture] -and $_.level -eq 'error' })
    if ($hit.Count -eq 0) { Write-Host "MISSED   $fixture should trigger $($expected[$fixture])" -ForegroundColor Red; $failed++ }
    else { Write-Host "caught   $fixture -> $($expected[$fixture])" }
}
if ($all.ok) { Write-Host 'The validator passed with the broken fixtures included' -ForegroundColor Red; $failed++ }
exit ($failed -gt 0 ? 1 : 0)
