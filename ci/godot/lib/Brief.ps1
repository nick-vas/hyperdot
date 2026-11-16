# `brief`: the structured start of a new game. The user describes the game in their own words; the kit then asks the
# questions that description leaves open, from a fixed bank (templates/brief-questions.json), in a fixed order, and writes
# a draft GDD (and STYLE.md) from the answers. The agent decides nothing: an answer is taken from the description only
# with the sentence that states it, quoted word for word, and every other answer comes from asking the question as written.
# State is docs/brief.json in the game's folder. Like help, it needs no Godot project yet.

$script:BriefSchema = 'hyperdot-brief/1'
$script:BriefMaxNext = 4

function Get-BriefQuestions {
    $path = Join-Path $PSScriptRoot '../templates/brief-questions.json'
    return Get-Content -LiteralPath $path -Raw | ConvertFrom-Json -Depth 10
}

function Get-BriefGenreTerms {
    $path = Join-Path $PSScriptRoot '../templates/genres-uw.json'
    return @((Get-Content -LiteralPath $path -Raw | ConvertFrom-Json -Depth 10).terms | Where-Object { $_.facet -eq 'gameplay' } | ForEach-Object { [string]$_.term })
}

function Get-BriefPath([string]$Dir) { return Join-Path $Dir 'docs/brief.json' }

function Read-Brief([string]$Dir) {
    $path = Get-BriefPath $Dir
    if (-not (Test-Path -LiteralPath $path)) { Stop-GodotCi "No brief at $path. Write the game's description to a file, then run: $(Format-KitCommand 'brief -Do start -TextFile <file>')" 'brief-missing' }
    try { $brief = Get-Content -LiteralPath $path -Raw | ConvertFrom-Json -Depth 10 -AsHashtable }
    catch { Stop-GodotCi "$path is not valid JSON: $($_.Exception.Message)" 'brief-missing' }
    if (-not ($brief -is [System.Collections.IDictionary]) -or "$($brief['schema'])" -ne $script:BriefSchema -or -not $brief.Contains('text')) {
        Stop-GodotCi "$path is not a brief ($script:BriefSchema with text and answers); delete it and run brief -Do start again" 'brief-missing'
    }
    if (-not $brief.Contains('answers') -or $brief['answers'] -isnot [System.Collections.IDictionary]) { $brief['answers'] = [ordered]@{} }
    return $brief
}

function Save-Brief([string]$Dir, $Brief) {
    $path = Get-BriefPath $Dir
    New-Item -ItemType Directory -Force (Split-Path $path) | Out-Null
    $sorted = [ordered]@{ schema = $script:BriefSchema; startedAt = $Brief['startedAt']; text = $Brief['text']; answers = [ordered]@{} }
    foreach ($q in (Get-BriefQuestions).questions) { if ($Brief['answers'].Contains($q.id)) { $sorted.answers[$q.id] = $Brief['answers'][$q.id] } }
    [System.IO.File]::WriteAllText([System.IO.Path]::GetFullPath($path), ($sorted | ConvertTo-Json -Depth 10) + "`n", [System.Text.UTF8Encoding]::new($false))
}

# Text compared for quotes: case, curly quotes and runs of white space do not count.
function ConvertTo-BriefComparable([string]$Text) {
    return (($Text -replace '[‘’]', "'" -replace '[“”]', '"' -replace '\s+', ' ').Trim().ToLowerInvariant())
}

function Test-BriefQuote([string]$Text, [string]$Quote) {
    $q = ConvertTo-BriefComparable $Quote
    return ($q.Length -ge 3 -and (ConvertTo-BriefComparable $Text).Contains($q))
}

# Whether a question applies, from its "when": every listed answer must hold one of the listed values.
function Test-BriefApplies($Question, $Answers) {
    $when = $Question.PSObject.Properties['when'] ? $Question.when : $null
    if ($null -eq $when) { return $true }
    foreach ($property in $when.PSObject.Properties) {
        if (-not $Answers.Contains($property.Name)) { return $false }
        $have = @($Answers[$property.Name]['value'])
        if (@($have | Where-Object { $_ -in @($property.Value) }).Count -eq 0) { return $false }
    }
    return $true
}

