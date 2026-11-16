# `calendar`: the dated events a game's marketing plans around, set against plan.json's release block.
#   steam      Valve's "Upcoming Steam Events" page: the seasonal sales, Next Fest editions, themed fests and the
#              Black Friday discount hub, with their dates and registration links. The page is the source of truth;
#              no date is hard-coded here (store-page section 7).
#   itch       itch.io's jam calendar (the data its /jams page embeds): the most-joined jams in the window.
#   epic       the Epic Games Store's free-games feed (current and upcoming giveaways). Epic does not document it, and
#              Epic's sale calendar is only in its developer portal, behind a sign-in.
#   lootradar  LootRadar's public API (lootradar.gg, keyless): for each comparable game, the prices, 12 weeks of price
#              history, the deepest discount seen, the wait-or-buy hint and live players: what similar games sell for.
# Each page is cached in .godot/hyperdot-calendar for 6 hours (LootRadar's data changes every few hours; its fair-use
# note asks for caching and a client name). A source that cannot be reached is reported, never fatal; with -Offline only
# the cache is read. Nothing in the game is changed: the result is the JSON and calendar.ics in the results folder.

$script:CalendarSources = @('steam', 'itch', 'epic', 'lootradar')
$script:CalendarUrls = @{
    steam = 'https://partner.steamgames.com/doc/marketing/upcoming_events'
    itch = 'https://itch.io/jams'
    epic = 'https://store-site-backend-static.ak.epicgames.com/freeGamesPromotions?locale=en-US'
    lootradar = 'https://lootradar.gg/api/trpc/catalog.game'
}
$script:CalendarAttribution = @{
    steam = 'Valve, Steamworks: Upcoming Steam Events'
    itch = 'itch.io jam calendar'
    epic = 'Epic Games Store free-games feed (undocumented)'
    lootradar = 'LootRadar (lootradar.gg)'
}
$script:CalendarCacheHours = 6
$script:CalendarUserAgent = 'hyperdot-calendar/1.0'
$script:CalendarJamCount = 15
$script:CalendarMaxDays = 1095
$script:CalendarMaxComparables = 10
# Next Fest's demo goes to review 3 weeks before the festival (Plan.ps1's release timeline holds the press-preview case).
$script:CalendarDemoReviewDays = 21

function Get-CalendarField($Object, [string]$Name) {
    if ($null -eq $Object) { return $null }
    if ($Object -is [System.Collections.IDictionary]) { return $Object.Contains($Name) ? $Object[$Name] : $null }
    $property = $Object.PSObject.Properties[$Name]
    return $property ? $property.Value : $null
}

function Format-CalendarDay([datetime]$Day) { return $Day.ToString('yyyy-MM-dd', [cultureinfo]::InvariantCulture) }

# A day from "2026-11-19T16:00:00.000Z" (UTC), "2026-11-01 21:37:27" (itch.io, read as UTC) or "2026-11-19".
function ConvertTo-CalendarDay($Value) {
    if ($null -eq $Value -or "$Value" -eq '') { return $null }
    if ($Value -is [datetime]) { return $Value.ToUniversalTime().Date }
    $text = "$Value".Trim()
    $parsed = [datetimeoffset]::MinValue
    $styles = [System.Globalization.DateTimeStyles]::AssumeUniversal -bor [System.Globalization.DateTimeStyles]::AdjustToUniversal
    if ([datetimeoffset]::TryParse($text, [cultureinfo]::InvariantCulture, $styles, [ref]$parsed)) { return $parsed.UtcDateTime.Date }
    return $null
}

# "December 17, 2026", "November 26th", "Nov 16" (with -Year when the text has none) as a day, or $null.
function ConvertFrom-CalendarDayText([string]$Text, [int]$Year = 0) {
    $clean = (($Text -replace '(\d)(st|nd|rd|th)\b', '$1') -replace ',', ' ' -replace '\s+', ' ').Trim()
    if ($clean -notmatch '\d{4}$') {
        if ($Year -le 0) { return $null }
        $clean = "$clean $Year"
    }
    $parsed = [datetime]::MinValue
    foreach ($format in 'MMMM d yyyy', 'MMM d yyyy') {
        if ([datetime]::TryParseExact($clean, $format, [cultureinfo]::InvariantCulture, [System.Globalization.DateTimeStyles]::None, [ref]$parsed)) { return $parsed.Date }
    }
    return $null
}

# Valve's ranges: "December 17, 2026 - January 4, 2027", "February 22 - March 1, 2027", "June 14 - 21, 2027".
function ConvertFrom-CalendarRange([string]$Text) {
    $parts = @($Text.Trim() -split '\s+[-–]\s+')
    if ($parts.Count -ne 2) { return $null }
    $left = $parts[0].Trim(); $right = $parts[1].Trim()
    if ($right -notmatch '(\d{4})\s*$') { return $null }
    $year = [int]$Matches[1]
    if ($right -match '^\d{1,2}\s*,?\s*\d{4}$' -and $left -match '^([A-Za-z]+)') { $right = "$($Matches[1]) $right" }
    $end = ConvertFrom-CalendarDayText $right
    if ($null -eq $end) { return $null }
    $start = ConvertFrom-CalendarDayText $left $year
    if ($null -eq $start) { return $null }
    if ($left -notmatch '\d{4}' -and $start -gt $end) { $start = $start.AddYears(-1) }
    return [pscustomobject]@{ start = $start; end = $end }
}

function ConvertFrom-CalendarHtmlText([string]$Html) {
    $text = $Html -replace '<br\s*/?>|</?(td|th|tr|p|div|h\d)\b[^>]*>', ' ' -replace '<[^>]+>', ''
    return ([System.Net.WebUtility]::HtmlDecode($text) -replace '\s+', ' ').Trim()
}

function New-CalendarEvent([string]$Source, [string]$Kind, [string]$Name, $Start, $End, [string]$Url = '', [string]$Registration = '', [string]$Notes = '') {
    return [ordered]@{ source = $Source; kind = $Kind; name = $Name
        start = ($null -ne $Start ? (Format-CalendarDay $Start) : $null); end = ($null -ne $End ? (Format-CalendarDay $End) : $null)
        tbd = ($null -eq $Start); url = ($Url ? $Url : $null); registration = ($Registration ? $Registration : $null); notes = ($Notes ? $Notes : $null) }
}

