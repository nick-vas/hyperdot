# Installs the .NET SDK (when missing), the Godot .NET editor and, on request, export templates.
# Windows for local runs; Linux for GitHub runners and Claude Code cloud sessions; macOS for macOS and iOS exports.

function Save-Download([string]$Url, [string]$Destination) {
    Write-CiLog "Downloading $Url"
    $ProgressPreference = 'SilentlyContinue'   # the progress bar slows Invoke-WebRequest down a lot
    for ($attempt = 1; ; $attempt++) {
        try {
            # One partial file per process: two runs fetching the same file never write into each other.
            Invoke-WebRequest -Uri $Url -OutFile "$Destination.$PID.part" -MaximumRedirection 10
            Move-Item -Force -LiteralPath "$Destination.$PID.part" -Destination $Destination
            return
        } catch {
            if ($attempt -ge 4) { throw }
            Start-Sleep -Seconds ([math]::Pow(2, $attempt))
        }
    }
}

# Godot and its templates exist only behind this download. When it gives up, the failure is the network's or the
# server's, not the project's: its own code tells an agent to retry rather than change the game.
function Save-RequiredDownload([string]$Url, [string]$Destination) {
    try { Save-Download $Url $Destination }
    catch { Stop-GodotCi "Could not download $Url after 4 attempts ($($_.Exception.Message.TrimEnd("."))). Retry later or check the network; the project is not at fault." 'download-failed' }
}

# Godot publishes a SHA512-SUMS.txt beside each release (godot-builds). A download is compared with it before it is unpacked:
# HTTPS alone would trust whatever the server, a mirror or a proxy in the way hands over. A release without the file, or a
# file the sums do not list, is logged and used (older releases); a mismatch is never used.
$script:PublishedChecksums = @{}
function Get-PublishedChecksums([string]$BaseUrl) {
    if ($script:PublishedChecksums.ContainsKey($BaseUrl)) { return $script:PublishedChecksums[$BaseUrl] }
    $url = "$BaseUrl/SHA512-SUMS.txt"
    $ProgressPreference = 'SilentlyContinue'
    $sums = $null
    for ($attempt = 1; ; $attempt++) {
        try {
            $response = Invoke-WebRequest -Uri $url -MaximumRedirection 10 -SkipHttpErrorCheck
            if ($response.StatusCode -eq 404) { break }
            if ($response.StatusCode -ne 200) { throw "HTTP $($response.StatusCode)" }
            $text = if ($response.Content -is [byte[]]) { [System.Text.Encoding]::UTF8.GetString($response.Content) } else { [string]$response.Content }
            $sums = @{}
            foreach ($line in $text -split "`r?`n") {
                if ($line -match '^(?<hash>[0-9a-fA-F]{128})\s+\*?(?<name>\S.*?)\s*$') { $sums[$Matches['name']] = $Matches['hash'].ToLowerInvariant() }
            }
            if ($sums.Count -eq 0) { throw 'it lists no SHA-512 sums' }
            break
        } catch {
            if ($attempt -ge 4) { Stop-GodotCi "Could not read $url after 4 attempts ($($_.Exception.Message.TrimEnd("."))), so the download cannot be checked. Retry later or check the network; the project is not at fault." 'download-failed' }
            Start-Sleep -Seconds ([math]::Pow(2, $attempt))
        }
    }
    $script:PublishedChecksums[$BaseUrl] = $sums
    return $sums
}

function Confirm-DownloadChecksum([string]$BaseUrl, [string]$File, [string]$Path) {
    $sums = Get-PublishedChecksums $BaseUrl
    if ($null -eq $sums) { Write-CiLog "No SHA512-SUMS.txt is published at ${BaseUrl}: $File was not checked"; return }
    if (-not $sums.ContainsKey($File)) { Write-CiLog "SHA512-SUMS.txt at ${BaseUrl} does not list ${File}: it was not checked"; return }
    $actual = (Get-FileHash -Algorithm SHA512 -LiteralPath $Path).Hash.ToLowerInvariant()
    if ($actual -ne $sums[$File]) {
        Remove-Item -Force -LiteralPath $Path
        Stop-GodotCi "$File does not match the SHA-512 Godot publishes for it ($BaseUrl/SHA512-SUMS.txt lists $($sums[$File]); the download is $actual). The file was deleted. Retry, and report it if it happens again: it was altered on the way or is damaged." 'checksum-mismatch'
    }
    Write-CiLog "$File matches the SHA-512 Godot publishes"
}

