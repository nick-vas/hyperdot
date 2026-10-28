#!/usr/bin/env pwsh
# Self-test of ci/godot/tools/Initialize-HyperdotGame.ps1, the script that sets Hyperdot up for a game and makes a worktree
# for a parallel chat. A stub kit (it logs each call and answers detect, doctor, init and test) and fake Godot executables
# (shell scripts that print a version) stand in for the real ones, so this needs neither Godot, .NET nor the network.
# Checks: a dry run changes nothing; the setup commit, merge and worktree; the Godot is looked for locally and only a copy of
# the game's version is used; several copies are listed with their paths and chosen with -GodotChoice or -Godot; a Godot
# outside the kit's folder is recorded in .claude/settings.local.json (excluded from Git); every refusal leaves the game
# untouched; a second run does no harm. Linux and macOS only: the fakes are shell scripts (passes with a note on Windows).
Set-StrictMode -Version 3.0
$ErrorActionPreference = 'Stop'
$root = Split-Path $PSScriptRoot
$script = Join-Path $root 'ci/godot/tools/Initialize-HyperdotGame.ps1'
$failures = [System.Collections.Generic.List[string]]::new()
function Assert-True([bool]$Condition, [string]$Message) {
    if ($Condition) { Write-Host "ok   $Message" } else { $failures.Add($Message); Write-Host "FAIL $Message" -ForegroundColor Red }
}
if ($IsWindows) { Write-Host 'Initialize-HyperdotGame is checked with fake Godot shell scripts, which Windows cannot run: skipped here.'; exit 0 }

$temp = Join-Path ([IO.Path]::GetTempPath()) "init-game-$([guid]::NewGuid().ToString('n').Substring(0, 8))"
New-Item -ItemType Directory -Force $temp | Out-Null
$counter = 0

# --- Fixtures -------------------------------------------------------------------------------------------------------
# A stub kit: logs "<command> <arguments>" to $env:STUB_LOG and answers like the real one, as much as the script needs.
$stubKit = Join-Path $temp 'stub-kit'
New-Item -ItemType Directory -Force (Join-Path $stubKit 'ci/godot') | Out-Null
Set-Content -LiteralPath (Join-Path $stubKit 'ci/godot/hyperdot.ps1') -Value @'
param([Parameter(Position = 0)][string]$Command, [Parameter(ValueFromRemainingArguments)][string[]]$Rest)
Add-Content -LiteralPath $env:STUB_LOG -Value "$Command $($Rest -join ' ') | GODOT_BIN=$env:GODOT_BIN"
$project = $Rest[([array]::IndexOf($Rest, '-Project') + 1)]
switch ($Command) {
    'detect' { '{"ok":true,"csharp":false,"godotVersion":"' + $env:STUB_GODOT_VERSION + '"}' }
    'doctor' { Write-Host 'stub doctor: 0 problem(s)'; exit $(if ($env:STUB_DOCTOR_FAILS) { 1 } else { 0 }) }
    'init' {
        New-Item -ItemType Directory -Force (Join-Path $project 'docs'), (Join-Path $project '.claude') | Out-Null
        Set-Content -LiteralPath (Join-Path $project 'docs/kit-notes.md') -Value 'notes'
        Set-Content -LiteralPath (Join-Path $project '.claude/settings.json') -Value '{}'
        Write-Host 'stub init: added docs/kit-notes.md'
    }
    'test' { '{"ok":' + $(if ($env:STUB_TEST_FAILS) { 'false' } else { 'true' }) + '}'; exit 0 }
}
'@

