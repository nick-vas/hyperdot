#!/usr/bin/env pwsh
# Self-test of promo, the weekly marketing brief, and init -Promo. A fixture repository (a copy of examples/gdscript with a
# workflow calling the kit) and a mocked GitHub API and GitHub Models (tests/promo-fixture/MockGitHub.ps1, an HttpListener on
# 127.0.0.1) cover: the gate on a red-then-green history and through a merged pull request's head; trailers in a pull
# request's description; carrying over last week's unticked tasks; the issue, then the mkt/N tag, then the close, with a
# close that fails; @ mentions broken; AI drafts falling back on an error and on a Bluesky post that is too long; a dry run
# writing nothing but the job summary; a week with nothing shipped; and the error codes. No Godot is needed.
Set-StrictMode -Version 3.0
$ErrorActionPreference = 'Stop'
$root = Split-Path $PSScriptRoot
$ci = Join-Path $root 'ci/godot/hyperdot.ps1'
$failures = @()
function Assert-True([bool]$Condition, [string]$Name) {
    if ($Condition) { Write-Host "ok     $Name" } else { Write-Host "FAIL   $Name"; $script:failures += $Name }
}
foreach ($lib in 'Common', 'Plan', 'Calendar', 'Init', 'Promo') { . (Join-Path $root "ci/godot/lib/$lib.ps1") }
$zwsp = [string][char]0x200B

# --- Pure parts ---
$today = [datetime]'2026-11-16'
$stageOf = { param($r) Get-PromoStage ([pscustomobject]$r) $today }
Assert-True ((Get-PromoStage $null $today) -eq 'development' -and (& $stageOf @{ date = $null; comingSoon = $null }) -eq 'development') 'no release block, or nothing set, is development'
Assert-True ((& $stageOf @{ comingSoon = '2026-10-01' }) -eq 'store-page' -and (& $stageOf @{ storePageSubmitted = '2026-10-01' }) -eq 'store-page') 'comingSoon or storePageSubmitted is store-page'
Assert-True ((& $stageOf @{ comingSoon = '2026-10-01'; nextFest = '2027-02-22' }) -eq 'demo' -and (& $stageOf @{ demoSubmitted = '2026-11-01' }) -eq 'demo') 'demoSubmitted or nextFest is demo'
Assert-True ((& $stageOf @{ date = '2026-11-16'; nextFest = '2026-10-01' }) -eq 'launched' -and (& $stageOf @{ date = '2026-12-01'; demoSubmitted = '2026-11-01' }) -eq 'demo') 'a release date reached is launched; one ahead is not'
Assert-True ((Protect-PromoMentions 'thanks @alice and @bob-2, not @ alone') -eq "thanks @${zwsp}alice and @${zwsp}bob-2, not @ alone") 'an @name gets a zero-width space after the @'
$trailers = @(Get-PromoTrailers "Title`n`nMarketing: One`nmarketing: Two`nMarketing-Priority: HIGH`nMarketing-Visual: yes" ('a' * 40) 'commit')
Assert-True ($trailers.Count -eq 2 -and $trailers[0].priority -eq 'high' -and $trailers[1].visual -and $trailers[0].text -eq 'One') 'every Marketing line is an item, with the message''s priority and visual flag (any case)'
$long = @([ordered]@{ text = ('Storms ' * 80).Trim(); priority = 'high'; visual = $false; sha = ('a' * 40); source = 'commit' }, [ordered]@{ text = 'Second'; priority = 'low'; visual = $false; sha = ('b' * 40); source = 'commit' })
$templates = New-PromoTemplateDrafts 'Game' $long @('discord', 'bluesky', 'steam') @('#indiedev')
Assert-True ((Get-PromoGraphemeCount $templates.bluesky) -le 300 -and $templates.bluesky.EndsWith(' #indiedev') -and $templates.bluesky.Contains([string][char]0x2026)) "the Bluesky template stays within 300 graphemes, the item cut with an ellipsis: $(Get-PromoGraphemeCount $templates.bluesky)"
Assert-True ($templates.steam.Contains('[list]') -and $templates.discord.StartsWith('**Game')) 'the Steam template is BBCode, the Discord one Markdown'

# --- A fixture repository and the mocked API ---
$work = Join-Path ([System.IO.Path]::GetTempPath()) "promo-$([guid]::NewGuid().ToString('n').Substring(0, 8))"
$repo = Join-Path $work 'game'
Copy-Item -LiteralPath (Join-Path $root 'examples/gdscript') -Destination $repo -Recurse
New-Item -ItemType Directory -Force (Join-Path $repo '.github/workflows') | Out-Null
Set-Content -LiteralPath (Join-Path $repo '.github/workflows/hyperdot.yml') -Value "name: Godot`non: [push]`njobs:`n  godot:`n    uses: nick-vas/hyperdot/.github/workflows/godot.yml@v1`n"
function Invoke-Git { $null = & git -C $repo -c user.name=Test -c user.email=test@example.com @args; if ($LASTEXITCODE) { throw "git $args failed" } }
function New-Commit([string]$Message) {
    Add-Content -LiteralPath (Join-Path $repo 'changes.txt') -Value $Message
    Invoke-Git add -A; Invoke-Git commit -q -m $Message
    return (& git -C $repo rev-parse HEAD).Trim()
}
Invoke-Git init -q -b main
$null = New-Commit 'Base'
$c2 = New-Commit "Add meteor storms`n`nMarketing: Meteor storms can now rain down on @someone's base`nMarketing-Priority: high`nMarketing-Visual: yes"
$c3 = New-Commit "Faster menus`n`nMarketing: Menus open twice as fast`nMarketing-Priority: low"
$c4 = New-Commit "Night mode`n`nMarketing: A night mode for late sessions"

