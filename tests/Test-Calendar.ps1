#!/usr/bin/env pwsh
# Self-test of `calendar` and of plan.json's discount schedule. The parsers read snapshots of the four sources as they
# were on 2026-11-16 (tests/calendar-fixture: Valve's Upcoming Steam Events block, itch.io's jam calendar call, Epic's
# free-games feed, LootRadar's catalog.game for Hades II), so a parser change that loses an event shows here. The
# command runs end to end with -Offline on temporary projects whose cache this script writes, with dates counted from
# today so the test never goes stale: no network and no Godot are needed.
Set-StrictMode -Version 3.0
$ErrorActionPreference = 'Stop'
$root = Split-Path $PSScriptRoot
$ci = Join-Path $root 'ci/godot/hyperdot.ps1'
$fixture = Join-Path $PSScriptRoot 'calendar-fixture'
$failures = @()
function Assert-True([bool]$Condition, [string]$Name) {
    if ($Condition) { Write-Host "ok     $Name" } else { Write-Host "FAIL   $Name"; $script:failures += $Name }
}
function Invoke-Kit([string]$Dir, [string[]]$KitArgs) {
    $out = & pwsh -NoProfile -NonInteractive -File $ci @KitArgs -Json -Project $Dir 2>$null | Out-String
    return [pscustomobject]@{ Code = $LASTEXITCODE; Doc = ($out.Trim() ? ($out | ConvertFrom-Json -Depth 30) : $null) }
}
foreach ($lib in 'Common', 'Report', 'Plan', 'Calendar') { . (Join-Path $root "ci/godot/lib/$lib.ps1") }
function Get-Day([string]$Text) { return [datetime]::ParseExact($Text, 'yyyy-MM-dd', [cultureinfo]::InvariantCulture) }

# --- Valve's date ranges ---
foreach ($case in @(
        @('December 17, 2026 - January 4, 2027', '2026-12-17', '2027-01-04'),
        @('February 22 - March 1, 2027', '2027-02-22', '2027-03-01'),
        @('June 14 - 21, 2027', '2027-06-14', '2027-06-21'),
        @('December 28 - January 3, 2027', '2026-12-28', '2027-01-03'))) {
    $range = ConvertFrom-CalendarRange $case[0]
    Assert-True ($null -ne $range -and (Format-CalendarDay $range.start) -eq $case[1] -and (Format-CalendarDay $range.end) -eq $case[2]) "range '$($case[0])' is $($case[1]) to $($case[2])"
}
Assert-True ($null -eq (ConvertFrom-CalendarRange 'TBD')) 'a TBD range has no dates'

