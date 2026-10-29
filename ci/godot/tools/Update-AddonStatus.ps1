#Requires -Version 7.6
<#
.SYNOPSIS
    Re-reads each add-on in ci/godot/addons-status.json from its repository, and with -Apply writes what moved: its newest
    commit (head) and whether GitHub has archived it. Prints one JSON document (schema hyperdot-addons-status-check/1).

.DESCRIPTION
    head comes from git ls-remote (no API, no token). archived comes from the GitHub API (GITHUB_TOKEN is used when set);
    when the API cannot be read, archived is left as it is and a note says why. The entry_symbol doctor matches is looked up
    again in the file the entry names (entrySymbolSource), at the repository's newest commit, through raw.githubusercontent.com.
    What a person must judge is listed under review, never applied: a new commit on an add-on doctor warns about because of
    its Godot range or as a prototype (it may now be fit for use), an archived one that is no longer archived, and an
    entry_symbol or file that is gone (doctor would stop recognising a renamed folder). The weekly canary runs this after
    the version updates: changes go into its pull request, review items into issues.
    The newest release's zip is checked too: an entry with a releaseZip record ({ tag, asset, prefix, checked }; asset is the
    zip's name with {tag} for the release's tag) has that asset's file list read (downloaded to a new temporary folder, listed
    with System.IO.Compression and deleted; nothing in it is extracted or run, and the URL is built here from the repository,
    tag and asset name, never taken from the API's answer) and compared with the recorded folder and .gdextension file name. A
    folder found under another prefix is applied (releaseZip.prefix); a folder or file that is not in the zip, an asset that
    is gone, or a repository that now has a release and no record are reported under review, since doctor finds a copy by its
    folder. A new tag whose zip still matches is applied (releaseZip.tag and checked). An API or download that cannot be
    reached (no token on a runner means 60 API calls an hour) is a note, and the entry is left as it was.
    -Source replaces every lookup with a JSON file, for tests: { "<owner/repo>": { "head": "<sha>", "archived": true|false|null,
    "files": { "<path>": "<text>" | null }, "release": { "tag": "<tag>", "assets": { "<name>": "<path of a zip>" | null } } } }
    (a null path is a download that fails; no release key is a repository with no release). "api": true on a repository sends
    its archived and release lookups to -ApiBase and its zip download to -DownloadBase (https://api.github.com and
    https://github.com by default), for tests with a stand-in server.
#>
[CmdletBinding()]
param(
    [string]$Root = (Join-Path $PSScriptRoot '../../..'),
    [switch]$Apply,
    [string]$Source,
    [string]$ApiBase = 'https://api.github.com',
    [string]$DownloadBase = 'https://github.com',
    [int]$MaxZipMegabytes = 600,
    [switch]$Json
)
$ErrorActionPreference = 'Stop'
Set-StrictMode -Version 3.0
$Root = (Resolve-Path -LiteralPath $Root).Path
Add-Type -AssemblyName System.IO.Compression.FileSystem
$relative = 'ci/godot/addons-status.json'
$path = Join-Path $Root $relative
# Objects, not hashtables: they keep the file's order, so a rewrite changes only the values that moved.
$doc = Get-Content -LiteralPath $path -Raw | ConvertFrom-Json
$fromFile = if ($Source) { Get-Content -LiteralPath $Source -Raw | ConvertFrom-Json -AsHashtable } else { $null }
$notes = [System.Collections.Generic.List[string]]::new()
$updates = [System.Collections.Generic.List[object]]::new()
$review = [System.Collections.Generic.List[object]]::new()

function Get-RepoHead([string]$Repo) {
    if ($fromFile) { return $fromFile[$Repo]['head'] }
    $line = @(& git ls-remote "https://github.com/$Repo" HEAD 2>$null) | Select-Object -First 1
    if ($LASTEXITCODE -or "$line" -notmatch '^(?<c>[0-9a-f]{40})\s') { throw "git ls-remote of $Repo failed ($LASTEXITCODE)" }
    return $Matches.c
}
# Without -Source every lookup is real; with it only a repository whose entry has "api": true goes to -ApiBase and -DownloadBase.
function Test-UseApi([string]$Repo) { return (-not $fromFile) -or ($fromFile[$Repo].Contains('api') -and $fromFile[$Repo]['api']) }
function Get-RepoArchived([string]$Repo) {
    if (-not (Test-UseApi $Repo)) { return $fromFile[$Repo]['archived'] }
    $headers = @{ 'User-Agent' = 'hyperdot' }
    if ($env:GITHUB_TOKEN) { $headers['Authorization'] = "Bearer $env:GITHUB_TOKEN" }
    return [bool](Invoke-RestMethod -Uri "$ApiBase/repos/$Repo" -Headers $headers).archived
}
# The file's text at the repository's newest commit, or $null when it is gone.
function Get-RepoFile([string]$Repo, [string]$Commit, [string]$File) {
    if ($fromFile) { $files = $fromFile[$Repo]['files']; return $(if ($files -and $files.Contains($File)) { $files[$File] } else { $null }) }
    try { return (Invoke-WebRequest -Uri "https://raw.githubusercontent.com/$Repo/$Commit/$File" -Headers @{ 'User-Agent' = 'hyperdot' }).Content }
    catch {
        $status = try { [int]$_.Exception.Response.StatusCode } catch { 0 }
        if ($status -eq 404) { return $null }
        throw
    }
}
# The newest release (a pre-release too): { tag, assets: [ { name, size, path } ] }, or $null when the repository has none.
function Get-RepoRelease([string]$Repo) {
    if (-not (Test-UseApi $Repo)) {
        $r = $fromFile[$Repo]
        if (-not $r.Contains('release')) { return $null }
        return [pscustomobject]@{ tag = [string]$r['release']['tag']; assets = @($r['release']['assets'].GetEnumerator() | ForEach-Object { [pscustomobject]@{ name = $_.Key; size = 0; path = $_.Value; stub = $true } }) }
    }
    $headers = @{ 'User-Agent' = 'hyperdot' }
    if ($env:GITHUB_TOKEN) { $headers['Authorization'] = "Bearer $env:GITHUB_TOKEN" }
    $releases = @(Invoke-RestMethod -Uri "$ApiBase/repos/$Repo/releases?per_page=1" -Headers $headers)
    if ($releases.Count -eq 0) { return $null }
    return [pscustomobject]@{ tag = [string]$releases[0].tag_name; assets = @($releases[0].assets | ForEach-Object { [pscustomobject]@{ name = [string]$_.name; size = [long]$_.size; path = $null; stub = $false } }) }
}
# The names of the files in a release zip. Downloaded into a new empty folder under the temporary one, read as a list and deleted:
# nothing is extracted, and the URL is built from the repository, tag and asset name (which must be plain), never from the API.
function Get-ReleaseZipNames([string]$Repo, [string]$Tag, $Asset) {
    $file = $null; $folder = $null
    try {
        if ($Asset.stub) {
            if (-not $Asset.path) { throw "the download of $($Asset.name) failed (stand-in)" }
            $file = $Asset.path
        } else {
            if ($Tag -notmatch '\A[\w.+-]+\z' -or $Asset.name -notmatch '\A[\w.+-]+\z') { throw "the tag or asset name is not plain text: $Tag, $($Asset.name)" }
            $folder = Join-Path ([System.IO.Path]::GetTempPath()) "addon-zip-$([guid]::NewGuid().ToString('n'))"
            [void][System.IO.Directory]::CreateDirectory($folder)
            $file = Join-Path $folder 'asset.zip'
            Invoke-WebRequest -Uri "$DownloadBase/$Repo/releases/download/$Tag/$($Asset.name)" -OutFile $file -Headers @{ 'User-Agent' = 'hyperdot' } -TimeoutSec 600
        }
        $zip = [System.IO.Compression.ZipFile]::OpenRead((Resolve-Path -LiteralPath $file).Path)
        try { return @($zip.Entries | ForEach-Object { $_.FullName }) } finally { $zip.Dispose() }
    } finally { if ($folder) { Remove-Item -LiteralPath $folder -Recurse -Force } }
}
function Add-Update([string]$Id, [string]$Field, $Old, $New) { $updates.Add([ordered]@{ id = $Id; field = $Field; old = $Old; new = $New }) }

foreach ($entry in @($doc.addons)) {
    $id = $entry.id; $repo = $entry.repo
    try {
        $head = Get-RepoHead $repo
    } catch { $notes.Add("${id}: could not read $repo with git ($($_.Exception.Message)); left as it was"); continue }
    if ($head -and $head -ne $entry.head) {
        Add-Update $id 'head' $entry.head $head
        if ($entry.status -ne 'archived') {
            $review.Add([ordered]@{ id = $id; message = "$($entry.name) ($repo) has new commits since $("$($entry.head)".Substring(0, [math]::Min(7, "$($entry.head)".Length))): check whether it is still $($entry.status) (why: $($entry.why)), and update or remove its entry in $relative" })
        }
        $entry.head = $head
    }
    try {
        $archived = Get-RepoArchived $repo
        if ($null -ne $archived -and $archived -ne $entry.archived) {
            Add-Update $id 'archived' $entry.archived $archived
            if (-not $archived -and $entry.status -eq 'archived') {
                $review.Add([ordered]@{ id = $id; message = "$($entry.name) ($repo) is no longer archived: check its state and its entry in $relative" })
            }
            $entry.archived = $archived
        }
    } catch { $notes.Add("${id}: GitHub's API could not be read for archived ($($_.Exception.Message)); left as it was") }
    try {
        $release = Get-RepoRelease $repo
        $record = $entry.PSObject.Properties['releaseZip']
        $record = if ($record) { $record.Value } else { $null }
        if (-not $release) {
            if ($record) { $review.Add([ordered]@{ id = $id; message = "$repo has no release now, and $relative records the zip of $($record.tag): check where $($entry.name) is published, and update or remove its releaseZip" }) }
        } elseif (-not $record) {
            $review.Add([ordered]@{ id = $id; message = "$repo has a release ($($release.tag)) and $relative has no releaseZip for $($entry.name): read its zip's folders, then add one (docs/addons.md)" })
        } else {
            $want = ([string]$record.asset).Replace('{tag}', $release.tag)
            $asset = @($release.assets | Where-Object { $_.name -ceq $want }) | Select-Object -First 1
            if (-not $asset) {
                $review.Add([ordered]@{ id = $id; message = "release $($release.tag) of $repo has no asset named $want (it has: $((@($release.assets | ForEach-Object name)) -join ', ')): update releaseZip.asset of $($entry.name) in $relative" })
            } elseif ($asset.size -gt $MaxZipMegabytes * 1MB) {
                $notes.Add("${id}: $($asset.name) of $repo is $([math]::Round($asset.size / 1MB)) MB, over the $MaxZipMegabytes MB limit; its folders were not checked")
            } else {
                $names = @(Get-ReleaseZipNames $repo $release.tag $asset)
                $problems = 0
                foreach ($folder in @($entry.folders)) {
                    $pattern = "\A(?<p>(?:[^/]+/)*)$([regex]::Escape($folder))/"
                    $hit = @($names | Where-Object { $_ -cmatch $pattern }) | Select-Object -First 1
                    if ($hit) {
                        $prefix = ([regex]::Match($hit, $pattern)).Groups['p'].Value
                        if ($prefix -cne [string]$record.prefix) { Add-Update $id 'releaseZip.prefix' $record.prefix $prefix; $record.prefix = $prefix }
                        $place = "$($record.prefix)$folder/"
                        if (-not @($names | Where-Object { $_.StartsWith($place, [StringComparison]::Ordinal) -and $_.Split('/')[-1] -ceq $entry.gdextension }).Count) {
                            $problems++
                            $review.Add([ordered]@{ id = $id; message = "$($asset.name) of $repo ($($release.tag)) has $place but no file named $($entry.gdextension) in it: doctor finds a renamed copy by that name; update gdextension in $relative" })
                        }
                    } else {
                        $problems++
                        $found = @($names | ForEach-Object { if ($_ -match '(?:\A|/)addons/([^/]+)/') { $Matches[1] } } | Sort-Object -Unique)
                        $review.Add([ordered]@{ id = $id; message = "$($asset.name) of $repo ($($release.tag)) has no $folder/ folder (addons/ in it: $(if ($found) { $found -join ', ' } else { 'none' })): doctor finds $($entry.name) by its folder; update folders in $relative" })
                    }
                }
                if (-not $problems -and $release.tag -cne [string]$record.tag) {
                    Add-Update $id 'releaseZip.tag' $record.tag $release.tag
                    $record.tag = $release.tag
                    $record.checked = [datetime]::UtcNow.ToString('yyyy-MM-dd', [cultureinfo]::InvariantCulture)
                }
            }
        }
    } catch { $notes.Add("${id}: the newest release of $repo could not be checked ($($_.Exception.Message)); left as it was") }
    try {
        $text = Get-RepoFile $repo $entry.head $entry.entrySymbolSource
        if ($null -eq $text) {
            $review.Add([ordered]@{ id = $id; message = "$($entry.entrySymbolSource) is gone from $repo at $($entry.head): find where its .gdextension's entry_symbol is now, and update entrySymbol and entrySymbolSource in $relative" })
        } elseif (-not $text.Contains($entry.entrySymbol)) {
            $review.Add([ordered]@{ id = $id; message = "$($entry.entrySymbolSource) in $repo no longer names entry_symbol $($entry.entrySymbol): doctor finds a renamed copy of $($entry.name) by it; update entrySymbol in $relative" })
        }
    } catch { $notes.Add("${id}: could not read $($entry.entrySymbolSource) from $repo ($($_.Exception.Message))") }
}

$changed = @()
if ($Apply -and $updates.Count -gt 0) {
    Set-Content -LiteralPath $path -Value ($doc | ConvertTo-Json -Depth 6) -Encoding utf8
    $changed = @($relative)
}
$result = [ordered]@{ schema = 'hyperdot-addons-status-check/1'; updates = @($updates); review = @($review); notes = @($notes); changed = $changed }
if ($Json) { [Console]::Out.WriteLine(($result | ConvertTo-Json -Depth 5)) }
else {
    if ($updates.Count -eq 0) { Write-Host 'No add-on in the status list moved.' }
    foreach ($u in $updates) { Write-Host "$($u.id) $($u.field): $($u.old) -> $($u.new)" }
    foreach ($r in $review) { Write-Host "Review: $($r.message)" -ForegroundColor Yellow }
    foreach ($n in $notes) { Write-Host "Note: $n" -ForegroundColor Yellow }
}
