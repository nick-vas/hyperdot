# `plan`: an A-to-Z plan for one developer. plan/plan.json holds phases, each with gates. A gate is either
# checked automatically from the project ("check": "tests", "ci", "preset", "export-run", "file:<path>", "verdict:<path>", "runner:<name>",
# "placeholders") or marked done by hand ("manual"). A gate with "optional": true does not hold its phase back. `plan`
# reports the current phase, what blocks it, and warns when a phase overruns its timebox or too many tasks are in progress.

function Get-PlanPath($Info) {
    $root = Get-GitRoot $Info.ProjectDir
    return Join-Path ($root ? $root : $Info.ProjectDir) 'plan/plan.json'
}

function Read-Plan([string]$Path) {
    if (-not (Test-Path -LiteralPath $Path)) { Stop-GodotCi "No plan at $Path. Run: $(Format-KitCommand 'plan -Do init')" 'no-plan' }
    try { $plan = Get-Content -LiteralPath $Path -Raw | ConvertFrom-Json -Depth 10 }
    catch { Stop-GodotCi "$Path is not valid JSON: $($_.Exception.Message)" 'invalid-plan' }
    $problems = @(Get-PlanProblems $plan)
    if ($problems.Count) { Stop-GodotCi "${Path}: $($problems -join '; ')" 'invalid-plan' }
    Add-PlanDefaults $plan
    return $plan
}

# A plan without a "tasks" list has no tasks: give it the (empty) list, so reading and adding work, and plan -Do add saves it.
function Add-PlanDefaults($Plan) {
    if (-not $Plan.PSObject.Properties['tasks'] -or $null -eq $Plan.tasks) { $Plan | Add-Member -NotePropertyName tasks -NotePropertyValue @() -Force }
}

# What would stop the plan being read, as messages: `plan` fails with invalid-plan on them, `status` reports them as a
# warning (it never fails on what it finds). Hand edits are what break a plan, so only what the kit reads is checked.
function Get-PlanProblems($Plan) {
    if ($null -eq $Plan -or $Plan.PSObject.BaseObject -isnot [System.Management.Automation.PSCustomObject]) { return @('it is not a JSON object') }
    $problems = [System.Collections.Generic.List[string]]::new()
    $wip = $Plan.PSObject.Properties['wipLimit']
    if (-not $wip -or -not ($wip.Value -is [int] -or $wip.Value -is [long]) -or $wip.Value -lt 1) {
        $problems.Add('wipLimit must be a whole number of tasks, 1 or more (the template has 2)')
    }
    if (-not $Plan.PSObject.Properties['phases']) { $problems.Add('it has no phases') }
    foreach ($phase in @($Plan.PSObject.Properties['phases'] ? $Plan.phases : @())) {
        if ($phase -isnot [pscustomobject] -or -not $phase.PSObject.Properties['id'] -or -not $phase.PSObject.Properties['gates']) { $problems.Add('a phase has no id or no gates'); continue }
        foreach ($gate in @($phase.gates)) {
            if ($gate -isnot [pscustomobject] -or -not $gate.PSObject.Properties['id']) { $problems.Add("a gate of phase '$($phase.id)' has no id"); continue }
            $check = $gate.PSObject.Properties['check'] ? "$($gate.check)" : 'manual'
            if ($check -notmatch '^(manual|tests|preset|export-run|ci|placeholders|runner:[a-z0-9]+|file:.+|verdict:.+)$') {
                $problems.Add("gate '$($gate.id)' has an unknown check '$check' (use manual, tests, preset, export-run, ci, placeholders, file:<path>, verdict:<path>, runner:<name>)")
            }
        }
    }
    foreach ($task in @($Plan.PSObject.Properties['tasks'] ? $Plan.tasks : @())) {
        if ($task -isnot [pscustomobject] -or -not $task.PSObject.Properties['id'] -or -not $task.PSObject.Properties['column']) { $problems.Add('a task has no id or no column') }
    }
    return @($problems)
}

function Save-Plan($Plan, [string]$Path) {
    $Plan | ConvertTo-Json -Depth 10 | Set-Content -LiteralPath $Path -Encoding utf8
}

# The runners of test frameworks. The others (validate, smoke, data, flows, l10n, ...) check the project, not its tests.
$script:TestFrameworkRunners = 'dotnet', 'gdunit4', 'godottest', 'gut'

# The export-run gate, from this machine's run history (.godot/hyperdot-history.jsonl): for every preset this machine
# can launch (its own desktop platform, and Web in a browser), the newest export -Run that included it passed and
# launched it. -Run skips the presets it cannot launch, so an export that launched nothing proves nothing. met is false
# with no preset at all, and $null when no preset can be launched here (the gate is then marked by hand, plan -Do
# done); detail says why it is not met,
# or when the oldest of the passing runs was.
function Get-ExportRunGate($Info) {
    $details = Get-ExportPresetDetails $Info.ProjectDir
    if ($details.Count -eq 0) { return [ordered]@{ met = $false; detail = 'No export preset yet: add one in Project > Export, then run export -Run'; lastGood = $null } }
    $runnable = @($details.Keys | Where-Object { $details[$_].Platform -eq 'Web' -or (Test-CanRunPlatform $details[$_].Platform) })
    if ($runnable.Count -eq 0) {
        $platforms = @($details.Values | ForEach-Object { $_.Platform } | Where-Object { $_ } | Select-Object -Unique)
        return [ordered]@{ met = $null; detail = "Not checked here: this machine can launch none of the presets ($($platforms -join ', ')). Run export -Run where one can be launched, then $(Format-KitCommand 'plan -Do done -Id <gate>')"; lastGood = $null }
    }
    $runs = @(Read-RunHistory $Info.ProjectDir | Where-Object { $_.command -eq 'export' -and $_.PSObject.Properties['run'] -and $_.run -eq $true })
    [array]::Reverse($runs)
    $format = { param($Time) ([datetime]$Time).ToUniversalTime().ToString('yyyy-MM-dd HH:mm', [cultureinfo]::InvariantCulture) + ' UTC' }
    $never = [System.Collections.Generic.List[string]]::new()
    $failed = [System.Collections.Generic.List[string]]::new()
    $good = [System.Collections.Generic.List[object]]::new()
    $open = [System.Collections.Generic.List[string]]::new()
    foreach ($name in $runnable) {
        $last = @($runs | Where-Object { $_.PSObject.Properties['presets'] -and @($_.presets) -contains $name } | Select-Object -First 1)
        if ($last.Count -eq 0) { $never.Add($name); $open.Add($name); continue }
        $run = $last[0]
        $launched = $run.PSObject.Properties['launched'] -and @($run.launched) -contains $name
        if ($run.ok -and $launched) { $good.Add($run); continue }
        $why = if (-not $run.ok) { "failed$(if ($run.code) { " ($($run.code))" })" } else { 'was not launched' }
        $failed.Add("'$name' $why on $(& $format $run.time)")
        $open.Add($name)
    }
    if ($never.Count -eq 0 -and $failed.Count -eq 0) {
        $oldest = @($good | Sort-Object { [datetime]$_.time } | Select-Object -First 1)[0]
        $commit = if ($oldest.PSObject.Properties['commit'] -and $oldest.commit) { " at $($oldest.commit)" } else { '' }
        return [ordered]@{ met = $true; detail = "Every preset this machine can launch passed export -Run ($($runnable -join ', ')); the oldest of those runs was on $(& $format $oldest.time)$commit"; lastGood = (& $format $oldest.time) }
    }
    $parts = @(
        if ($failed.Count) { "the newest export -Run of $($failed -join '; ')" }
        if ($never.Count) { "never launched here: $($never -join ', ')" })
    $text = $parts -join '; '
    $command = Format-KitCommand ('export -Run -Preset "' + ($open -join ',') + '"')
    return [ordered]@{ met = $false; detail = "$($text.Substring(0, 1).ToUpperInvariant())$($text.Substring(1)). Run: $command"; lastGood = $null }
}