# Two runs installing the same Godot at once (parallel jobs on one machine, two agent sessions) would share the zip, and
# one could start a half-extracted editor. An exclusive lock on a file serialises them; the system releases it when a
# run dies, so a crash never leaves it held. The wait is bounded by HYPERDOT_TIMEOUT, like any program the kit runs.
function Use-InstallLock([string]$Name, [scriptblock]$Body) {
    $dir = Get-ToolsDir
    New-Item -ItemType Directory -Force $dir | Out-Null
    $path = Join-Path $dir "$Name.lock"
    $limit = Get-ProcessTimeout
    $watch = [Diagnostics.Stopwatch]::StartNew()
    $waiting = $false
    while ($true) {
        try {
            $lock = [IO.File]::Open($path, [IO.FileMode]::OpenOrCreate, [IO.FileAccess]::ReadWrite, [IO.FileShare]::None)
            break
        } catch [IO.IOException] {
            if ($limit -gt 0 -and $watch.Elapsed.TotalSeconds -ge $limit) {
                Stop-GodotCi "Another run has been installing $Name for $([int]$watch.Elapsed.TotalSeconds) s ($path is locked). Wait for it to finish, or stop it, and retry." 'install-busy'
            }
            if (-not $waiting) { Write-CiLog "Waiting for another run installing $Name"; $waiting = $true }
            Start-Sleep -Milliseconds 500
        }
    }
    try { & $Body } finally { $lock.Dispose() }
}
function Expand-Zip([string]$Archive, [string]$Destination) {
    # ZipFile instead of Expand-Archive: it accepts any extension (.tpz) and is much faster on large files.
    Add-Type -AssemblyName System.IO.Compression.FileSystem
    New-Item -ItemType Directory -Force $Destination | Out-Null
    [System.IO.Compression.ZipFile]::ExtractToDirectory($Archive, $Destination, $true)
}

function Test-DotnetSdk([string]$Channel) {
    if (-not (Get-Command dotnet -ErrorAction SilentlyContinue)) { return $false }
    $major = $Channel.Split('.')[0]
    return [bool](& dotnet --list-sdks 2>$null | Where-Object { $_ -match "^$major\." })
}

function Install-DotnetSdk([string]$Channel) {
    if (Test-DotnetSdk $Channel) { return }
    if ($IsWindows) {
        Stop-GodotCi ".NET $Channel SDK not found. Install it with: winget install Microsoft.DotNet.SDK.$($Channel.Split('.')[0])"
    }
    $root = Join-Path (Get-ToolsDir) 'dotnet'
    $installed = $false
    try {
        $script = Join-Path (Get-ToolsDir) 'dotnet-install.sh'
        Save-Download 'https://dot.net/v1/dotnet-install.sh' $script
        # Invoke-Logged, not Invoke-Checked: a failure here must reach the apt fallback, not end the run.
        $installed = (Invoke-Logged bash @($script, '--channel', $Channel, '--install-dir', $root, '--no-path')) -eq 0
    } catch {
        Write-CiLog "dotnet-install.sh failed: $($_.Exception.Message)"
    }
    if ($installed) {
        $env:DOTNET_ROOT = $root
        $env:PATH = "$root$([IO.Path]::PathSeparator)$env:PATH"
        return
    }
    if ($IsMacOS) { Stop-GodotCi ".NET $Channel SDK not found and dotnet-install.sh failed. Install it with: brew install --cask dotnet-sdk" }
    # Sandboxed sessions may block Microsoft's CDN but allow the distro mirror.
    Write-CiLog "Microsoft's .NET download failed; installing dotnet-sdk-$Channel with apt"
    # Spelled out rather than indexing an array: PowerShell unrolls a one-item array to a plain string.
    $useSudo = (& id -u) -ne '0'
    foreach ($arguments in @(@('update', '-qq'), @('install', '-y', '-qq', "dotnet-sdk-$Channel"))) {
        if ($useSudo) { Invoke-Checked 'sudo' (@('apt-get') + $arguments) } else { Invoke-Checked 'apt-get' $arguments }
    }
}

