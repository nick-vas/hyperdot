#!/usr/bin/env pwsh
# Self-test of doctor's add-on checks (lib/Addons.ps1), on a project made in a temporary folder: which GDExtension
# library each export preset's builds get, by Godot's own rule (measured on 4.7.2: every tag of a key must be a feature,
# the most tags wins), relative paths and multi-line dependencies, editor-only and excluded extensions, Godot version
# limits; and add-on mistakes: the Godot Jolt extension on 4.4+, an add-on's autoload the game uses but project.godot
# lacks, test add-ons shipped, and Debug Draw 3D forced on. No Godot needed.
Set-StrictMode -Version 3.0
$ErrorActionPreference = 'Stop'
$root = Split-Path $PSScriptRoot
foreach ($lib in 'Common', 'Detect', 'Doctor', 'Addons') { . (Join-Path $root "ci/godot/lib/$lib.ps1") }
$failures = [System.Collections.Generic.List[string]]::new()
function Assert-True([bool]$Condition, [string]$What) {
    if ($Condition) { Write-Host "ok     $What" } else { Write-Host "FAILED $What" -ForegroundColor Red; $failures.Add($What) }
}
function New-Preset([string]$Name, [string]$Platform, [string]$Custom = '', [string]$Exclude = '', [hashtable]$Options = @{}) {
    [pscustomobject]@{ Name = $Name; Platform = $Platform; CustomFeatures = $Custom; ExcludeFilter = $Exclude; Options = $Options }
}
function Get-Messages($Problems) { @($Problems | ForEach-Object { "$($_.Status) $($_.Message)" }) -join "`n" }

# Feature sets as Godot 4.7.2 printed them.
$web = @(Get-ExportFeatureSets (New-Preset 'Web' 'Web'))
Assert-True ($web.Count -eq 2 -and $web[0].Features.Contains('nothreads') -and $web[0].Features.Contains('web_noextensions') -and $web[0].Features.Contains('template_release')) 'Web defaults to nothreads, without extensions'
$android = @(Get-ExportFeatureSets (New-Preset 'Android' 'Android' -Options @{ 'architectures/armeabi-v7a' = 'true'; 'architectures/arm64-v8a' = 'true' }))
Assert-True ($android.Count -eq 4 -and (@($android | ForEach-Object Arch | Sort-Object -Unique) -join ',') -eq 'arm32,arm64') 'Android gets one set per enabled architecture and build'
Assert-True (@(Get-ExportFeatureSets (New-Preset 'Android' 'Android')).Count -eq 2) 'Android defaults to arm64 only'
$mac = @(Get-ExportFeatureSets (New-Preset 'Mac' 'macOS'))
Assert-True ($mac.Count -eq 4 -and $mac[0].Features.Contains('universal')) 'a macOS universal export looks up x86_64 and arm64'

