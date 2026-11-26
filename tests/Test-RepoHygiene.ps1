#!/usr/bin/env pwsh
# Self-test of doctor's repository checks (GameCI's troubleshooting, applied to Godot): Git LFS pointers left in place
# of assets, committed signing keys, names Windows cannot create, paths that differ only in case, and res:// paths whose
# case differs from the file, and a keep-aspect project whose STYLE.md lists resolutions of another shape. The broken project is made in a temporary folder: committed here, the reserved name and
# the case twins would break this repository's own checkout on Windows. Needs git; not Godot.
Set-StrictMode -Version 3.0
$ErrorActionPreference = 'Stop'
$root = Split-Path $PSScriptRoot
$failures = @()

function New-Project([string]$Name) {
    $dir = Join-Path ([System.IO.Path]::GetTempPath()) "hygiene-$Name-$([guid]::NewGuid().ToString('n').Substring(0, 8))"
    New-Item -ItemType Directory -Force (Join-Path $dir 'art') | Out-Null
    Set-Content -LiteralPath (Join-Path $dir 'project.godot') "config_version=5`n`n[application]`n`nconfig/name=`"Hygiene`"`nrun/main_scene=`"res://main.tscn`"`n"
    [System.IO.File]::WriteAllBytes((Join-Path $dir 'art/hero.png'), [byte[]](0x89, 0x50, 0x4E, 0x47) + [byte[]]::new(300))
    Set-Content -LiteralPath (Join-Path $dir 'main.tscn') "[gd_scene format=3]`n`n[ext_resource type=`"Texture2D`" path=`"res://art/hero.png`" id=`"1`"]`n`n[node name=`"Main`" type=`"Node2D`"]`n"
    & git -C $dir init -q
    return $dir
}

function Get-DoctorMessages([string]$Dir) {
    $json = & pwsh -NoProfile -NonInteractive -File (Join-Path $root 'ci/godot/hyperdot.ps1') doctor -Project $Dir -Json 2>$null
    return @(($json | Out-String | ConvertFrom-Json).checks | ForEach-Object message)
}

$clean = New-Project 'clean'
& git -C $clean add -A
$messages = Get-DoctorMessages $clean
foreach ($pattern in 'LFS pointer', 'Signing keys', 'Windows cannot create', 'differ only in case', 'res:// paths whose case') {
    if ($messages -match $pattern) { $failures += "a clean project reported '$pattern': $($messages -match $pattern)" }
}

$broken = New-Project 'broken'
Set-Content -LiteralPath (Join-Path $broken 'art/boss.png') "version https://git-lfs.github.com/spec/v1`noid sha256:4d7a214614ab2935c943f9e0ff69d22eadbb8f32b1258daaa5e2ca24d17e2393`nsize 12345`n" -NoNewline
[System.IO.File]::WriteAllBytes((Join-Path $broken 'release.keystore'), [byte[]](1, 2, 3))
[System.IO.File]::WriteAllBytes((Join-Path $broken 'local.p12'), [byte[]](1, 2, 3))   # not committed: fine
# A key in a folder with a non-ASCII name, which git quotes when it prints it ("cl\303\251s/..."); the name is written as
# code so this file stays ASCII.
$accented = 'cl' + [char]0xE9 + 's'
New-Item -ItemType Directory -Force (Join-Path $broken $accented) | Out-Null
[System.IO.File]::WriteAllBytes((Join-Path $broken "$accented/upload.keystore"), [byte[]](1, 2, 3))
if (-not $IsWindows) {
    Set-Content -LiteralPath (Join-Path $broken 'art/aux.txt') 'reserved'
    Set-Content -LiteralPath (Join-Path $broken 'art/Hero.png') 'twin'
}
Set-Content -LiteralPath (Join-Path $broken 'level.tscn') "[gd_scene format=3]`n`n[ext_resource type=`"Texture2D`" path=`"res://Art/hero.png`" id=`"1`"]`n`n[node name=`"Level`" type=`"Node2D`"]`n"
& git -C $broken add -- release.keystore "$accented/upload.keystore"
$messages = Get-DoctorMessages $broken
$expect = @(
    'Git LFS pointer files instead of assets \(LFS was not pulled\): art/boss\.png$'
    'Signing keys or login files are committed: .*release\.keystore'
    "Signing keys or login files are committed: .*$accented/upload\.keystore"
    'res:// paths whose case differs from the file.*res://Art/hero\.png \(the file is res://art/hero\.png, in level\.tscn\)'
)
if (-not $IsWindows) {
    $expect += 'Names Windows cannot create.*art/aux\.txt$'
    $expect += 'Paths that differ only in case.*art/Hero\.png and art/hero\.png|art/hero\.png and art/Hero\.png'
}
foreach ($pattern in $expect) { if (-not ($messages -match $pattern)) { $failures += "doctor should report /$pattern/; got: $($messages -join ' | ')" } }
if ($messages -match 'local\.p12') { $failures += "an uncommitted key was reported: $($messages -match 'p12')" }


# Files the kit wrote that are not committed (and doctor -ReportIssue, with a stand-in gh that logs what it is asked).
function Invoke-DoctorJson([string]$Dir, [string]$Stdin, [string[]]$Extra = @()) {
    $out = $Stdin | & pwsh -NoProfile -NonInteractive -File (Join-Path $root 'ci/godot/hyperdot.ps1') doctor -Project $Dir -Json @Extra 2>$null
    return ($out | Out-String | ConvertFrom-Json)
}
$kit = New-Project 'kitfiles'
& git -C $kit add -A
& git -C $kit -c user.name=t -c user.email=t@example.com commit -q -m start
$d = Invoke-DoctorJson $kit ''
if (@($d.checks | Where-Object message -match 'kit wrote are not committed').Count) { $failures += 'a committed project was told its kit files are uncommitted' }
if (@($d.uncommittedKitFiles).Count) { $failures += "uncommittedKitFiles should be empty: $($d.uncommittedKitFiles | ConvertTo-Json -Depth 5 -Compress)" }
Set-Content -LiteralPath (Join-Path $kit 'AGENTS.md') "Run pwsh C:/source/repos/hyperdot/ci/godot/hyperdot.ps1 test`n"
New-Item -ItemType Directory -Force (Join-Path $kit '.claude') | Out-Null
Set-Content -LiteralPath (Join-Path $kit '.claude/settings.json') '{ "enabledPlugins": { "hyperdot@hyperdot": true } }'
Set-Content -LiteralPath (Join-Path $kit '.claude/settings.local.json') '{ "env": { "GODOT_BIN": "C:/Godot/godot.exe" } }'
$d = Invoke-DoctorJson $kit ''
$warn = @($d.checks | Where-Object { $_.status -eq 'WARN' -and $_.message -match 'kit wrote are not committed' })
$paths = @($d.uncommittedKitFiles | ForEach-Object path)
if ($warn.Count -ne 1 -or $warn[0].message -notmatch 'AGENTS\.md' -or $warn[0].message -notmatch '\.claude/settings\.json') { $failures += "doctor should warn about AGENTS.md and .claude/settings.json: $($warn.message)" }
if ($paths -contains '.claude/settings.local.json' -or $warn[0].message -match 'settings\.local\.json is') { if ($paths -contains '.claude/settings.local.json') { $failures += 'the machine-local settings file was listed' } }
$agents = @($d.uncommittedKitFiles | Where-Object path -eq 'AGENTS.md')
$settings = @($d.uncommittedKitFiles | Where-Object path -eq '.claude/settings.json')
if ($agents.Count -ne 1 -or -not $agents[0].machinePath -or $agents[0].status -ne 'untracked') { $failures += "AGENTS.md names a drive path and is untracked: $($agents | ConvertTo-Json -Depth 5 -Compress)" }
if ($settings.Count -ne 1 -or $settings[0].machinePath) { $failures += "settings.json holds no machine path: $($settings | ConvertTo-Json -Depth 5 -Compress)" }
if ($warn.Count -eq 1 -and $warn[0].message -notmatch 'AGENTS\.md name') { $failures += "the warning should say AGENTS.md names a path of this machine: $($warn[0].message)" }