# This machine as Get-GodotPaths names it: windows, linux or macos ('' for anything else), and x86_64 or arm64.
function Get-HostOs {
    if ($IsWindows) { return 'windows' }
    if ($IsLinux) { return 'linux' }
    if ($IsMacOS) { return 'macos' }
    return ''
}
function Get-HostArch {
    if ([System.Runtime.InteropServices.RuntimeInformation]::OSArchitecture -eq 'Arm64') { return 'arm64' }
    return 'x86_64'
}

# Download names and install paths. C# projects need the .NET ("mono") build; GDScript projects get the
# standard build, which needs no .NET SDK and is smaller. -Os and -Arch default to this machine's (tests pass others).
function Get-GodotPaths([string]$Version, [string]$Release, [bool]$Mono = $true, [string]$Os = (Get-HostOs), [string]$Arch = (Get-HostArch)) {
    $tag = "$Version-$Release"
    $flavor = if ($Mono) { 'mono' } else { 'standard' }
    $toolsDir = Join-Path (Get-ToolsDir) "$tag-$flavor"
    if ($Os -eq 'windows') {
        # The _console build writes to stdout, which logs and log checks need.
        if ($Mono) {
            $package = "Godot_v${tag}_mono_win64"
            $bin = Join-Path $toolsDir "$package/Godot_v${tag}_mono_win64_console.exe"
        } else {
            $package = "Godot_v${tag}_win64.exe"
            $bin = Join-Path $toolsDir "Godot_v${tag}_win64_console.exe"
        }
        $appData = if ($env:APPDATA) { $env:APPDATA } else { Join-Path $HOME 'AppData/Roaming' }
        $templatesRoot = Join-Path $appData 'Godot/export_templates'
    } elseif ($Os -eq 'linux') {
        if ($Mono) {
            $package = "Godot_v${tag}_mono_linux_$Arch"
            $bin = Join-Path $toolsDir "$package/Godot_v${tag}_mono_linux.$Arch"
        } else {
            $package = "Godot_v${tag}_linux.$Arch"
            $bin = Join-Path $toolsDir $package
        }
        $dataHome = if ($env:XDG_DATA_HOME) { $env:XDG_DATA_HOME } else { Join-Path $HOME '.local/share' }
        $templatesRoot = Join-Path $dataHome 'godot/export_templates'
    } elseif ($Os -eq 'macos') {
        # One universal build for Intel and Apple Silicon; the zip holds the app bundle (Godot_mono.app for .NET).
        if ($Mono) {
            $package = "Godot_v${tag}_mono_macos.universal"
            $bin = Join-Path $toolsDir 'Godot_mono.app/Contents/MacOS/Godot'
        } else {
            $package = "Godot_v${tag}_macos.universal"
            $bin = Join-Path $toolsDir 'Godot.app/Contents/MacOS/Godot'
        }
        $templatesRoot = Join-Path $HOME 'Library/Application Support/Godot/export_templates'
    } else {
        Stop-GodotCi 'Only Windows, Linux and macOS are supported'
    }
    $monoSuffix = if ($Mono) { '_mono' } else { '' }
    [pscustomobject]@{
        Tag           = $tag
        ToolsDir      = $toolsDir
        Package       = $package
        Bin           = $bin
        TemplatesDir  = Join-Path $templatesRoot ("$Version.$Release" + $(if ($Mono) { '.mono' } else { '' }))
        TemplatesFile = "Godot_v$tag${monoSuffix}_export_templates.tpz"
        BaseUrl       = "https://github.com/godotengine/godot-builds/releases/download/$tag"
    }
}