# The answer in its stored form (always a list of strings) or a refusal message; nothing outside the question's options.
function ConvertTo-BriefValue($Question, [string]$Value) {
    $raw = $Value.Trim()
    if (-not $raw) { return [ordered]@{ ok = $false; message = "An answer to '$($Question.id)' cannot be empty" } }
    $labels = @($Question.PSObject.Properties['options'] ? @($Question.options | ForEach-Object { [string]$_.label }) : @())
    $match = { param([string]$Item) @($labels | Where-Object { $_ -ieq $Item.Trim() } | Select-Object -First 1) }
    switch ($Question.kind) {
        'text' {
            if ($raw.Length -gt 500) { return [ordered]@{ ok = $false; message = "The answer to '$($Question.id)' is $($raw.Length) characters; keep it under 500" } }
            return [ordered]@{ ok = $true; value = @($raw) }
        }
        'choice' {
            $found = @(& $match $raw)
            if ($found.Count -eq 0) { return [ordered]@{ ok = $false; message = "'$raw' is not an answer to '$($Question.id)'; it is one of: $($labels -join ', ')" } }
            return [ordered]@{ ok = $true; value = @($found[0]) }
        }
        'multi' {
            if ($raw -ieq 'none' -and $Question.PSObject.Properties['optional'] -and $Question.optional) { return [ordered]@{ ok = $true; value = @() } }
            $items = @($raw -split ',' | ForEach-Object { $_.Trim() } | Where-Object { $_ })
            $values = [System.Collections.Generic.List[string]]::new()
            foreach ($item in $items) {
                $found = @(& $match $item)
                if ($found.Count -eq 0) {
                    $none = ($Question.PSObject.Properties['optional'] -and $Question.optional) ? ' (or "none")' : ''
                    return [ordered]@{ ok = $false; message = "'$item' is not an answer to '$($Question.id)'; pick from: $($labels -join ', ')$none, comma-separated" }
                }
                if (-not $values.Contains($found[0])) { $values.Add($found[0]) }
            }
            return [ordered]@{ ok = $true; value = @($values) }
        }
        'term' {
            $terms = Get-BriefGenreTerms
            $items = @($raw -split ',' | ForEach-Object { $_.Trim() } | Where-Object { $_ })
            $max = $Question.PSObject.Properties['max'] ? [int]$Question.max : 3
            if ($items.Count -gt $max) { return [ordered]@{ ok = $false; message = "'$($Question.id)' takes at most $max terms, not $($items.Count)" } }
            $values = [System.Collections.Generic.List[string]]::new()
            foreach ($item in $items) {
                $found = @($terms | Where-Object { $_ -ieq $item } | Select-Object -First 1)
                if ($found.Count -eq 0) {
                    $close = Get-ClosestName $item.ToLowerInvariant() @($terms | ForEach-Object { $_.ToLowerInvariant() })
                    $hint = $close ? " (did you mean $(@($terms | Where-Object { $_.ToLowerInvariant() -eq $close })[0])?)" : ''
                    return [ordered]@{ ok = $false; message = "'$item' is not a gameplay genre in the kit's list (genres-uw.json)$hint" }
                }
                if (-not $values.Contains($found[0])) { $values.Add($found[0]) }
            }
            return [ordered]@{ ok = $true; value = @($values) }
        }
    }
    return [ordered]@{ ok = $false; message = "Question '$($Question.id)' has an unknown kind '$($Question.kind)'" }
}

function Get-BriefAnswerValues($Answers, [string]$Id) { return @($Answers.Contains($Id) ? @($Answers[$Id]['value']) : @()) }

# The rules across answers (templates/brief-questions.json "rules"), each broken one with the fix to make.
function Get-BriefConflicts($Answers) {
    $conflicts = [System.Collections.Generic.List[object]]::new()
    if ($Answers.Contains('funA') -and $Answers.Contains('funB') -and @(Get-BriefAnswerValues $Answers 'funA').Count + @(Get-BriefAnswerValues $Answers 'funB').Count -eq 0) {
        $conflicts.Add([ordered]@{ rule = 'fun-at-least-one'; message = 'No kind of fun was chosen in either question'; fix = 'Answer funA or funB again with at least one kind' })
    }
    if ('C#' -in (Get-BriefAnswerValues $Answers 'language') -and 'Web' -in (Get-BriefAnswerValues $Answers 'platforms')) {
        $conflicts.Add([ordered]@{ rule = 'csharp-web'; message = 'C# with the Web platform: Godot 4.7 cannot export C# to the Web'; fix = 'Answer language with GDScript, or platforms without Web' })
    }
    $platforms = @(Get-BriefAnswerValues $Answers 'platforms')
    if ('Touch' -in (Get-BriefAnswerValues $Answers 'input') -and $platforms.Count -and 'Mobile' -notin $platforms -and 'Web' -notin $platforms) {
        $conflicts.Add([ordered]@{ rule = 'touch-needs-mobile'; message = 'Touch controls with no Mobile or Web platform to touch'; fix = 'Answer input without Touch, or platforms with Mobile or Web' })
    }
    return @($conflicts)
}

