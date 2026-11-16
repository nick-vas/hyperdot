#!/usr/bin/env pwsh
# Self-test of `brief`, the structured start of a new game: the description in tests/brief-fixture/idea.txt, answers
# taken from it only with a word-for-word quote, the questions that open and close with earlier answers (when), the
# refusals (an answer outside the options, a genre outside genres-uw.json, a quote that is not in the text, a question
# that does not apply), the rules across answers, and the draft GDD and STYLE.md, which pass doctor's feature grammar.
# Runs in temporary folders with no Godot project, as a new game starts; no Godot is needed.
Set-StrictMode -Version 3.0
$ErrorActionPreference = 'Stop'
$root = Split-Path $PSScriptRoot
$ci = Join-Path $root 'ci/godot/hyperdot.ps1'
$idea = Join-Path $PSScriptRoot 'brief-fixture/idea.txt'
$failures = @()
function Assert-True([bool]$Condition, [string]$Name) {
    if ($Condition) { Write-Host "ok     $Name" } else { Write-Host "FAIL   $Name"; $script:failures += $Name }
}
function Invoke-Brief([string]$Dir, [string[]]$KitArgs) {
    $out = & pwsh -NoProfile -NonInteractive -File $ci brief @KitArgs -Json -Project $Dir 2>$null | Out-String
    return [pscustomobject]@{ Code = $LASTEXITCODE; Doc = ($out.Trim() ? ($out | ConvertFrom-Json -Depth 20) : $null) }
}
function New-Folder { $d = Join-Path ([System.IO.Path]::GetTempPath()) "brief-$([guid]::NewGuid().ToString('n').Substring(0, 8))"; New-Item -ItemType Directory $d | Out-Null; return $d }
function Get-NextIds($Doc) { return @($Doc.brief.next | ForEach-Object { $_.id }) }

# The bank itself: every question has an id, a kind and at most four options, as a question dialog takes.
$bank = Get-Content -LiteralPath (Join-Path $root 'ci/godot/templates/brief-questions.json') -Raw | ConvertFrom-Json -Depth 10
$ids = @($bank.questions | ForEach-Object { $_.id })
Assert-True (@($ids | Select-Object -Unique).Count -eq $ids.Count) "every question has its own id ($($ids.Count) questions)"
Assert-True (@($bank.questions | Where-Object { $_.kind -notin 'text', 'choice', 'multi', 'term' }).Count -eq 0) 'every question has a known kind'
Assert-True (@($bank.questions | Where-Object { $_.PSObject.Properties['options'] -and @($_.options).Count -gt 4 }).Count -eq 0) 'no question has more than four options'
Assert-True (@($bank.questions | Where-Object { $_.kind -in 'choice', 'multi' -and -not $_.PSObject.Properties['options'] }).Count -eq 0) 'every choice question has options'
$whenIds = @($bank.questions | Where-Object { $_.PSObject.Properties['when'] } | ForEach-Object { $_.when.PSObject.Properties.Name })
Assert-True (@($whenIds | Where-Object { $_ -notin $ids }).Count -eq 0) 'every condition names a question'