# The template files Godot reads for a preset, in the templates folder (Godot 4's names), for the platforms whose names are
# certain: Windows Desktop and Linux. Others: none, and the export finds out.
function Get-ExportTemplateFiles($Preset) {
    $arch = 'x86_64'
    if ($Preset.Options -and $Preset.Options.ContainsKey('binary_format/architecture') -and "$($Preset.Options['binary_format/architecture'])") { $arch = "$($Preset.Options['binary_format/architecture'])" }
    switch -Regex ($Preset.Platform) {
        '^Windows Desktop$' { return @("windows_release_$arch.exe", "windows_debug_$arch.exe") }
        '^Linux' { return @("linux_release.$arch", "linux_debug.$arch") }
        default { return @() }
    }
}

# Full paths of the template files a preset needs that the templates folder lacks (empty when all are there).
function Get-MissingExportTemplates($Preset, [string]$TemplatesDir) {
    @(foreach ($name in Get-ExportTemplateFiles $Preset) { $path = Join-Path $TemplatesDir $name; if (-not (Test-Path -LiteralPath $path)) { $path } })
}

function Install-GodotTools {
    param([string]$Version, [string]$Release = 'stable', [switch]$Templates, [bool]$Mono = $true, [string]$DotnetChannel = '8.0')

    if ($Mono) { Install-DotnetSdk $DotnetChannel }
    $paths = Get-GodotPaths $Version $Release $Mono

    Use-InstallLock (Split-Path -Leaf $paths.ToolsDir) {
        if (Test-Path -LiteralPath $paths.Bin) {
            Write-CiLog "Godot $($paths.Tag) already installed"
        } else {
            $zip = Join-Path (Get-ToolsDir) "$($paths.Package).zip"
            New-Item -ItemType Directory -Force (Get-ToolsDir) | Out-Null
            Save-RequiredDownload "$($paths.BaseUrl)/$($paths.Package).zip" $zip
            Confirm-DownloadChecksum $paths.BaseUrl "$($paths.Package).zip" $zip
            # Unpacked beside the final folder and renamed into place, so a run killed halfway never leaves an editor
            # that looks installed. ditto keeps what an app bundle needs (symbolic links, permissions, its code
            # signature) and ZipFile does not.
            $partial = "$($paths.ToolsDir).$PID.part"
            if ($IsMacOS) {
                New-Item -ItemType Directory -Force $partial | Out-Null
                Invoke-Checked ditto @('-x', '-k', $zip, $partial)
            } else {
                Expand-Zip $zip $partial
            }
            Remove-Item -Force -LiteralPath $zip
            if (Test-Path -LiteralPath $paths.ToolsDir) { Remove-Item -Recurse -Force -LiteralPath $paths.ToolsDir }
            Move-Item -LiteralPath $partial -Destination $paths.ToolsDir
            if (-not (Test-Path -LiteralPath $paths.Bin)) {
                $found = @(Get-ChildItem -LiteralPath $paths.ToolsDir | ForEach-Object Name)
                Stop-GodotCi "$($paths.Package).zip has no $([System.IO.Path]::GetRelativePath($paths.ToolsDir, $paths.Bin)) (it holds: $($found -join ', '))"
            }
            if (-not $IsWindows) { Invoke-Checked chmod @('+x', $paths.Bin) }
        }

        if ($Templates) {
            if (Test-Path -LiteralPath (Join-Path $paths.TemplatesDir 'version.txt')) {
                Write-CiLog "Export templates already installed"
            } else {
                $tpz = Join-Path (Get-ToolsDir) $paths.TemplatesFile
                Save-RequiredDownload "$($paths.BaseUrl)/$($paths.TemplatesFile)" $tpz
                Confirm-DownloadChecksum $paths.BaseUrl $paths.TemplatesFile $tpz
                $tmp = Join-Path ([IO.Path]::GetTempPath()) "godot-templates-$([guid]::NewGuid())"
                Expand-Zip $tpz $tmp
                New-Item -ItemType Directory -Force $paths.TemplatesDir | Out-Null
                Copy-Item -Recurse -Force -Destination $paths.TemplatesDir -LiteralPath @(Get-ChildItem -LiteralPath (Join-Path $tmp 'templates') -Force | ForEach-Object FullName)
                Remove-Item -Recurse -Force -LiteralPath $tmp, $tpz
            }
        }
    }

    $env:GODOT_BIN = $paths.Bin
    $env:DOTNET_CLI_TELEMETRY_OPTOUT = '1'
    $env:DOTNET_NOLOGO = '1'
    if ($env:GITHUB_ENV) {
        Add-Content -LiteralPath $env:GITHUB_ENV -Value "GODOT_BIN=$($paths.Bin)"
        # Marks GODOT_BIN as ours, so a later step for another project picks its own Godot build instead
        # of treating this one as a Godot the user chose.
        Add-Content -LiteralPath $env:GITHUB_ENV -Value 'HYPERDOT_INSTALLED=1'
        if ($env:DOTNET_ROOT) {
            Add-Content -LiteralPath $env:GITHUB_ENV -Value "DOTNET_ROOT=$env:DOTNET_ROOT"
            Add-Content -LiteralPath $env:GITHUB_PATH -Value $env:DOTNET_ROOT
        }
    }
    $dotnet = if ($Mono) { "  .NET: $(& dotnet --version)" } else { '' }
    Write-CiLog "Godot: $(& $paths.Bin --version)$dotnet"
}

