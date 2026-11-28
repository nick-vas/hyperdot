#!/usr/bin/env pwsh
# Self-test of the plan's gates on a fresh plan: slice.debt and prototype.trailer are automatic and turn true when
# docs/TECH-DEBT.md and docs/TRAILER.md exist (and `plan -Do done` refuses them), slice.budget is manual and names a real
# `bench` command, the trailer template asks what its gate says, and every gate id, template and hyperdot.ps1 flag that
# the plan or any skill quotes exists. The release timeline (plan.json "release") warns on fixed days when Steam's dates
# cannot be kept, and `plan -Json` reports it. The `tests` gate and doctor's test check
# count test frameworks only (not data tables or flows). A hand-broken plan.json fails `plan` with invalid-plan and is a
# warning in `status`. `init` never overwrites an existing test/test_example.gd, and pins its workflow at `@v1`; with
# -Plugin it writes docs/kit-notes.md once. concept.risks wants a non-empty docs/RISKS.md, the optional concept.budget
# does not hold its phase back, beta.placeholders reads assets.json and the Placeholders table of docs/TECH-DEBT.md, and
# `plan -Do reopen` opens a manual gate again. `plan -Do init -Profile jam` writes the jam plan, sized in days. `status`
# lists the GDD's first-session steps with the flows and stubs tagged GDD:S<n>. No Godot needed.
Set-StrictMode -Version 3.0
$ErrorActionPreference = 'Stop'
$root = Split-Path $PSScriptRoot
$ci = Join-Path $root 'ci/godot/hyperdot.ps1'
$templates = Join-Path $root 'ci/godot/templates'
$dir = Join-Path ([IO.Path]::GetTempPath()) "plan-$([guid]::NewGuid().ToString('N').Substring(0, 8))"
$failures = [System.Collections.Generic.List[string]]::new()
function Assert-True([bool]$Condition, [string]$What) {
    if ($Condition) { Write-Host "ok     $What" } else { Write-Host "FAILED $What" -ForegroundColor Red; $failures.Add($What) }
}
function Invoke-PlanJson([string[]]$Arguments) {
    return pwsh -NoProfile -NonInteractive -File $ci plan -Json -Project $dir @Arguments 2>$null | ConvertFrom-Json
}

$template = Get-Content -LiteralPath (Join-Path $templates 'plan.json') -Raw | ConvertFrom-Json -Depth 10
$jamTemplate = Get-Content -LiteralPath (Join-Path $templates 'plan-jam.json') -Raw | ConvertFrom-Json -Depth 10
$gateIds = @(foreach ($phase in @($template.phases) + @($jamTemplate.phases)) { foreach ($gate in $phase.gates) { $gate.id } })
Assert-True (@($gateIds | Group-Object | Where-Object Count -gt 1).Count -eq 0) 'gate ids are unique across the full and jam templates'

# Flags quoted after "hyperdot.ps1 <command>" in a gate's text must be parameters of the script.
$ast = [System.Management.Automation.Language.Parser]::ParseFile($ci, [ref]$null, [ref]$null)
$parameters = @($ast.ParamBlock.Parameters | ForEach-Object { $_.Name.VariablePath.UserPath })
foreach ($phase in @($template.phases) + @($jamTemplate.phases)) {
    foreach ($gate in $phase.gates) {
        foreach ($quote in [regex]::Matches($gate.text, 'hyperdot\.ps1 \w+(?<rest>[^:;,)]*)')) {
            foreach ($flag in [regex]::Matches($quote.Groups['rest'].Value, '(?<=\s)-(?<name>[A-Za-z]+)')) {
                Assert-True ($flag.Groups['name'].Value -in $parameters) "$($gate.id) quotes -$($flag.Groups['name'].Value), a hyperdot.ps1 parameter"
            }
        }
    }
}

# Gate ids any skill names exist in the template (plan.json is copied once, so a renamed gate would strand them).
foreach ($skillFile in @(Get-ChildItem -LiteralPath (Join-Path $root '.agents/skills') -Filter 'SKILL.md' -Recurse)) {
    $skill = Get-Content -LiteralPath $skillFile.FullName -Raw
    foreach ($quoted in [regex]::Matches($skill, '`(?<id>(concept|prototype|slice|production|beta|launch|post|jam)\.[a-z0-9]+)`')) {
        Assert-True ($quoted.Groups['id'].Value -in $gateIds) "$($skillFile.Directory.Name) names gate $($quoted.Groups['id'].Value), which plan.json has"
    }
}

# Templates the planning and store-page skills tell an agent to copy exist.
foreach ($skillName in 'game-plan', 'store-page') {
    $text = Get-Content -LiteralPath (Join-Path $root ".agents/skills/$skillName/SKILL.md") -Raw
    foreach ($quoted in [regex]::Matches($text, 'ci/godot/templates/(?<file>[A-Za-z0-9._-]+)')) {
        Assert-True (Test-Path -LiteralPath (Join-Path $templates $quoted.Groups['file'].Value)) "$skillName names templates/$($quoted.Groups['file'].Value), which exists"
    }
}
$planSkill = Get-Content -LiteralPath (Join-Path $root '.agents/skills/game-plan/SKILL.md') -Raw
Assert-True ($planSkill -match 'prototype\.trailer') 'game-plan explains prototype.trailer'

# The trailer template asks what the gate promises, in the talk's order: genre, then hook, content last; three standout
# moments; a feedback column for every mechanic.
$trailerPath = Join-Path $templates 'TRAILER.md'
$trailer = (Test-Path -LiteralPath $trailerPath) ? (Get-Content -LiteralPath $trailerPath -Raw) : ''
Assert-True ($trailer -ne '') 'templates/TRAILER.md exists'
$genre = $trailer.IndexOf('| Genre (first 5 seconds)'); $hook = $trailer.IndexOf('| Hook'); $content = $trailer.IndexOf('| Content (last')
Assert-True ($genre -ge 0 -and $hook -gt $genre -and $content -gt $hook) 'the trailer template orders genre (first 5 seconds), hook, then content'
$moments = [regex]::Match($trailer, '(?s)## Three standout moments\r?\n(?<body>.*?)(\r?\n## |\z)')
Assert-True ($moments.Success -and @([regex]::Matches($moments.Groups['body'].Value, '(?m)^[1-3]\.')).Count -eq 3) 'the trailer template has three standout moments to fill'
Assert-True ($trailer -match '(?m)^\| Mechanic \|.*\| On-screen feedback a viewer sees \|') 'the trailer template pairs each mechanic with its on-screen feedback'

# The release timeline (plan.json "release"), on fixed days: Steam's 21 days after the fee, 2 weeks of Coming Soon,
# 7 business days per review (the store page before the build), the date lock, and the Next Fest demo deadline.
foreach ($lib in 'Common', 'Detect', 'Report', 'Plan') { . (Join-Path $root "ci/godot/lib/$lib.ps1") }
$fields = @($template.release.PSObject.Properties.Name)
Assert-True (@($script:ReleaseDateFields | Where-Object { $_ -notin $fields }).Count -eq 0 -and $fields -contains 'pressPreview') "the plan template has every release field: $($fields -join ', ')"
Assert-True ((Get-BusinessDayCount ([datetime]'2027-03-04') ([datetime]'2027-03-15')) -eq 7 -and (Get-BusinessDayBefore ([datetime]'2027-03-15') 7) -eq [datetime]'2027-03-04') 'business days skip the weekend'

$onTime = Get-ReleaseTimeline ([pscustomobject]@{ date = '2027-03-15'; steamFeePaid = '2027-01-04'; comingSoon = '2026-12-01'; storePageSubmitted = '2026-11-16'
        buildSubmitted = $null; nextFest = '2027-02-22'; demoSubmitted = '2027-01-25'; pressPreview = $false }) ([datetime]'2027-01-04')
$t = $onTime.timeline
Assert-True ($onTime.warnings.Count -eq 0) "a timeline that keeps every rule has no warnings: $($onTime.warnings -join ' | ')"
Assert-True ($t.date -eq '2027-03-15' -and $t.daysLeft -eq 70 -and $t.businessDaysLeft -eq 50 -and -not $t.dateLocked) "days and business days left: $($t | ConvertTo-Json -Depth 10 -Compress)"
Assert-True ($t.deadlines.steamFee -eq '2027-02-22' -and $t.deadlines.comingSoon -eq '2027-03-01' -and $t.deadlines.buildReview -eq '2027-03-04' -and
    $t.deadlines.storePageReview -eq '2026-11-20' -and $t.deadlines.dateLock -eq '2027-03-01' -and $t.deadlines.demoReview -eq '2027-02-01') "deadlines: $($t.deadlines | ConvertTo-Json -Depth 10 -Compress)"

$late = Get-ReleaseTimeline ([pscustomobject]@{ date = '2027-03-15'; steamFeePaid = '2027-03-01'; comingSoon = '2027-03-05'; storePageSubmitted = '2027-03-01'
        nextFest = '2027-02-22'; demoSubmitted = '2027-02-10' }) ([datetime]'2027-03-08')
foreach ($expected in @(
        @('app fee was paid on 2027-03-01, 14 days before release.*at least 21 days', 'a fee paid 14 days before release warns'),
        @('Coming Soon page goes live on 2027-03-05, 10 days before release.*at least 2 weeks', 'Coming Soon 10 days before release warns'),
        @('store page was submitted for review 4 business day\(s\) before its Coming Soon date', 'a store page submitted 4 business days ahead warns'),
        @('^5 business day\(s\) left before release and release\.buildSubmitted is not set', 'no build submitted with 5 business days left warns'),
        @('Next Fest demo was submitted on 2027-02-10, after the 2027-02-01 deadline \(3 weeks', 'a demo submitted after the 3-week deadline warns'))) {
    Assert-True (@($late.warnings | Where-Object { $_ -match $expected[0] }).Count -eq 1) $expected[1]
}
Assert-True ($late.warnings.Count -eq 5) "nothing else: $($late.warnings -join ' | ')"
Assert-True ($late.timeline.dateLocked -and @($late.notes | Where-Object { $_ -match 'is locked' }).Count -eq 1) 'a week before release the date is locked (a note, not a warning)'