$dir = New-Folder
try {
    $r = Invoke-Brief $dir @()
    Assert-True ($r.Code -ne 0 -and $r.Doc.error.code -eq 'brief-missing') "with no brief, brief says how to start: $($r.Doc.error.message)"
    $r = Invoke-Brief $dir @('-Do', 'start', '-TextFile', $idea)
    Assert-True ($r.Code -eq 0 -and $r.Doc.ok -and (Test-Path -LiteralPath (Join-Path $dir 'docs/brief.json')) -and -not (Test-Path -LiteralPath (Join-Path $dir 'project.godot'))) 'brief -Do start works in a folder with no Godot project'
    Assert-True ((Get-NextIds $r.Doc) -join ',' -eq 'title,genre,dimension,platforms') "the next questions come in the bank's order, four at a time: $((Get-NextIds $r.Doc) -join ',')"
    Assert-True (@($r.Doc.brief.next | Where-Object { $_.id -eq 'genre' })[0].multiSelect -and @(@($r.Doc.brief.next)[2].options).Count -eq 3) 'each next question carries its options and whether several may be picked'
    $again = Invoke-Brief $dir @('-Do', 'start', '-TextFile', $idea)
    Assert-True ($again.Doc.error.code -eq 'brief-exists') 'a second start is refused'

    # Answers from the description: a whole sentence (or several in a row), word for word, that names the answer.
    $first = 'Lantern Keeper is a cosy 2D puzzle game.'
    $third = 'It is single player, played with a gamepad or keyboard, on desktop and Steam Deck.'
    foreach ($case in @(@('title', 'Lantern Keeper', $first), @('genre', 'puzzle', $first), @('dimension', '2D', 'lantern keeper is a cosy  2D puzzle game'),
            @('players', 'Single player', $third))) {
        $r = Invoke-Brief $dir @('-Do', 'answer', '-Id', $case[0], '-Value', $case[1], '-Quote', $case[2])
        Assert-True ($r.Doc.ok) "$($case[0]) is taken from the description with a quote$(if (-not $r.Doc.ok) { ": $($r.Doc.error.message)" })"
    }
    $genre = @($r.Doc.brief.answers | Where-Object { $_.id -eq 'genre' })[0]
    Assert-True ((@($genre.value) -join ',') -eq 'Puzzle' -and $genre.source -eq 'text') 'an answer is stored in the option''s own spelling, with its source'
    Assert-True ('camera2d' -in (Get-NextIds $r.Doc) -and 'camera3d' -notin (Get-NextIds $r.Doc)) "a 2D answer opens the 2D camera question, not the 3D one: $((Get-NextIds $r.Doc) -join ',')"

    # Refusals.
    foreach ($case in @(
            @(@('-Do', 'answer', '-Id', 'input', '-Value', 'Gamepad', '-Quote', 'played with a controller'), 'invalid-answer', 'not a whole sentence of the description', 'a quote that is not in the text'),
            @(@('-Do', 'answer', '-Id', 'saves', '-Value', 'Nothing', '-Quote', 'art'), 'invalid-answer', 'not a whole sentence', 'a few letters that happen to be in the text'),
            @(@('-Do', 'answer', '-Id', 'platforms', '-Value', 'Mobile', '-Quote', $third), 'invalid-answer', "does not name 'Mobile'", 'a real sentence that does not name the answer'),
            @(@('-Do', 'answer', '-Id', 'input', '-Value', 'Touch', '-Quote', $third), 'invalid-answer', "does not name 'Touch'", 'an option the sentence does not state'),
            @(@('-Do', 'answer', '-Id', 'artStyle', '-Value', 'Pixel art'), 'invalid-answer', 'is not among the questions to ask now', 'an asked answer out of order'),
            @(@('-Do', 'answer', '-Id', 'platforms', '-Value', ','), 'invalid-answer', 'names at least one of', 'an empty list'),
            @(@('-Do', 'answer', '-Id', 'genre', '-Value', ' , '), 'invalid-answer', 'names at least one genre', 'an empty genre list'),
            @(@('-Do', 'answer', '-Id', 'dimension', '-Value', '4D'), 'invalid-answer', 'it is one of: 2D, 3D, 2.5D', 'an answer outside the options'),
            @(@('-Do', 'answer', '-Id', 'genre', '-Value', 'Puzzel'), 'invalid-answer', 'did you mean Puzzle?', 'a genre outside the vocabulary, with the nearest'),
            @(@('-Do', 'answer', '-Id', 'camera3d', '-Value', 'First person'), 'invalid-answer', 'does not apply', 'a question that does not apply'),
            @(@('-Do', 'answer', '-Id', 'colour', '-Value', 'red'), 'invalid-arguments', 'not a brief question', 'an unknown question'),
            @(@('-Do', 'gdd'), 'brief-incomplete', 'question(s) open', 'a GDD before the brief is complete'),
            @(@('-Do', 'sync'), 'invalid-arguments', 'is not one of: status, start, answer, gdd', "plan's actions"))) {
        $r = Invoke-Brief $dir $case[0]
        Assert-True ($r.Code -ne 0 -and $r.Doc.error.code -eq $case[1] -and $r.Doc.error.message.Contains($case[2])) "$($case[3]) is refused with $($case[1]): $($r.Doc.error.message)"
    }
    $neg = New-Folder
    try {
        Set-Content -LiteralPath (Join-Path $neg 'idea.txt') 'Glowfarm is a cosy farming game. It is not online.'
        $null = Invoke-Brief $neg @('-Do', 'start', '-TextFile', (Join-Path $neg 'idea.txt'))
        $r = Invoke-Brief $neg @('-Do', 'answer', '-Id', 'players', '-Value', 'Online multiplayer', '-Quote', 'It is not online.')
        Assert-True ($r.Doc.error.code -eq 'invalid-answer' -and $r.Doc.error.message -match 'negation') "a sentence with a negation is not evidence: $($r.Doc.error.message)"
    } finally { Remove-Item -LiteralPath $neg -Recurse -Force -ErrorAction SilentlyContinue }
    $out = & pwsh -NoProfile -NonInteractive -File $ci plan -Do answer -Json -Project $dir 2>$null | Out-String
    Assert-True (($out | ConvertFrom-Json).error.code -eq 'invalid-arguments') "plan refuses brief's actions"

    # A rule across answers: C# cannot export to the Web.
    $null = Invoke-Brief $dir @('-Do', 'answer', '-Id', 'platforms', '-Value', 'Desktop, Web')
    $r = Invoke-Brief $dir @('-Do', 'answer', '-Id', 'language', '-Value', 'C#')
    Assert-True (@($r.Doc.brief.conflicts | Where-Object { $_.rule -eq 'csharp-web' }).Count -eq 1 -and -not $r.Doc.brief.complete) "C# with Web is a conflict with its fix: $(@($r.Doc.brief.conflicts | ForEach-Object fix) -join ' | ')"
    $r = Invoke-Brief $dir @('-Do', 'answer', '-Id', 'platforms', '-Value', 'Desktop, Steam Deck', '-Quote', $third)
    $r = Invoke-Brief $dir @('-Do', 'answer', '-Id', 'input', '-Value', 'Gamepad, Keyboard and mouse', '-Quote', $third)
    Assert-True ($r.Doc.ok -and @($r.Doc.brief.answers | Where-Object { $_.id -eq 'input' })[0].source -eq 'text') "one sentence may answer several questions when it names each answer (keyboard is a cue for Keyboard and mouse)$(if (-not $r.Doc.ok) { ": $($r.Doc.error.message)" })"
    foreach ($case in @(@('coreLoop', "slide`n## Pitch"), @('coreLoop', '# heading'), @('pillars', 'calm over speed'), @('pillars', ', ,'))) {
        $null = Invoke-Brief $dir @('-Do', 'answer', '-Id', 'language', '-Value', 'GDScript')
        $null = Invoke-Brief $dir @('-Do', 'answer', '-Id', 'camera2d', '-Value', 'Top-down')
        $r = Invoke-Brief $dir @('-Do', 'answer', '-Id', $case[0], '-Value', $case[1], '-Quote', $first)
        $r2 = Invoke-Brief $dir @('-Do', 'answer', '-Id', $case[0], '-Value', $case[1])
        Assert-True ($r2.Doc.error.code -eq 'invalid-answer') "$($case[0]) '$($case[1] -replace "`n", '\n')' is refused: $($r2.Doc.error.message)"
    }

    # The rest, as a user would answer the questions, in the order brief lists them.
    $rest = [ordered]@{ coreLoop = 'slide the lantern to light every wick before the oil runs out'
        session = '5 to 20 minutes'; funA = 'none'; funB = 'none' }
    foreach ($key in $rest.Keys) { $null = Invoke-Brief $dir @('-Do', 'answer', '-Id', $key, '-Value', $rest[$key]) }
    $r = Invoke-Brief $dir @()
    Assert-True (@($r.Doc.brief.conflicts | Where-Object { $_.rule -eq 'fun-at-least-one' }).Count -eq 1) 'no kind of fun in either question is a conflict'
    $rest = [ordered]@{ funA = 'challenge'; pillars = 'calm over speed, every level fits one screen'; failure = 'Retry at once'
        saves = 'Progress, automatically'; scope = 'Game jam'; jamLength = '3 days'; comparables = 'none'; outOfScope = 'online play'
        artStyle = 'Pixel art'; resolution = '320x180'; palette = 'Muted or dark'; audio = 'Chiptune' }
    $bad = @(foreach ($key in $rest.Keys) { $r = Invoke-Brief $dir @('-Do', 'answer', '-Id', $key, '-Value', $rest[$key]); if (-not $r.Doc.ok) { "$key ($($r.Doc.error.message))" } })
    Assert-True ($bad.Count -eq 0) "every remaining answer is accepted: $($bad -join '; ')"
    $r = Invoke-Brief $dir @()
    Assert-True ($r.Doc.brief.complete -and $r.Doc.brief.open -eq 0 -and @($r.Doc.brief.next).Count -eq 0) "the brief is complete ($($r.Doc.brief.answeredCount) answers)"
    Assert-True ('weeklyHours' -notin @($r.Doc.brief.answers | ForEach-Object id)) 'a jam is not asked for hours a week'

    $r = Invoke-Brief $dir @('-Do', 'gdd')
    $gddPath = Join-Path $dir 'docs/GDD.md'
    Assert-True ($r.Doc.ok -and (Test-Path -LiteralPath $gddPath) -and (Test-Path -LiteralPath (Join-Path $dir 'docs/STYLE.md')) -and $r.Doc.planProfile -eq 'jam' -and $null -eq $r.Doc.weeklyHours -and $r.Doc.jamLength -eq '3 days' -and @($r.Doc.nextSteps | Where-Object { $_ -match 'scale .*timeboxDays.* to 3 days' }).Count -eq 1) "the draft GDD and STYLE.md are written; jam profile, no weekly hours, the jam's length in the next steps: $(@($r.Doc.nextSteps) -join ' | ')"
    foreach ($lib in 'Common', 'Status') { . (Join-Path $root "ci/godot/lib/$lib.ps1") }
    $gdd = Read-Gdd $gddPath
    $problems = @(Get-GddProblems $gdd)
    Assert-True ($problems.Count -eq 0 -and $gdd.draft) "the GDD is a draft that follows the feature grammar: $(@($problems | ForEach-Object problem) -join ' | ')"
    $f1 = @($gdd.features | Where-Object { $_.id -eq 'F1' })[0]
    Assert-True ($f1.priority -eq 'must' -and ($f1.fun -join ',') -eq 'challenge' -and @($gdd.features | Where-Object { $_.title -eq 'Saves' -and $_.priority -eq 'could' }).Count -eq 1) 'the core loop is a must with the chosen fun; saves are a could with none'
    $text = Get-Content -LiteralPath $gddPath -Raw
    Assert-True ($text -match '(?m)^# Lantern Keeper: game design document' -and $text -match 'Genre: Puzzle' -and $text -match '1\. Calm over speed\.' -and $text -match 'View: 2D, top-down; designed at 320x180') 'the title, genre, pillars and screens come from the answers'
    $style = Get-Content -LiteralPath (Join-Path $dir 'docs/STYLE.md') -Raw
    Assert-True ($style -match '(?m)^Resolutions: 320x180, 1920x1080, 1280x720$' -and $style -match 'Art style: Pixel art\.') 'STYLE.md gets the design resolution first and the art direction'
    $r = Invoke-Brief $dir @('-Do', 'gdd')
    Assert-True ($r.Doc.error.code -eq 'gdd-exists') 'an existing GDD is never overwritten'
} finally { Remove-Item -LiteralPath $dir -Recurse -Force -ErrorAction SilentlyContinue }

# Answers change which questions apply: switching to 3D drops the 2D camera answer from the brief.
$dir = New-Folder
try {
    $null = Invoke-Brief $dir @('-Do', 'start', '-TextFile', $idea)
    $null = Invoke-Brief $dir @('-Do', 'answer', '-Id', 'dimension', '-Value', '2D')
    $null = Invoke-Brief $dir @('-Do', 'answer', '-Id', 'camera2d', '-Value', 'Side view')
    $r = Invoke-Brief $dir @('-Do', 'answer', '-Id', 'dimension', '-Value', '3D')
    Assert-True ('camera2d' -in @($r.Doc.brief.stale) -and 'camera2d' -notin @($r.Doc.brief.answers | ForEach-Object id)) 'an answer whose question no longer applies is listed as stale and left out'
    $r = Invoke-Brief $dir @('-Do', 'answer', '-Id', 'camera3d', '-Value', 'First person')
    Assert-True ($r.Doc.ok -and 'camera3d' -in @($r.Doc.brief.answers | ForEach-Object id) -and 'camera2d' -notin @($r.Doc.brief.answers | ForEach-Object id)) 'the 3D camera is then asked, and only it counts'
} finally { Remove-Item -LiteralPath $dir -Recurse -Force -ErrorAction SilentlyContinue }

if ($failures.Count) { Write-Host "`n$($failures.Count) failed"; exit 1 }
Write-Host "`nbrief self-test passed"
exit 0