$port = & { $l = [System.Net.Sockets.TcpListener]::new([System.Net.IPAddress]::Loopback, 0); $l.Start(); $p = $l.LocalEndpoint.Port; $l.Stop(); $p }
$routesFile = Join-Path $work 'routes.json'; $logFile = Join-Path $work 'requests.jsonl'; $summary = Join-Path $work 'summary.md'
$api = "http://127.0.0.1:$port"
function Set-Routes([hashtable]$Table) { Set-Content -LiteralPath $routesFile -Value ($Table | ConvertTo-Json -Depth 20) -Encoding utf8; Set-Content -LiteralPath $logFile -Value $null; Set-Content -LiteralPath $summary -Value $null }
function Get-Requests { return @(Get-Content -LiteralPath $logFile | Where-Object { $_ } | ForEach-Object { $_ | ConvertFrom-Json -Depth 5 }) }
function New-Checks([string]$Conclusion) { return @{ status = 200; body = @{ total_count = 1; check_runs = @(@{ name = 'godot / Test'; status = 'completed'; conclusion = $Conclusion }) } } }
$lastBrief = "<!-- hyperdot-promo mkt/0 -->`n## Shipped`n`n- [ ] not a task either`n`n## Tasks`n`n- [ ] Record a clip: The old harbour`n- [x] Post on Discord`n- [ ] Post on Bluesky (from #2)`n- [ ] Answer the comments on @carol's thread`n`n## Drafts`n`n``````text`n- [ ] a box inside a draft`n```````n"
$openBriefs = @{ status = 200; body = @(@{ number = 3; title = 'Marketing brief 0'; body = $lastBrief; labels = @(@{ name = 'marketing-brief' }) },
        @{ number = 8; title = 'A pull request with the label'; body = "## Tasks`n- [ ] from a pull request"; pull_request = @{ url = 'x' } }) }