$unset = Get-ReleaseTimeline ([pscustomobject]@{ date = '2027-03-15'; comingSoon = 'next week' }) ([datetime]'2027-03-08')
foreach ($expected in "release.comingSoon 'next week' is not a date", 'release.steamFeePaid is not set', 'release.comingSoon is not set', 'release.buildSubmitted is not set') {
    Assert-True (@($unset.warnings | Where-Object { $_.Contains($expected) }).Count -eq 1) "unset dates close to release warn: $expected"
}
Assert-True ($unset.warnings.Count -eq 4) "nothing else when dates are unset: $($unset.warnings -join ' | ')"

$order = Get-ReleaseTimeline ([pscustomobject]@{ date = '2027-06-01'; steamFeePaid = '2027-01-04'; comingSoon = '2027-02-01'; storePageSubmitted = '2027-05-03'
        buildSubmitted = '2027-04-01'; nextFest = '2027-06-14'; pressPreview = $true }) ([datetime]'2027-01-04')
Assert-True (@($order.warnings | Where-Object { $_ -match 'build was submitted for review before the store page' }).Count -eq 1) 'a build submitted before the store page warns'
Assert-True (@($order.warnings | Where-Object { $_ -match 'Next Fest \(2027-06-14\) is on or after release' }).Count -eq 1) 'a Next Fest after release warns'
Assert-True ($order.timeline.deadlines.demoReview -eq '2027-05-10') 'the press preview moves the demo deadline to 5 weeks before'
$none = Get-ReleaseTimeline ([pscustomobject]@{ date = $null }) ([datetime]'2027-01-04')
Assert-True ($null -eq $none.timeline -and $none.warnings.Count -eq 0) 'no release date, no timeline'

# The automatic gates `ci` and `preset` (Test-PlanGate on a made-up project): a workflow that uses the kit
# passes, one that only mentions godot.yml, or none, does not, and neither does a project with no export preset.
$gateDir = Join-Path ([IO.Path]::GetTempPath()) "plan-gate-$([guid]::NewGuid().ToString('N').Substring(0, 8))"
try {
    New-Item -ItemType Directory -Force (Join-Path $gateDir 'plan') | Out-Null
    Set-Content -LiteralPath (Join-Path $gateDir 'plan/plan.json') -Value '{}'
    $gateInfo = [pscustomobject]@{ ProjectDir = $gateDir; Runners = @(); Presets = @() }
    $ciGate = [pscustomobject]@{ id = 'prototype.setup'; check = 'ci' }
    $workflowDir = Join-Path $gateDir '.github/workflows'
    New-Item -ItemType Directory -Force $workflowDir | Out-Null
    function Set-CiFile([string]$Path, [string]$Text) { Set-Content -LiteralPath (Join-Path $gateDir $Path) -Value $Text }
    Assert-True ((Test-PlanGate $ciGate $gateInfo) -eq $false) 'the ci gate is open with no workflow'
    Set-CiFile '.github/workflows/test.yml' "jobs:`n  t:`n    steps:`n      - run: echo godot.yml`n      - uses: actions/checkout@v4`n"
    Assert-True ((Test-PlanGate $ciGate $gateInfo) -eq $false) 'the ci gate stays open for a workflow that only mentions godot.yml'
    Set-CiFile '.github/workflows/other.yml' "jobs:`n  t:`n    uses: someone-else/repo/.github/workflows/godot.yml@v1`n"
    Assert-True ((Test-PlanGate $ciGate $gateInfo) -eq $false) 'the ci gate stays open for another repository''s godot.yml'
    Set-CiFile '.github/workflows/action.yml' "jobs:`n  t:`n    steps:`n      - uses: nick-vas/hyperdot/.github/actions/godot@v1`n"
    Assert-True ((Test-PlanGate $ciGate $gateInfo) -eq $true) 'the ci gate passes for a workflow using the kit''s composite action'
    Remove-Item -LiteralPath (Join-Path $workflowDir 'action.yml')
    Set-CiFile '.github/workflows/hyperdot.yml' "jobs:`n  t:`n    uses: nick-vas/hyperdot/.github/workflows/godot.yml@v1`n"
    Assert-True ((Test-PlanGate $ciGate $gateInfo) -eq $true) 'the ci gate passes for a workflow calling the kit''s reusable workflow'
    Remove-Item -LiteralPath $workflowDir -Recurse -Force
    $presetGate = [pscustomobject]@{ id = 'x.preset'; check = 'preset' }
    Assert-True ((Test-PlanGate $presetGate $gateInfo) -eq $false) 'the preset gate is open with no export preset'
    $gateInfo.Presets = @('Linux')
    Assert-True ((Test-PlanGate $presetGate $gateInfo) -eq $true) 'the preset gate passes with an export preset'
} finally {
    Remove-Item -LiteralPath $gateDir -Recurse -Force -ErrorAction SilentlyContinue
}

