#!/usr/bin/env pwsh
# Self-test of `plan -Do sync` (GitHub Projects). By default it runs against a stand-in `gh` that keeps a few projects in a
# JSON file, so it needs no account and no network. -Live runs the same steps with the real `gh` (signed in with the
# project scope: gh auth refresh -s project): it makes a private project for @me, syncs a plan to it, moves and archives
# items the way a person would, and deletes the project at the end (-KeepProject leaves it for a look). Checks: a sync
# with an owner makes the project, its Column field and one item per task in the right column (and links it to the game's
# repository), a second sync changes nothing, an item moved on the board moves its task, a task moved in the plan moves its
# item, an archived item is reported, a project.columns mapping survives sync and link, a failed call keeps the ids of the
# items made before it (stand-in), a task in an unknown column is refused before any call, a missing option and refused
# credentials fail with their codes, and the token never appears in the kit's output. Column names ("To Do", "testing")
# work in move, add and link; an item a person adds becomes a task; a removed task's item is archived by the next sync and
# its id is not given again; an item the kit made for a task no one links is reported; -Board takes <owner>/<number>, a
# project URL or an owner.
param([switch]$Live, [switch]$KeepProject)
Set-StrictMode -Version 3.0
$ErrorActionPreference = 'Stop'
$root = Split-Path $PSScriptRoot
$ci = Join-Path $root 'ci/godot/hyperdot.ps1'
$work = Join-Path ([IO.Path]::GetTempPath()) "project-$([guid]::NewGuid().ToString('N').Substring(0, 8))"
$dir = Join-Path $work 'game'
$bin = Join-Path $work 'bin'
$failures = [System.Collections.Generic.List[string]]::new()
function Assert-True([bool]$Condition, [string]$What) {
    if ($Condition) { Write-Host "ok     $What" } else { Write-Host "FAILED $What" -ForegroundColor Red; $failures.Add($What) }
}