$redThenGreen = @{
    "GET /repos/o/r/commits/$c3/check-runs" = New-Checks 'failure'
    "GET /repos/o/r/commits/$c2/check-runs" = New-Checks 'success'
    'GET /repos/o/r/issues' = $openBriefs
    'POST /repos/o/r/issues' = @{ status = 201; body = @{ number = 4; html_url = 'https://github.com/o/r/issues/4' } }
    'POST /repos/o/r/git/refs' = @{ status = 201; body = @{ ref = 'refs/tags/mkt/1' } }
    'PATCH /repos/o/r/issues/3' = @{ status = 200; body = @{ number = 3; state = 'closed' } }
}
Set-Routes $redThenGreen
$server = Start-Process pwsh -PassThru -ArgumentList @('-NoProfile', '-NonInteractive', '-File', "`"$(Join-Path $PSScriptRoot 'promo-fixture/MockGitHub.ps1')`"", '-Port', "$port", '-Routes', "`"$routesFile`"", '-Log', "`"$logFile`"")
$saved = @{}
foreach ($name in 'GITHUB_API_URL', 'HYPERDOT_MODELS_URL', 'GITHUB_TOKEN', 'GH_TOKEN', 'GITHUB_REPOSITORY', 'GITHUB_STEP_SUMMARY') { $saved[$name] = [Environment]::GetEnvironmentVariable($name) }
$env:GITHUB_API_URL = $api; $env:HYPERDOT_MODELS_URL = "$api/models"; $env:GITHUB_TOKEN = 'test-token'; $env:GH_TOKEN = $null
$env:GITHUB_REPOSITORY = 'o/r'; $env:GITHUB_STEP_SUMMARY = $summary
function Invoke-PromoCli([string[]]$Extra = @()) {
    $out = & pwsh -NoProfile -NonInteractive -File $ci promo -Json -Project $repo @Extra 2>$null | Out-String
    $code = $LASTEXITCODE
    try { $doc = $out | ConvertFrom-Json -Depth 30 } catch { $doc = $null; Write-Host $out }
    return @{ code = $code; doc = $doc }
}
try {
    for ($i = 0; $i -lt 50; $i++) {
        try { $null = Invoke-WebRequest -Uri "$api/ping" -SkipHttpErrorCheck -TimeoutSec 2; break } catch { Start-Sleep -Milliseconds 200 }
    }
    Set-Routes $redThenGreen

    # --- Dry run: the gate walks past a commit with no run and a red one to the green one; nothing is written ---
    $run = Invoke-PromoCli @('-DryRun')
    $p = $run.doc.promo
    Assert-True ($run.code -eq 0 -and $run.doc.ok -and $p.check -eq 'godot / Test' -and $p.green -and $p.green.sha -eq $c2 -and $p.green.via -eq 'check') "the gate is the newest green commit, past a commit with no run and a failed one: $(if ($p.green) { $p.green.sha } else { "none" })"
    Assert-True (@($p.shipped).Count -eq 1 -and $p.shipped[0].text -eq "Meteor storms can now rain down on @someone's base" -and @($p.waiting).Count -eq 2) 'the green commit''s change shipped, as written; the two newer ones wait'
    Assert-True ($p.range.firstRun -and $p.number -eq 1 -and $p.dryRun -and -not $p.written -and $null -eq $p.issue -and $null -eq $p.tag) 'with no mkt tag it is the first run, brief 1, and a dry run writes nothing'
    $requests = @(Get-Requests)
    Assert-True (@($requests | Where-Object { $_.method -ne 'GET' }).Count -eq 0) "a dry run only reads the API: $(@($requests | ForEach-Object { "$($_.method) $($_.path)" }) -join ', ')"
    $checkQueries = @($requests | Where-Object { $_.path -match '/check-runs$' } | ForEach-Object { $_.query })
    Assert-True ($checkQueries.Count -ge 3 -and @($checkQueries | Where-Object { $_ -notmatch 'check_name=godot%20%2F%20Test' -or $_ -notmatch 'filter=latest' }).Count -eq 0) "every check-run request asks for the check by name, the latest run: $($checkQueries[0])"
    $issueQuery = @($requests | Where-Object { $_.method -eq 'GET' -and $_.path -eq '/repos/o/r/issues' } | ForEach-Object { $_.query })
    Assert-True ($issueQuery.Count -eq 1 -and $issueQuery[0] -match 'labels=marketing-brief' -and $issueQuery[0] -match 'state=open') "the open briefs are read by label and state: $($issueQuery -join ' ')"
    Assert-True (@($requests | Where-Object { $_.path -eq '/repos/o/r/git/ref/tags/mkt/1' }).Count -eq 1) 'it checks that mkt/1 is not on GitHub before going on'
    $summaryText = Get-Content -LiteralPath $summary -Raw
    Assert-True ($summaryText -match '\(dry run\)' -and $summaryText.Contains('Meteor storms') -and $summaryText.Contains('## Waiting for a green build')) 'a dry run writes the brief to the job summary'
    $body = "$($p.body)"
    Assert-True ($body.Contains('- [ ] Record a clip: Meteor storms') -and $body.Contains('- [ ] Post on Discord') -and $body.Contains('- [ ] Post on Bluesky') -and -not $body.Contains('Steam news')) 'tasks: a clip for the visual change, a post per channel, no Steam before a store page'
    Assert-True ($body.Contains('- [ ] Record a clip: The old harbour (from #3)') -and $body.Contains("- [ ] Answer the comments on @${zwsp}carol's thread (from #3)") -and -not $body.Contains('Post on Bluesky (from #2)') -and -not $body.Contains('Post on Discord (from')) 'unticked tasks carry over naming their brief; ticked ones and ones asked for again do not'
    Assert-True (-not $body.Contains('not a task either') -and -not $body.Contains('a box inside a draft') -and -not $body.Contains('from a pull request') -and @($p.previous).Count -eq 1) 'only the Tasks section carries over, and a pull request with the label is not a brief'
    Assert-True ($body.Contains("- **high** Meteor storms can now rain down on @${zwsp}someone's base") -and $p.drafts.text.discord.Contains("@someone's base")) 'the issue breaks the @ in the lists; the drafts keep it, ready to paste'
    Assert-True ($p.drafts.source -eq 'template' -and -not @($requests | Where-Object { $_.path -eq '/models' }).Count) 'AI is off by default: template drafts, the model never called'

    # --- Real run: the issue, then the tag at the green commit, then last week's brief closed ---
    Set-Routes $redThenGreen
    $run = Invoke-PromoCli
    $p = $run.doc.promo
    $writes = @(Get-Requests | Where-Object { $_.method -ne 'GET' })
    $order = @($writes | ForEach-Object { "$($_.method) $($_.path)" }) -join ', '
    Assert-True ($run.code -eq 0 -and $order -eq 'POST /repos/o/r/issues, POST /repos/o/r/git/refs, PATCH /repos/o/r/issues/3') "issue, tag, close, in that order: $order"
    $tagBody = $writes[1].body | ConvertFrom-Json
    $issueBody = $writes[0].body | ConvertFrom-Json
    Assert-True ($tagBody.ref -eq 'refs/tags/mkt/1' -and $tagBody.sha -eq $c2 -and @($issueBody.labels) -contains 'marketing-brief') 'mkt/1 is tagged at the green commit; the issue is labelled marketing-brief'
    Assert-True ($p.written -and $p.issue.number -eq 4 -and $p.tag -eq 'mkt/1' -and $p.previous[0].closed) 'the result names the issue, the tag and the closed brief'
    $outsideFences = [regex]::Replace($issueBody.body, '(?ms)^(`{3,})text$.*?^\1$', '')
    Assert-True ($outsideFences.Contains("@${zwsp}someone") -and -not $outsideFences.Contains('@someone') -and -not $outsideFences.Contains('@carol') -and $issueBody.title -notmatch '@\w') 'no @name reaches the issue unbroken outside the drafts'
    Assert-True (@($writes | Where-Object { $_.path -match '/issues/8$' }).Count -eq 0) 'the pull request with the label is never closed'

    # --- A close that fails: the tag is already there, the run still succeeds and says so ---
    $failingClose = $redThenGreen.Clone(); $failingClose['PATCH /repos/o/r/issues/3'] = @{ status = 500; body = @{ message = 'Server Error' } }
    Set-Routes $failingClose
    $run = Invoke-PromoCli
    $writes = @(Get-Requests | Where-Object { $_.method -ne 'GET' })
    Assert-True ($run.code -eq 0 -and $run.doc.promo.tag -eq 'mkt/1' -and -not $run.doc.promo.previous[0].closed -and @($run.doc.warnings | Where-Object { $_ -match '#3 could not be closed' }).Count -eq 1 -and $writes[1].path -eq '/repos/o/r/git/refs') 'a failed close leaves the tag made and a warning'

    # --- A failed tag after the issue is an error naming the fix ---
    $failingTag = $redThenGreen.Clone(); $failingTag['POST /repos/o/r/git/refs'] = @{ status = 422; body = @{ message = 'Reference already exists' } }
    Set-Routes $failingTag
    $run = Invoke-PromoCli
    Assert-True ($run.code -ne 0 -and $run.doc.error.code -eq 'promo-api' -and $run.doc.error.message -match 'git tag mkt/1' -and -not @(Get-Requests | Where-Object { $_.method -eq 'PATCH' }).Count) 'a failed tag stops with promo-api before anything is closed'

    # --- A clone with stale tags: mkt/1 is on GitHub already, so nothing is written ---
    $staleTags = $redThenGreen.Clone(); $staleTags['GET /repos/o/r/git/ref/tags/mkt/1'] = @{ status = 200; body = @{ ref = 'refs/tags/mkt/1' } }
    Set-Routes $staleTags
    $run = Invoke-PromoCli
    Assert-True ($run.code -ne 0 -and $run.doc.error.code -eq 'promo-tag-exists' -and $run.doc.error.message -match 'git fetch --tags' -and -not @(Get-Requests | Where-Object { $_.method -ne 'GET' }).Count) 'a tag already on GitHub stops with promo-tag-exists before anything is written'

    # --- Next week: from mkt/1; a squash commit's trailer is in its pull request, and its gate is that pull request's head ---
    Invoke-Git tag mkt/1 $c2
    $c5 = New-Commit 'Co-op (#9)'
    $head = 'f' * 40
    Set-Routes @{
        "GET /repos/o/r/commits/$c5/pulls" = @{ status = 200; body = @(
                @{ number = 10; merged_at = $null; body = 'Marketing: From a pull request never merged'; head = @{ sha = 'e' * 40 } },
                @{ number = 9; merged_at = '2026-11-15T10:00:00Z'; head = @{ sha = $head }
                    body = "Adds co-op.`r`n<!-- Template: write a line like`r`nMarketing: one line players care about`r`n-->`r`n``````text`r`nMarketing: in a code block`r`n```````r`n`r`nMarketing: Two-player co-op`r`nMarketing-Priority: high" }) }
        "GET /repos/o/r/commits/$('e' * 40)/check-runs" = New-Checks 'success'
        "GET /repos/o/r/commits/$head/check-runs" = New-Checks 'success'
        'GET /repos/o/r/issues' = @{ status = 200; body = @() }
        'POST /repos/o/r/issues' = @{ status = 201; body = @{ number = 5; html_url = 'https://github.com/o/r/issues/5' } }
        'POST /repos/o/r/git/refs' = @{ status = 201; body = @{ ref = 'refs/tags/mkt/2' } }
    }
    $run = Invoke-PromoCli
    $p = $run.doc.promo
    $texts = @($p.shipped | ForEach-Object { $_.text })
    Assert-True ($run.code -eq 0 -and $p.green -and $p.green.sha -eq $c5 -and $p.green.via -eq 'pull-request' -and $p.green.pullRequest -eq 9) "a merge or squash commit with no run passes through its pull request's head: $(if ($p.green) { $p.green.via } else { "none" })"
    Assert-True ($p.range.from -eq 'mkt/1' -and $p.number -eq 2 -and $p.tag -eq 'mkt/2' -and $texts.Count -eq 3 -and $texts -contains 'Two-player co-op' -and $texts -notcontains "Meteor storms can now rain down on @someone's base") "the range starts after mkt/1, and the pull request's trailer counts: $($texts -join ' | ')"
    Assert-True (@($p.shipped | Where-Object { $_.source -eq '#9' -and $_.priority -eq 'high' }).Count -eq 1 -and @($p.previous).Count -eq 0) 'the item names its pull request and priority; with no open brief nothing is closed'
    Assert-True ($texts -notcontains 'one line players care about' -and $texts -notcontains 'in a code block' -and $texts -notcontains 'From a pull request never merged') 'trailers in an HTML comment, a code block or a pull request never merged are not read'

    # --- Nothing green: no issue, no tag ---
    Set-Routes @{ "GET /repos/o/r/commits/$c5/check-runs" = New-Checks 'failure'; "GET /repos/o/r/commits/$c4/check-runs" = New-Checks 'failure'; "GET /repos/o/r/commits/$c3/check-runs" = New-Checks 'failure' }
    $run = Invoke-PromoCli
    Assert-True ($run.code -eq 0 -and $run.doc.promo.nothingShipped -match 'passed godot / Test' -and -not @(Get-Requests | Where-Object { $_.method -ne 'GET' }).Count) "a week with nothing green writes nothing: $($run.doc.promo.nothingShipped)"

    # --- AI drafts: on only by setting; an error and a long Bluesky post fall back to the templates ---
    New-Item -ItemType Directory -Force (Join-Path $repo 'docs') | Out-Null
    Set-Content -LiteralPath (Join-Path $repo 'docs/promo.json') -Value '{ "ai": true, "channels": ["discord", "bluesky"], "hashtags": ["#coop"] }'
    $green5 = @{
        "GET /repos/o/r/commits/$c5/pulls" = @{ status = 200; body = @(@{ number = 9; merged_at = '2026-11-15T10:00:00Z'; body = 'Marketing: Two-player co-op'; head = @{ sha = $head } }) }
        "GET /repos/o/r/commits/$head/check-runs" = New-Checks 'success'
        'GET /repos/o/r/issues' = @{ status = 200; body = @() }
    }
    $ai = { param($Status, $Content) $t = $green5.Clone(); $t['POST /models'] = @{ status = $Status; body = @{ choices = @(@{ message = @{ content = $Content } }) } }; $t }
    Set-Routes (& $ai 500 '')
    $run = Invoke-PromoCli @('-DryRun')
    Assert-True ($run.code -eq 0 -and $run.doc.promo.drafts.source -eq 'template' -and $run.doc.promo.drafts.fallbackReason -match 'HTTP 500' -and "$($run.doc.promo.body)".Contains('AI drafts were not used')) 'an error from the model falls back to the templates, and says so'
    Set-Routes (& $ai 200 (@{ discord = 'Co-op is here'; bluesky = ('co-op ' * 60) } | ConvertTo-Json -Depth 3))
    $run = Invoke-PromoCli @('-DryRun')
    Assert-True ($run.doc.promo.drafts.source -eq 'template' -and $run.doc.promo.drafts.fallbackReason -match 'over Bluesky''s 300') "a Bluesky post over 300 graphemes falls back to the templates: $($run.doc.promo.drafts.fallbackReason)"
    Set-Routes (& $ai 200 ("``````json`n" + (@{ discord = 'Co-op is here, thanks @dave ``````'; bluesky = 'Two-player co-op is in! #coop' } | ConvertTo-Json -Depth 3) + "`n``````"))
    $run = Invoke-PromoCli @('-DryRun')
    $p = $run.doc.promo
    $call = @(Get-Requests | Where-Object { $_.path -eq '/models' })
    Assert-True ($p.drafts.source -eq 'ai' -and $p.drafts.text.discord -eq 'Co-op is here, thanks @dave ``````' -and "$($p.body)".Contains("````````text`nCo-op is here") -and "$($p.body)".Contains('check every claim') -and $call.Count -eq 1 -and ($call[0].body | ConvertFrom-Json).model -eq 'openai/gpt-4.1-mini') 'good AI drafts are used as written, in a fence longer than their backticks, labelled "check every claim"'

    # --- Coming up: Steam's dates (a page made relative to today, in the calendar cache) and plan.json's deadlines ---
    $now = [datetime]::UtcNow.Date
    $dayOf = { param([int]$Offset) $now.AddDays($Offset).ToString('yyyy-MM-dd', [cultureinfo]::InvariantCulture) }
    $fest = { param([int]$From, [int]$To, [string]$Name, [string]$OptIn)
        $a = $now.AddDays($From); $b = $now.AddDays($To); $inv = [cultureinfo]::InvariantCulture
        $link = if ($OptIn) { '<a href="' + $OptIn + '">Registration details</a>' } else { '' }
        "<h2 class=""bb_subsection""><strong>$($a.Year) Fests</strong></h2><table><tr><th>Event Dates</th><th>Theme</th><th>Registration</th><th>Notes</th></tr>" +
        "<tr><td>$($a.ToString('MMM d', $inv))<br>$($b.ToString('MMM d', $inv))</td><td>$Name</td><td>$link</td><td>Games. <a href=""https://partner.steamgames.com/doc/x"" class=""bb_doclink"">More info</a>.</td></tr></table>" }
    $nf = { param([int]$From, [int]$To) $inv = [cultureinfo]::InvariantCulture
        "<h2 class=""bb_subsection"">Next Fest | $($now.AddDays($From).ToString('MMMM d', $inv)) - $($now.AddDays($To).ToString('MMMM d, yyyy', $inv))</h2><strong>Registration</strong>: <a href=""https://partner.steamgames.com/optin/sale/nextfest_test"">View registration details</a>" }
    $steamPage = "<div class=""documentation_bbcode""><h2 class=""bb_section"">Themed Sale Events</h2>" + (& $fest 3 10 'Soon Fest' 'https://partner.steamgames.com/optin/sale/soon') +
        (& $fest 20 25 'Later Fest' '') + (& $fest 60 65 'Far Fest' 'https://partner.steamgames.com/optin/sale/far') + "<h2 class=""bb_section"">Next Fest</h2>" + (& $nf 25 32) + '</div>'
    $cache = Join-Path $repo '.godot/hyperdot-calendar'
    New-Item -ItemType Directory -Force $cache | Out-Null
    Set-Content -LiteralPath (Join-Path $cache 'steam.html') -Value $steamPage -Encoding utf8
    New-Item -ItemType Directory -Force (Join-Path $repo 'plan') | Out-Null
    # Release in 40 days with the Coming Soon page set (store-page stage): the app fee is due in 19 days, the rest is past or later.
    Set-Content -LiteralPath (Join-Path $repo 'plan/plan.json') -Value (@{ game = 'Storm Keep'; release = @{ date = (& $dayOf 40); comingSoon = (& $dayOf 5) } } | ConvertTo-Json -Depth 3)
    Set-Content -LiteralPath (Join-Path $repo 'docs/promo.json') -Value '{ "channels": ["discord"] }'
    Set-Routes $green5
    $run = Invoke-PromoCli @('-DryRun')
    $p = $run.doc.promo
    $what = @($p.upcoming | ForEach-Object { "$($_.date) $($_.what)" })
    Assert-True ($run.code -eq 0 -and $p.stage -eq 'store-page' -and -not $p.deadlineOnly -and $p.green) "a normal brief, store-page stage: $($p.stage)"
    Assert-True (@($what | Where-Object { $_ -like "$(& $dayOf 3) Steam Soon Fest*" }).Count -eq 1 -and @($what | Where-Object { $_ -like "$(& $dayOf 20) Steam Later Fest*" }).Count -eq 1 -and -not @($what | Where-Object { $_ -match 'Far Fest' }).Count) "Steam's fests of the next 4 weeks are listed, a later one is not: $($what -join ' | ')"
    Assert-True (@($what | Where-Object { $_ -like "$(& $dayOf 19) Pay Steam's app fee*" }).Count -eq 1 -and -not @($what | Where-Object { $_ -match 'Coming Soon page live|Release day' }).Count) 'an open plan deadline is listed; a done one (comingSoon set) and a date beyond 4 weeks are not'
    Assert-True (@($what | Where-Object { $_ -like "$(& $dayOf 4) The demo for Steam Next Fest*" }).Count -eq 1) 'the last Next Fest before release gives its demo review date'
    $body = "$($p.body)"
    Assert-True ($body.Contains('## Coming up (next 28 days)') -and $body.Contains("- [ ] Opt in to Steam Soon Fest before it starts on $(& $dayOf 3): https://partner.steamgames.com/optin/sale/soon") -and $body.Contains("Pay Steam's app fee (21 days before release): by $(& $dayOf 19)") -and -not $body.Contains('Opt in to Steam Later Fest')) 'a date with an opt-in page or a deadline is a task; one without is only listed'
    Assert-True ($body.Contains('- [ ] Post on Discord') -and $body.Contains('## Drafts') -and $body.IndexOf('## Coming up') -lt $body.IndexOf('## Tasks')) 'the normal brief keeps its posts and drafts, with Coming up before the tasks'

    # Nothing green, a date within a week: a dates-only brief, no tag, last week's brief closed and its open tasks carried.
    Set-Routes @{
        "GET /repos/o/r/commits/$c5/check-runs" = New-Checks 'failure'; "GET /repos/o/r/commits/$c4/check-runs" = New-Checks 'failure'; "GET /repos/o/r/commits/$c3/check-runs" = New-Checks 'failure'
        'GET /repos/o/r/issues' = @{ status = 200; body = @(@{ number = 5; title = 'Marketing brief 1'; body = "## Tasks`n`n- [ ] Post on Discord`n- [ ] Reply to the press" }) }
        'POST /repos/o/r/issues' = @{ status = 201; body = @{ number = 6; html_url = 'https://github.com/o/r/issues/6' } }
        'PATCH /repos/o/r/issues/5' = @{ status = 200; body = @{ number = 5; state = 'closed' } }
    }
    $run = Invoke-PromoCli
    $p = $run.doc.promo
    $writes = @(Get-Requests | Where-Object { $_.method -ne 'GET' })
    $order = @($writes | ForEach-Object { "$($_.method) $($_.path)" }) -join ', '
    Assert-True ($run.code -eq 0 -and $p.deadlineOnly -and $null -eq $p.green -and $p.written -and $null -eq $p.tag -and $order -eq 'POST /repos/o/r/issues, PATCH /repos/o/r/issues/5') "nothing shipped but a date within a week: the issue and the close, no tag: $order"
    Assert-True (-not @(Get-Requests | Where-Object { $_.path -match '/git/ref' }).Count) 'a dates-only brief never looks for or makes a tag'
    $issueBody = $writes[0].body | ConvertFrom-Json
    Assert-True ($issueBody.title -like 'Marketing dates: Storm Keep, *' -and $issueBody.body.Contains('Nothing shipped since mkt/1') -and $issueBody.body.Contains('Opt in to Steam Soon Fest') -and $issueBody.body.Contains('- [ ] Reply to the press (from #5)')) "the dates-only brief has its own title, the dates and the carried tasks: $($issueBody.title)"
    Assert-True (-not $issueBody.body.Contains('## Drafts') -and -not $issueBody.body.Contains('## Shipped') -and -not ($issueBody.body -match '(?m)^- \[ \] Post on Discord$') -and $issueBody.body.Contains('- [ ] Post on Discord (from #5)') -and $issueBody.body.Contains('## Waiting for a green build')) 'and no drafts, no shipped list and no new posts (an open one carries over), but the changes still waiting'

    # The same week with the calendar off: nothing to act on, nothing written.
    Set-Content -LiteralPath (Join-Path $repo 'docs/promo.json') -Value '{ "calendar": false }'
    Set-Routes (Get-Content -LiteralPath $routesFile -Raw | ConvertFrom-Json -AsHashtable)
    $run = Invoke-PromoCli
    Assert-True ($run.code -eq 0 -and @($run.doc.promo.upcoming).Count -eq 0 -and -not $run.doc.promo.deadlineOnly -and $run.doc.promo.nothingShipped -and -not @(Get-Requests | Where-Object { $_.method -ne 'GET' }).Count) '"calendar": false lists no dates, and a quiet week stays quiet'

    # A Steam page that cannot be read: a warning, and the plan's deadlines and the brief still come.
    Set-Content -LiteralPath (Join-Path $repo 'docs/promo.json') -Value '{ "channels": ["discord"] }'
    Set-Content -LiteralPath (Join-Path $cache 'steam.html') -Value '<html><body>A page with another layout</body></html>' -Encoding utf8
    Set-Routes $green5
    $run = Invoke-PromoCli @('-DryRun')
    $p = $run.doc.promo
    Assert-True ($run.code -eq 0 -and $p.green -and @($run.doc.warnings | Where-Object { $_ -match "^Coming up: Steam's event page could not be read" }).Count -eq 1 -and @($p.upcoming | Where-Object { $_.what -like "Pay Steam's app fee*" }).Count -eq 1 -and -not @($p.upcoming | Where-Object { $_.kind -ne 'deadline' }).Count) "an unreadable Steam page is a warning; the plan's deadlines and the brief still come: $(@($run.doc.warnings) -join ' | ')"
    Remove-Item -LiteralPath (Join-Path $repo 'plan') -Recurse
    Remove-Item -LiteralPath $cache -Recurse

    # --- Errors ---
    Set-Content -LiteralPath (Join-Path $repo 'docs/promo.json') -Value '{ "calendar": "yes" }'
    $run = Invoke-PromoCli @('-DryRun')
    Assert-True ($run.code -ne 0 -and $run.doc.error.code -eq 'promo-settings' -and $run.doc.error.message -match 'calendar is true or false') 'calendar that is not true or false is promo-settings'
    Set-Content -LiteralPath (Join-Path $repo 'docs/promo.json') -Value '{ "channels": ["tiktok"] }'
    $run = Invoke-PromoCli @('-DryRun')
    Assert-True ($run.code -ne 0 -and $run.doc.error.code -eq 'promo-settings') 'an unknown channel is promo-settings'
    Set-Content -LiteralPath (Join-Path $repo 'docs/promo.json') -Value ('{ "hashtags": ["#' + ('a' * 120) + '"] }')
    $run = Invoke-PromoCli @('-DryRun')
    Assert-True ($run.code -ne 0 -and $run.doc.error.code -eq 'promo-settings' -and $run.doc.error.message -match 'at most 100') 'hashtags too long for a Bluesky post are promo-settings'
    Remove-Item -LiteralPath (Join-Path $repo 'docs/promo.json')
    $env:GITHUB_TOKEN = $null
    $run = Invoke-PromoCli
    Assert-True ($run.code -ne 0 -and $run.doc.error.code -eq 'promo-no-token') 'a real run without a token is promo-no-token'
    $env:GITHUB_TOKEN = 'test-token'
    $env:GITHUB_REPOSITORY = $null
    $run = Invoke-PromoCli @('-DryRun')
    Assert-True ($run.code -ne 0 -and $run.doc.error.code -eq 'promo-no-repository') 'no GITHUB_REPOSITORY and no github.com origin is promo-no-repository'
    $env:GITHUB_REPOSITORY = 'o/r'
    $loose = Join-Path $work 'not-a-repository'
    Copy-Item -LiteralPath (Join-Path $root 'examples/gdscript') -Destination $loose -Recurse
    $out = & pwsh -NoProfile -NonInteractive -File $ci promo -DryRun -Json -Project $loose 2>$null | Out-String
    Assert-True (($out | ConvertFrom-Json).error.code -eq 'promo-no-git') 'a project outside git is promo-no-git'
    Remove-Item -LiteralPath (Join-Path $repo '.github/workflows/hyperdot.yml')
    $run = Invoke-PromoCli @('-DryRun')
    Assert-True ($run.code -ne 0 -and $run.doc.error.code -eq 'promo-no-workflow') 'no workflow calling the kit is promo-no-workflow'
    $named = "jobs:`n  ci:`n    name: Checks`n    permissions:`n      contents: read`n    uses: nick-vas/hyperdot/.github/workflows/godot.yml@v1`n"
    Set-Content -LiteralPath (Join-Path $repo '.github/workflows/ci.yml') -Value $named
    Assert-True ((Get-PromoCheckName $repo).name -eq 'Checks / Test') 'a job with a name: gives "<name> / Test"'
    Set-Content -LiteralPath (Join-Path $repo '.github/workflows/ci.yml') -Value "jobs:  # the kit`n  lint:`n    runs-on: ubuntu-latest`n# between jobs`n  godot:`n    uses: nick-vas/hyperdot/.github/workflows/godot.yml@v1  # pinned`n    name: 'Game tests'  # shown in checks`n"
    Assert-True ((Get-PromoCheckName $repo).name -eq 'Game tests / Test') "name: after uses:, comments and an earlier job are read right: $((Get-PromoCheckName $repo).name)"
    Set-Content -LiteralPath (Join-Path $repo '.github/workflows/deploy.yml') -Value "on:`n  release:`njobs:`n  ship:`n    uses: nick-vas/hyperdot/.github/workflows/godot.yml@v1`n"
    Set-Content -LiteralPath (Join-Path $repo '.github/workflows/hyperdot.yml') -Value "on: [push]`njobs:`n  godot:`n    uses: nick-vas/hyperdot/.github/workflows/godot.yml@v1`n"
    Assert-True ((Get-PromoCheckName $repo).name -eq 'godot / Test') 'with several workflows calling the kit, hyperdot.yml is the gate'
    Remove-Item -LiteralPath (Join-Path $repo '.github/workflows/hyperdot.yml')
    Set-Content -LiteralPath (Join-Path $repo '.github/workflows/zz.yml') -Value "on:`n  push:`njobs:`n  checks:`n    uses: nick-vas/hyperdot/.github/workflows/godot.yml@v1`n"
    Assert-True ((Get-PromoCheckName $repo).name -eq 'checks / Test') 'without hyperdot.yml, a workflow that runs on push comes before one that does not'
    Remove-Item -LiteralPath (Join-Path $repo '.github/workflows/deploy.yml'), (Join-Path $repo '.github/workflows/zz.yml')
    $out = & pwsh -NoProfile -NonInteractive -File $ci test -DryRun -Json -Project $repo 2>$null | Out-String
    Assert-True (($out | ConvertFrom-Json).error.code -eq 'invalid-arguments') '-DryRun on another command is invalid-arguments'
    $out = & pwsh -NoProfile -NonInteractive -File $ci doctor -Promo -Json -Project $repo 2>$null | Out-String
    Assert-True (($out | ConvertFrom-Json).error.code -eq 'invalid-arguments') '-Promo on another command is invalid-arguments'

    # --- init -Promo: adds the caller and the settings, never overwrites, safe to run again ---
    Remove-Item -LiteralPath (Join-Path $repo '.github/workflows/ci.yml')
    $out = & pwsh -NoProfile -NonInteractive -File $ci init -Promo -Json -Project $repo 2>$null | Out-String
    $doc = $out | ConvertFrom-Json -Depth 10
    $caller = Join-Path $repo '.github/workflows/hyperdot-promo.yml'
    $callerText = Get-Content -LiteralPath $caller -Raw
    Assert-True ($doc.ok -and $callerText -match 'nick-vas/hyperdot/\.github/workflows/promo\.yml@v1' -and $callerText -match 'models: read' -and $callerText -match 'checks: read' -and $callerText -match 'pull-requests: read' -and $callerText -match 'issues: write' -and $callerText -match 'contents: write') 'init -Promo writes the caller, pinned @v1, granting the five permissions'
    Assert-True ($callerText -match 'group: hyperdot-promo' -and $callerText -match 'cancel-in-progress: false' -and $callerText.Contains("if: github.event_name == 'schedule' || inputs.dry-run || github.ref_name == github.event.repository.default_branch")) 'runs never overlap, and a real run by hand only runs from the default branch'
    $settings = Get-Content -LiteralPath (Join-Path $repo 'docs/promo.json') -Raw | ConvertFrom-Json
    Assert-True ($settings.ai -eq $false -and $settings.calendar -eq $true -and @($settings.channels).Count -eq 3) 'init -Promo writes docs/promo.json with AI off and the calendar on'
    Assert-True (Test-Path -LiteralPath (Join-Path $repo '.github/workflows/hyperdot.yml')) 'init still writes the CI workflow the gate reads'
    Set-Content -LiteralPath (Join-Path $repo 'docs/promo.json') -Value '{ "ai": true }'
    $out = & pwsh -NoProfile -NonInteractive -File $ci init -Promo -Json -Project $repo 2>$null | Out-String
    $doc = $out | ConvertFrom-Json -Depth 10
    Assert-True ($doc.ok -and (Get-Content -LiteralPath (Join-Path $repo 'docs/promo.json') -Raw).Trim() -eq '{ "ai": true }' -and (Get-Content -LiteralPath $caller -Raw) -eq $callerText -and @($doc.steps | Where-Object { $_.status -eq 'skipped' -and $_.message -match 'promo' }).Count -eq 2) 'a second init -Promo skips both and overwrites nothing'
} finally {
    try { $null = Invoke-WebRequest -Uri "$api/__stop" -SkipHttpErrorCheck -TimeoutSec 2 } catch { $null = $_ }
    if (-not $server.WaitForExit(3000)) { $server.Kill() }
    foreach ($name in $saved.Keys) { [Environment]::SetEnvironmentVariable($name, $saved[$name]) }
    Remove-Item -LiteralPath $work -Recurse -Force -ErrorAction SilentlyContinue
}

if ($failures.Count) { Write-Host "`n$($failures.Count) failed"; exit 1 }
Write-Host "`npromo self-test passed"
exit 0
