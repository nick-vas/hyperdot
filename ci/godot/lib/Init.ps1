# `init`: wires the kit into an existing game. Only adds things (never overwrites a file), so it is
# safe to run again. Prints what it changed.

function Write-InitStep([string]$Status, [string]$Message) {
    if ($script:JsonMode) {
        if (-not $script:JsonDoc.Contains('steps')) { $script:JsonDoc['steps'] = @() }
        $script:JsonDoc['steps'] += [ordered]@{ status = $Status; message = $Message }
    }
    $color = @{ added = 'Green'; updated = 'Green'; skipped = 'DarkGray' }[$Status]
    Write-Console ('  {0,-8} ' -f $Status) -ForegroundColor $color -NoNewline
    Write-Console $Message
}

function Add-GitignoreEntries([string]$ProjectDir, [string[]]$Entries) {
    $file = Join-Path $ProjectDir '.gitignore'
    $existing = (Get-GitignoreFiles $ProjectDir | ForEach-Object { Get-Content -LiteralPath $_ }) | ForEach-Object { $_.Trim() }
    $missing = @($Entries | Where-Object { $_ -notin $existing })
    if ($missing.Count -eq 0) { Write-InitStep skipped '.gitignore already has the kit''s entries'; return }
    Add-Content -LiteralPath $file -Value (@('', '# Hyperdot') + $missing)
    Write-InitStep updated ".gitignore: $($missing -join ', ')"
}

# The workflow files of a repository that call the kit's reusable workflow (under its name now or before Hyperdot), by file name.
function Get-KitWorkflowFiles([string]$GitRoot) {
    $workflows = Join-Path $GitRoot '.github/workflows'
    @(Get-ChildItem -LiteralPath $workflows -File -ErrorAction SilentlyContinue | Where-Object { $_.Extension -in '.yml', '.yaml' } |
        Where-Object { (Get-Content -LiteralPath $_.FullName -Raw) -match '(hyperdot|Godot_TestSuite)/\.github/workflows/godot\.yml' } | Sort-Object Name)
}

