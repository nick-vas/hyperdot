#!/usr/bin/env pwsh
# Self-test of the godot-xr skill's claims that can be held without a headset, on tests/xr-fixture through the kit's gut
# runner. The script writes every engine name the skill quotes in backticks (XRNode3D.get_pose(), Viewport.use_xr,
# xr/openxr/enabled, ...) into the fixture's test/api.txt, and copies ci/godot/templates/xr_math.gd and xr_rig.gd next to
# the scene; test/test_xr.gd then checks each name against the engine's ClassDB and project settings, runs a scene with an
# XR origin and no XR interface, drives an XRController3D from a tracker added to the XRServer, and tests the numbers (the
# peak of the last ten frames for a throw, snap turns, turning the origin about the player, the vignette, the
# one-controller choice). Then a made-up name is added to api.txt and must fail by name, so a check that stopped looking is
# noticed. Tracking quality, passthrough and how comfortable anything feels need a headset and are not run here
# (docs/roadmap.md). Needs Godot (GODOT_BIN, or the kit installs it).
Set-StrictMode -Version 3.0
$ErrorActionPreference = 'Stop'
$root = Split-Path $PSScriptRoot
$kit = Join-Path $root 'ci/godot/hyperdot.ps1'
$failures = [System.Collections.Generic.List[string]]::new()
function Assert-True([bool]$Condition, [string]$What) {
    if ($Condition) { Write-Host "ok     $What" } else { Write-Host "FAILED $What" -ForegroundColor Red; $failures.Add($What) }
}

# The names: a backticked Class.member (or Class, or a project setting under xr/) in the skill and its side files. Files,
# the kit's own scripts (XrMath, SnapTurn, Vignette) and the XR Tools add-on's classes are not the engine's.
$skillDir = Join-Path $root '.agents/skills/godot-xr'
$text = (Get-ChildItem -LiteralPath $skillDir -Recurse -File -Filter '*.md' | ForEach-Object { Get-Content -LiteralPath $_.FullName -Raw }) -join "`n"
$names = [System.Collections.Generic.SortedSet[string]]::new()
foreach ($m in [regex]::Matches($text, '`([^`\r\n]+)`')) {
    $token = $m.Groups[1].Value
    if ($token -match '^xr/[a-z_/]+$') { [void]$names.Add($token); continue }
    if ($token -match '\.(gd|tscn|tres|md|json|ps1|cs|cfg|godot|txt|zip)$') { continue }
    if ($token -cmatch '^(XR|OpenXR)[A-Za-z0-9]*(\.[A-Za-z_][A-Za-z0-9_]*)?(\(\))?$' -and $token -cnotmatch '^XRTools') { [void]$names.Add($token) }
    elseif ($token -cmatch '^(Viewport|Engine|XRServer|ProjectSettings|RenderingServer|Camera3D|Node3D)\.[A-Za-z_][A-Za-z0-9_]*(\(\))?$') { [void]$names.Add($token) }
}
Assert-True ($names.Count -ge 40) "the skill quotes at least 40 engine names: $($names.Count)"

$game = Join-Path ([IO.Path]::GetTempPath()) "xr-$([guid]::NewGuid().ToString('N').Substring(0, 8))"
Copy-Item -Recurse -LiteralPath (Join-Path $PSScriptRoot 'xr-fixture') $game
foreach ($file in 'xr_math.gd', 'xr_rig.gd') { Copy-Item -LiteralPath (Join-Path $root "ci/godot/templates/$file") (Join-Path $game $file) }
$api = Join-Path $game 'test/api.txt'
[IO.File]::WriteAllText($api, (($names -join "`n") + "`n"))

function Invoke-Xr([string]$Tag) {
    $results = Join-Path $game "r-$Tag"
    $json = pwsh -NoProfile -NonInteractive -File $kit test -Json -Quiet -Project $game -Runners gut -Results $results 2>$null | ConvertFrom-Json
    $runner = @($json.runnerResults | Where-Object runner -eq 'gut')[0]
    $log = Get-Content -LiteralPath (Join-Path $results 'gut/gut.log') -Raw
    return [pscustomobject]@{ Ok = [bool]$json.ok; Total = $runner.total; Failed = @($runner.failures).Count; Log = $log }
}

try {
    $good = Invoke-Xr 'good'
    Assert-True ($good.Ok) "the XR fixture passes: $($good.Failed) failed of $($good.Total)$(if (-not $good.Ok) { "`n" + $good.Log })"
    Assert-True ($good.Total -ge 20) "at least 20 tests ran: $($good.Total)"
    Assert-True ($good.Log -match '\d+ names checked') 'the names were counted'

    # A name the engine does not have, and a project setting it does not have, must fail and be named.
    [IO.File]::AppendAllText($api, "XRController3D.no_such_thing`nXRServer.no_such_signal`nxr/openxr/no_such_setting`n")
    $bad = Invoke-Xr 'bad'
    Assert-True (-not $bad.Ok) 'made-up names fail the run'
    foreach ($made in 'XRController3D.no_such_thing', 'XRServer.no_such_signal', 'xr/openxr/no_such_setting') {
        Assert-True ($bad.Log.Contains("missing from the engine: $made")) "the report names $made"
    }
}
finally {
    Remove-Item -Recurse -Force -LiteralPath $game -ErrorAction SilentlyContinue
}

if ($failures.Count) { Write-Host "$($failures.Count) check(s) failed" -ForegroundColor Red; exit 1 }
Write-Host 'the XR names the skill quotes exist in the engine, a scene with an XR origin runs with no interface, a tracker drives a controller, and the throw, snap-turn, origin-turn, vignette and one-controller numbers hold'
exit 0
