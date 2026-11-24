#!/usr/bin/env pwsh
<#
.SYNOPSIS
    Opens or updates the release pull request: the branch release/next holds main with the changelog.d/ fragments
    assembled into a new CHANGELOG.md section. Run by .github/workflows/release-pr.yml after each green push to main, and
    by tests/Test-ReleasePr.ps1 against a stand-in gh.

.DESCRIPTION
    The version is -Version, or the next one Update-Changelog.ps1 -Next works out from the fragments. The branch is rebuilt
    from the checked-out commit each time and force-pushed (it is the workflow's own branch), and the open pull request
    from it gets the new title and notes; without one, one is opened. With no fragments left (the release pull request was
    merged, or there was nothing to release) an open release pull request is closed. Merging it releases the version:
    release.yml tags the newest changelog section that has no tag once Self-test passes on main.

    -ExpectSha is the commit whose Self-test run started this; when the checkout is a newer commit, nothing is done, since
    that commit's own run comes next.

.EXAMPLE
    pwsh .github/scripts/Update-ReleasePr.ps1 -ExpectSha $sha
#>
param(
    [string]$Version,
    [string]$ExpectSha,
    [string]$Branch = 'release/next',
    [string]$Base = 'main',
    [string]$Root = (Split-Path (Split-Path $PSScriptRoot))
)
Set-StrictMode -Version 3.0
$ErrorActionPreference = 'Stop'

function Invoke-Native([string]$What, [scriptblock]$Command) {
    $out = & $Command
    if ($LASTEXITCODE -ne 0) { throw "$What failed (exit code $LASTEXITCODE)" }
    return $out
}
$Root = (Resolve-Path -LiteralPath $Root).Path
Set-Location -LiteralPath $Root
$changelogTool = Join-Path $Root 'ci/godot/tools/Update-Changelog.ps1'
$sectionTool = Join-Path $Root '.github/scripts/Get-ChangelogSection.ps1'

$head = "$(Invoke-Native 'git rev-parse' { git rev-parse HEAD })".Trim()
if ($ExpectSha -and $head -ne $ExpectSha) {
    Write-Host "::notice::$Base moved on from $ExpectSha to $head; the Self-test run of $head updates the release pull request"
    exit 0
}

$count = @(Get-ChildItem -LiteralPath (Join-Path $Root 'changelog.d') -File | Where-Object { $_.Name -notin 'README.md', '.gitkeep' }).Count
$number = @(Invoke-Native 'gh pr list' { gh pr list --head $Branch --base $Base --state open --json number --jq '.[].number' }) |
    Where-Object { "$_".Trim() } | Select-Object -First 1
if ($count -and -not $Version) { $Version = "$(Invoke-Native 'Update-Changelog.ps1 -Next' { pwsh -NoProfile -NonInteractive -File $changelogTool -Next -Root $Root })".Trim() }
# Without fragments there is nothing to release, whatever version was asked for.
if (-not $count) {
    if ($number) {
        Invoke-Native 'gh pr close' { gh pr close "$number" --delete-branch --comment 'No changelog fragments are left on main: nothing to release.' } | Out-Null
        Write-Host "No changelog fragments: closed the release pull request #$number"
    } else {
        Write-Host 'No changelog fragments: nothing to release'
    }
    exit 0
}
if ($Version -notmatch '\A[0-9]+\.[0-9]+\.[0-9]+\z') { throw "version '$Version' is not <major>.<minor>.<patch>" }

Invoke-Native 'git checkout' { git checkout --quiet -B "$Branch" } | Out-Null
Invoke-Native 'Update-Changelog.ps1' { pwsh -NoProfile -NonInteractive -File $changelogTool -Version $Version -Root $Root } | Out-Null
Invoke-Native 'git add' { git add -A -- CHANGELOG.md changelog.d } | Out-Null
Invoke-Native 'git commit' { git -c 'user.name=github-actions[bot]' -c 'user.email=41898282+github-actions[bot]@users.noreply.github.com' commit --quiet -m "Release $Version" } | Out-Null
Invoke-Native 'git push' { git push --quiet --force origin "HEAD:refs/heads/$Branch" } | Out-Null

$notes = (Invoke-Native 'Get-ChangelogSection.ps1' { pwsh -NoProfile -NonInteractive -File $sectionTool -Version $Version -Changelog (Join-Path $Root 'CHANGELOG.md') }) -join "`n"
$intro = @"
Merging this releases **$Version**. Once Self-test passes on $Base, the Release workflow tags ``v$Version``, moves the major tag games pin and publishes the notes below.

This branch is rebuilt from $Base ($($head.Substring(0, 7))) after every green push, from its $count changelog fragment(s); change the fragments on $Base, not here. The version follows the fragments: the minor goes up for Added, Changed, Removed or Deprecated, the patch for Fixed or Security alone. For another version, run the Release PR workflow by hand with that version.

---

"@
# A pull request body holds at most 65536 characters.
$body = $intro + $notes
if ($body.Length -gt 60000) { $cut = $body.Substring(0, 60000); $body = $cut.Substring(0, $cut.LastIndexOf("`n")) + "`n`n(Cut here: the whole section is in CHANGELOG.md on this branch.)" }
$bodyFile = Join-Path ([System.IO.Path]::GetTempPath()) "release-pr-$([guid]::NewGuid().ToString('n').Substring(0, 8)).md"
[System.IO.File]::WriteAllText($bodyFile, $body, [System.Text.UTF8Encoding]::new($false))
try {
    if ($number) {
        Invoke-Native 'gh pr edit' { gh pr edit "$number" --title "Release $Version" --body-file $bodyFile } | Out-Null
        Write-Host "Updated the release pull request #$number to $Version ($count fragments)"
    } else {
        $url = & gh pr create --base $Base --head $Branch --title "Release $Version" --body-file $bodyFile
        if ($LASTEXITCODE -ne 0) {
            $message = "Could not open the release pull request (gh exit code $LASTEXITCODE). If the repository does not let workflows open pull requests, allow it: Settings > Actions > General > Workflow permissions > 'Allow GitHub Actions to create and approve pull requests'. The branch $Branch is pushed; it can also be opened by hand."
            # On one line as an annotation of the run: the error view wraps a thrown message at the console width.
            Write-Host "::error::$message"
            throw $message
        }
        Write-Host "Opened the release pull request for $Version ($count fragments): $url"
    }
} finally {
    Remove-Item -LiteralPath $bodyFile -Force
}
exit 0
