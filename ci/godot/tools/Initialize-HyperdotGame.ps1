#!/usr/bin/env pwsh
#Requires -Version 7.6
<#
.SYNOPSIS
    Sets up Hyperdot for a Godot game and makes a second working copy for a parallel Claude chat.

.DESCRIPTION
    Does, in order: checks the game's Git repository; checks git, .NET 8 (C# games) and PowerShell; finds the Hyperdot kit;
    finds a Godot of the game's version; runs `doctor`; adds the kit to the game on a branch (`init -Plugin`), runs the
    tests, commits and merges the branch; makes a Git worktree on a new branch for the chat.

    Nothing is downloaded unless -AllowDownload is given, and every download is preceded by a search for a local copy:
      git, dotnet      PATH, then the usual install folders; with -AllowDownload and Windows, `winget install`.
      the kit          -Kit, $env:HYPERDOT_KIT, -KitInstallDir, C:\Tools\hyperdot, ~\hyperdot; with -AllowDownload, `git clone`.
                       An existing copy is not updated unless -UpdateKit.
      Godot            $env:GODOT_BIN, the kit's own folder (~\.hyperdot), then Godot executables in -GodotSearchPath and the
                       usual folders (Downloads, Desktop, C:\Godot, C:\Tools, Program Files, scoop, Steam, PATH). A candidate
                       is kept only when `--version` says it is the game's version (and the .NET build for a C# game).
                       One match is used. Several are listed with their paths and you choose (or pass -GodotChoice <n> or
                       -Godot <path>). None, and with -AllowDownload, the kit downloads the version on its first run.
    A Godot found outside the kit's folder is recorded for the chat in .claude/settings.local.json (`env.GODOT_BIN`) of the
    game and of the worktree, and that file is excluded from Git in .git/info/exclude. GODOT_BIN is never set for the
    whole machine: the kit trusts it without checking the version, so a global one would be wrong for another game.

.EXAMPLE
    pwsh <kit>\ci\godot\tools\Initialize-HyperdotGame.ps1 -Game C:\Games\MyGame -DryRun
.EXAMPLE
    pwsh <kit>\ci\godot\tools\Initialize-HyperdotGame.ps1 -Game C:\Games\MyGame -GodotSearchPath D:\Engines
#>
[CmdletBinding()]
param(
    # The game's folder: the root of its Git repository, with project.godot in it.
    [Parameter(Mandatory)][string]$Game,
    # An existing clone of the kit (the folder that holds ci/godot/hyperdot.ps1).
    [string]$Kit,
    # Where to look for the kit, and where to clone it when -AllowDownload is given. Default C:\Tools\hyperdot, or ~/hyperdot.
    [string]$KitInstallDir,
    # Branch for adding the kit to the game, and branch for the chat's worktree. Default feature/<random>.
    [string]$SetupBranch = "feature/$(-join ((48..57) + (97..122) | Get-Random -Count 6 | ForEach-Object { [char]$_ }))",
    [string]$WorktreeBranch = "feature/$(-join ((48..57) + (97..122) | Get-Random -Count 6 | ForEach-Object { [char]$_ }))",
    # The chat's folder. Default: the game's folder with -chat2 added.
    [string]$Worktree,
    # More folders to search for a Godot executable (several: separate them with commas).
    [string[]]$GodotSearchPath = @(),
    # Search only -GodotSearchPath (and GODOT_BIN and the kit's folder): not Downloads, Program Files, PATH and the other usual folders.
    [switch]$NoDefaultSearch,
    # Use exactly this Godot executable (it must be the game's version), and skip the search.
    [string]$Godot,
    # When several local copies fit, take the one with this number from the list instead of asking.
    [int]$GodotChoice = 0,
    # Allow downloads and installs (winget, git clone of the kit, the kit's own Godot download).
    [switch]$AllowDownload,
    # `git pull --ff-only` in an existing kit clone.
    [switch]$UpdateKit,
    # Do not write .claude/settings.local.json with GODOT_BIN for a Godot found outside the kit's folder.
    [switch]$NoLocalSettings,
    [switch]$SkipWorktree,
    # Print what would change and change nothing.
    [switch]$DryRun
)
Set-StrictMode -Version 3.0
$ErrorActionPreference = 'Stop'
$pwshPath = (Get-Process -Id $PID).Path
# `pwsh -File` hands -GodotSearchPath over as one string: "a,b" is two folders.
$GodotSearchPath = @($GodotSearchPath | ForEach-Object { $_ -split ',' } | ForEach-Object { $_.Trim() } | Where-Object { $_ })
# A stop or any error ends the script with one red line and exit code 1, not a stack trace.
trap { Write-Host ""; Write-Host "STOPPED: $($_.Exception.Message)" -ForegroundColor Red; exit 1 }

