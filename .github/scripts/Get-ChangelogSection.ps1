#Requires -Version 7.6
<#
.SYNOPSIS
    Prints the body of one version's section of CHANGELOG.md: the lines under `## <Version> - <date>` up to the next `## `
    heading. Run by .github/workflows/release.yml for the release notes, and by tests/Test-ReleaseNotes.ps1.

.DESCRIPTION
    The heading must be `## <Version> - ` with the whole version (0.1.0 does not match 0.1.01 or 10.1.0). Stops with a
    non-zero exit code when the section is missing or empty.

.EXAMPLE
    pwsh .github/scripts/Get-ChangelogSection.ps1 -Version 0.1.0
#>
param(
    [Parameter(Mandatory)][ValidatePattern('^\d+\.\d+\.\d+$')][string]$Version,
    [string]$Changelog = (Join-Path (Split-Path (Split-Path $PSScriptRoot)) 'CHANGELOG.md')
)
Set-StrictMode -Version 3.0
$ErrorActionPreference = 'Stop'

$prefix = "## $Version - "
$body = [System.Collections.Generic.List[string]]::new()
$inside = $false
$found = $false
foreach ($line in [System.IO.File]::ReadAllLines([System.IO.Path]::GetFullPath($Changelog, (Get-Location).Path))) {
    if ($line.StartsWith('## ')) {
        if ($inside) { break }
        if ($line.StartsWith($prefix, [System.StringComparison]::Ordinal)) { $inside = $true; $found = $true }
        continue
    }
    if ($inside) { $body.Add($line) }
}
if (-not $found) { throw "CHANGELOG.md has no section '## $Version - '" }
$text = ($body -join "`n").Trim()
if (-not $text) { throw "The section of $Version in CHANGELOG.md is empty" }
$text