if (-not $IsWindows) {
    $bin = Join-Path ([System.IO.Path]::GetTempPath()) "fakegh-$([guid]::NewGuid().ToString('n').Substring(0, 8))"
    New-Item -ItemType Directory -Force $bin | Out-Null
    $log = Join-Path $bin 'calls.log'
    $existing = Join-Path $bin 'existing.json'
    Set-Content -LiteralPath $existing '[]'
    Set-Content -LiteralPath (Join-Path $bin 'gh') @'
#!/bin/sh
echo "$@" >> "$FAKE_GH_LOG"
case "$1 $2" in
  "auth status") exit 0 ;;
  "issue list") cat "$FAKE_GH_EXISTING" ;;
  "issue create")
    while [ $# -gt 0 ]; do if [ "$1" = "--body-file" ]; then cp "$2" "$FAKE_GH_LOG.body"; fi; shift; done
    echo "https://github.com/nick-vas/hyperdot/issues/999" ;;
esac
'@
    & chmod +x (Join-Path $bin 'gh')
    $oldPath = $env:PATH; $env:FAKE_GH_LOG = $log; $env:FAKE_GH_EXISTING = $existing
    $env:PATH = "$bin$([System.IO.Path]::PathSeparator)$oldPath"
    try {
        $d = Invoke-DoctorJson $kit '' @('-ReportIssue')
        $calls = if (Test-Path -LiteralPath $log) { Get-Content -LiteralPath $log -Raw } else { '' }
        if ($calls -match 'issue create') { $failures += "-ReportIssue created an issue without a yes: $calls" }
        if ($d.issue.created -or $d.issue.open -notmatch '^https://github\.com/nick-vas/hyperdot/issues/new\?title=') { $failures += "without a yes the link to file it by hand is returned: $($d.issue | ConvertTo-Json -Depth 5 -Compress)" }

        $d = Invoke-DoctorJson $kit 'n' @('-ReportIssue')
        if ((Get-Content -LiteralPath $log -Raw) -match 'issue create') { $failures += 'an n created an issue' }

        $d = Invoke-DoctorJson $kit 'y' @('-ReportIssue')
        $calls = Get-Content -LiteralPath $log -Raw
        $body = if (Test-Path -LiteralPath "$log.body") { Get-Content -LiteralPath "$log.body" -Raw } else { '' }
        if ($calls -notmatch 'issue create --repo nick-vas/hyperdot --title doctor: files the kit wrote are not committed in a game' -or -not $d.issue.created -or $d.issue.url -ne 'https://github.com/nick-vas/hyperdot/issues/999') { $failures += "a y should create the issue: $($d.issue | ConvertTo-Json -Depth 5 -Compress); calls: $calls" }
        if ($body -notmatch 'AGENTS\.md' -or $body -match [regex]::Escape($kit) -or $body -match 'C:/source|hyperdot@hyperdot|GODOT_BIN') { $failures += "the issue text should name the files only, no paths, contents or the game folder: $body" }

        Remove-Item -LiteralPath $log, "$log.body" -Force
        Set-Content -LiteralPath $existing '[{"number":7,"url":"https://github.com/nick-vas/hyperdot/issues/7"}]'
        $d = Invoke-DoctorJson $kit 'y' @('-ReportIssue')
        if ((Get-Content -LiteralPath $log -Raw) -match 'issue create' -or $d.issue.url -ne 'https://github.com/nick-vas/hyperdot/issues/7' -or $d.issue.created) { $failures += "an open issue with the title should be shown, not duplicated: $($d.issue | ConvertTo-Json -Depth 5 -Compress)" }
    } finally {
        $env:PATH = $oldPath
        Remove-Item Env:FAKE_GH_LOG, Env:FAKE_GH_EXISTING -ErrorAction SilentlyContinue
        Remove-Item -Recurse -Force $bin
    }
}
& git -C $kit add -A -- AGENTS.md .claude/settings.json
& git -C $kit -c user.name=t -c user.email=t@example.com commit -q -m kit
$d = Invoke-DoctorJson $kit ''
if (@($d.uncommittedKitFiles).Count -or @($d.checks | Where-Object message -match 'kit wrote are not committed').Count) { $failures += 'committed kit files were still reported' }
$flag = (& pwsh -NoProfile -NonInteractive -File (Join-Path $root 'ci/godot/hyperdot.ps1') test -ReportIssue -Json 2>$null | Out-String | ConvertFrom-Json)
if ($flag.error.code -ne 'invalid-arguments') { $failures += "-ReportIssue on another command should be invalid-arguments: $($flag.error | ConvertTo-Json -Depth 5 -Compress)" }

