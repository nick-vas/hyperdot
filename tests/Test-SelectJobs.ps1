#!/usr/bin/env pwsh
# Self-test of .github/scripts/Select-Jobs.ps1, which decides what the Self-test workflow runs for a change. No Godot.
# The selection is run with the changed files given (-Files), and once through git against a temporary repository.
Set-StrictMode -Version 3.0
$ErrorActionPreference = 'Stop'
$root = Split-Path $PSScriptRoot
$script = Join-Path $root '.github/scripts/Select-Jobs.ps1'
$failures = [System.Collections.Generic.List[string]]::new()

function Assert-True([bool]$Condition, [string]$Message) {
    if (-not $Condition) { $failures.Add($Message); Write-Host "FAIL $Message" -ForegroundColor Red } else { Write-Host "ok   $Message" }
}

function Get-Selection([string]$EventName = 'pull_request', [string[]]$Files = @(), [string]$Base = ('a' * 40), [string]$Where = $root, [switch]$NoFiles) {
    $arguments = @('-NoProfile', '-File', $script, '-EventName', $EventName, '-Base', $Base, '-Root', $Where, '-Json')
    if (-not $NoFiles) { $arguments += '-Files'; $arguments += $(if ($Files.Count) { $Files -join ',' } else { '' }) }
    $text = (& pwsh @arguments 2>&1) -join "`n"
    if ($LASTEXITCODE) { throw "Select-Jobs failed: $text" }
    return $text | ConvertFrom-Json
}
$gated = 'zero-config', 'csharp', 'explicit-runners', 'action', 'local-windows', 'init', 'measure', 'game-benchmark', 'field-test', 'web'
function Get-JobNames($Selection) { return @($gated | Where-Object { $Selection.$_ }) }
function Get-PairNames($Selection) { return @($Selection.pairs | ForEach-Object { "$($_.genre)/$($_.language)" }) }

$spec = Get-Content -Raw (Join-Path $root 'benchmark/game-programme.json') | ConvertFrom-Json
$written = @(foreach ($g in $spec.programme.genres) { foreach ($l in $g.languages) { if (Test-Path (Join-Path $root "benchmark/games/$($g.id)/$l")) { "$($g.id)/$l" } } })
Assert-True ($written.Count -ge 20) "the programme has its written pairs ($($written.Count))"

# The jobs. Documentation and unrelated files run lint alone (it always runs): no gated job, no pair.
foreach ($file in 'docs/ci.md', 'README.md', 'CHANGELOG.md', 'AGENTS.md', 'site/Build-Site.ps1', 'site/site.css', 'benchmark/PLAN.md', 'benchmark/games/arena/DESIGN.md', 'evals/scaffold-gdscript.sh', '.gitignore', 'tests/doctor-fixture/project.godot', 'tests/Get-CoverageMap.ps1', '.github/workflows/pages.yml', '.github/workflows/release.yml', '.github/scripts/Get-ChangelogSection.ps1', '.github/scripts/Test-MajorTagMove.ps1', '.github/scripts/Get-BenchmarkMinutes.ps1', 'tests/Test-ReleaseNotes.ps1') {
    $s = Get-Selection -Files $file
    Assert-True (@(Get-JobNames $s).Count -eq 0 -and @($s.pairs).Count -eq 0 -and -not $s.all) "$file runs lint alone ($(@(Get-JobNames $s) -join ', '))"
}
# docs/json.md is a table the error-code test reads; a skill, a subagent or a template ships to games.
$s = Get-Selection -Files 'docs/json.md'
Assert-True (((Get-JobNames $s) -join ',') -eq 'measure') "docs/json.md runs the error-code test's job ($((Get-JobNames $s) -join ', '))"
$s = Get-Selection -Files '.agents/skills/godot-testing/SKILL.md', 'agents/godot-verifier.md'
Assert-True (((Get-JobNames $s) -join ',') -eq 'init') "a skill and a subagent run init ($((Get-JobNames $s) -join ', '))"