# The verdict gate: the file (looked up from the repository root, then the Godot project, as file:) holds a line that
# records one verdict, "Verdict: PROCEED", "PIVOT" or "KILL", any case, as a list item, heading or in bold too. A line
# listing them ("Verdict: PROCEED, PIVOT or KILL") or with anything else before the word ("Verdict: (owner to write:
# ...)") is a placeholder, and HTML comments and fenced code blocks are not read. detail says what was found.
function Get-VerdictGate($Info, [string]$Path) {
    $root = Split-Path (Split-Path (Get-PlanPath $Info))
    $file = @(foreach ($base in $root, $Info.ProjectDir) {
            $candidate = Join-Path $base $Path
            if (Test-Path -LiteralPath $candidate -PathType Leaf) { $candidate }
        }) | Select-Object -First 1
    $how = "write one line ""Verdict: PROCEED"", ""Verdict: PIVOT"" or ""Verdict: KILL"" (the user's decision)"
    if (-not $file) { return [ordered]@{ met = $false; detail = "$Path does not exist yet: $how" } }
    $text = [System.IO.File]::ReadAllText($file)
    # Comments and code blocks are blanked line for line, so the line numbers stay right.
    $blank = { param($m) [regex]::Replace($m.Value, '[^\r\n]', '') }
    $text = [regex]::Replace($text, '(?s)<!--.*?-->', $blank)
    $text = [regex]::Replace($text, '(?ms)^\s*(```|~~~).*?^\s*\1[^\r\n]*$', $blank)
    $lines = @($text -split '\r?\n')
    $placeholder = $null
    for ($i = 0; $i -lt $lines.Count; $i++) {
        if ($lines[$i] -notmatch '(?i)^\s*(?:[-*+]\s+|#+\s*)?[*_]*verdict[*_]*\s*:(?<rest>.*)$') { continue }
        # The verdict word first; a list of them right after it ("PROCEED, PIVOT or KILL", "PROCEED / PIVOT") is the template's
        # wording, not a decision. Later prose may name another ("PROCEED, though we may pivot the art").
        if ($Matches.rest -match '(?i)^[\s*_]*(?<v>proceed|pivot|kill)\b(?![\s*_]*(?:,|/|\bor\b)[\s*_]*(?:proceed|pivot|kill)\b)') {
            return [ordered]@{ met = $true; detail = "Verdict: $($Matches.v.ToUpperInvariant()) ($Path line $($i + 1))" }
        }
        if ($null -eq $placeholder) { $placeholder = $i + 1 }
    }
    $found = if ($placeholder) { "line $placeholder is still a placeholder" } else { 'it has no verdict line' }
    return [ordered]@{ met = $false; detail = "$Path exists, but $found`: $how" }
}

# True/false for gates the project can answer by itself; $null for manual gates.
function Test-PlanGate($Gate, $Info) {
    $check = $Gate.PSObject.Properties['check'] ? "$($Gate.check)" : 'manual'
    $root = Split-Path (Split-Path (Get-PlanPath $Info))
    switch -Regex ($check) {
        '^manual$' { return $null }
        '^tests$' { return @($Info.Runners | Where-Object { $_ -in $script:TestFrameworkRunners }).Count -gt 0 }
        '^preset$' { return $Info.Presets.Count -gt 0 }
        # The runner is set up for the project (detected or listed), so every CI run enforces it.
        '^runner:(?<runner>[a-z0-9]+)$' { return @($Info.Runners) -contains $Matches.runner }
        # A GitHub workflow that calls the kit's reusable workflow or composite action.
        '^ci$' {
            $files = @(Get-ChildItem -LiteralPath (Join-Path $root '.github/workflows') -File -ErrorAction SilentlyContinue)
            return @($files | Where-Object { (Get-Content -LiteralPath $_.FullName -Raw) -match '(hyperdot|Godot_TestSuite)/\.github/(workflows/godot\.yml|actions/godot)' }).Count -gt 0
        }
        # A folder, or a file with something in it: an empty docs/RISKS.md is not a risk log.
        '^file:(?<path>.+)$' {
            $path = $Matches.path
            foreach ($base in $root, $Info.ProjectDir) {
                foreach ($item in @(Get-Item -LiteralPath (Join-Path $base $path) -Force -ErrorAction SilentlyContinue)) {
                    if ($item -is [System.IO.DirectoryInfo]) { return $true }
                    if ([System.IO.File]::ReadAllText($item.FullName) -match '\S') { return $true }
                }
            }
            return $false
        }
        '^placeholders$' {
            $found = Get-PlanPlaceholders $root $Info.ProjectDir
            return $found.sources.Count -gt 0 -and $found.items.Count -eq 0
        }
        # Every preset this machine can launch passed its newest export -Run here; $null when it can launch none of them.
        '^export-run$' { return (Get-ExportRunGate $Info).met }
        # A line "Verdict: PROCEED" (or PIVOT, KILL) in the file, not a placeholder.
        '^verdict:(?<path>.+)$' { return (Get-VerdictGate $Info $Matches.path).met }
        default { Stop-GodotCi "Gate '$($Gate.id)' has an unknown check '$check' (use manual, tests, preset, export-run, ci, placeholders, file:<path>, verdict:<path>, runner:<name>)" 'invalid-plan' }
    }
}

# What is still a placeholder: assets.json entries with "placeholder": true (in the Godot project), and the filled rows
# of the Placeholders table in docs/TECH-DEBT.md (at the repository root or in the project). sources lists the files
# that exist; with none, nothing says what is left, so the placeholders gate stays open.
function Get-PlanPlaceholders([string]$Root, [string]$ProjectDir) {
    $sources = [System.Collections.Generic.List[string]]::new()
    $items = [System.Collections.Generic.List[string]]::new()
    $manifest = Join-Path $ProjectDir 'assets.json'
    if (Test-Path -LiteralPath $manifest -PathType Leaf) {
        $sources.Add($manifest)
        try {
            $doc = Get-Content -LiteralPath $manifest -Raw | ConvertFrom-Json -Depth 20
            $entries = ($doc -is [pscustomobject] -and $doc.PSObject.Properties['assets']) ? @($doc.assets) : @()
            foreach ($entry in $entries) {
                if ($entry -is [pscustomobject] -and $entry.PSObject.Properties['placeholder'] -and $entry.placeholder -eq $true) {
                    $items.Add("assets.json: $($entry.PSObject.Properties['path'] ? $entry.path : '(an entry with no path)')")
                }
            }
        } catch { $items.Add("assets.json cannot be read: $($_.Exception.Message)") }
    }
    foreach ($base in @($Root, $ProjectDir | Select-Object -Unique)) {
        $debt = Join-Path $base 'docs/TECH-DEBT.md'
        if (-not (Test-Path -LiteralPath $debt -PathType Leaf)) { continue }
        $sources.Add($debt)
        $section = [regex]::Match((Get-Content -LiteralPath $debt -Raw), '(?ms)^##\s+Placeholders\s*$(?<body>.*?)(?=^##\s|\z)')
        if (-not $section.Success) { continue }
        $rows = @([regex]::Matches($section.Groups['body'].Value, '(?m)^\s*\|(?<cells>.*)\|\s*$') | ForEach-Object { $_.Groups['cells'].Value })
        # The first row is the header, the second the |---| line.
        foreach ($row in @($rows | Select-Object -Skip 2)) {
            $first = ($row -split '\|')[0].Trim()
            if ($first) { $items.Add("docs/TECH-DEBT.md: $first") }
        }
        break
    }
    return [ordered]@{ sources = @($sources); items = @($items) }
}

# Weekdays from $From (counted) up to $To (not counted); public holidays are not known, so they count as business days.
function Get-BusinessDayCount([datetime]$From, [datetime]$To) {
    $count = 0
    for ($day = $From.Date; $day -lt $To.Date; $day = $day.AddDays(1)) {
        if ($day.DayOfWeek -notin [DayOfWeek]::Saturday, [DayOfWeek]::Sunday) { $count++ }
    }
    return $count
}

# The latest day from which $Count business days remain before $Date.
function Get-BusinessDayBefore([datetime]$Date, [int]$Count) {
    $day = $Date.Date
    $found = 0
    while ($found -lt $Count) {
        $day = $day.AddDays(-1)
        if ($day.DayOfWeek -notin [DayOfWeek]::Saturday, [DayOfWeek]::Sunday) { $found++ }
    }
    return $day
}

# Steam's release timeline from plan.json's optional "release" block, against the rules docs/store-and-legal.md and
# store-page quote (Steamworks pages read 2026-10-21): at least 21 days between paying the app fee and releasing,
# a Coming Soon page live at least 2 weeks before release, 3 to 5 business days per review so submit 7 business days
# ahead (the store page before the build), the release date locked 2 weeks before it, and a Next Fest demo submitted for
# review 3 weeks before the festival (5 for the press preview). Dates are yyyy-MM-dd. Only warnings: plans are advice.
$script:ReleaseDateFields = 'date', 'steamFeePaid', 'comingSoon', 'storePageSubmitted', 'buildSubmitted', 'nextFest', 'demoSubmitted'

# Steam's discounting rules (Steamworks "Discounting", read 2026-11-16; docs/store-and-legal.md): no discount for 30 days
# after release but the optional launch discount (10 to 40%, 7 to 14 days, set up before release); 30 days between the
# end of one discount and the start of the next; any discount 10 to 95% and 1 to 14 days. The four seasonal sales are
# exempt from the 30 days between discounts, both ways, but not from the 30 days after release: a game still in that
# cooldown joins a seasonal sale part-way, once it ends.
$script:SteamDiscountCooldownDays = 30
$script:SteamDiscountRules = @{ launchMin = 10; launchMax = 40; launchDaysMin = 7; launchDaysMax = 14; min = 10; max = 95; daysMin = 1; daysMax = 14 }

function ConvertTo-PlanDate($Value) {
    if ($null -eq $Value -or "$Value" -eq '') { return $null }
    if ($Value -is [datetime]) { return $Value.Date }
    $parsed = [datetime]::MinValue
    if ([datetime]::TryParseExact("$Value", 'yyyy-MM-dd', [cultureinfo]::InvariantCulture, [System.Globalization.DateTimeStyles]::None, [ref]$parsed)) { return $parsed.Date }
    return $null
}

function Test-PlanNumber($Value) { return $Value -is [int] -or $Value -is [long] -or $Value -is [double] -or $Value -is [decimal] }