# The stand-in keeps just enough of GitHub Projects for the sync: projects (by owner and number) with their fields,
# single-select options and draft items, and the calls it was given. FAKE_GH_MODE makes it refuse (scope) or fail (fail).
$standIn = @'
param()
Set-StrictMode -Version 3.0
$ErrorActionPreference = 'Stop'
$argv = @($args)
$statePath = Join-Path $env:FAKE_GH_DIR 'state.json'
Add-Content -LiteralPath (Join-Path $env:FAKE_GH_DIR 'calls.log') -Value ($args -join ' ')
if ($env:FAKE_GH_MODE -eq 'scope') { [Console]::Error.WriteLine('error: your authentication token is missing required scopes [project]'); exit 1 }
if ($env:FAKE_GH_MODE -eq 'fail') { [Console]::Error.WriteLine('HTTP 502: Bad Gateway'); exit 1 }
$state = Get-Content -LiteralPath $statePath -Raw | ConvertFrom-Json -AsHashtable
function Get-Flag([string]$Name) { $i = [array]::IndexOf($argv, $Name); if ($i -ge 0 -and $i + 1 -lt $argv.Count) { return [string]$argv[$i + 1] } return $null }
function New-GhId([string]$Prefix) { $Prefix + '_' + [guid]::NewGuid().ToString('N').Substring(0, 12) }
function Save-State { $state | ConvertTo-Json -Depth 20 | Set-Content -LiteralPath $statePath -Encoding utf8 }
if ($argv[0] -ne 'project') { exit 2 }
$command = $argv[1]
$owner = Get-Flag '--owner'
$needs = @('view', 'field-list', 'field-create', 'item-list', 'item-create', 'item-archive', 'link', 'delete')
if ($command -in $needs) {
    $project = $null
    foreach ($p in $state.projects) { if ($p.owner -eq $owner -and "$($p.number)" -eq "$($argv[2])") { $project = $p } }
    if (-not $project) { [Console]::Error.WriteLine("GraphQL: Could not resolve to a ProjectV2 with the number $($argv[2])."); exit 1 }
}
switch ($command) {
    'create' {
        $number = $state.projects.Count + 1
        $project = @{ id = New-GhId 'PVT'; number = $number; owner = $owner; title = (Get-Flag '--title'); linked = @()
            fields = @(@{ id = New-GhId 'PVTSSF'; name = 'Status'; type = 'ProjectV2SingleSelectField'; options = @(@{ id = 'o1'; name = 'Todo' }, @{ id = 'o2'; name = 'In Progress' }, @{ id = 'o3'; name = 'Done' }) })
            items = @() }
        $state.projects = @($state.projects) + $project; Save-State
        @{ id = $project.id; number = $number; title = $project.title } | ConvertTo-Json -Compress
    }
    'view' { @{ id = $project.id; number = $project.number; title = $project.title } | ConvertTo-Json -Compress }
    'field-list' { @{ fields = @($project.fields); totalCount = @($project.fields).Count } | ConvertTo-Json -Depth 10 -Compress }
    'field-create' {
        $options = @((Get-Flag '--single-select-options') -split ',' | ForEach-Object { @{ id = New-GhId 'opt'; name = $_ } })
        $field = @{ id = New-GhId 'PVTSSF'; name = (Get-Flag '--name'); type = 'ProjectV2SingleSelectField'; options = $options }
        $project.fields = @($project.fields) + $field; Save-State
        @{ id = $field.id; name = $field.name } | ConvertTo-Json -Compress
    }
    'item-list' {
        $items = @(foreach ($i in $project.items) { if (-not $i.archived) {
            $o = [ordered]@{ id = $i.id; title = $i.title; content = [ordered]@{ type = 'DraftIssue'; body = $i.body; title = $i.title } }
            if ($i.column) { $o['column'] = $i.column }
            $o } })
        @{ items = $items; totalCount = $items.Count } | ConvertTo-Json -Depth 10 -Compress
    }
    'item-create' {
        if ((Get-Flag '--title').StartsWith('Rate limited')) { [Console]::Error.WriteLine('HTTP 502: Bad Gateway'); exit 1 }
        $item = @{ id = New-GhId 'PVTI'; title = (Get-Flag '--title'); body = (Get-Flag '--body'); column = $null; archived = $false }
        $project.items = @($project.items) + $item; Save-State
        @{ id = $item.id; title = $item.title; body = $item.body; type = 'DraftIssue' } | ConvertTo-Json -Compress
    }
    'item-edit' {
        $found = $null
        foreach ($p in $state.projects) { if ($p.id -eq (Get-Flag '--project-id')) { foreach ($i in $p.items) { if ($i.id -eq (Get-Flag '--id')) { $found = @($p, $i) } } } }
        if (-not $found) { [Console]::Error.WriteLine('item not found'); exit 1 }
        foreach ($f in $found[0].fields) { if ($f.id -eq (Get-Flag '--field-id')) { foreach ($o in $f.options) { if ($o.id -eq (Get-Flag '--single-select-option-id')) { $found[1].column = $o.name } } } }
        Save-State
        @{ id = $found[1].id } | ConvertTo-Json -Compress
    }
    'item-archive' {
        foreach ($i in $project.items) { if ($i.id -eq (Get-Flag '--id')) { $i.archived = $true } }
        Save-State
    }
    'link' { $project.linked = @($project.linked) + (Get-Flag '--repo'); Save-State }
    'delete' { $state.projects = @($state.projects | Where-Object { $_.id -ne $project.id }); Save-State }
    default { exit 2 }
}
'@

