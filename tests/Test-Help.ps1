#!/usr/bin/env pwsh
# Self-test of `help` and its one source, docs/help.md: every command in hyperdot.ps1's -Command set, every skill in
# .agents/skills and every subagent in agents/ has an entry there with a one-line summary, and no entry names one that
# does not exist; the kit calls its pages quote bind. Then `help` itself, from a folder with no project: the Markdown page
# (a row per entry, the same bytes twice, docs/kit-help.md with -Project), a command's, a skill's and a subagent's page, an unknown name and a name given to another command. No Godot needed.
Set-StrictMode -Version 3.0
$ErrorActionPreference = 'Stop'
$root = Split-Path $PSScriptRoot
$ci = Join-Path $root 'ci/godot/hyperdot.ps1'
$failures = @()
function Assert-True([bool]$Condition, [string]$Name) {
    if ($Condition) { Write-Host "ok     $Name" } else { Write-Host "FAIL   $Name"; $script:failures += $Name }
}

foreach ($lib in 'Common', 'Context', 'Help') { . (Join-Path $root "ci/godot/lib/$lib.ps1") }
$helpFile = Join-Path $root 'docs/help.md'
$entries = @(Read-HelpEntries $helpFile)
$subjects = Get-HelpSubjects
foreach ($kind in $subjects.Keys) {
    $listed = @($entries | Where-Object kind -eq $kind | ForEach-Object name)
    $missing = @($subjects[$kind] | Where-Object { $_ -notin $listed })
    $stale = @($listed | Where-Object { $_ -notin $subjects[$kind] })
    Assert-True ($missing.Count -eq 0) "every $kind has an entry in docs/help.md$(if ($missing) { ": add ### $($missing -join ', ### ') under its section" })"
    Assert-True ($stale.Count -eq 0) "every $kind entry exists$(if ($stale) { ": $($stale -join ', ') no longer does" })"
}
# Every skill sits in exactly one group of "## Skill groups", and a group names only skills that exist.
$groups = @(Read-HelpGroups $helpFile)
$grouped = @($groups | ForEach-Object { $_.skills })
$ungrouped = @($subjects.skill | Where-Object { $_ -notin $grouped })
$unknown = @($grouped | Where-Object { $_ -notin $subjects.skill })
$doubled = @($grouped | Group-Object | Where-Object Count -gt 1 | ForEach-Object Name)
Assert-True ($groups.Count -gt 0 -and $ungrouped.Count -eq 0) "every skill is in a group of docs/help.md$(if ($ungrouped) { ": add $($ungrouped -join ', ') under ## Skill groups" })"
Assert-True ($unknown.Count -eq 0 -and $doubled.Count -eq 0) "each group lists real skills, each once$(if ($unknown -or $doubled) { ": $(@($unknown) + @($doubled) -join ', ')" })"
$twice = @($entries | ForEach-Object { $_.name } | Group-Object | Where-Object Count -gt 1 | ForEach-Object Name)
Assert-True ($twice.Count -eq 0) "no name has two entries$(if ($twice) { ": $($twice -join ', ')" })"
$noSummary = @($entries | Where-Object { -not $_.summary -or $_.summary.Length -gt 200 } | ForEach-Object name)
Assert-True ($noSummary.Count -eq 0) "each entry starts with a summary line of at most 200 characters$(if ($noSummary) { ": $($noSummary -join ', ')" })"

# The pages quote calls as `hyperdot.ps1 <command> [-Flag value]`: each must name a real command and real flags.
$calls = ([System.IO.File]::ReadAllText($helpFile) -replace '(?m)^(\s*)hyperdot\.ps1', '$1pwsh hyperdot.ps1') -replace '[\[\]|]', ' '
$problems = @(Get-KitCommandProblems $calls 'docs/help.md')
Assert-True ($problems.Count -eq 0) "every call in docs/help.md binds$(if ($problems) { ': ' + ($problems -join ' | ') })"

