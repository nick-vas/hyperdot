#Requires -Version 7.6
# Self-test of paths and text the kit puts into other text: the kit run from a folder whose name holds [ ] (a runner finds
# its tool, which -Path would read as a wildcard), project.godot's version line and solution_directory entry when the value
# holds $ (a replacement string reads $0, $1 and $& as groups of the match). -NoGodot skips the run from the folder.
param([switch]$NoGodot)
$ErrorActionPreference = 'Stop'
Set-StrictMode -Version 3.0
$root = Split-Path $PSScriptRoot
foreach ($lib in 'Common', 'Version', 'Init') { . (Join-Path $root "ci/godot/lib/$lib.ps1") }
$failures = [System.Collections.Generic.List[string]]::new()
function Assert-True([bool]$Condition, [string]$What) {
    if ($Condition) { Write-Host "ok     $What" } else { Write-Host "FAILED $What" -ForegroundColor Red; $failures.Add($What) }
}
$temp = Join-Path ([IO.Path]::GetTempPath()) "kit-paths-$([guid]::NewGuid().ToString('N').Substring(0, 8))"
New-Item -ItemType Directory -Force -Path $temp | Out-Null
try {
    # The version line: replaced when present, added under [application] when not, whatever the line holds.
    $line = 'config/version="$0 $1 $& ${x}"'
    $has = Set-ProjectVersionLine "[application]`nconfig/name=`"G`"`nconfig/version=`"1.0`"`nconfig/icon=`"i`"`n" $line
    Assert-True ($has -eq "[application]`nconfig/name=`"G`"`n$line`nconfig/icon=`"i`"`n") "a version line with \$ replaces the old one as it is: $has"
    $none = Set-ProjectVersionLine "[application]`n`nconfig/name=`"G`"`n" $line
    Assert-True ($none -eq "[application]`n`n$line`nconfig/name=`"G`"`n") "a version line with \$ is added under [application] as it is: $none"

    # solution_directory: the folder's name goes in as it is, with or without a [dotnet] section.
    foreach ($case in @(@{ Name = 'with'; Godot = "[application]`n`n[dotnet]`n`nproject/assembly_name=`"G`"`n" }, @{ Name = 'without'; Godot = "[application]`n" })) {
        $project = Join-Path $temp "game-$($case.Name)"
        New-Item -ItemType Directory -Force -Path (Join-Path $project 'Sol$0 [a]') | Out-Null
        Set-Content -LiteralPath (Join-Path $project 'project.godot') -Value $case.Godot -Encoding utf8
        Set-SolutionDirectory $project (Join-Path $project 'Sol$0 [a]/G.sln') 6>$null
        $text = Get-Content -LiteralPath (Join-Path $project 'project.godot') -Raw
        Assert-True ($text.Contains('project/solution_directory="Sol$0 [a]"')) "solution_directory keeps \$ and brackets $($case.Name) a [dotnet] section: $($text -replace '\s+', ' ')"
    }

    # The kit run from a folder with [ ] in its name: the textsize runner still finds its tool.
    if ($NoGodot) { Write-Host 'skip   the run from a folder with [ ] (-NoGodot)' } else {
        $kitCopy = Join-Path $temp 'kit [v2]'
        New-Item -ItemType Directory -Force -Path (Join-Path $kitCopy 'ci') | Out-Null
        Copy-Item -LiteralPath (Join-Path $root 'ci/godot') -Destination (Join-Path $kitCopy 'ci/godot') -Recurse
        Copy-Item -LiteralPath (Join-Path $root '.gdignore') -Destination $kitCopy
        $results = Join-Path $temp 'results'
        $out = & pwsh -NoProfile -NonInteractive -File (Join-Path $kitCopy 'ci/godot/hyperdot.ps1') test -Json -Quiet -Project (Join-Path $PSScriptRoot 'textsize-fixture') -Runners textsize -Results $results 2>$null
        $json = if ($out) { $out | ConvertFrom-Json } else { $null }
        $runner = if ($json -and $json.PSObject.Properties['runnerResults']) { @($json.runnerResults | Where-Object runner -eq 'textsize')[0] } else { $null }
        Assert-True ($null -ne $runner -and @($runner.failures | Where-Object name -eq 'textsize.1280x800').Count -eq 1) "textsize runs from 'kit [v2]' and finds its tool: $(if ($json -and $json.PSObject.Properties['error']) { $json.error.message })"
    }
} finally {
    Remove-Item -LiteralPath $temp -Recurse -Force -ErrorAction SilentlyContinue
}
if ($failures.Count) { throw "$($failures.Count) kit path check(s) failed" }
Write-Host 'Kit paths self-test passed'
