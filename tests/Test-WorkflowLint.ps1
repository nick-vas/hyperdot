#!/usr/bin/env pwsh
# Static checks of the workflows (they cannot run here): the YAML is read as text and each property below must hold.
#   self-test.yml   a pull request's concurrency group is its number, not its branch name (two forks can share a branch name)
#   godot.yml       `release` with no export preset fails loudly, and the release job needs a successful export
#   canary.yml      the job that runs upstream code has no write permission, no token and no stored credentials; the job that
#                   has them runs none of that code
#   release.yml     the version and the major tag are matched whole (\A..\z: `$` accepts a trailing newline, \d Unicode digits)
#                   and the major tag is moved by Test-MajorTagMove.ps1
#   token-benchmark.yml  -MaxMinutes is always set, by Get-BenchmarkMinutes.ps1
# It also lists, without failing, what is not pinned in a job that holds a Claude token (docs/roadmap.md, "To do").
# Needs no Godot.
Set-StrictMode -Version 3.0
$ErrorActionPreference = 'Stop'
$root = Split-Path $PSScriptRoot
$failures = [System.Collections.Generic.List[string]]::new()
function Assert-True([bool]$Condition, [string]$Message) {
    if ($Condition) { Write-Host "ok   $Message" } else { $failures.Add($Message); Write-Host "FAIL $Message" -ForegroundColor Red }
}
function Get-Workflow([string]$Name) {
    # Comments dropped, so a note about a thing is not the thing.
    $lines = [System.IO.File]::ReadAllLines((Join-Path $root ".github/workflows/$Name"))
    return ($lines | Where-Object { $_ -notmatch '^\s*#' }) -join "`n"
}
# job id -> the text of the job (two-space indent under `jobs:`).
function Get-JobBlocks([string]$Text) {
    $jobs = [ordered]@{}
    $body = $Text.Substring($Text.IndexOf("`njobs:") + 6)
    foreach ($block in [regex]::Split($body, '(?m)^  (?=[A-Za-z_][A-Za-z0-9_-]*:\s*$)')) {
        if (-not $block.Trim()) { continue }
        $jobs[($block -split ':', 2)[0]] = $block
    }
    return $jobs
}

# self-test.yml
$selfTest = Get-Workflow 'self-test.yml'
$group = [regex]::Match($selfTest, '(?m)^  group: (.+)$').Groups[1].Value
Assert-True ($group -match 'pull_request\.number' -and $group -notmatch 'head_ref') "a pull request's concurrency group is its number, not its branch name ($group)"

# godot.yml
$godot = Get-Workflow 'godot.yml'
$godotJobs = Get-JobBlocks $godot
Assert-True ($godotJobs['release'] -match "(?m)^    if: .*needs\.export\.result == 'success'") 'the release job needs a successful export'
Assert-True ($godotJobs['test'] -match '(?s)RELEASE: \$\{\{ inputs\.release \}\}.*\$env:RELEASE -eq .true. -and \$presets\.Count -eq 0.*exit 1') 'release with no export preset fails the test job with a message'

# canary.yml
$canary = Get-Workflow 'canary.yml'
$canaryJobs = Get-JobBlocks $canary
$running = @($canaryJobs.Keys | Where-Object { $canaryJobs[$_] -match 'Invoke-Canary\.ps1' })
Assert-True ($running.Count -eq 1) "exactly one canary job runs the upstream code ($($running -join ', '))"
foreach ($job in $running) {
    $block = $canaryJobs[$job]
    Assert-True ($block -match '(?m)^    permissions:\s*\n      contents: read\s*$' -and $block -notmatch ': write') "the job $job that runs upstream code has read permission only"
    Assert-True ($block -notmatch 'GH_TOKEN|GITHUB_TOKEN|secrets\.|github\.token') "the job $job has no token in its environment or steps"
    Assert-True ($block -match 'persist-credentials: false') "the job $job leaves no credentials in its checkout"
}
Assert-True ($canary -notmatch '(?m)^  (contents|pull-requests|issues): write') 'the workflow grants no write permission to every job'
foreach ($job in @($canaryJobs.Keys | Where-Object { $_ -notin $running })) {
    $block = $canaryJobs[$job]
    Assert-True ($block -notmatch '(?i)\b(dotnet|uvx|pipx|npm|pip|Invoke-Canary|Update-Versions|Update-AddonStatus)\b') "the job $job that has the write token runs no upstream code"
    Assert-True ($block -match 'needs: ' -and $block -match '(?m)^      contents: write') "the job $job needs the one that tried and holds the write permissions"
}

