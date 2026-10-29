#!/usr/bin/env pwsh
# Self-test of project detection: which solution a C# game builds and tests with (Find-Solution), and the GoDotTest
# scene. Copies of the C# example's solution in temporary folders, with and without git; runs without Godot or .NET.
Set-StrictMode -Version 3.0
$ErrorActionPreference = 'Stop'
$root = Split-Path $PSScriptRoot
foreach ($lib in 'Common', 'Detect', 'Localization', 'Architecture', 'Report', 'Runners') { . (Join-Path $root "ci/godot/lib/$lib.ps1") }
$failures = @()
$dir = Join-Path ([System.IO.Path]::GetTempPath()) "detect-$PID"
$hasGit = [bool](Get-Command git -ErrorAction SilentlyContinue)

# A folder with the C# example's solution and the game's .csproj at their real places.
function New-ExampleCopy([string]$Name, [switch]$Git) {
    $copy = Join-Path $dir $Name
    New-Item -ItemType Directory -Force -Path (Join-Path $copy 'game') | Out-Null
    Copy-Item -LiteralPath (Join-Path $root 'examples/csharp/Example.sln') -Destination $copy
    Copy-Item -LiteralPath (Join-Path $root 'examples/csharp/game/Example.csproj') -Destination (Join-Path $copy 'game')
    if ($Git) { git init -q $copy 2>&1 | Out-Null }
    return $copy
}
function Get-Leaf([string]$Path) { if ($Path) { return Split-Path -Leaf $Path } return '' }