# --- Output and process helpers -------------------------------------------------------------------------------------
function Write-Step([string]$Text) { Write-Host ''; Write-Host "== $Text" -ForegroundColor Cyan }
function Write-Info([string]$Text) { Write-Host "   $Text" }
function Write-Warn([string]$Text) { Write-Host "   ! $Text" -ForegroundColor Yellow }
function Stop-Setup([string]$Text) { throw $Text }

# Runs a program with an argument array. A mutating call is only printed under -DryRun. Output is returned, and printed
# with -Show; stdout and stderr are merged unless -StdoutOnly.
function Invoke-Native([string]$File, [string[]]$Arguments, [switch]$Mutating, [switch]$Show, [switch]$StdoutOnly) {
    if ($Mutating -and $DryRun) {
        Write-Host "   [dry-run] $File $($Arguments -join ' ')" -ForegroundColor DarkYellow
        return [pscustomobject]@{ ExitCode = 0; Output = @() }
    }
    $lines = if ($StdoutOnly) { @(& $File @Arguments 2>$null | ForEach-Object { "$_" }) } else { @(& $File @Arguments 2>&1 | ForEach-Object { "$_" }) }
    $code = $LASTEXITCODE
    if ($Show) { foreach ($line in $lines) { Write-Host "     $line" } }
    return [pscustomobject]@{ ExitCode = $code; Output = $lines }
}
function Invoke-Git([string]$Folder, [string[]]$Arguments, [switch]$Mutating, [switch]$Show) {
    return Invoke-Native 'git' (@('-C', $Folder) + $Arguments) -Mutating:$Mutating -Show:$Show
}
function Invoke-Kit([string[]]$Arguments, [switch]$Show, [switch]$StdoutOnly) {
    return Invoke-Native $pwshPath (@('-NoProfile', '-NonInteractive', '-File', $script:KitScript) + $Arguments) -Show:$Show -StdoutOnly:$StdoutOnly
}

# A version as major.minor.patch ('4.6' is '4.6.0'), or '' when it is not one.
function ConvertTo-VersionKey([string]$Text) {
    $m = [regex]::Match($Text, '^(\d+)\.(\d+)(?:\.(\d+))?')
    if (-not $m.Success) { return '' }
    $patch = if ($m.Groups[3].Success) { $m.Groups[3].Value } else { '0' }
    return "$($m.Groups[1].Value).$($m.Groups[2].Value).$patch"
}

