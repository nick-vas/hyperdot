#!/usr/bin/env pwsh
# The input hash of each Self-test job, for the cache of docs/ci-cache.md (stage 0: measured, nothing is skipped).
#
# A job's hash is the sha256 of
#   the job id, the kind of event (pull_request or not), the runner image and the PowerShell version,
#   and the git object id and mode of every file the job reads: the files Select-Jobs.ps1 -Inputs lists for it (a file is
#   an input of a job exactly when a change to that file alone would run the job), read from the commit's tree, not the disk.
# `lint` has no such list (it always runs and reads most of the tree): its hash is over the commit's whole tree id.
# Git object ids are the content hash: two commits with different ids but the same files for a job give the same hash.
#
# Outputs `<job>=<first 32 hex characters>`: appended to $GITHUB_OUTPUT, or printed as JSON with -Json.
param(
    [string]$Root = (Split-Path (Split-Path $PSScriptRoot)),
    [string]$Commit = 'HEAD',
    [string]$EventName = $env:GITHUB_EVENT_NAME,
    # The runner image, as the apt action keys it ($env:ImageOS-$env:ImageVersion on a hosted runner).
    [string]$Runner = $(if ($env:ImageOS) { "$($env:ImageOS)-$($env:ImageVersion)" } else { "$($env:RUNNER_OS)-$($env:RUNNER_ARCH)" }),
    # A job that runs on another runner than this one, as JSON: {"local-windows": "windows-latest"}. Its hash then uses that
    # string instead of -Runner (the hosted image version of a runner this job is not on cannot be read here, so give a label
    # that is changed by hand, or a version, when the runner matters).
    [string]$RunnerByJob = $env:RUNNER_BY_JOB,
    # Job -> files, as Select-Jobs.ps1 -Inputs prints it (default: asked of it).
    [string]$InputsPath,
    [switch]$Json
)
Set-StrictMode -Version 3.0
$ErrorActionPreference = 'Stop'

function Get-Sha256Hex([string]$Text) {
    $bytes = [System.Text.Encoding]::UTF8.GetBytes($Text)
    return [System.BitConverter]::ToString([System.Security.Cryptography.SHA256]::HashData($bytes)).Replace('-', '').ToLowerInvariant()
}

$inputs = if ($InputsPath) { Get-Content -LiteralPath $InputsPath -Raw | ConvertFrom-Json -AsHashtable }
          else { (& pwsh -NoProfile -NonInteractive -File (Join-Path $PSScriptRoot 'Select-Jobs.ps1') -Root $Root -Inputs) -join "`n" | ConvertFrom-Json -AsHashtable }

$runnerOf = @{}
if ($RunnerByJob) { foreach ($property in ($RunnerByJob | ConvertFrom-Json).PSObject.Properties) { $runnerOf[$property.Name] = [string]$property.Value } }

# One listing of the commit's tree: path -> "mode oid". (-z: a path with a space or a quote is not escaped.) Ordinal: two
# tracked files whose names differ in case are two files.
$tree = [System.Collections.Generic.Dictionary[string, string]]::new([System.StringComparer]::Ordinal)
$listing = (& git -C $Root ls-tree -r -z $Commit) -join ''
if ($LASTEXITCODE -ne 0) { throw "git ls-tree $Commit failed" }
foreach ($entry in $listing.Split([char]0, [System.StringSplitOptions]::RemoveEmptyEntries)) {
    $tab = $entry.IndexOf("`t")
    $meta = $entry.Substring(0, $tab).Split(' ')
    $tree[$entry.Substring($tab + 1)] = "$($meta[0]) $($meta[2])"
}
$treeId = (& git -C $Root rev-parse "$Commit^{tree}").Trim()
if ($LASTEXITCODE -ne 0) { throw "git rev-parse $Commit^{tree} failed" }

$kind = if ($EventName -eq 'pull_request') { 'pull_request' } else { 'other' }
$pwshVersion = $PSVersionTable.PSVersion.ToString()
$hashes = [ordered]@{}
$jobs = @('lint') + @($inputs.Keys)
foreach ($job in $jobs) {
    $lines = [System.Collections.Generic.List[string]]::new()
    $lines.Add("job=$job"); $lines.Add("event=$kind"); $lines.Add("runner=$(if ($runnerOf.ContainsKey($job)) { $runnerOf[$job] } else { $Runner })"); $lines.Add("pwsh=$pwshVersion")
    if ($job -eq 'lint') { $lines.Add("tree=$treeId") }
    else {
        foreach ($file in @($inputs[$job] | Sort-Object { $_ } -CaseSensitive)) {
            if ($tree.ContainsKey($file)) { $lines.Add("$($tree[$file]) $file") }
        }
    }
    $hashes[$job] = (Get-Sha256Hex ($lines -join "`n")).Substring(0, 32)
}

if ($Json) { ConvertTo-Json -InputObject $hashes -Depth 3; return }
if ($env:GITHUB_OUTPUT) { foreach ($job in $hashes.Keys) { "$job=$($hashes[$job])" >> $env:GITHUB_OUTPUT } }
foreach ($job in $hashes.Keys) { Write-Host "$job $($hashes[$job])" }