try {
    # Outside any git repository the search still climbs from game/ to the solution beside it: stopping at the
    # project folder built game/Example.csproj alone and ran a fraction of the tests, green.
    $copy = New-ExampleCopy 'nogit'
    $found = Get-Leaf (Find-Solution (Join-Path $copy 'game'))
    if ($found -ne 'Example.sln') { $failures += "outside git: expected Example.sln, got '$found'" }

    if ($hasGit) {
        $copy = New-ExampleCopy 'git' -Git
        $found = Get-Leaf (Find-Solution (Join-Path $copy 'game'))
        if ($found -ne 'Example.sln') { $failures += "in a git repository: expected Example.sln, got '$found'" }
    }

    # A solution that lists another project whose name ends the same (tools\OtherGame\OtherGame.csproj ends in
    # Game.csproj) is not the game's, with or without git.
    foreach ($git in @($false, $true)) {
        if ($git -and -not $hasGit) { continue }
        $copy = Join-Path $dir "tools-$git"
        New-Item -ItemType Directory -Force -Path (Join-Path $copy 'game') | Out-Null
        Set-Content -LiteralPath (Join-Path $copy 'game/Game.csproj') -Value '<Project Sdk="Godot.NET.Sdk/4.7.2"></Project>'
        Set-Content -LiteralPath (Join-Path $copy 'Tools.sln') -Value @'
Project("{FAE04EC0-301F-11D3-BF4B-00C04F79EFBC}") = "OtherGame", "tools\OtherGame\OtherGame.csproj", "{6D3E5A40-6C1B-4A56-9C2B-0F3A1B2C4D5E}"
EndProject
'@
        if ($git) { git init -q $copy 2>&1 | Out-Null }
        $found = Get-Leaf (Find-Solution (Join-Path $copy 'game'))
        if ($found -ne 'Game.csproj') { $failures += "an unrelated Tools.sln (git: $git) should be skipped, got '$found'" }

        # An empty solution is skipped rather than failing detection for every command.
        New-Item -ItemType File -Path (Join-Path $copy 'Empty.sln') | Out-Null
        try {
            $found = Get-Leaf (Find-Solution (Join-Path $copy 'game'))
            if ($found -ne 'Game.csproj') { $failures += "an empty .sln (git: $git) should be skipped, got '$found'" }
        } catch { $failures += "an empty .sln (git: $git) broke detection: $_" }

        # A .slnx that lists the project (forward slashes) is the solution.
        Set-Content -LiteralPath (Join-Path $copy 'Game.slnx') -Value '<Solution><Project Path="game/Game.csproj" /></Solution>'
        $found = Get-Leaf (Find-Solution (Join-Path $copy 'game'))
        if ($found -ne 'Game.slnx') { $failures += "a .slnx listing the project (git: $git) should be chosen, got '$found'" }
    }

    # GoDotTest's scene is found past an empty .tscn, which used to throw.
    $game = Join-Path $dir 'godottest'
    New-Item -ItemType Directory -Force -Path (Join-Path $game 'test') | Out-Null
    Set-Content -LiteralPath (Join-Path $game 'project.godot') -Value 'config_version=5'
    Set-Content -LiteralPath (Join-Path $game 'test/Tests.cs') -Value 'public partial class Tests : Node { public override void _Ready() => GoTest.RunTests(null, this, null); }'
    New-Item -ItemType File -Path (Join-Path $game 'a_empty.tscn') | Out-Null
    Set-Content -LiteralPath (Join-Path $game 'test/Tests.tscn') -Value '[ext_resource type="Script" path="res://test/Tests.cs" id="1"]'
    try {
        $scene = Find-GoDotTestScene $game
        if ($scene -ne 'res://test/Tests.tscn') { $failures += "GoDotTest scene: expected res://test/Tests.tscn, got '$scene'" }
    } catch { $failures += "an empty .tscn broke the GoDotTest scene search: $_" }

    # A solution above the repository's root is not the game's: the search stops at the git root.
    if ($hasGit) {
        $repo = Join-Path $dir 'above-root/repo'
        New-Item -ItemType Directory -Force -Path (Join-Path $repo 'game') | Out-Null
        Set-Content -LiteralPath (Join-Path $repo 'game/Game.csproj') -Value '<Project Sdk="Godot.NET.Sdk/4.7.2"></Project>'
        Set-Content -LiteralPath (Join-Path $dir 'above-root/Outer.sln') -Value '"Game", "repo\game\Game.csproj", "{6D3E5A40-6C1B-4A56-9C2B-0F3A1B2C4D5E}"'
        git init -q $repo 2>&1 | Out-Null
        $found = Get-Leaf (Find-Solution (Join-Path $repo 'game'))
        if ($found -ne 'Game.csproj') { $failures += "a solution above the git root should not be picked, got '$found'" }
    }
    # Two solutions that list the project: the first by name wins.
    $two = Join-Path $dir 'two-solutions'
    New-Item -ItemType Directory -Force -Path (Join-Path $two 'game') | Out-Null
    Set-Content -LiteralPath (Join-Path $two 'game/Game.csproj') -Value '<Project Sdk="Godot.NET.Sdk/4.7.2"></Project>'
    foreach ($name in 'B.sln', 'A.sln') { Set-Content -LiteralPath (Join-Path $two $name) -Value '"Game", "game\Game.csproj", "{6D3E5A40-6C1B-4A56-9C2B-0F3A1B2C4D5E}"' }
    $found = Get-Leaf (Find-Solution (Join-Path $two 'game'))
    if ($found -ne 'A.sln') { $failures += "of two solutions the first by name should win, got '$found'" }

    # -Project naming a repository whose project.godot is in a subfolder finds the shallowest one, like running from that folder.
    $repo = Join-Path $dir 'repo'
    New-Item -ItemType Directory -Force -Path (Join-Path $repo 'Template/addons') | Out-Null
    Set-Content -LiteralPath (Join-Path $repo 'Template/project.godot') "config_version=5`n"
    Set-Content -LiteralPath (Join-Path $repo 'Template/addons/project.godot') "config_version=5`n"
    $info = Get-ProjectInfo -Project $repo -Solution '' -GodotVersion '' -Runners @()
    if ((Split-Path -Leaf $info.ProjectDir) -ne 'Template') { $failures += "-Project at a repository root should find Template/, got '$($info.ProjectDir)'" }
    $none = Join-Path $dir 'empty-repo'
    New-Item -ItemType Directory -Force -Path $none | Out-Null
    $out = & pwsh -NoProfile -NonInteractive -File (Join-Path $root 'ci/godot/hyperdot.ps1') detect -Json -Project $none 2>$null
    $detected = ($out -join "`n") | ConvertFrom-Json
    if ($detected.ok) { $failures += '-Project at a folder with no project.godot below it should still fail' }
} finally {
    Remove-Item -LiteralPath $dir -Recurse -Force -ErrorAction SilentlyContinue
}

if ($failures) {
    foreach ($failure in $failures) { Write-Host "FAIL: $failure" -ForegroundColor Red }
    exit 1
}
Write-Host 'Detection self-test passed.' -ForegroundColor Green
exit 0