# Where the brief stands: the questions that apply, answered or not, the next ones to ask (in the bank's order, at most
# four), answers whose question no longer applies, and broken rules.
function Get-BriefState($Brief) {
    $bank = Get-BriefQuestions
    $answers = $Brief['answers']
    $applicable = @($bank.questions | Where-Object { Test-BriefApplies $_ $answers })
    $open = @($applicable | Where-Object { -not $answers.Contains($_.id) })
    $next = @($open | Select-Object -First $script:BriefMaxNext | ForEach-Object {
            $q = $_
            [ordered]@{ id = $q.id; header = $q.header; question = $q.question; kind = $q.kind
                multiSelect = ($q.kind -in 'multi', 'term'); optional = [bool]($q.PSObject.Properties['optional'] -and $q.optional)
                options = @(if ($q.PSObject.Properties['options']) { $q.options | ForEach-Object { [ordered]@{ label = $_.label; description = $_.description } } })
                max = ($q.PSObject.Properties['max'] ? [int]$q.max : $null) }
        })
    $stale = @($answers.Keys | Where-Object { $id = $_; @($applicable | Where-Object { $_.id -eq $id }).Count -eq 0 })
    $conflicts = @(Get-BriefConflicts $answers)
    $listed = @(foreach ($q in $applicable) {
            if (-not $answers.Contains($q.id)) { continue }
            $a = $answers[$q.id]
            [ordered]@{ id = $q.id; header = $q.header; value = @($a['value']); source = $a['source']; quote = $a['quote'] }
        })
    return [ordered]@{ applicable = $applicable.Count; answeredCount = $applicable.Count - $open.Count; open = $open.Count
        complete = ($open.Count -eq 0 -and $conflicts.Count -eq 0); answers = $listed; next = $next; stale = $stale; conflicts = $conflicts }
}

# One section of a Markdown document ("## Name" to the next "## "), replaced by $Body.
function Set-BriefSection([string]$Document, [string]$Name, [string]$Body) {
    $pattern = "(?ms)^## $([regex]::Escape($Name))[^\r\n]*\r?\n.*?(?=^## |\z)"
    if ($Document -notmatch $pattern) { return $Document }
    return [regex]::Replace($Document, $pattern, { param($m) "## $Name`n`n$($Body.TrimEnd())`n`n" }, 'Multiline, Singleline')
}

function ConvertTo-BriefSentence([string]$Text) {
    $t = $Text.Trim()
    if (-not $t) { return '' }
    return ($t.Substring(0, 1).ToUpperInvariant() + $t.Substring(1)).TrimEnd('.') + '.'
}