# Installs an addon from a Git tag into <project>/addons. Idempotent.
#   gut@v9.6.1, gdunit4@v6.2.1, or owner/repo@ref:addons/<name>
function Install-Addon([string]$ProjectDir, [string]$Spec) {
    if ($Spec -notmatch '^(?<name>[^@]+)@(?<ref>.+)$') { Stop-GodotCi "Addon '$Spec' needs a version, e.g. gut@v9.6.1" }
    $name = $Matches.name; $ref = $Matches.ref
    switch -Regex ($name) {
        '^gut$' { $repo = 'bitwes/Gut'; $addon = 'addons/gut' }
        '^gdunit4$' { $repo = 'godot-gdunit-labs/gdUnit4'; $addon = 'addons/gdUnit4' }
        '/' {
            if ($ref -notmatch '^(?<r>[^:]+):(?<a>.+)$') { Stop-GodotCi "Custom addon '$Spec' must look like owner/repo@ref:addons/<name>" }
            $repo = $name; $ref = $Matches.r; $addon = $Matches.a
        }
        default { Stop-GodotCi "Unknown addon '$name' (use owner/repo@ref:addons/<name>)" }
    }
    $dest = Join-Path $ProjectDir $addon
    $stamp = Join-Path $dest '.hyperdot-version'
    if ((Test-Path -LiteralPath $stamp) -and (Get-Content -LiteralPath $stamp -Raw).Trim() -eq "$repo@$ref") {
        Write-CiLog "$addon already at $repo@$ref"
        return
    }
    Write-CiLog "Installing $repo@$ref -> $dest"
    $tmp = Join-Path ([IO.Path]::GetTempPath()) "godot-addon-$([guid]::NewGuid())"
    Invoke-Checked git @('-c', 'advice.detachedHead=false', 'clone', '-q', '--depth', '1', '--branch', $ref,
        '--filter=blob:none', '--sparse', "https://github.com/$repo.git", $tmp)
    Invoke-Checked git @('-C', $tmp, 'sparse-checkout', 'set', $addon)
    if (-not (Test-Path -LiteralPath (Join-Path $tmp $addon))) { Stop-GodotCi "$repo@$ref has no $addon folder" }
    # -LiteralPath throughout: a project path with [ or ] is a wildcard to -Path, which then removes nothing and the copy
    # below nests the new add-on inside the old one.
    if (Test-Path -LiteralPath $dest) { Remove-Item -LiteralPath $dest -Recurse -Force }
    New-Item -ItemType Directory -Force (Split-Path $dest) | Out-Null
    Copy-Item -Recurse -LiteralPath (Join-Path $tmp $addon) -Destination $dest
    Set-Content -LiteralPath $stamp -Value "$repo@$ref"
    Remove-Item -LiteralPath $tmp -Recurse -Force
}

# GUT release that matches the Godot minor version.
function Get-GutTag([string]$GodotVersion) {
    switch -Regex ($GodotVersion) {
        '^4\.7' { 'v9.7.1' } '^4\.6' { 'v9.6.1' } '^4\.5' { 'v9.5.0' } '^4\.4' { 'v9.4.0' }
        default { Stop-GodotCi "No known GUT release for Godot $GodotVersion; commit addons/gut yourself" }
    }
}