# --- Valve's page, as it was ---
$steam = @(ConvertFrom-SteamEventsHtml (Get-Content -LiteralPath (Join-Path $fixture 'steam-2026-11-16.html') -Raw))
$kinds = @{}; foreach ($item in $steam) { $kinds[$item.kind] = 1 + ($kinds.ContainsKey($item.kind) ? $kinds[$item.kind] : 0) }
Assert-True ($kinds['seasonal-sale'] -eq 4 -and $kinds['next-fest'] -eq 2 -and $kinds['themed-fest'] -eq 12 -and $kinds['discount-hub'] -eq 1) "Valve's page gives 4 seasonal sales, 2 Next Fests, 12 themed fests and the Black Friday hub: $(($kinds.GetEnumerator() | ForEach-Object { "$($_.Key)=$($_.Value)" }) -join ', ')"
$winter = @($steam | Where-Object { $_.name -eq 'Steam Winter Sale 2026' })
Assert-True ($winter.Count -eq 1 -and $winter[0].start -eq '2026-12-17' -and $winter[0].end -eq '2027-01-04') 'the Winter Sale runs 2026-12-17 to 2027-01-04'
$autumn = @($steam | Where-Object { $_.name -eq 'Steam Autumn Sale 2027' })
Assert-True ($autumn.Count -eq 1 -and $autumn[0].tbd -and $null -eq $autumn[0].start) 'the Autumn Sale 2027 is listed as TBD, with no dates'
$june = @($steam | Where-Object { $_.kind -eq 'next-fest' -and $_.start -eq '2027-06-14' })
Assert-True ($june.Count -eq 1 -and $june[0].end -eq '2027-06-21' -and $june[0].registration -match 'optin/sale/nextfest_june_2027' -and $june[0].url -match 'nextfest/june_2027') 'Next Fest June 2027 has its dates, registration and documentation links'
$sheep = @($steam | Where-Object { $_.name -eq 'Steam Sheep Fest' })
Assert-True ($sheep.Count -eq 1 -and $sheep[0].start -eq '2027-02-04' -and $sheep[0].end -eq '2027-02-08' -and $sheep[0].registration -match 'optin/sale/sheep_2027' -and $sheep[0].notes -match 'Caprinae' -and $sheep[0].notes -notmatch 'More info') "a themed fest has its dates, registration and eligibility text: $($sheep | ConvertTo-Json -Depth 5 -Compress)"
$racing = @($steam | Where-Object { $_.name -eq 'Steam Racing Fest' })
Assert-True ($racing.Count -eq 1 -and $racing[0].notes -match 'about going fast\. Like') "inline markup leaves no stray spaces: $($racing[0].notes)"
$friday = @($steam | Where-Object { $_.kind -eq 'discount-hub' })
Assert-True ($friday.Count -eq 1 -and $friday[0].start -eq '2026-11-26' -and $friday[0].end -eq '2026-11-30') 'the Black Friday hub runs 2026-11-26 to 2026-11-30'
Assert-True (@(ConvertFrom-SteamEventsHtml '<html><body>Moved</body></html>').Count -eq 0) 'a page without the events block gives no events'

# --- itch.io's jam calendar ---
$itchHtml = Get-Content -LiteralPath (Join-Path $fixture 'itch-2026-11-16.html') -Raw
$jams = @(ConvertFrom-ItchJamsHtml $itchHtml (Get-Day '2026-11-16') (Get-Day '2027-11-16'))
Assert-True ($jams.Count -eq 3 -and @($jams | Where-Object { $_.name -eq 'Long past jam' }).Count -eq 0) "the jams in the window are kept, the 2020 one dropped: $(@($jams | ForEach-Object name) -join ', ')"
$brace = @($jams | Where-Object { $_.name -eq 'Brace } and "quote" jam' })
Assert-True ($brace.Count -eq 1 -and $brace[0].url -eq 'https://itch.io/jam/brace-test' -and $brace[0].start -eq '2027-01-10') 'a brace and quotes inside a title do not end the embedded JSON early; the URL is absolute'
$gameOff = @($jams | Where-Object { $_.name -eq 'Game Off 2026' })
Assert-True ($gameOff.Count -eq 1 -and $gameOff[0].joined -gt 1000 -and $gameOff[0].notes -match 'joined') 'a jam carries how many joined'
Assert-True (@($jams | ForEach-Object start) -join ',' -eq (@($jams | ForEach-Object start | Sort-Object) -join ',')) 'jams come out by start date'
Assert-True (@(ConvertFrom-ItchJamsHtml '<p>no calendar</p>' (Get-Day '2026-11-16') (Get-Day '2027-11-16')).Count -eq 0) 'a page without the calendar gives no jams'

# --- Epic's free-games feed ---
$epic = @(ConvertFrom-EpicFreeGamesJson (Get-Content -LiteralPath (Join-Path $fixture 'epic-2026-11-16.json') -Raw))
$free = @($epic | Where-Object { $_.kind -eq 'epic-free' })
Assert-True ($free.Count -eq 1 -and $free[0].name -eq 'Free on Epic: Alien: Isolation' -and $free[0].start -eq '2026-11-19' -and $free[0].end -eq '2026-11-26' -and $free[0].url -eq 'https://store.epicgames.com/p/alien-isolation') "only the 0% offer is a giveaway, with its UTC days and store link: $($free | ConvertTo-Json -Depth 5 -Compress)"
$windows = @($epic | Where-Object { $_.kind -eq 'epic-discounts' })
$holiday = @($windows | Where-Object { $_.start -eq '2026-12-10' -and $_.end -eq '2027-01-07' })
Assert-True ($windows.Count -eq 2 -and $holiday.Count -eq 1 -and $holiday[0].notes -match 'Ghostrunner 2 \(80% off\)' -and $holiday[0].notes -match '45% off') "discounted offers are grouped by window, the percent read as the share paid: $(@($windows | ForEach-Object { "$($_.start) $($_.notes)" }) -join ' | ')"