# The export-run gate (#288), from made-up history lines: every preset this machine can launch (its own desktop
# platform and Web) passed its newest export -Run and was launched; skipped launches, partial runs, failures and lines
# from before the gate do not count; a project it cannot launch anything of leaves the gate to plan -Do done; a later
# phase that has begun keeps it met with a warning; trimming the history keeps the newest export -Run line.
$runDir = Join-Path ([IO.Path]::GetTempPath()) "plan-exportrun-$([guid]::NewGuid().ToString('N').Substring(0, 8))"
try {
    New-Item -ItemType Directory -Force (Join-Path $runDir 'plan'), (Join-Path $runDir '.godot') | Out-Null
    $native = if ($IsWindows) { 'Windows Desktop' } else { 'Linux' }
    function Set-Presets([string[]]$Platforms) {
        $i = 0
        $text = @(foreach ($p in $Platforms) { "[preset.$i]`n`nname=""$($p -replace '[^A-Za-z]', '')""`nplatform=""$p""`nexport_path=""build/x""`n"; $i++ }) -join "`n"
        Set-Content -LiteralPath (Join-Path $runDir 'export_presets.cfg') -Value $text
    }
    $desk = $native -replace '[^A-Za-z]', ''
    function Set-History([object[]]$Lines) {
        Set-Content -LiteralPath (Join-Path $runDir '.godot/hyperdot-history.jsonl') -Value @($Lines | ForEach-Object { $_ | ConvertTo-Json -Compress -Depth 4 })
    }
    function New-Line([string]$Time, [bool]$Ok, $Presets, $Launched, $Run = $true, [string]$Code = '') {
        $line = [ordered]@{ time = $Time; command = 'export'; ok = $Ok; code = $Code; commit = 'abc1234' }
        if ($null -ne $Run) { $line.run = $Run; $line.presets = @($Presets); $line.launched = @($Launched) }
        return $line
    }
    $runInfo = [pscustomobject]@{ ProjectDir = $runDir; Runners = @(); Presets = @('x') }
    $runGate = [pscustomobject]@{ id = 'slice.export'; check = 'export-run' }
    Set-Presets @($native, 'Web', 'Android')
    Set-History @()
    $g = Get-ExportRunGate $runInfo
    Assert-True ($g.met -eq $false -and $g.detail -match "never launched here: $desk, Web" -and $g.detail -match "export -Run -Preset `"$desk,Web`"") "no export -Run yet: open, naming the presets to launch: $($g.detail)"
    Set-History @((New-Line '2026-11-18T10:00:00Z' $true @($desk, 'Web', 'Android') @($desk, 'Web')))
    $g = Get-ExportRunGate $runInfo
    Assert-True ($g.met -eq $true -and (Test-PlanGate $runGate $runInfo) -eq $true -and $g.detail -match '2026-11-18 10:00 UTC at abc1234') "every launchable preset passed (Android cannot launch here and does not count): $($g.detail)"
    Set-History @((New-Line '2026-11-18T10:00:00Z' $true @($desk, 'Web') @('Web')))
    Assert-True ((Get-ExportRunGate $runInfo).detail -match "'$desk' was not launched") 'an export -Run that skipped the launch proves nothing'
    Set-History @((New-Line '2026-11-18T10:00:00Z' $true @($desk) @($desk)))
    $g = Get-ExportRunGate $runInfo
    Assert-True ($g.met -eq $false -and $g.detail -match 'never launched here: Web') "the stricter rule: a run of one preset leaves the others open: $($g.detail)"
    Set-History @((New-Line '2026-11-18T10:00:00Z' $true @($desk, 'Web') @($desk, 'Web')), (New-Line '2026-11-19T09:30:00Z' $false @($desk) @() -Code 'export-failed'))
    $g = Get-ExportRunGate $runInfo
    Assert-True ($g.met -eq $false -and $g.detail -match "'$desk' failed \(export-failed\) on 2026-11-19 09:30 UTC") "a newer failed export -Run reopens it, with its time and code: $($g.detail)"
    Set-History @((New-Line '2026-11-18T10:00:00Z' $true @($desk, 'Web') @($desk, 'Web')), (New-Line '2026-11-19T09:30:00Z' $false @($desk) @() -Run $false -Code 'export-failed'))
    Assert-True ((Get-ExportRunGate $runInfo).met -eq $true) 'an export without -Run does not count either way'
    Set-History @((New-Line '2026-11-18T10:00:00Z' $true @() @() -Run $null))
    Assert-True ((Get-ExportRunGate $runInfo).met -eq $false) 'a history line from before export recorded -Run counts as no export -Run'
    Set-Presets @('Android', 'iOS')
    $g = Get-ExportRunGate $runInfo
    Assert-True ($null -eq $g.met -and $null -eq (Test-PlanGate $runGate $runInfo) -and $g.detail -match 'can launch none of the presets \(Android, iOS\)' -and $g.detail -match 'plan -Do done') "nothing launchable here: the gate is marked by hand: $($g.detail)"
    Remove-Item -LiteralPath (Join-Path $runDir 'export_presets.cfg')
    $g = Get-ExportRunGate $runInfo
    Assert-True ($g.met -eq $false -and $g.detail -match '^No export preset yet') "no preset at all: open, not marked by hand: $($g.detail)"
    Set-Presets @($native, 'Web')

    # The latch, and the warning for plans made before export-run.
    $plan = [pscustomobject]@{ wipLimit = 3; tasks = @(); phases = @(
            [pscustomobject]@{ id = 'slice'; name = 'Vertical slice'; goal = 'g'; gates = @([pscustomobject]@{ id = 'slice.export'; text = 't'; check = 'export-run' }) },
            [pscustomobject]@{ id = 'launch'; name = 'Launch'; goal = 'g'; gates = @([pscustomobject]@{ id = 'launch.gold'; text = 't'; check = 'preset' }, [pscustomobject]@{ id = 'launch.go'; text = 't' }) }) }
    Set-History @((New-Line '2026-11-18T10:00:00Z' $true @($desk, 'Web') @($desk, 'Web')), (New-Line '2026-11-19T09:30:00Z' $false @($desk) @() -Code 'export-failed'))
    $state = Get-PlanState $plan $runInfo
    $gate = @($state.phases[0].gates)[0]
    Assert-True ($gate.done -eq $false -and $state.current.id -eq 'slice' -and $gate.detail -match "'$desk' failed") 'before the next phase begins, a failed export -Run holds the phase'
    Assert-True (@($state.warnings | Where-Object { $_ -match "Gate 'launch.gold' checks only that an export preset exists" }).Count -eq 1) 'a kit gate still on check preset is a warning naming export-run'
    $plan.phases[1] | Add-Member -NotePropertyName startedAt -NotePropertyValue '2026-11-10T00:00:00Z'
    $state = Get-PlanState $plan $runInfo
    Assert-True (@($state.phases[0].gates)[0].done -eq $true -and $state.current.id -eq 'launch' -and @($state.warnings | Where-Object { $_ -match "Gate 'slice.export' \(Vertical slice\) no longer holds, but a later phase has begun" }).Count -eq 1) 'once a later phase has begun, the gate stays met and the failure is a warning'
    $known = @(Get-PlanProblems ([pscustomobject]@{ phases = @([pscustomobject]@{ id = 'p'; gates = @([pscustomobject]@{ id = 'g'; check = 'export-run' }) }); tasks = @() }))
    Assert-True (@($known | Where-Object { $_ -match 'unknown check' }).Count -eq 0) "export-run is a known check: $($known -join '; ')"

    # Trimming: over 2,500 lines the newest 2,000 stay, plus the newest export -Run line.
    $old = (New-Line '2026-01-01T00:00:00Z' $true @($desk, 'Web') @($desk, 'Web')) | ConvertTo-Json -Compress -Depth 4
    $filler = @(1..2600 | ForEach-Object { '{"time":"2026-11-01T00:00:00Z","command":"test","ok":true,"code":""}' })
    Set-Content -LiteralPath (Join-Path $runDir '.godot/hyperdot-history.jsonl') -Value (@($old) + $filler)
    Start-RunHistory 'doctor' $runDir
    Add-RunHistory $true ''
    $lines = @(Get-Content -LiteralPath (Join-Path $runDir '.godot/hyperdot-history.jsonl'))
    Assert-True ($lines.Count -eq 2001 -and $lines[0] -eq $old -and (Get-ExportRunGate $runInfo).met -eq $true) "trimming keeps the newest export -Run line: $($lines.Count) lines"
} finally {
    Remove-Item -LiteralPath $runDir -Recurse -Force -ErrorAction SilentlyContinue
}

# The verdict gate (#289): only a line recording one verdict counts; the template's wording, a placeholder in parentheses,
# comments and code blocks do not. The file is looked up from the repository root, then the Godot project.
$verdictDir = Join-Path ([IO.Path]::GetTempPath()) "plan-verdict-$([guid]::NewGuid().ToString('N').Substring(0, 8))"
try {
    New-Item -ItemType Directory -Force (Join-Path $verdictDir 'plan'), (Join-Path $verdictDir 'docs') | Out-Null
    $verdictInfo = [pscustomobject]@{ ProjectDir = $verdictDir; Runners = @(); Presets = @() }
    $decisions = Join-Path $verdictDir 'docs/DECISIONS.md'
    $verdictGate = [pscustomobject]@{ id = 'prototype.verdict'; check = 'verdict:docs/DECISIONS.md' }
    $v = Get-VerdictGate $verdictInfo 'docs/DECISIONS.md'
    Assert-True ($v.met -eq $false -and $v.detail -match 'does not exist yet' -and $v.detail -match 'Verdict: PROCEED') "no DECISIONS.md: open, saying what to write: $($v.detail)"
    foreach ($case in @(
            @("# Decisions`n`nThe loop tested well with five players.`n", $false, 'has no verdict line', 'evidence but no verdict line'),
            @("# Decisions`n`nEvidence: 5 of 6 players asked for another run.`n`nVerdict: (owner to write: PROCEED, PIVOT or KILL)`n", $false, 'line 5 is still a placeholder', "Slay the Brick's placeholder"),
            @("Verdict: PROCEED, PIVOT or KILL`n", $false, 'line 1 is still a placeholder', "the template's wording"),
            @("Verdict: PROCEED / PIVOT / KILL`n", $false, 'still a placeholder', 'a slash-separated list'),
            @("<!--`nVerdict: PROCEED`n-->`nVerdict: TBD`n", $false, 'line 4 is still a placeholder', 'a verdict inside a comment, with the line numbers kept'),
            @("``````text`nVerdict: KILL`n``````n", $false, 'has no verdict line', 'a verdict inside a code block'),
            @("# Decisions`n`nVerdict: PIVOT`n", $true, '^Verdict: PIVOT \(docs/DECISIONS.md line 3\)$', 'a plain verdict line'),
            @("**Verdict:** proceed`n", $true, '^Verdict: PROCEED', 'bold, lower case'),
            @("- Verdict: Kill - nobody played twice`n", $true, '^Verdict: KILL', 'a list item with a reason'),
            @("## Verdict: Proceed, though we may pivot the art`n", $true, '^Verdict: PROCEED', 'a heading whose reason names another word'),
            @("Verdict: (owner to write)`n`nVerdict: PROCEED`n", $true, 'line 3', 'a placeholder, then the real line'))) {
        Set-Content -LiteralPath $decisions -Value $case[0] -NoNewline
        $v = Get-VerdictGate $verdictInfo 'docs/DECISIONS.md'
        Assert-True ($v.met -eq $case[1] -and $v.detail -match $case[2]) "verdict, $($case[3]): $($v.detail)"
    }
    Assert-True ((Test-PlanGate $verdictGate $verdictInfo) -eq $true) 'Test-PlanGate answers the verdict check'
    $known = @(Get-PlanProblems ([pscustomobject]@{ phases = @([pscustomobject]@{ id = 'p'; gates = @($verdictGate) }); tasks = @() }))
    Assert-True (@($known | Where-Object { $_ -match 'unknown check' }).Count -eq 0) 'verdict:<path> is a known check'
    $plan = [pscustomobject]@{ wipLimit = 3; tasks = @(); phases = @(
            [pscustomobject]@{ id = 'prototype'; name = 'Prototype'; goal = 'g'; gates = @([pscustomobject]@{ id = 'prototype.verdict'; text = 't'; check = 'verdict:docs/DECISIONS.md' }) }) }
    Set-Content -LiteralPath $decisions -Value "Verdict: (owner to write: PROCEED, PIVOT or KILL)`n" -NoNewline
    $state = Get-PlanState $plan $verdictInfo
    $gate = @($state.phases[0].gates)[0]
    Assert-True ($gate.done -eq $false -and $gate.detail -match 'still a placeholder' -and $state.current.id -eq 'prototype') "the placeholder holds the prototype open, and the gate's detail says why: $($gate.detail)"
    $plan.phases[0].gates[0].check = 'file:docs/DECISIONS.md'
    $state = Get-PlanState $plan $verdictInfo
    Assert-True (@($state.warnings | Where-Object { $_ -match "Gate 'prototype.verdict' passes on any text in docs/DECISIONS.md" -and $_ -match 'verdict:docs/DECISIONS.md' }).Count -eq 1) 'a plan made before is warned to use verdict:docs/DECISIONS.md'
} finally {
    Remove-Item -LiteralPath $verdictDir -Recurse -Force -ErrorAction SilentlyContinue
}