New-Item -ItemType Directory -Force $dir, $bin | Out-Null
$saved = @{ path = $env:PATH; dir = $env:FAKE_GH_DIR; mode = $env:FAKE_GH_MODE; token = $env:GH_TOKEN }
$canary = 'ghp_' + ('c' * 36)
$project = $null; $projectOwner = $null
if (-not $Live) {
    Set-Content -LiteralPath (Join-Path $work 'state.json') -Value '{"projects":[]}'
    Set-Content -LiteralPath (Join-Path $work 'calls.log') -Value ''
    Set-Content -LiteralPath (Join-Path $work 'gh.ps1') -Value $standIn
    Set-Content -LiteralPath (Join-Path $bin 'gh') -Value "#!/bin/sh`nexec pwsh -NoProfile -NonInteractive -File `"`$FAKE_GH_DIR/gh.ps1`" `"`$@`"`n"
    Set-Content -LiteralPath (Join-Path $bin 'gh.cmd') -Value "@pwsh -NoProfile -NonInteractive -File `"%FAKE_GH_DIR%\gh.ps1`" %*`r`n"
    if (-not $IsWindows) { & chmod +x (Join-Path $bin 'gh') }
    $env:FAKE_GH_DIR = $work; $env:FAKE_GH_MODE = ''
    $env:PATH = "$bin$([IO.Path]::PathSeparator)$($env:PATH)"
    $env:GH_TOKEN = $canary
    $projectOwner = 'tester'
} else {
    if (-not (Get-Command gh -ErrorAction SilentlyContinue)) { throw 'Install the GitHub CLI and run gh auth refresh -s project to run the live project test' }
    $projectOwner = '@me'
}

# The test's own calls stand in for a person working on the board.
function Get-State { return (Get-Content -LiteralPath (Join-Path $work 'state.json') -Raw | ConvertFrom-Json -AsHashtable) }
function Save-StateFile($State) { $State | ConvertTo-Json -Depth 20 | Set-Content -LiteralPath (Join-Path $work 'state.json') -Encoding utf8 }
function Get-BoardItems([string]$Number) {
    if (-not $Live) { return @((Get-State).projects | Where-Object { "$($_.number)" -eq $Number -and $_.owner -eq $projectOwner } | ForEach-Object { $_.items }) | Where-Object { -not $_.archived } }
    return @((gh project item-list $Number --owner $projectOwner --limit 500 --format json | ConvertFrom-Json).items)
}
function Get-BoardItem([string]$Number, [string]$ItemId) {
    $item = @(Get-BoardItems $Number) | Where-Object { $_['id'] -eq $ItemId -or ($_ -isnot [hashtable] -and $_.id -eq $ItemId) } | Select-Object -First 1
    if ($item -is [hashtable]) { return [pscustomobject]$item }
    return $item
}
function Move-BoardItem([string]$Number, [string]$ItemId, [string]$ColumnName) {
    if (-not $Live) {
        $s = Get-State
        foreach ($p in $s.projects) { if ("$($p.number)" -eq $Number) { foreach ($i in $p.items) { if ($i.id -eq $ItemId) { $i.column = $ColumnName } } } }
        Save-StateFile $s; return
    }
    $view = gh project view $Number --owner $projectOwner --format json | ConvertFrom-Json
    $field = (gh project field-list $Number --owner $projectOwner --format json | ConvertFrom-Json).fields | Where-Object { $_.name -eq 'Column' }
    $option = $field.options | Where-Object { $_.name -eq $ColumnName }
    gh project item-edit --id $ItemId --project-id $view.id --field-id $field.id --single-select-option-id $option.id | Out-Null
}
function Add-BoardItem([string]$Number, [string]$Title, [string]$Body, [string]$ColumnName) {
    if (-not $Live) {
        $s = Get-State
        $id = 'PVTI_person' + [guid]::NewGuid().ToString('N').Substring(0, 8)
        foreach ($p in $s.projects) { if ("$($p.number)" -eq $Number) { $p.items = @($p.items) + @{ id = $id; title = $Title; body = $Body; column = $ColumnName; archived = $false } } }
        Save-StateFile $s; return $id
    }
    $made = gh project item-create $Number --owner $projectOwner --title $Title --body $Body --format json | ConvertFrom-Json
    Move-BoardItem $Number $made.id $ColumnName
    return $made.id
}
function Remove-BoardItem([string]$Number, [string]$ItemId) {
    if (-not $Live) {
        $s = Get-State
        foreach ($p in $s.projects) { if ("$($p.number)" -eq $Number) { foreach ($i in $p.items) { if ($i.id -eq $ItemId) { $i.archived = $true } } } }
        Save-StateFile $s; return
    }
    gh project item-archive $Number --owner $projectOwner --id $ItemId | Out-Null
}
function Rename-BoardOption([string]$Number, [string]$From, [string]$To) {
    if ($Live) { throw 'renaming an option is only done in the stand-in' }
    $s = Get-State
    foreach ($p in $s.projects) { if ("$($p.number)" -eq $Number) { foreach ($f in $p.fields) { if ($f.name -eq 'Column') { foreach ($o in $f.options) { if ($o.name -eq $From) { $o.name = $To } } } } } }
    Save-StateFile $s
}

$outputs = [System.Collections.Generic.List[string]]::new()
function Invoke-PlanJson([string[]]$Arguments) {
    $errFile = Join-Path $work 'stderr.txt'
    $out = pwsh -NoProfile -NonInteractive -File $ci plan -Json -Project $dir @Arguments 2>$errFile
    $outputs.Add(($out -join "`n") + (Get-Content -LiteralPath $errFile -Raw -ErrorAction SilentlyContinue))
    return ($out -join "`n") | ConvertFrom-Json
}
$planPath = Join-Path $dir 'plan/plan.json'
function Read-PlanFile { return (Get-Content -LiteralPath $planPath -Raw | ConvertFrom-Json) }
function Save-PlanFile($Plan) { $Plan | ConvertTo-Json -Depth 10 | Set-Content -LiteralPath $planPath -Encoding utf8 }
function Get-PlanTask([string]$Id) { return @((Read-PlanFile).tasks) | Where-Object { $_.id -eq $Id } | Select-Object -First 1 }
function Get-ItemColumn([string]$Number, [string]$ItemId) {
    $item = Get-BoardItem $Number $ItemId
    return ($item -and $item.PSObject.Properties['column']) ? $item.column : $null
}
function ConvertTo-Summary($Sync) { return ($Sync | ConvertTo-Json -Depth 10 -Compress) }