function New-CiWorkflow([string]$ProjectDir) {
    $root = Get-GitRoot $ProjectDir
    if (-not $root) { Write-InitStep skipped 'CI workflow: not a git repository'; return }
    $workflows = Join-Path $root '.github/workflows'
    # A workflow written before Hyperdot calls the old repository name: it is moved once to the new name, unless another workflow already
    # calls the kit: rewriting this one would leave two copies on the same triggers and concurrency group, and each run would cancel the other
    # (a game ended up with godot-ci.yml and hyperdot.yml, identical, and Export and Release failed after 0 seconds on every pull request).
    foreach ($old in @(Get-ChildItem -LiteralPath $workflows -File -ErrorAction SilentlyContinue)) {
        $text = Get-Content -LiteralPath $old.FullName -Raw
        if ($text -notmatch 'Godot_TestSuite/\.github/workflows/godot\.yml') { continue }
        $others = @(Get-KitWorkflowFiles $root | Where-Object { $_.FullName -ne $old.FullName })
        if ($others.Count -gt 0) {
            Write-InitStep skipped ".github/workflows/$($old.Name) calls the kit by its old name and $($others[0].Name) calls it too: delete one of them (left as it is; two workflows on the same triggers cancel each other)"
            continue
        }
        Set-Content -LiteralPath $old.FullName -Encoding utf8 -NoNewline -Value ($text -replace 'nick-vas/Godot_TestSuite', 'nick-vas/hyperdot')
        $target = Join-Path $workflows 'hyperdot.yml'
        if ($old.Name -eq 'godot-ci.yml' -and -not (Test-Path -LiteralPath $target)) {
            Move-Item -LiteralPath $old.FullName -Destination $target
            Write-InitStep updated '.github/workflows/godot-ci.yml is now hyperdot.yml and calls nick-vas/hyperdot'
        } else {
            Write-InitStep updated ".github/workflows/$($old.Name) calls nick-vas/hyperdot"
        }
    }
    $existing = @(Get-KitWorkflowFiles $root)      # under either name: one left under its old name (see above) still counts, so no third copy is written
    if ($existing) { Write-InitStep skipped "CI workflow: $($existing[0].Name) already calls the kit"; return }
    $file = Join-Path $workflows 'hyperdot.yml'
    if (Test-Path -LiteralPath $file) { Write-InitStep skipped 'CI workflow: .github/workflows/hyperdot.yml exists'; return }
    $relative = [System.IO.Path]::GetRelativePath($root, $ProjectDir) -replace '\\', '/'
    $projectInput = if ($relative -ne '.') { "`n      project: $relative" } else { '' }
    New-Item -ItemType Directory -Force $workflows | Out-Null
    Set-Content -LiteralPath $file -Encoding utf8 -Value @"
# Runs Hyperdot's checks on a GitHub Linux runner: https://github.com/nick-vas/hyperdot
# @v1 follows the kit's releases; move to another tag or commit on purpose, in a commit of its own.
name: Godot

# Each run uses the account's Actions minutes when the repository is private. A change to documents or the plan alone
# starts no run. A push to main still runs: it checks the merge, and it saves the caches (Godot, templates, the import)
# that pull requests read. If branch protection requires this check, a skipped pull request waits for it forever:
# remove paths-ignore under pull_request, or do not require the check (https://github.com/nick-vas/hyperdot/blob/main/docs/usage.md).
on:
  push:
    branches: [main]
    paths-ignore:
      - 'docs/**'
      - 'plan/**'
      - '**/*.md'
      - '.gitignore'
  pull_request:
    paths-ignore:
      - 'docs/**'
      - 'plan/**'
      - '**/*.md'
      - '.gitignore'
  workflow_dispatch:

concurrency:
  group: godot-`${{ github.ref }}
  cancel-in-progress: true

jobs:
  godot:
    permissions:
      contents: read
      pull-requests: write   # for the test summary comment on pull requests
    uses: nick-vas/hyperdot/.github/workflows/godot.yml@v1
    with:$projectInput
      coverage: true
"@
    Write-InitStep added ".github/workflows/hyperdot.yml (tests on pull requests and pushes to main, except changes to documents or the plan alone)"
}

# init -Promo: the weekly marketing brief. The caller of the kit's promo.yml, which must grant the permissions itself (a reusable
# workflow cannot raise them), and docs/promo.json, the brief's own settings (AI drafts off). Adds only, like the rest of init.
function New-PromoWorkflow($Info) {
    $settingsPath = Get-PromoSettingsPath $Info
    if (Test-Path -LiteralPath $settingsPath) { Write-InitStep skipped 'docs/promo.json exists' }
    else {
        New-Item -ItemType Directory -Force (Split-Path $settingsPath) | Out-Null
        Set-Content -LiteralPath $settingsPath -Encoding utf8 -Value ((New-PromoSettings) | ConvertTo-Json -Depth 5)
        Write-InitStep added 'docs/promo.json (the brief''s channels and hashtags; "ai": true rewords the drafts with GitHub Models)'
    }
    $root = Get-GitRoot $Info.ProjectDir
    if (-not $root) { Write-InitStep skipped 'promo workflow: not a git repository'; return }
    $workflows = Join-Path $root '.github/workflows'
    $existing = @(Get-ChildItem -LiteralPath $workflows -File -ErrorAction SilentlyContinue | Where-Object { $_.Extension -in '.yml', '.yaml' } |
            Where-Object { (Get-Content -LiteralPath $_.FullName -Raw) -match 'hyperdot/\.github/workflows/promo\.yml' })
    if ($existing.Count) { Write-InitStep skipped "promo workflow: $($existing[0].Name) already calls it"; return }
    $file = Join-Path $workflows 'hyperdot-promo.yml'
    if (Test-Path -LiteralPath $file) { Write-InitStep skipped 'promo workflow: .github/workflows/hyperdot-promo.yml exists'; return }
    $relative = [System.IO.Path]::GetRelativePath($root, $Info.ProjectDir) -replace '\\', '/'
    $projectInput = if ($relative -ne '.') { "`n      project: $relative" } else { '' }
    New-Item -ItemType Directory -Force $workflows | Out-Null
    Set-Content -LiteralPath $file -Encoding utf8 -Value @"
# The weekly marketing brief (Hyperdot's promo): an issue labelled marketing-brief with the player-facing changes that are in a
# build whose tests passed, a checklist and drafts to post. Changes reach it through a trailer in the commit message, or in the
# pull request's description for a squash merge:
#   Marketing: Meteor storms can now rain down on your base
#   Marketing-Priority: high          (optional: high, normal or low)
#   Marketing-Visual: yes             (optional: worth a clip)
#   Marketing-Scene: res://levels/storm.tscn   (optional: with clips below, a first clip of it; Marketing-Args, Marketing-Seconds)
# Settings: docs/promo.json. Without clips it never runs Godot: about a minute of Actions time a week. https://github.com/nick-vas/hyperdot
name: Marketing brief

on:
  schedule:
    - cron: '17 8 * * 1'   # Mondays 08:17 UTC
  workflow_dispatch:
    inputs:
      dry-run:
        description: Write the brief to the run summary only (no issue, no tag)
        type: boolean
        default: true

# One brief at a time: two overlapping runs would both open brief N.
concurrency:
  group: hyperdot-promo
  cancel-in-progress: false

jobs:
  promo:
    # A real run by hand only from the default branch: from another branch it would ship and tag that branch's commits.
    if: github.event_name == 'schedule' || inputs.dry-run || github.ref_name == github.event.repository.default_branch
    permissions:
      contents: write        # the mkt/N tag that marks where the next brief starts
      issues: write          # the brief, and closing last week's
      checks: read           # the gate: which commits passed the tests
      pull-requests: read    # trailers in squash-merge descriptions, and the gate for merge commits
      models: read           # only used when docs/promo.json has "ai": true
    uses: nick-vas/hyperdot/.github/workflows/promo.yml@v1
    with:$projectInput
      dry-run: `${{ github.event_name == 'workflow_dispatch' && inputs.dry-run }}
      clips: false   # true: also record a clip of each change with a Marketing-Scene: trailer (sets Godot up: several minutes a week)
"@
    Write-InitStep added '.github/workflows/hyperdot-promo.yml (the weekly marketing brief, Mondays; run it by hand for a dry run)'
}

function Add-CSharpTestSetup([string]$ProjectDir, $Info) {
    $csproj = (Get-ChildItem -LiteralPath $ProjectDir -File -Filter '*.csproj' | Select-Object -First 1).FullName
    $content = Get-Content -LiteralPath $csproj -Raw
    if ($content -match 'gdUnit4\.test\.adapter') {
        Write-InitStep skipped "$(Split-Path $csproj -Leaf) already references gdUnit4Net"
    } elseif ($content -match 'Microsoft\.NET\.Test\.Sdk') {
        # Another framework is set up in the game project; a gdUnit4 starter test would not compile there.
        Write-InitStep skipped "$(Split-Path $csproj -Leaf) already has its own test setup; no starter test added"
        return
    } elseif ($Info.GodotVersion -notmatch '^4\.([4-9]|\d{2,})') {
        Write-InitStep skipped "gdUnit4Net needs Godot 4.4 or newer (project uses $($Info.GodotVersion))"
        return
    } else {
        $block = @'
  <!-- Hyperdot: test packages and test code stay out of release exports. -->
  <PropertyGroup>
    <IncludeTests Condition="'$(Configuration)' != 'ExportRelease'">true</IncludeTests>
  </PropertyGroup>
  <ItemGroup Condition="'$(IncludeTests)' == 'true'">
    <PackageReference Include="Microsoft.NET.Test.Sdk" Version="18.11.0" />
    <PackageReference Include="gdUnit4.api" Version="5.0.0" />
    <PackageReference Include="gdUnit4.test.adapter" Version="3.0.0" />
    <PackageReference Include="coverlet.collector" Version="10.1.0" />
  </ItemGroup>
  <ItemGroup Condition="'$(IncludeTests)' != 'true'">
    <Compile Remove="test/**;gdunit4_testadapter*/**" />
  </ItemGroup>
'@
        $newline = if ($content.Contains("`r`n")) { "`r`n" } else { "`n" }
        $content = $content -replace '</Project>\s*$', { ($block -replace "`r?`n", { $newline }) + "</Project>$newline" }
        Set-Content -LiteralPath $csproj -Value $content -NoNewline -Encoding utf8
        Write-InitStep updated "$(Split-Path $csproj -Leaf): gdUnit4Net test packages (excluded from release exports)"
    }

    $testFile = Join-Path $ProjectDir 'test/ExampleTest.cs'
    if (Test-Path -LiteralPath $testFile) { Write-InitStep skipped 'test/ExampleTest.cs exists'; return }
    $mainScene = if ((Get-Content -LiteralPath (Join-Path $ProjectDir 'project.godot') -Raw) -match '(?m)^run/main_scene="(?<s>[^"]+)"') { $Matches.s } else { '' }
    $sceneTest = if ($mainScene) { @"

    // Loads the main scene in a real (headless) Godot and plays a few frames.
    [TestCase]
    [RequireGodotRuntime]
    public async Task MainSceneRuns()
    {
        using ISceneRunner runner = ISceneRunner.Load("$mainScene");
        await runner.SimulateFrames(30);
        AssertThat(runner.Scene()).IsNotNull();
    }
"@ } else { '' }
    New-Item -ItemType Directory -Force (Split-Path $testFile) | Out-Null
    Set-Content -LiteralPath $testFile -Encoding utf8 -Value @"
namespace Tests;

using System.Threading.Tasks;
using GdUnit4;
using static GdUnit4.Assertions;

// Starter tests from Hyperdot. Plain tests run without the engine (fast); mark tests that
// need Godot with [RequireGodotRuntime]. Run them all with: pwsh ci/godot/hyperdot.ps1
[TestSuite]
public class ExampleTest
{
    [TestCase]
    public void Arithmetic() => AssertThat(2 + 2).IsEqual(4);
$sceneTest}
"@
    Write-InitStep added 'test/ExampleTest.cs (gdUnit4Net starter tests)'
}