# --- LootRadar ---
$hades = ConvertFrom-LootRadarGame (Get-Content -LiteralPath (Join-Path $fixture 'lootradar-hades-ii-2026-11-16.json') -Raw) 'hades-ii'
Assert-True ($hades.title -eq 'Hades II' -and $hades.basePrice -eq 29.99 -and $hades.steamPrice -eq 29.99 -and $hades.bestOfficialStore -eq 'Fanatical' -and $hades.bestOfficialPrice -eq 25.49) "Hades II: Steam's base price and the best official store, keyshops left out: $($hades | ConvertTo-Json -Depth 5 -Compress)"
Assert-True ($hades.lowestSeen -eq 15.65 -and $hades.deepestDiscountPercent -eq 48 -and $hades.historyWeeks -eq 13 -and $hades.honestyScore -eq 55) 'the lowest price seen makes the deepest discount, 48%'
Assert-True ($null -eq (ConvertFrom-LootRadarGame '{"result":{"data":{"json":null}}}' 'no-such-game')) 'an unknown slug gives no game'
$two = Get-CalendarComparableSummary @($hades, ([ordered]@{ basePrice = 19.99; deepestDiscountPercent = 30; steamDiscountPercent = $null }))
Assert-True ($two.games -eq 2 -and $two.medianBasePrice -eq 24.99 -and $two.medianDeepestDiscountPercent -eq 39 -and $two.medianSteamDiscountNowPercent -eq 0) "the medians keep cents and skip missing values: $($two | ConvertTo-Json -Depth 5 -Compress)"
$one = Get-CalendarComparableSummary @($hades)
Assert-True ($one.medianBasePrice -eq 29.99) 'one comparable gives its own numbers'

# --- the discount schedule (plan.json release), against Steam's rules ---
function Get-ScheduleWarnings([hashtable]$Release) {
    return @(Get-DiscountScheduleWarnings ([pscustomobject]$Release) (Get-Day '2027-04-20'))
}
$clean = @(Get-ScheduleWarnings @{ launchDiscount = [pscustomobject]@{ percent = 15; days = 7 }; discounts = @(
        [pscustomobject]@{ name = 'Summer'; start = '2027-06-24'; end = '2027-07-08'; percent = 20; seasonal = $true }
        [pscustomobject]@{ name = 'Fest'; start = '2027-06-01'; end = '2027-06-07'; percent = 20 }
        [pscustomobject]@{ name = 'After'; start = '2027-07-10'; end = '2027-07-17'; percent = 25 }
        [pscustomobject]@{ name = 'Autumn custom'; start = '2027-08-20'; end = '2027-08-27'; percent = 30 }) })
