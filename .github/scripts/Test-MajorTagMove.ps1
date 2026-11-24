#Requires -Version 7.6
<#
.SYNOPSIS
    Says whether the moving major tag (v1) may be moved to a release: not when a greater version of the same major already
    has a tag, since releasing 1.2.1 after 1.3.0 would move v1 backwards. Run by .github/workflows/release.yml, and by
    tests/Test-ReleaseNotes.ps1.

.DESCRIPTION
    -Tags are the existing tag names (v1.3.0 and the like; anything that is not v<n>.<n>.<n> is ignored). -MajorTag is the
    tag to move (v<major of -Version> when empty); versions up to its major count: a v2.0.0 tag does not hold v1 back, and a
    0.x release that moves v1 is held back by v1.0.0, so games pinned to @v1 never go back to 0.x. The version itself being tagged already is fine
    (a run repeated to move the major tag). Prints one line of JSON: {"move": true|false, "reason": "..."}.

.EXAMPLE
    pwsh .github/scripts/Test-MajorTagMove.ps1 -Version 1.2.1 -Tags v1.2.0, v1.3.0
#>
param(
    [Parameter(Mandatory)][ValidatePattern('\A[0-9]+\.[0-9]+\.[0-9]+\z')][string]$Version,
    [string[]]$Tags = @(),
    [string]$MajorTag
)
Set-StrictMode -Version 3.0
$ErrorActionPreference = 'Stop'

$new = [version]$Version
if (-not $MajorTag) { $MajorTag = "v$($new.Major)" }
if ($MajorTag -notmatch '\Av([0-9]+)\z') { throw "-MajorTag '$MajorTag' is not v<number>" }
$majorNumber = [int]$Matches[1]
# (-File hands a comma list over as one string.)
$Tags = @($Tags | ForEach-Object { $_ -split ',' } | Where-Object { $_ })
$greater = [System.Collections.Generic.List[string]]::new()
foreach ($tag in $Tags) {
    if ($tag -notmatch '\Av([0-9]+\.[0-9]+\.[0-9]+)\z') { continue }
    $existing = [version]$Matches[1]
    if ($existing.Major -le $majorNumber -and $existing -gt $new) { $greater.Add($tag) }
}
$move = $greater.Count -eq 0
$reason = if ($move) { "no tag of a greater version up to $MajorTag exists" } else { "$($greater -join ', ') is greater than v$Version" }
ConvertTo-Json -Compress -Depth 3 -InputObject ([ordered]@{ move = $move; reason = $reason })