try {
    Set-Content -LiteralPath (Join-Path $dir 'project.godot') -Value "config_version=5`n`n[application]`n`nconfig/name=""Sync Fixture""`n"
    pwsh -NoProfile -NonInteractive -File $ci plan -Do init -Project $dir 2>$null | Out-Null

    $missing = Invoke-PlanJson @('-Do', 'sync')
    Assert-True (-not $missing.ok -and $missing.error.code -eq 'invalid-arguments') 'sync without -Board or a saved project fails with invalid-arguments'
    $d = Invoke-PlanJson @('-Do', 'sync', '-Board', 'not a project!')
    Assert-True (-not $d.ok -and $d.error.code -eq 'invalid-arguments') 'a -Board that is no project fails with invalid-arguments'

    foreach ($task in @(@('Paddle movement', 'backlog'), @('Combo multiplier', 'todo'), @('Pause menu', 'doing'), @('Title screen', 'done'))) {
        Invoke-PlanJson @('-Do', 'add', '-Title', $task[0], '-Column', $task[1]) | Out-Null
    }

    # The game has a GitHub origin, so the new project is linked to it (the stand-in logs the link call).
    git -C $dir init -q 2>$null | Out-Null
    git -C $dir remote add origin 'https://github.com/nick-vas/sync-fixture.git' 2>$null | Out-Null

    $d = Invoke-PlanJson @('-Do', 'sync', '-Board', $projectOwner)
    Assert-True ($d.ok -and $d.sync.madeProject -and $d.sync.created -eq 4 -and $d.sync.moved -eq 0) "sync with an owner makes the project and 4 items: $(if ($d.ok) { ConvertTo-Summary $d.sync } else { $d.error.message })"
    $number = $d.ok ? ($d.sync.board -split '/')[-1] : '0'
    $project = $number
    Assert-True ($d.sync.board -eq "$projectOwner/$number" -and $d.projectBoard -eq "$projectOwner/$number") 'the sync returns the project as <owner>/<number>'
    $plan = Read-PlanFile
    Assert-True ($plan.project.owner -eq $projectOwner -and "$($plan.project.number)" -eq $number) 'sync saves the project to plan.json'
    Assert-True (@($plan.tasks | Where-Object { $_.itemId -match '^PVTI_[A-Za-z0-9_-]+$' }).Count -eq 4) 'every task gets a PVTI_ item id'
    if (-not $Live) {
        Assert-True ((Get-Content -LiteralPath (Join-Path $work 'calls.log') -Raw) -match 'project link \d+ --owner tester --repo nick-vas/sync-fixture') 'the new project is linked to the game repository'
        Assert-True ((Get-State).projects[0].title -eq 'Sync Fixture plan') 'the project is titled "<game> plan"'
    }
    $expected = @{ t1 = 'Backlog'; t2 = 'To Do'; t3 = 'Doing'; t4 = 'Done' }
    foreach ($id in 't1', 't2', 't3', 't4') {
        $item = Get-BoardItem $number (Get-PlanTask $id).itemId
        Assert-True ($item.column -eq $expected[$id]) "$id's item is in '$($expected[$id])'"
        $body = $item.PSObject.Properties['content'] ? $item.content.body : $item.body
        Assert-True ($body -eq "plan task $id, phase concept") "$id's item says 'plan task $id, phase concept'"
    }

    $d = Invoke-PlanJson @('-Do', 'sync')
    Assert-True ($d.ok -and $d.sync.created -eq 0 -and $d.sync.moved -eq 0 -and -not $d.sync.madeProject -and $d.sync.board -eq "$projectOwner/$number") 'a second sync uses the saved project and changes nothing'

    Move-BoardItem $number (Get-PlanTask 't2').itemId 'Testing'
    $d = Invoke-PlanJson @('-Do', 'sync')
    Assert-True ($d.ok -and $d.sync.moved -eq 1 -and $d.sync.created -eq 0) 'an item moved on the board counts as moved'
    Assert-True ((Get-PlanTask 't2').column -eq 'verify' -and (Get-PlanTask 't2').boardColumn -eq 'verify') 'the moved item moves its task to verify, and its boardColumn with it'

    Invoke-PlanJson @('-Do', 'add', '-Title', 'Level select') | Out-Null
    $d = Invoke-PlanJson @('-Do', 'sync')
    Assert-True ($d.ok -and $d.sync.created -eq 1) 'a task added to the plan becomes one new item'
    $item = Get-BoardItem $number (Get-PlanTask 't5').itemId
    Assert-True ($item.title -eq 'Level select' -and $item.column -eq 'Backlog') 'the new item is "Level select" in Backlog'

    # A task moved in the plan since the last sync moves its item; the board's earlier move above is not undone.
    Invoke-PlanJson @('-Do', 'move', '-Id', 't5', '-Column', 'todo') | Out-Null
    $d = Invoke-PlanJson @('-Do', 'sync')
    Assert-True ($d.ok -and $d.sync.moved -eq 0 -and $d.sync.itemsMoved -eq 1) "a task moved with plan -Do move moves its item: $(if ($d.ok) { ConvertTo-Summary $d.sync } else { $d.error.message })"
    Assert-True ((Get-PlanTask 't5').column -eq 'todo' -and (Get-PlanTask 't2').column -eq 'verify') 'the sync keeps the plan move (t5 in todo) and the board move (t2 in verify)'
    Assert-True ((Get-ItemColumn $number (Get-PlanTask 't5').itemId) -eq 'To Do') "t5's item follows it to 'To Do'"
    $d = Invoke-PlanJson @('-Do', 'sync')
    Assert-True ($d.ok -and $d.sync.moved -eq 0 -and $d.sync.itemsMoved -eq 0 -and $d.sync.created -eq 0) 'the sync after that changes nothing'

    Remove-BoardItem $number (Get-PlanTask 't1').itemId
    $d = Invoke-PlanJson @('-Do', 'sync')
    Assert-True ($d.ok -and @($d.sync.warnings | Where-Object { $_ -match '\bt1\b' }).Count -eq 1) "an archived item is reported, not recreated: $(if ($d.ok) { $d.sync.warnings -join ' | ' } else { $d.error.message })"
    Assert-True ($d.sync.created -eq 0 -and (Get-PlanTask 't1').column -eq 'backlog') 'the archived item leaves its task as it was'

    if (-not $Live) {
        # A renamed option is a missing column; project.columns names the new one, and the mapping survives sync and link -Board.
        Rename-BoardOption $number 'Design' 'Ideas'
        $d = Invoke-PlanJson @('-Do', 'sync')
        Assert-True (-not $d.ok -and $d.error.code -eq 'project-column-missing' -and $d.error.message -match "'design'") "a Column field without a Design option fails with project-column-missing: $($d.error.message)"
        $plan = Read-PlanFile
        $plan.project | Add-Member -NotePropertyName columns -NotePropertyValue ([pscustomobject]@{ design = 'Ideas' }) -Force
        Save-PlanFile $plan
        $d = Invoke-PlanJson @('-Do', 'sync')
        Assert-True ($d.ok) "project.columns maps design to the option 'Ideas': $(if (-not $d.ok) { $d.error.message })"
        Invoke-PlanJson @('-Do', 'link', '-Board', "$projectOwner/$number") | Out-Null
        $plan = Read-PlanFile
        Assert-True ($plan.project.columns.design -eq 'Ideas' -and "$($plan.project.number)" -eq $number) 'sync and link -Board keep project.columns'
        $plan.project.PSObject.Properties.Remove('columns'); Save-PlanFile $plan
        Rename-BoardOption $number 'Ideas' 'Design'
    }

    # A column no option maps to is refused before any call, so nothing is half done.
    Invoke-PlanJson @('-Do', 'add', '-Title', 'Combo meter') | Out-Null
    $plan = Read-PlanFile
    (@($plan.tasks) | Where-Object { $_.id -eq 't6' }).column = 'review'
    Save-PlanFile $plan
    $d = Invoke-PlanJson @('-Do', 'sync')
    Assert-True (-not $d.ok -and $d.error.code -eq 'invalid-plan' -and $d.error.message -match 't6') "a task in an unknown column fails with invalid-plan: $($d.error.code) $($d.error.message)"
    Assert-True (-not (Get-PlanTask 't6').PSObject.Properties['itemId']) 'and gets no item'
    Invoke-PlanJson @('-Do', 'move', '-Id', 't6', '-Column', 'backlog') | Out-Null

    if (-not $Live) {
        # A call that fails halfway must not lose the ids of the items made before it.
        Invoke-PlanJson @('-Do', 'add', '-Title', 'Rate limited once') | Out-Null
        $d = Invoke-PlanJson @('-Do', 'sync')
        Assert-True (-not $d.ok -and $d.error.code -eq 'project-error' -and $d.error.message -match '502') "a failing call fails with project-error: $($d.error.code) $($d.error.message)"
        Assert-True ([bool](Get-PlanTask 't6').PSObject.Properties['itemId']) 'the item made before the failure keeps its id in plan.json'
        $plan = Read-PlanFile
        (@($plan.tasks) | Where-Object { $_.id -eq 't7' }).title = 'Credits screen'
        Save-PlanFile $plan
        $d = Invoke-PlanJson @('-Do', 'sync')
        Assert-True ($d.ok -and $d.sync.created -eq 1) "the next sync creates only the missing item: $(if ($d.ok) { ConvertTo-Summary $d.sync } else { $d.error.message })"
        Assert-True (@(Get-BoardItems $number | Where-Object { $_.title -eq 'Combo meter' }).Count -eq 1) 'no item is duplicated'
    }

    # Column names stand for columns, case-insensitive and by prefix as sync matches options; anything else is refused.
    $done = 'Done ' + [char]::ConvertFromUtf32(0x1F389)
    $d = Invoke-PlanJson @('-Do', 'add', '-Title', 'Sound pass', '-Column', 'testing')
    $sound = $d.ok ? $d.task.id : $null
    Assert-True ($d.ok -and $d.task.column -eq 'verify') "plan -Do add takes the name 'testing' for verify: $(if (-not $d.ok) { $d.error.message })"
    $d = Invoke-PlanJson @('-Do', 'move', '-Id', $sound, '-Column', 'To Do')
    Assert-True ($d.ok -and $d.task.column -eq 'todo') "plan -Do move takes 'To Do' for todo: $(if (-not $d.ok) { $d.error.message })"
    $d = Invoke-PlanJson @('-Do', 'move', '-Id', $sound, '-Column', $done)
    Assert-True ($d.ok -and $d.task.column -eq 'done') "plan -Do move takes '$done' for done: $(if (-not $d.ok) { $d.error.message })"
    $d = Invoke-PlanJson @('-Do', 'link', '-Id', $sound, '-Column', 'to do')
    Assert-True ($d.ok -and (Get-PlanTask $sound).boardColumn -eq 'todo') "plan -Do link -Column takes 'to do' for todo: $(if (-not $d.ok) { $d.error.message })"
    $d = Invoke-PlanJson @('-Do', 'move', '-Id', $sound, '-Column', 'Review')
    Assert-True (-not $d.ok -and $d.error.code -eq 'invalid-arguments' -and $d.error.message -match 'To Do') "a column that is neither an id nor a name fails with invalid-arguments: $($d.error.message)"
    $d = Invoke-PlanJson @('-Do', 'sync')
    Assert-True ($d.ok -and $d.sync.itemsMoved -eq 0 -and $d.sync.moved -eq 0 -and (Get-PlanTask $sound).column -eq 'done') "after a recorded column the sync creates the item where the plan says: $(if ($d.ok) { ConvertTo-Summary $d.sync } else { $d.error.message })"

    # An item a person adds on the board becomes a task in its column; the next sync does not add it again.
    $personItem = Add-BoardItem $number 'Boss rush mode' '' 'To Do'
    $d = Invoke-PlanJson @('-Do', 'sync')
    Assert-True ($d.ok -and $d.sync.imported -eq 1 -and $d.sync.created -eq 0) "an item added on the board is imported: $(if ($d.ok) { ConvertTo-Summary $d.sync } else { $d.error.message })"
    $boss = @((Read-PlanFile).tasks) | Where-Object { $_.PSObject.Properties['itemId'] -and $_.itemId -eq $personItem } | Select-Object -First 1
    Assert-True ($boss -and $boss.title -eq 'Boss rush mode' -and $boss.column -eq 'todo' -and $boss.boardColumn -eq 'todo' -and $boss.phase -eq 'concept') 'it becomes a task in todo with the current phase'
    $d = Invoke-PlanJson @('-Do', 'sync')
    Assert-True ($d.ok -and $d.sync.imported -eq 0 -and $d.sync.created -eq 0) 'the next sync imports nothing'

    # plan -Do remove deletes the task; the next sync archives its item, which is then not imported back.
    $d = Invoke-PlanJson @('-Do', 'remove', '-Id', $boss.id)
    Assert-True ($d.ok -and $d.task.itemId -eq $personItem -and -not (Get-PlanTask $boss.id) -and @((Read-PlanFile).project.toArchive) -contains $personItem) "plan -Do remove deletes $($boss.id) and queues its item for archiving"
    $d = Invoke-PlanJson @('-Do', 'sync')
    Assert-True ($d.ok -and $d.sync.archived -eq 1 -and $d.sync.imported -eq 0) "the next sync archives the item: $(if ($d.ok) { ConvertTo-Summary $d.sync } else { $d.error.message })"
    Assert-True (-not (Get-BoardItem $number $personItem)) 'the item is archived on the board'
    Assert-True (-not (Read-PlanFile).project.PSObject.Properties['toArchive']) 'and nothing is left to archive'
    $d = Invoke-PlanJson @('-Do', 'add', '-Title', 'After the removal')
    Assert-True ($d.ok -and [int]($d.task.id -replace '\D', '') -gt [int]($boss.id -replace '\D', '')) "a removed task's id is not given again: $($boss.id) removed, $($d.task.id) added"
    $d = Invoke-PlanJson @('-Do', 'remove', '-Id', 't999')
    Assert-True (-not $d.ok -and $d.error.code -eq 'unknown-task') 'removing a task that does not exist fails with unknown-task'

    # An item the kit made for a task that no task links (its body says "plan task") is reported, not imported.
    $stray = Add-BoardItem $number 'Old task' 'plan task t99, phase concept' 'Backlog'
    $d = Invoke-PlanJson @('-Do', 'sync')
    Assert-True ($d.ok -and $d.sync.imported -eq 0 -and @($d.sync.warnings | Where-Object { $_ -match 't99' -and $_.Contains($stray) }).Count -eq 1) "a kit item no task links is reported: $(if ($d.ok) { $d.sync.warnings -join ' | ' } else { $d.error.message })"
    Remove-BoardItem $number $stray

    # link -Item stores the id; anything else is refused. -Board takes <owner>/<number> or the project's URL; an owner alone only makes a project in sync.
    $d = Invoke-PlanJson @('-Do', 'add', '-Title', 'Linked by hand')
    $byHand = $d.task.id
    $handItem = Add-BoardItem $number 'Linked by hand' "plan task $byHand, phase concept" 'Backlog'
    $d = Invoke-PlanJson @('-Do', 'link', '-Id', $byHand, '-Item', $handItem, '-Column', 'Backlog')
    Assert-True ($d.ok -and (Get-PlanTask $byHand).itemId -eq $handItem -and $d.task.boardColumn -eq 'backlog') "plan -Do link -Item stores the item id: $(if (-not $d.ok) { $d.error.message })"
    $d = Invoke-PlanJson @('-Do', 'sync')
    Assert-True ($d.ok -and $d.sync.created -eq 0 -and $d.sync.imported -eq 0 -and @($d.sync.warnings | Where-Object { $_ -match "\b$byHand\b" }).Count -eq 0) "the linked item is the task's item: $(if ($d.ok) { ConvertTo-Summary $d.sync } else { $d.error.message })"
    $d = Invoke-PlanJson @('-Do', 'link', '-Id', $byHand, '-Item', 'https://github.com/users/x/projects/1/views/1')
    Assert-True (-not $d.ok -and $d.error.code -eq 'invalid-arguments' -and (Get-PlanTask $byHand).itemId -eq $handItem) "a URL is no item id: $($d.error.message)"
    $d = Invoke-PlanJson @('-Do', 'link', '-Board', "https://github.com/users/$($projectOwner -replace '@me', 'me')/projects/$number/views/1")
    Assert-True ($d.ok -and $d.projectBoard -eq "$($projectOwner -replace '@me', 'me')/$number") "link -Board <project URL> saves owner/number: $(if ($d.ok) { $d.projectBoard } else { $d.error.message })"
    $d = Invoke-PlanJson @('-Do', 'link', '-Board', $projectOwner)
    Assert-True (-not $d.ok -and $d.error.code -eq 'invalid-arguments') 'link -Board with just an owner is refused (only sync makes projects)'
    Invoke-PlanJson @('-Do', 'link', '-Board', "$projectOwner/$number") | Out-Null

    # The Stop hook syncs a changed plan by itself, once, and never blocks.
    if (-not $Live) {
        $hook = Join-Path $root 'hooks/project-sync.ps1'
        $stamp = Join-Path $dir '.godot/hyperdot-project-sync'
        $callsPath = Join-Path $work 'calls.log'
        function Invoke-Hook([hashtable]$Environment = @{}) {
            $before = @(Get-Content -LiteralPath $callsPath).Count
            $saved = @{}; foreach ($k in $Environment.Keys) { $saved[$k] = [Environment]::GetEnvironmentVariable($k); [Environment]::SetEnvironmentVariable($k, $Environment[$k]) }
            try { $out = ('{"cwd": ' + (ConvertTo-Json -InputObject $dir -Depth 2) + '}') | pwsh -NoProfile -NonInteractive -File $hook 2>$null; $code = $LASTEXITCODE }
            finally { foreach ($k in $saved.Keys) { [Environment]::SetEnvironmentVariable($k, $saved[$k]) } }
            return [pscustomobject]@{ code = $code; out = ($out -join "`n"); calls = (@(Get-Content -LiteralPath $callsPath).Count - $before) }
        }
        Remove-Item -LiteralPath $stamp -Force -ErrorAction SilentlyContinue
        Invoke-PlanJson @('-Do', 'add', '-Title', 'Added in the turn') | Out-Null
        $h = Invoke-Hook
        $newTask = @((Read-PlanFile).tasks | Where-Object { $_.title -eq 'Added in the turn' })[0]
        Assert-True ($h.code -eq 0 -and $newTask.PSObject.Properties['itemId'] -and $h.out -match 'synced') "the Stop hook syncs a changed plan: $($h.out)"
        $h = Invoke-Hook
        Assert-True ($h.code -eq 0 -and $h.calls -eq 0 -and -not $h.out) "and does nothing while the plan is unchanged ($($h.calls) gh call(s))"
        Invoke-PlanJson @('-Do', 'add', '-Title', 'Added later') | Out-Null
        $h = Invoke-Hook @{ HYPERDOT_PROJECT_SYNC = 'off' }
        Assert-True ($h.code -eq 0 -and $h.calls -eq 0) 'HYPERDOT_PROJECT_SYNC=off disables it'
        $h = Invoke-Hook @{ FAKE_GH_MODE = 'scope' }
        Assert-True ($h.code -eq 0 -and $h.out -match 'project-credentials') "a failed sync becomes a notice, exit 0: $($h.out)"
        $h = Invoke-Hook
        Assert-True ($h.code -eq 0 -and $h.calls -gt 0 -and $h.out -match 'synced') "the next turn tries again after a failure: $($h.out)"
        $plan = Read-PlanFile; $plan.PSObject.Properties.Remove('project'); Save-PlanFile $plan
        Remove-Item -LiteralPath $stamp -Force -ErrorAction SilentlyContinue
        $h = Invoke-Hook
        Assert-True ($h.code -eq 0 -and $h.calls -eq 0) 'a plan with no project is left alone'
        Invoke-PlanJson @('-Do', 'link', '-Board', "$projectOwner/$number") | Out-Null
    }

    if (-not $Live) {
        $env:FAKE_GH_MODE = 'scope'
        $d = Invoke-PlanJson @('-Do', 'sync')
        Assert-True (-not $d.ok -and $d.error.code -eq 'project-credentials' -and $d.error.message -match 'gh auth refresh -s project') "a token without the project scope fails with project-credentials: $($d.error.code) $($d.error.message)"
        $env:FAKE_GH_MODE = 'fail'
        $d = Invoke-PlanJson @('-Do', 'sync')
        Assert-True (-not $d.ok -and $d.error.code -eq 'project-error') "any other failure is project-error: $($d.error.code)"
        $env:FAKE_GH_MODE = ''
        $d = Invoke-PlanJson @('-Do', 'sync', '-Board', "$projectOwner/99")
        Assert-True (-not $d.ok -and $d.error.code -eq 'project-error' -and $d.error.message -match 'ProjectV2') "a project that does not exist fails with project-error: $($d.error.message)"
        Assert-True (@($outputs | Where-Object { $_.Contains($canary) }).Count -eq 0) 'no output of the kit contains the token'
    }
} finally {
    if ($Live -and $project -and -not $KeepProject) {
        try { gh project delete $project --owner $projectOwner | Out-Null } catch { Write-Host "WARNING: could not delete project $project`: $_" -ForegroundColor Yellow }
    }
    $env:PATH = $saved.path; $env:FAKE_GH_DIR = $saved.dir; $env:FAKE_GH_MODE = $saved.mode; $env:GH_TOKEN = $saved.token
    Remove-Item -LiteralPath $work -Recurse -Force -ErrorAction SilentlyContinue
}

if ($failures.Count) { throw "$($failures.Count) project sync check(s) failed" }
Write-Host "Project sync self-test passed ($(if ($Live) { 'live GitHub' } else { 'stand-in gh' }))"
# Some kit runs failed on purpose; GitHub's pwsh wrapper would exit with the last one's code.
exit 0