try {
    New-Item -ItemType Directory -Force $dir | Out-Null
    Set-Content -LiteralPath (Join-Path $dir 'project.godot') -Value "config_version=5`n`n[application]`n`nconfig/name=""Plan Fixture""`n"
    pwsh -NoProfile -NonInteractive -File $ci plan -Do init -Project $dir 2>$null | Out-Null
    $planPath = Join-Path $dir 'plan/plan.json'
    Assert-True (Test-Path -LiteralPath $planPath) 'plan -Do init writes plan/plan.json'

    $fresh = Get-Content -LiteralPath $planPath -Raw

    # The concept phase: concept.risks wants a docs/RISKS.md with something in it (an empty file is not a risk log), and
    # the optional concept.budget does not hold the phase back.
    $d = Invoke-PlanJson @()
    $risks = @($d.nextActions) | Where-Object id -eq 'concept.risks'
    $budgetGate = @($d.nextActions) | Where-Object id -eq 'concept.budget'
    Assert-True ($d.ok -and $d.currentPhase.id -eq 'concept' -and $risks -and $risks.auto -and $risks.check -eq 'file:docs/RISKS.md' -and -not $risks.optional) 'concept.risks is open and checked automatically from docs/RISKS.md'
    Assert-True ($budgetGate -and $budgetGate.optional -eq $true -and $budgetGate.check -eq 'file:docs/BUDGET.md') 'concept.budget is optional and checked from docs/BUDGET.md'
    New-Item -ItemType Directory -Force (Join-Path $dir 'docs') | Out-Null
    Set-Content -LiteralPath (Join-Path $dir 'docs/RISKS.md') -Value "  `n"
    $d = Invoke-PlanJson @()
    Assert-True ($d.ok -and 'concept.risks' -in @($d.nextActions | ForEach-Object id)) 'an empty docs/RISKS.md leaves concept.risks open'
    Set-Content -LiteralPath (Join-Path $dir 'docs/RISKS.md') -Value "| Risk | Likelihood | Impact | Retired by |`n|---|---|---|---|`n| Netcode never built | high | high | prototype week 2 |"
    Set-Content -LiteralPath (Join-Path $dir 'docs/GDD.md') -Value "# Plan Fixture`n"
    foreach ($gate in 'concept.scope', 'concept.decisions', 'concept.market', 'concept.name', 'concept.kill') { Invoke-PlanJson @('-Do', 'done', '-Id', $gate) | Out-Null }
    $d = Invoke-PlanJson @()
    $concept = @($d.phases) | Where-Object id -eq 'concept'
    Assert-True ($d.ok -and $concept.complete -and $d.currentPhase.id -eq 'prototype') "with every other concept gate met, the open concept.budget does not hold the phase back: $(if ($d.ok) { $d.currentPhase.id } else { $d.error.message })"
    $refused = Invoke-PlanJson @('-Do', 'done', '-Id', 'concept.risks')
    Assert-True (-not $refused.ok -and $refused.error.code -eq 'auto-gate') 'plan -Do done refuses concept.risks (auto-gate)'
    Remove-Item -LiteralPath (Join-Path $dir 'docs') -Recurse -Force
    Set-Content -LiteralPath $planPath -Value $fresh -Encoding utf8

    # The prototype phase: concept dropped from this copy, so the prototype is the current phase.
    $plan = $fresh | ConvertFrom-Json -Depth 10
    $plan.phases = @($plan.phases | Where-Object id -eq 'prototype')
    $plan | ConvertTo-Json -Depth 10 | Set-Content -LiteralPath $planPath -Encoding utf8
    $d = Invoke-PlanJson @()
    $next = @($d.nextActions)
    $ids = @($next | ForEach-Object id)
    $trailerGate = $next | Where-Object id -eq 'prototype.trailer'
    Assert-True ($d.ok -and $d.currentPhase.id -eq 'prototype') 'the prototype is the current phase'
    Assert-True ($trailerGate -and $trailerGate.auto -and $trailerGate.check -eq 'file:docs/TRAILER.md') 'prototype.trailer is open and checked automatically from docs/TRAILER.md'
    Assert-True ($trailerGate -and $trailerGate.text -match 'genre' -and $trailerGate.text -match 'hook' -and
        $trailerGate.text -match 'standout moments' -and $trailerGate.text -match 'on-screen feedback') 'prototype.trailer names genre, hook, standout moments and on-screen feedback'
    Assert-True ($trailerGate -and [array]::IndexOf($ids, 'prototype.trailer') -lt [array]::IndexOf($ids, 'prototype.loop') -and
        [array]::IndexOf($ids, 'prototype.trailer') -lt [array]::IndexOf($ids, 'prototype.verdict')) 'the trailer is written before the loop is built and before the verdict'
    $refused = Invoke-PlanJson @('-Do', 'done', '-Id', 'prototype.trailer')
    Assert-True (-not $refused.ok -and $refused.error.code -eq 'auto-gate') 'plan -Do done refuses prototype.trailer (auto-gate)'
    New-Item -ItemType Directory -Force (Join-Path $dir 'docs') | Out-Null
    if ($trailer) { Set-Content -LiteralPath (Join-Path $dir 'docs/TRAILER.md') -Value $trailer.Replace('{{GAME}}', 'Plan Fixture') }
    $d = Invoke-PlanJson @()
    Assert-True ($d.ok -and 'prototype.trailer' -notin @($d.nextActions | ForEach-Object id)) 'prototype.trailer is done once docs/TRAILER.md exists'

    # Earlier phases are the user's to finish; dropping them from this copy makes the slice the current phase.
    $plan = $fresh | ConvertFrom-Json -Depth 10
    $plan.phases = @($plan.phases | Where-Object id -eq 'vertical-slice')
    $plan | ConvertTo-Json -Depth 10 | Set-Content -LiteralPath $planPath -Encoding utf8

    $d = Invoke-PlanJson @()
    $next = @($d.nextActions)
    $ids = @($next | ForEach-Object id)
    $debt = $next | Where-Object id -eq 'slice.debt'
    $budget = $next | Where-Object id -eq 'slice.budget'
    $verdict = $next | Where-Object id -eq 'slice.verdict'
    Assert-True ($d.ok -and $d.currentPhase.id -eq 'vertical-slice') 'the vertical slice is the current phase'
    Assert-True ($debt -and $debt.auto -and $debt.check -eq 'file:docs/TECH-DEBT.md') 'slice.debt is open and checked automatically from docs/TECH-DEBT.md'
    Assert-True ($budget -and -not $budget.auto -and $budget.text -match 'bench -Scene \S+.* -BudgetMs ' -and $budget.text -match 'level of detail') 'slice.budget is manual and names bench -Scene ... -BudgetMs at production density'
    Assert-True ($verdict -and $verdict.text -match 'tech demo' -and $verdict.text -match 'tech debt') 'slice.verdict weighs the experience and the tech debt'
    Assert-True ([array]::IndexOf($ids, 'slice.debt') -lt [array]::IndexOf($ids, 'slice.verdict') -and
        [array]::IndexOf($ids, 'slice.budget') -lt [array]::IndexOf($ids, 'slice.verdict')) 'the debt and budget gates come before the verdict'

    $refused = Invoke-PlanJson @('-Do', 'done', '-Id', 'slice.debt')
    Assert-True (-not $refused.ok -and $refused.error.code -eq 'auto-gate') 'plan -Do done refuses slice.debt (auto-gate)'

    New-Item -ItemType Directory -Force (Join-Path $dir 'docs') | Out-Null
    Copy-Item -LiteralPath (Join-Path $templates 'TECH-DEBT.md') (Join-Path $dir 'docs/TECH-DEBT.md')
    $doneBefore = @($d.phases)[0].gatesDone
    $d = Invoke-PlanJson @()
    Assert-True ($d.ok -and 'slice.debt' -notin @($d.nextActions | ForEach-Object id) -and @($d.phases)[0].gatesDone -eq $doneBefore + 1) 'slice.debt is done once docs/TECH-DEBT.md exists'

    $d = Invoke-PlanJson @('-Do', 'done', '-Id', 'slice.budget')
    Assert-True ($d.ok -and 'slice.budget' -notin @($d.nextActions | ForEach-Object id)) 'slice.budget is marked done by hand'

    # plan -Do reopen undoes done for a manual gate; an automatic gate, an unknown gate and a missing -Id are refused.
    $d = Invoke-PlanJson @('-Do', 'reopen', '-Id', 'slice.budget')
    Assert-True ($d.ok -and 'slice.budget' -in @($d.nextActions | ForEach-Object id)) 'plan -Do reopen opens slice.budget again'
    $gate = @((Get-Content -LiteralPath $planPath -Raw | ConvertFrom-Json).phases.gates | Where-Object id -eq 'slice.budget')[0]
    Assert-True (-not $gate.PSObject.Properties['done']) 'and plan.json no longer marks it done'
    $d = Invoke-PlanJson @('-Do', 'reopen', '-Id', 'slice.budget')
    Assert-True ($d.ok -and 'slice.budget' -in @($d.nextActions | ForEach-Object id)) 'reopening an open gate changes nothing'
    foreach ($case in @(@('slice.debt', 'auto-gate'), @('no.such.gate', 'unknown-gate'), @('', 'invalid-arguments'))) {
        $refused = Invoke-PlanJson @('-Do', 'reopen', '-Id', $case[0])
        Assert-True (-not $refused.ok -and $refused.error.code -eq $case[1]) "plan -Do reopen -Id '$($case[0])' fails with $($case[1]): $(if (-not $refused.ok) { $refused.error.code })"
    }
    $d = Invoke-PlanJson @('-Do', 'done', '-Id', 'slice.budget')
    Assert-True ($d.ok -and 'slice.budget' -notin @($d.nextActions | ForEach-Object id)) 'and it can be marked done again'

    # plan -Json reports the release timeline; five days out with no other date, the app fee is flagged and the date locked.
    Assert-True ($null -eq $d.release) 'a plan without a release date reports no release'
    $plan = Get-Content -LiteralPath $planPath -Raw | ConvertFrom-Json -Depth 10
    $plan.release.date = [datetime]::UtcNow.Date.AddDays(5).ToString('yyyy-MM-dd', [cultureinfo]::InvariantCulture)
    $plan | ConvertTo-Json -Depth 10 | Set-Content -LiteralPath $planPath -Encoding utf8
    $d = Invoke-PlanJson @()
    Assert-True ($d.ok -and $d.release.daysLeft -eq 5 -and $d.release.dateLocked -eq $true -and $d.release.deadlines.steamFee) "plan -Json reports the release: $($d.release | ConvertTo-Json -Depth 10 -Compress)"
    Assert-True (@($d.warnings | Where-Object { $_ -match 'release\.steamFeePaid is not set' }).Count -eq 1) "plan warns that the app fee is not recorded five days before release: $($d.warnings -join ' | ')"

    # The tests gate and doctor's test check count test frameworks only: data tables and flows are checks, not tests.
    Set-Content -LiteralPath (Join-Path $dir 'data.json') -Value '{}'
    Set-Content -LiteralPath (Join-Path $dir 'start.flow.json') -Value '{ "steps": [] }'
    $d = Invoke-PlanJson @()
    Assert-True ($d.ok -and 'slice.tests' -in @($d.nextActions | ForEach-Object id)) 'slice.tests stays open with only the data and flows runners'
    $doctor = pwsh -NoProfile -NonInteractive -File $ci doctor -Json -Project $dir 2>$null | ConvertFrom-Json
    Assert-True (@($doctor.checks | Where-Object { $_.status -eq 'WARN' -and $_.message -match '^No tests found' }).Count -eq 1) "doctor warns that there are no tests: $(@($doctor.checks | Where-Object { $_.message -match 'test' } | ForEach-Object message) -join ' | ')"
    Set-Content -LiteralPath (Join-Path $dir 'test_paddle.gd') -Value "extends GutTest`n`nfunc test_paddle():`n`tassert_true(true)`n"
    $d = Invoke-PlanJson @()
    Assert-True ($d.ok -and 'slice.tests' -notin @($d.nextActions | ForEach-Object id)) 'slice.tests is done once a GUT test exists'

    # beta.placeholders: open while nothing says what is left (no TECH-DEBT.md, no assets.json), while the Placeholders
    # table of docs/TECH-DEBT.md has a row, or while an assets.json entry is "placeholder": true.
    $plan = $fresh | ConvertFrom-Json -Depth 10
    $plan.phases = @($plan.phases | Where-Object id -eq 'alpha-beta')
    $plan | ConvertTo-Json -Depth 10 | Set-Content -LiteralPath $planPath -Encoding utf8
    Remove-Item -LiteralPath (Join-Path $dir 'docs/TECH-DEBT.md') -Force
    $placeholderOpen = { param($Doc) $Doc.ok -and 'beta.placeholders' -in @($Doc.nextActions | ForEach-Object id) }
    $d = Invoke-PlanJson @()
    $gate = @($d.nextActions) | Where-Object id -eq 'beta.placeholders'
    Assert-True ((& $placeholderOpen $d) -and $gate.auto -and $gate.check -eq 'placeholders') 'beta.placeholders is automatic and open with neither docs/TECH-DEBT.md nor assets.json'
    $debtText = (Get-Content -LiteralPath (Join-Path $templates 'TECH-DEBT.md') -Raw).Replace('{{GAME}}', 'Plan Fixture')
    Set-Content -LiteralPath (Join-Path $dir 'docs/TECH-DEBT.md') -Value $debtText
    $d = Invoke-PlanJson @()
    Assert-True ($d.ok -and -not (& $placeholderOpen $d)) 'the template TECH-DEBT.md, whose Placeholders table is empty, meets beta.placeholders'
    $withRow = $debtText.Replace("|---|---|---|---|`n| | | | |", "|---|---|---|---|`n| art/boss.png | the final boss sprite | me | M3 |").Replace("|---|---|---|---|`r`n| | | | |", "|---|---|---|---|`r`n| art/boss.png | the final boss sprite | me | M3 |")
    Set-Content -LiteralPath (Join-Path $dir 'docs/TECH-DEBT.md') -Value $withRow
    $d = Invoke-PlanJson @()
    Assert-True ($withRow -ne $debtText -and (& $placeholderOpen $d)) 'a row in the Placeholders table opens it'
    Set-Content -LiteralPath (Join-Path $dir 'docs/TECH-DEBT.md') -Value $debtText
    Set-Content -LiteralPath (Join-Path $dir 'assets.json') -Value '{ "assets": [ { "path": "art/boss.png", "source": "own", "licence": "proprietary", "placeholder": true } ] }'
    $d = Invoke-PlanJson @()
    Assert-True (& $placeholderOpen $d) 'an assets.json entry marked "placeholder": true opens it'
    Set-Content -LiteralPath (Join-Path $dir 'assets.json') -Value '{ "assets": [ { "path": "art/boss.png", "source": "own", "licence": "proprietary", "placeholder": false } ] }'
    $d = Invoke-PlanJson @()
    Assert-True ($d.ok -and -not (& $placeholderOpen $d)) 'with "placeholder": false it is met again'
} finally {
    Remove-Item -LiteralPath $dir -Recurse -Force -ErrorAction SilentlyContinue
}

