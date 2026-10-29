#!/usr/bin/env pwsh
# Self-test of Invoke-GodotRetried: a crash (exit 134, or a negative Windows code) is repeated up to twice and the file
# the crashed run left is deleted first; an ordinary failure, a hang's 124 and a crash on every run are not hidden.
# pwsh stands in for Godot, counting its runs in a file, so this runs on every OS without Godot.
Set-StrictMode -Version 3.0
$ErrorActionPreference = 'Stop'
. (Join-Path $PSScriptRoot '../ci/godot/lib/Common.ps1')

$pwshPath = (Get-Process -Id $PID).Path
$dir = Join-Path ([IO.Path]::GetTempPath()) "crash-retry-$PID"
New-Item -ItemType Directory -Force $dir | Out-Null
$log = Join-Path $dir 'run.log'
$output = Join-Path $dir 'game.pck'
$failures = @()

# Runs the stand-in once per exit code in $Codes, in order (the last repeats), and returns the result and run count.
function Invoke-StandIn([int[]]$Codes) {
    $counter = Join-Path $dir 'runs.txt'
    Set-Content -LiteralPath $counter -Value 0
    if (Test-Path -LiteralPath $output) { Remove-Item -LiteralPath $output }
    $script = @"
`$n = [int](Get-Content -LiteralPath '$counter') + 1
Set-Content -LiteralPath '$counter' -Value `$n
`$codes = @($($Codes -join ', '))
if (Test-Path -LiteralPath '$output') { Write-Output 'stale output present' }
Set-Content -LiteralPath '$output' -Value "run `$n"
exit `$codes[[Math]::Min(`$n, `$codes.Count) - 1]
"@
    $result = Invoke-GodotRetried @('-NoProfile', '-Command', $script) $log 'export' $output $pwshPath
    return [pscustomobject]@{ Code = $result.Code; Retries = $result.Retries; Runs = [int](Get-Content -LiteralPath $counter) }
}

# Linux and macOS exit codes are 0 to 255, so a crash there is a signal (139, a segmentation fault); on Windows it is a
# negative NTSTATUS code.
$segfault = if ($IsWindows) { -1073741819 } else { 139 }
$cases = @(
    @{ Name = 'a clean run'; Codes = @(0); Code = 0; Retries = 0 }
    @{ Name = 'an abort, then a clean run'; Codes = @(134, 0); Code = 0; Retries = 1 }
    @{ Name = 'a segmentation fault twice, then a clean run'; Codes = @($segfault, $segfault, 0); Code = 0; Retries = 2 }
    @{ Name = 'an abort on every run'; Codes = @(134); Code = 134; Retries = 2 }
    @{ Name = 'an ordinary failure'; Codes = @(1); Code = 1; Retries = 0 }
    @{ Name = 'a hang stopped by the time limit'; Codes = @(124); Code = 124; Retries = 0 }
)
foreach ($case in $cases) {
    $r = Invoke-StandIn $case.Codes
    if ($r.Code -ne $case.Code -or $r.Retries -ne $case.Retries -or $r.Runs -ne $case.Retries + 1) {
        $failures += "$($case.Name): exit $($r.Code), $($r.Retries) retries, $($r.Runs) runs; expected exit $($case.Code), $($case.Retries) retries"
    }
    # Every repeat starts without the crashed run's file, and the log holds only the last run.
    if ((Get-Content -LiteralPath $log -Raw) -match 'stale output present') { $failures += "$($case.Name): a repeat found the crashed run's file" }
}

# The build's import judges errors after one more import: a stand-in Godot (a shell script) that prints an error only on its
# first run passes with importRepeated; one that prints it every time still fails with engine-errors. Not on Windows.
if (-not $IsWindows) {
    $game = Join-Path $dir 'game'
    New-Item -ItemType Directory -Force $game | Out-Null
    Set-Content -LiteralPath (Join-Path $game 'project.godot') -Value "config_version=5`n[application]`nconfig/name=`"x`"`nconfig/features=PackedStringArray(`"4.7`")`n"
    $stand = Join-Path $dir 'fake-godot'
    $count = Join-Path $dir 'imports.txt'
    foreach ($case in @(@{ Name = 'an error only on the first import'; Every = 0; Ok = $true }, @{ Name = 'an error on every import'; Every = 1; Ok = $false })) {
        Set-Content -LiteralPath $count -Value 0
        Set-Content -LiteralPath $stand -NoNewline -Value "#!/bin/sh`ncase `"`$*`" in *--version*) echo '4.7.2.stable.official.abc'; exit 0;; esac`nn=`$((`$(cat '$count') + 1)); echo `$n > '$count'`nif [ `$n = 1 ] || [ $($case.Every) = 1 ]; then echo `"ERROR: Cannot open file 'res://.godot/imported/font.fontdata'.`"; fi`nexit 0`n"
        chmod +x $stand
        $saved = $env:GODOT_BIN; $env:GODOT_BIN = $stand
        try { $json = & $pwshPath -NoProfile -NonInteractive -File (Join-Path $PSScriptRoot '../ci/godot/hyperdot.ps1') build -Json -Project $game 2>$null } finally { $env:GODOT_BIN = $saved }
        $result = ($json -join "`n") | ConvertFrom-Json
        $code = if ($result.PSObject.Properties['error']) { $result.error.code } else { '' }
        $repeated = $result.PSObject.Properties['importRepeated'] -and $result.importRepeated
        if ($result.ok -ne $case.Ok -or -not $repeated -or (-not $case.Ok -and $code -ne 'engine-errors')) {
            $failures += "$($case.Name): ok $($result.ok), importRepeated $repeated, error '$code'; expected ok $($case.Ok), a second import"
        }
    }

    # export: an empty export_path stops before anything runs; a Godot that has no export template for the preset gives
    # export-template-missing with the path it looked at, and engineErrors[] carries the line under "configuration errors:".
    $export = Join-Path $dir 'export-game'
    New-Item -ItemType Directory -Force $export | Out-Null
    Copy-Item -LiteralPath (Join-Path $game 'project.godot') -Destination $export
    $presetText = "[preset.0]`n`nname=`"Linux`"`nplatform=`"Linux`"`nrunnable=true`nexport_path=`"EXPORT_PATH`"`n`n[preset.0.options]`n`n"
    Set-Content -LiteralPath $stand -NoNewline -Value "#!/bin/sh`ncase `"`$*`" in *--version*) echo '4.7.2.stable.official.abc'; exit 0;; esac`ncase `"`$*`" in *--export-release*)`n echo 'ERROR: Cannot export project with preset `"Linux`" due to configuration errors:'`n echo 'No export template found at the expected path: /opt/templates/4.7.2.stable/linux_release.x86_64'`n exit 1;; esac`nexit 0`n"
    chmod +x $stand
    foreach ($case in @(@{ Path = ''; Code = 'export-no-path' }, @{ Path = 'build/game.x86_64'; Code = 'export-template-missing' })) {
        Set-Content -LiteralPath (Join-Path $export 'export_presets.cfg') -Value ($presetText -creplace 'EXPORT_PATH', $case.Path) -NoNewline
        $saved = $env:GODOT_BIN; $env:GODOT_BIN = $stand
        try { $json = & $pwshPath -NoProfile -NonInteractive -File (Join-Path $PSScriptRoot '../ci/godot/hyperdot.ps1') export -Json -Project $export 2>$null } finally { $env:GODOT_BIN = $saved }
        $result = ($json -join "`n") | ConvertFrom-Json
        $code = if ($result.PSObject.Properties['error']) { $result.error.code } else { '' }
        if ($code -ne $case.Code) { $failures += "export with path '$($case.Path)': error '$code', expected $($case.Code)" }
        if ($case.Code -eq 'export-template-missing') {
            if ($result.error.message -notmatch '/opt/templates/4\.7\.2\.stable/linux_release\.x86_64') { $failures += "export-template-missing should name the path: $($result.error.message)" }
            if (@($result.engineErrors | Where-Object { $_.message -match 'configuration errors: No export template found' }).Count -ne 1) { $failures += 'engineErrors should hold the reason under "configuration errors:"' }
        }
    }
}

Remove-Item -LiteralPath $dir -Recurse -Force
if ($failures) {
    foreach ($failure in $failures) { Write-Host "FAIL $failure" }
    exit 1
}
Write-Host 'Invoke-GodotRetried repeats a crashed import or export up to twice, deletes what the crash left, and never repeats a failure or a hang'
exit 0