# release.yml and the scripts it runs
$release = Get-Workflow 'release.yml'
Assert-True ($release -match [regex]::Escape('\A[0-9]+\.[0-9]+\.[0-9]+\z') -and $release -match [regex]::Escape('\Av[0-9]+\z')) 'release.yml matches the version and the major tag whole, ASCII digits only'
Assert-True ($release -notmatch [regex]::Escape('^\d+\.\d+\.\d+$') -and $release -notmatch [regex]::Escape('^v\d+$')) 'release.yml has no ^..$ / \d match of a version'
Assert-True ($release -match 'Test-MajorTagMove\.ps1') 'release.yml asks Test-MajorTagMove.ps1 before moving the major tag'
$leftovers = [System.Collections.Generic.List[string]]::new()
foreach ($file in @(& git -C $root ls-files -z '*.ps1' '*.yml') -join '' -split [char]0) {
    if (-not $file -or $file -eq 'tests/Test-WorkflowLint.ps1' -or $file -eq 'tests/Test-ReleaseNotes.ps1') { continue }
    if ((Get-Content -LiteralPath (Join-Path $root $file) -Raw) -match [regex]::Escape("'^\d+\.\d+\.\d+") + '(\(|\$)') { $leftovers.Add($file) }
}
Assert-True ($leftovers.Count -eq 0) "no version is matched with ^\d+\.\d+\.\d+ (accepts a trailing newline and Unicode digits): $($leftovers -join ', ')"

# token-benchmark.yml
$benchmark = Get-Workflow 'token-benchmark.yml'
Assert-True ($benchmark -match 'Get-BenchmarkMinutes\.ps1' -and $benchmark -notmatch 'if \(\$minutes -gt 0\)') '-MaxMinutes is always set, by Get-BenchmarkMinutes.ps1'

# The Claude Code CLI and uv are installed at a version, in every job that holds a Claude token (Update-Versions.ps1 keeps them current).
foreach ($name in 'evals.yml', 'token-benchmark.yml', 'canary.yml') {
    $text = Get-Workflow $name
    $unpinned = @([regex]::Matches($text, '(?m)npm install -g @anthropic-ai/claude-code(?!@[0-9]+\.[0-9]+\.[0-9]+\b)|pipx install uv(?!==[0-9]+\.[0-9]+\.[0-9]+\b)') | ForEach-Object { $_.Value })
    Assert-True ($unpinned.Count -eq 0) "$name installs the Claude Code CLI and uv at a version (found unpinned: $($unpinned -join '; '))"
}
$pinned = (Get-Workflow 'evals.yml') + (Get-Workflow 'token-benchmark.yml') + (Get-Workflow 'canary.yml')
Assert-True ([regex]::Matches($pinned, 'npm install -g @anthropic-ai/claude-code@').Count -eq 3 -and [regex]::Matches($pinned, 'pipx install uv==').Count -eq 1) 'the three CLI installs and the uv install are all there to be checked'

# Every action from another repository is pinned to a commit (a tag can be moved), with its version in a comment so a person
# and Dependabot (.github/dependabot.yml) can read it. Local actions and reusable workflows (./...) are this repository's own.
$unpinnedActions = @(foreach ($file in @(Get-ChildItem -LiteralPath (Join-Path $root '.github/workflows') -Filter '*.yml') + @(Get-ChildItem -LiteralPath (Join-Path $root '.github/actions') -Recurse -Filter 'action.yml')) {
    foreach ($line in Get-Content -LiteralPath $file.FullName) {
        if ($line -match '^\s*(?:-\s*)?uses:\s*(?<ref>\S+)' -and $Matches['ref'] -notlike './*' -and $Matches['ref'] -notmatch '@[0-9a-f]{40}\z') { "$($file.Name): $($Matches['ref'])" }
    }
})
Assert-True ($unpinnedActions.Count -eq 0) "every action from another repository is pinned to a commit SHA (found: $($unpinnedActions -join '; '))"
$pinnedActions = @(foreach ($file in Get-ChildItem -LiteralPath (Join-Path $root '.github/workflows') -Filter '*.yml') { Select-String -LiteralPath $file.FullName -Pattern '^\s*(?:-\s*)?uses:\s*\S+@[0-9a-f]{40} # v\d+' })
Assert-True ($pinnedActions.Count -gt 20) "the pinned actions each carry their version in a comment ($($pinnedActions.Count) found in the workflows)"

if ($failures.Count) { Write-Host "`n$($failures.Count) failed" -ForegroundColor Red; exit 1 }
Write-Host "`nAll passed"