# plan.json's release.launchDiscount ({ percent, days }) and release.discounts[] ({ name, start, end, percent, seasonal })
# against the rules above. A discount runs from its start day to its end day, and its length is end minus start (Valve's
# own example: a 7-day launch discount from November 15 to 22), so a 1-day discount ends the day after it starts.
# Warnings only. Returns the warnings and the discounts it could read (an entry it cannot read is left out of both the
# checks and calendar.ics).
function Get-PlannedDiscounts($Release, [datetime]$ReleaseDay) {
    $rules = $script:SteamDiscountRules
    $cooldown = $script:SteamDiscountCooldownDays
    $source = '(Steamworks discounting rules, docs/store-and-legal.md)'
    $format = { param([datetime]$Day) $Day.ToString('yyyy-MM-dd', [cultureinfo]::InvariantCulture) }
    $warnings = [System.Collections.Generic.List[string]]::new()
    $discounts = [System.Collections.Generic.List[object]]::new()
    $firstDay = $ReleaseDay.AddDays($cooldown)

    $launch = $Release.PSObject.Properties['launchDiscount'] ? $Release.launchDiscount : $null
    if ($null -ne $launch) {
        $percent = $launch.PSObject.Properties['percent'] ? $launch.percent : $null
        $days = $launch.PSObject.Properties['days'] ? $launch.days : $null
        if (-not (Test-PlanNumber $percent) -or -not (Test-PlanNumber $days) -or $days -lt 1 -or $days -gt 366 -or $days -ne [math]::Floor($days)) {
            $warnings.Add('release.launchDiscount needs a percent and a whole number of days, e.g. { "percent": 10, "days": 7 }; it was ignored.')
        } else {
            if ($percent -lt $rules.launchMin -or $percent -gt $rules.launchMax) { $warnings.Add("The launch discount is $percent%; Steam allows $($rules.launchMin) to $($rules.launchMax)% $source.") }
            if ($days -lt $rules.launchDaysMin -or $days -gt $rules.launchDaysMax) { $warnings.Add("The launch discount runs $days days; Steam allows $($rules.launchDaysMin) to $($rules.launchDaysMax) $source.") }
            $discounts.Add([pscustomobject]@{ name = 'the launch discount'; label = 'launch discount'; start = $ReleaseDay; end = $ReleaseDay.AddDays([int]$days); seasonal = $false; launch = $true; percent = $percent })
        }
    }

    $index = 0
    foreach ($entry in @($Release.PSObject.Properties['discounts'] ? $Release.discounts : @())) {
        $index++
        if ($null -eq $entry) { continue }
        $name = ($entry.PSObject.Properties['name'] -and $entry.name) ? "'$($entry.name)'" : "release.discounts[$index]"
        $start = ConvertTo-PlanDate ($entry.PSObject.Properties['start'] ? $entry.start : $null)
        $end = ConvertTo-PlanDate ($entry.PSObject.Properties['end'] ? $entry.end : $null)
        $percent = $entry.PSObject.Properties['percent'] ? $entry.percent : $null
        $seasonal = [bool]($entry.PSObject.Properties['seasonal'] -and $entry.seasonal -eq $true)
        if ($null -eq $start -or $null -eq $end -or -not (Test-PlanNumber $percent)) {
            $warnings.Add("The discount $name needs start and end dates (yyyy-MM-dd) and a percent; it was ignored.")
            continue
        }
        if ($end -le $start) { $warnings.Add("The discount $name ends ($(& $format $end)) on or before it starts ($(& $format $start)); it was ignored."); continue }
        if ($percent -lt $rules.min -or $percent -gt $rules.max) { $warnings.Add("The discount $name is $percent%; Steam allows $($rules.min) to $($rules.max)% $source.") }
        $length = [int]($end - $start).TotalDays
        if (-not $seasonal -and $length -gt $rules.daysMax) { $warnings.Add("The discount $name runs $length days; Steam allows $($rules.daysMin) to $($rules.daysMax) (a seasonal sale's own discount runs as long as the sale: mark it seasonal) $source.") }
        if ($start -lt $firstDay) {
            if ($seasonal -and $firstDay -ge $end) {
                $warnings.Add("The seasonal discount $name ($(& $format $start) to $(& $format $end)) ends before the $cooldown days after release do ($(& $format $firstDay)); the game cannot join that sale $source.")
            } elseif ($seasonal) {
                $warnings.Add("The seasonal discount $name starts on $(& $format $start), inside the $cooldown days after release; the game can join the sale only from $(& $format $firstDay), part-way through, and the discount cannot be entered before then $source.")
            } else {
                $warnings.Add("The discount $name starts on $(& $format $start), inside the $cooldown days after release (until $(& $format $firstDay)); only the launch discount may run then $source.")
            }
        }
        $discounts.Add([pscustomobject]@{ name = "the discount $name"; label = (($entry.PSObject.Properties['name'] -and $entry.name) ? "$($entry.name)" : "discount $index")
                start = $start; end = $end; seasonal = $seasonal; launch = $false; percent = $percent })
    }

    $sorted = @($discounts | Sort-Object start)
    for ($i = 0; $i -lt $sorted.Count; $i++) {
        for ($j = $i + 1; $j -lt $sorted.Count; $j++) {
            $a = $sorted[$i]; $b = $sorted[$j]
            if ($b.start -lt $a.end) {
                $warnings.Add("$($a.name.Substring(0, 1).ToUpperInvariant())$($a.name.Substring(1)) ($(& $format $a.start) to $(& $format $a.end)) and $($b.name) ($(& $format $b.start) to $(& $format $b.end)) overlap; a game has one discount at a time $source.")
            } elseif (-not $a.seasonal -and -not $b.seasonal) {
                $gap = [int]($b.start - $a.end).TotalDays
                if ($gap -lt $cooldown) { $warnings.Add("$($b.name.Substring(0, 1).ToUpperInvariant())$($b.name.Substring(1)) starts $gap days after $($a.name) ends ($(& $format $a.end)); Steam wants $cooldown days between discounts (seasonal sales are exempt) $source.") }
            }
        }
    }
    return [ordered]@{ warnings = @($warnings); discounts = @($sorted) }
}

function Get-DiscountScheduleWarnings($Release, [datetime]$ReleaseDay) { return @((Get-PlannedDiscounts $Release $ReleaseDay).warnings) }