# --- 1. The game ----------------------------------------------------------------------------------------------------
Write-Step '1. The game'
if (-not (Test-Path -LiteralPath $Game -PathType Container)) { Stop-Setup "The game folder $Game does not exist." }
$Game = (Resolve-Path -LiteralPath $Game).Path.TrimEnd('\', '/')
if (-not (Test-Path -LiteralPath (Join-Path $Game 'project.godot'))) { Stop-Setup "$Game has no project.godot: pass the folder that holds it." }
if (-not (Get-Command git -ErrorAction SilentlyContinue)) {
    foreach ($candidate in $(if ($IsWindows) { 'C:\Program Files\Git\cmd', 'C:\Program Files (x86)\Git\cmd' } else { '/usr/local/bin', '/usr/bin' })) {
        if (Test-Path -LiteralPath (Join-Path $candidate $(if ($IsWindows) { 'git.exe' } else { 'git' }))) { $env:PATH = "$candidate$([IO.Path]::PathSeparator)$env:PATH"; break }
    }
}
if (-not (Get-Command git -ErrorAction SilentlyContinue)) {
    if (-not $IsWindows -or -not $AllowDownload) { Stop-Setup 'git was not found. Install it with: winget install --id Git.Git -e   (or rerun with -AllowDownload), then open a new PowerShell.' }
    Invoke-Native 'winget' @('install', '--id', 'Git.Git', '-e', '--accept-package-agreements', '--accept-source-agreements') -Mutating -Show | Out-Null
    Stop-Setup 'git was installed. Open a new PowerShell window (so PATH is refreshed) and run this script again.'
}
$top = (Invoke-Git $Game @('rev-parse', '--show-toplevel')).Output | Select-Object -First 1
if (-not $top -or $LASTEXITCODE) { Stop-Setup "$Game is not a Git repository. Run 'git init' there first and commit your game." }
$topFull = [IO.Path]::GetFullPath($top).TrimEnd('\', '/')
$same = if ($IsWindows) { $topFull -ieq $Game } else { $topFull -ceq $Game }
if (-not $same) { Stop-Setup "$Game is inside the repository at $topFull. This script needs the game folder to be the repository root." }
$dirty = @((Invoke-Git $Game @('status', '--porcelain')).Output)
if ($dirty.Count -gt 0) { Stop-Setup "The game has uncommitted changes (first lines: $(($dirty | Select-Object -First 3) -join ' | ')). Commit or stash them, then run again." }
foreach ($key in 'user.name', 'user.email') {
    if (-not (Invoke-Git $Game @('config', $key)).Output) { Stop-Setup "git $key is not set. Run: git config --global $key '<value>'" }
}
$mainBranch = ((Invoke-Git $Game @('branch', '--show-current')).Output | Select-Object -First 1)
if (-not $mainBranch) { Stop-Setup 'The game is on a detached HEAD. Switch to your main branch first.' }
$isCSharp = @(Get-ChildItem -LiteralPath $Game -File -Filter '*.csproj').Count -gt 0
Write-Info "Game: $Game (branch $mainBranch, $(if ($isCSharp) { 'C#' } else { 'GDScript' }), clean)"

# --- 2. Tools -------------------------------------------------------------------------------------------------------
Write-Step '2. Tools: PowerShell, .NET'
Write-Info "PowerShell $($PSVersionTable.PSVersion): ok"
if ($isCSharp) {
    function Test-Dotnet8 { return [bool](Get-Command dotnet -ErrorAction SilentlyContinue) -and [bool](& dotnet --list-sdks 2>$null | Where-Object { $_ -match '^8\.' }) }
    if (-not (Test-Dotnet8)) {
        foreach ($candidate in @("$env:DOTNET_ROOT") + $(if ($IsWindows) { @('C:\Program Files\dotnet') } else { @('/usr/lib/dotnet', '/usr/share/dotnet', "$HOME/.dotnet") })) {
            if ($candidate -and (Test-Path -LiteralPath (Join-Path $candidate $(if ($IsWindows) { 'dotnet.exe' } else { 'dotnet' })))) {
                $env:PATH = "$candidate$([IO.Path]::PathSeparator)$env:PATH"
                if (Test-Dotnet8) { Write-Info "Found a local .NET at $candidate (added to PATH for this run)"; break }
            }
        }
    }
    if (-not (Test-Dotnet8)) {
        if (-not $IsWindows -or -not $AllowDownload) { Stop-Setup 'The .NET 8 SDK was not found. Install it with: winget install --id Microsoft.DotNet.SDK.8 -e   (or rerun with -AllowDownload), then open a new PowerShell.' }
        Invoke-Native 'winget' @('install', '--id', 'Microsoft.DotNet.SDK.8', '-e', '--accept-package-agreements', '--accept-source-agreements') -Mutating -Show | Out-Null
        Stop-Setup 'The .NET 8 SDK was installed. Open a new PowerShell window and run this script again.'
    }
    Write-Info ".NET: $((& dotnet --list-sdks 2>$null | Where-Object { $_ -match '^8\.' } | Select-Object -First 1))"
} else {
    Write-Info '.NET: not needed for a GDScript game'
}

# --- 3. The kit -----------------------------------------------------------------------------------------------------
Write-Step '3. The kit'
if (-not $KitInstallDir) { $KitInstallDir = if ($IsWindows) { 'C:\Tools\hyperdot' } else { Join-Path $HOME 'hyperdot' } }
$kitCandidates = @($Kit, $env:HYPERDOT_KIT, (Join-Path $PSScriptRoot '../../..'), $KitInstallDir, $(if ($IsWindows) { 'C:\Tools\hyperdot' }), (Join-Path $HOME 'hyperdot')) | Where-Object { $_ }
$kitDir = $null
foreach ($candidate in $kitCandidates) {
    if (Test-Path -LiteralPath (Join-Path $candidate 'ci/godot/hyperdot.ps1')) { $kitDir = (Resolve-Path -LiteralPath $candidate).Path; break }
}
if ($kitDir) {
    Write-Info "Using the local kit at $kitDir (nothing downloaded)"
    if ($UpdateKit) { Invoke-Git $kitDir @('pull', '--ff-only') -Mutating -Show | Out-Null }
} elseif ($AllowDownload) {
    Write-Info "No local kit found (looked in: $(($kitCandidates | Select-Object -Unique) -join ', ')); cloning to $KitInstallDir"
    Invoke-Native 'git' @('clone', 'https://github.com/nick-vas/hyperdot', $KitInstallDir) -Mutating -Show | Out-Null
    $kitDir = $KitInstallDir
} else {
    Stop-Setup "No local kit found (looked in: $(($kitCandidates | Select-Object -Unique) -join ', ')). Clone it with: git clone https://github.com/nick-vas/hyperdot $KitInstallDir   or rerun with -AllowDownload."
}
$script:KitScript = Join-Path $kitDir 'ci/godot/hyperdot.ps1'
$kitReady = Test-Path -LiteralPath $script:KitScript

# --- 4. Godot: a local copy of the game's version -------------------------------------------------------------------
Write-Step "4. Godot: a local copy first"
$wantVersion = ''
if ($kitReady) {
    $detected = (Invoke-Kit @('detect', '-Json', '-Project', $Game) -StdoutOnly).Output -join "`n"
    try { $wantVersion = ConvertTo-VersionKey ([string](($detected | ConvertFrom-Json).godotVersion)) } catch { $wantVersion = '' }
}
if (-not $wantVersion) {
    foreach ($csproj in Get-ChildItem -LiteralPath $Game -File -Filter '*.csproj') {
        $m = [regex]::Match((Get-Content -LiteralPath $csproj.FullName -Raw), 'Godot\.NET\.Sdk/(\d+\.\d+(?:\.\d+)?)')
        if ($m.Success) { $wantVersion = ConvertTo-VersionKey $m.Groups[1].Value; break }
    }
}
# The kit decides the version itself: from Godot.NET.Sdk in a .csproj, else its own default; project.godot's feature tag is not used.
if (-not $wantVersion) { Stop-Setup 'Could not tell which Godot version the kit will use for this game (`detect` gave none).' }
$flavor = if ($isCSharp) { 'mono' } else { 'standard' }
Write-Info "The game needs Godot $wantVersion ($flavor build, stable)"

# `godot --version` prints e.g. 4.6.1.stable.mono.official.abcdef1; '' when it cannot be run.
function Get-GodotVersionText([string]$Path) {
    $info = [Diagnostics.ProcessStartInfo]::new($Path)
    $info.ArgumentList.Add('--version')
    $info.RedirectStandardOutput = $true
    $info.RedirectStandardError = $true
    $info.UseShellExecute = $false
    $info.CreateNoWindow = $true
    try { $process = [Diagnostics.Process]::Start($info) } catch { return '' }
    if (-not $process.WaitForExit(20000)) { try { $process.Kill() } catch { Write-Verbose "could not stop $Path" }; return '' }
    return $process.StandardOutput.ReadToEnd().Trim()
}
# The executable to use for a found file: on Windows the _console build (it writes to stdout, which the kit's checks need).
function Resolve-GodotExecutable([System.IO.FileInfo]$File) {
    if (-not $IsWindows) { return $File.FullName }
    if ($File.Name -match '_console\.exe$') { return $File.FullName }
    $console = Join-Path $File.DirectoryName ($File.Name -replace '\.exe$', '_console.exe')
    if (Test-Path -LiteralPath $console) { return $console }
    return $null
}
function Test-GodotFileName([System.IO.FileInfo]$File) {
    if ($File.Name -match 'export_template|crash') { return $false }
    if ($IsWindows) { return $File.Name -match '^Godot.*\.exe$' }
    return $File.Name -match '^Godot(_v|\.|$)' -and $File.Extension -in '', '.x86_64', '.arm64'
}
# Matches `--version` against the game's version and build: C# needs the .NET (mono) build.
function Test-GodotMatch([string]$VersionText) {
    $m = [regex]::Match($VersionText, '^(\d+\.\d+(?:\.\d+)?)\.(?<rel>[a-z]+\d*)(?<mono>\.mono)?')
    if (-not $m.Success) { return "cannot read its version ('$VersionText')" }
    if ((ConvertTo-VersionKey $m.Groups[1].Value) -ne $wantVersion) { return "is Godot $($m.Groups[1].Value), the game needs $wantVersion" }
    if ($m.Groups['rel'].Value -ne 'stable') { return "is a $($m.Groups['rel'].Value) build, not stable" }
    if ($isCSharp -and -not $m.Groups['mono'].Success) { return 'is the standard build; a C# game needs the .NET (mono) build' }
    return ''
}

$originalGodotBin = $env:GODOT_BIN
$rejected = [System.Collections.Generic.List[string]]::new()
$found = [System.Collections.Generic.List[pscustomobject]]::new()      # every local copy that fits the game
function Add-GodotCandidate([string]$Path, [string]$Source) {
    $full = [IO.Path]::GetFullPath($Path)
    foreach ($known in $found) {
        $same = if ($IsWindows) { $known.Path -ieq $full } else { $known.Path -ceq $full }
        if ($same) { return }
    }
    $text = Get-GodotVersionText $full
    $why = Test-GodotMatch $text
    if ($why) { $rejected.Add("${full}: $why"); return }
    $found.Add([pscustomobject]@{ Path = $full; Source = $Source; Version = $text })
}

# An explicit choice: -Godot <path>.
if ($Godot) {
    if (-not (Test-Path -LiteralPath $Godot -PathType Leaf)) { Stop-Setup "-Godot $Godot does not exist." }
    Add-GodotCandidate $Godot 'given with -Godot'
    if ($found.Count -eq 0) { Stop-Setup "-Godot $Godot cannot be used: $($rejected -join '; ')" }
} else {
    # a. GODOT_BIN already set
    if ($env:GODOT_BIN -and (Test-Path -LiteralPath $env:GODOT_BIN)) { Add-GodotCandidate $env:GODOT_BIN 'GODOT_BIN, already set' }
    # b. the kit's own folder
    $toolsDir = if ($env:GODOT_TOOLS_DIR) { $env:GODOT_TOOLS_DIR } else { Join-Path $HOME '.hyperdot' }
    if (Test-Path -LiteralPath $toolsDir -PathType Container) {
        foreach ($dir in Get-ChildItem -LiteralPath $toolsDir -Directory) {
            $m = [regex]::Match($dir.Name, '^(?<v>\d+\.\d+(?:\.\d+)?)-stable-(?<fl>mono|standard)$')
            if (-not $m.Success -or (ConvertTo-VersionKey $m.Groups['v'].Value) -ne $wantVersion -or $m.Groups['fl'].Value -ne $flavor) { continue }
            $exe = Get-ChildItem -LiteralPath $dir.FullName -Recurse -Depth 2 -File | Where-Object { (Test-GodotFileName $_) -and $_.Extension -ne '.zip' -and $_.Extension -ne '.lock' } |
                ForEach-Object { Resolve-GodotExecutable $_ } | Where-Object { $_ } | Select-Object -First 1
            if ($exe) { Add-GodotCandidate $exe "the kit's own folder ($toolsDir)" }
        }
    }
    # c. Godot executables elsewhere on this machine
    $folders = [System.Collections.Generic.List[string]]::new()
    foreach ($f in $GodotSearchPath) { $folders.Add($f) }
    $defaults = if ($IsWindows) {
        @("$HOME\Downloads", "$HOME\Desktop", "$HOME\Documents", 'C:\Godot', 'C:\Tools', 'D:\Godot', $env:LOCALAPPDATA + '\Programs', $env:ProgramFiles, "$HOME\scoop\apps",
          'C:\Program Files (x86)\Steam\steamapps\common')
    } else { @("$HOME/Downloads", "$HOME/bin", '/usr/local/bin', '/opt', '/Applications') }
    if (-not $NoDefaultSearch) { foreach ($f in $defaults) { if ($f) { $folders.Add($f) } } }
    $files = [System.Collections.Generic.List[System.IO.FileInfo]]::new()
    foreach ($folder in $folders) {
        if (-not (Test-Path -LiteralPath $folder -PathType Container)) { continue }
        Write-Info "Searching $folder"
        # Search only: a folder that cannot be read is skipped, not an error.
        foreach ($file in Get-ChildItem -LiteralPath $folder -Recurse -Depth 3 -File -ErrorAction SilentlyContinue) { if (Test-GodotFileName $file) { $files.Add($file) } }
    }
    if (-not $NoDefaultSearch) {
        foreach ($cmd in Get-Command 'godot*' -CommandType Application -ErrorAction SilentlyContinue) { $files.Add([System.IO.FileInfo]::new($cmd.Source)) }
    }
    foreach ($file in $files) {
        $exe = Resolve-GodotExecutable $file
        if (-not $exe) { $rejected.Add("$($file.FullName): no _console.exe beside it (the kit's log checks need the console build)"); continue }
        Add-GodotCandidate $exe 'found on this machine'
    }
}
foreach ($line in $rejected) { Write-Info "skipped $line" }

$godotBin = $null
$needsLocalSetting = $false
if ($found.Count -gt 1) {
    Write-Host ''
    Write-Host "   Found $($found.Count) local copies of Godot $wantVersion ($flavor):" -ForegroundColor Yellow
    for ($n = 0; $n -lt $found.Count; $n++) {
        Write-Host ('   [{0}] {1}' -f ($n + 1), $found[$n].Path)
        Write-Host ('       {0}; {1}' -f $found[$n].Source, $found[$n].Version) -ForegroundColor DarkGray
    }
    $choice = 0
    if ($GodotChoice -ge 1) {
        if ($GodotChoice -gt $found.Count) { Stop-Setup "-GodotChoice ${GodotChoice}: there are only $($found.Count) copies." }
        $choice = $GodotChoice
    } elseif ([Environment]::UserInteractive -and -not [Console]::IsInputRedirected) {
        while ($choice -lt 1 -or $choice -gt $found.Count) {
            $answer = Read-Host "   Which one should the kit use? Enter 1-$($found.Count)"
            if (-not [int]::TryParse($answer, [ref]$choice)) { $choice = 0 }
        }
    } else {
        Stop-Setup "More than one Godot $wantVersion was found and there is no keyboard to ask. Run again with -GodotChoice <number> or -Godot <path>."
    }
    $godotBin = $found[$choice - 1].Path
    Write-Info "Chosen: [$choice] $godotBin"
    $godotSource = $found[$choice - 1].Source
} elseif ($found.Count -eq 1) {
    $godotBin = $found[0].Path
    $godotSource = $found[0].Source
}
if ($godotBin) {
    Write-Info "Using a local Godot: $godotBin ($godotSource); nothing will be downloaded"
    # The kit finds its own folder's copy without help, unless GODOT_BIN points elsewhere.
    $isKitOwn = $godotSource -like "the kit's own folder*" -and -not $originalGodotBin
    $env:GODOT_BIN = $godotBin
    $needsLocalSetting = -not $isKitOwn -and -not $NoLocalSettings
} elseif ($AllowDownload) {
    Write-Warn "No local Godot $wantVersion ($flavor) found. The kit will download it on its first run (-AllowDownload)."
} else {
    Stop-Setup "No local Godot $wantVersion ($flavor build) was found, so nothing was changed. Point -GodotSearchPath at the folder that holds it, set GODOT_BIN, or rerun with -AllowDownload to let the kit download it."
}

# --- 5. doctor ------------------------------------------------------------------------------------------------------
Write-Step '5. doctor'
if ($kitReady) {
    $doctor = Invoke-Kit @('doctor', '-Project', $Game) -Show
    if ($doctor.ExitCode -ne 0) { Stop-Setup "doctor reported problems (exit $($doctor.ExitCode)); read the lines above, fix them, and run the script again. Nothing was changed in the game." }
    Write-Info 'doctor: no problems'
} else {
    Write-Host '   [dry-run] the kit is not on disk yet, so doctor would run here' -ForegroundColor DarkYellow
}

# --- 6. Add the kit to the game, on a branch ------------------------------------------------------------------------
Write-Step "6. Add the kit to the game (branch $SetupBranch)"
$initialised = (Test-Path -LiteralPath (Join-Path $Game 'docs/kit-notes.md')) -and (Test-Path -LiteralPath (Join-Path $Game '.claude/settings.json'))
if ($initialised) {
    Write-Info 'The game already has the kit (docs/kit-notes.md and .claude/settings.json): skipping init and the setup commit.'
    if ($kitReady) {
        $run = Invoke-Kit @('test', '-Json', '-Quiet', '-Project', $Game) -StdoutOnly
        $ok = try { [bool](($run.Output -join "`n") | ConvertFrom-Json).ok } catch { $false }
        if (-not $ok) { Stop-Setup 'The tests do not pass on the game as it is. Run: pwsh <kit>\ci\godot\hyperdot.ps1 test -Project <game>   to see why.' }
        Write-Info 'tests: ok'
    }
} else {
    Invoke-Git $Game @('switch', '-c', $SetupBranch) -Mutating | Out-Null
    if ($LASTEXITCODE -and -not $DryRun) { Stop-Setup "Could not create the branch $SetupBranch." }
    if ($kitReady -and -not $DryRun) {
        $init = Invoke-Kit @('init', '-Plugin', '-Project', $Game) -Show
        if ($init.ExitCode -ne 0) { Stop-Setup "init failed (exit $($init.ExitCode)). You are on the branch $SetupBranch; look at 'git status', or go back with: git switch $mainBranch; git branch -D $SetupBranch" }
        Write-Info 'Changes made by init:'
        Invoke-Git $Game @('status', '--short') -Show | Out-Null
        $run = Invoke-Kit @('test', '-Json', '-Quiet', '-Project', $Game) -StdoutOnly
        $ok = try { [bool](($run.Output -join "`n") | ConvertFrom-Json).ok } catch { $false }
        if (-not $ok) { Stop-Setup "The tests do not pass after init. You are on the branch $SetupBranch with the changes uncommitted. Run: pwsh $script:KitScript test -Project $Game   to see why." }
        Write-Info 'tests: ok'
    } else {
        Write-Host '   [dry-run] init -Plugin, then the tests, would run here' -ForegroundColor DarkYellow
    }
    Invoke-Git $Game @('add', '-A') -Mutating | Out-Null
    Invoke-Git $Game @('commit', '-m', 'Add Hyperdot') -Mutating -Show | Out-Null
    Invoke-Git $Game @('switch', $mainBranch) -Mutating | Out-Null
    Invoke-Git $Game @('merge', '--ff-only', $SetupBranch) -Mutating -Show | Out-Null
    Invoke-Git $Game @('branch', '-d', $SetupBranch) -Mutating | Out-Null
    if (-not $DryRun) { Write-Info "Merged into $mainBranch." }
}
if ($needsLocalSetting) { $localSettingFolders = @($Game) } else { $localSettingFolders = @() }

# --- 7. The worktree for the chat -----------------------------------------------------------------------------------
function Set-LocalGodotSetting([string]$Folder, [string]$Path) {
    $dir = Join-Path $Folder '.claude'
    $file = Join-Path $dir 'settings.local.json'
    if ($DryRun) { Write-Host "   [dry-run] write env.GODOT_BIN=$Path to $file and exclude it from Git" -ForegroundColor DarkYellow; return }
    $settings = @{}
    if (Test-Path -LiteralPath $file) {
        try { $settings = Get-Content -LiteralPath $file -Raw | ConvertFrom-Json -AsHashtable } catch { Stop-Setup "$file is not plain JSON; add \"env\": {\"GODOT_BIN\": \"$Path\"} to it by hand." }
        if ($null -eq $settings) { $settings = @{} }
    }
    if (-not $settings.ContainsKey('env')) { $settings['env'] = @{} }
    $settings['env']['GODOT_BIN'] = $Path
    New-Item -ItemType Directory -Force $dir | Out-Null
    $settings | ConvertTo-Json -Depth 10 | Set-Content -LiteralPath $file -Encoding utf8
    $exclude = (Invoke-Git $Folder @('rev-parse', '--git-path', 'info/exclude')).Output | Select-Object -First 1
    if (-not [IO.Path]::IsPathRooted($exclude)) { $exclude = Join-Path $Folder $exclude }
    New-Item -ItemType Directory -Force (Split-Path $exclude) | Out-Null
    $existing = if (Test-Path -LiteralPath $exclude) { @(Get-Content -LiteralPath $exclude) } else { @() }
    if ('.claude/settings.local.json' -notin $existing) { Add-Content -LiteralPath $exclude -Value '.claude/settings.local.json' }
    Write-Info "Wrote GODOT_BIN to $file (excluded from Git)"
}

$chatFolder = $null
if (-not $SkipWorktree) {
    Write-Step "7. A separate folder for the chat (branch $WorktreeBranch)"
    $chatFolder = if ($Worktree) { $Worktree } else { "$Game-chat2" }
    $registered = @((Invoke-Git $Game @('worktree', 'list', '--porcelain')).Output | Where-Object { $_ -like 'worktree *' } |
        ForEach-Object { [IO.Path]::GetFullPath($_.Substring(9)).TrimEnd('\', '/') })
    $chatFull = [IO.Path]::GetFullPath($chatFolder).TrimEnd('\', '/')
    $isRegistered = @($registered | Where-Object { if ($IsWindows) { $_ -ieq $chatFull } else { $_ -ceq $chatFull } }).Count -gt 0
    if ($isRegistered) {
        Write-Info "$chatFolder is already a worktree of this game: nothing to create."
    } elseif (Test-Path -LiteralPath $chatFolder) {
        Stop-Setup "$chatFolder already exists and is not a worktree of this game. Pass -Worktree with another folder, or remove it first."
    } else {
        Invoke-Git $Game @('worktree', 'add', $chatFolder, '-b', $WorktreeBranch) -Mutating -Show | Out-Null
        if ($LASTEXITCODE -and -not $DryRun) { Stop-Setup "git worktree add failed for $chatFolder." }
    }
    if ($needsLocalSetting) { $localSettingFolders += $chatFolder }
}
foreach ($folder in $localSettingFolders) { Set-LocalGodotSetting $folder $godotBin }

# --- Summary ---------------------------------------------------------------------------------------------------------
Write-Step "Done$(if ($DryRun) { ' (dry run: nothing was changed)' })"
Write-Info "Kit:      $script:KitScript"
Write-Info "Godot:    $(if ($godotBin) { $godotBin } else { 'the kit downloads it on its first run' })"
if ($chatFolder) {
    Write-Info "Chat dir: $chatFolder  (branch $WorktreeBranch)"
    Write-Host ''
    Write-Host '   In the Claude app: Code tab > new local session > choose the folder above, then send /game.' -ForegroundColor Green
    Write-Host "   When the chat is done:  git -C $Game merge $WorktreeBranch ; git -C $Game worktree remove $chatFolder ; git -C $Game branch -d $WorktreeBranch"
} else {
    Write-Host ''
    Write-Host "   In the Claude app: Code tab > new local session > choose $Game, then send /game." -ForegroundColor Green
}