Assert-True ($clean.Count -eq 0) "a launch discount, a custom discount 30 days later, a seasonal sale and custom ones on either side of it pass (the seasonal sale is exempt): $($clean -join ' | ')"
$cases = @(
    @(@{ launchDiscount = [pscustomobject]@{ percent = 50; days = 7 } }, 'launch discount is 50%; Steam allows 10 to 40%', 'a 50% launch discount warns'),
    @(@{ launchDiscount = [pscustomobject]@{ percent = 10; days = 5 } }, 'launch discount runs 5 days; Steam allows 7 to 14', 'a 5-day launch discount warns'),
    @(@{ launchDiscount = [pscustomobject]@{ percent = 10 } }, 'needs a percent and a number of days', 'a launch discount without days is ignored with a warning'),
    @(@{ discounts = @([pscustomobject]@{ name = 'Early'; start = '2027-05-01'; end = '2027-05-07'; percent = 20 }) }, "'Early' starts on 2027-05-01, inside the 30 days after release \(until 2027-05-20\)", 'a custom discount inside the 30 days after release warns'),
    @(@{ discounts = @([pscustomobject]@{ name = 'Spring'; start = '2027-05-10'; end = '2027-05-17'; percent = 20; seasonal = $true }) }, 'can join the sale only from 2027-05-20, part-way', 'a seasonal sale inside the 30 days after release is joined part-way'),
    @(@{ discounts = @([pscustomobject]@{ name = 'A'; start = '2027-06-01'; end = '2027-06-07'; percent = 20 }; [pscustomobject]@{ name = 'B'; start = '2027-06-17'; end = '2027-06-24'; percent = 20 }) }, "^The discount 'B' starts 10 days after the discount 'A' ends", 'two custom discounts 10 days apart warn, capitalised'),
    @(@{ discounts = @([pscustomobject]@{ name = 'A'; start = '2027-06-01'; end = '2027-06-10'; percent = 20 }; [pscustomobject]@{ name = 'S'; start = '2027-06-05'; end = '2027-06-20'; percent = 20; seasonal = $true }) }, 'overlap; a game has one discount at a time', 'overlapping discounts warn, even with a seasonal sale'),
    @(@{ discounts = @([pscustomobject]@{ name = 'Long'; start = '2027-06-01'; end = '2027-06-21'; percent = 20 }) }, 'runs 20 days; Steam allows 1 to 14', 'a 20-day custom discount warns'),
    @(@{ discounts = @([pscustomobject]@{ name = 'Deep'; start = '2027-06-01'; end = '2027-06-07'; percent = 99 }) }, 'is 99%; Steam allows 10 to 95%', 'a 99% discount warns'),
    @(@{ discounts = @([pscustomobject]@{ name = 'Bad'; start = 'June'; end = '2027-06-07'; percent = 20 }) }, "'Bad' needs start and end dates", 'a discount with a bad date is ignored with a warning'),
    @(@{ discounts = @([pscustomobject]@{ name = 'Back'; start = '2027-06-07'; end = '2027-06-01'; percent = 20 }) }, 'on or before it starts', 'a discount that ends before it starts is ignored with a warning'))
foreach ($case in $cases) {
    $found = @(Get-ScheduleWarnings $case[0])
    Assert-True (@($found | Where-Object { $_ -match $case[1] }).Count -eq 1) "$($case[2]): $($found -join ' | ')"
}
$launchThenCustom = @(Get-ScheduleWarnings @{ launchDiscount = [pscustomobject]@{ percent = 10; days = 14 }; discounts = @([pscustomobject]@{ name = 'Soon'; start = '2027-05-25'; end = '2027-05-31'; percent = 20 }) })
Assert-True (@($launchThenCustom | Where-Object { $_ -match "^The discount 'Soon' starts 21 days after the launch discount ends \(2027-05-04\)" }).Count -eq 1) "the launch discount starts the 30 days between discounts too: $($launchThenCustom -join ' | ')"
$timeline = Get-ReleaseTimeline ([pscustomobject]@{ date = '2027-04-20' }) (Get-Day '2026-11-16')
Assert-True ($timeline.timeline.deadlines.firstDiscount -eq '2027-05-20') 'the release timeline names the first day a discount can start'

# --- the release against the events ---
$events = @(
    (New-CalendarEvent 'steam' 'seasonal-sale' 'Spring' (Get-Day '2027-04-10') (Get-Day '2027-04-25'))
    (New-CalendarEvent 'steam' 'seasonal-sale' 'Late spring' (Get-Day '2027-05-10') (Get-Day '2027-05-30'))
    (New-CalendarEvent 'steam' 'seasonal-sale' 'Summer' (Get-Day '2027-06-24') (Get-Day '2027-07-08'))
    (New-CalendarEvent 'steam' 'next-fest' 'Next Fest (February 2027)' (Get-Day '2027-02-22') (Get-Day '2027-03-01'))
    (New-CalendarEvent 'steam' 'next-fest' 'Next Fest (June 2027)' (Get-Day '2027-06-14') (Get-Day '2027-06-21'))
    (New-CalendarEvent 'epic' 'epic-free' 'Free on Epic: Rival' (Get-Day '2027-04-22') (Get-Day '2027-04-29')))
