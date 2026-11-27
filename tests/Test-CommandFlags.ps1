#!/usr/bin/env pwsh
# Self-test of the table of which command takes which flag ($KitCommandFlags in ci/godot/lib/Common.ps1), which
# hyperdot.ps1 uses to refuse a flag given to a command that does not read it. Without Godot, in about two seconds:
#   1. the table and the script agree: every parameter is in it, every name in it is a parameter, every command has a row;
#   2. no command's own code reads a parameter its row leaves out (its switch branch, an `if ($Command -eq ...)` block,
#      and the script's own functions they call), so the check never refuses a flag a command uses;
#   3. every `hyperdot.ps1 <command> -Flag` (or `-File $ci <command>`) written in the skills, docs, workflows, templates,
#      evals and tests passes it, but for a test's own refusal case (it checks invalid-arguments in the next lines);
#   4. a flag given to the wrong command is refused as invalid-arguments, naming the commands that take it.
Set-StrictMode -Version 3.0
$ErrorActionPreference = 'Stop'
$root = Split-Path $PSScriptRoot
$kit = Join-Path $root 'ci/godot/hyperdot.ps1'
$failures = [System.Collections.Generic.List[string]]::new()
. (Join-Path $root 'ci/godot/lib/Common.ps1')

$ast = [System.Management.Automation.Language.Parser]::ParseFile($kit, [ref]$null, [ref]$null)
$params = @($ast.ParamBlock.Parameters | ForEach-Object { $_.Name.VariablePath.UserPath })
$commands = @((Get-KitParameterSets $ast.ParamBlock)['Command'])
$listed = @($script:KitAnyCommandFlags) + @($script:KitCommandFlags.Values | ForEach-Object { $_ })

# 1. The table and the parameter block.
foreach ($p in $params) { if ($p -notin $listed) { $failures.Add("-$p is in no command's row of `$KitCommandFlags") } }
foreach ($name in ($listed | Sort-Object -Unique)) { if ($name -notin $params) { $failures.Add("`$KitCommandFlags names $name, which is not a parameter of hyperdot.ps1") } }
foreach ($c in $commands) { if (-not $script:KitCommandFlags.Contains($c)) { $failures.Add("the command $c has no row in `$KitCommandFlags") } }
foreach ($c in $script:KitCommandFlags.Keys) { if ($c -notin $commands) { $failures.Add("`$KitCommandFlags has a row for $c, which is not a command") } }

# 2. What each command's code reads. The script's own functions are followed through the calls between them.
function Get-ParameterReads($Node) {
    return @($Node.FindAll({ $args[0] -is [System.Management.Automation.Language.VariableExpressionAst] }, $true) |
            ForEach-Object { $_.VariablePath.UserPath } | Where-Object { $_ -in $params } | Sort-Object -Unique)
}
$functions = @{}
foreach ($f in $ast.FindAll({ $args[0] -is [System.Management.Automation.Language.FunctionDefinitionAst] }, $false)) { $functions[$f.Name] = $f }
function Get-CodeReads($Node) {
    $reads = [System.Collections.Generic.HashSet[string]]::new([StringComparer]::OrdinalIgnoreCase)
    $queue = [System.Collections.Generic.Queue[object]]::new(); $queue.Enqueue($Node)
    $seen = [System.Collections.Generic.HashSet[string]]::new()
    while ($queue.Count) {
        $n = $queue.Dequeue()
        foreach ($r in Get-ParameterReads $n) { [void]$reads.Add($r) }
        foreach ($call in $n.FindAll({ $args[0] -is [System.Management.Automation.Language.CommandAst] }, $true)) {
            $name = $call.GetCommandName()
            if ($name -and $functions.ContainsKey($name) -and $seen.Add($name)) { $queue.Enqueue($functions[$name].Body) }
        }
    }
    return @($reads)
}
$byCommand = @{}
foreach ($c in $commands) { $byCommand[$c] = [System.Collections.Generic.List[object]]::new() }
$switch = @($ast.FindAll({ $args[0] -is [System.Management.Automation.Language.SwitchStatementAst] -and $args[0].Condition.Extent.Text -match '^\(?\$Command\)?$' }, $false))
if ($switch.Count -ne 1) { $failures.Add("expected one switch (`$Command) in hyperdot.ps1, found $($switch.Count)") }
foreach ($clause in @($switch | ForEach-Object { $_.Clauses })) {
    $byCommand[$clause.Item1.Value].Add($clause.Item2)
}
# Top-level blocks that run for one command only: if ($Command -eq 'x') { ... }.
foreach ($st in $ast.EndBlock.Statements) {
    if ($st -isnot [System.Management.Automation.Language.IfStatementAst]) { continue }
    foreach ($clause in $st.Clauses) {
        if ($clause.Item1.Extent.Text -match "^\`$Command -eq '(\w+)'$" -and $byCommand.ContainsKey($Matches[1])) { $byCommand[$Matches[1]].Add($clause.Item2) }
    }
}
foreach ($c in $commands) {
    $own = @($script:KitAnyCommandFlags) + @($script:KitCommandFlags[$c])
    $reads = @(foreach ($block in $byCommand[$c]) { Get-CodeReads $block })
    foreach ($r in ($reads | Sort-Object -Unique)) { if ($r -notin $own) { $failures.Add("$c's code reads -$r, but its row in `$KitCommandFlags leaves it out: it would be refused") } }
}
if (@($byCommand['soak']).Count -eq 0 -or @(Get-CodeReads $byCommand['soak'][0]) -notcontains 'MaxMetricGrowth') { $failures.Add('the code reads were not found (soak should read -MaxMetricGrowth)') }