# docs/GDD.md (draft) and, when there is none, docs/STYLE.md, from a complete brief. The GDD follows the feature grammar
# doctor checks (Get-GddProblems): it is checked before it is written.
function New-BriefGdd($Brief, [string]$Dir) {
    $a = $Brief['answers']
    $one = { param([string]$Id) $v = @(Get-BriefAnswerValues $a $Id); $v.Count ? [string]$v[0] : '' }
    $all = { param([string]$Id) @(Get-BriefAnswerValues $a $Id) }
    $title = & $one 'title'
    $template = Get-Content -LiteralPath (Join-Path $PSScriptRoot '../templates/GDD.md') -Raw
    $doc = $template.Replace('{{GAME}}', $title) -replace "`r`n", "`n"
    $genres = & $all 'genre'
    $fun = @(@(& $all 'funA') + @(& $all 'funB'))
    $comparables = & $one 'comparables'
    $doc = Set-BriefSection $doc 'Pitch' (@(
            "$title is a $(($genres -join ', ').ToLowerInvariant()) game. $(ConvertTo-BriefSentence (& $one 'coreLoop'))"
            ''
            "Genre: $($genres -join ', ')"
            ''
            "Comparable games: $comparables"
            ''
            'Core fantasy: who the player gets to be, in a few words (not asked yet).'
            ''
            "<!-- Written by hyperdot brief from docs/brief.json; confirm each section with /game. -->") -join "`n")
    $pillars = @((& $one 'pillars') -split ',' | ForEach-Object { $_.Trim() } | Where-Object { $_ })
    $doc = Set-BriefSection $doc 'Pillars' ((@(for ($i = 0; $i -lt $pillars.Count; $i++) { "$($i + 1). $(ConvertTo-BriefSentence $pillars[$i])" }) + @('', "The kinds of fun this game is mostly about, in order: $($fun -join ', ').")) -join "`n")
    $failure = & $one 'failure'
    $failureText = @{ 'Nothing to fail' = 'there is no losing state'; 'Retry at once' = 'the player is back a few seconds later and loses nothing'
        'Back to a checkpoint' = 'the player loses the progress since the last checkpoint'; 'The run ends' = 'the run ends and the player starts over' }[$failure]
    $doc = Set-BriefSection $doc 'Core loop' (@(
            "- Moment (seconds): $(ConvertTo-BriefSentence (& $one 'coreLoop'))"
            "- Session (one sitting): $((& $one 'session').ToLowerInvariant()); what a session sets out to do, and how it ends (not asked yet)."
            '- Playthrough (the whole game or one run): what changes from start to end, and what brings them back (not asked yet).'
            ''
            "What failing costs: $failureText.") -join "`n")
    $features = [System.Collections.Generic.List[string]]::new()
    $add = { param([string]$Name, [string]$Priority, [string]$Fun, [string]$Done)
        $script:briefFeatureNumber++
        $features.Add("### F$($script:briefFeatureNumber) $Name`nPriority: $Priority`nFun: $Fun`nDone when:`n- $Done`n") }
    $script:briefFeatureNumber = 0
    & $add 'The core loop' 'must' ($fun -join ', ') "$(ConvertTo-BriefSentence (& $one 'coreLoop')) (Write the observable result a test, flow or screenshot checks.)"
    $players = & $one 'players'
    if ($players -in 'Local multiplayer', 'Local and online') { & $add 'Local multiplayer' 'must' 'fellowship' 'Two players play on one device at once.' }
    if ($players -in 'Online multiplayer', 'Local and online') { & $add 'Online multiplayer' 'must' 'fellowship' "Players play together over the network ($((& $one 'network').ToLowerInvariant()))." }
    $saves = & $one 'saves'
    $saveText = @{ 'Settings only' = 'The settings are saved and come back after a restart'
        'Progress, automatically' = 'Progress is saved automatically and comes back after a restart'
        'Save slots' = 'The player saves to a slot of their choice and loads it after a restart' }
    if ($saves -ne 'Nothing') { & $add 'Saves' 'could' 'none' "$($saveText[$saves]); saves from an older version still load." }
    $doc = Set-BriefSection $doc 'Features' (($features -join "`n").TrimEnd())
    $modes = @("Players: $($players.ToLowerInvariant())$(if ($a.Contains('network')) { "; online, $((& $one 'network').ToLowerInvariant())" }).")
    $doc = Set-BriefSection $doc 'Modes (optional)' ($modes -join "`n")
    $camera = @((& $one 'camera2d'), (& $one 'camera3d')) | Where-Object { $_ } | Select-Object -First 1
    $doc = Set-BriefSection $doc 'Screens' (@(
            "View: $(& $one 'dimension'), $($camera.ToLowerInvariant()); designed at $(& $one 'resolution')."
            "Platforms: $((& $all 'platforms') -join ', '). Controls: $((& $all 'input') -join ', ')."
            "Art: $((& $one 'artStyle').ToLowerInvariant()); colours $((& $one 'palette').ToLowerInvariant()); sound: $((& $one 'audio').ToLowerInvariant()).") -join "`n")
    $doc = Set-BriefSection $doc 'Out of scope' (ConvertTo-BriefSentence (& $one 'outOfScope'))
    $gddPath = Join-Path $Dir 'docs/GDD.md'
    $tmp = Join-Path ([System.IO.Path]::GetTempPath()) "brief-gdd-$([guid]::NewGuid().ToString('n')).md"
    [System.IO.File]::WriteAllText($tmp, $doc, [System.Text.UTF8Encoding]::new($false))
    $problems = @(Get-GddProblems (Read-Gdd $tmp))
    Remove-Item -LiteralPath $tmp -Force
    if ($problems.Count) { Stop-GodotCi "The GDD written from the brief breaks the feature grammar (a kit bug): $(@($problems | ForEach-Object { $_.problem }) -join '; ')" 'unexpected-error' }
    New-Item -ItemType Directory -Force (Split-Path $gddPath) | Out-Null
    [System.IO.File]::WriteAllText([System.IO.Path]::GetFullPath($gddPath), $doc, [System.Text.UTF8Encoding]::new($false))
    $written = [System.Collections.Generic.List[string]]::new(); $written.Add($gddPath)
    $stylePath = Join-Path $Dir 'docs/STYLE.md'
    if (-not (Test-Path -LiteralPath $stylePath)) {
        $style = (Get-Content -LiteralPath (Join-Path $PSScriptRoot '../templates/STYLE.md') -Raw).Replace('{{GAME}}', $title) -replace "`r`n", "`n"
        $design = & $one 'resolution'
        $resolutions = @(@($design) + @('1920x1080', '1280x720') | Select-Object -Unique)
        # A script block, not a string: the answers are the user's words, and a "$1" in them must stay text.
        $line = "Resolutions: $($resolutions -join ', ')`n`nArt style: $(& $one 'artStyle'). Colours: $(& $one 'palette') (from the brief; /look picks the colours below)."
        $style = [regex]::Replace($style, '(?m)^Resolutions:.*$', { param($m) $line })
        [System.IO.File]::WriteAllText([System.IO.Path]::GetFullPath($stylePath), $style, [System.Text.UTF8Encoding]::new($false))
        $written.Add($stylePath)
    }
    return @($written)
}