$related = Get-CalendarRelease ([pscustomobject]@{ date = '2027-04-20' }) $events (Get-Day '2026-11-16')
$spring = @($related.seasonalSales | Where-Object { $_.name -eq 'Spring' })[0]
$late = @($related.seasonalSales | Where-Object { $_.name -eq 'Late spring' })[0]
Assert-True (-not $spring.joinable -and $late.joinable -and $late.partWay -and $late.joinFrom -eq '2027-05-20' -and $related.firstSeasonalSale -eq 'Late spring') "a sale running on release day cannot be joined; one the 30 days end inside is joined part-way: $($related.seasonalSales | ConvertTo-Json -Depth 5 -Compress)"
Assert-True (@($related.notes | Where-Object { $_ -match 'falls in Spring' }).Count -eq 1) 'release inside a seasonal sale is noted'
Assert-True (@($related.notes | Where-Object { $_ -match 'Free on Epic: Rival runs .* in launch week' }).Count -eq 1) 'an Epic giveaway in launch week is noted'
Assert-True ($related.nextFest.suggested -eq 'Next Fest (February 2027)' -and $related.nextFest.demoReviewBy -eq '2027-02-01') 'with no Next Fest planned, the last one before release is suggested with its demo deadline'
$planned = Get-CalendarRelease ([pscustomobject]@{ date = '2027-04-20'; nextFest = '2027-02-21' }) $events (Get-Day '2026-11-16')
Assert-True (@($planned.warnings | Where-Object { $_ -match 'release.nextFest \(2027-02-21\) is not the first day of a Next Fest Valve lists' }).Count -eq 1) 'a planned Next Fest Valve does not list warns'
$matched = Get-CalendarRelease ([pscustomobject]@{ date = '2027-04-20'; nextFest = '2027-02-22' }) $events (Get-Day '2026-11-16')
Assert-True ($matched.warnings.Count -eq 0 -and $matched.nextFest.edition -eq 'Next Fest (February 2027)') 'a planned Next Fest Valve lists is matched'
Assert-True ($null -eq (Get-CalendarRelease ([pscustomobject]@{ date = $null }) $events (Get-Day '2026-11-16'))) 'no release date, no relation'

