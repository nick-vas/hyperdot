#!/usr/bin/env pwsh
# Self-test of .github/scripts/Update-ReleasePr.ps1, the release pull request of .github/workflows/release-pr.yml, in a
# temporary repository with a bare origin and a stand-in `gh` that logs its calls: the next version from the fragments
# (minor for Added, Removed or Deprecated, patch for Changed, Fixed or Security alone, or -Version), release/next pushed with the assembled CHANGELOG.md and no
# fragments while main keeps them, the pull request opened, or the open one updated after a force push, closed when no
# fragments are left, nothing done for a commit main has moved past, a refused pull request named with the setting that
# allows it, and a malformed version refused. And Update-Changelog.ps1 -Next. Needs git; the stand-in gh needs Linux or macOS.
Set-StrictMode -Version 3.0
$ErrorActionPreference = 'Stop'
$root = Split-Path $PSScriptRoot
$failures = @()
function Assert-True([bool]$Condition, [string]$Name) {
    if ($Condition) { Write-Host "ok     $Name" } else { Write-Host "FAIL   $Name"; $script:failures += $Name }
}
if ($IsWindows) { Write-Host 'skipped: the stand-in gh is a shell script'; exit 0 }

$base = Join-Path ([System.IO.Path]::GetTempPath()) "release-pr-$([guid]::NewGuid().ToString('n').Substring(0, 8))"
New-Item -ItemType Directory -Force $base | Out-Null
$bin = Join-Path $base 'bin'
New-Item -ItemType Directory -Force $bin | Out-Null
# The stand-in gh: logs each call (and the body file it was given), answers `pr list` with FAKE_PR and `pr create` with
# FAKE_CREATE_EXIT.
Set-Content -LiteralPath (Join-Path $bin 'gh') -Value @'
#!/bin/sh
echo "gh $*" >> "$GH_LOG"
prev=''
for a in "$@"; do
  if [ "$prev" = '--body-file' ]; then cat "$a" >> "$GH_LOG.body"; fi
  prev="$a"
done
case "$1 $2" in
  'pr list') [ -n "$FAKE_PR" ] && echo "$FAKE_PR"; exit 0 ;;
  'pr create') [ "${FAKE_CREATE_EXIT:-0}" != 0 ] && { echo 'pull request create failed: GitHub Actions is not permitted to create or approve pull requests' >&2; exit "$FAKE_CREATE_EXIT"; }; echo 'https://github.com/o/r/pull/9'; exit 0 ;;
esac
exit 0
'@
& chmod +x (Join-Path $bin 'gh')
$savedPath = $env:PATH
$env:PATH = "$bin$([IO.Path]::PathSeparator)$savedPath"
$n = 0

function Invoke-Git([string]$Dir, [string[]]$GitArgs) {
    $out = & git -C $Dir -c user.name=t -c user.email=t@example.com @GitArgs 2>&1 | Out-String
    if ($LASTEXITCODE -ne 0) { throw "git $($GitArgs -join ' ') failed: $out" }
    return $out.Trim()
}
# A repository with the release tools, a released 0.1.0, the given fragments and a bare origin, on main.
function New-Work([hashtable]$Fragments) {
    $script:n++
    $dir = Join-Path $base "w$($script:n)"
    $origin = Join-Path $base "o$($script:n).git"
    & git init --quiet --bare -b main $origin
    New-Item -ItemType Directory -Force (Join-Path $dir 'changelog.d'), (Join-Path $dir 'ci/godot/tools'), (Join-Path $dir '.github/scripts') | Out-Null
    Copy-Item -LiteralPath (Join-Path $root 'ci/godot/tools/Update-Changelog.ps1') -Destination (Join-Path $dir 'ci/godot/tools')
    foreach ($s in 'Get-ChangelogSection.ps1', 'Update-ReleasePr.ps1') { Copy-Item -LiteralPath (Join-Path $root ".github/scripts/$s") -Destination (Join-Path $dir '.github/scripts') }
    Set-Content -LiteralPath (Join-Path $dir 'CHANGELOG.md') "# Changelog`n`n## Unreleased`n`n## 0.1.0 - 2026-10-27`n- First.`n" -NoNewline
    Set-Content -LiteralPath (Join-Path $dir 'changelog.d/README.md') 'not a fragment'
    foreach ($k in $Fragments.Keys) { Set-Content -LiteralPath (Join-Path $dir "changelog.d/$k.md") $Fragments[$k] }
    & git init --quiet -b main $dir
    Invoke-Git $dir @('add', '-A') | Out-Null
    Invoke-Git $dir @('commit', '--quiet', '-m', 'start') | Out-Null
    Invoke-Git $dir @('remote', 'add', 'origin', $origin) | Out-Null
    Invoke-Git $dir @('push', '--quiet', 'origin', 'main') | Out-Null
    return [pscustomobject]@{ Dir = $dir; Origin = $origin }
}
function Invoke-ReleasePr($Work, [string[]]$ToolArgs, [hashtable]$Env = @{}) {
    $log = Join-Path $base "gh-$($script:n)-$([guid]::NewGuid().ToString('n').Substring(0, 6)).log"
    $env:GH_LOG = $log
    foreach ($k in 'FAKE_PR', 'FAKE_CREATE_EXIT') { [Environment]::SetEnvironmentVariable($k, $null) }
    foreach ($k in $Env.Keys) { [Environment]::SetEnvironmentVariable($k, $Env[$k]) }
    $out = & pwsh -NoProfile -NonInteractive -File (Join-Path $Work.Dir '.github/scripts/Update-ReleasePr.ps1') -Root $Work.Dir @ToolArgs 2>&1 | Out-String
    $code = $LASTEXITCODE
    $calls = if (Test-Path -LiteralPath $log) { Get-Content -Raw -LiteralPath $log } else { '' }
    $body = if (Test-Path -LiteralPath "$log.body") { Get-Content -Raw -LiteralPath "$log.body" } else { '' }
    return [pscustomobject]@{ Code = $code; Out = $out; Calls = $calls; Body = $body }
}
function Get-Remote($Work, [string]$Ref, [string]$Path) { return (& git -C $Work.Origin show "$($Ref):$Path" 2>$null) -join "`n" }