# Valve's page, section by section (the bb_section headings): the seasonal sales, the Black Friday hub, the themed
# fests (a table per year) and the Next Fest editions. What does not parse is skipped; no events at all is the caller's
# sign that the page changed.
function ConvertFrom-SteamEventsHtml([string]$Html) {
    $url = $script:CalendarUrls.steam
    $start = $Html.IndexOf('documentation_bbcode')
    if ($start -lt 0) { return @() }
    $body = $Html.Substring($start)
    $events = [System.Collections.Generic.List[object]]::new()
    $sections = [regex]::Split($body, '<h2 class="bb_section">')
    foreach ($section in @($sections | Select-Object -Skip 1)) {
        $title = ConvertFrom-CalendarHtmlText ($section -replace '(?s)</h2>.*$', '')
        if ($title -match '^Seasonal Sales') {
            foreach ($m in [regex]::Matches($section, '(?s)<h2 class="bb_subsection">(?:<a[^>]*></a>)?\s*<strong>([^<]+)</strong>\s*\|\s*([^<]+)</h2>')) {
                $name = ConvertFrom-CalendarHtmlText $m.Groups[1].Value
                $range = ConvertFrom-CalendarRange (ConvertFrom-CalendarHtmlText $m.Groups[2].Value)
                $notes = 'Games released at least 30 days before it starts join with a discount from its first day (Discount Management page); one released later joins part-way, once its 30 days after release end. Exempt from the 30 days between discounts.'
                $events.Add((New-CalendarEvent 'steam' 'seasonal-sale' "Steam $name" ($range ? $range.start : $null) ($range ? $range.end : $null) "$url#1" '' $notes))
            }
        } elseif ($title -match 'Black Friday\s+(\d{4})') {
            $year = [int]$Matches[1]
            $text = ConvertFrom-CalendarHtmlText $section
            if ($text -match 'From ([A-Za-z]+ \d{1,2})(?:st|nd|rd|th)?\b.*?through ([A-Za-z]+ \d{1,2})(?:st|nd|rd|th)?\b') {
                $from = ConvertFrom-CalendarDayText $Matches[1] $year
                $to = ConvertFrom-CalendarDayText $Matches[2] $year
                if ($from -and $to) {
                    $events.Add((New-CalendarEvent 'steam' 'discount-hub' "Steam Black Friday $year (Discounts & Events page)" $from $to "$url#2" '' 'Not a Steam sale event: a themed hub for discounts; the 30 days between discounts still apply.'))
                }
            }
        } elseif ($title -match 'Themed Sale Events') {
            foreach ($block in [regex]::Split($section, '<h2 class="bb_subsection">')) {
                if ($block -notmatch '<strong>\s*(\d{4}) Fests\s*</strong>') { continue }
                $year = [int]$Matches[1]
                foreach ($row in [regex]::Matches($block, '(?s)<tr>(.*?)</tr>')) {
                    $cells = @([regex]::Matches($row.Groups[1].Value, '(?s)<td>(.*?)</td>') | ForEach-Object { $_.Groups[1].Value })
                    if ($cells.Count -lt 3) { continue }
                    $days = @($cells[0] -split '<br\s*/?>' | ForEach-Object { ConvertFrom-CalendarHtmlText $_ } | Where-Object { $_ })
                    if ($days.Count -lt 2) { continue }
                    $from = ConvertFrom-CalendarDayText $days[0] $year
                    $to = ConvertFrom-CalendarDayText $days[1] $year
                    if (-not $from -or -not $to) { continue }
                    if ($to -lt $from) { $to = $to.AddYears(1) }
                    $name = ConvertFrom-CalendarHtmlText $cells[1]
                    $registration = ($cells[2] -match 'href="([^"]+)"') ? $Matches[1] : ''
                    $more = ($cells.Count -ge 4 -and $cells[3] -match 'href="([^"]+)"') ? $Matches[1] : "$url#3"
                    $notes = $cells.Count -ge 4 ? ((ConvertFrom-CalendarHtmlText $cells[3]) -replace '\s*More info\s*\.?\s*$', '') : ''
                    $events.Add((New-CalendarEvent 'steam' 'themed-fest' "Steam $name" $from $to $more $registration $notes))
                }
            }
        } elseif ($title -match '^Next Fest') {
            foreach ($m in [regex]::Matches($section, '(?s)<h2 class="bb_subsection">(?:<a[^>]*></a>)?\s*Next Fest\s*\|\s*([^<]+)</h2>(.*?)(?=<h2|$)')) {
                $range = ConvertFrom-CalendarRange (ConvertFrom-CalendarHtmlText $m.Groups[1].Value)
                if (-not $range) { continue }
                $rest = $m.Groups[2].Value
                $registration = ($rest -match 'href="(https://partner\.steamgames\.com/optin/[^"]+)"') ? $Matches[1] : ''
                $more = ($rest -match 'href="(https://partner\.steamgames\.com/doc/marketing/upcoming_events/nextfest/[^"]+)"') ? $Matches[1] : "$url#6"
                $label = $range.start.ToString('MMMM yyyy', [cultureinfo]::InvariantCulture)
                $events.Add((New-CalendarEvent 'steam' 'next-fest' "Steam Next Fest ($label)" $range.start $range.end $more $registration 'For unreleased games with a playable demo; the demo goes to review 3 weeks before (5 for the press preview). One Next Fest per game.'))
            }
        }
    }
    return @($events)
}