# The shared core runs every job, but the field test only for the workflow and its scripts.
foreach ($file in '.github/workflows/self-test.yml', '.github/actions/apt/action.yml', '.github/scripts/Select-Jobs.ps1', 'ci/godot/hyperdot.ps1', 'ci/godot/lib/Common.ps1', 'ci/godot/lib/Runners.ps1', 'ci/godot/lib/Setup.ps1', 'ci/godot/tools/validate.gd', 'examples/csharp/game/Main.cs') {
    $s = Get-Selection -Files $file
    $names = @(Get-JobNames $s)
    $every = if ($file -match '^\.github/(workflows/self-test\.yml|scripts/)') { $gated } else { @($gated | Where-Object { $_ -ne 'field-test' }) }
    Assert-True (@($every | Where-Object { $_ -notin $names }).Count -eq 0 -and ($file -match '^\.github/(workflows/self-test\.yml|scripts/)' -or 'field-test' -notin $names)) "$file runs every job$(if ($every.Count -lt $gated.Count) { ' but the field test' })"
}
# What a job exercises runs that job and not a heavy one that does not.
$cases = @(
    @{ File = 'ci/godot/lib/Measure.ps1'; Runs = 'measure', 'web', 'init'; Not = @() }
    @{ File = 'ci/godot/tools/bench.gd'; Runs = 'measure', 'web', 'init'; Not = 'field-test', 'game-benchmark' }
    @{ File = 'ci/godot/lib/Web.ps1'; Runs = 'web'; Not = 'measure', 'field-test', 'game-benchmark' }
    @{ File = 'ci/godot/lib/Sfx.ps1'; Runs = 'init', 'zero-config'; Not = 'measure', 'web', 'field-test', 'game-benchmark' }
    @{ File = 'ci/godot/lib/Doctor.ps1'; Runs = 'game-benchmark'; Not = 'field-test' }
    @{ File = 'ci/godot/lib/Common.ps1'; Runs = $gated | Where-Object { $_ -ne 'field-test' }; Not = 'field-test' }
    @{ File = 'benchmark/FieldTest.ps1'; Runs = 'field-test', 'game-benchmark'; Not = 'measure', 'web', 'init', 'csharp', 'local-windows' }
    @{ File = 'benchmark/Isolation.ps1'; Runs = 'game-benchmark'; Not = 'measure', 'web', 'init' }
    @{ File = 'benchmark/games/arena/gdscript/main.gd'; Runs = @(); Not = $gated }
    @{ File = 'tests/Test-Web.ps1'; Runs = 'web'; Not = 'measure', 'init', 'field-test' }
    @{ File = 'tests/web-fixture/project.godot'; Runs = 'web'; Not = 'init', 'field-test', 'game-benchmark' }
    @{ File = 'tests/Test-ProcessTimeout.ps1'; Runs = 'local-windows'; Not = 'measure', 'web', 'field-test' }
    @{ File = 'tests/Test-GameProgramme.ps1'; Runs = 'game-benchmark'; Not = 'measure', 'web', 'init' }
    @{ File = 'tests/Test-FieldTest.ps1'; Runs = 'field-test'; Not = 'game-benchmark', 'measure', 'web' }
    @{ File = 'hooks/stop-gate.ps1'; Runs = 'init'; Not = 'measure', 'web', 'field-test' }
    @{ File = "tests/unnamed-$([guid]::NewGuid().ToString('N')).json"; Runs = $gated; Not = @() }
)
foreach ($case in $cases) {
    $names = @(Get-JobNames (Get-Selection -Files $case.File))
    $missing = @($case.Runs | Where-Object { $_ -notin $names }); $extra = @($case.Not | Where-Object { $_ -in $names })
    Assert-True ($missing.Count -eq 0 -and $extra.Count -eq 0) "$($case.File) runs $($case.Runs -join ', ') and not $($case.Not -join ', ') (ran: $($names -join ', '))"
}
# Several files: the union.
$names = @(Get-JobNames (Get-Selection -Files 'ci/godot/lib/Web.ps1', 'benchmark/FieldTest.ps1', 'docs/ci.md'))
$want = @('web', 'field-test', 'game-benchmark', 'zero-config', 'csharp', 'explicit-runners', 'action', 'local-windows', 'init') | Sort-Object
Assert-True ((($names | Sort-Object) -join ',') -eq ($want -join ',') ) "the jobs of several files add up ($($names -join ', '))"