function Add-GutStarterTest([string]$ProjectDir) {
    if (@(Get-GutTestFiles $ProjectDir).Count -gt 0) { Write-InitStep skipped 'GUT tests already exist'; return }
    $testFile = Join-Path $ProjectDir 'test/test_example.gd'
    # A file of that name that is not a GutTest (another framework, or extends GUT's script by path) is still the user's.
    if (Test-Path -LiteralPath $testFile) { Write-InitStep skipped 'test/test_example.gd exists'; return }
    $mainScene = if ((Get-Content -LiteralPath (Join-Path $ProjectDir 'project.godot') -Raw) -match '(?m)^run/main_scene="(?<s>[^"]+)"') { $Matches.s } else { '' }
    $sceneTest = if ($mainScene) { @"


func test_main_scene_loads():
	var scene = add_child_autofree(load("$mainScene").instantiate())
	await wait_process_frames(30)
	assert_not_null(scene)
"@ } else { '' }
    New-Item -ItemType Directory -Force (Split-Path $testFile) | Out-Null
    Set-Content -LiteralPath $testFile -Encoding utf8 -Value @"
extends GutTest
## Starter tests from Hyperdot. GUT runs every test_*.gd; the kit installs GUT itself.
## Run them with: pwsh ci/godot/hyperdot.ps1


func test_arithmetic():
	assert_eq(2 + 2, 4)$sceneTest
"@
    Write-InitStep added 'test/test_example.gd (GUT starter tests)'
}

function Add-ExportExcludes([string]$ProjectDir, [string[]]$Patterns) {
    $file = Join-Path $ProjectDir 'export_presets.cfg'
    if (-not (Test-Path -LiteralPath $file)) { Write-InitStep skipped 'export presets: none yet'; return }
    $lines = Get-Content -LiteralPath $file
    $changed = $false
    for ($i = 0; $i -lt $lines.Count; $i++) {
        if ($lines[$i] -match '^exclude_filter="(?<f>.*)"$') {
            $current = @($Matches.f -split ',' | ForEach-Object { $_.Trim() } | Where-Object { $_ })
            $add = @($Patterns | Where-Object { $_ -notin $current })
            if ($add) { $lines[$i] = 'exclude_filter="' + (($current + $add) -join ', ') + '"'; $changed = $true }
        }
    }
    if ($changed) {
        Set-Content -LiteralPath $file -Value $lines -Encoding utf8
        Write-InitStep updated "export presets exclude $($Patterns -join ', ')"
    } else {
        Write-InitStep skipped 'export presets already exclude test files'
    }
}

function Set-SolutionDirectory([string]$ProjectDir, [string]$Solution) {
    if (-not $Solution -or $Solution -like '*.csproj' -or (Split-Path $Solution) -eq $ProjectDir) { return }
    $file = Join-Path $ProjectDir 'project.godot'
    $content = Get-Content -LiteralPath $file -Raw
    if ($content -match '(?m)^project/solution_directory=') { return }
    $relative = [System.IO.Path]::GetRelativePath($ProjectDir, (Split-Path $Solution)) -replace '\\', '/'
    $entry = "project/solution_directory=""$relative"""
    $content = if ($content -match '(?m)^\[dotnet\]\s*$') { $content -replace '(?m)^\[dotnet\]\s*$', { "[dotnet]`n`n$entry" } }
        else { $content.TrimEnd() + "`n`n[dotnet]`n`n$entry`n" }
    Set-Content -LiteralPath $file -Value $content -NoNewline -Encoding utf8
    Write-InitStep updated "project.godot: solution_directory=$relative (exports need it to find your C# code)"
}

function Initialize-Project($Info) {
    $project = $Info.ProjectDir
    $isCSharp = @(Get-ChildItem -LiteralPath $project -File -Filter '*.csproj').Count -gt 0
    Write-CiLog "Setting up $project"
    $ignore = @('.godot/', 'test-results/', 'build/', 'screenshots/')
    $excludes = @('test/*')
    if ($isCSharp) {
        $ignore += 'gdunit4_testadapter*/'; $excludes += 'gdunit4_testadapter*/*'
        Add-CSharpTestSetup $project $Info
        Set-SolutionDirectory $project $Info.Solution
    } else {
        $ignore += 'addons/gut/'; $excludes += 'addons/gut/*'
        Add-GutStarterTest $project
    }
    Add-GitignoreEntries $project $ignore
    Add-ExportExcludes $project $excludes
    New-CiWorkflow $project
}

# init -Agents: AGENTS.md (CLAUDE.md imports it) and docs/kit-notes.md, and the plugin that supplies the skills, the subagents and the hooks, so
# nothing is copied into the game and nothing goes stale there. -CopySkills copies the skills and subagents instead, for a host that loads no
# plugins, and never into a game that already enables the plugin. Adds only.
function Add-AgentFiles($Info, [string]$SuiteScript, [bool]$Copy, [string]$PluginSource, [bool]$SourceChosen) {
    $root = Get-GitRoot $Info.ProjectDir
    $root = $root ? $root : $Info.ProjectDir
    $suiteRoot = Split-Path (Split-Path (Split-Path $PSScriptRoot))
    # Inside the game repo (a submodule): a relative path, which works on every clone. Outside it (a separate clone of the
    # kit, so it never ships with the game): the HYPERDOT_KIT variable, which each machine points at its own clone. This
    # machine's path would be wrong on every other one (issue 314), so it goes only to .claude/settings.local.json, the
    # machine's own file, and to the console.
    $relative = [System.IO.Path]::GetRelativePath($root, $SuiteScript)
    $outside = $relative.StartsWith('..') -or [System.IO.Path]::IsPathRooted($relative)
    $suitePath = if ($outside) { '"$HYPERDOT_KIT/ci/godot/hyperdot.ps1"' } else { $relative -replace '\\', '/' }
    if (-not $outside -and $suitePath -match '\s') { $suitePath = "`"$suitePath`"" }
    $kitLocation = if ($outside) { $script:KitLocationText } else { '' }
    $agents = Join-Path $root 'AGENTS.md'
    if (Test-Path -LiteralPath $agents) { Write-InitStep skipped 'AGENTS.md exists' }
    else {
        $text = (Get-Content -LiteralPath (Join-Path $PSScriptRoot '../templates/AGENTS.md') -Raw).Replace('{{SUITE}}', $suitePath)
        $text = if ($kitLocation) { $text.Replace('{{KIT_LOCATION}}', $kitLocation) } else { $text -replace '\{\{KIT_LOCATION\}\}\r?\n\r?\n', '' }
        Set-Content -LiteralPath $agents -Value $text -NoNewline -Encoding utf8
        Write-InitStep added 'AGENTS.md'
    }
    if ($outside) { Set-KitLocationSetting $root $suiteRoot }
    $claude = Join-Path $root 'CLAUDE.md'
    if (Test-Path -LiteralPath $claude) { Write-InitStep skipped 'CLAUDE.md exists (add "@AGENTS.md" to it)' }
    else { Set-Content -LiteralPath $claude -Value '@AGENTS.md' -Encoding utf8; Write-InitStep added 'CLAUDE.md (imports AGENTS.md)' }
    # docs/kit-notes.md: one line each time the kit got in the way in this game, for /retro and the weekly review to read.
    $notes = Join-Path $root 'docs/kit-notes.md'
    if (Test-Path -LiteralPath $notes) { Write-InitStep skipped 'docs/kit-notes.md exists' }
    else {
        New-Item -ItemType Directory -Force (Split-Path $notes) | Out-Null
        Copy-Item -LiteralPath (Join-Path $PSScriptRoot '../templates/kit-notes.md') -Destination $notes
        Write-InitStep added 'docs/kit-notes.md (one line each time the kit gets in the way)'
    }
    # docs/kit-help.md: not written any more. It was a copy of the kit's text that went stale in the game; `help` and /kit write the
    # same page to .godot/kit-help.md, which no repository tracks. A copy an older init left is named, so it can be deleted.
    if (Test-Path -LiteralPath (Join-Path $root 'docs/kit-help.md')) {
        Write-InitStep skipped 'docs/kit-help.md is a copy an older init wrote and goes stale: delete it; `help` and /kit write .godot/kit-help.md'
    }
    # With the plugin, skills, subagents and hooks come from the kit itself and stay up to date; copies would only duplicate them.
    if (-not $Copy) { Add-PluginSettings $root $suiteRoot $PluginSource $SourceChosen; return }
    if (Test-HyperdotPluginEnabled $root) {
        Write-InitStep skipped 'no skills or subagents copied: the game already enables the hyperdot plugin, which supplies them (a copy would load twice and go stale)'
        return
    }
    # Skills and agents name the kit as ${CLAUDE_PLUGIN_ROOT}/ci/godot/hyperdot.ps1, which Claude Code fills in for the
    # plugin. Copies get this machine's path instead.
    $placeholder = '${CLAUDE_PLUGIN_ROOT}/ci/godot/hyperdot.ps1'
    # Other kit files (templates) are named from the kit's folder.
    $rootPlaceholder = '${CLAUDE_PLUGIN_ROOT}'
    $kitRoot = if ($outside) { '$HYPERDOT_KIT' } else { $suiteRoot -replace '\\', '/' }
    $fill = { param([string]$Text) $Text.Replace($placeholder, $suitePath).Replace($rootPlaceholder, $kitRoot) }
    foreach ($skill in Get-ChildItem -LiteralPath (Join-Path $suiteRoot '.agents/skills') -Directory) {
        $copied = @(foreach ($base in '.agents/skills', '.claude/skills') {
            $target = Join-Path $root "$base/$($skill.Name)"
            if (Test-Path -LiteralPath $target) { continue }
            New-Item -ItemType Directory -Force (Split-Path $target) | Out-Null
            Copy-Item -LiteralPath $skill.FullName -Destination $target -Recurse
            foreach ($md in Get-ChildItem -LiteralPath $target -Recurse -File -Filter '*.md') {
                $text = Get-Content -LiteralPath $md.FullName -Raw
                if ($text.Contains($rootPlaceholder)) { Set-Content -LiteralPath $md.FullName -Value (& $fill $text) -NoNewline -Encoding utf8 }
            }
            $base
        })
        if ($copied.Count -gt 0) { Write-InitStep added "skill $($skill.Name) ($($copied -join ' and '))" }
        else { Write-InitStep skipped "skill $($skill.Name) is already there" }
    }
    foreach ($agent in Get-ChildItem -LiteralPath (Join-Path $suiteRoot 'agents') -File -Filter '*.md') {
        $target = Join-Path $root ".claude/agents/$($agent.Name)"
        if (Test-Path -LiteralPath $target) { Write-InitStep skipped "agent $($agent.BaseName) is already there"; continue }
        New-Item -ItemType Directory -Force (Split-Path $target) | Out-Null
        Set-Content -LiteralPath $target -Value (& $fill (Get-Content -LiteralPath $agent.FullName -Raw)) -NoNewline -Encoding utf8
        Write-InitStep added "agent $($agent.BaseName) (.claude/agents)"
    }
}

# The kit outside the game: HYPERDOT_KIT for Claude Code on this machine, in .claude/settings.local.json (the machine's own
# file, kept out of git), so the commands AGENTS.md gives work here without a shell profile. A value already there is left.
function Set-KitLocationSetting([string]$Root, [string]$KitRoot) {
    $kit = [System.IO.Path]::GetFullPath($KitRoot) -replace '\\', '/'
    $file = Join-Path $Root '.claude/settings.local.json'
    $settings = [ordered]@{}
    if (Test-Path -LiteralPath $file) {
        try { $settings = Get-Content -LiteralPath $file -Raw | ConvertFrom-Json -AsHashtable }
        catch { Write-InitStep skipped ".claude/settings.local.json is not valid JSON, so HYPERDOT_KIT was not added: add `"env`": { `"HYPERDOT_KIT`": `"$kit`" }"; return }
        if ($settings -isnot [System.Collections.IDictionary]) { Write-InitStep skipped '.claude/settings.local.json is not an object, so HYPERDOT_KIT was not added'; return }
    }
    if (-not $settings.Contains('env') -or $settings['env'] -isnot [System.Collections.IDictionary]) { $settings['env'] = [ordered]@{} }
    $current = $settings['env']['HYPERDOT_KIT']
    if ($current) {
        Write-InitStep skipped ".claude/settings.local.json already sets HYPERDOT_KIT ($current)$(if ($current -ne $kit) { "; this kit is $kit" })"
    } else {
        $settings['env']['HYPERDOT_KIT'] = $kit
        New-Item -ItemType Directory -Force (Split-Path $file) | Out-Null
        Set-Content -LiteralPath $file -Value ($settings | ConvertTo-Json -Depth 10) -Encoding utf8
        Write-InitStep updated ".claude/settings.local.json: HYPERDOT_KIT=$kit (this machine only; Claude Code reads it on its next start)"
    }
    Add-GitignoreEntries $Root @('.claude/settings.local.json')
    if ($env:HYPERDOT_KIT -ne $kit) { Write-CiLog "For terminals outside Claude Code, set HYPERDOT_KIT=$kit in your shell profile: AGENTS.md runs the kit from it" }
}

# The GitHub repository the plugin is fetched from when -PluginSource is github: this kit's own, or a fork named in HYPERDOT_KIT_REPO.
function Get-KitRepository {
    if ($env:HYPERDOT_KIT_REPO -match '\A[A-Za-z0-9_.-]+/[A-Za-z0-9_.-]+\z') { return $env:HYPERDOT_KIT_REPO }
    return 'nick-vas/hyperdot'
}

# init -Agents: the game's .claude/settings.json registers this kit as a plugin marketplace and enables the plugin, so Claude Code loads
# the skills, the subagents and the hooks from it. github: from the kit's GitHub repository (any machine, cloud sessions; /plugin update
# brings changes). local: from the folder this kit runs from, loaded in place (a git pull in the kit updates every game). Adds only; an
# existing file is backed up first. A game that already enables the plugin from the other source keeps it unless -PluginSource is given.
function Add-PluginSettings([string]$Root, [string]$SuiteRoot, [string]$Source = 'github', [bool]$SourceChosen = $false) {
    $file = Join-Path $Root '.claude/settings.json'
    $settings = if (Test-Path -LiteralPath $file) { Get-Content -LiteralPath $file -Raw | ConvertFrom-Json -AsHashtable } else { [ordered]@{} }
    if (-not $settings) { $settings = [ordered]@{} }
    $marketplaces = if ($settings.Contains('extraKnownMarketplaces')) { $settings['extraKnownMarketplaces'] } else { [ordered]@{} }
    $enabled = if ($settings.Contains('enabledPlugins')) { $settings['enabledPlugins'] } else { [ordered]@{} }
    # Before Hyperdot the plugin was godot-agent-kit: its entries are replaced once.
    $renamed = $marketplaces.Contains('godot-agent-kit') -or $enabled.Contains('godot-agent-kit@godot-agent-kit')
    $marketplaces.Remove('godot-agent-kit'); $enabled.Remove('godot-agent-kit@godot-agent-kit')
    $wanted = if ($Source -eq 'github') { [ordered]@{ source = 'github'; repo = (Get-KitRepository) } }
              else { [ordered]@{ source = 'directory'; path = ($SuiteRoot -replace '\\', '/') } }
    if (-not $renamed -and $marketplaces.Contains('hyperdot') -and $enabled.Contains('hyperdot@hyperdot')) {
        $have = $marketplaces['hyperdot']
        $haveSource = if ($have -is [System.Collections.IDictionary] -and $have.Contains('source') -and $have['source'] -is [System.Collections.IDictionary]) { $have['source'] } else { @{} }
        $same = $haveSource.Contains('source') -and $haveSource['source'] -eq $wanted['source'] -and
            (($wanted['source'] -eq 'github' -and $haveSource['repo'] -eq $wanted['repo']) -or $wanted['source'] -eq 'directory')
        if ($same -or -not $SourceChosen) {
            $kind = if ($haveSource.Contains('source')) { $haveSource['source'] } else { 'an unknown source' }
            Write-InitStep skipped ".claude/settings.json already enables the hyperdot plugin (from $kind$(if (-not $same) { "; -PluginSource $Source switches it" }))"
            return
        }
    }
    if (Test-Path -LiteralPath $file) { Copy-Item -LiteralPath $file "$file.bak" -Force }
    $marketplaces['hyperdot'] = [ordered]@{ source = $wanted }
    $enabled['hyperdot@hyperdot'] = $true
    $settings['extraKnownMarketplaces'] = $marketplaces
    $settings['enabledPlugins'] = $enabled
    New-Item -ItemType Directory -Force (Split-Path $file) | Out-Null
    $settings | ConvertTo-Json -Depth 8 | Set-Content -LiteralPath $file -Encoding utf8
    $from = if ($Source -eq 'github') { "GitHub ($($wanted['repo']))" } else { $SuiteRoot }
    Write-InitStep updated ".claude/settings.json: hyperdot plugin from $from (Claude Code asks to install it on the next start)"
}

# aseprite-mcp (diivi/aseprite-mcp, MIT) at a reviewed commit. It has no release and no lock uvx reads: unpinned, its
# "mcp[cli]>=1.6.0" resolved to MCP SDK 2.x, which renamed the FastMCP it imports, and its locked 1.6.0 fails to import with
# today's pydantic; 1.30.0 starts it with all 123 tools (measured with uvx 0.8 on 2026-10-22).
$script:AsepriteMcpSource = 'git+https://github.com/diivi/aseprite-mcp@a89b205bed31930ee141edf319e78c71ef16bba6'
$script:AsepriteMcpSdk = 'mcp[cli]==1.30.0'

# The Aseprite program from a path to it or to its install folder (C:\Program Files\Aseprite, Steam's common\Aseprite,
# /Applications/Aseprite.app), as a full path; stops with aseprite-not-found when there is none.
function Resolve-AsepritePath([string]$Path) {
    $candidates = @($Path)
    if (Test-Path -LiteralPath $Path -PathType Container) {
        $candidates = @('Aseprite.exe', 'aseprite', 'Contents/MacOS/aseprite', 'Aseprite.app/Contents/MacOS/aseprite' |
            ForEach-Object { Join-Path $Path $_ })
    }
    foreach ($candidate in $candidates) {
        if (Test-Path -LiteralPath $candidate -PathType Leaf) { return (Resolve-Path -LiteralPath $candidate).Path }
    }
    Stop-GodotCi "No Aseprite program at $Path (give Aseprite.exe, the aseprite binary, or the folder that holds it)" 'aseprite-not-found'
}

# init -Mcp / -McpDiagnostics / -McpAseprite: registers MCP servers for the project in .mcp.json (adds only; a changed file is
# backed up). -Mcp godot-mcp is the editor bridge; -McpDiagnostics adds minimal-godot-mcp (GDScript diagnostics and the running
# game's console, through Godot's own language server and debug adapter, so no addon); -McpAseprite adds aseprite-mcp, which
# drives Aseprite in batch mode to draw and export pixel art. The bridge's addon still has to be installed and enabled in the
# editor, which needs Node and the editor, so those steps are printed and not run.
function Add-McpConfig($Info, [string]$Server, [bool]$Diagnostics, [string]$Aseprite) {
    $root = Get-GitRoot $Info.ProjectDir
    $root = $root ? $root : $Info.ProjectDir
    if ($Server -eq 'godot-ai') {
        Write-InitStep skipped 'godot-ai configures its own clients: install the addon, enable it, press Configure in the Godot AI dock'
        Write-Console '           https://github.com/hi-godot/godot-ai (Godot 4.7+, needs uv)'
    }
    $wanted = [ordered]@{}
    if ($Server -eq 'godot-mcp') {
        $wanted['godot-mcp'] = [ordered]@{ command = 'npx'; args = @('-y', '@satelliteoflove/godot-mcp@4.1.11') }
    }
    if ($Diagnostics) {
        $wanted['minimal-godot-mcp'] = [ordered]@{ command = 'npx'; args = @('-y', '@ryanmazzolini/minimal-godot-mcp@0.1.6') }
    }
    if ($Aseprite) {
        $wanted['aseprite'] = [ordered]@{
            command = 'uvx'
            args    = @('--from', $script:AsepriteMcpSource, '--with', $script:AsepriteMcpSdk, 'python', '-m', 'aseprite_mcp')
            env     = [ordered]@{ ASEPRITE_PATH = (Resolve-AsepritePath $Aseprite) }
        }
    }
    if ($wanted.Count -eq 0) { return }

    $file = Join-Path $root '.mcp.json'
    $config = [ordered]@{ mcpServers = [ordered]@{} }
    if (Test-Path -LiteralPath $file) {
        try { $config = Get-Content -LiteralPath $file -Raw | ConvertFrom-Json -AsHashtable -Depth 10 }
        catch { Stop-GodotCi ".mcp.json is not valid JSON; fix it or remove it first ($($_.Exception.Message))" 'invalid-mcp-config' }
        if (-not $config.Contains('mcpServers')) { $config['mcpServers'] = [ordered]@{} }
    }
    $changed = $false
    foreach ($name in $wanted.Keys) {
        if ($config['mcpServers'].Contains($name)) { Write-InitStep skipped ".mcp.json already has $name"; continue }
        if (-not $changed -and (Test-Path -LiteralPath $file)) { Copy-Item -LiteralPath $file -Destination "$file.bak" -Force }
        $config['mcpServers'][$name] = $wanted[$name]
        $changed = $true
        Write-InitStep added ".mcp.json: $name"
    }
    if ($changed) { $config | ConvertTo-Json -Depth 10 | Set-Content -LiteralPath $file -Encoding utf8 }

    if ($wanted.Contains('godot-mcp')) {
        Write-Console "           next: npx @satelliteoflove/godot-mcp@4.1.11 --install-addon `"$($Info.ProjectDir)`""
        Write-Console '           then enable it: Project > Project Settings > Plugins > Godot MCP, and restart your agent'
    }
    if ($wanted.Contains('aseprite')) {
        Write-Console "           aseprite runs $($wanted['aseprite'].env.ASEPRITE_PATH) in batch mode; restart your agent to load it."
        if (-not (Get-Command uvx -ErrorAction SilentlyContinue)) {
            Write-Console '           It needs uv (uvx), which is not on PATH: winget install astral-sh.uv, or https://docs.astral.sh/uv/ (uv fetches Python 3.13 itself).'
        }
        Write-Console '           Its run_lua_script tool runs any Lua the agent writes, with your rights: keep the agent asking before it calls it.'
    }
    if ($wanted.Contains('minimal-godot-mcp')) {
        Write-Console '           minimal-godot-mcp needs Node 22+ and the editor open on this project (its language server is on by default).'
        Write-Console ('           It checks GDScript only; the console tool needs a running scene (F5). C# is checked by: ' + (Format-KitCommand 'build'))
    }
}