# The JSON object that starts at $Start (a "{"), read up to its matching "}", strings and escapes respected.
function Get-CalendarJsonObject([string]$Text, [int]$Start) {
    $depth = 0; $inString = $false; $escape = $false
    for ($i = $Start; $i -lt $Text.Length; $i++) {
        $c = $Text[$i]
        if ($inString) {
            if ($escape) { $escape = $false } elseif ($c -eq '\') { $escape = $true } elseif ($c -eq '"') { $inString = $false }
            continue
        }
        if ($c -eq '"') { $inString = $true }
        elseif ($c -eq '{') { $depth++ }
        elseif ($c -eq '}') { $depth--; if ($depth -eq 0) { return $Text.Substring($Start, $i - $Start + 1) } }
    }
    return $null
}

# itch.io's /jams page embeds its calendar as R.Jam.FilteredJamCalendar({...,"jams":[...]}). The most-joined jams that
# overlap the window; times carry no zone and are read as UTC.
function ConvertFrom-ItchJamsHtml([string]$Html, [datetime]$From, [datetime]$To) {
    $marker = 'R.Jam.FilteredJamCalendar('
    $at = $Html.IndexOf($marker)
    if ($at -lt 0) { return @() }
    $json = Get-CalendarJsonObject $Html ($at + $marker.Length)
    if (-not $json) { return @() }
    $data = $json | ConvertFrom-Json -DateKind String -Depth 10
    $jams = @(foreach ($jam in @(Get-CalendarField $data 'jams')) {
        $start = ConvertTo-CalendarDay (Get-CalendarField $jam 'start_date')
        $end = ConvertTo-CalendarDay (Get-CalendarField $jam 'end_date')
        if ($null -eq $start -or $null -eq $end -or $end -lt $From -or $start -gt $To) { continue }
        $joined = Get-CalendarNumber (Get-CalendarField $jam 'joined')
        [pscustomobject]@{ jam = $jam; start = $start; end = $end; joined = ($null -ne $joined ? [int][math]::Min($joined, [int]::MaxValue) : 0) }
    })
    return @(foreach ($entry in @($jams | Sort-Object @{ Expression = 'joined'; Descending = $true }, start | Select-Object -First $script:CalendarJamCount)) {
        $jam = $entry.jam
        $path = "$(Get-CalendarField $jam 'url')"
        $voting = ConvertTo-CalendarDay (Get-CalendarField $jam 'voting_end_date')
        $notes = "$($entry.joined) joined$(if ((Get-CalendarField $jam 'featured') -eq 1) { ', featured' })$(if ($voting) { ", voting until $(Format-CalendarDay $voting)" })."
        $item = New-CalendarEvent 'itch' 'jam' "$(Get-CalendarField $jam 'title')" $entry.start $entry.end ($path.StartsWith('/') ? "https://itch.io$path" : $path) '' $notes
        $item['joined'] = $entry.joined
        $item
    }) | Sort-Object { $_.start }
}

# Epic's free-games feed: each offer with a 0% discount setting is a giveaway, now or upcoming.
function ConvertFrom-EpicFreeGamesJson([string]$Json) {
    $data = $Json | ConvertFrom-Json -DateKind String -Depth 30
    $elements = @(Get-CalendarField (Get-CalendarField (Get-CalendarField (Get-CalendarField $data 'data') 'Catalog') 'searchStore') 'elements')
    $events = [System.Collections.Generic.List[object]]::new()
    $discounted = [ordered]@{}   # "start|end" -> titles: the feed's other games on discount, by window
    foreach ($element in $elements) {
        $promotions = Get-CalendarField $element 'promotions'
        if ($null -eq $promotions) { continue }
        $title = "$(Get-CalendarField $element 'title')"
        $slug = Get-CalendarField $element 'productSlug'
        $mappings = @(Get-CalendarField $element 'offerMappings' | Where-Object { $null -ne $_ })
        if (-not $slug -and $mappings.Count) { $slug = Get-CalendarField $mappings[0] 'pageSlug' }
        $url = $slug ? "https://store.epicgames.com/p/$slug" : 'https://store.epicgames.com/free-games'
        foreach ($group in @(@(Get-CalendarField $promotions 'promotionalOffers') + @(Get-CalendarField $promotions 'upcomingPromotionalOffers'))) {
            foreach ($offer in @(Get-CalendarField $group 'promotionalOffers')) {
                if ($null -eq $offer) { continue }
                $percent = Get-CalendarNumber (Get-CalendarField (Get-CalendarField $offer 'discountSetting') 'discountPercentage')
                $start = ConvertTo-CalendarDay (Get-CalendarField $offer 'startDate')
                $end = ConvertTo-CalendarDay (Get-CalendarField $offer 'endDate')
                if ($null -eq $start -or $null -eq $end -or $null -eq $percent -or $percent -lt 0 -or $percent -ge 100) { continue }
                if ($percent -eq 0) {
                    $events.Add((New-CalendarEvent 'epic' 'epic-free' "Free on Epic: $title" $start $end $url '' 'A game Epic gives away that week; its genre competes for the same players.'))
                } else {
                    $key = "$(Format-CalendarDay $start)|$(Format-CalendarDay $end)"
                    if (-not $discounted.Contains($key)) { $discounted[$key] = [System.Collections.Generic.List[string]]::new() }
                    $discounted[$key].Add("$title ($(100 - $percent)% off)")
                }
            }
        }
    }
    # discountPercentage is the share of the price paid: 0 is free, 80 is 20% off.
    foreach ($key in $discounted.Keys) {
        $days = $key -split '\|'
        $titles = $discounted[$key]
        $events.Add((New-CalendarEvent 'epic' 'epic-discounts' "Epic discounts in the free-games feed ($($titles.Count) game$(if ($titles.Count -ne 1) { 's' }))" `
                    (ConvertTo-PlanDate $days[0]) (ConvertTo-PlanDate $days[1]) 'https://store.epicgames.com/free-games' '' `
                    "$($titles -join ', '). Only what the feed shows: Epic's sale calendar is in its developer portal."))
    }
    return @($events)
}

function Get-CalendarNumber($Value) {
    if ($null -eq $Value -or "$Value" -eq '') { return $null }
    $number = 0.0
    if ([double]::TryParse("$Value", [System.Globalization.NumberStyles]::Float, [cultureinfo]::InvariantCulture, [ref]$number)) { return $number }
    return $null
}

# One comparable game from LootRadar's catalog.game: its base price (Steam's, else the highest official store's), the
# price on Steam now, the best official price and the deepest official discount now, from the official stores' deals
# only (a developer's own sale is on official stores). LootRadar's price history, historical low and lowest-ever price
# are its best price over every store, keyshops included, and cannot be split by store: they are reported as such
# (the *AllStores fields), with the honesty score and the wait-or-buy hint.
function ConvertFrom-LootRadarGame([string]$Json, [string]$Slug) {
    $data = Get-CalendarField (Get-CalendarField (Get-CalendarField ($Json | ConvertFrom-Json -DateKind String -Depth 30) 'result') 'data') 'json'
    $game = Get-CalendarField $data 'game'
    if ($null -eq $game) { return $null }
    $official = @(foreach ($entry in @(Get-CalendarField $data 'deals')) {
        $store = Get-CalendarField $entry 'store'
        if ((Get-CalendarField $store 'type') -ne 'official') { continue }
        $deal = Get-CalendarField $entry 'deal'
        [pscustomobject]@{ store = "$(Get-CalendarField $store 'name')"; price = Get-CalendarNumber (Get-CalendarField $deal 'price')
            basePrice = Get-CalendarNumber (Get-CalendarField $deal 'basePrice'); discount = Get-CalendarNumber (Get-CalendarField $deal 'discountPct') }
    })
    $steam = @($official | Where-Object { $_.store -eq 'Steam' } | Select-Object -First 1)
    $bases = @($official | Where-Object { $null -ne $_.basePrice } | ForEach-Object basePrice)
    $basePrice = $steam.Count -and $null -ne $steam[0].basePrice ? $steam[0].basePrice : ($bases.Count ? ($bases | Measure-Object -Maximum).Maximum : $null)
    $priced = @($official | Where-Object { $null -ne $_.price } | Sort-Object price)
    $history = @(foreach ($point in @(Get-CalendarField $data 'history')) { Get-CalendarNumber (Get-CalendarField $point 'price') }) | Where-Object { $null -ne $_ }
    $waitOrBuy = Get-CalendarField $data 'waitOrBuy'
    $lows = @((Get-CalendarNumber (Get-CalendarField $game 'historicalLow')), (Get-CalendarNumber (Get-CalendarField $waitOrBuy 'lowestEver'))) + @($history) | Where-Object { $null -ne $_ -and $_ -gt 0 }
    $lowest = @($lows).Count ? (@($lows) | Measure-Object -Minimum).Minimum : $null
    $officialDiscounts = @($official | Where-Object { $null -ne $_.discount } | ForEach-Object discount)
    $deepest = ($null -ne $basePrice -and $basePrice -gt 0 -and $null -ne $lowest) ? [math]::Max(0, [math]::Round((1 - $lowest / $basePrice) * 100)) : $null
    return [ordered]@{
        slug = $Slug; title = "$(Get-CalendarField $game 'title')"; url = "https://lootradar.gg/game/$Slug"
        steamAppId = Get-CalendarField $game 'steamAppId'; genres = Get-CalendarField $game 'genres'; releaseDate = Get-CalendarField $game 'releaseDate'
        basePrice = $basePrice
        steamPrice = ($steam.Count ? $steam[0].price : $null); steamDiscountPercent = ($steam.Count ? $steam[0].discount : $null)
        bestOfficialPrice = ($priced.Count ? $priced[0].price : $null); bestOfficialStore = ($priced.Count ? $priced[0].store : $null)
        officialDiscountNowPercent = ($officialDiscounts.Count ? ($officialDiscounts | Measure-Object -Maximum).Maximum : $null)
        lowestSeenAllStores = $lowest; lowestSeenAllStoresDate = Get-CalendarField $waitOrBuy 'lowestEverDate'; deepestDiscountAllStoresPercent = $deepest
        historyWeeks = @($history).Count
        historyLowAllStores = (@($history).Count ? (@($history) | Measure-Object -Minimum).Minimum : $null)
        historyHighAllStores = (@($history).Count ? (@($history) | Measure-Object -Maximum).Maximum : $null)
        historySynthetic = [bool](Get-CalendarField $data 'historySynthetic'); historyThin = [bool](Get-CalendarField $data 'thin')
        honestyScore = Get-CalendarField (Get-CalendarField $data 'honesty') 'score'
        verdict = Get-CalendarField $waitOrBuy 'action'; nextDropHintDays = Get-CalendarField $waitOrBuy 'nextDropHintDays'
        playersNow = Get-CalendarField $game 'playersNow'
    }
}

function Get-CalendarCachePath([string]$ProjectDir, [string]$Name) { return Join-Path $ProjectDir ".godot/hyperdot-calendar/$Name" }

# A page from the cache when it is under $CacheHours old (or with -Offline, at any age), else from the network, cached on
# success. A failed fetch falls back to an older cached copy, marked stale. Never throws: the error is in the result.
function Get-CalendarDocument([string]$Url, [string]$CacheFile, [bool]$Offline) {
    $result = [ordered]@{ body = $null; fetchedAt = $null; cached = $false; stale = $false; error = $null }
    $cachedAt = (Test-Path -LiteralPath $CacheFile) ? (Get-Item -LiteralPath $CacheFile).LastWriteTimeUtc : $null
    $fresh = $null -ne $cachedAt -and ([datetime]::UtcNow - $cachedAt).TotalHours -lt $script:CalendarCacheHours
    if ($null -ne $cachedAt -and ($fresh -or $Offline)) {
        $result.body = Get-Content -LiteralPath $CacheFile -Raw -Encoding utf8
        $result.fetchedAt = $cachedAt.ToString('o'); $result.cached = $true; $result.stale = -not $fresh
        return $result
    }
    if ($Offline) { $result.error = 'no cached copy (-Offline reads only the cache)'; return $result }
    try {
        $ProgressPreference = 'SilentlyContinue'
        $response = Invoke-WebRequest -Uri $Url -UserAgent $script:CalendarUserAgent -TimeoutSec 30 -MaximumRedirection 5 -SkipHttpErrorCheck
        if ($response.StatusCode -ne 200) { throw "HTTP $($response.StatusCode)" }
        $content = $response.Content -is [byte[]] ? [System.Text.Encoding]::UTF8.GetString($response.Content) : "$($response.Content)"
        New-Item -ItemType Directory -Force (Split-Path $CacheFile) | Out-Null
        Set-Content -LiteralPath $CacheFile -Value $content -Encoding utf8 -NoNewline
        $result.body = $content; $result.fetchedAt = [datetime]::UtcNow.ToString('o')
    } catch {
        $result.error = "$($_.Exception.Message)"
        if ($null -ne $cachedAt) {
            $result.body = Get-Content -LiteralPath $CacheFile -Raw -Encoding utf8
            $result.fetchedAt = $cachedAt.ToString('o'); $result.cached = $true; $result.stale = $true
        }
    }
    return $result
}

# The release against the events: which seasonal sales the game can join (released at least 30 days before the start,
# or part-way once the 30 days after release end), what falls on release day, whether release.nextFest is an edition
# Valve lists, the last Next Fest before release when none is planned, and Epic giveaways in launch week.
function Get-CalendarRelease($Release, [object[]]$Events, [datetime]$Today) {
    $releaseDay = ConvertTo-PlanDate (Get-CalendarField $Release 'date')
    if ($null -eq $releaseDay) { return $null }
    $warnings = [System.Collections.Generic.List[string]]::new()
    $notes = [System.Collections.Generic.List[string]]::new()
    $firstDiscount = $releaseDay.AddDays($script:SteamDiscountCooldownDays)
    $dated = @($Events | Where-Object { $_.start -and $_.end })

    $seasonal = @(foreach ($item in @($dated | Where-Object { $_.kind -eq 'seasonal-sale' })) {
        $start = ConvertTo-PlanDate $item.start; $end = ConvertTo-PlanDate $item.end
        if ($end -lt $releaseDay) { continue }
        $joinFrom = $start -gt $firstDiscount ? $start : $firstDiscount
        # Valve's sales end at 10 am Pacific on their last day: joining on it leaves nothing to join.
        $joinable = $joinFrom -lt $end
        [ordered]@{ name = $item.name; start = $item.start; end = $item.end; joinable = $joinable
            partWay = ($joinable -and $joinFrom -gt $start); joinFrom = ($joinable ? (Format-CalendarDay $joinFrom) : $null) }
    })
    $first = @($seasonal | Where-Object { $_.joinable } | Select-Object -First 1)

    foreach ($item in @($dated | Where-Object { $_.kind -in 'seasonal-sale', 'next-fest', 'discount-hub' })) {
        $start = ConvertTo-PlanDate $item.start; $end = ConvertTo-PlanDate $item.end
        if ($releaseDay -lt $start -or $releaseDay -gt $end) { continue }
        $what = switch ($item.kind) {
            'seasonal-sale' { 'the store front is given over to discounts, and a game in its first 30 days cannot join it' }
            'next-fest' { 'Next Fest is for unreleased games: release after it, not during it' }
            default { 'the Discounts & Events page is filled with other games on sale' }
        }
        $notes.Add("Release ($(Format-CalendarDay $releaseDay)) falls in $($item.name) ($($item.start) to $($item.end)): $what.")
    }
    foreach ($item in @($dated | Where-Object { $_.kind -eq 'epic-free' })) {
        $start = ConvertTo-PlanDate $item.start; $end = ConvertTo-PlanDate $item.end
        if ($end -lt $releaseDay -or $start -gt $releaseDay.AddDays(7)) { continue }
        $notes.Add("$($item.name) runs $($item.start) to $($item.end), in launch week: check whether it is in the same genre.")
    }

    # A discount marked seasonal is exempt from the 30 days between discounts only if it is a Steam seasonal sale: check
    # it against the sales Valve lists (when the page was read; it lists only upcoming ones, so past discounts are skipped).
    $sales = @($dated | Where-Object { $_.kind -eq 'seasonal-sale' })
    if ($sales.Count) {
        foreach ($discount in @((Get-PlannedDiscounts $Release $releaseDay).discounts | Where-Object { $_.seasonal -and $_.end -ge $Today })) {
            $overlaps = @($sales | Where-Object { $discount.start -le (ConvertTo-PlanDate $_.end) -and $discount.end -ge (ConvertTo-PlanDate $_.start) })
            if ($overlaps.Count -eq 0) {
                $warnings.Add("The discount '$($discount.label)' is marked seasonal, but $(Format-CalendarDay $discount.start) to $(Format-CalendarDay $discount.end) is in no Steam seasonal sale Valve lists ($(@($sales | ForEach-Object { "$($_.name) $($_.start) to $($_.end)" }) -join '; ')); only those four sales are exempt from the 30 days between discounts.")
            }
        }
    }

    $editions = @($dated | Where-Object { $_.kind -eq 'next-fest' } | Sort-Object { $_.start })
    $planned = ConvertTo-PlanDate (Get-CalendarField $Release 'nextFest')
    # The demo goes to review 3 weeks before the festival, 5 with the press preview (as Plan.ps1's release timeline).
    $press = (Get-CalendarField $Release 'pressPreview') -eq $true
    $reviewDays = $press ? 35 : $script:CalendarDemoReviewDays
    $nextFest = [ordered]@{ planned = ($planned ? (Format-CalendarDay $planned) : $null); edition = $null; suggested = $null; demoReviewBy = $null }
    if ($planned) {
        $match = @($editions | Where-Object { $_.start -eq (Format-CalendarDay $planned) } | Select-Object -First 1)
        if ($match.Count) { $nextFest.edition = $match[0].name }
        # Valve lists only upcoming editions: one that has begun can no longer be matched, and is not wrong for that.
        elseif ($editions.Count -and $planned -ge $Today) { $warnings.Add("release.nextFest ($(Format-CalendarDay $planned)) is not the first day of a Next Fest Valve lists: $(@($editions | ForEach-Object { "$($_.name) starts $($_.start)" }) -join '; ').") }
    } elseif ($releaseDay -gt $Today) {
        $before = @($editions | Where-Object { (ConvertTo-PlanDate $_.end) -lt $releaseDay -and (ConvertTo-PlanDate $_.start).AddDays(-$reviewDays) -ge $Today } | Select-Object -Last 1)
        if ($before.Count) {
            $by = (ConvertTo-PlanDate $before[0].start).AddDays(-$reviewDays)
            $nextFest.suggested = $before[0].name; $nextFest.demoReviewBy = Format-CalendarDay $by
            $notes.Add("The last Next Fest before release is $($before[0].name), $($before[0].start) to $($before[0].end): the demo goes to review by $(Format-CalendarDay $by) ($($press ? '5 weeks before, with the press preview' : '3 weeks before; 5 with the press preview')); set release.nextFest to $($before[0].start) to plan it.")
        }
    }
    return [ordered]@{ date = Format-CalendarDay $releaseDay; firstDiscount = Format-CalendarDay $firstDiscount
        seasonalSales = @($seasonal); firstSeasonalSale = ($first.Count ? $first[0].name : $null); nextFest = $nextFest
        warnings = @($warnings); notes = @($notes) }
}

# The comparables' medians: what similar games cost (to the cent) and how deep they have been cut (whole percent).
function Get-CalendarComparableSummary([object[]]$Games) {
    $base = [double[]]@($Games | ForEach-Object { $_['basePrice'] } | Where-Object { $null -ne $_ })
    $deepest = [double[]]@($Games | ForEach-Object { $_['deepestDiscountAllStoresPercent'] } | Where-Object { $null -ne $_ })
    $now = [double[]]@($Games | ForEach-Object { $_['steamDiscountPercent'] } | Where-Object { $null -ne $_ })
    $official = [double[]]@($Games | ForEach-Object { $_['officialDiscountNowPercent'] } | Where-Object { $null -ne $_ })
    return [ordered]@{ games = @($Games).Count
        medianBasePrice = Get-RunMedian $base 2
        medianDeepestDiscountAllStoresPercent = Get-RunMedian $deepest 0
        medianSteamDiscountNowPercent = Get-RunMedian $now 0
        medianOfficialDiscountNowPercent = Get-RunMedian $official 0 }
}

function ConvertTo-IcsText([string]$Text) {
    return ($Text -replace '\\', '\\' -replace ';', '\;' -replace ',', '\,' -replace "`r?`n", '\n')
}

# RFC 5545 folds lines longer than 75 octets: CRLF and a space, never inside a UTF-8 character.
function Add-IcsLine([System.Collections.Generic.List[string]]$Lines, [string]$Line) {
    $builder = [System.Text.StringBuilder]::new()
    $octets = 0
    foreach ($rune in $Line.EnumerateRunes()) {
        $size = $rune.Utf8SequenceLength
        if ($octets + $size -gt 74) { $Lines.Add($builder.ToString()); [void]$builder.Clear().Append(' '); $octets = 1 }
        [void]$builder.Append($rune.ToString()); $octets += $size
    }
    $Lines.Add($builder.ToString())
}

# calendar.ics: every dated event, the release timeline's deadlines and the planned discounts as all-day events, for a
# calendar app to import or subscribe to. A UID is made from what names an event, not its dates (a Valve event by its
# name and year, an Epic discount window by its days, a planned discount by its name), so importing the file again
# updates an event whose dates moved instead of adding a second one.
function Write-CalendarIcs([string]$Path, [string]$Game, [object[]]$Events, $Timeline, $Release) {
    $lines = [System.Collections.Generic.List[string]]::new()
    $stamp = [datetime]::UtcNow.ToString("yyyyMMdd'T'HHmmss'Z'", [cultureinfo]::InvariantCulture)
    $sha = [System.Security.Cryptography.SHA256]::Create()
    $entries = [System.Collections.Generic.List[object]]::new()
    foreach ($item in @($Events | Where-Object { $_.start -and $_.end })) {
        $key = switch ($item.kind) {
            'epic-discounts' { "epic|epic-discounts|$($item.start)|$($item.end)" }
            'epic-free' { "epic|epic-free|$($item.name)|$($item.start)" }
            default { "$($item.source)|$($item.kind)|$($item.name)|$($item.start.Substring(0, 4))" }
        }
        $entries.Add([pscustomobject]@{ key = $key; summary = $item.name; start = $item.start; end = $item.end
                url = ($item.registration ? $item.registration : $item.url); description = (@($item.notes, $item.url) | Where-Object { $_ }) -join "`n" })
    }
    if ($Timeline) {
        $labels = [ordered]@{ steamFee = 'Pay the Steam app fee (21 days before release)'; storePageReview = 'Submit the store page for review'
            comingSoon = 'Coming Soon page live (2 weeks before release)'; buildReview = 'Submit the release build for review'
            dateLock = 'Release date locks on Steam'; demoReview = 'Submit the Next Fest demo for review'; firstDiscount = 'First day a discount other than the launch discount can start' }
        foreach ($name in $labels.Keys) {
            $day = Get-CalendarField $Timeline.deadlines $name
            if ($day) { $entries.Add([pscustomobject]@{ key = "plan|$name"; summary = "$($Game): $($labels[$name])"; start = $day; end = $day; url = $null; description = 'From plan.json (hyperdot plan).' }) }
        }
        $entries.Add([pscustomobject]@{ key = 'plan|release'; summary = "$($Game): release day"; start = $Timeline.date; end = $Timeline.date; url = $null; description = 'release.date in plan.json.' })
    }
    # Only the discounts the plan check could read: one it ignored (bad dates, an end before its start) is not drawn.
    $releaseDay = ConvertTo-PlanDate (Get-CalendarField $Release 'date')
    if ($releaseDay) {
        $seen = @{}   # label -> how many so far, in start order: two discounts of one name get their own UIDs
        foreach ($discount in @((Get-PlannedDiscounts $Release $releaseDay).discounts)) {
            $seen[$discount.label] = 1 + ($seen.ContainsKey($discount.label) ? $seen[$discount.label] : 0)
            $entries.Add([pscustomobject]@{ key = "plan|discount|$($discount.label)|$($seen[$discount.label])"; summary = "$($Game): $($discount.label) $($discount.percent)%"
                    start = Format-CalendarDay $discount.start; end = Format-CalendarDay $discount.end; url = $null
                    description = $discount.launch ? 'release.launchDiscount in plan.json.' : 'release.discounts in plan.json.' })
        }
    }
    $lines.Add('BEGIN:VCALENDAR'); $lines.Add('VERSION:2.0'); $lines.Add('PRODID:-//hyperdot//calendar//EN'); $lines.Add('CALSCALE:GREGORIAN')
    Add-IcsLine $lines "X-WR-CALNAME:$(ConvertTo-IcsText "$Game marketing calendar")"
    foreach ($entry in $entries) {
        $hash = -join ($sha.ComputeHash([System.Text.Encoding]::UTF8.GetBytes($entry.key)) | Select-Object -First 12 | ForEach-Object { $_.ToString('x2') })
        $start = ConvertTo-PlanDate $entry.start; $end = ConvertTo-PlanDate $entry.end
        $lines.Add('BEGIN:VEVENT')
        $lines.Add("UID:$hash@hyperdot"); $lines.Add("DTSTAMP:$stamp")
        $lines.Add("DTSTART;VALUE=DATE:$($start.ToString('yyyyMMdd', [cultureinfo]::InvariantCulture))")
        $lines.Add("DTEND;VALUE=DATE:$($end.AddDays(1).ToString('yyyyMMdd', [cultureinfo]::InvariantCulture))")
        Add-IcsLine $lines "SUMMARY:$(ConvertTo-IcsText $entry.summary)"
        if ($entry.url) { Add-IcsLine $lines "URL:$($entry.url)" }
        if ($entry.description) { Add-IcsLine $lines "DESCRIPTION:$(ConvertTo-IcsText $entry.description)" }
        $lines.Add('TRANSP:TRANSPARENT')
        $lines.Add('END:VEVENT')
    }
    $lines.Add('END:VCALENDAR')
    $sha.Dispose()
    New-Item -ItemType Directory -Force (Split-Path $Path) | Out-Null
    [System.IO.File]::WriteAllText([System.IO.Path]::GetFullPath($Path), (($lines -join "`r`n") + "`r`n"), [System.Text.UTF8Encoding]::new($false))
    return $entries.Count
}

function Invoke-Calendar($Info, [string[]]$Source, [int]$Days, [bool]$Offline, [string[]]$Comparable, [string]$ResultsDir) {
    $sources = @($Source | ForEach-Object { "$_" -split ',' } | ForEach-Object { $_.Trim().ToLowerInvariant() } | Where-Object { $_ } | Select-Object -Unique)
    if ($sources.Count -eq 0) { $sources = $script:CalendarSources }
    foreach ($name in $sources) {
        if ($name -notin $script:CalendarSources) { Stop-GodotCi "-Source $name is not one of: $($script:CalendarSources -join ', ')" 'invalid-arguments' }
    }
    if ($Days -lt 1 -or $Days -gt $script:CalendarMaxDays) { Stop-GodotCi "-Days must be 1 to $($script:CalendarMaxDays) (how far ahead to list events), not $Days" 'invalid-arguments' }
    $today = [datetime]::UtcNow.Date
    $horizon = $today.AddDays($Days)
    $warnings = [System.Collections.Generic.List[string]]::new()

    # plan.json is optional here: without it (or without release.date) the events are listed and nothing is related.
    $planPath = Get-PlanPath $Info
    $plan = $null
    if (Test-Path -LiteralPath $planPath) {
        try { $plan = Get-Content -LiteralPath $planPath -Raw | ConvertFrom-Json -Depth 10 }
        catch { $warnings.Add("$planPath is not valid JSON, so the release was not related to the events: $($_.Exception.Message)") }
    }
    $release = $plan ? (Get-CalendarField $plan 'release') : $null
    $game = $plan -and (Get-CalendarField $plan 'game') ? "$($plan.game)" : $Info.DisplayName

    $slugs = @($Comparable | ForEach-Object { "$_" -split ',' } | ForEach-Object { $_.Trim().ToLowerInvariant() } | Where-Object { $_ } | Select-Object -Unique)
    $fromPlan = $slugs.Count -eq 0
    if ($fromPlan) { $slugs = @(Get-CalendarField $release 'comparables' | ForEach-Object { "$_".Trim().ToLowerInvariant() } | Where-Object { $_ } | Select-Object -Unique) }
    $badSlugs = @($slugs | Where-Object { $_ -notmatch '^[a-z0-9][a-z0-9-]{0,99}$' })
    if ($badSlugs.Count) {
        if (-not $fromPlan) { Stop-GodotCi "-Comparable takes LootRadar slugs (lowercase letters, digits and hyphens, as in lootradar.gg/game/<slug>), not: $($badSlugs -join ', ')" 'invalid-arguments' }
        $warnings.Add("release.comparables holds what is not a LootRadar slug (lootradar.gg/game/<slug>), skipped: $($badSlugs -join ', ')")
        $slugs = @($slugs | Where-Object { $_ -notin $badSlugs })
    }
    if ($slugs.Count -gt $script:CalendarMaxComparables) {
        $warnings.Add("Only the first $($script:CalendarMaxComparables) comparables are read, not $($slugs.Count).")
        $slugs = @($slugs | Select-Object -First $script:CalendarMaxComparables)
    }

    $events = [System.Collections.Generic.List[object]]::new()
    # Every event read, in the window or not: the release is related to all of them, so -Days only narrows the list.
    $allEvents = [System.Collections.Generic.List[object]]::new()
    $status = [System.Collections.Generic.List[object]]::new()
    $comparables = [System.Collections.Generic.List[object]]::new()
    foreach ($name in $sources) {
        $entry = [ordered]@{ source = $name; url = $script:CalendarUrls[$name]; attribution = $script:CalendarAttribution[$name]
            ok = $false; cached = $false; stale = $false; fetchedAt = $null; items = 0; error = $null }
        if ($name -eq 'lootradar') {
            if ($slugs.Count -eq 0) { $entry.error = 'no comparables: list LootRadar slugs in plan.json release.comparables or pass -Comparable'; $status.Add($entry); continue }
            $errors = [System.Collections.Generic.List[string]]::new()
            foreach ($slug in $slugs) {
                $query = [uri]::EscapeDataString("{`"json`":{`"slug`":`"$slug`"}}")
                $doc = Get-CalendarDocument "$($script:CalendarUrls.lootradar)?input=$query" (Get-CalendarCachePath $Info.ProjectDir "lootradar-$slug.json") $Offline
                if ($doc.error -and -not $doc.body) { $errors.Add("${slug}: $($doc.error)"); continue }
                if ($doc.error) { $errors.Add("${slug}: $($doc.error) (an older cached copy was used)") }
                try { $parsed = ConvertFrom-LootRadarGame $doc.body $slug } catch { $parsed = $null }
                if ($null -eq $parsed) { $errors.Add("${slug}: LootRadar returned no game by that slug"); continue }
                $parsed['fetchedAt'] = $doc.fetchedAt
                $comparables.Add($parsed)
                $entry.cached = $entry.cached -or $doc.cached; $entry.stale = $entry.stale -or $doc.stale
                if (-not $entry.fetchedAt -or $doc.fetchedAt -lt $entry.fetchedAt) { $entry.fetchedAt = $doc.fetchedAt }
            }
            $entry.items = $comparables.Count; $entry.ok = $comparables.Count -gt 0
            if ($errors.Count) { $entry.error = $errors -join '; ' }
            $status.Add($entry); continue
        }
        $doc = Get-CalendarDocument $script:CalendarUrls[$name] (Get-CalendarCachePath $Info.ProjectDir "$name.$($name -eq 'epic' ? 'json' : 'html')") $Offline
        $entry.cached = $doc.cached; $entry.stale = $doc.stale; $entry.fetchedAt = $doc.fetchedAt; $entry.error = $doc.error
        if ($doc.body) {
            $found = @(try {
                    switch ($name) {
                        'steam' { ConvertFrom-SteamEventsHtml $doc.body }
                        'itch' { ConvertFrom-ItchJamsHtml $doc.body $today $horizon }
                        'epic' { ConvertFrom-EpicFreeGamesJson $doc.body }
                    }
                } catch { $entry.error = "could not be read: $($_.Exception.Message)" })
            $found = @($found | Where-Object { $_ -is [System.Collections.IDictionary] })
            if ($found.Count -eq 0 -and -not $entry.error) { $entry.error = 'the page held no events the kit could read: its layout may have changed' }
            $inWindow = @($found | Where-Object { $_.tbd -or ((ConvertTo-PlanDate $_.end) -ge $today -and (ConvertTo-PlanDate $_.start) -le $horizon) })
            foreach ($item in $inWindow) { $events.Add($item) }
            foreach ($item in $found) { $allEvents.Add($item) }
            $entry.items = $inWindow.Count; $entry.ok = $found.Count -gt 0
        }
        $status.Add($entry)
    }
    foreach ($entry in $status) {
        if (-not $entry.ok -or $entry.error) { $warnings.Add("$($entry.source): $(if ($entry.ok) { 'used, but ' })$($entry.error)") }
        elseif ($entry.stale) { $warnings.Add("$($entry.source): read from a cached copy of $($entry.fetchedAt), over $($script:CalendarCacheHours) hours old") }
    }
    if (@($status | Where-Object { $_.ok }).Count -eq 0) {
        Set-JsonField calendar ([ordered]@{ sources = @($status) })
        $why = @($status | ForEach-Object { "$($_.source): $($_.error)" }) -join '; '
        Stop-GodotCi "No calendar source could be read ($why). Check the network, or run again without -Offline once to fill the cache" 'calendar-unavailable'
    }

    $sorted = @(@($events | Where-Object { -not $_.tbd } | Sort-Object { $_.start }, { $_.name }) + @($events | Where-Object { $_.tbd }))
    $timeline = $null
    $relation = $null
    if ($release -and (ConvertTo-PlanDate (Get-CalendarField $release 'date'))) {
        $line = Get-ReleaseTimeline $release $today
        $timeline = $line.timeline
        foreach ($warning in $line.warnings) { $warnings.Add($warning) }
        $relation = Get-CalendarRelease $release @($allEvents) $today
        foreach ($warning in $relation.warnings) { $warnings.Add($warning) }
        $relation['notes'] = @(@($line.notes) + @($relation.notes))
    }
    $icsPath = Join-Path $ResultsDir 'calendar.ics'
    $icsEvents = Write-CalendarIcs $icsPath $game $sorted $timeline $release

    $byKind = [ordered]@{}
    foreach ($kind in 'seasonal-sale', 'next-fest', 'themed-fest', 'discount-hub', 'jam', 'epic-free', 'epic-discounts') { $byKind[$kind] = @($sorted | Where-Object { $_.kind -eq $kind }).Count }
    Write-CiLog "Calendar for $game, $(Format-CalendarDay $today) to $(Format-CalendarDay $horizon): $(@($byKind.Keys | Where-Object { $byKind[$_] } | ForEach-Object { "$($byKind[$_]) $_" }) -join ', ')"
    foreach ($item in @($sorted | Where-Object { $_.kind -in 'seasonal-sale', 'next-fest', 'discount-hub' })) {
        Write-CiLog "  $(if ($item.tbd) { 'TBD       ' } else { $item.start }) $($item.name)$(if (-not $item.tbd) { " (to $($item.end))" })"
    }
    if ($relation) {
        Write-CiLog "Release $($relation.date): first seasonal sale it can join: $(if ($relation.firstSeasonalSale) { $relation.firstSeasonalSale } else { 'none listed yet' }); first discount from $($relation.firstDiscount)"
        foreach ($note in $relation.notes) { Write-CiLog "  $note" }
    } elseif (-not $release -or -not (Get-CalendarField $release 'date')) {
        Write-CiLog "No release.date in plan.json: set it to relate the release to these events ($(Format-KitCommand 'plan'))."
    }
    foreach ($similar in $comparables) {
        Write-CiLog "  $($similar.title): base $($similar.basePrice), Steam now $($similar.steamPrice) (-$($similar.steamDiscountPercent)%), lowest seen at any store, keyshops included, $($similar.lowestSeenAllStores) (-$($similar.deepestDiscountAllStoresPercent)%)"
    }
    foreach ($warning in $warnings) { Write-CiLog "WARNING: $warning" }
    Write-CiLog "Wrote $icsPath ($icsEvents events)"

    $used = @($status | Where-Object { $_.ok } | ForEach-Object { $_.attribution })
    Set-JsonField calendar ([ordered]@{
            today = Format-CalendarDay $today; until = Format-CalendarDay $horizon; days = $Days; offline = $Offline
            sources = @($status); events = $sorted; counts = $byKind
            release = $relation; timeline = $timeline
            comparables = @($comparables); comparableSummary = ($comparables.Count ? (Get-CalendarComparableSummary @($comparables)) : $null)
            ics = $icsPath; attribution = $used })
    Set-JsonField warnings @($warnings)
}