# Whatever the workflow runs in a skippable job selects that job when that test script alone changes, so a test added to a
# job cannot be left out of its filter.
$text = Get-Content -Raw (Join-Path $root '.github/workflows/self-test.yml')
$text = (($text -split "`n") | Where-Object { $_ -notmatch '^\s*#' }) -join "`n"
$jobs = [regex]::Split($text.Substring($text.IndexOf("`njobs:")), '(?m)^  (?=[a-z][a-z0-9-]*:\s*$)')
foreach ($block in $jobs) {
    $job = ($block -split ':', 2)[0]
    if ($job -notin $gated) { continue }
    foreach ($test in [regex]::Matches($block, 'tests/(Test-[\w-]+\.ps1)') | ForEach-Object { $_.Groups[1].Value } | Sort-Object -Unique) {
        $names = @(Get-JobNames (Get-Selection -Files "tests/$test"))
        Assert-True ($job -in $names) "tests/$test, run by $job, selects it"
    }
}
foreach ($job in $gated) { Assert-True ($text -match "(?m)^  $job`:\s*$") "the workflow has the job $job" }

# Docs and unrelated files: no pair.
$s = Get-Selection -Files 'docs/ci.md', 'README.md', 'benchmark/games/arena/DESIGN.md'
Assert-True (@(Get-PairNames $s).Count -eq 0) 'prose changes run no pair of the matrix'

# The check's own code: a sample of three, one of them platformer in C# and one arena in GDScript.
foreach ($file in 'benchmark/GameProgramme.ps1', 'benchmark/game-programme.json', 'tests/Test-GameProgramme.ps1', 'benchmark/templates/csharp/Foo.cs') {
    $names = @(Get-PairNames (Get-Selection -Files $file))
    Assert-True ($names.Count -eq 3 -and 'platformer/csharp' -in $names -and 'arena/gdscript' -in $names) "$file runs the sample of three ($($names -join ', '))"
}

# A game folder: that pair, whatever else the change holds; a sample pair is not added twice.
$names = @(Get-PairNames (Get-Selection -Files 'benchmark/games/racing/csharp/Game.cs'))
Assert-True ($names.Count -eq 1 -and $names[0] -eq 'racing/csharp') "a game's folder runs its pair ($($names -join ', '))"
$names = @(Get-PairNames (Get-Selection -Files 'benchmark/games/racing/gdscript/main.gd', 'benchmark/games/arena/gdscript/main.gd', 'benchmark/GameProgramme.ps1'))
Assert-True ($names.Count -eq 4 -and 'racing/gdscript' -in $names) "a game and the check's code: the sample plus the changed pair ($($names -join ', '))"
$names = @(Get-PairNames (Get-Selection -Files 'benchmark/games/idle/shared.json'))
Assert-True ($names.Count -eq 2 -and 'idle/csharp' -in $names -and 'idle/gdscript' -in $names) "a genre's file outside both languages runs both its pairs ($($names -join ', '))"

# Everything: dispatch, push to main, schedule, no base, and a base that cannot be fetched.
foreach ($trigger in 'workflow_dispatch', 'push', 'schedule') {
    $s = Get-Selection -EventName $trigger -Files 'README.md'
    Assert-True ($s.full -and @(Get-PairNames $s).Count -eq $written.Count) "$trigger runs every pair"
}
$s = Get-Selection -Base ('0' * 40) -Files 'README.md'
Assert-True ($s.full -and @(Get-PairNames $s).Count -eq $written.Count) 'an all-zero base (a new branch) runs every pair'
$s = Get-Selection -Base '' -Files 'README.md'
Assert-True ($s.full) 'no base runs every pair'