function Get-ReleaseTimeline($Release, [datetime]$Today) {
    $warnings = [System.Collections.Generic.List[string]]::new()
    $notes = [System.Collections.Generic.List[string]]::new()
    $dates = @{}
    foreach ($name in $script:ReleaseDateFields) {
        $property = $Release.PSObject.Properties[$name]
        if (-not $property -or $null -eq $property.Value -or "$($property.Value)" -eq '') { continue }
        $parsed = ConvertTo-PlanDate $property.Value
        if ($null -ne $parsed) { $dates[$name] = $parsed }
        else { $warnings.Add("release.$name '$($property.Value)' is not a date (yyyy-MM-dd); it was ignored.") }
    }
    if (-not $dates.ContainsKey('date')) {
        return [ordered]@{ timeline = $null; warnings = @($warnings); notes = @($notes) }
    }
    $format = { param([datetime]$Day) $Day.ToString('yyyy-MM-dd', [cultureinfo]::InvariantCulture) }
    $today = $Today.Date
    $releaseDay = $dates['date']
    $daysLeft = [int]($releaseDay - $today).TotalDays
    $upcoming = $daysLeft -gt 0
    $source = '(Steamworks, docs/store-and-legal.md)'
    $deadlines = [ordered]@{
        steamFee = & $format $releaseDay.AddDays(-21)
        comingSoon = & $format $releaseDay.AddDays(-14)
        buildReview = & $format (Get-BusinessDayBefore $releaseDay 7)
        dateLock = & $format $releaseDay.AddDays(-14)
    }

    # The app fee: 21 days between paying and releasing.
    if ($dates.ContainsKey('steamFeePaid')) {
        $gap = [int]($releaseDay - $dates['steamFeePaid']).TotalDays
        if ($gap -lt 21) { $warnings.Add("Steam's app fee was paid on $(& $format $dates['steamFeePaid']), $gap days before release on $(& $format $releaseDay); Valve lists a wait of at least 21 days between paying and releasing for a first few titles (an established account may differ) $source.") }
    } elseif ($upcoming -and $daysLeft -lt 21) {
        $warnings.Add("Release is $daysLeft days away and release.steamFeePaid is not set; Steam needs at least 21 days between paying the app fee and releasing $source.")
    }

    # The Coming Soon page: live at least 2 weeks before release.
    if ($dates.ContainsKey('comingSoon')) {
        $gap = [int]($releaseDay - $dates['comingSoon']).TotalDays
        if ($gap -lt 14) { $warnings.Add("The Coming Soon page goes live on $(& $format $dates['comingSoon']), $gap days before release; Steam wants it live at least 2 weeks before $source.") }
    } elseif ($upcoming -and $daysLeft -lt 14) {
        $warnings.Add("Release is $daysLeft days away and release.comingSoon is not set; Steam wants the Coming Soon page live at least 2 weeks before release $source.")
    }

    # Reviews: 3 to 5 business days each, so submit 7 business days ahead; the store page before the build.
    if ($dates.ContainsKey('comingSoon')) {
        $comingSoon = $dates['comingSoon']
        $deadlines['storePageReview'] = & $format (Get-BusinessDayBefore $comingSoon 7)
        if ($dates.ContainsKey('storePageSubmitted')) {
            $lead = Get-BusinessDayCount $dates['storePageSubmitted'] $comingSoon
            if ($lead -lt 7) { $warnings.Add("The store page was submitted for review $lead business day(s) before its Coming Soon date ($(& $format $comingSoon)); a review takes 3 to 5 business days, so submit 7 ahead $source.") }
        } elseif ($comingSoon -gt $today) {
            $lead = Get-BusinessDayCount $today $comingSoon
            if ($lead -lt 7) { $warnings.Add("$lead business day(s) left before the Coming Soon date ($(& $format $comingSoon)) and release.storePageSubmitted is not set; a review takes 3 to 5 business days, so submit 7 ahead $source.") }
        }
    }
    if ($dates.ContainsKey('buildSubmitted')) {
        $lead = Get-BusinessDayCount $dates['buildSubmitted'] $releaseDay
        if ($lead -lt 7) { $warnings.Add("The build was submitted for review $lead business day(s) before release; a review takes 3 to 5 business days, so submit 7 ahead $source.") }
        if ($dates.ContainsKey('storePageSubmitted') -and $dates['buildSubmitted'] -lt $dates['storePageSubmitted']) {
            $warnings.Add("The build was submitted for review before the store page; Steam reviews the store page first $source.")
        }
    } elseif ($upcoming) {
        $lead = Get-BusinessDayCount $today $releaseDay
        if ($lead -lt 7) { $warnings.Add("$lead business day(s) left before release and release.buildSubmitted is not set; a review takes 3 to 5 business days, so submit 7 ahead $source.") }
    }

    # The release date is locked 2 weeks before it.
    $locked = $upcoming -and $daysLeft -le 14
    if ($locked) { $notes.Add("The release date ($(& $format $releaseDay)) is locked: Steam freezes it 2 weeks before release, and an approved game still goes out with the Release App button.") }

    # Steam Next Fest: the demo is submitted for review 3 weeks before the festival, 5 for the press preview.
    if ($dates.ContainsKey('nextFest')) {
        $fest = $dates['nextFest']
        $press = $Release.PSObject.Properties['pressPreview'] -and $Release.pressPreview -eq $true
        $weeks = $press ? 5 : 3
        $demoDeadline = $fest.AddDays(-7 * $weeks)
        $deadlines['demoReview'] = & $format $demoDeadline
        $which = $press ? ' with the press preview' : ''
        if ($dates.ContainsKey('demoSubmitted')) {
            if ($dates['demoSubmitted'] -gt $demoDeadline) { $warnings.Add("The Next Fest demo was submitted on $(& $format $dates['demoSubmitted']), after the $(& $format $demoDeadline) deadline ($weeks weeks before the festival$which) $source.") }
        } elseif ($today -gt $demoDeadline -and $today -lt $fest) {
            $warnings.Add("The Next Fest demo had to be submitted for review by $(& $format $demoDeadline) ($weeks weeks before the festival$which) and release.demoSubmitted is not set $source.")
        }
        if ($fest -ge $releaseDay) { $warnings.Add("Next Fest ($(& $format $fest)) is on or after release ($(& $format $releaseDay)); do the last Next Fest before launch (store-page).") }
    }

    # Discounts: the launch discount and the planned ones, against Steam's discounting rules.
    $deadlines['firstDiscount'] = & $format $releaseDay.AddDays($script:SteamDiscountCooldownDays)
    foreach ($warning in @(Get-DiscountScheduleWarnings $Release $releaseDay)) { $warnings.Add($warning) }

    $timeline = [ordered]@{ date = & $format $releaseDay; daysLeft = $daysLeft
        businessDaysLeft = ($upcoming ? (Get-BusinessDayCount $today $releaseDay) : 0); dateLocked = $locked; deadlines = $deadlines }
    return [ordered]@{ timeline = $timeline; warnings = @($warnings); notes = @($notes) }
}

function Get-PlanState($Plan, $Info, [datetime]$Today = [datetime]::UtcNow.Date) {
    $now = [datetime]::UtcNow
    $warnings = [System.Collections.Generic.List[string]]::new()
    $allPhases = @($Plan.phases)
    $exportRun = $null
    $phases = @(for ($index = 0; $index -lt $allPhases.Count; $index++) {
        $phase = $allPhases[$index]
        # A later phase has begun: this phase was finished once, so a gate read from the run history stays met.
        $laterStarted = @($allPhases | Select-Object -Skip ($index + 1) | Where-Object { $_.PSObject.Properties['startedAt'] -and $_.startedAt }).Count -gt 0
        $gates = @(foreach ($gate in $phase.gates) {
            $check = $gate.PSObject.Properties['check'] ? "$($gate.check)" : 'manual'
            $detail = $null
            if ($check -eq 'export-run') {
                if (-not $exportRun) { $exportRun = Get-ExportRunGate $Info }
                $auto = $exportRun.met
                $detail = $exportRun.detail
                # One failed export -Run while working on a later phase does not send the plan back to this one.
                if ($auto -eq $false -and $laterStarted) {
                    $warnings.Add("Gate '$($gate.id)' ($($phase.name)) no longer holds, but a later phase has begun, so it stays met: $detail")
                    $auto = $true
                }
            } elseif ($check -match '^verdict:(?<path>.+)$') {
                $verdict = Get-VerdictGate $Info $Matches.path
                $auto = $verdict.met
                $detail = $verdict.detail
            } else { $auto = Test-PlanGate $gate $Info }
            # Kit templates before verdict: passed prototype.verdict on any DECISIONS.md with text in it.
            if ($gate.id -eq 'prototype.verdict' -and $check -like 'file:*') {
                $warnings.Add("Gate 'prototype.verdict' passes on any text in $($check.Substring(5)), a placeholder included: set its ""check"" to ""verdict:$($check.Substring(5))"" in plan.json (it then holds once a line reads ""Verdict: PROCEED"", ""PIVOT"" or ""KILL"")")
            }
            # Kit templates before export-run checked only that a preset exists, which a failed export also passes.
            if ($check -eq 'preset' -and $gate.id -in 'slice.export', 'jam.export', 'launch.gold') {
                $warnings.Add("Gate '$($gate.id)' checks only that an export preset exists, but its text asks for export -Run: set its ""check"" to ""export-run"" in plan.json (it then holds once export -Run passes on this machine)")
            }
            $manual = $gate.PSObject.Properties['done'] -and $gate.done -eq $true
            [ordered]@{ id = $gate.id; text = $gate.text; check = $check
                done = ($null -ne $auto ? [bool]$auto : $manual) ; auto = ($null -ne $auto); detail = $detail
                optional = [bool]($gate.PSObject.Properties['optional'] -and $gate.optional -eq $true) }
        })
        # A phase is sized in weeks (timeboxWeeks) or, in a jam plan, in days (timeboxDays); both are reported.
        $byDays = [bool]$phase.PSObject.Properties['timeboxDays']
        $timeboxDays = $byDays ? [double]$phase.timeboxDays : ($phase.PSObject.Properties['timeboxWeeks'] ? [double]$phase.timeboxWeeks * 7 : $null)
        $timeboxWeeks = $phase.PSObject.Properties['timeboxWeeks'] ? $phase.timeboxWeeks : ($null -ne $timeboxDays ? [math]::Round($timeboxDays / 7, 2) : $null)
        [ordered]@{ id = $phase.id; name = $phase.name; goal = $phase.goal; timeboxWeeks = $timeboxWeeks; timeboxDays = $timeboxDays; byDays = $byDays
            startedAt = ($phase.PSObject.Properties['startedAt'] ? $phase.startedAt : $null)
            gates = $gates; complete = (@($gates | Where-Object { -not $_.done -and -not $_.optional }).Count -eq 0) }
    })
    $current = $phases | Where-Object { -not $_.complete } | Select-Object -First 1
    if ($current -and $current.startedAt) {
        $elapsed = ($now - (ConvertTo-UtcTime $current.startedAt)).TotalDays
        $weeks = [math]::Round($elapsed / 7, 1)
        $days = [math]::Round($elapsed, 1)
        $current['elapsedWeeks'] = $weeks
        $current['elapsedDays'] = $days
        if ($current.byDays -and $days -gt $current.timeboxDays) {
            $warnings.Add("Phase '$($current.name)' is $days days in, over its $($current.timeboxDays)-day timebox. Cut from the cut list, then the must-haves; don't cut testing or the time to submit.")
        } elseif (-not $current.byDays -and $null -ne $current.timeboxWeeks -and $weeks -gt $current.timeboxWeeks) {
            $warnings.Add("Phase '$($current.name)' is $weeks weeks in, over its $($current.timeboxWeeks)-week timebox. Cut scope or kill; don't cut testing.")
        }
    }
    $tasks = @($Plan.tasks)
    $inProgress = @($tasks | Where-Object { $_.column -eq 'doing' })
    if ($inProgress.Count -gt $Plan.wipLimit) {
        $warnings.Add("$($inProgress.Count) tasks are in 'doing' but the limit is $($Plan.wipLimit). Finish something before starting more.")
    }
    $board = [ordered]@{}
    foreach ($column in 'backlog', 'design', 'todo', 'doing', 'verify', 'done') {
        $board[$column] = @($tasks | Where-Object { $_.column -eq $column }).Count
    }
    $release = [ordered]@{ timeline = $null; warnings = @(); notes = @() }
    if ($Plan.PSObject.Properties['release'] -and $null -ne $Plan.release) { $release = Get-ReleaseTimeline $Plan.release $Today }
    foreach ($warning in $release.warnings) { $warnings.Add($warning) }
    return [ordered]@{ phases = $phases; current = $current; warnings = @($warnings); board = $board; wipLimit = $Plan.wipLimit
        release = $release.timeline; releaseNotes = $release.notes }
}