# plan -Do init -Profile jam: phases sized in days, with the jam's gates; a day over the timebox warns in days.
$jam = Join-Path ([IO.Path]::GetTempPath()) "plan-jam-$([guid]::NewGuid().ToString('N').Substring(0, 8))"
try {
    New-Item -ItemType Directory -Force $jam | Out-Null
    Set-Content -LiteralPath (Join-Path $jam 'project.godot') -Value "config_version=5`n`n[application]`n`nconfig/name=""Jam""`n"
    $d = pwsh -NoProfile -NonInteractive -File $ci plan -Do init -Profile jam -Json -Project $jam 2>$null | ConvertFrom-Json
    $jamPath = Join-Path $jam 'plan/plan.json'
    $jamPlan = Get-Content -LiteralPath $jamPath -Raw | ConvertFrom-Json -Depth 10
    Assert-True ($d.ok -and $jamPlan.profile -eq 'jam' -and $jamPlan.game -eq 'Jam') 'plan -Do init -Profile jam writes a jam plan'
    $days = @($jamPlan.phases | ForEach-Object { if ($_.PSObject.Properties['timeboxDays']) { [double]$_.timeboxDays } })
    Assert-True ($days.Count -eq @($jamPlan.phases).Count -and @($jamPlan.phases | Where-Object { $_.PSObject.Properties['timeboxWeeks'] }).Count -eq 0) "every jam phase is sized in days: $($days -join ', ')"
    $sum = ($days | Select-Object -First 4 | Measure-Object -Sum).Sum
    Assert-True ($sum -ge 2 -and $sum -le 9) "the jam itself (all but the last phase) fits a 2- to 9-day jam: $sum days"
    $d = pwsh -NoProfile -NonInteractive -File $ci plan -Json -Project $jam 2>$null | ConvertFrom-Json
    $ids = @($d.nextActions | ForEach-Object id)
    Assert-True ($d.ok -and $d.currentPhase.id -eq 'jam-concept' -and $d.currentPhase.timeboxDays -eq 1 -and $null -ne $d.currentPhase.elapsedDays) "the jam starts in jam-concept, 1 day: $(if ($d.ok) { $d.currentPhase | ConvertTo-Json -Depth 10 -Compress } else { $d.error.message })"
    Assert-True ($ids.Count -gt 0 -and $ids[0] -eq 'jam.platform' -and 'jam.gdd' -in $ids) "'browser build?' comes first, then the jam GDD: $($ids -join ', ')"
    Assert-True ((Get-Content -LiteralPath (Join-Path $jam 'plan/PLAN.md') -Raw) -match '## Theme and core feel \(current, 1 day\)') 'PLAN.md sizes the phase in days'
    $jamPlan.phases[0].startedAt = [datetime]::UtcNow.AddDays(-2).ToString('o')
    $jamPlan | ConvertTo-Json -Depth 10 | Set-Content -LiteralPath $jamPath -Encoding utf8
    $d = pwsh -NoProfile -NonInteractive -File $ci plan -Json -Project $jam 2>$null | ConvertFrom-Json
    Assert-True ($d.ok -and @($d.warnings | Where-Object { $_ -match "is 2 days in, over its 1-day timebox" }).Count -eq 1) "two days into a one-day phase warns in days: $($d.warnings -join ' | ')"
    $d = pwsh -NoProfile -NonInteractive -File $ci plan -Do init -Json -Project $jam 2>$null | ConvertFrom-Json
    Assert-True ($d.ok -and (Get-Content -LiteralPath $jamPath -Raw | ConvertFrom-Json).profile -eq 'jam') 'init again leaves the jam plan as it is'
} finally {
    Remove-Item -LiteralPath $jam -Recurse -Force -ErrorAction SilentlyContinue
}

# A day-first culture (Greek here) must read the phase's start time back: it once failed with "String '10/23/2026
# 05:57:27' was not recognized as a valid DateTime" on every plan command after init.
$culture = Join-Path ([IO.Path]::GetTempPath()) "plan-culture-$([guid]::NewGuid().ToString('N').Substring(0, 8))"
try {
    New-Item -ItemType Directory -Force $culture | Out-Null
    Set-Content -LiteralPath (Join-Path $culture 'project.godot') -Value "config_version=5`n`n[application]`n`nconfig/name=""Culture""`n"
    $command = "[cultureinfo]::CurrentCulture = 'el-GR'; & '$ci' plan -Do init -Project '$culture' *> `$null; & '$ci' plan -Do add -Title Task -Json -Project '$culture' 2>`$null"
    $added = pwsh -NoProfile -NonInteractive -Command $command | ConvertFrom-Json
    Assert-True ($added.ok) 'plan reads its start time back under a day-first culture (el-GR)'
    Assert-True ((ConvertTo-UtcTime ([datetime]::new(2026, 10, 23, 5, 57, 27, [DateTimeKind]::Utc))) -eq [datetime]::new(2026, 10, 23, 5, 57, 27, [DateTimeKind]::Utc) -and
        (ConvertTo-UtcTime '2026-10-23T05:57:27.0000000Z') -eq [datetime]::new(2026, 10, 23, 5, 57, 27, [DateTimeKind]::Utc)) 'ConvertTo-UtcTime keeps a UTC DateTime and reads an ISO string as the same instant'
} finally {
    Remove-Item -LiteralPath $culture -Recurse -Force -ErrorAction SilentlyContinue
}

# A hand-broken plan: plan fails with invalid-plan (not unexpected-error), and status, which never fails on what it finds,
# warns and reports plan as null.
$broken = Join-Path ([IO.Path]::GetTempPath()) "plan-broken-$([guid]::NewGuid().ToString('N').Substring(0, 8))"
try {
    New-Item -ItemType Directory -Force $broken | Out-Null
    Set-Content -LiteralPath (Join-Path $broken 'project.godot') -Value "config_version=5`n`n[application]`n`nconfig/name=""Broken""`n"
    pwsh -NoProfile -NonInteractive -File $ci plan -Do init -Project $broken 2>$null | Out-Null
    $brokenPath = Join-Path $broken 'plan/plan.json'
    $good = Get-Content -LiteralPath $brokenPath -Raw
    $noWip = $good | ConvertFrom-Json -Depth 10
    $noWip.PSObject.Properties.Remove('wipLimit')
    $badCheck = $good | ConvertFrom-Json -Depth 10
    $badCheck.phases[0].gates[1] | Add-Member -NotePropertyName check -NotePropertyValue 'files:docs/x.md' -Force
    foreach ($case in @(@('no wipLimit', ($noWip | ConvertTo-Json -Depth 10), 'wipLimit'), @('an unknown check', ($badCheck | ConvertTo-Json -Depth 10), 'files:docs/x\.md'),
            @('broken JSON', '{ "phases": [', 'not valid JSON'))) {
        Set-Content -LiteralPath $brokenPath -Value $case[1] -Encoding utf8
        $d = pwsh -NoProfile -NonInteractive -File $ci plan -Json -Project $broken 2>$null | ConvertFrom-Json
        Assert-True (-not $d.ok -and $d.error.code -eq 'invalid-plan' -and $d.error.message -match $case[2]) "plan with $($case[0]) fails with invalid-plan: $($d.error.code) $($d.error.message)"
        $s = pwsh -NoProfile -NonInteractive -File $ci status -Json -Project $broken 2>$null | ConvertFrom-Json
        Assert-True ($s.ok -and $null -eq $s.plan -and @($s.warnings | Where-Object { $_ -match 'cannot be read' -and $_ -match $case[2] }).Count -eq 1) "status with $($case[0]) warns and reports no plan: $(if ($s.ok) { $s.warnings -join ' | ' } else { $s.error.message })"
    }

    # A plan.json with no "tasks" is a plan with none: plan, plan -Do add and status work, and add creates the list.
    $noTasks = $good | ConvertFrom-Json -Depth 10
    $noTasks.PSObject.Properties.Remove('tasks')
    Set-Content -LiteralPath $brokenPath -Value ($noTasks | ConvertTo-Json -Depth 10) -Encoding utf8
    $d = pwsh -NoProfile -NonInteractive -File $ci plan -Json -Project $broken 2>$null | ConvertFrom-Json
    Assert-True ($d.ok -and @($d.tasks).Count -eq 0) "plan with no tasks property works: $(if ($d.ok) { 'ok' } else { $d.error.message })"
    $s = pwsh -NoProfile -NonInteractive -File $ci status -Json -Project $broken 2>$null | ConvertFrom-Json
    Assert-True ($s.ok -and $null -ne $s.plan) "status with no tasks property reads the plan: $(if ($s.ok) { $s.warnings -join ' | ' } else { $s.error.message })"
    $d = pwsh -NoProfile -NonInteractive -File $ci plan -Do add -Title 'First task' -Json -Project $broken 2>$null | ConvertFrom-Json
    Assert-True ($d.ok) "plan -Do add on a plan with no tasks property works: $(if ($d.ok) { 'ok' } else { $d.error.message })"
    $after = Get-Content -LiteralPath $brokenPath -Raw | ConvertFrom-Json -Depth 10
    Assert-True (@($after.tasks).Count -eq 1 -and $after.tasks[0].title -eq 'First task') 'add created the tasks list'
} finally {
    Remove-Item -LiteralPath $broken -Recurse -Force -ErrorAction SilentlyContinue
}