try {
    # Update-Changelog.ps1 -Next: minor for Added, Removed or Deprecated, patch for Changed, Fixed or Security alone, nothing without fragments.
    $tool = Join-Path $root 'ci/godot/tools/Update-Changelog.ps1'
    $w = New-Work @{ 'a-new' = 'Added: a thing'; 'b-fix' = 'Fixed: a bug' }
    Assert-True ((& pwsh -NoProfile -NonInteractive -File $tool -Next -Root $w.Dir | Out-String).Trim() -eq '0.2.0') '-Next: an Added fragment raises the minor'
    $p = New-Work @{ 'b-fix' = 'Fixed: a bug'; 'c-sec' = 'Security: a hole' }
    Assert-True ((& pwsh -NoProfile -NonInteractive -File $tool -Next -Root $p.Dir | Out-String).Trim() -eq '0.1.1') '-Next: Fixed and Security alone raise the patch'
    $ch = New-Work @{ 'b-fix' = 'Fixed: a bug'; 'c-tweak' = 'Changed: a recheck' }
    Assert-True ((& pwsh -NoProfile -NonInteractive -File $tool -Next -Root $ch.Dir | Out-String).Trim() -eq '0.1.1') '-Next: Changed raises only the patch'
    foreach ($kind in 'Removed', 'Deprecated') {
        $k = New-Work @{ 'b-fix' = 'Fixed: a bug'; 'c-kind' = "${kind}: a flag" }
        Assert-True ((& pwsh -NoProfile -NonInteractive -File $tool -Next -Root $k.Dir | Out-String).Trim() -eq '0.2.0') "-Next: $kind raises the minor"
    }
    $e = New-Work @{}
    Assert-True ((& pwsh -NoProfile -NonInteractive -File $tool -Next -Root $e.Dir | Out-String).Trim() -eq '') '-Next: no fragments, no version'

    # The first run opens the pull request; main keeps its fragments, release/next has the section.
    $r = Invoke-ReleasePr $w @()
    $log = Get-Remote $w 'release/next' 'CHANGELOG.md'
    Assert-True ($r.Code -eq 0 -and $log -match '(?m)^## 0\.2\.0 - \d{4}-\d{2}-\d{2}$' -and $log -match '### Added\n- a thing' -and $log -match '### Fixed\n- a bug') "release/next holds the 0.2.0 section: $($r.Out.Trim())"
    $files = (& git -C $w.Origin ls-tree --name-only 'release/next' 'changelog.d/') -join ' '
    Assert-True ($files -eq 'changelog.d/README.md' -and (Get-Remote $w 'main' 'changelog.d/a-new.md') -eq 'Added: a thing') "release/next has no fragments, main keeps them ($files)"
    $author = (& git -C $w.Origin log -1 --format='%an|%s' 'release/next')
    Assert-True ($author -eq 'github-actions[bot]|Release 0.2.0') "the commit is the bot's 'Release 0.2.0' ($author)"
    Assert-True ($r.Calls -match 'gh pr create --base main --head release/next --title Release 0\.2\.0' -and $r.Body -match '(?s)Merging this releases \*\*0\.2\.0\*\*.*2 changelog fragment.*### Added\n- a thing') "the pull request is opened with the notes: $($r.Calls.Trim())"

    # A later green push: the open pull request is updated, the branch rebuilt from the new main (a force push).
    Set-Content -LiteralPath (Join-Path $w.Dir 'changelog.d/d-more.md') 'Changed: more'
    Invoke-Git $w.Dir @('checkout', '--quiet', 'main') | Out-Null
    Invoke-Git $w.Dir @('add', '-A') | Out-Null
    Invoke-Git $w.Dir @('commit', '--quiet', '-m', 'more') | Out-Null
    Invoke-Git $w.Dir @('push', '--quiet', 'origin', 'main') | Out-Null
    $r = Invoke-ReleasePr $w @() @{ FAKE_PR = '7' }
    Assert-True ($r.Code -eq 0 -and $r.Calls -match 'gh pr edit 7 --title Release 0\.2\.0' -and $r.Calls -notmatch 'pr create' -and (Get-Remote $w 'release/next' 'CHANGELOG.md') -match '### Changed\n- more') "the open pull request is updated after a force push: $($r.Out.Trim())"

    # A run for a commit main has moved past does nothing: that commit's own run comes next.
    $r = Invoke-ReleasePr $w @('-ExpectSha', '0000000000000000000000000000000000000000') @{ FAKE_PR = '7' }
    Assert-True ($r.Code -eq 0 -and -not $r.Calls -and $r.Out -match 'moved on') 'a commit main has moved past changes nothing'

    # Fixed alone gives a patch; -Version chooses another.
    $r = Invoke-ReleasePr $p @()
    Assert-True ($r.Code -eq 0 -and $r.Calls -match 'Release 0\.1\.1') 'a pull request of fixes alone is 0.1.1'
    $q = New-Work @{ 'a-new' = 'Added: a thing' }
    $r = Invoke-ReleasePr $q @('-Version', '1.0.0')
    Assert-True ($r.Code -eq 0 -and $r.Calls -match 'Release 1\.0\.0' -and (Get-Remote $q 'release/next' 'CHANGELOG.md') -match '(?m)^## 1\.0\.0 - ') '-Version chooses the version'
    $r = Invoke-ReleasePr (New-Work @{ 'a-new' = 'Added: a thing' }) @('-Version', 'v1')
    Assert-True ($r.Code -ne 0 -and $r.Out -match 'not <major>\.<minor>\.<patch>' -and $r.Calls -notmatch 'pr create') 'a malformed version is refused before anything is pushed'

    # No fragments left (the release pull request was merged): an open one is closed, otherwise nothing happens.
    $r = Invoke-ReleasePr $e @() @{ FAKE_PR = '7' }
    Assert-True ($r.Code -eq 0 -and $r.Calls -match 'gh pr close 7 --delete-branch') 'with no fragments the open release pull request is closed'
    $r = Invoke-ReleasePr $e @()
    $branches = (& git -C $e.Origin branch --format='%(refname:short)') -join ' '
    Assert-True ($r.Code -eq 0 -and $r.Calls -notmatch 'pr (create|edit|close)' -and $branches -eq 'main') "with no fragments and no pull request nothing happens ($branches)"

    # -Version with no fragments left: nothing to release, the open pull request is closed (not a failed empty commit).
    $r = Invoke-ReleasePr $e @('-Version', '1.0.0') @{ FAKE_PR = '7' }
    Assert-True ($r.Code -eq 0 -and $r.Calls -match 'gh pr close 7' -and $r.Calls -notmatch 'pr (create|edit)') "-Version with no fragments closes, not fails: $($r.Out.Trim())"

    # Get-PendingRelease.ps1, what release.yml releases after Self-test: the highest untagged section, only from the commit
    # that added it.
    $pending = Join-Path $root '.github/scripts/Get-PendingRelease.ps1'
    function Get-Pending($Work, [string]$Sha) {
        Push-Location -LiteralPath $Work.Dir
        try { $out = & pwsh -NoProfile -NonInteractive -File $pending -Sha $Sha 2>&1 | Out-String } finally { Pop-Location }
        if ($LASTEXITCODE -ne 0) { return [pscustomobject]@{ release = $null; version = ''; reason = $out } }
        return $out | ConvertFrom-Json
    }
    $g = New-Work @{ 'a-new' = 'Added: a thing' }
    Invoke-Git $g.Dir @('tag', 'v0.1.0') | Out-Null
    Invoke-Git $g.Dir @('push', '--quiet', 'origin', 'v0.1.0') | Out-Null
    $start = Invoke-Git $g.Dir @('rev-parse', 'HEAD')
    $d = Get-Pending $g $start
    Assert-True ($d.release -eq $false -and $d.reason -match 'v0\.1\.0 is already released') "a released section is not released again: $($d.reason)"
    & pwsh -NoProfile -NonInteractive -File (Join-Path $g.Dir 'ci/godot/tools/Update-Changelog.ps1') -Version 0.2.0 -Root $g.Dir | Out-Null
    Invoke-Git $g.Dir @('add', '-A') | Out-Null
    Invoke-Git $g.Dir @('commit', '--quiet', '-m', 'Release 0.2.0') | Out-Null
    $merge = Invoke-Git $g.Dir @('rev-parse', 'HEAD')
    Set-Content -LiteralPath (Join-Path $g.Dir 'later.txt') 'later'
    Invoke-Git $g.Dir @('add', '-A') | Out-Null
    Invoke-Git $g.Dir @('commit', '--quiet', '-m', 'later') | Out-Null
    $later = Invoke-Git $g.Dir @('rev-parse', 'HEAD')
    $d = Get-Pending $g $merge
    Assert-True ($d.release -eq $true -and $d.version -eq '0.2.0' -and $d.sha -eq $merge) "the commit that added 0.2.0 releases it: $($d.reason)"
    $d = Get-Pending $g $later
    Assert-True ($d.release -eq $false -and $d.reason -match [regex]::Escape($merge)) "a later commit whose run ends first does not take the tag: $($d.reason)"
    Invoke-Git $g.Dir @('tag', 'v0.2.0', $merge) | Out-Null
    Invoke-Git $g.Dir @('push', '--quiet', 'origin', 'v0.2.0') | Out-Null
    $d = Get-Pending $g $merge
    Assert-True ($d.release -eq $false -and $d.reason -match 'already released') 'once tagged, a repeated run releases nothing'
    $d = Get-Pending $g 'HEAD'
    Assert-True ($null -eq $d.release) 'a commit that is not a full SHA is refused'
    # The release pull request merged with a merge commit: the merge, the commit on main, releases.
    $h = New-Work @{ 'a-new' = 'Added: a thing' }
    Invoke-Git $h.Dir @('checkout', '--quiet', '-b', 'release/next') | Out-Null
    & pwsh -NoProfile -NonInteractive -File (Join-Path $h.Dir 'ci/godot/tools/Update-Changelog.ps1') -Version 0.2.0 -Root $h.Dir | Out-Null
    Invoke-Git $h.Dir @('add', '-A') | Out-Null
    Invoke-Git $h.Dir @('commit', '--quiet', '-m', 'Release 0.2.0') | Out-Null
    Invoke-Git $h.Dir @('checkout', '--quiet', 'main') | Out-Null
    Set-Content -LiteralPath (Join-Path $h.Dir 'other.txt') 'other'
    Invoke-Git $h.Dir @('add', '-A') | Out-Null
    Invoke-Git $h.Dir @('commit', '--quiet', '-m', 'other') | Out-Null
    Invoke-Git $h.Dir @('merge', '--quiet', '--no-ff', '-m', 'Merge release/next', 'release/next') | Out-Null
    $mergeCommit = Invoke-Git $h.Dir @('rev-parse', 'HEAD')
    $d = Get-Pending $h $mergeCommit
    Assert-True ($d.release -eq $true -and $d.version -eq '0.2.0') "a merge commit of the release pull request releases it: $($d.reason)"

    # A repository that does not let workflows open pull requests: the setting is named.
    $r = Invoke-ReleasePr (New-Work @{ 'a-new' = 'Added: a thing' }) @() @{ FAKE_CREATE_EXIT = '1' }
    Assert-True ($r.Code -ne 0 -and $r.Out -match 'Allow GitHub Actions to create and approve pull requests') 'a refused pull request names the setting that allows it'
} finally {
    $env:PATH = $savedPath
    foreach ($k in 'GH_LOG', 'FAKE_PR', 'FAKE_CREATE_EXIT') { [Environment]::SetEnvironmentVariable($k, $null) }
    Remove-Item -LiteralPath $base -Recurse -Force -ErrorAction SilentlyContinue
}

if ($failures.Count) { Write-Host "`n$($failures.Count) failed"; exit 1 }
Write-Host "`nRelease pull request self-test passed"
exit 0