# plan/PLAN.md: the human-readable view, regenerated from plan.json (never edit it by hand).
function Write-PlanMarkdown($Plan, $State, [string]$Path) {
    $md = [System.Collections.Generic.List[string]]::new()
    $md.Add("# $($Plan.game ? $Plan.game : 'Game') plan"); $md.Add('')
    $md.Add('<!-- Generated from plan.json by `hyperdot.ps1 plan`. Edit plan.json, not this file. -->')
    if ($Plan.pitch) { $md.Add(''); $md.Add("> $($Plan.pitch)") }
    foreach ($phase in $State.phases) {
        $mark = $phase.complete ? 'done' : ($phase.id -eq $State.current.id ? 'current' : 'later')
        $size = $phase.byDays ? "$($phase.timeboxDays) day$(if ($phase.timeboxDays -ne 1) { 's' })" : "$($phase.timeboxWeeks) weeks"
        $md.Add(''); $md.Add("## $($phase.name) ($mark, $size)"); $md.Add(''); $md.Add("_$($phase.goal)_"); $md.Add('')
        foreach ($gate in $phase.gates) { $md.Add("- [$($gate.done ? 'x' : ' ')] $($gate.text)$($gate.auto ? ' _(auto)_' : '')$($gate.optional ? ' _(optional)_' : '')") }
    }
    $tasks = @($Plan.tasks)
    if ($tasks.Count -gt 0) {
        $md.Add(''); $md.Add('## Tasks')
        foreach ($column in 'doing', 'verify', 'todo', 'design', 'backlog', 'done') {
            $inColumn = @($tasks | Where-Object { $_.column -eq $column })
            if ($inColumn.Count -eq 0) { continue }
            $md.Add(''); $md.Add("**$column**")
            foreach ($task in $inColumn) { $md.Add("- $($task.id): $($task.title) _($($task.phase))_") }
        }
    }
    Set-Content -LiteralPath $Path -Value $md -Encoding utf8
}

$script:PlanColumns = 'backlog', 'design', 'todo', 'doing', 'verify', 'done'

function Assert-FeatureId([string]$Feature) {
    if ($Feature -notmatch '^F\d+$') { Stop-GodotCi "-Feature must be a GDD feature id such as F3, not '$Feature'" 'invalid-arguments' }
}

# The project option each plan column maps to: the Work Loop's names, unless plan.json's project.columns names another.
function Get-PlanListNames($Plan) {
    $names = [ordered]@{ backlog = 'Backlog'; design = 'Design'; todo = 'To Do'; doing = 'Doing'; verify = 'Testing'; done = 'Done' }
    $block = Get-PlanProjectBlock $Plan
    if ($block -and $block.PSObject.Properties['columns'] -and $block.columns -is [pscustomobject]) {
        foreach ($p in $block.columns.PSObject.Properties) {
            if ($p.Name -in $script:PlanColumns -and "$($p.Value)".Trim()) { $names[$p.Name] = "$($p.Value)" }
        }
    }
    return $names
}

# A column as the kit stores it, from a column id (todo) or a board list name ("To Do", or "Done" with an emoji after it), case-insensitive. A
# list name matches the way sync matches lists: it starts with the name the column maps to; the longest such name wins.
function Resolve-PlanColumn($Plan, [string]$Column) {
    $text = "$Column".Trim()
    foreach ($id in $script:PlanColumns) { if ($id -eq $text) { return $id } }
    $names = Get-PlanListNames $Plan
    $best = $null
    foreach ($id in $script:PlanColumns) {
        if ($text.StartsWith($names[$id], [StringComparison]::OrdinalIgnoreCase) -and (-not $best -or $names[$id].Length -gt $names[$best].Length)) { $best = $id }
    }
    if ($best) { return $best }
    $lists = @(foreach ($id in $script:PlanColumns) { $names[$id] }) -join ', '
    Stop-GodotCi "Unknown column '$Column'; use $($script:PlanColumns -join ', ') or a board list name ($lists)" 'invalid-arguments'
}

# The next task id. Ids of removed tasks are never given again (lastTaskNumber), so a card or a note naming one stays unambiguous.
function New-PlanTaskId($Plan) {
    $numbers = @(foreach ($task in @($Plan.tasks)) { if ($task) { [int]("$($task.id)" -replace '\D', '' -replace '^$', '0') } })
    $last = $Plan.PSObject.Properties['lastTaskNumber'] ? [int]$Plan.lastTaskNumber : 0
    $max = ($numbers | Measure-Object -Maximum).Maximum ?? 0
    return 't' + ([math]::Max($max, $last) + 1)
}

# The phase a new task belongs to: the current one, or the last when every phase is complete.
function Get-PlanTaskPhase($Plan, $Info) {
    $state = Get-PlanState $Plan $Info
    if ($state.current) { return $state.current.id }
    return @($Plan.phases)[-1].id
}

function Get-PlanTaskJson($Task) {
    return [ordered]@{ id = $Task.id; title = $Task.title; column = $Task.column; phase = $Task.phase
        feature = ($Task.PSObject.Properties['feature'] ? $Task.feature : $null); itemId = ($Task.PSObject.Properties['itemId'] ? $Task.itemId : $null)
        boardColumn = ($Task.PSObject.Properties['boardColumn'] ? $Task.boardColumn : $null) }
}

# The GitHub Project a plan mirrors, as -Board names it: "<owner>/<number>", a project URL
# (https://github.com/users/<login>/projects/<number> or .../orgs/...), or just an owner ("@me", a login), which
# stands for "make a new project for this owner". Returns owner and number ($null when the project is still to be made).
function ConvertTo-ProjectRef([string]$Board) {
    $text = "$Board".Trim()
    if ($text -match '^https://github\.com/(?:users|orgs)/(?<owner>[A-Za-z0-9-]+)/projects/(?<number>\d+)(?:[/?#].*)?$') {
        return [ordered]@{ owner = $Matches.owner; number = [int]$Matches.number }
    }
    if ($text -match '^(?<owner>@me|[A-Za-z0-9][A-Za-z0-9-]*)/(?<number>\d+)$') {
        return [ordered]@{ owner = $Matches.owner; number = [int]$Matches.number }
    }
    if ($text -match '^(?<owner>@me|[A-Za-z0-9][A-Za-z0-9-]*)$') { return [ordered]@{ owner = $Matches.owner; number = $null } }
    Stop-GodotCi "-Board '$Board' is not a GitHub Project: give <owner>/<number>, the project's URL, or an owner (@me or a login) to make a new project" 'invalid-arguments'
}

# A project item id as the GitHub API gives it (PVTI_...).
function ConvertTo-ProjectItemId([string]$Item) {
    $id = "$Item".Trim()
    if ($id -notmatch '^PVTI_[A-Za-z0-9_-]+$') {
        Stop-GodotCi "-Item '$Item' is not a project item id: give the id that starts with PVTI_ (gh project item-list <number> --owner <owner> --format json shows it)" 'invalid-arguments'
    }
    return $id
}

function Get-PlanProjectBlock($Plan) {
    return ($Plan.PSObject.Properties['project'] -and $Plan.project -is [pscustomobject]) ? $Plan.project : $null
}

# The project as plan.json stores it, "<owner>/<number>", or $null.
function Get-PlanProjectBoard($Plan) {
    $block = Get-PlanProjectBlock $Plan
    if ($block -and $block.PSObject.Properties['owner'] -and $block.PSObject.Properties['number'] -and $block.number) { return "$($block.owner)/$($block.number)" }
    return $null
}

# Item ids of removed tasks that the next sync archives (project.toArchive).
function Get-PlanArchiveList($Plan) {
    $block = Get-PlanProjectBlock $Plan
    if ($block -and $block.PSObject.Properties['toArchive']) { return @(@($block.toArchive) | Where-Object { $_ } | ForEach-Object { "$_" }) }
    return @()
}

function Set-PlanArchiveList($Plan, [string[]]$ItemIds) {
    $ids = @($ItemIds | Where-Object { $_ } | Select-Object -Unique)
    $block = Get-PlanProjectBlock $Plan
    if (-not $block) {
        if ($ids.Count -eq 0) { return }
        $Plan | Add-Member -NotePropertyName project -NotePropertyValue ([pscustomobject]@{}) -Force
        $block = $Plan.project
    }
    if ($ids.Count) { $block | Add-Member -NotePropertyName toArchive -NotePropertyValue $ids -Force }
    elseif ($block.PSObject.Properties['toArchive']) { $block.PSObject.Properties.Remove('toArchive') }
}

