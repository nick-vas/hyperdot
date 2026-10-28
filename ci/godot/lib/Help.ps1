# `help`: a Markdown reference of every command, skill and subagent (written to docs/kit-help.md of the game, which `init`
# also puts there), or the page of one. The text lives in docs/help.md, which the /kit skill shows through this command
# too, so there is one source; a skill's or subagent's page adds the "when to use it" line of its own file. Needs no
# project and no Godot.

# The kit's own folder (two levels above ci/godot/lib).
function Get-HelpKitRoot { return Split-Path (Split-Path (Split-Path $PSScriptRoot)) }

# docs/help.md as entries: a "## Commands", "## Skills" or "## Subagents" section of "### name" headings, each followed by
# its one-line summary and then its page.
function Read-HelpEntries([string]$Path) {
    $kinds = @{ 'Commands' = 'command'; 'Skills' = 'skill'; 'Subagents' = 'subagent' }
    $entries = [System.Collections.Generic.List[object]]::new()
    $kind = $null; $current = $null; $body = $null
    $finish = {
        if ($current) {
            $lines = [System.Collections.Generic.List[string]]::new()
            foreach ($l in $body) { if ($lines.Count -gt 0 -or $l.Trim()) { $lines.Add($l) } }
            $current.summary = $lines.Count ? $lines[0].Trim() : ''
            $current.page = (@($lines | Select-Object -Skip 1) -join "`n").Trim("`n").TrimEnd()
            $entries.Add($current)
        }
    }
    foreach ($line in [System.IO.File]::ReadAllLines($Path)) {
        if ($line -match '^##\s+(?<s>\S+)\s*$') {
            & $finish; $current = $null
            $kind = $kinds.ContainsKey($Matches.s) ? $kinds[$Matches.s] : $null
        } elseif ($kind -and $line -match '^###\s+(?<n>[a-z0-9-]+)\s*$') {
            & $finish
            $current = [ordered]@{ name = $Matches.n; kind = $kind; summary = ''; page = '' }
            $body = [System.Collections.Generic.List[string]]::new()
        } elseif ($current) {
            $body.Add($line)
        }
    }
    & $finish
    return @($entries)
}

# The front matter of a skill or subagent file as a hashtable of its "key: value" lines.
function Get-HelpFrontMatter([string]$Path) {
    $fields = @{}
    $m = [regex]::Match([System.IO.File]::ReadAllText($Path), '(?s)\A---\r?\n(?<fm>.*?)\r?\n---')
    foreach ($line in $m.Groups['fm'].Value -split '\r?\n') { if ($line -match '^(?<k>[\w-]+):\s*(?<v>.*)$') { $fields[$Matches.k] = $Matches.v.Trim() } }
    return $fields
}

# What exists to be described: the commands of hyperdot.ps1, the skills and the subagents.
function Get-HelpSubjects {
    $root = Get-HelpKitRoot
    $ast = [System.Management.Automation.Language.Parser]::ParseFile((Join-Path $root 'ci/godot/hyperdot.ps1'), [ref]$null, [ref]$null)
    $command = @($ast.ParamBlock.Parameters | Where-Object { $_.Name.VariablePath.UserPath -eq 'Command' })
    $set = @($command[0].Attributes | Where-Object { $_.TypeName.Name -in 'ArgumentCompletions', 'ValidateSet' })
    $skills = Join-Path $root '.agents/skills'
    $agents = Join-Path $root 'agents'
    return [ordered]@{
        command = @($set[0].PositionalArguments | ForEach-Object { $_.Value })
        skill = @(if (Test-Path -LiteralPath $skills) { Get-ChildItem -LiteralPath $skills -Directory | Where-Object { Test-Path -LiteralPath (Join-Path $_.FullName 'SKILL.md') } | ForEach-Object Name })
        subagent = @(if (Test-Path -LiteralPath $agents) { Get-ChildItem -LiteralPath $agents -File -Filter '*.md' | ForEach-Object BaseName })
    }
}

# A skill's or subagent's page: the entry's own text, then when to use it and how to start it, from its file.
function Get-HelpEntryDetails($Entry) {
    $root = Get-HelpKitRoot
    $details = [ordered]@{ name = $Entry.name; kind = $Entry.kind; summary = $Entry.summary; page = $Entry.page }
    $file = switch ($Entry.kind) {
        'skill' { Join-Path $root ".agents/skills/$($Entry.name)/SKILL.md" }
        'subagent' { Join-Path $root "agents/$($Entry.name).md" }
        default { $null }
    }
    if ($file -and (Test-Path -LiteralPath $file)) {
        $fields = Get-HelpFrontMatter $file
        $details['when'] = $fields['description']
        $details['file'] = [System.IO.Path]::GetRelativePath($root, $file) -replace '\\', '/'
        $details['start'] = if ($Entry.kind -eq 'subagent') { "Claude hands work to it when that applies; or ask for the $($Entry.name) subagent by name." }
            elseif ($fields['disable-model-invocation'] -eq 'true') { "Type /$($Entry.name) in Claude Code; Claude does not start it by itself." }
            else { "Claude loads it when that applies; /$($Entry.name) loads it by hand." }
    }
    return $details
}