function Join-BriefResult([string]$Path, $Text, $State) {
    $result = [ordered]@{ path = $Path }
    if ($null -ne $Text) { $result['text'] = $Text }
    foreach ($key in $State.Keys) { $result[$key] = $State[$key] }
    return $result
}

function Invoke-Brief([string]$Dir, [string]$Action, [string]$Id, [string]$Value, [string]$Quote, [string]$TextFile) {
    if (-not (Test-Path -LiteralPath $Dir -PathType Container)) { Stop-GodotCi "The game's folder $Dir does not exist; create it, or pass -Project <folder>" 'invalid-arguments' }
    $Dir = (Resolve-Path -LiteralPath $Dir).Path
    $path = Get-BriefPath $Dir
    switch ($Action) {
        'start' {
            if (-not $TextFile) { Stop-GodotCi 'brief -Do start needs -TextFile <file>: the game described in the user''s own words, saved to a file' 'invalid-arguments' }
            if (-not (Test-Path -LiteralPath $TextFile -PathType Leaf)) { Stop-GodotCi "-TextFile $TextFile does not exist" 'invalid-arguments' }
            if (Test-Path -LiteralPath $path) { Stop-GodotCi "$path already exists; answer its questions (brief), or delete it to start over" 'brief-exists' }
            $text = (Get-Content -LiteralPath $TextFile -Raw).Trim()
            if (-not $text) { Stop-GodotCi "-TextFile $TextFile is empty: describe the game first" 'invalid-arguments' }
            Save-Brief $Dir ([ordered]@{ startedAt = [datetime]::UtcNow.ToString('o'); text = $text; answers = [ordered]@{} })
            Write-CiLog "Started $path from $TextFile ($($text.Length) characters)"
        }
        'answer' {
            $brief = Read-Brief $Dir
            $bank = Get-BriefQuestions
            $ids = @($bank.questions | ForEach-Object id)
            if (-not $Id) { Stop-GodotCi "brief -Do answer needs -Id (one of: $($ids -join ', '))" 'invalid-arguments' }
            $question = @($bank.questions | Where-Object { $_.id -ceq $Id })
            if ($question.Count -eq 0) {
                $close = Get-ClosestName $Id $ids
                Stop-GodotCi "'$Id' is not a brief question$(if ($close) { " (did you mean $($close)?)" }); the questions: $($ids -join ', ')" 'invalid-arguments'
            }
            $question = $question[0]
            if (-not (Test-BriefApplies $question $brief['answers'])) { Stop-GodotCi "'$Id' does not apply to this game with the answers so far ($(@($question.when.PSObject.Properties | ForEach-Object { "$($_.Name): $(@($_.Value) -join ' or ')" }) -join '; '))" 'invalid-answer' }
            if (-not $Value) { Stop-GodotCi "brief -Do answer -Id $Id needs -Value" 'invalid-arguments' }
            $converted = ConvertTo-BriefValue $question $Value
            if (-not $converted.ok) { Stop-GodotCi $converted.message 'invalid-answer' }
            $source = 'asked'
            if ($Quote) {
                if (-not (Test-BriefQuote $brief['text'] $Quote)) { Stop-GodotCi "The quote is not in the description word for word: ""$Quote"". Quote the sentence that states the answer exactly, or ask the question instead" 'invalid-answer' }
                $source = 'text'
            }
            $brief['answers'][$Id] = [ordered]@{ value = @($converted.value); source = $source; quote = ($Quote ? $Quote.Trim() : $null); at = [datetime]::UtcNow.ToString('o') }
            Save-Brief $Dir $brief
            Write-CiLog "$Id = $(if (@($converted.value).Count) { @($converted.value) -join ', ' } else { 'none' }) ($source)"
        }
        'gdd' {
            $brief = Read-Brief $Dir
            $state = Get-BriefState $brief
            if (-not $state.complete) {
                Set-JsonField brief (Join-BriefResult $path $null $state)
                Stop-GodotCi "The brief is not complete: $($state.open) question(s) open$(if ($state.conflicts.Count) { ", $($state.conflicts.Count) rule(s) broken: $(@($state.conflicts | ForEach-Object { $_.message }) -join '; ')" })" 'brief-incomplete'
            }
            $gddPath = Join-Path $Dir 'docs/GDD.md'
            if (Test-Path -LiteralPath $gddPath) { Stop-GodotCi "$gddPath already exists; /game confirms and edits it. Delete it to write it again from the brief" 'gdd-exists' }
            $written = New-BriefGdd $brief $Dir
            $a = $brief['answers']
            $scope = @(Get-BriefAnswerValues $a 'scope')[0]
            $planProfile = $scope -eq 'Game jam' ? 'jam' : 'full'
            $title = @(Get-BriefAnswerValues $a 'title')[0]
            $hours = @{ 'Under 5' = 4; '5 to 10' = 8; '10 to 20' = 15; 'Over 20' = 25 }
            $weekly = $a.Contains('weeklyHours') ? $hours[@(Get-BriefAnswerValues $a 'weeklyHours')[0]] : $null
            $next = [System.Collections.Generic.List[string]]::new()
            if (-not (Test-Path -LiteralPath (Join-Path $Dir 'project.godot'))) {
                $next.Add("Create the Godot 4.7 project in $Dir$(if ('C#' -in (Get-BriefAnswerValues $a 'language')) { ' with the .NET build of Godot (C#)' })")
            }
            $next.Add((Format-KitCommand "plan -Do init -Profile $planProfile -Game ""$title"""))
            $next.Add('/game: confirm the draft GDD section by section')
            Set-JsonField written @($written)
            Set-JsonField nextSteps @($next)
            Set-JsonField planProfile $planProfile
            Set-JsonField weeklyHours $weekly
            Write-CiLog "Wrote $($written -join ', ') from the brief. Next: $($next -join '; ')"
        }
    }
    $brief = Read-Brief $Dir
    $state = Get-BriefState $brief
    if ($Action -eq 'status' -or $Action -eq 'start' -or $Action -eq 'answer') {
        if ($state.complete) { Write-CiLog "The brief is complete ($($state.answeredCount) answers). Next: $(Format-KitCommand 'brief -Do gdd')" }
        else {
            Write-CiLog "$($state.answeredCount) of $($state.applicable) answered; ask next, as written:"
            foreach ($q in $state.next) { Write-CiLog "  [$($q.id)] $($q.question)$(if ($q.options.Count) { ' (' + (@($q.options | ForEach-Object { $_.label }) -join ' / ') + ')' })" }
            foreach ($c in $state.conflicts) { Write-CiLog "  RULE $($c.rule): $($c.message). Fix: $($c.fix)" }
        }
    }
    Set-JsonField brief (Join-BriefResult $path $brief['text'] $state)
}