# Through git: the files come from the diff against the base; a base git cannot fetch means everything. A repository of
# its own whose origin is itself, so nothing leaves this machine.
$temp = Join-Path ([IO.Path]::GetTempPath()) "select-jobs-$PID"
try {
    New-Item -ItemType Directory $temp | Out-Null
    foreach ($file in 'benchmark/game-programme.json', '.github/workflows/self-test.yml') { New-Item -ItemType Directory -Force (Join-Path $temp (Split-Path $file)) | Out-Null; Copy-Item (Join-Path $root $file) (Join-Path $temp $file) }
    New-Item -ItemType Directory -Force (Join-Path $temp 'benchmark/games/arena/gdscript'), (Join-Path $temp 'benchmark/games/platformer/csharp') | Out-Null
    Set-Content (Join-Path $temp 'benchmark/games/arena/gdscript/main.gd') 'extends Node'
    Set-Content (Join-Path $temp 'benchmark/games/platformer/csharp/Game.cs') 'class A {}'
    git -C $temp init -q
    git -C $temp remote add origin $temp
    git -C $temp add -A
    git -C $temp -c user.name=ci -c user.email=ci@example.com commit -qm base
    $base = (git -C $temp rev-parse HEAD).Trim()
    Set-Content (Join-Path $temp 'benchmark/games/arena/gdscript/main.gd') 'extends Node2D'
    git -C $temp -c user.name=ci -c user.email=ci@example.com commit -qam change
    $names = @(Get-PairNames (Get-Selection -Base $base -Where $temp -NoFiles))
    Assert-True ($names.Count -eq 1 -and $names[0] -eq 'arena/gdscript') "git diff against the base finds the changed game ($($names -join ', '))"
    $s = Get-Selection -Base ('b' * 40) -Where $temp -NoFiles
    Assert-True ($s.full) 'a base git cannot fetch runs every pair'

    # A rename out of a gated path lists the old path too (no rename detection), and git's quoting of a non-ASCII name
    # does not hide the file.
    $gitCommit = { param([string]$Message) git -C $temp add -A; git -C $temp -c user.name=ci -c user.email=ci@example.com commit -qm $Message }
    New-Item -ItemType Directory -Force (Join-Path $temp 'ci/godot/lib'), (Join-Path $temp 'docs'), (Join-Path $temp 'examples/gdscript/art') | Out-Null
    Set-Content (Join-Path $temp 'ci/godot/lib/Measure.ps1') '# measure'
    Set-Content -LiteralPath (Join-Path $temp 'examples/gdscript/art/café.png') 'one'
    Set-Content -LiteralPath (Join-Path $temp 'examples/gdscript/art/a b.png') 'one'
    & $gitCommit 'files' | Out-Null
    $base2 = (git -C $temp rev-parse HEAD).Trim()
    git -C $temp mv ci/godot/lib/Measure.ps1 docs/Measure.ps1
    & $gitCommit 'move' | Out-Null
    $s = Get-Selection -Base $base2 -Where $temp -NoFiles
    Assert-True ($s.measure -and -not $s.full) 'a file moved out of a gated path into docs/ still selects the job'
    git -C $temp reset -q --hard $base2
    Set-Content -LiteralPath (Join-Path $temp 'examples/gdscript/art/café.png') 'two'
    & $gitCommit 'cafe' | Out-Null
    $s = Get-Selection -Base $base2 -Where $temp -NoFiles
    Assert-True ($s.'zero-config' -and -not $s.full) 'a changed file with a non-ASCII name is selected'
    git -C $temp reset -q --hard $base2
    Set-Content -LiteralPath (Join-Path $temp 'examples/gdscript/art/a b.png') 'two'
    & $gitCommit 'space' | Out-Null
    $s = Get-Selection -Base $base2 -Where $temp -NoFiles
    Assert-True ($s.'zero-config' -and -not $s.full) 'a changed file with a space in its name is selected'
    $listed = (& pwsh -NoProfile -NonInteractive -File $script -Root $temp -Inputs) -join "`n" | ConvertFrom-Json -AsHashtable
    Assert-True ('examples/gdscript/art/café.png' -in $listed['zero-config'] -and 'examples/gdscript/art/a b.png' -in $listed['zero-config']) '-Inputs lists a non-ASCII name and a name with a space as they are'
} finally { Remove-Item -LiteralPath $temp -Recurse -Force -ErrorAction SilentlyContinue }

if ($failures.Count) { Write-Host "`n$($failures.Count) failed" -ForegroundColor Red; exit 1 }
Write-Host "`nAll passed"