# Sets plan.json's project and keeps the rest of the block (a custom project.columns mapping, items waiting to be archived).
function Set-PlanProject($Plan, $Ref) {
    $block = Get-PlanProjectBlock $Plan
    if (-not $block) {
        $Plan | Add-Member -NotePropertyName project -NotePropertyValue ([pscustomobject]@{}) -Force
        $block = $Plan.project
    }
    $block | Add-Member -NotePropertyName owner -NotePropertyValue $Ref.owner -Force
    $block | Add-Member -NotePropertyName number -NotePropertyValue $Ref.number -Force
}

# Runs the GitHub CLI and returns its output text. The CLI holds the credentials (gh auth login; the project scope is
# added by gh auth refresh -s project, or GH_TOKEN carries a token that has it), so the kit never sees or prints a token.
function Invoke-GhProject([string[]]$Arguments) {
    if (-not (Get-Command gh -ErrorAction SilentlyContinue)) {
        Stop-GodotCi 'plan -Do sync needs the GitHub CLI (gh), signed in with the project scope: gh auth login, then gh auth refresh -s project' 'project-credentials'
    }
    # Bounded by -TimeoutSec when it is set: a call that outlives it stops the command, naming the call (a hung GitHub call used to stall it for good).
    $gh = Invoke-ExternalBounded 'gh' $Arguments -MergeStderr
    if ($gh.TimedOut) {
        Stop-GodotCi "GitHub project call (gh $($Arguments[0..1] -join ' ')) was still running after the -TimeoutSec limit ($($script:CommandDeadline.Seconds) s) and was stopped: the GitHub call hung or the network is slow. What plan.json already holds is unchanged by this call; raise -TimeoutSec, or run plan -Do sync again later" 'command-timeout'
    }
    $text = $gh.Lines -join "`n"
    $code = $gh.Code
    if ($code -ne 0) {
        $short = ($text -split "`n" | Where-Object { $_.Trim() } | Select-Object -First 3) -join ' '
        if ($text -match 'scope|not logged in|authentication|gh auth login|HTTP 401|GH_TOKEN') {
            Stop-GodotCi "GitHub refused the call (gh $($Arguments[0..1] -join ' ')): $short. Sign in with the project scope: gh auth refresh -s project" 'project-credentials'
        }
        Stop-GodotCi "GitHub project call failed (gh $($Arguments[0..1] -join ' ')): $short" 'project-error'
    }
    return $text
}

function Invoke-GhProjectJson([string[]]$Arguments) {
    $text = Invoke-GhProject (@($Arguments) + @('--format', 'json'))
    try { return ($text | ConvertFrom-Json -Depth 20) } catch { Stop-GodotCi "gh $($Arguments[0..1] -join ' ') did not return JSON" 'project-error' }
}

# The repository (OWNER/NAME) of the game's git origin on github.com, or $null; the new project is linked to it.
function Get-ProjectRepo([string]$Dir) {
    $git = Invoke-GitBounded $Dir @('remote', 'get-url', 'origin') 'project repository'
    $url = $git.Lines | Select-Object -First 1
    if ($git.Code -eq 0 -and "$url" -match 'github\.com[:/](?<repo>[A-Za-z0-9._-]+/[A-Za-z0-9._-]+?)(?:\.git)?/?$') { return $Matches.repo }
    return $null
}

# The project, its "Column" field and the option each plan column maps to, made when missing. GitHub's built-in Status
# field only offers Todo, In Progress and Done and the CLI cannot change its options, so the kit keeps its own
# single-select field with the Work Loop's six columns (Backlog, Design, To Do, Doing, Testing, Done).
function Get-ProjectColumns($Plan, [string]$Owner, [int]$Number) {
    $project = Invoke-GhProjectJson @('project', 'view', "$Number", '--owner', $Owner)
    $names = Get-PlanListNames $Plan
    $find = {
        $fields = Invoke-GhProjectJson @('project', 'field-list', "$Number", '--owner', $Owner, '--limit', '100')
        @($fields.fields) | Where-Object { "$($_.name)" -eq 'Column' } | Select-Object -First 1
    }
    $field = & $find
    if (-not $field) {
        Invoke-GhProject @('project', 'field-create', "$Number", '--owner', $Owner, '--name', 'Column', '--data-type', 'SINGLE_SELECT',
            '--single-select-options', (@($script:PlanColumns | ForEach-Object { $names[$_] }) -join ',')) | Out-Null
        $field = & $find
    }
    if (-not $field -or -not $field.PSObject.Properties['options']) {
        Stop-GodotCi "Project $Owner/$Number has no single-select field named 'Column'" 'project-column-missing'
    }
    $options = @($field.options)
    $optionOf = @{}; $columnOf = @{}
    foreach ($column in $script:PlanColumns) {
        $option = $options | Where-Object { "$($_.name)".StartsWith($names[$column], [StringComparison]::OrdinalIgnoreCase) } | Select-Object -First 1
        if (-not $option) {
            Stop-GodotCi "The project's Column field has no option for '$column' (looked for '$($names[$column])'; it has: $(if ($options.Count) { @($options | ForEach-Object name) -join ', ' } else { 'no options' }))" 'project-column-missing'
        }
        $optionOf[$column] = "$($option.id)"; $columnOf["$($option.name)".ToLowerInvariant()] = $column
    }
    return [ordered]@{ projectId = "$($project.id)"; fieldId = "$($field.id)"; optionOf = $optionOf; columnOf = $columnOf }
}

function Set-ProjectItemColumn($Columns, [string]$ItemId, [string]$Column) {
    Invoke-GhProject @('project', 'item-edit', '--id', $ItemId, '--project-id', $Columns.projectId, '--field-id', $Columns.fieldId,
        '--single-select-option-id', $Columns.optionOf[$Column]) | Out-Null
}