# The reference as Markdown: a table each for the commands, skills and subagents. No date or version in it, so a second
# run writes the same bytes and a game's copy only changes when the kit's text does.
function New-HelpMarkdown($Entries) {
    $cell = { param([string]$Text) $Text.Replace('|', '\|') }
    $sections = @(
        [ordered]@{ kind = 'command'; title = 'Commands'; head = 'Command'; intro = 'Run as `pwsh <kit>/ci/godot/hyperdot.ps1 <command> [-Json]`.'; label = { param($n) "``$n``" } }
        [ordered]@{ kind = 'skill'; title = 'Skills'; head = 'Skill'; intro = 'Type `/<name>` in Claude Code.'; label = { param($n) "``/$n``" } }
        [ordered]@{ kind = 'subagent'; title = 'Subagents'; head = 'Subagent'; intro = 'Claude hands slow or verbose work to them; or ask for one by name.'; label = { param($n) "``$n``" } }
    )
    $out = [System.Collections.Generic.List[string]]::new()
    $out.Add('# Hyperdot kit help')
    $out.Add('')
    $out.Add('Written by `hyperdot.ps1 help` from the kit''s `docs/help.md`; the kit rewrites it, so change the text there. One page: `/kit <name>` or `hyperdot.ps1 help <name>`. Every parameter: the kit''s `docs/reference.md`.')
    foreach ($section in $sections) {
        $ofKind = @($Entries | Where-Object kind -eq $section.kind)
        if ($ofKind.Count -eq 0) { continue }
        $out.Add('')
        $out.Add("## $($section.title) ($($ofKind.Count))")
        $out.Add('')
        $out.Add($section.intro)
        $out.Add('')
        $out.Add("| $($section.head) | What it does |")
        $out.Add('|---|---|')
        foreach ($e in $ofKind) { $out.Add("| $(& $section.label $e.name) | $(& $cell $e.summary) |") }
    }
    return (($out -join "`n") + "`n")
}

# Writes the reference to $Path (creating its folder) and returns the number of entries; the same bytes every time.
function Write-HelpFile([string]$Path) {
    $source = Join-Path (Get-HelpKitRoot) 'docs/help.md'
    if (-not (Test-Path -LiteralPath $source)) { Stop-GodotCi "help reads $source, which is missing; it comes with the kit's repository" 'failed' }
    $entries = @(Read-HelpEntries $source)
    $folder = Split-Path -Path $Path
    if ($folder) { New-Item -ItemType Directory -Force -Path $folder | Out-Null }
    [System.IO.File]::WriteAllText($Path, (New-HelpMarkdown $entries), [System.Text.UTF8Encoding]::new($false))
    return $entries.Count
}

# Where `help` writes: docs/kit-help.md of the game it is given (-Project) or run in, else a file in the temp folder.
function Get-HelpFilePath([string]$Project) {
    $base = if ($Project) { [System.IO.Path]::GetFullPath($Project, (Get-Location).ProviderPath) }
        elseif (Test-Path -LiteralPath (Join-Path (Get-Location).ProviderPath 'project.godot')) { (Get-Location).ProviderPath }
        else { $null }
    if ($base) { return Join-Path $base 'docs/kit-help.md' }
    return Join-Path ([System.IO.Path]::GetTempPath()) 'hyperdot-kit-help.md'
}

function Invoke-Help([string]$Topic, [string]$Project) {
    $path = Join-Path (Get-HelpKitRoot) 'docs/help.md'
    if (-not (Test-Path -LiteralPath $path)) { Stop-GodotCi "help reads $path, which is missing; it comes with the kit's repository" 'failed' }
    $entries = @(Read-HelpEntries $path)
    if (-not $Topic) {
        Set-JsonField entries @($entries | ForEach-Object { [ordered]@{ name = $_.name; kind = $_.kind; summary = $_.summary } })
        $file = Get-HelpFilePath $Project
        $null = Write-HelpFile $file
        Set-JsonField path $file
        Write-Console "Kit help written to $file ($(@($entries | Where-Object kind -eq 'command').Count) commands, $(@($entries | Where-Object kind -eq 'skill').Count) skills, $(@($entries | Where-Object kind -eq 'subagent').Count) subagents). Open it, or ask for one page: hyperdot.ps1 help <name> (or /kit <name>)."
        return
    }
    $name = $Topic.Trim().TrimStart('/').ToLowerInvariant()
    $entry = @($entries | Where-Object { $_.name -eq $name })
    if ($entry.Count -eq 0) {
        $closest = Get-ClosestName $name @($entries | ForEach-Object name)
        Stop-GodotCi "help has no entry '$Topic'$(if ($closest) { " (did you mean $($closest)?)" }); hyperdot.ps1 help lists them all" 'invalid-arguments'
    }
    $details = Get-HelpEntryDetails $entry[0]
    Set-JsonField entry $details
    if (-not $script:JsonMode) {
        Write-Console "$($details.name) ($($details.kind)): $($details.summary)"
        if ($details.page) { Write-Console ''; Write-Console $details.page }
        Write-Console ''
        if ($details.Contains('when') -and $details.when) { Write-Console "When: $($details.when)" }
        if ($details.Contains('start')) { Write-Console "Start: $($details.start)" }
        if ($details.Contains('file')) { Write-Console "File: $($details.file)" }
    }
}