# The plan names the game as its project does: "My Game" stays "My Game" (the file-name slug is My-Game), and a name with
# no ASCII letters is not emptied.
foreach ($gameName in 'My Game', 'ゲーム') {
    $named = Join-Path ([IO.Path]::GetTempPath()) "plan-name-$([guid]::NewGuid().ToString('N').Substring(0, 8))"
    try {
        New-Item -ItemType Directory -Force $named | Out-Null
        Set-Content -LiteralPath (Join-Path $named 'project.godot') -Value "config_version=5`n`n[application]`n`nconfig/name=""$gameName""`n" -Encoding utf8
        pwsh -NoProfile -NonInteractive -File $ci plan -Do init -Project $named 2>$null | Out-Null
        $namedPlan = Get-Content -LiteralPath (Join-Path $named 'plan/plan.json') -Raw | ConvertFrom-Json -Depth 10
        $title = (Get-Content -LiteralPath (Join-Path $named 'plan/PLAN.md') -TotalCount 1)
        Assert-True ($namedPlan.game -eq $gameName -and $title -eq "# $gameName plan") "plan.game keeps the project's name '$gameName': '$($namedPlan.game)', $title"
    } finally {
        Remove-Item -LiteralPath $named -Recurse -Force -ErrorAction SilentlyContinue
    }
}