# plan.json stays the source of truth for what the tasks are; the GitHub Project is where you drag them. With no
# project yet, -Board <owner> makes one (titled "<game> plan", linked to the game's repository when it has one) with
# the Column field. New tasks become draft items, an item moved on the board moves its task, and a task moved with
# `plan -Do move` moves its item. Each task records the column its item was in at the last sync (boardColumn), which
# tells the two kinds of move apart. An item a person added on the board becomes a task, and the items of tasks removed
# with `plan -Do remove` are archived.
function Sync-PlanProject([string]$Path, [string]$Dir, $Info, [string]$Board) {
    $plan = Read-Plan $Path
    if (-not $Board) { $Board = Get-PlanProjectBoard $plan }
    if (-not $Board) { Stop-GodotCi 'plan -Do sync needs -Board <owner>/<number>, the project URL, or an owner (@me or a login) to make a new project (saved to plan.json afterwards)' 'invalid-arguments' }
    $ref = ConvertTo-ProjectRef $Board
    # Checked before any call, so a bad column cannot stop the sync halfway.
    foreach ($task in @($plan.tasks)) {
        if ("$($task.column)" -notin $script:PlanColumns) {
            Stop-GodotCi "Task $($task.id) is in an unknown column '$($task.column)'; use $($script:PlanColumns -join ', ')" 'invalid-plan'
        }
    }
    $created = 0; $moved = 0; $itemsMoved = 0; $imported = 0; $archived = 0
    $warnings = [System.Collections.Generic.List[string]]::new()
    $madeProject = $false
    if ($null -eq $ref.number) {
        $title = "$($plan.game) plan".Trim()
        $made = Invoke-GhProjectJson @('project', 'create', '--owner', $ref.owner, '--title', $title)
        $ref.number = [int]$made.number
        $madeProject = $true
        Write-CiLog "Created the GitHub Project $($ref.owner)/$($ref.number): $title"
        $repo = Get-ProjectRepo $Dir
        if ($repo) {
            try { Invoke-GhProject @('project', 'link', "$($ref.number)", '--owner', $ref.owner, '--repo', $repo) | Out-Null; Write-CiLog "Linked it to $repo" }
            catch { $warnings.Add("The project could not be linked to $repo ($($_.Exception.Message)); link it on the project's settings page") }
        }
        # Saved at once, so a failure below does not leave a project nobody knows about.
        Set-PlanProject $plan $ref
        Save-Plan $plan $Path
    }
    $columns = Get-ProjectColumns $plan $ref.owner $ref.number
    $columnOf = $columns.columnOf
    $listed = Invoke-GhProjectJson @('project', 'item-list', "$($ref.number)", '--owner', $ref.owner, '--limit', '1000')
    $itemList = @($listed.items)
    if ($listed.PSObject.Properties['totalCount'] -and [int]$listed.totalCount -gt $itemList.Count) {
        $warnings.Add("The project has $($listed.totalCount) items and the sync read $($itemList.Count); items past that are not seen")
    }
    $items = @{}; foreach ($item in $itemList) { $items["$($item.id)"] = $item }
    $itemColumn = {
        param($Item)
        $value = $Item.PSObject.Properties['column'] ? "$($Item.column)".ToLowerInvariant() : ''
        $columnOf.ContainsKey($value) ? $columnOf[$value] : $null
    }

    Set-PlanProject $plan $ref
    $pending = [System.Collections.Generic.List[string]]::new()
    foreach ($itemId in @(Get-PlanArchiveList $plan)) { $pending.Add($itemId) }
    $phase = Get-PlanTaskPhase $plan $Info
    # Saved whatever happens: an item created before a failed call keeps its id, so the next sync does not duplicate it.
    try {
        # Items of removed tasks go first, so they are not taken for items a person added.
        foreach ($itemId in @($pending)) {
            if ($items.ContainsKey($itemId)) {
                Invoke-GhProject @('project', 'item-archive', "$($ref.number)", '--owner', $ref.owner, '--id', $itemId) | Out-Null
                Write-CiLog "Archived item $itemId (its task was removed)"
                $items.Remove($itemId); $archived++
            }
            $pending.Remove($itemId) | Out-Null
        }
        foreach ($task in @($plan.tasks)) {
            $itemId = $task.PSObject.Properties['itemId'] ? "$($task.itemId)" : $null
            if ($itemId -and $items.ContainsKey($itemId)) {
                $itemCol = & $itemColumn $items[$itemId]
                if (-not $itemCol) { continue }
                $recorded = $task.PSObject.Properties['boardColumn'] ? $task.boardColumn : $null
                if ($itemCol -ne $task.column -and ($null -eq $recorded -or $itemCol -ne $recorded)) {
                    Write-CiLog "$($task.id): $($task.column) -> $itemCol (moved on the board)"
                    $task.column = $itemCol; $moved++
                } elseif ($itemCol -ne $task.column) {
                    Write-CiLog "$($task.id): item $itemCol -> $($task.column) (moved in the plan)"
                    Set-ProjectItemColumn $columns $itemId $task.column
                    $itemsMoved++
                }
                $task | Add-Member -NotePropertyName boardColumn -NotePropertyValue $task.column -Force
            } elseif ($itemId) {
                $warnings.Add("Item for $($task.id) is gone from the project (archived or deleted); left as is")
            } else {
                $item = Invoke-GhProjectJson @('project', 'item-create', "$($ref.number)", '--owner', $ref.owner, '--title', "$($task.title)", '--body', "plan task $($task.id), phase $($task.phase)")
                $task | Add-Member -NotePropertyName itemId -NotePropertyValue "$($item.id)" -Force
                # Linked before the column is set: a failed edit leaves the item in the project and the id in the plan.
                Set-ProjectItemColumn $columns "$($item.id)" $task.column
                $task | Add-Member -NotePropertyName boardColumn -NotePropertyValue $task.column -Force
                $created++
            }
        }
        # An item no task names, in a column the plan maps, was added on the board: it becomes a task in that column. An
        # item the kit made for a task ("plan task <id>" in its body) that no task names now is reported, not imported.
        $linked = @{}
        foreach ($task in @($plan.tasks)) { if ($task.PSObject.Properties['itemId'] -and $task.itemId) { $linked["$($task.itemId)"] = $true } }
        foreach ($item in $itemList) {
            $itemId = "$($item.id)"
            if ($linked.ContainsKey($itemId) -or -not $items.ContainsKey($itemId)) { continue }
            $column = & $itemColumn $item
            if (-not $column) { continue }
            $body = ($item.PSObject.Properties['content'] -and $item.content -and $item.content.PSObject.Properties['body']) ? "$($item.content.body)" : ''
            if ($body -match '^plan task (?<task>[^,\s]+)') {
                $warnings.Add("Item '$($item.title)' ($itemId) was made for plan task $($Matches.task), which no task links to; left as is (archive it, or link it: plan -Do link -Id <task> -Item $itemId)")
                continue
            }
            $taskId = New-PlanTaskId $plan
            $plan.tasks = @($plan.tasks) + [pscustomobject]@{ id = $taskId; title = "$($item.title)"; phase = $phase; column = $column; itemId = $itemId; boardColumn = $column }
            Write-CiLog "${taskId}: added from the board's item '$($item.title)' in $column"
            $imported++
        }
    } finally {
        Set-PlanArchiveList $plan @($pending)
        Save-Plan $plan $Path
    }
    Write-PlanMarkdown $plan (Get-PlanState $plan $Info) (Join-Path $Dir 'PLAN.md')
    foreach ($warning in $warnings) { Write-Console "WARNING: $warning" -ForegroundColor Yellow }
    Write-CiLog "Project sync ($($ref.owner)/$($ref.number)): $created item(s) created, $moved task(s) moved from the board, $itemsMoved item(s) moved to follow the plan, $imported task(s) added from the board, $archived item(s) archived"
    if ($madeProject) { Write-CiLog "Open the project and set its Board view to group by Column: gh project view $($ref.number) --owner $($ref.owner) --web" }
    Set-JsonField sync ([ordered]@{ board = "$($ref.owner)/$($ref.number)"; created = $created; moved = $moved; itemsMoved = $itemsMoved; imported = $imported; archived = $archived; madeProject = $madeProject; warnings = @($warnings) })
}