# The command itself, run where there is no Godot project at all.
$empty = Join-Path ([System.IO.Path]::GetTempPath()) "help-$([guid]::NewGuid().ToString('n').Substring(0, 8))"
New-Item -ItemType Directory -Force $empty | Out-Null
function Invoke-Help([string[]]$HelpArgs) {
    Push-Location $empty
    try { $out = & pwsh -NoProfile -NonInteractive -File $ci @HelpArgs 2>$null | Out-String } finally { Pop-Location }
    return [pscustomobject]@{ Code = $LASTEXITCODE; Text = $out }
}
try {
    $r = Invoke-Help @('help', '-Json')
    $d = $r.Text | ConvertFrom-Json
    $total = @($subjects.Values | ForEach-Object { $_ }).Count
    Assert-True ($r.Code -eq 0 -and $d.ok -and $d.command -eq 'help' -and @($d.entries).Count -eq $total) "help -Json lists all $total entries without a project: $(@($d.entries).Count)"
    Assert-True (@($d.entries | Where-Object { $_.name -eq 'shot' -and $_.kind -eq 'command' -and $_.summary }).Count -eq 1) 'each entry has a name, kind and summary'

    # Without a name the list is a Markdown file: in the temp folder from here (no project), in docs/ of a project.
    $r = Invoke-Help @('help')
    $file = Join-Path ([System.IO.Path]::GetTempPath()) 'hyperdot-kit-help.md'
    Assert-True ($r.Code -eq 0 -and $r.Text -match 'Kit help written to ' -and (Test-Path -LiteralPath $file)) 'help writes the Markdown page and prints where'
    $md = [System.IO.File]::ReadAllText($file)
    $absent = @(foreach ($e in $entries) { $mark = if ($e.kind -eq 'skill') { "/$($e.name)" } else { $e.name }; if ($md -notmatch "(?m)^\| ``$([regex]::Escape($mark))`` \| \S") { $e.name } })
    Assert-True ($absent.Count -eq 0) "the page has a table row per entry$(if ($absent) { ": missing $($absent -join ', ')" })"
    Assert-True ($md -match '(?m)^## Commands \(\d+\)$' -and $md -match '(?m)^## Skills \(\d+\)$' -and $md -match '(?m)^## Subagents \(\d+\)$' -and $md -notmatch '\r') 'the page has a table each for commands, skills and subagents, with LF line ends'
    $groupLines = @($groups | Where-Object { $md -notmatch "(?m)^### $([regex]::Escape($_.name)) \($($_.skills.Count)\)$" } | ForEach-Object name)
    Assert-True ($groupLines.Count -eq 0 -and $md -notmatch '### Other') "the skills are under one heading per group, each with its count$(if ($groupLines) { ": missing $($groupLines -join ', ')" })"
    $before = (Get-FileHash -LiteralPath $file).Hash
    $d = (Invoke-Help @('help', '-Json')).Text | ConvertFrom-Json
    Assert-True ($d.path -eq $file -and (Get-FileHash -LiteralPath $file).Hash -eq $before) 'help -Json names the file, and a second run writes the same bytes'
    $game = Join-Path $empty 'game'
    New-Item -ItemType Directory -Force $game | Out-Null
    Set-Content -LiteralPath (Join-Path $game 'project.godot') -Value 'config_version=5'
    $d = (Invoke-Help @('help', '-Json', '-Project', $game)).Text | ConvertFrom-Json
    Assert-True ((Test-Path -LiteralPath (Join-Path $game 'docs/kit-help.md')) -and $d.path -eq (Join-Path $game 'docs/kit-help.md')) 'with -Project the page goes to docs/kit-help.md of the game'

    $d = (Invoke-Help @('help', 'shot', '-Json')).Text | ConvertFrom-Json
    Assert-True ($d.ok -and $d.entry.kind -eq 'command' -and $d.entry.page -match 'hyperdot\.ps1 shot ') "help shot returns the command's page: $($d.entry | ConvertTo-Json -Depth 10 -Compress)"
    $d = (Invoke-Help @('help', '/game', '-Json')).Text | ConvertFrom-Json
    Assert-True ($d.ok -and $d.entry.kind -eq 'skill' -and $d.entry.when -match '^Use when' -and $d.entry.start -match '/game' -and $d.entry.file -eq '.agents/skills/game/SKILL.md') "help /game adds when and how to start it: $($d.entry | ConvertTo-Json -Depth 10 -Compress)"
    $d = (Invoke-Help @('help', 'godot-verifier', '-Json')).Text | ConvertFrom-Json
    Assert-True ($d.ok -and $d.entry.kind -eq 'subagent' -and $d.entry.when) 'help godot-verifier returns the subagent page'
    $r = Invoke-Help @('help', 'game')
    Assert-True ($r.Code -eq 0 -and $r.Text -match '(?m)^game \(skill\): ' -and $r.Text -match '(?m)^When: Use when') 'help game prints the page as text'

    $r = Invoke-Help @('help', 'shto', '-Json')
    $d = $r.Text | ConvertFrom-Json
    Assert-True ($r.Code -eq 1 -and $d.error.code -eq 'invalid-arguments' -and $d.error.message -match 'did you mean shot') "an unknown name suggests the closest: $($d.error.message)"
    $r = Invoke-Help @('test', 'shot', '-Json')
    $d = $r.Text | ConvertFrom-Json
    Assert-True ($r.Code -eq 1 -and $d.error.code -eq 'invalid-arguments') 'a name given to another command is refused'
} finally {
    Remove-Item -LiteralPath $empty -Recurse -Force -ErrorAction SilentlyContinue
}

if ($failures.Count) { throw "$($failures.Count) help check(s) failed" }
Write-Host 'help self-test passed'
# Some kit runs failed on purpose (the refusals); GitHub's pwsh wrapper would exit with the last one's code.
exit 0