# init sets up the project the plan's gates check: it adds a starter test, but never over a file the user already has
# (here a test of that name that extends GUT's script by path, so it is not found as a GutTest).
$starter = Join-Path ([IO.Path]::GetTempPath()) "plan-init-$([guid]::NewGuid().ToString('N').Substring(0, 8))"
try {
    New-Item -ItemType Directory -Force (Join-Path $starter 'test') | Out-Null
    Set-Content -LiteralPath (Join-Path $starter 'project.godot') -Value "config_version=5`n`n[application]`n`nconfig/name=""Starter""`n"
    $mine = "extends ""res://addons/gut/test.gd""`n`nfunc test_mine():`n`tassert_true(true)`n"
    Set-Content -LiteralPath (Join-Path $starter 'test/test_example.gd') -Value $mine -NoNewline
    & git -C $starter init -q
    $d = pwsh -NoProfile -NonInteractive -File $ci init -Json -Project $starter 2>$null | ConvertFrom-Json
    Assert-True ((Get-Content -LiteralPath (Join-Path $starter 'test/test_example.gd') -Raw) -ceq $mine) 'init leaves an existing test/test_example.gd as it was'
    Assert-True (@($d.steps | Where-Object { $_.status -eq 'skipped' -and $_.message -match 'test_example\.gd exists' }).Count -eq 1) "init says it skipped it: $(@($d.steps | ForEach-Object message) -join ' | ')"
    # The workflow init writes calls the kit's moving v1 tag, not main, so a kit change reaches a game only with a release.
    $workflow = Get-Content -LiteralPath (Join-Path $starter '.github/workflows/hyperdot.yml') -Raw
    Assert-True ($workflow -match 'uses: nick-vas/hyperdot/\.github/workflows/godot\.yml@v1\s' -and $workflow -notmatch '@main') 'init pins the workflow at @v1'
    # Runs on pull requests and on pushes to main (the merge check, and the caches pull requests read), both without
    # document-only changes: a private repository pays for every run.
    $on = [regex]::Match($workflow, '(?ms)^on:\r?\n(?<body>.*?)^\S').Groups['body'].Value
    $triggers = @([regex]::Matches($on, '(?m)^  (?<name>[a-z_]+):') | ForEach-Object { $_.Groups['name'].Value })
    Assert-True (($triggers -join ',') -eq 'push,pull_request,workflow_dispatch') "the workflow runs on push, pull_request and workflow_dispatch: $($triggers -join ',')"
    Assert-True ($on -match '(?m)^  push:\r?\n    branches: \[main\]\r?\n    paths-ignore:') 'a push runs only on main, with paths-ignore'
    foreach ($ignored in "'docs/**'", "'plan/**'", "'**/*.md'", "'.gitignore'") {
        Assert-True ([regex]::Matches($on, "(?m)^      - $([regex]::Escape($ignored))\r?$").Count -eq 2) "push and pull_request both ignore $ignored"
    }
    # With the agent files comes docs/kit-notes.md, where the agent notes each time the kit got in the way; never overwritten.
    pwsh -NoProfile -NonInteractive -File $ci init -Plugin -Project $starter 2>$null | Out-Null
    $notes = Join-Path $starter 'docs/kit-notes.md'
    Assert-True ((Test-Path -LiteralPath $notes) -and (Get-Content -LiteralPath $notes -Raw) -match '# Kit notes') 'init -Plugin writes docs/kit-notes.md'
    Add-Content -LiteralPath $notes -Value '2026-10-23 test: a note'
    $again = pwsh -NoProfile -NonInteractive -File $ci init -Plugin -Json -Project $starter 2>$null | ConvertFrom-Json
    Assert-True ((Get-Content -LiteralPath $notes -Raw) -match 'a note' -and @($again.steps | Where-Object { $_.message -match 'kit-notes\.md exists' }).Count -eq 1) 'a second init keeps the notes'
    # docs/kit-help.md is not written: the page would be a copy that goes stale; `help` and /kit write .godot/kit-help.md. A copy an older init left is named.
    $kitHelp = Join-Path $starter 'docs/kit-help.md'
    Assert-True (-not (Test-Path -LiteralPath $kitHelp)) 'init writes no docs/kit-help.md'
    Set-Content -LiteralPath $kitHelp -Value 'an older copy'
    $third = pwsh -NoProfile -NonInteractive -File $ci init -Plugin -Json -Project $starter 2>$null | ConvertFrom-Json
    Assert-True ((Get-Content -LiteralPath $kitHelp -Raw).Trim() -eq 'an older copy' -and @($third.steps | Where-Object { $_.message -match 'kit-help\.md is a copy' }).Count -eq 1) 'init names an old docs/kit-help.md and leaves it'
    # The skills come from the plugin, never from copies: -Agents (and the older -Plugin) enable it from GitHub, write no skill or subagent
    # into the game, and -PluginSource local registers this kit's folder instead.
    $kitFolder = (Split-Path (Split-Path (Split-Path $ci -Parent) -Parent) -Parent) -replace '\\', '/'
    $readSettings = { param($Game) Get-Content -LiteralPath (Join-Path $Game '.claude/settings.json') -Raw | ConvertFrom-Json -AsHashtable }
    $newGame = { param($Name) $g = Join-Path ([System.IO.Path]::GetTempPath()) "$Name-$PID"; New-Item -ItemType Directory -Force $g | Out-Null
        Copy-Item -LiteralPath (Join-Path $PSScriptRoot '../examples/gdscript/project.godot'), (Join-Path $PSScriptRoot '../examples/gdscript/main.gd'), (Join-Path $PSScriptRoot '../examples/gdscript/main.tscn'), (Join-Path $PSScriptRoot '../examples/gdscript/score.gd') -Destination $g; $g }
    $agentsGame = & $newGame 'init-agents'
    try {
        $env:HYPERDOT_KIT_REPO = $null
        pwsh -NoProfile -NonInteractive -File $ci init -Agents -Project $agentsGame 2>$null | Out-Null
        $settings = & $readSettings $agentsGame
        $source = $settings.extraKnownMarketplaces['hyperdot'].source
        Assert-True ($source.source -eq 'github' -and $source.repo -eq 'nick-vas/hyperdot' -and $settings.enabledPlugins['hyperdot@hyperdot'] -eq $true) "init -Agents enables the plugin from GitHub: $($settings | ConvertTo-Json -Depth 6 -Compress)"
        Assert-True (-not (Test-Path -LiteralPath (Join-Path $agentsGame '.claude/skills')) -and -not (Test-Path -LiteralPath (Join-Path $agentsGame '.agents/skills')) -and -not (Test-Path -LiteralPath (Join-Path $agentsGame '.claude/agents'))) 'init -Agents copies no skill or subagent'
        Assert-True ((Test-Path -LiteralPath (Join-Path $agentsGame 'AGENTS.md')) -and (Test-Path -LiteralPath (Join-Path $agentsGame 'docs/kit-notes.md'))) 'init -Agents still writes AGENTS.md and the kit notes'
        # The kit outside the game (issue 314): AGENTS.md runs it from HYPERDOT_KIT, names no path of this machine (it is shared),
        # and says how the variable is set in bash and in PowerShell; this machine's path goes to .claude/settings.local.json,
        # which git ignores, so Claude Code has the variable here.
        $agentsText = Get-Content -LiteralPath (Join-Path $agentsGame 'AGENTS.md') -Raw
        Assert-True ($agentsText.Contains('pwsh "$HYPERDOT_KIT/ci/godot/hyperdot.ps1" test -Json -Quiet') -and $agentsText.Contains('$env:HYPERDOT_KIT') -and -not $agentsText.Contains($kitFolder) -and -not $agentsText.Contains('{{')) "init -Agents with the kit outside the game writes `$HYPERDOT_KIT, not this machine's path: $($agentsText.Substring(0, [Math]::Min(600, $agentsText.Length)))"
        $localSettings = Get-Content -LiteralPath (Join-Path $agentsGame '.claude/settings.local.json') -Raw | ConvertFrom-Json -AsHashtable
        Assert-True ($localSettings.env.HYPERDOT_KIT -eq $kitFolder) "init sets HYPERDOT_KIT in .claude/settings.local.json: $($localSettings | ConvertTo-Json -Compress -Depth 4)"
        Assert-True ((Get-Content -LiteralPath (Join-Path $agentsGame '.gitignore')) -contains '.claude/settings.local.json') 'init keeps .claude/settings.local.json out of git'
        # doctor: an INFO while the variable is unset or points elsewhere, OK when it points at a kit.
        $doctorKit = { param([string]$Value)
            $saved = $env:HYPERDOT_KIT; $env:HYPERDOT_KIT = $Value
            try { @((pwsh -NoProfile -NonInteractive -File $ci doctor -Json -Project $agentsGame 2>$null | Out-String | ConvertFrom-Json).checks | Where-Object { $_.message -match 'HYPERDOT_KIT' } | ForEach-Object { "$($_.status) $($_.message)" }) }
            finally { $env:HYPERDOT_KIT = $saved } }
        $unset = @(& $doctorKit '')
        Assert-True ($unset.Count -eq 1 -and $unset[0] -match '^INFO .*not set') "doctor says HYPERDOT_KIT is not set: $($unset -join ' | ')"
        $wrong = @(& $doctorKit (Join-Path $agentsGame 'nowhere'))
        Assert-True ($wrong.Count -eq 1 -and $wrong[0] -match '^INFO .*has no ci/godot/hyperdot.ps1') "doctor says HYPERDOT_KIT points at no kit: $($wrong -join ' | ')"
        $right = @(& $doctorKit $kitFolder)
        Assert-True ($right.Count -eq 1 -and $right[0] -match '^OK HYPERDOT_KIT points at the kit') "doctor says HYPERDOT_KIT points at the kit: $($right -join ' | ')"
        # The kit inside the game's repository (a submodule): a relative path, no HYPERDOT_KIT line and no local settings.
        $insideGame = & $newGame 'init-inside'
        New-Item -ItemType Directory -Force (Join-Path $insideGame 'tools/hyperdot') | Out-Null
        Copy-Item -LiteralPath (Join-Path $PSScriptRoot '../ci') -Destination (Join-Path $insideGame 'tools/hyperdot') -Recurse
        pwsh -NoProfile -NonInteractive -File (Join-Path $insideGame 'tools/hyperdot/ci/godot/hyperdot.ps1') init -Agents -Project $insideGame 2>$null | Out-Null
        $insideText = Get-Content -LiteralPath (Join-Path $insideGame 'AGENTS.md') -Raw
        Assert-True ($insideText.Contains('pwsh tools/hyperdot/ci/godot/hyperdot.ps1 test -Json -Quiet') -and -not $insideText.Contains('HYPERDOT_KIT') -and -not $insideText.Contains('{{') -and -not (Test-Path -LiteralPath (Join-Path $insideGame '.claude/settings.local.json'))) "init -Agents with the kit inside the game writes its relative path: $($insideText.Substring(0, [Math]::Min(600, $insideText.Length)))"
        Remove-Item -LiteralPath $insideGame -Recurse -Force
        # A fork's repository, by environment.
        $forkGame = & $newGame 'init-fork'
        $env:HYPERDOT_KIT_REPO = 'someone/hyperdot-fork'
        pwsh -NoProfile -NonInteractive -File $ci init -Agents -Project $forkGame 2>$null | Out-Null
        $env:HYPERDOT_KIT_REPO = $null
        Assert-True ((& $readSettings $forkGame).extraKnownMarketplaces['hyperdot'].source.repo -eq 'someone/hyperdot-fork') 'HYPERDOT_KIT_REPO names the repository of a fork'
        Remove-Item -LiteralPath $forkGame -Recurse -Force
        # A game on the local folder keeps it unless -PluginSource says otherwise (then the old file is kept as .bak).
        $localGame = & $newGame 'init-local'
        pwsh -NoProfile -NonInteractive -File $ci init -Agents -PluginSource local -Project $localGame 2>$null | Out-Null
        $local = (& $readSettings $localGame).extraKnownMarketplaces['hyperdot'].source
        Assert-True ($local.source -eq 'directory' -and $local.path -eq $kitFolder) "-PluginSource local registers this kit's folder: $($local | ConvertTo-Json -Compress -Depth 4)"
        $kept = pwsh -NoProfile -NonInteractive -File $ci init -Agents -Json -Project $localGame 2>$null | ConvertFrom-Json
        Assert-True ((& $readSettings $localGame).extraKnownMarketplaces['hyperdot'].source.source -eq 'directory' -and @($kept.steps | Where-Object { $_.message -match 'already enables the hyperdot plugin \(from directory; -PluginSource github switches it\)' }).Count -eq 1) 'a game on the local folder keeps it without -PluginSource'
        pwsh -NoProfile -NonInteractive -File $ci init -Agents -PluginSource github -Project $localGame 2>$null | Out-Null
        Assert-True ((& $readSettings $localGame).extraKnownMarketplaces['hyperdot'].source.source -eq 'github' -and (Test-Path -LiteralPath (Join-Path $localGame '.claude/settings.json.bak'))) '-PluginSource github switches it and keeps a .bak'
        Remove-Item -LiteralPath $localGame -Recurse -Force
        # -CopySkills copies for a host without plugins, and never into a game that enables the plugin.
        $copyGame = & $newGame 'init-copy'
        pwsh -NoProfile -NonInteractive -File $ci init -Agents -CopySkills -Project $copyGame 2>$null | Out-Null
        Assert-True ((Test-Path -LiteralPath (Join-Path $copyGame '.claude/skills/game/SKILL.md')) -and (Test-Path -LiteralPath (Join-Path $copyGame '.agents/skills/game/SKILL.md')) -and (Test-Path -LiteralPath (Join-Path $copyGame '.claude/agents/godot-verifier.md')) -and -not (Test-Path -LiteralPath (Join-Path $copyGame '.claude/settings.json'))) 'init -Agents -CopySkills copies the skills and subagents and enables no plugin'
        # The copies name the kit by HYPERDOT_KIT too, never by this machine's path.
        $copied = @(Get-ChildItem -LiteralPath (Join-Path $copyGame '.claude') -Recurse -File -Filter '*.md' | Where-Object { (Get-Content -LiteralPath $_.FullName -Raw).Contains($kitFolder) } | ForEach-Object Name)
        $viaKit = (Get-Content -LiteralPath (Join-Path $copyGame '.claude/agents/godot-verifier.md') -Raw).Contains('$HYPERDOT_KIT/ci/godot/hyperdot.ps1')
        Assert-True ($copied.Count -eq 0 -and $viaKit) "-CopySkills copies name the kit by `$HYPERDOT_KIT (this machine's path in: $($copied -join ', '))"
        Remove-Item -LiteralPath $copyGame -Recurse -Force
        $refused = pwsh -NoProfile -NonInteractive -File $ci init -Agents -CopySkills -Json -Project $agentsGame 2>$null | ConvertFrom-Json
        Assert-True (-not (Test-Path -LiteralPath (Join-Path $agentsGame '.claude/skills')) -and @($refused.steps | Where-Object { $_.message -match 'already enables the hyperdot plugin, which supplies them' }).Count -eq 1) '-CopySkills copies nothing into a game that enables the plugin'
        # The flags belong to init.
        $bad = pwsh -NoProfile -NonInteractive -File $ci doctor -CopySkills -Json -Project $agentsGame 2>$null | ConvertFrom-Json
        Assert-True ($bad.error.code -eq 'invalid-arguments') '-CopySkills with another command is refused'
    } finally {
        $env:HYPERDOT_KIT_REPO = $null
        Remove-Item -LiteralPath $agentsGame -Recurse -Force -ErrorAction SilentlyContinue
    }
} finally {
    Remove-Item -LiteralPath $starter -Recurse -Force -ErrorAction SilentlyContinue
}