# --- the command, end to end and offline ---
$today = [datetime]::UtcNow.Date
function Format-Long([datetime]$Day) { return $Day.ToString('MMMM d, yyyy', [cultureinfo]::InvariantCulture) }
function Format-Short([datetime]$Day) { return $Day.ToString('MMM d', [cultureinfo]::InvariantCulture) }
$saleStart = $today.AddDays(70); $saleEnd = $today.AddDays(90)
$festStart = $today.AddDays(40); $festEnd = $festStart.AddDays(7)
$themeStart = $today.AddDays(20); $themeEnd = $themeStart.AddDays(5)
$pastStart = $today.AddDays(-40); $pastEnd = $today.AddDays(-30)
# Valve's markup with dates from today: a past sale (dropped), an upcoming one, a TBD one, a Next Fest and a fest.
$steamHtml = @"
<div class="documentation_bbcode">Intro<h2 class="bb_section"><a name="1"></a>Seasonal Sales</h2>Four times a year.<br><h2 class="bb_subsection"><a name="1"></a><strong>Past Sale</strong> | $(Format-Long $pastStart) - $(Format-Long $pastEnd)</h2> <h2 class="bb_subsection"><a name="1"></a><strong>Big Sale</strong> | $(Format-Long $saleStart) - $(Format-Long $saleEnd)</h2> <h2 class="bb_subsection"><a name="1"></a><strong>Later Sale</strong> | TBD</h2><h2 class="bb_section"><a name="3"></a>Themed Sale Events (Fests)</h2>Text<h2 class="bb_subsection"><a name="4"></a><strong>$($themeStart.Year) Fests</strong></h2><table><tr><th>Event Dates</th><th>Theme</th><th>Registration</th><th>Eligibility &amp; Notes</th></tr><tr><td>$(Format-Short $themeStart)<br>$(Format-Short $themeEnd)</td><td>Test Fest</td><td><a href="https://partner.steamgames.com/optin/sale/test" target="_blank">Registration details</a></td><td>Games about tests. <a href="https://partner.steamgames.com/doc/marketing/upcoming_events/themed_sales/test" class="bb_doclink">More info</a>.</td></tr></table><h2 class="bb_section"><a name="6"></a>Next Fest</h2>Text<h2 class="bb_subsection"><a name="8"></a>Next Fest | $(Format-Long $festStart) - $(Format-Long $festEnd)</h2><strong>Registration</strong>: <a href="https://partner.steamgames.com/optin/sale/nextfest_test" target="_blank">View</a><br><strong>More Info</strong>: <a href="https://partner.steamgames.com/doc/marketing/upcoming_events/nextfest/test" class="bb_doclink">View documentation</a><br></div>
"@
function New-CalendarProject([hashtable]$Release, [string[]]$Cached = @('steam', 'itch', 'epic', 'lootradar')) {
    $dir = Join-Path ([System.IO.Path]::GetTempPath()) "calendar-$([guid]::NewGuid().ToString('n').Substring(0, 8))"
    New-Item -ItemType Directory -Force (Join-Path $dir '.godot/hyperdot-calendar'), (Join-Path $dir 'plan') | Out-Null
    Set-Content -LiteralPath (Join-Path $dir 'project.godot') "config_version=5`n`n[application]`n`nconfig/name=`"Calendar Test`"`n"
    $cache = Join-Path $dir '.godot/hyperdot-calendar'
    if ('steam' -in $Cached) { Set-Content -LiteralPath (Join-Path $cache 'steam.html') $steamHtml -NoNewline }
    if ('itch' -in $Cached) { Copy-Item -LiteralPath (Join-Path $fixture 'itch-2026-11-16.html') (Join-Path $cache 'itch.html') }
    if ('epic' -in $Cached) { Copy-Item -LiteralPath (Join-Path $fixture 'epic-2026-11-16.json') (Join-Path $cache 'epic.json') }
    if ('lootradar' -in $Cached) { Copy-Item -LiteralPath (Join-Path $fixture 'lootradar-hades-ii-2026-11-16.json') (Join-Path $cache 'lootradar-hades-ii.json') }
    if ($null -ne $Release) {
        $plan = [ordered]@{ schema = 'godot-plan/1'; game = 'Calendar Test'; wipLimit = 2; release = $Release; phases = @(); tasks = @() }
        Set-Content -LiteralPath (Join-Path $dir 'plan/plan.json') ($plan | ConvertTo-Json -Depth 10)
    }
    return $dir
}
$releaseDay = $today.AddDays(50)
$dir = New-CalendarProject @{ date = $releaseDay.ToString('yyyy-MM-dd', [cultureinfo]::InvariantCulture); comparables = @('hades-ii')
    launchDiscount = @{ percent = 15; days = 7 }; discounts = @(@{ name = 'Too soon'; start = $releaseDay.AddDays(10).ToString('yyyy-MM-dd', [cultureinfo]::InvariantCulture); end = $releaseDay.AddDays(15).ToString('yyyy-MM-dd', [cultureinfo]::InvariantCulture); percent = 20 }) }