# A project that keeps its aspect ratio renders the same layout, with bars, in any other window shape: a target resolution of another shape in
# docs/STYLE.md cannot be judged by a screenshot, and doctor says so (six look rounds never judged 21:9 and 4:3 for that reason).
function New-StretchProject([string]$Name, [string]$Display, [string]$Resolutions) {
    $dir = New-Project $Name
    Set-Content -LiteralPath (Join-Path $dir 'project.godot') "config_version=5`n`n[application]`n`nconfig/name=`"Stretch`"`nrun/main_scene=`"res://main.tscn`"`n`n[display]`n`n$Display`n"
    New-Item -ItemType Directory -Force (Join-Path $dir 'docs') | Out-Null
    Set-Content -LiteralPath (Join-Path $dir 'docs/STYLE.md') "# Style`n`nResolutions: $Resolutions`n"
    & git -C $dir add -A
    return $dir
}
$base = "window/size/viewport_width=1920`nwindow/size/viewport_height=1080`nwindow/stretch/mode=`"canvas_items`""
$cases = [ordered]@{
    'keep'        = @{ display = "$base`nwindow/stretch/aspect=`"keep`""; resolutions = '1920x1080, 2560x1080, 1440x1080'; warn = $true }
    'keep-default' = @{ display = $base; resolutions = '1920x1080, 2560x1080'; warn = $true }                                  # aspect keep is Godot's default
    'keep-sameshape' = @{ display = "$base`nwindow/stretch/aspect=`"keep`""; resolutions = '1920x1080, 1280x720, 3840x2160'; warn = $false }
    'expand'      = @{ display = "$base`nwindow/stretch/aspect=`"expand`""; resolutions = '1920x1080, 2560x1080, 1440x1080'; warn = $false }
    'disabled'    = @{ display = "window/size/viewport_width=1920`nwindow/size/viewport_height=1080"; resolutions = '1920x1080, 2560x1080'; warn = $false }
}
foreach ($name in $cases.Keys) {
    $case = $cases[$name]
    $project = New-StretchProject "stretch-$name" $case.display $case.resolutions
    $messages = Get-DoctorMessages $project
    Remove-Item -Recurse -Force $project
    $hit = @($messages | Where-Object { $_ -match 'docs/STYLE\.md lists .* but the stretch aspect is' })
    if ($case.warn -and $hit.Count -ne 1) { $failures += "stretch case '$name' should warn that its other-shaped resolutions render with bars; got: $($messages -join ' | ')" }
    if (-not $case.warn -and $hit.Count -ne 0) { $failures += "stretch case '$name' should not warn about its resolutions; got: $hit" }
    if ($case.warn -and $hit.Count -eq 1 -and ($hit[0] -notmatch '2560x1080' -or $hit[0] -match '1920x1080,|, 1920x1080')) { $failures += "stretch case '$name' should name the resolutions of another shape and not the design one: $($hit[0])" }
}