# A fake Godot: prints a version like `godot --version`.
function New-FakeGodot([string]$Folder, [string]$Version, [string]$Flavor = 'standard') {
    New-Item -ItemType Directory -Force $Folder | Out-Null
    $path = Join-Path $Folder "Godot_v${Version}-stable_$($Flavor)_linux.x86_64"
    $text = "$Version.stable.$(if ($Flavor -eq 'mono') { 'mono.' })official.0123abc"
    Set-Content -LiteralPath $path -Value "#!/bin/sh`necho '$text'" -NoNewline
    & chmod '+x' $path
    return $path
}
# A game: a Git repository with a project.godot and one commit, on branch main.
function New-Game([string]$Name) {
    $dir = Join-Path $temp $Name
    New-Item -ItemType Directory -Force $dir | Out-Null
    Set-Content -LiteralPath (Join-Path $dir 'project.godot') -Value "config_version=5`n[application]`nconfig/name=`"$Name`""
    foreach ($arguments in @(@('init', '-q', '-b', 'main'), @('config', 'user.name', 'tester'), @('config', 'user.email', 'tester@example.com'), @('add', '-A'), @('commit', '-q', '-m', 'game'))) {
        & git -C $dir @arguments
        if ($LASTEXITCODE) { throw "git $($arguments -join ' ') failed" }
    }
    return $dir
}
function Get-GitText([string]$Folder, [string[]]$Arguments) { return (@(& git -C $Folder @Arguments 2>&1) -join "`n").Trim() }

# Runs the script with no keyboard (stdin closed), its own environment and a log; returns the exit code and all output.
function Invoke-Setup([string]$Game, [string[]]$Arguments, [string]$Version = '4.6.1', [hashtable]$Environment = @{}) {
    $script:counter++
    $info = [Diagnostics.ProcessStartInfo]::new((Get-Process -Id $PID).Path)
    foreach ($a in @('-NoProfile', '-NonInteractive', '-File', $script, '-Game', $Game, '-Kit', $stubKit, '-NoDefaultSearch') + $Arguments) { $info.ArgumentList.Add($a) }
    $info.RedirectStandardOutput = $true
    $info.RedirectStandardError = $true
    $info.RedirectStandardInput = $true
    $info.UseShellExecute = $false
    $log = Join-Path $temp "stub-$counter.log"
    $info.Environment['STUB_LOG'] = $log
    $info.Environment['STUB_GODOT_VERSION'] = $Version
    $info.Environment['GODOT_TOOLS_DIR'] = (Join-Path $temp 'empty-tools')
    [void]$info.Environment.Remove('GODOT_BIN')
    foreach ($key in $Environment.Keys) { $info.Environment[$key] = $Environment[$key] }
    $process = [Diagnostics.Process]::Start($info)
    $process.StandardInput.Close()
    $out = $process.StandardOutput.ReadToEndAsync()
    $err = $process.StandardError.ReadToEndAsync()
    if (-not $process.WaitForExit(240000)) { $process.Kill(); throw 'Initialize-HyperdotGame.ps1 did not finish in 4 minutes' }
    $calls = if (Test-Path -LiteralPath $log) { @(Get-Content -LiteralPath $log) } else { @() }
    return [pscustomobject]@{ Code = $process.ExitCode; Text = "$($out.Result)`n$($err.Result)"; Calls = $calls }
}
function Test-Untouched([string]$Game) {
    $branches = Get-GitText $Game @('branch', '--format=%(refname:short)')
    return (-not (Get-GitText $Game @('status', '--porcelain'))) -and $branches -eq 'main' -and (Get-GitText $Game @('rev-list', '--count', 'HEAD')) -eq '1' -and
        (Get-GitText $Game @('worktree', 'list')).Split("`n").Count -eq 1
}
New-Item -ItemType Directory -Force (Join-Path $temp 'empty-tools') | Out-Null

try {
    # 1. A dry run changes nothing and never runs init or the tests.
    $engines = Join-Path $temp 'engines'
    $good = New-FakeGodot $engines '4.6.1'
    $game = New-Game 'dry'
    $r = Invoke-Setup $game @('-GodotSearchPath', $engines, '-DryRun')
    Assert-True ($r.Code -eq 0 -and $r.Text -match 'dry run') "a dry run finishes ($($r.Code))"
    Assert-True (Test-Untouched $game) 'a dry run leaves the game as it was: no branch, no commit, no worktree, no file'
    Assert-True (@($r.Calls | Where-Object { $_ -match '^(init|test) ' }).Count -eq 0 -and @($r.Calls | Where-Object { $_ -match '^doctor ' }).Count -eq 1) 'a dry run runs doctor but not init or the tests'

    # 2. A real run: one local Godot of the game's version.
    $game = New-Game 'one'
    $r = Invoke-Setup $game @('-GodotSearchPath', $engines)
    Assert-True ($r.Code -eq 0) "a real run finishes ($($r.Code)): $(($r.Text -split "`n" | Select-Object -Last 3) -join ' / ')"
    Assert-True ($r.Text -match [regex]::Escape($good) -and $r.Text -match 'nothing will be downloaded') 'it uses the local Godot it found and says nothing is downloaded'
    $order = @($r.Calls | ForEach-Object { ($_ -split ' ')[0] })
    Assert-True (($order -join ',') -eq 'detect,doctor,init,test') "the kit is called in order: detect, doctor, init, test (got $($order -join ','))"
    Assert-True (@($r.Calls | Where-Object { $_ -match 'doctor .*GODOT_BIN=' + [regex]::Escape($good) }).Count -eq 1) 'the kit runs with GODOT_BIN set to that Godot'
    Assert-True ((Get-GitText $game @('log', '--format=%s', '-1')) -eq 'Add Hyperdot' -and (Test-Path -LiteralPath (Join-Path $game 'docs/kit-notes.md'))) 'the setup is committed on the main branch'
    Assert-True ((Get-GitText $game @('branch', '--format=%(refname:short)')).Split("`n").Count -eq 2) 'the setup branch is gone; main and the chat branch remain'
    $chat = "$game-chat2"
    Assert-True ((Test-Path -LiteralPath $chat) -and (Get-GitText $game @('worktree', 'list')) -match 'chat2') 'a worktree for the chat exists beside the game'
    foreach ($folder in $game, $chat) {
        $settings = Join-Path $folder '.claude/settings.local.json'
        $value = if (Test-Path -LiteralPath $settings) { (Get-Content -LiteralPath $settings -Raw | ConvertFrom-Json).env.GODOT_BIN } else { '' }
        Assert-True ($value -eq $good) "GODOT_BIN is recorded for the chat in $(Split-Path -Leaf $folder)/.claude/settings.local.json"
        Assert-True (-not (Get-GitText $folder @('status', '--porcelain'))) "$(Split-Path -Leaf $folder) has nothing to commit (the file is excluded from Git)"
    }

    # 3. A second run: nothing is redone, nothing breaks.
    $commits = Get-GitText $game @('rev-list', '--count', 'HEAD')
    $r = Invoke-Setup $game @('-GodotSearchPath', $engines)
    Assert-True ($r.Code -eq 0 -and $r.Text -match 'skipping init' -and $r.Text -match 'already a worktree') "a second run skips init and the existing worktree ($($r.Code))"
    Assert-True ((Get-GitText $game @('rev-list', '--count', 'HEAD')) -eq $commits -and @($r.Calls | Where-Object { $_ -match '^init ' }).Count -eq 0) 'a second run makes no new commit and does not run init'

    # 4. Only a Godot of another version: nothing is changed, and the message says why.
    $game = New-Game 'wrong'
    $other = Join-Path $temp 'engines-47'
    New-FakeGodot $other '4.7.2' | Out-Null
    $r = Invoke-Setup $game @('-GodotSearchPath', $other)
    Assert-True ($r.Code -eq 1 -and $r.Text -match 'No local Godot 4\.6\.1' -and $r.Text -match 'is Godot 4\.7\.2, the game needs 4\.6\.1') 'a Godot of another version is skipped, and the refusal says which version it was'
    Assert-True (Test-Untouched $game -and @($r.Calls | Where-Object { $_ -match '^(init|test) ' }).Count -eq 0) 'the refusal leaves the game untouched and runs neither init nor the tests'

    # 5. GODOT_BIN set to the wrong version is not trusted.
    $game = New-Game 'envwrong'
    $r = Invoke-Setup $game @('-GodotSearchPath', $engines) -Environment @{ GODOT_BIN = (Join-Path $other 'Godot_v4.7.2-stable_standard_linux.x86_64') }
    Assert-True ($r.Code -eq 0 -and $r.Text -match [regex]::Escape($good) -and $r.Text -match 'skipped .*4\.7\.2') 'a GODOT_BIN of another version is skipped and the right copy is used'

    # 6. Several copies: listed with their paths, then chosen.
    $second = New-FakeGodot (Join-Path $temp 'engines-b') '4.6.1' 'mono'
    $game = New-Game 'several'
    $both = "$engines,$(Join-Path $temp 'engines-b')"
    $r = Invoke-Setup $game @('-GodotSearchPath', $both)
    Assert-True ($r.Code -eq 1 -and $r.Text -match 'Found 2 local copies' -and $r.Text -match '\[1\]' -and $r.Text -match '\[2\]' -and $r.Text.Contains($good) -and $r.Text.Contains($second)) 'two copies are listed, numbered, with their paths'
    Assert-True ($r.Text -match 'no keyboard to ask' -and $r.Text -match '-GodotChoice' -and (Test-Untouched $game)) 'with no keyboard it stops, names -GodotChoice and -Godot, and changes nothing'
    $r = Invoke-Setup $game @('-GodotSearchPath', $both, '-GodotChoice', '2', '-SkipWorktree')
    Assert-True ($r.Code -eq 0 -and $r.Text -match 'Chosen: \[2\]' -and (@($r.Calls | Where-Object { $_ -match 'doctor .*GODOT_BIN=' }).Count -eq 1)) "-GodotChoice picks a numbered copy ($($r.Code))"
    $usedByKit = ($r.Calls | Where-Object { $_ -match '^doctor ' }) -replace '^.*GODOT_BIN=', ''
    Assert-True ($usedByKit -eq $r.Text.Split("`n").Where({ $_ -match '^\s+\[2\] ' })[0].Trim().Substring(4)) 'the kit ran with the copy that was numbered 2'
    $game = New-Game 'badchoice'
    $r = Invoke-Setup $game @('-GodotSearchPath', $both, '-GodotChoice', '9')
    Assert-True ($r.Code -eq 1 -and $r.Text -match 'only 2 copies' -and (Test-Untouched $game)) 'a -GodotChoice beyond the list is refused and changes nothing'

    # 7. -Godot names one explicitly; it must still be the right version.
    $game = New-Game 'explicit'
    $r = Invoke-Setup $game @('-Godot', $second, '-SkipWorktree')
    Assert-True ($r.Code -eq 0 -and $r.Text -match 'given with -Godot') '-Godot uses exactly that executable'
    $game = New-Game 'explicitwrong'
    $r = Invoke-Setup $game @('-Godot', (Join-Path $other 'Godot_v4.7.2-stable_standard_linux.x86_64'))
    Assert-True ($r.Code -eq 1 -and $r.Text -match 'cannot be used' -and (Test-Untouched $game)) '-Godot with another version is refused and changes nothing'

    # 8. The kit's own folder is found without writing a local setting.
    $tools = Join-Path $temp 'kit-tools'
    New-FakeGodot (Join-Path $tools '4.6.1-stable-standard') '4.6.1' | Out-Null
    $game = New-Game 'kitown'
    $r = Invoke-Setup $game @('-SkipWorktree') -Environment @{ GODOT_TOOLS_DIR = $tools }
    Assert-True ($r.Code -eq 0 -and $r.Text -match "the kit's own folder") "a copy in the kit's own folder is found ($($r.Code))"
    Assert-True (-not (Test-Path -LiteralPath (Join-Path $game '.claude/settings.local.json'))) 'the kit finds its own copy itself, so no local setting is written'

    # 9. Refusals before anything changes.
    $game = New-Game 'dirty'
    Set-Content -LiteralPath (Join-Path $game 'new.txt') -Value 'x'
    $r = Invoke-Setup $game @('-GodotSearchPath', $engines)
    Assert-True ($r.Code -eq 1 -and $r.Text -match 'uncommitted changes' -and @($r.Calls).Count -eq 0) 'a game with uncommitted changes is refused before the kit is called'
    $notRepo = Join-Path $temp 'norepo'
    New-Item -ItemType Directory -Force $notRepo | Out-Null
    Set-Content -LiteralPath (Join-Path $notRepo 'project.godot') -Value 'x'
    $r = Invoke-Setup $notRepo @('-GodotSearchPath', $engines)
    Assert-True ($r.Code -eq 1 -and $r.Text -match 'not a Git repository') 'a folder that is not a Git repository is refused'
    $empty = Join-Path $temp 'noproject'
    New-Item -ItemType Directory -Force $empty | Out-Null
    $r = Invoke-Setup $empty @()
    Assert-True ($r.Code -eq 1 -and $r.Text -match 'no project\.godot') 'a folder without project.godot is refused'
    $game = New-Game 'nokit'
    # The script finds the kit it lives in, so this run uses a copy outside any kit and a home folder without ~/hyperdot.
    $lonely = Join-Path $temp 'lonely/script'
    New-Item -ItemType Directory -Force $lonely, (Join-Path $temp 'home') | Out-Null
    Copy-Item -LiteralPath $script -Destination $lonely
    $info = [Diagnostics.ProcessStartInfo]::new((Get-Process -Id $PID).Path)
    foreach ($a in @('-NoProfile', '-NonInteractive', '-File', (Join-Path $lonely 'Initialize-HyperdotGame.ps1'), '-Game', $game, '-Kit', (Join-Path $temp 'nowhere'), '-GodotSearchPath', $engines, '-NoDefaultSearch')) { $info.ArgumentList.Add($a) }
    $info.RedirectStandardOutput = $true; $info.RedirectStandardError = $true; $info.RedirectStandardInput = $true; $info.UseShellExecute = $false
    $info.Environment['HYPERDOT_KIT'] = (Join-Path $temp 'nowhere-either')
    $info.Environment['HOME'] = (Join-Path $temp 'home')
    $p = [Diagnostics.Process]::Start($info); $p.StandardInput.Close()
    $o = $p.StandardOutput.ReadToEndAsync(); $e = $p.StandardError.ReadToEndAsync(); [void]$p.WaitForExit(120000)
    Assert-True ($p.ExitCode -eq 1 -and "$($o.Result)$($e.Result)" -match 'No local kit found' -and "$($o.Result)$($e.Result)" -match 'git clone' -and (Test-Untouched $game)) 'with no local kit and no -AllowDownload it stops and names the clone command, downloading nothing'

    # 10. A failing doctor or test stops the setup without a commit on main.
    $game = New-Game 'doctorfails'
    $r = Invoke-Setup $game @('-GodotSearchPath', $engines) -Environment @{ STUB_DOCTOR_FAILS = '1' }
    Assert-True ($r.Code -eq 1 -and $r.Text -match 'doctor reported problems' -and (Test-Untouched $game)) 'a doctor with problems stops the script before the game is changed'
    $game = New-Game 'testfails'
    $r = Invoke-Setup $game @('-GodotSearchPath', $engines) -Environment @{ STUB_TEST_FAILS = '1' }
    Assert-True ($r.Code -eq 1 -and $r.Text -match 'tests do not pass after init' -and (Get-GitText $game @('branch', '--show-current')) -match '^feature/' -and (Get-GitText $game @('rev-list', '--count', 'main')) -eq '1') 'failing tests after init stop the script on the setup branch, with main untouched'
} finally {
    Remove-Item -LiteralPath $temp -Recurse -Force -ErrorAction SilentlyContinue
}

if ($failures.Count) { Write-Host "`n$($failures.Count) failed" -ForegroundColor Red; exit 1 }
Write-Host "`nAll passed"
exit 0