function Invoke-Plan($Info, [string]$Action, [string]$Id, [string]$Game, [string]$Title, [string]$Column, [string]$Board, [string]$Feature, [string]$Item, [string]$PlanProfile = 'full') {
    $path = Get-PlanPath $Info
    $dir = Split-Path $path
    switch ($Action) {
        'init' {
            if (Test-Path -LiteralPath $path) { Write-CiLog "Plan already exists: $path"; Set-JsonField plan $path; return }
            New-Item -ItemType Directory -Force $dir | Out-Null
            # -Profile jam: a game jam of 2 to 9 days, phases sized in days with the jam's gates (templates/plan-jam.json).
            $template = $PlanProfile -eq 'jam' ? 'plan-jam.json' : 'plan.json'
            $plan = Get-Content -LiteralPath (Join-Path $PSScriptRoot "../templates/$template") -Raw | ConvertFrom-Json -Depth 10
            $plan.game = $Game ? $Game : ($Info.DisplayName.Trim() ? $Info.DisplayName.Trim() : $Info.Name)
            $plan.phases[0] | Add-Member -NotePropertyName startedAt -NotePropertyValue ([datetime]::UtcNow.ToString('o'))
            Save-Plan $plan $path
            Write-PlanMarkdown $plan (Get-PlanState $plan $Info) (Join-Path $dir 'PLAN.md')
            Write-CiLog "Created $path and PLAN.md. Next: $(Format-KitCommand 'plan')"
            Set-JsonField plan $path
        }
        'done' {
            if (-not $Id) { Stop-GodotCi 'plan -Do done needs -Id <gate id>' 'invalid-arguments' }
            $plan = Read-Plan $path
            $gate = $plan.phases.gates | Where-Object { $_.id -eq $Id } | Select-Object -First 1
            if (-not $gate) { Stop-GodotCi "No gate '$Id' in $path" 'unknown-gate' }
            # An export-run gate is marked by hand only where it cannot be checked: no preset this machine can launch.
            if ($gate.PSObject.Properties['check'] -and $gate.check -ne 'manual' -and -not ($gate.check -eq 'export-run' -and $null -eq (Test-PlanGate $gate $Info))) {
                Stop-GodotCi "Gate '$Id' is checked automatically ($($gate.check)); make it true in the project instead" 'auto-gate'
            }
            $gate | Add-Member -NotePropertyName done -NotePropertyValue $true -Force
            # Starting the next phase's clock when the last gate of a phase closes.
            $state = Get-PlanState $plan $Info
            $next = $state.current
            if ($next) {
                $phase = $plan.phases | Where-Object { $_.id -eq $next.id }
                if (-not $phase.PSObject.Properties['startedAt']) { $phase | Add-Member -NotePropertyName startedAt -NotePropertyValue ([datetime]::UtcNow.ToString('o')) }
            }
            Save-Plan $plan $path
            Write-PlanMarkdown $plan (Get-PlanState $plan $Info) (Join-Path $dir 'PLAN.md')
            Write-CiLog "Marked $Id done"
        }
        'reopen' {
            # Undoes plan -Do done: the gate counts as open again. Phase clocks are left as they are.
            if (-not $Id) { Stop-GodotCi 'plan -Do reopen needs -Id <gate id>' 'invalid-arguments' }
            $plan = Read-Plan $path
            $gate = $plan.phases.gates | Where-Object { $_.id -eq $Id } | Select-Object -First 1
            if (-not $gate) { Stop-GodotCi "No gate '$Id' in $path" 'unknown-gate' }
            if ($gate.PSObject.Properties['check'] -and $gate.check -ne 'manual') {
                Stop-GodotCi "Gate '$Id' is checked automatically ($($gate.check)); it is open again as soon as the project no longer meets it" 'auto-gate'
            }
            if ($gate.PSObject.Properties['done'] -and $gate.done -eq $true) {
                $gate.PSObject.Properties.Remove('done')
                Save-Plan $plan $path
                Write-PlanMarkdown $plan (Get-PlanState $plan $Info) (Join-Path $dir 'PLAN.md')
                Write-CiLog "Reopened $Id"
            } else { Write-CiLog "$Id is not done; nothing to reopen" }
        }
        'add' {
            if (-not $Title) { Stop-GodotCi 'plan -Do add needs -Title' 'invalid-arguments' }
            $plan = Read-Plan $path
            $column = Resolve-PlanColumn $plan ($Column ? $Column : 'backlog')
            $taskId = New-PlanTaskId $plan
            $task = [pscustomobject]@{ id = $taskId; title = $Title; phase = (Get-PlanTaskPhase $plan $Info); column = $column }
            if ($Feature) { Assert-FeatureId $Feature; $task | Add-Member -NotePropertyName feature -NotePropertyValue $Feature }
            $plan.tasks = @($plan.tasks) + $task
            Save-Plan $plan $path
            Write-PlanMarkdown $plan (Get-PlanState $plan $Info) (Join-Path $dir 'PLAN.md')
            Write-CiLog "Added $taskId to ${column}: $Title"
            Set-JsonField task (Get-PlanTaskJson $task)
        }
        'move' {
            if (-not $Id -or -not $Column) { Stop-GodotCi 'plan -Do move needs -Id <task id> (several: t1,t2,t3) and -Column' 'invalid-arguments' }
            $plan = Read-Plan $path
            $column = Resolve-PlanColumn $plan $Column
            # Several tasks in one call: each plan command starts the kit and reads the project, so moving thirteen tasks one by
            # one took minutes. All of them move or none does.
            $ids = @($Id -split '[,\s]+' | Where-Object { $_ } | Select-Object -Unique)
            $moving = @(foreach ($one in $ids) {
                $found = @($plan.tasks) | Where-Object { $_.id -eq $one } | Select-Object -First 1
                if (-not $found) { Stop-GodotCi "No task '$one' in $path" 'unknown-task' }
                $found
            })
            $doing = @($plan.tasks | Where-Object { $_.column -eq 'doing' -and $_.id -notin $ids }).Count
            if ($column -eq 'doing' -and $doing + $moving.Count -gt $plan.wipLimit) {
                Stop-GodotCi "$doing task(s) already in 'doing' (limit $($plan.wipLimit))$(if ($moving.Count -gt 1) { ", and $($moving.Count) are being moved there" }). Finish or move one first." 'wip-limit'
            }
            foreach ($task in $moving) { $task.column = $column }
            Save-Plan $plan $path
            Write-PlanMarkdown $plan (Get-PlanState $plan $Info) (Join-Path $dir 'PLAN.md')
            Write-CiLog "Moved $($ids -join ', ') to $column"
            Set-JsonField task (Get-PlanTaskJson $moving[0])
            Set-JsonField movedTasks @($moving | ForEach-Object { Get-PlanTaskJson $_ })
        }
        'remove' {
            # Deletes a task. Its project item, if it has one, is archived by the next plan -Do sync (project.toArchive).
            if (-not $Id) { Stop-GodotCi 'plan -Do remove needs -Id <task id>' 'invalid-arguments' }
            $plan = Read-Plan $path
            $task = @($plan.tasks) | Where-Object { $_.id -eq $Id } | Select-Object -First 1
            if (-not $task) { Stop-GodotCi "No task '$Id' in $path" 'unknown-task' }
            $number = [int]("$($task.id)" -replace '\D', '' -replace '^$', '0')
            $last = $plan.PSObject.Properties['lastTaskNumber'] ? [int]$plan.lastTaskNumber : 0
            $plan | Add-Member -NotePropertyName lastTaskNumber -NotePropertyValue ([math]::Max($number, $last)) -Force
            $plan.tasks = @(@($plan.tasks) | Where-Object { $_ -and $_.id -ne $Id })
            $itemId = ($task.PSObject.Properties['itemId'] -and $task.itemId) ? "$($task.itemId)" : $null
            if ($itemId) { Set-PlanArchiveList $plan (@(Get-PlanArchiveList $plan) + $itemId) }
            Save-Plan $plan $path
            Write-PlanMarkdown $plan (Get-PlanState $plan $Info) (Join-Path $dir 'PLAN.md')
            Write-CiLog "Removed $Id ($($task.title))$(if ($itemId) { "; its project item $itemId is archived by the next plan -Do sync" })"
            Set-JsonField task (Get-PlanTaskJson $task)
        }
        'sync' { Sync-PlanProject $path $dir $Info $Board }
        'link' {
            # Ties a task to a GDD feature and/or a project item, and records the board's column for that item (-Column), so the
            # next /game can tell a card the user moved from one it placed itself. -Board alone sets the plan's board.
            $plan = Read-Plan $path
            if ($Board) {
                $ref = ConvertTo-ProjectRef $Board
                if ($null -eq $ref.number) { Stop-GodotCi "plan -Do link -Board needs <owner>/<number> or the project's URL; plan -Do sync -Board $($ref.owner) makes a new project" 'invalid-arguments' }
                $Board = "$($ref.owner)/$($ref.number)"
                Set-PlanProject $plan $ref
                if (-not $Id) {
                    Save-Plan $plan $path
                    Write-CiLog "Project set to $Board"
                    break
                }
            }
            if (-not $Id -or (-not $Feature -and -not $Item -and -not $Column)) {
                Stop-GodotCi 'plan -Do link needs -Board <board>, or -Id <task id> with -Feature <F id>, -Item <item id> and/or -Column <list>' 'invalid-arguments'
            }
            $task = @($plan.tasks) | Where-Object { $_.id -eq $Id } | Select-Object -First 1
            if (-not $task) { Stop-GodotCi "No task '$Id' in $path" 'unknown-task' }
            $itemId = $Item ? (ConvertTo-ProjectItemId $Item) : $null
            $column = $Column ? (Resolve-PlanColumn $plan $Column) : $null
            if ($Feature) { Assert-FeatureId $Feature; $task | Add-Member -NotePropertyName feature -NotePropertyValue $Feature -Force }
            if ($itemId) { $task | Add-Member -NotePropertyName itemId -NotePropertyValue $itemId -Force }
            if ($column) { $task | Add-Member -NotePropertyName boardColumn -NotePropertyValue $column -Force }
            Save-Plan $plan $path
            Write-PlanMarkdown $plan (Get-PlanState $plan $Info) (Join-Path $dir 'PLAN.md')
            Write-CiLog "Linked $Id$(if ($Feature) { " to $Feature" })$(if ($itemId) { " to item $itemId" })$(if ($column) { " (on the board in $column)" })"
            Set-JsonField task (Get-PlanTaskJson $task)
        }
        default { }
    }
    if ($Action -eq 'init') { return }
    $plan = Read-Plan $path
    $state = Get-PlanState $plan $Info
    Set-JsonField plan $path
    Set-JsonField currentPhase ($state.current ? [ordered]@{ id = $state.current.id; name = $state.current.name; goal = $state.current.goal
        timeboxWeeks = $state.current.timeboxWeeks; elapsedWeeks = ($state.current.Contains('elapsedWeeks') ? $state.current.elapsedWeeks : $null)
        timeboxDays = $state.current.timeboxDays; elapsedDays = ($state.current.Contains('elapsedDays') ? $state.current.elapsedDays : $null) } : $null)
    Set-JsonField nextActions @($state.current ? @($state.current.gates | Where-Object { -not $_.done } | ForEach-Object {
        [ordered]@{ id = $_.id; text = $_.text; auto = $_.auto; check = $_.check; optional = $_.optional; detail = $_.detail } }) : @())
    Set-JsonField phases @($state.phases | ForEach-Object {
        [ordered]@{ id = $_.id; name = $_.name; complete = $_.complete; gatesDone = @($_.gates | Where-Object done).Count; gatesTotal = $_.gates.Count } })
    Set-JsonField board $state.board
    Set-JsonField tasks @(@($plan.tasks) | Where-Object { $_ } | ForEach-Object { Get-PlanTaskJson $_ })
    Set-JsonField projectBoard (Get-PlanProjectBoard $plan)
    Set-JsonField release $state.release
    Set-JsonField warnings $state.warnings
    Set-JsonField partial (Get-PartialResult)

    if ($Action -in 'add', 'move', 'remove', 'sync', 'link') { return }
    Write-Console ''
    $partial = Get-PartialResult
    if ($partial) { Write-Console "PARTIAL: $($partial.note). Skipped: $(($partial.skipped | ForEach-Object { "$($_.step) (waiting for $($_.waitingOn))" }) -join '; ')" }
    foreach ($phase in $state.phases) {
        $label = $phase.complete ? 'done   ' : ($phase.id -eq $state.current.id ? 'CURRENT' : 'later  ')
        Write-Console ("{0} {1}  {2}/{3} gates" -f $label, $phase.name.PadRight(26), @($phase.gates | Where-Object done).Count, $phase.gates.Count)
    }
    if ($state.current) {
        Write-Console ''; Write-Console "Now: $($state.current.name) - $($state.current.goal)"
        foreach ($gate in $state.current.gates | Where-Object { -not $_.done }) {
            Write-Console "  [ ] $($gate.id): $($gate.text)$($gate.auto ? '  (auto)' : '')$($gate.optional ? '  (optional)' : '')"
            if ($gate.detail) { Write-Console "      $($gate.detail)" }
        }
    } else { Write-Console 'Every phase is complete.' }
    if ($state.release) {
        $r = $state.release
        $when = $r.daysLeft -gt 0 ? "$($r.daysLeft) days ($($r.businessDaysLeft) business days) away" : 'released or due today'
        Write-Console ''; Write-Console "Release $($r.date): $when"
        Write-Console ('  deadlines: ' + (($r.deadlines.GetEnumerator() | ForEach-Object { "$($_.Key) $($_.Value)" }) -join ' | '))
        foreach ($note in $state.releaseNotes) { Write-Console "  $note" }
    }
    foreach ($warning in $state.warnings) { Write-Console "WARNING: $warning" -ForegroundColor Yellow }
    Write-Console ("Board: " + (($state.board.GetEnumerator() | ForEach-Object { "$($_.Key) $($_.Value)" }) -join ' | '))
}