# Godot builds a C# game in Debug, and a plain library the game references inherits it (issue 311): doctor says so for each
# such library without <Optimize>, and not for one that opts in, a test project, or a project the game does not reference.
$cs = New-Project 'csharp-lib'
New-Item -ItemType Directory -Force (Join-Path $cs 'src/Rules'), (Join-Path $cs 'src/Fast'), (Join-Path $cs 'tests/Rules.Tests'), (Join-Path $cs 'src/Unused') | Out-Null
Set-Content -LiteralPath (Join-Path $cs 'Game.csproj') '<Project Sdk="Godot.NET.Sdk/4.7.2"><PropertyGroup><TargetFramework>net8.0</TargetFramework></PropertyGroup><ItemGroup><ProjectReference Include="src/Rules/Rules.csproj" /><ProjectReference Include="src\Fast\Fast.csproj" /><ProjectReference Include="tests/Rules.Tests/Rules.Tests.csproj" /></ItemGroup></Project>'
Set-Content -LiteralPath (Join-Path $cs 'src/Rules/Rules.csproj') '<Project Sdk="Microsoft.NET.Sdk"><PropertyGroup><TargetFramework>net8.0</TargetFramework></PropertyGroup></Project>'
Set-Content -LiteralPath (Join-Path $cs 'src/Fast/Fast.csproj') '<Project Sdk="Microsoft.NET.Sdk"><PropertyGroup><TargetFramework>net8.0</TargetFramework><Optimize>true</Optimize></PropertyGroup></Project>'
Set-Content -LiteralPath (Join-Path $cs 'tests/Rules.Tests/Rules.Tests.csproj') '<Project Sdk="Microsoft.NET.Sdk"><ItemGroup><PackageReference Include="Microsoft.NET.Test.Sdk" Version="17.0.0" /></ItemGroup></Project>'
Set-Content -LiteralPath (Join-Path $cs 'src/Unused/Unused.csproj') '<Project Sdk="Microsoft.NET.Sdk"><PropertyGroup><TargetFramework>net8.0</TargetFramework></PropertyGroup></Project>'
& git -C $cs add -A
$messages = @(Get-DoctorMessages $cs | Where-Object { $_ -match 'runs unoptimised' })
if ($messages.Count -ne 1 -or $messages[0] -notmatch 'Rules\.csproj runs unoptimised') { $failures += "doctor should name only the referenced library without <Optimize> (Rules.csproj); got: $($messages -join ' | ')" }
Remove-Item -Recurse -Force $cs

Remove-Item -Recurse -Force $clean, $broken, $kit
if ($failures) { $failures | ForEach-Object { Write-Host "FAIL $_" -ForegroundColor Red }; exit 1 }
Write-Host 'doctor reports LFS pointers, committed keys, Windows-reserved names, case twins, res:// paths in the wrong case, uncommitted kit files (and files an issue only after a yes) and referenced C# libraries that run unoptimised, and nothing on a clean project'
exit 0