try {
    $results = Join-Path $dir 'calendar-results'
    $run = Invoke-Kit $dir @('calendar', '-Offline', '-Results', $results)
    $doc = $run.Doc
    Assert-True ($run.Code -eq 0 -and $doc.ok -and $doc.command -eq 'calendar') "calendar -Offline reads the cache and passes (exit $($run.Code)): $(if ($doc -and -not $doc.ok) { $doc.error.message })"
    $c = $doc.calendar
    Assert-True (@($c.sources | Where-Object { $_.ok -and $_.cached }).Count -eq 4) "all four sources are read from the cache: $(@($c.sources | ForEach-Object { "$($_.source)=$($_.ok)" }) -join ', ')"
    $names = @($c.events | ForEach-Object name)
    Assert-True ('Steam Big Sale' -in $names -and 'Steam Later Sale' -in $names -and 'Steam Past Sale' -notin $names) "an upcoming and a TBD sale are listed, a past one is not: $($names -join ', ')"
    Assert-True ($c.events[-1].tbd -and $c.events[-1].name -eq 'Steam Later Sale') 'TBD events come last'
    Assert-True ($c.counts.'seasonal-sale' -eq 2 -and $c.counts.'next-fest' -eq 1 -and $c.counts.'themed-fest' -eq 1 -and $c.counts.jam -eq 3) "the counts are per kind: $($c.counts | ConvertTo-Json -Depth 5 -Compress)"
    $joinFrom = $releaseDay.AddDays(30).ToString('yyyy-MM-dd', [cultureinfo]::InvariantCulture)
    Assert-True ($c.release.firstSeasonalSale -eq 'Steam Big Sale' -and @($c.release.seasonalSales)[0].partWay -and @($c.release.seasonalSales)[0].joinFrom -eq $joinFrom) "released 20 days before the sale, the game joins it part-way, from $($joinFrom): $($c.release | ConvertTo-Json -Depth 5 -Compress)"
    Assert-True ($c.release.nextFest.suggested -match 'Next Fest' -and $c.release.nextFest.demoReviewBy -eq $festStart.AddDays(-21).ToString('yyyy-MM-dd', [cultureinfo]::InvariantCulture)) 'the Next Fest before release is suggested, with its demo deadline'
    Assert-True ($c.timeline.deadlines.firstDiscount -eq $releaseDay.AddDays(30).ToString('yyyy-MM-dd', [cultureinfo]::InvariantCulture)) 'the plan timeline comes along'
    Assert-True (@($doc.warnings | Where-Object { $_ -match "The discount 'Too soon' starts .* inside the 30 days after release" }).Count -eq 1) "the discount schedule is checked: $($doc.warnings -join ' | ')"
    Assert-True (@($c.comparables).Count -eq 1 -and $c.comparables[0].title -eq 'Hades II' -and $c.comparableSummary.medianBasePrice -eq 29.99) 'the comparable from plan.json is read, with its summary'
    Assert-True ('LootRadar (lootradar.gg)' -in @($c.attribution)) 'LootRadar is attributed'
    $ics = Join-Path $results 'calendar.ics'
    Assert-True ($doc.calendar.ics -eq $ics -and (Test-Path -LiteralPath $ics) -and (Test-Path -LiteralPath (Join-Path $results '.gdignore'))) 'calendar.ics is written to the results folder, which Godot is told to ignore'
    $bytes = [System.IO.File]::ReadAllBytes($ics)
    $text = [System.Text.Encoding]::UTF8.GetString($bytes)
    $lines = @($text -split "`r`n")
    Assert-True ($text.StartsWith('BEGIN:VCALENDAR') -and $text.TrimEnd().EndsWith('END:VCALENDAR') -and ($text -replace "`r`n", '') -notmatch "`n") 'calendar.ics is one VCALENDAR with CRLF line ends'
    Assert-True (@($lines | Where-Object { [System.Text.Encoding]::UTF8.GetByteCount($_) -gt 75 }).Count -eq 0) 'no calendar.ics line is over 75 octets'
    $vevents = @($lines | Where-Object { $_ -eq 'BEGIN:VEVENT' }).Count
    Assert-True ($vevents -ge 8 -and @($lines | Where-Object { $_ -match '^SUMMARY:Calendar Test: release day$' }).Count -eq 1 -and @($lines | Where-Object { $_ -match '^SUMMARY:Calendar Test: launch discount 15%' }).Count -eq 1) "calendar.ics holds the events, the release day and the launch discount ($vevents events)"
    $big = [array]::IndexOf($lines, 'SUMMARY:Steam Big Sale')
    Assert-True ($big -gt 0 -and $lines[$big - 1] -eq "DTEND;VALUE=DATE:$($saleEnd.AddDays(1).ToString('yyyyMMdd', [cultureinfo]::InvariantCulture))") 'an all-day event ends the day after its last day (DTEND is exclusive)'
    $uids = @($lines | Where-Object { $_ -match '^UID:' })
    Assert-True ($uids.Count -eq $vevents -and @($uids | Select-Object -Unique).Count -eq $uids.Count) 'every event has its own UID'
    $again = Invoke-Kit $dir @('calendar', '-Offline', '-Results', $results)
    $uidsAgain = @([System.IO.File]::ReadAllLines($ics) | Where-Object { $_ -match '^UID:' })
    Assert-True ($again.Doc.ok -and ($uidsAgain -join ',') -eq ($uids -join ',')) 'a second run gives the same UIDs, so a re-import updates instead of duplicating'
    $history = Join-Path $dir '.godot/hyperdot-history.jsonl'
    Assert-True ((Test-Path -LiteralPath $history) -and @(Get-Content -LiteralPath $history | Where-Object { $_ -match '"command":"calendar"' }).Count -ge 1) 'the run is recorded in the history, for status and its workflow rules'
    $narrow = Invoke-Kit $dir @('calendar', '-Offline', '-Source', 'steam', '-Days', '30', '-Results', $results)
    Assert-True ($narrow.Doc.ok -and @($narrow.Doc.calendar.sources).Count -eq 1 -and 'Steam Big Sale' -notin @($narrow.Doc.calendar.events | ForEach-Object name) -and 'Steam Test Fest' -in @($narrow.Doc.calendar.events | ForEach-Object name)) '-Source steam -Days 30 reads one source and lists the next 30 days'
} finally { Remove-Item -LiteralPath $dir -Recurse -Force -ErrorAction SilentlyContinue }