# 2b. No function of the script assigns a variable named like a parameter: PowerShell names ignore case, so a local $run
# hides -Run from the rest of that function (Invoke-ExportPresets launched every build, -Run given or not).
foreach ($f in $functions.Values) {
    foreach ($assign in $f.Body.FindAll({ $args[0] -is [System.Management.Automation.Language.AssignmentStatementAst] }, $true)) {
        $target = $assign.Left
        if ($target -is [System.Management.Automation.Language.ConvertExpressionAst]) { $target = $target.Child }
        if ($target -is [System.Management.Automation.Language.VariableExpressionAst] -and -not $target.VariablePath.IsScript -and $target.VariablePath.UserPath -in $params) {
            $failures.Add("$($f.Name) assigns `$$($target.VariablePath.UserPath) (line $($assign.Extent.StartLineNumber)), which hides the parameter -$($target.VariablePath.UserPath) in it")
        }
    }
    foreach ($loop in $f.Body.FindAll({ $args[0] -is [System.Management.Automation.Language.ForEachStatementAst] }, $true)) {
        if ($loop.Variable.VariablePath.UserPath -in $params) { $failures.Add("$($f.Name) loops with `$$($loop.Variable.VariablePath.UserPath) (line $($loop.Extent.StartLineNumber)), which hides the parameter of that name") }
    }
}

# 3. Every written invocation: hyperdot.ps1 <command> followed by flags on the same line.
$flagToVariable = @{}
foreach ($p in $ast.ParamBlock.Parameters) { $flagToVariable[(Get-KitFlagName $p).ToLowerInvariant()] = $p.Name.VariablePath.UserPath; $flagToVariable[$p.Name.VariablePath.UserPath.ToLowerInvariant()] = $p.Name.VariablePath.UserPath }
$scanned = 0
$files = @(git -C $root ls-files -- '.agents' 'agents' 'docs' '.github' 'ci/godot/templates' 'evals' 'tests' 'README.md' 'hooks' |
        Where-Object { $_ -match '\.(md|yml|yaml|ps1|json|sh)$' -and $_ -notmatch '^docs/coverage\.md$' })
foreach ($rel in $files) {
    $lines = [System.IO.File]::ReadAllLines((Join-Path $root $rel))
    for ($i = 0; $i -lt $lines.Length; $i++) {
        $line = $lines[$i]
        $lineNo = $i + 1
        # A test that gives a flag to the wrong command on purpose checks the refusal within the next three lines.
        $expectsRefusal = (@($lines[$i..([Math]::Min($i + 3, $lines.Length - 1))]) -join "`n") -match 'invalid-arguments|refused'
        foreach ($m in [regex]::Matches($line, '(?:hyperdot\.ps1[''"]?\)?|-File \$(?:ci|kit|cli|entry|script|hyperdot))\s+(?<cmd>[a-z]+)\b(?<rest>[^|;`]*)')) {
            $cmd = $m.Groups['cmd'].Value
            if ($cmd -notin $commands) { continue }
            $scanned++
            $own = @($script:KitAnyCommandFlags) + @($script:KitCommandFlags[$cmd])
            foreach ($f in [regex]::Matches($m.Groups['rest'].Value, '(?<![\w-])-(?<f>[A-Z][A-Za-z]+)')) {
                $variable = $flagToVariable[$f.Groups['f'].Value.ToLowerInvariant()]
                if ($variable -and $variable -notin $own -and -not $expectsRefusal) { $failures.Add("${rel}:${lineNo}: $cmd -$($f.Groups['f'].Value) would be refused ($($line.Trim()))") }
            }
        }
    }
}
if ($scanned -lt 100) { $failures.Add("only $scanned written invocations found; the scan is not reading the files") }

# 4. The refusal itself, in JSON.
function Invoke-KitJson([string[]]$Arguments) {
    $out = & pwsh -NoProfile -NonInteractive -File $kit @Arguments -Json 2>$null
    return ($out | Out-String | ConvertFrom-Json)
}
foreach ($case in @(
        @{ Args = @('soak', '-BudgetMs', '5'); Says = '-BudgetMs is for bench, deck, not soak' },
        @{ Args = @('detect', '-Clients', '5'); Says = '-Clients is for soak, not detect' },
        @{ Args = @('plan', '-Profile', 'jam', '-Do', 'status', '-Project', $root); Says = $null },
        @{ Args = @('status', '-Profile', 'jam'); Says = '-Profile is for plan, not status' },
        @{ Args = @('test', '-TimeoutSec', '5'); Says = 'HYPERDOT_TIMEOUT' })) {
    $r = Invoke-KitJson $case.Args
    if ($null -eq $case.Says) {
        if ($r.PSObject.Properties['error'] -and $r.error.code -eq 'invalid-arguments' -and $r.error.message -match 'is for') { $failures.Add("$($case.Args -join ' ') was refused: $($r.error.message)") }
        continue
    }
    if ($r.ok -or $r.error.code -ne 'invalid-arguments' -or -not "$($r.error.message)".Contains($case.Says)) {
        $failures.Add("$($case.Args -join ' ') should be invalid-arguments saying '$($case.Says)': $($r.error.code) $($r.error.message)")
    }
}

if ($failures.Count) { $failures | ForEach-Object { Write-Host "FAIL $_" -ForegroundColor Red }; exit 1 }
Write-Host "Every parameter belongs to the commands that read it ($($script:KitCommandFlags.Count) commands, $($params.Count) parameters); $scanned written invocations pass; a flag given to the wrong command is refused"
exit 0
