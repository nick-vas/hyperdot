#!/usr/bin/env pwsh
# Self-test of the input hash of docs/ci-cache.md (stage 0): .github/scripts/Select-Jobs.ps1 -Inputs, Get-InputHash.ps1 and
# Write-CacheObservations.ps1. A small repository is made in a temporary folder from the real workflow and scripts: a change
# moves the hash of exactly the jobs that read the file, a docs-only commit moves lint's alone, and the observations say
# what to record. No Godot.
Set-StrictMode -Version 3.0
$ErrorActionPreference = 'Stop'
$root = Split-Path $PSScriptRoot
$failures = [System.Collections.Generic.List[string]]::new()
function Assert-True([bool]$Condition, [string]$Message) {
    if ($Condition) { Write-Host "ok   $Message" } else { $failures.Add($Message); Write-Host "FAIL $Message" -ForegroundColor Red }
}

$temp = Join-Path ([IO.Path]::GetTempPath()) "inputhash-$([guid]::NewGuid().ToString('N').Substring(0, 8))"
$repo = Join-Path $temp 'repo'
try {
    New-Item -ItemType Directory -Force (Join-Path $repo '.github/workflows'), (Join-Path $repo 'benchmark'), (Join-Path $repo 'tests'), (Join-Path $repo 'ci/godot/lib'), (Join-Path $repo 'docs') | Out-Null
    Copy-Item -LiteralPath (Join-Path $root '.github/workflows/self-test.yml') -Destination (Join-Path $repo '.github/workflows')
    Copy-Item -LiteralPath (Join-Path $root '.github/scripts') -Destination (Join-Path $repo '.github/scripts') -Recurse
    Copy-Item -LiteralPath (Join-Path $root 'benchmark/game-programme.json') -Destination (Join-Path $repo 'benchmark')
    Copy-Item -LiteralPath (Join-Path $root 'tests/Test-SelectJobs.ps1') -Destination (Join-Path $repo 'tests')
    Set-Content -LiteralPath (Join-Path $repo 'ci/godot/lib/Web.ps1') -Value '# web'
    Set-Content -LiteralPath (Join-Path $repo 'benchmark/Invoke-Thing.ps1') -Value '# benchmark'
    Set-Content -LiteralPath (Join-Path $repo 'docs/notes.md') -Value 'notes'
    Set-Content -LiteralPath (Join-Path $repo 'file with space.txt') -Value 'unrelated'
    $git = { param([string[]]$GitArguments) & git -C $repo -c user.name=t -c user.email=t@example.com @GitArguments | Out-Null; if ($LASTEXITCODE) { throw "git $GitArguments failed" } }
    & $git @('init', '-q'); & $git @('add', '-A'); & $git @('commit', '-q', '-m', 'one')

    $inputs = (& pwsh -NoProfile -NonInteractive -File (Join-Path $repo '.github/scripts/Select-Jobs.ps1') -Root $repo -Inputs) -join "`n" | ConvertFrom-Json -AsHashtable
    Assert-True ('ci/godot/lib/Web.ps1' -in $inputs['web'] -and 'ci/godot/lib/Web.ps1' -notin $inputs['field-test'] -and 'benchmark/Invoke-Thing.ps1' -in $inputs['field-test'] -and 'benchmark/Invoke-Thing.ps1' -notin $inputs['zero-config']) 'a file is an input of exactly the jobs a change to it alone would run'
    Assert-True ('docs/notes.md' -notin $inputs['web'] -and @($inputs['measure'] | Where-Object { $_ -like 'docs/notes.md' }).Count -eq 0) 'documentation is an input of no job'
    Assert-True (@($inputs['zero-config'] | Where-Object { $_ -like '.github/workflows/self-test.yml' }).Count -eq 1) 'the workflow is an input of the shared jobs'

    function Get-Hashes([string]$EventName = 'pull_request', [string]$Runner = 'ubuntu24-1') {
        return (& pwsh -NoProfile -NonInteractive -File (Join-Path $repo '.github/scripts/Get-InputHash.ps1') -Root $repo -Json -EventName $EventName -Runner $Runner) -join "`n" | ConvertFrom-Json -AsHashtable
    }
    $jobs = @($inputs.Keys)
    $base = Get-Hashes
    Assert-True ($base.Count -eq $jobs.Count + 1 -and $base.ContainsKey('lint') -and @($base.Values | Where-Object { $_ -notmatch '^[0-9a-f]{32}$' }).Count -eq 0) "a hash of 32 hex characters for lint and each of the $($jobs.Count) gated jobs"
    # What the hash is made of, spelled out for lint (the job, the event, the runner image, the PowerShell version, the tree).
    $treeId = "$(& git -C $repo rev-parse 'HEAD^{tree}')".Trim()
    $text = "job=lint`nevent=pull_request`nrunner=ubuntu24-1`npwsh=$($PSVersionTable.PSVersion)`ntree=$treeId"
    $want = [System.BitConverter]::ToString([System.Security.Cryptography.SHA256]::HashData([System.Text.Encoding]::UTF8.GetBytes($text))).Replace('-', '').ToLowerInvariant().Substring(0, 32)
    Assert-True ($base['lint'] -eq $want) "lint's hash is the sha256 of its job, event, runner image, PowerShell version and tree ($($base['lint']) against $want)"
    $again = Get-Hashes
    Assert-True ((($base.Keys | ForEach-Object { "$_=$($base[$_])" }) -join ',') -eq (($again.Keys | ForEach-Object { "$_=$($again[$_])" }) -join ',')) 'the same commit gives the same hashes'
    function Get-Changed($Before, $After) { return @($Before.Keys | Where-Object { $Before[$_] -ne $After[$_] } | Sort-Object) }

    Add-Content -LiteralPath (Join-Path $repo 'docs/notes.md') -Value 'more notes'; & $git @('commit', '-q', '-am', 'docs')
    Assert-True (((Get-Changed $base (Get-Hashes)) -join ',') -eq 'lint') 'a documentation commit changes lint alone'

    $base = Get-Hashes
    Add-Content -LiteralPath (Join-Path $repo 'ci/godot/lib/Web.ps1') -Value '# changed'; & $git @('commit', '-q', '-am', 'web')
    $changed = Get-Changed $base (Get-Hashes)
    Assert-True ('web' -in $changed -and 'lint' -in $changed -and 'zero-config' -in $changed -and 'field-test' -notin $changed) "a lib the web job reads changes web, the kit's example jobs and lint, not the field test ($($changed -join ', '))"

    $base = Get-Hashes
    Add-Content -LiteralPath (Join-Path $repo 'benchmark/Invoke-Thing.ps1') -Value '# changed'; & $git @('commit', '-q', '-am', 'benchmark')
    $changed = Get-Changed $base (Get-Hashes)
    Assert-True ('field-test' -in $changed -and 'web' -notin $changed -and 'zero-config' -notin $changed -and 'lint' -in $changed) "a benchmark file changes the field test, the game benchmark and lint, not the example jobs ($($changed -join ', '))"

    $base = Get-Hashes
    Add-Content -LiteralPath (Join-Path $repo 'file with space.txt') -Value 'x'; & $git @('commit', '-q', '-am', 'unrelated')
    $changed = Get-Changed $base (Get-Hashes)
    Assert-True (((Get-Changed $base (Get-Hashes)) -join ',') -eq 'lint') "a file no job reads changes lint alone, a name with a space included ($($changed -join ', '))"

    $base = Get-Hashes
    Assert-True ((Get-Changed $base (Get-Hashes -EventName 'push')).Count -eq $base.Count) 'a pull request and a push have different hashes for every job'
    Assert-True ((Get-Changed $base (Get-Hashes -Runner 'ubuntu24-2')).Count -eq $base.Count) 'a new runner image changes every hash'

    # The observations: what is recorded, what is not.
    $needs = [ordered]@{ changes = [ordered]@{ result = 'success'; outputs = [ordered]@{ 'zero-config' = 'true'; web = 'false'; 'hash-lint' = ('a' * 32); 'hit-lint' = ''; 'hash-zero-config' = ('b' * 32); 'hit-zero-config' = 'true'
            'hash-web' = ('c' * 32); 'hit-web' = ''; 'hash-measure' = ('d' * 32); 'hit-measure' = ''; measure = 'true' } }
        lint = @{ result = 'success' }; 'zero-config' = @{ result = 'success' }; web = @{ result = 'skipped' }; measure = @{ result = 'failure' } }
    $outFile = Join-Path $temp 'github-output'; $summary = Join-Path $temp 'summary.md'
    foreach ($f in $outFile, $summary) { Set-Content -LiteralPath $f -Value '' }
    $env:GITHUB_OUTPUT = $outFile; $env:GITHUB_STEP_SUMMARY = $summary
    try {
        & pwsh -NoProfile -NonInteractive -File (Join-Path $root '.github/scripts/Write-CacheObservations.ps1') -Needs (ConvertTo-Json -InputObject $needs -Depth 6 -Compress) -OutputDirectory $temp -EventName pull_request -RunId 7 -RunAttempt 2 -MayWrite true
        Assert-True ($LASTEXITCODE -eq 0) 'the observations script runs'
    } finally { Remove-Item Env:GITHUB_OUTPUT, Env:GITHUB_STEP_SUMMARY }
    $saves = @{}; foreach ($line in Get-Content -LiteralPath $outFile) { if ($line -match '^save-(.+)=(true|false)$') { $saves[$Matches[1]] = $Matches[2] } }
    Assert-True ($saves['lint'] -eq 'true' -and $saves['zero-config'] -eq 'false' -and $saves['web'] -eq 'false' -and $saves['measure'] -eq 'false') 'a marker is saved for a green job without one, not for a hit, a skipped job or a failed one'
    $observed = @(Get-Content -LiteralPath (Join-Path $temp 'cache-observations.jsonl') | ForEach-Object { $_ | ConvertFrom-Json })
    $zero = $observed | Where-Object { $_.job -eq 'zero-config' }
    Assert-True ($observed.Count -eq 11 -and $zero.hit -eq $true -and $zero.selected -eq $true -and $zero.runAttempt -eq 2 -and $zero.runId -eq '7') 'an observation per job: hash, hit, selected, result, run attempt and run id'
    Assert-True ((Get-Content -LiteralPath $summary -Raw) -match 'Input hashes' -and (Get-Content -LiteralPath $summary -Raw) -match 'bbbbbbbbbbbb') 'the summary table names the first 12 characters of each hash'
    foreach ($f in $outFile) { Set-Content -LiteralPath $f -Value '' }
    $env:GITHUB_OUTPUT = $outFile; $env:GITHUB_STEP_SUMMARY = $summary
    try { & pwsh -NoProfile -NonInteractive -File (Join-Path $root '.github/scripts/Write-CacheObservations.ps1') -Needs (ConvertTo-Json -InputObject $needs -Depth 6 -Compress) -OutputDirectory $temp -EventName pull_request -RunId 7 -RunAttempt 1 -MayWrite false }
    finally { Remove-Item Env:GITHUB_OUTPUT, Env:GITHUB_STEP_SUMMARY }
    Assert-True (@(Get-Content -LiteralPath $outFile | Where-Object { $_ -match '=true$' }).Count -eq 0) 'a pull request from a fork saves no marker'
} finally {
    Remove-Item -LiteralPath $temp -Recurse -Force -ErrorAction SilentlyContinue
}

if ($failures.Count) { Write-Host "`n$($failures.Count) failed" -ForegroundColor Red; exit 1 }
Write-Host "`nAll passed"