# status reads the GDD's first session: each numbered step is S<n>; a GDD:S<n> tag in a flow or playthrough.json plays it,
# one in a *.stub.json only stubs it (and a stub never counts as a feature's test); steps with neither, and tags for a step
# the GDD lacks, are warnings once the GDD is confirmed.
$session = Join-Path ([IO.Path]::GetTempPath()) "plan-session-$([guid]::NewGuid().ToString('N').Substring(0, 8))"
try {
    New-Item -ItemType Directory -Force (Join-Path $session 'docs'), (Join-Path $session 'test/flows') | Out-Null
    Set-Content -LiteralPath (Join-Path $session 'project.godot') -Value "config_version=5`n`n[application]`n`nconfig/name=""Session""`n"
    $gddText = (Get-Content -LiteralPath (Join-Path $templates 'GDD.md') -Raw).Replace('{{GAME}}', 'Session') -replace '(?s)<!-- Status: draft\..*?-->', ''
    $gddText = $gddText -replace '(?ms)^1\. The player starts the game and sees\.\.\.\r?\n2\. The player presses\.\.\.\r?\n3\.\r?\n',
        "1. The title screen shows Play and Quit.`n2. Play starts level 1 with the hero at the door.`n3. Reaching the exit shows the score.`n"
    Set-Content -LiteralPath (Join-Path $session 'docs/GDD.md') -Value $gddText
    Set-Content -LiteralPath (Join-Path $session 'test/flows/title.flow.json') -Value '{ "name": "GDD:S1 the title screen", "scene": "res://title.tscn", "steps": [] }'
    Set-Content -LiteralPath (Join-Path $session 'test/flows/first_session_s2.stub.json') -Value "{ `"name`": `"GDD:S2 GDD:F1 level 1 starts`",`n  `"scene`": `"res://title.tscn`", `"steps`": [] }"
    Set-Content -LiteralPath (Join-Path $session 'playthrough.stub.json') -Value '{ "covers": ["GDD:S2", "GDD:S7"], "expect": ["[Run] ending reached"] }'
    $s = pwsh -NoProfile -NonInteractive -File $ci status -Json -Project $session 2>$null | ConvertFrom-Json
    $steps = @($s.gdd.firstSession)
    Assert-True ($s.ok -and -not $s.gdd.draft -and ($steps.id -join ',') -eq 'S1,S2,S3' -and $steps[1].text -eq 'Play starts level 1 with the hero at the door.') "status lists the GDD's first-session steps: $(@($steps | ForEach-Object { "$($_.id)=$($_.text)" }) -join ' | ')"
    Assert-True (@($steps[0].tests).Count -eq 1 -and $steps[0].tests[0].file -eq 'test/flows/title.flow.json' -and @($steps[0].stubs).Count -eq 0) 'a flow tagged GDD:S1 plays step S1'
    Assert-True (@($steps[1].tests).Count -eq 0 -and (@($steps[1].stubs.file) -join ',') -eq 'playthrough.stub.json,test/flows/first_session_s2.stub.json') "S2 has only stubs: $(@($steps[1].stubs.file) -join ',')"
    $f1 = @($s.features | Where-Object id -eq 'F1')
    Assert-True ($f1.Count -eq 1 -and @($f1[0].taggedTests).Count -eq 0) 'a stub tagged GDD:F1 is not a test of F1'
    Assert-True (@($s.warnings | Where-Object { $_ -match '^First-session step\(s\) S3 have no flow' }).Count -eq 1) "a step with neither is a warning: $($s.warnings -join ' | ')"
    Assert-True (@($s.warnings | Where-Object { $_ -match 'GDD:S7 is tagged' }).Count -eq 1 -and @($s.warnings | Where-Object { $_ -match 'GDD:S\d is tagged in tests but not in the GDD' }).Count -eq 0) 'a tag for a step the GDD lacks is a warning of its own'
    # A draft GDD (the template as copied) lists the template's two example steps and warns about none of them.
    Set-Content -LiteralPath (Join-Path $session 'docs/GDD.md') -Value (Get-Content -LiteralPath (Join-Path $templates 'GDD.md') -Raw)
    $s = pwsh -NoProfile -NonInteractive -File $ci status -Json -Project $session 2>$null | ConvertFrom-Json
    Assert-True ($s.gdd.draft -and @($s.gdd.firstSession).Count -eq 2 -and @($s.warnings | Where-Object { $_ -match '^First-session' }).Count -eq 0) "a draft GDD's steps are listed without warnings: $(@($s.gdd.firstSession).Count)"
} finally {
    Remove-Item -LiteralPath $session -Recurse -Force -ErrorAction SilentlyContinue
}

# plan -Do move takes several ids in one call (each call starts the kit and reads the project): all move, or none does.
$multi = Join-Path ([IO.Path]::GetTempPath()) "plan-multi-$([guid]::NewGuid().ToString('N').Substring(0, 8))"
try {
    New-Item -ItemType Directory -Force $multi | Out-Null
    Set-Content -LiteralPath (Join-Path $multi 'project.godot') -Value "config_version=5`n`n[application]`n`nconfig/name=`"Multi`"`n"
    pwsh -NoProfile -NonInteractive -File $ci plan -Do init -Project $multi *> $null
    $ids = @(foreach ($n in 1..4) { (pwsh -NoProfile -NonInteractive -File $ci plan -Do add -Title "Task $n" -Json -Project $multi 2>$null | ConvertFrom-Json).task.id })
    $d = pwsh -NoProfile -NonInteractive -File $ci plan -Do move -Id ($ids[0..2] -join ',') -Column done -Json -Project $multi 2>$null | ConvertFrom-Json
    Assert-True ($d.ok -and @($d.movedTasks).Count -eq 3 -and @($d.movedTasks | Where-Object column -ne 'done').Count -eq 0 -and $d.task.id -eq $ids[0]) "plan -Do move -Id t1,t2,t3 moves all three in one call: $(if ($d.ok) { 'ok' } else { $d.error.message })"
    Assert-True (@($d.tasks | Where-Object { $_.column -eq 'done' }).Count -eq 3 -and ($d.tasks | Where-Object id -eq $ids[3]).column -eq 'backlog') 'the fourth task stays where it was'
    $d = pwsh -NoProfile -NonInteractive -File $ci plan -Do move -Id "$($ids[3]),t999" -Column todo -Json -Project $multi 2>$null | ConvertFrom-Json
    $after = pwsh -NoProfile -NonInteractive -File $ci plan -Json -Project $multi 2>$null | ConvertFrom-Json
    Assert-True (-not $d.ok -and $d.error.code -eq 'unknown-task' -and ($after.tasks | Where-Object id -eq $ids[3]).column -eq 'backlog') 'an unknown id in the list refuses the whole move (unknown-task) and moves none'
    $limit = (Get-Content -LiteralPath (Join-Path $multi 'plan/plan.json') -Raw | ConvertFrom-Json).wipLimit
    $d = pwsh -NoProfile -NonInteractive -File $ci plan -Do move -Id ($ids -join ',') -Column doing -Json -Project $multi 2>$null | ConvertFrom-Json
    $after = pwsh -NoProfile -NonInteractive -File $ci plan -Json -Project $multi 2>$null | ConvertFrom-Json
    Assert-True ($ids.Count -gt $limit -and -not $d.ok -and $d.error.code -eq 'wip-limit' -and @($after.tasks | Where-Object { $_.column -eq 'doing' }).Count -eq 0) "more tasks than the work-in-progress limit ($limit) is refused as a whole (wip-limit)"
} finally {
    Remove-Item -LiteralPath $multi -Recurse -Force -ErrorAction SilentlyContinue
}

# -TimeoutSec: a git or gh that hangs costs the limit, not the run. A fake git and gh that sleep stand in for an editor holding git and a hung GitHub call
# (a shell script, so not on Windows). status and a plain plan print what they gathered, with "partial" naming each step that was skipped and what it waited
# for; plan -Do sync stops with command-timeout and names the call; -TimeoutSec on another command is refused.
if (-not $IsWindows) {
    $slow = Join-Path ([IO.Path]::GetTempPath()) "plan-slow-$([guid]::NewGuid().ToString('N').Substring(0, 8))"
    $hang = Join-Path ([IO.Path]::GetTempPath()) "plan-hang-$([guid]::NewGuid().ToString('N').Substring(0, 8))"
    $savedPath = $env:PATH
    try {
        New-Item -ItemType Directory -Force $slow, $hang | Out-Null
        Set-Content -LiteralPath (Join-Path $hang 'project.godot') -Value "config_version=5`n`n[application]`n`nconfig/name=`"Hang`"`n"
        pwsh -NoProfile -NonInteractive -File $ci plan -Do init -Project $hang *> $null
        # Real git first, for the repository the project is in; then fakes that never answer.
        & git -C $hang init -q
        foreach ($name in 'git', 'gh') {
            Set-Content -LiteralPath (Join-Path $slow $name) -Value "#!/bin/sh`nexec sleep 60`n"
            & chmod +x (Join-Path $slow $name)
        }
        $env:PATH = "$slow$([IO.Path]::PathSeparator)$env:PATH"
        $clock = [System.Diagnostics.Stopwatch]::StartNew()
        $st = pwsh -NoProfile -NonInteractive -File $ci status -Json -TimeoutSec 3 -Project $hang 2>$null | ConvertFrom-Json
        $took = $clock.Elapsed.TotalSeconds
        Assert-True ($st.ok -and $st.partial -and $st.partial.reason -eq 'timeout' -and $st.partial.timeoutSec -eq 3 -and @($st.partial.skipped).Count -ge 1 -and @($st.partial.skipped | Where-Object waitingOn -like 'git *').Count -ge 1) "status with a git that never answers still returns, with partial naming what it waited for: $(@($st.partial.skipped | ForEach-Object { "$($_.step) <- $($_.waitingOn)" }) -join '; ')"
        Assert-True ($took -lt 40) "status with a 3 s limit returned in $([math]::Round($took, 1)) s, not after the fake git's 60 s"
        Assert-True ($null -ne $st.plan -and $null -ne $st.warnings) 'what was gathered without git (the plan, the warnings) is still in the result'
        $pl = pwsh -NoProfile -NonInteractive -File $ci plan -Json -TimeoutSec 3 -Project $hang 2>$null | ConvertFrom-Json
        Assert-True ($pl.ok -and $pl.partial -and $pl.partial.timeoutSec -eq 3) 'a plain plan reports the same partial result'
        $env:PATH = $savedPath
        $sy = pwsh -NoProfile -NonInteractive -File $ci status -Json -Project $hang 2>$null | ConvertFrom-Json
        Assert-True ($sy.ok -and $null -eq $sy.partial) 'without a hang there is no partial field value'
        $env:PATH = "$slow$([IO.Path]::PathSeparator)$env:PATH"
        $sync = pwsh -NoProfile -NonInteractive -File $ci plan -Do sync -Board 'someone/1' -TimeoutSec 3 -Json -Project $hang 2>$null | ConvertFrom-Json
        Assert-True (-not $sync.ok -and $sync.error.code -eq 'command-timeout' -and $sync.error.message -match 'gh project') "plan -Do sync with a gh that never answers stops with command-timeout naming the call: $($sync.error.message)"
    } finally {
        $env:PATH = $savedPath
        Remove-Item -LiteralPath $slow, $hang -Recurse -Force -ErrorAction SilentlyContinue
    }
    $other = pwsh -NoProfile -NonInteractive -File $ci doctor -Json -TimeoutSec 5 -Project $dir 2>$null | ConvertFrom-Json
    Assert-True (-not $other.ok -and $other.error.code -eq 'invalid-arguments' -and $other.error.message -match 'is for plan, status, not doctor') '-TimeoutSec on another command is refused (invalid-arguments)'
}

if ($failures.Count) { throw "$($failures.Count) plan check(s) failed" }
Write-Host 'plan self-test passed'
# One kit run failed on purpose (the refused gate); GitHub's pwsh wrapper would exit with its code.
exit 0