# A source missing from the cache is a warning; none at all is calendar-unavailable.
$partial = New-CalendarProject $null @('steam')
try {
    $run = Invoke-Kit $partial @('calendar', '-Offline', '-Results', (Join-Path $partial 'calendar-results'))
    Assert-True ($run.Code -eq 0 -and $run.Doc.ok -and $null -eq $run.Doc.calendar.release -and @($run.Doc.warnings | Where-Object { $_ -match '^itch: no cached copy' }).Count -eq 1 -and @($run.Doc.warnings | Where-Object { $_ -match '^lootradar: no comparables' }).Count -eq 1) "with only Valve's page cached and no plan, calendar passes and says what it could not read: $($run.Doc.warnings -join ' | ')"
} finally { Remove-Item -LiteralPath $partial -Recurse -Force -ErrorAction SilentlyContinue }
$empty = New-CalendarProject $null @()
try {
    $run = Invoke-Kit $empty @('calendar', '-Offline', '-Results', (Join-Path $empty 'calendar-results'))
    Assert-True ($run.Code -ne 0 -and $run.Doc.error.code -eq 'calendar-unavailable' -and @($run.Doc.calendar.sources).Count -eq 4) "with nothing cached, -Offline fails with calendar-unavailable and lists each source: $($run.Doc.error.message)"
    foreach ($case in @(
            @(@('calendar', '-Source', 'steam,twitter'), 'invalid-arguments', '-Source twitter is not one of'),
            @(@('calendar', '-Days', '0'), 'invalid-arguments', '-Days must be 1 to 1095'),
            @(@('calendar', '-Comparable', 'Hades II!'), 'invalid-arguments', '-Comparable takes LootRadar slugs'),
            @(@('status', '-Offline'), 'invalid-arguments', '-Offline is for calendar'),
            @(@('plan', '-Comparable', 'hades-ii'), 'invalid-arguments', '-Comparable is for calendar'))) {
        $run = Invoke-Kit $empty $case[0]
        Assert-True ($run.Code -ne 0 -and $run.Doc.error.code -eq $case[1] -and $run.Doc.error.message -match [regex]::Escape($case[2])) "$($case[0] -join ' ') fails with $($case[1]): $($run.Doc.error.message)"
    }
} finally { Remove-Item -LiteralPath $empty -Recurse -Force -ErrorAction SilentlyContinue }

if ($failures.Count) { Write-Host "`n$($failures.Count) failed"; exit 1 }
Write-Host "`nAll calendar checks passed"