$dir = Join-Path ([System.IO.Path]::GetTempPath()) "addons-$([guid]::NewGuid().ToString('n').Substring(0, 8))"
try {
    foreach ($d in 'addons/native/libs/web', 'addons/native/libs/linux', 'addons/vcs', 'addons/dm', 'addons/gut', 'addons/debug_draw_3d', 'addons/old', 'addons/new', 'scripts') {
        New-Item -ItemType Directory -Force (Join-Path $dir $d) | Out-Null
    }
    Set-Content -LiteralPath (Join-Path $dir 'project.godot') "config_version=5`n`n[application]`n`nconfig/name=`"Addons`"`n"
    foreach ($f in 'libs/linux/native.release.so', 'libs/linux/native.debug.so', 'libs/linux/native.tagged.so', 'libs/web/native.release.wasm', 'libs/linux/dep_a.so') {
        Set-Content -LiteralPath (Join-Path $dir "addons/native/$f") 'fake'
    }
    # Relative paths, a key that only a custom feature picks, release-only Web keys, a multi-line dependency with one file missing.
    Set-Content -LiteralPath (Join-Path $dir 'addons/native/native.gdextension') @'
[configuration]

entry_symbol = "native_init"
compatibility_minimum = 4.5

[libraries]

linux.debug.x86_64 = "libs/linux/native.debug.so"
linux.release.x86_64 = "libs/linux/native.release.so"
linux.template_release.x86_64.demo = "libs/linux/native.tagged.so"
linux.release.arm64 = "libs/linux/native.arm64.so"
web.release.wasm32.nothreads = "libs/web/native.release.wasm"
android.release.arm64 = "res://addons/native/libs/android/native.arm64.so"

[dependencies]

linux.release.x86_64 = {
"libs/linux/dep_a.so": "",
"libs/linux/dep_b.so": ""
}
'@
    $linux = New-Preset 'Linux' 'Linux'
    $problems = @(Get-GdextensionProblems $dir @($linux) '4.7.2')
    $text = Get-Messages $problems
    Assert-True ($text -notmatch 'native\.release\.so|native\.debug\.so|dep_a') "relative paths that exist are found: $text"
    Assert-True ($text -match 'FAIL .*\[dependencies\] linux\.release\.x86_64 names libs/linux/dep_b\.so') 'a missing file in a multi-line dependency fails'
    $tagged = @(Get-GdextensionProblems $dir @(New-Preset 'Demo' 'Linux' -Custom 'demo') '4.7.2')
    Assert-True (@($tagged | Where-Object Message -match 'native\.tagged|has no library').Count -eq 0) "a custom feature picks the key with more tags: $(Get-Messages $tagged)"
    $arm = @(Get-GdextensionProblems $dir @(New-Preset 'LinuxArm' 'Linux' -Options @{ 'binary_format/architecture' = 'arm64' }) '4.7.2')
    Assert-True ((Get-Messages $arm) -match "FAIL .*linux\.release\.arm64 = libs/linux/native\.arm64\.so, which does not exist" -and (Get-Messages $arm) -match "WARN .*no library for export preset 'LinuxArm' \(debug\)") "arm64: a missing release file fails, no debug key warns: $(Get-Messages $arm)"
    $webProblems = @(Get-GdextensionProblems $dir @(New-Preset 'Web' 'Web') '4.7.2')
    Assert-True ($webProblems.Count -eq 1 -and $webProblems[0].Status -eq 'WARN' -and $webProblems[0].Message -match '\(debug\)') "release-only Web keys: the debug build warns, release passes: $(Get-Messages $webProblems)"
    $threads = @(Get-GdextensionProblems $dir @(New-Preset 'WebThreads' 'Web' -Options @{ 'variant/thread_support' = 'true' }) '4.7.2')
    Assert-True (@($threads | Where-Object { $_.Status -eq 'FAIL' -and $_.Message -match '\(release\)' }).Count -eq 1) 'a threads Web export does not fit a nothreads key and fails'
    $two = @(Get-GdextensionProblems $dir @(New-Preset 'Android' 'Android' -Options @{ 'architectures/armeabi-v7a' = 'true' }) '4.7.2')
    Assert-True ((Get-Messages $two) -match "FAIL .*no library for export preset 'Android' \(release, arm32\)" -and (Get-Messages $two) -match "FAIL .*android\.release\.arm64 = res://") "Android names the architecture with no key: $(Get-Messages $two)"
    $excluded = @(Get-GdextensionProblems $dir @(New-Preset 'Excl' 'Web' -Exclude 'addons/native/*') '4.7.2')
    Assert-True ($excluded.Count -eq 0) 'a preset that excludes the add-on is not checked'
    Assert-True (@(Get-GdextensionProblems $dir @($linux) '4.4').Where({ $_.Message -match 'needs Godot 4\.5 or later' }).Count -eq 1) 'an unquoted compatibility_minimum above the engine fails'

    # Editor-only, and version limits.
    Set-Content -LiteralPath (Join-Path $dir 'addons/vcs/vcs.gdextension') "[configuration]`n`nentry_symbol = `"vcs_init`"`ncompatibility_minimum = `"4.3`"`n`n[libraries]`n`nlinux.editor.x86_64 = `"lib/vcs.so`"`n"
    Set-Content -LiteralPath (Join-Path $dir 'addons/old/old.gdextension') "[configuration]`n`nentry_symbol = `"old_init`"`ncompatibility_minimum = `"4.3`"`ncompatibility_maximum = `"4.6`"`n"
    Set-Content -LiteralPath (Join-Path $dir 'addons/new/new.gdextension') "[configuration]`n`nentry_symbol = `"new_init`"`ncompatibility_maximum = `"4.7`"`n"
    $moreProblems = @(Get-GdextensionProblems $dir @($linux) '4.7.2')
    $more = Get-Messages $moreProblems
    $editorOnly = @($moreProblems | Where-Object Message -match 'vcs\.gdextension is an editor-only extension')
    Assert-True ($editorOnly.Count -eq 1 -and $editorOnly[0].Status -eq 'WARN' -and $editorOnly[0].Fix -match 'addons/vcs/\*') 'an editor-only extension in an export warns, naming the folder to exclude'
    Assert-True ($more -match 'FAIL res://addons/old/old\.gdextension supports Godot up to 4\.6') 'a maximum below the engine fails'
    Assert-True ($more -notmatch 'new\.gdextension supports' -and $more -match 'FAIL res://addons/new/new\.gdextension has no compatibility_minimum') 'a maximum of 4.7 includes 4.7.2; a missing minimum fails'
    $vcsExcluded = Get-Messages @(Get-GdextensionProblems $dir @(New-Preset 'L' 'Linux' -Exclude 'addons/vcs/*') '4.7.2')
    Assert-True ($vcsExcluded -notmatch 'editor-only') 'an excluded editor-only extension is fine'

    # Add-on problems.
    Set-Content -LiteralPath (Join-Path $dir 'addons/dm/plugin.gd') "@tool`nextends EditorPlugin`nconst SINGLETON_NAME := `"DialogueManager`"`nfunc _enable_plugin():`n`tadd_autoload_singleton(SINGLETON_NAME, `"res://addons/dm/dialogue_manager.gd`")`n`tadd_autoload_singleton(`"DialogueUnused`", `"res://addons/dm/x.gd`")`n"
    Set-Content -LiteralPath (Join-Path $dir 'scripts/npc.gd') "extends Node`nfunc talk():`n`tDialogueManager.show_dialogue_balloon(load(`"res://intro.dialogue`"))`n"
    $godot = "config_version=5`n`n[physics]`n`n3d/physics_engine=`"Jolt Physics (Extension)`"`n"
    $addon = Get-Messages @(Get-AddonProblems $dir $godot @(New-Preset 'Release' 'Linux' -Custom 'forced_dd3d'; New-Preset 'Clean' 'Linux' -Exclude 'test/*, addons/gut/*') '4.7.2')
    Assert-True ($addon -match 'WARN The project uses the Godot Jolt extension') 'the Godot Jolt extension on 4.7 warns'
    Assert-True ($addon -match 'WARN The game uses DialogueManager, an autoload that res://addons/dm/plugin\.gd registers') 'an add-on autoload the game uses but project.godot lacks warns (through a constant)'
    Assert-True ($addon -notmatch 'DialogueUnused') 'an autoload the game does not use is not reported'
    Assert-True ($addon -match "WARN Export preset 'Release' ships addons/gut" -and $addon -notmatch "'Clean' ships") 'GUT in an export warns unless excluded'
    Assert-True ($addon -match "WARN Export preset 'Release' sets forced_dd3d" -and $addon -notmatch "'Clean' sets forced_dd3d") 'forced_dd3d in a preset warns'
    $clean = Get-Messages @(Get-AddonProblems $dir "config_version=5`n`n[autoload]`n`nDialogueManager=`"*res://addons/dm/dialogue_manager.gd`"`n`n[physics]`n`n3d/physics_engine=`"Jolt Physics`"`n" @() '4.7.2')
    Assert-True ($clean -notmatch 'Jolt|DialogueManager') "the built-in Jolt and a registered autoload pass: $clean"
    Assert-True ((Get-Messages @(Get-AddonProblems $dir $godot @() '4.3')) -notmatch 'Jolt') 'the Jolt extension on 4.3 is fine'

    # End to end: doctor reports them and fails on the release library.
    Set-Content -LiteralPath (Join-Path $dir 'export_presets.cfg') "[preset.0]`n`nname=`"Web`"`nplatform=`"Web`"`nrunnable=true`ncustom_features=`"`"`nexport_filter=`"all_resources`"`ninclude_filter=`"`"`nexclude_filter=`"addons/gut/*`"`nexport_path=`"build/web/index.html`"`n`n[preset.0.options]`n`nvariant/thread_support=true`n"
    & git -C $dir init -q
    $json = & pwsh -NoProfile -NonInteractive -File (Join-Path $root 'ci/godot/hyperdot.ps1') doctor -Project $dir -Json 2>$null | Out-String | ConvertFrom-Json
    $messages = @($json.checks | ForEach-Object { "$($_.status) $($_.message)" }) -join "`n"
    Assert-True ($json.ok -eq $false -and $messages -match "FAIL res://addons/native/native\.gdextension has no library for export preset 'Web' \(release\)") "doctor fails on a release build with no library: $(($messages -split "`n" | Select-String 'gdextension|addons') -join ' | ')"
} finally {
    Remove-Item -LiteralPath $dir -Recurse -Force -ErrorAction SilentlyContinue
}

# Add-ons with a known status (ci/godot/addons-status.json), in a project of their own: found by folder in any letter
# case, or renamed by their .gdextension's file name and entry_symbol; a Godot range only warns outside it.
$known = Join-Path ([System.IO.Path]::GetTempPath()) "addons-known-$([guid]::NewGuid().ToString('n').Substring(0, 8))"
try {
    foreach ($d in 'addons/perfbullets', 'addons/godot-steam-audio', 'addons/py', 'addons/other') { New-Item -ItemType Directory -Force (Join-Path $known $d) | Out-Null }
    Set-Content -LiteralPath (Join-Path $known 'addons/py/python.gdextension') "[configuration]`n`nentry_symbol = `"initialize_pythonscript`"`ncompatibility_minimum = `"4.7.0`"`n"
    # The same file name with another entry_symbol is someone else's extension.
    Set-Content -LiteralPath (Join-Path $known 'addons/other/python.gdextension') "[configuration]`n`nentry_symbol = `"other_init`"`ncompatibility_minimum = `"4.5`"`n"
    $statusList = Get-Content -LiteralPath (Join-Path $root 'ci/godot/addons-status.json') -Raw | ConvertFrom-Json
    Assert-True (@($statusList.addons | Where-Object { -not ($_.id -and $_.repo -and $_.folders -and $_.gdextension -and $_.entrySymbol -and $_.entrySymbolSource -and $_.why -and $_.fix -and $_.head -match '^[0-9a-f]{40}$' -and $_.confirmed) }).Count -eq 0) 'every status entry names its repository, folders, file, entry_symbol, source, reason, fix, commit and how it was confirmed'
    $knownProblems = @(Get-AddonProblems $known "config_version=5`n" @() '4.7.2')
    $knownText = Get-Messages $knownProblems
    Assert-True ($knownText -match 'WARN res://addons/perfbullets is Godot-PerfBullets \(Moonzel/Godot-PerfBullets\), not made for this Godot: .*works with Godot 4\.1 and 4\.2.* It supports Godot up to 4\.2, and the project uses 4\.7\.2') "PerfBullets is found by its folder in another case, outside its Godot range: $knownText"
    Assert-True ($knownText -match 'WARN res://addons/godot-steam-audio is godot-steam-audio \(stechyo/godot-steam-audio\), no longer maintained: archived') 'godot-steam-audio warns as archived'
    Assert-True ($knownText -match 'WARN res://addons/py/python\.gdextension is py4godot' -and @($knownProblems | Where-Object Message -match 'addons/other').Count -eq 0) 'a renamed py4godot is found by file name and entry_symbol, another extension with its file name is not'
    Assert-True ((Get-Messages @(Get-AddonProblems $known "config_version=5`n" @() '4.2.2')) -notmatch 'PerfBullets') 'PerfBullets on Godot 4.2 is within its range'
    # Godot Jolt: the folder alone warns; with the extension's physics engine set, the setting's warning (which names the
    # folder) is the only Jolt line.
    New-Item -ItemType Directory -Force (Join-Path $known 'addons/godot-jolt') | Out-Null
    $joltFolder = Get-Messages @(Get-AddonProblems $known "config_version=5`n" @() '4.7.2')
    Assert-True ($joltFolder -match 'WARN res://addons/godot-jolt is Godot Jolt \(godot-jolt/godot-jolt\), superseded by the engine') "addons/godot-jolt on 4.7 warns from the list: $joltFolder"
    $joltBoth = @(Get-AddonProblems $known "config_version=5`n`n[physics]`n`n3d/physics_engine=`"Jolt Physics (Extension)`"`n" @() '4.7.2')
    Assert-True (@($joltBoth | Where-Object Message -match 'Jolt').Count -eq 1) "with the extension's physics engine set, one Jolt line: $(Get-Messages $joltBoth)"
    Assert-True ((Get-Messages @(Get-AddonProblems $known "config_version=5`n" @() '4.6.1')) -notmatch 'Godot Jolt') 'Godot Jolt on 4.6 is within its range'

    # The canary's refresh (Update-AddonStatus.ps1) on a copy of the list, with made-up repositories (-Source).
    $copyRoot = Join-Path $known 'kit'
    New-Item -ItemType Directory -Force (Join-Path $copyRoot 'ci/godot') | Out-Null
    Copy-Item -LiteralPath (Join-Path $root 'ci/godot/addons-status.json') -Destination (Join-Path $copyRoot 'ci/godot/addons-status.json')
    $source = @{}
    foreach ($a in $statusList.addons) { $source[$a.repo] = @{ head = $a.head; archived = $a.archived; files = @{ $a.entrySymbolSource = "entry_symbol = `"$($a.entrySymbol)`"" } } }
    # The newest release's zip of each add-on with a releaseZip record: the right folder and file inside, in the recorded place.
    $zipDir = Join-Path $known 'zips'
    New-Item -ItemType Directory -Force $zipDir | Out-Null
    function New-TestZip([string]$Name, [string[]]$Entries) {
        $zipPath = Join-Path $zipDir $Name
        $stream = [System.IO.File]::Create($zipPath)
        $zip = [System.IO.Compression.ZipArchive]::new($stream, [System.IO.Compression.ZipArchiveMode]::Create)
        foreach ($e in $Entries) { $entry = $zip.CreateEntry($e); $w = [System.IO.StreamWriter]::new($entry.Open()); $w.Write('x'); $w.Dispose() }
        $zip.Dispose(); $stream.Dispose()
        return $zipPath
    }
    function New-ReleaseSource($Addon, [string]$Tag, [string]$Folder, [string]$Prefix, [bool]$Gdextension = $true, [string]$Label = 'good') {
        $rz = $Addon.releaseZip
        $inside = "$Prefix$Folder"
        $entries = @("$inside/LICENSE.txt")
        if ($Gdextension) { $entries += "$inside/$($Addon.gdextension)" }
        return @{ tag = $Tag; assets = @{ ($rz.asset.Replace('{tag}', $Tag)) = (New-TestZip "$Label-$($Addon.id)-$Tag.zip" $entries) } }
    }
    foreach ($a in $statusList.addons) {
        if ($a.PSObject.Properties['releaseZip']) { $source[$a.repo].release = New-ReleaseSource $a $a.releaseZip.tag $a.folders[0] $a.releaseZip.prefix }
    }
    Assert-True (@($statusList.addons | Where-Object { $_.PSObject.Properties['releaseZip'] }).Count -ge 3) 'the list records the release zip of Godot Jolt, godot-steam-audio and py4godot'
    $source['godot-jolt/godot-jolt'].archived = $true
    $source['stechyo/godot-steam-audio'].archived = $false
    $source['Moonzel/Godot-PerfBullets'].head = 'c' * 40
    $source['niklas2902/py4godot'].files = @{}
    $sourceFile = Join-Path $known 'source.json'
    $source | ConvertTo-Json -Depth 5 | Set-Content -LiteralPath $sourceFile
    $tool = Join-Path $root 'ci/godot/tools/Update-AddonStatus.ps1'
    $r = & pwsh -NoProfile -NonInteractive -File $tool -Root $copyRoot -Source $sourceFile -Apply -Json | Out-String | ConvertFrom-Json
    $updates = @($r.updates | ForEach-Object { "$($_.id).$($_.field)" } | Sort-Object)
    Assert-True (($updates -join ',') -eq 'godot-jolt.archived,godot-perfbullets.head,godot-steam-audio.archived') "head and archived changes are found: $($updates -join ',')"
    $reviewIds = @($r.review | ForEach-Object id | Sort-Object)
    Assert-True (($reviewIds -join ',') -eq 'godot-perfbullets,godot-steam-audio,py4godot') "a new commit on a warned add-on, an unarchived one and a missing entry_symbol file need a person: $($reviewIds -join ',')"
    $written = Get-Content -LiteralPath (Join-Path $copyRoot 'ci/godot/addons-status.json') -Raw | ConvertFrom-Json
    $perf = @($written.addons | Where-Object id -eq 'godot-perfbullets')[0]
    $jolt = @($written.addons | Where-Object id -eq 'godot-jolt')[0]
    Assert-True ($perf.head -eq ('c' * 40) -and $jolt.archived -eq $true -and $perf.status -eq 'unsupported' -and @($r.changed) -contains 'ci/godot/addons-status.json') '-Apply writes head and archived, and leaves the status to a person'
    $again = & pwsh -NoProfile -NonInteractive -File $tool -Root $copyRoot -Source $sourceFile -Apply -Json | Out-String | ConvertFrom-Json
    Assert-True (@($r.notes).Count -eq 0 -and ($updates -join ',') -notmatch 'releaseZip') "release zips with the recorded folder, file and tag change nothing and raise no note: $(@($r.notes) -join '; ')"
    Assert-True (@($again.updates).Count -eq 0 -and @($again.changed).Count -eq 0 -and (@($again.review | ForEach-Object id) -join ',') -eq 'py4godot') "a second run changes nothing; only the missing file is still reported: $(@($again.review | ForEach-Object id) -join ',')"

    # The zip check: a wrong folder, a missing .gdextension, a download that fails, a new tag with a good zip, a folder under
    # another prefix, and a repository with a release and no record. Each on a fresh copy of the list.
    $zipCopy = Join-Path $known 'kit-zip'
    New-Item -ItemType Directory -Force (Join-Path $zipCopy 'ci/godot') | Out-Null
    Copy-Item -LiteralPath (Join-Path $root 'ci/godot/addons-status.json') -Destination (Join-Path $zipCopy 'ci/godot/addons-status.json')
    $byId = @{}; foreach ($a in $statusList.addons) { $byId[$a.id] = $a }
    $zs = @{}
    foreach ($a in $statusList.addons) { $zs[$a.repo] = @{ head = $a.head; archived = $a.archived; files = @{ $a.entrySymbolSource = "entry_symbol = `"$($a.entrySymbol)`"" } } }
    # Godot Jolt: the folder is named another way in the zip (the add-on would be missed by doctor).
    $zs['godot-jolt/godot-jolt'].release = New-ReleaseSource $byId['godot-jolt'] 'v0.16.0-stable' 'addons/godot_jolt' ''
    # godot-steam-audio: a new tag, with the folder under a wrapper folder.
    $zs['stechyo/godot-steam-audio'].release = New-ReleaseSource $byId['godot-steam-audio'] '0.3.2' 'addons/godot-steam-audio' 'pkg/'
    # py4godot: the folder is there and its .gdextension is not; PerfBullets has a release now.
    $zs['niklas2902/py4godot'].release = New-ReleaseSource $byId['py4godot'] '4.7-alpha21' 'addons/py4godot' 'install_dir/' $false 'nofile'
    $zs['Moonzel/Godot-PerfBullets'].release = @{ tag = 'v1'; assets = @{ 'x.zip' = $null } }
    $zsFile = Join-Path $known 'zs.json'
    $zs | ConvertTo-Json -Depth 6 | Set-Content -LiteralPath $zsFile
    $z = & pwsh -NoProfile -NonInteractive -File $tool -Root $zipCopy -Source $zsFile -Apply -Json | Out-String | ConvertFrom-Json
    $zMessages = @($z.review | ForEach-Object { "$($_.id): $($_.message)" })
    Assert-True (@($zMessages | Where-Object { $_ -match '^godot-jolt: .*godot-jolt_v0\.16\.0-stable\.zip.*no addons/godot-jolt/ folder \(addons/ in it: godot_jolt\)' }).Count -eq 1) "a zip with another folder name is reported with the folders it has: $($zMessages -join ' | ')"
    Assert-True (@($zMessages | Where-Object { $_ -match '^py4godot: .*no file named python\.gdextension' }).Count -eq 1) "a folder without the .gdextension is reported: $($zMessages -join ' | ')"
    Assert-True (@($zMessages | Where-Object { $_ -match '^godot-perfbullets: .*has a release \(v1\).*no releaseZip' }).Count -eq 1) "a repository that now has a release and no record is reported: $($zMessages -join ' | ')"
    Assert-True (@($zMessages | Where-Object { $_ -match '^godot-steam-audio: ' }).Count -eq 0) "a new tag whose zip matches needs no person: $($zMessages -join ' | ')"
    $zUpdates = @($z.updates | ForEach-Object { "$($_.id).$($_.field)=$($_.new)" } | Sort-Object)
    Assert-True (($zUpdates -join ',') -eq 'godot-steam-audio.releaseZip.prefix=pkg/,godot-steam-audio.releaseZip.tag=0.3.2') "a new tag and a new prefix are proposed and nothing else: $($zUpdates -join ',')"
    $zWritten = Get-Content -LiteralPath (Join-Path $zipCopy 'ci/godot/addons-status.json') -Raw | ConvertFrom-Json
    $zSteam = @($zWritten.addons | Where-Object id -eq 'godot-steam-audio')[0]
    $zJolt = @($zWritten.addons | Where-Object id -eq 'godot-jolt')[0]
    Assert-True ($zSteam.releaseZip.tag -eq '0.3.2' -and $zSteam.releaseZip.prefix -eq 'pkg/' -and $zSteam.releaseZip.checked -match '^\d{4}-\d\d-\d\d$' -and $zJolt.releaseZip.tag -eq 'v0.16.0-stable' -and $zJolt.folders[0] -eq 'addons/godot-jolt') '-Apply writes the tag, prefix and date of a good zip, and leaves a mismatched entry (the folders) to a person'
    Assert-True (@($z.notes).Count -eq 0) "no zip is read for an entry with no record: $(@($z.notes) -join '; ')"
    # A download that fails is a note; the entry is left as it was, and the run still succeeds.
    $zs['godot-jolt/godot-jolt'].release = @{ tag = 'v0.99.0-stable'; assets = @{ 'godot-jolt_v0.99.0-stable.zip' = $null } }
    $zs | ConvertTo-Json -Depth 6 | Set-Content -LiteralPath $zsFile
    $zf = & pwsh -NoProfile -NonInteractive -File $tool -Root $zipCopy -Source $zsFile -Json | Out-String | ConvertFrom-Json
    Assert-True (@($zf.notes | Where-Object { $_ -match '^godot-jolt: the newest release of godot-jolt/godot-jolt could not be checked \(the download of godot-jolt_v0\.99\.0-stable\.zip failed' }).Count -eq 1 -and @($zf.updates | Where-Object id -eq 'godot-jolt').Count -eq 0) "an unreachable download is a note and changes nothing: $(@($zf.notes) -join ' | ')"

    # The real path against a stand-in server on 127.0.0.1: the API's archived and releases answers, the zip downloaded to a
    # temporary folder and listed (a new tag, so the record moves), another repository's API answering 403 (a note, the entry
    # left as it was), and nothing left behind in the temporary folder.
    $goodZip = [System.IO.File]::ReadAllBytes((New-TestZip 'served.zip' @('addons/godot-jolt/', 'addons/godot-jolt/godot-jolt.gdextension')))
    $probe = [System.Net.Sockets.TcpListener]::new([System.Net.IPAddress]::Loopback, 0)
    $probe.Start(); $port = $probe.LocalEndpoint.Port; $probe.Stop()
    $server = Start-ThreadJob -ArgumentList $port, $goodZip -ScriptBlock {
        param($Port, $ZipBytes)
        $listener = [System.Net.HttpListener]::new()
        $listener.Prefixes.Add("http://127.0.0.1:$Port/")
        $listener.Start()
        try {
            while ($true) {
                $context = $listener.GetContext()
                $path = $context.Request.Url.AbsolutePath
                $reply = switch ($path) {
                    '/repos/godot-jolt/godot-jolt' { @(200, 'application/json', [System.Text.Encoding]::UTF8.GetBytes('{"archived": true}')) }
                    '/repos/godot-jolt/godot-jolt/releases' { @(200, 'application/json', [System.Text.Encoding]::UTF8.GetBytes('[{"tag_name": "v0.17.0-stable", "assets": [{"name": "godot-jolt_v0.17.0-stable.zip", "size": 200, "browser_download_url": "http://127.0.0.1:1/never-used.zip"}]}]')) }
                    '/godot-jolt/godot-jolt/releases/download/v0.17.0-stable/godot-jolt_v0.17.0-stable.zip' { @(200, 'application/zip', $ZipBytes) }
                    '/stop' { $null }
                    default { @(403, 'application/json', [System.Text.Encoding]::UTF8.GetBytes('{"message": "rate limit exceeded"}')) }
                }
                if ($null -eq $reply) { $context.Response.Close(); break }
                $context.Response.StatusCode = $reply[0]; $context.Response.ContentType = $reply[1]
                $context.Response.OutputStream.Write($reply[2], 0, $reply[2].Length); $context.Response.Close()
            }
        } finally { $listener.Stop() }
    }
    $httpCopy = Join-Path $known 'kit-http'
    New-Item -ItemType Directory -Force (Join-Path $httpCopy 'ci/godot') | Out-Null
    Copy-Item -LiteralPath (Join-Path $root 'ci/godot/addons-status.json') -Destination (Join-Path $httpCopy 'ci/godot/addons-status.json')
    $hs = @{}
    foreach ($a in $statusList.addons) { $hs[$a.repo] = @{ head = $a.head; archived = $a.archived; files = @{ $a.entrySymbolSource = "entry_symbol = `"$($a.entrySymbol)`"" } } }
    $hs['godot-jolt/godot-jolt'].api = $true
    $hs['stechyo/godot-steam-audio'].api = $true
    $hsFile = Join-Path $known 'hs.json'
    $hs | ConvertTo-Json -Depth 6 | Set-Content -LiteralPath $hsFile
    $tempBefore = @(Get-ChildItem -LiteralPath ([System.IO.Path]::GetTempPath()) -Directory -Filter 'addon-zip-*' | ForEach-Object Name)
    $env:NO_PROXY = '127.0.0.1,localhost'; $env:no_proxy = '127.0.0.1,localhost'
    try {
        $h = & pwsh -NoProfile -NonInteractive -File $tool -Root $httpCopy -Source $hsFile -ApiBase "http://127.0.0.1:$port" -DownloadBase "http://127.0.0.1:$port" -Apply -Json | Out-String | ConvertFrom-Json
    } finally {
        try { Invoke-RestMethod "http://127.0.0.1:$port/stop" -NoProxy -TimeoutSec 5 | Out-Null } catch { Write-Host "stop: $($_.Exception.Message)" }
        Remove-Item Env:NO_PROXY, Env:no_proxy -ErrorAction SilentlyContinue
        Receive-Job $server -Wait -AutoRemoveJob -ErrorAction SilentlyContinue | Out-Null
    }
    $hUpdates = @($h.updates | ForEach-Object { "$($_.id).$($_.field)=$($_.new)" } | Sort-Object)
    Assert-True (($hUpdates -join ',') -eq 'godot-jolt.archived=True,godot-jolt.releaseZip.tag=v0.17.0-stable') "archived and the new tag are read from the stand-in API and its zip: $($hUpdates -join ',')"
    Assert-True (@($h.notes | Where-Object { $_ -match '^godot-steam-audio: GitHub''s API could not be read for archived' }).Count -eq 1 -and @($h.notes | Where-Object { $_ -match '^godot-steam-audio: the newest release of stechyo/godot-steam-audio could not be checked' }).Count -eq 1) "an API that answers 403 is a note for archived and for the release, not a failure: $(@($h.notes) -join ' | ')"
    $tempAfter = @(Get-ChildItem -LiteralPath ([System.IO.Path]::GetTempPath()) -Directory -Filter 'addon-zip-*' | ForEach-Object Name)
    Assert-True (@($tempAfter | Where-Object { $tempBefore -notcontains $_ }).Count -eq 0) 'the downloaded zip is deleted'
} finally {
    Remove-Item -LiteralPath $known -Recurse -Force -ErrorAction SilentlyContinue
}

# Checks that read the machine and the project's own files (field test M1, M2, M3, D10).
$wave = Join-Path ([System.IO.Path]::GetTempPath()) "wave3-$([guid]::NewGuid().ToString('n').Substring(0, 8))"
try {
    $hostOs = if ($IsWindows) { 'windows' } elseif ($IsMacOS) { 'macos' } else { 'linux' }
    $otherOs = if ($hostOs -eq 'windows') { 'linux' } else { 'windows' }
    New-Item -ItemType Directory -Force (Join-Path $wave 'addons/native/bin') | Out-Null
    Set-Content -LiteralPath (Join-Path $wave 'project.godot') "config_version=5`n"
    $ext = Join-Path $wave 'addons/native/native.gdextension'
    $keys = @($hostOs, 'linux', 'windows', 'macos' | Select-Object -Unique)
    # The library key lists every platform, so it fits whichever machine runs this test; the file is what is missing.
    Set-Content -LiteralPath $ext (@("[configuration]", 'entry_symbol = "native_init"', 'compatibility_minimum = 4.5', '', '[libraries]', '') + @(foreach ($os in $keys) { "$os.debug = `"bin/native-$os.lib`"" }))
    $host1 = @(Get-GdextensionHostProblems $wave)
    Assert-True ($host1.Count -eq 1 -and $host1[0].Status -eq 'FAIL' -and $host1[0].Message -match 'which does not exist') "a library missing on this machine fails: $(Get-Messages $host1)"
    foreach ($os in $keys) { Set-Content -LiteralPath (Join-Path $wave "addons/native/bin/native-$os.lib") 'fake' }
    Assert-True (@(Get-GdextensionHostProblems $wave).Count -eq 0) 'the library on disk passes'
    Set-Content -LiteralPath $ext "[configuration]`nentry_symbol = `"native_init`"`ncompatibility_minimum = 4.5`n`n[libraries]`n`n$otherOs.debug = `"bin/native-$otherOs.lib`"`n"
    $host2 = @(Get-GdextensionHostProblems $wave)
    Assert-True ($host2.Count -eq 1 -and $host2[0].Status -eq 'WARN' -and $host2[0].Message -match 'no library for this machine') "an extension without a library for this OS warns: $(Get-Messages $host2)"

    $cs = Join-Path $wave 'cs'
    New-Item -ItemType Directory -Force (Join-Path $cs 'addons/imgui') | Out-Null
    Set-Content -LiteralPath (Join-Path $cs 'addons/imgui/Thing.cs') 'class Thing {}'
    $csProblem = Get-CsWithoutProjectProblem $cs $false
    Assert-True ($csProblem -and $csProblem.Status -eq 'WARN' -and $csProblem.Message -match '1 C# file\(s\), the first res://addons/imgui/Thing\.cs') "C# files with no project warn: $($csProblem.Message)"
    Assert-True ($null -eq (Get-CsWithoutProjectProblem $cs $true)) 'C# files with a project are fine'
    Assert-True ($null -eq (Get-CsWithoutProjectProblem (Join-Path $wave 'addons') $false)) 'no C# files, nothing to say'

    $mismatch = Get-SdkPinProblem '<Project Sdk="Godot.NET.Sdk/4.6.2">' '4.7.2' 'Game.csproj'
    Assert-True ($mismatch -and $mismatch.Status -eq 'WARN' -and $mismatch.Message -match '4\.6\.2') 'a Godot.NET.Sdk pin of another minor warns'
    $patch = Get-SdkPinProblem '<Project Sdk="Godot.NET.Sdk/4.7.0">' '4.7.2' 'Game.csproj'
    Assert-True ($patch -and $patch.Status -eq 'INFO' -and $patch.Message -match 'rewrites the pin') 'a pin of another patch says the editor rewrites it'
    Assert-True ($null -eq (Get-SdkPinProblem '<Project Sdk="Godot.NET.Sdk/4.7.2">' '4.7.2' 'Game.csproj') -and $null -eq (Get-SdkPinProblem '<Project Sdk="Godot.NET.Sdk/4.7">' '4.7.2' 'Game.csproj')) 'the matching pin, or one with only a minor, is quiet'

    $ci = Join-Path $wave 'ci/.github/workflows'
    New-Item -ItemType Directory -Force $ci | Out-Null
    Set-Content -LiteralPath (Join-Path $ci 'build.yml.disabled') "jobs:`n  t:`n    steps:`n      - with:`n          godot-version: '4.6'`n"
    Set-Content -LiteralPath (Join-Path $ci 'ok.yml') "jobs:`n  t:`n    steps:`n      - with:`n          godot-version: 4.7.2`n"
    $ciProblems = @(Get-CiVersionProblems (Join-Path $wave 'ci') '4.7.2')
    Assert-True ($ciProblems.Count -eq 1 -and $ciProblems[0].Message -match 'build\.yml\.disabled \(disabled\) pins godot-version 4\.6') "a workflow pinning another minor warns, a matching one does not: $(Get-Messages $ciProblems)"
} finally {
    Remove-Item -LiteralPath $wave -Recurse -Force -ErrorAction SilentlyContinue
}

if ($failures.Count) { throw "$($failures.Count) add-on check(s) failed" }
Write-Host 'add-on self-test passed'
# The doctor run above failed on purpose; GitHub's pwsh wrapper would exit with its code.
exit 0
