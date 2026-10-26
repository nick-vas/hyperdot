#Requires -Version 7.6
# Holds every tracked .ps1 to the PowerShell anti-patterns of docs/powershell.md that have no use in the repository today,
# so none comes back. Each check reads PowerShell's own syntax tree, not the text, so a comment or a string that names a
# pattern does not trip it. The fixture (tests/powershell-patterns-fixture) proves every check fires: one file per rule,
# named after it, whose lines marked "# flagged" must be reported (and no others), and clean.ps1, full of near misses, must
# not be. The fixture is left out of the repository pass and of PSScriptAnalyzer. Runs without Godot.
$ErrorActionPreference = 'Stop'
Set-StrictMode -Version 3.0
$root = Split-Path $PSScriptRoot
$fixtureDir = Join-Path $PSScriptRoot 'powershell-patterns-fixture'
$failures = @()
function Assert-True([bool]$Condition, [string]$Name) {
    if ($Condition) { Write-Host "ok     $Name" } else { Write-Host "FAIL   $Name" -ForegroundColor Red; $script:failures += $Name }
}

$rules = [ordered]@{
    'pipeline-continue'    = 'continue or break that leaves a ForEach-Object, Where-Object, .ForEach() or .Where() block, a function or the script: it ends the script quietly with exit code 0 or steps the caller''s loop; use return'
    'null-on-right'        = '$null on the right of -eq or -ne: with a collection on the left it filters instead of comparing; write $null -eq $x'
    'invoke-expression'    = 'Invoke-Expression runs a string as code; call the command with its arguments as an array'
    'path-combine'         = '[IO.Path]::Combine drops every part before one that is rooted; use Join-Path or [IO.Path]::Join'
    'boundparams-dot'      = '$PSBoundParameters.Name throws under strict mode when the parameter was not passed; use .ContainsKey(''Name'') or [''Name'']'
    'lowered-erroraction'  = '$ErrorActionPreference set below Stop: a throw is then skipped and the next line runs; test first, or use try/catch'
    'relative-dotnet-path' = 'a relative literal path given to .NET file APIs resolves against the process folder, not $PWD; build it from $PSScriptRoot or another absolute root'
    'strictmode-latest'    = 'Set-StrictMode -Version Latest changes with each PowerShell release; pin 3.0'
    'windows-alias'        = 'a Windows-only alias at command position runs a cmdlet on Windows and a program on Linux; write the cmdlet''s name, or & name for the program'
    'same-file-pipeline'   = 'Get-Content X piped into Set-Content, Add-Content or Out-File X: on Linux it truncates the file without an error or never ends; read it whole in parentheses first'
}

$windowsAliases = @('cat', 'clear', 'compare', 'cp', 'diff', 'kill', 'ls', 'man', 'mount', 'mv', 'ps', 'rm', 'rmdir', 'sleep', 'sort', 'start', 'tee', 'write')
$pipelineCommands = @('ForEach-Object', 'Where-Object', '%', '?', 'foreach', 'where')
$boundAllowed = @('ContainsKey', 'Keys', 'Values', 'Count', 'Remove', 'Add', 'GetEnumerator', 'TryGetValue', 'Clear')
$writers = @('Set-Content', 'Add-Content', 'Out-File', 'sc', 'ac')

# Where a continue or break goes: $null when a loop, switch or trap of its own takes it, else why it escapes.
function Get-JumpEscape([System.Management.Automation.Language.Ast]$Jump) {
    $node = $Jump.Parent
    while ($node) {
        if ($node -is [System.Management.Automation.Language.LabeledStatementAst] -or $node -is [System.Management.Automation.Language.TrapStatementAst]) { return $null }
        if ($node -is [System.Management.Automation.Language.ScriptBlockAst]) {
            $holder = $node.Parent
            if ($null -eq $holder) { return 'outside any loop in the script' }
            if ($holder -is [System.Management.Automation.Language.FunctionDefinitionAst]) { return "outside any loop in function $($holder.Name)" }
            if ($holder -is [System.Management.Automation.Language.ScriptBlockExpressionAst]) {
                $user = $holder.Parent
                if ($user -is [System.Management.Automation.Language.CommandParameterAst]) { $user = $user.Parent }
                if ($user -is [System.Management.Automation.Language.CommandAst] -and $user.GetCommandName() -in $pipelineCommands) { return "inside a $($user.GetCommandName()) block" }
                if ($user -is [System.Management.Automation.Language.InvokeMemberExpressionAst] -and $user.Member.Extent.Text -in 'ForEach', 'Where') { return "inside a .$($user.Member.Extent.Text)() block" }
            }
        }
        $node = $node.Parent
    }
    return 'outside any loop'
}

# The path argument of a command: the value after -Path or -LiteralPath (or a prefix of them), or the first positional one.
function Get-PathArgument([System.Management.Automation.Language.CommandAst]$Command) {
    $elements = @($Command.CommandElements)
    for ($i = 1; $i -lt $elements.Count; $i++) {
        $element = $elements[$i]
        if ($element -is [System.Management.Automation.Language.CommandParameterAst]) {
            if ($element.ParameterName -match '^(P|Pa|Pat|Path|L|Li|Lit|Lite|Liter|Litera|Literal|LiteralP|LiteralPa|LiteralPat|LiteralPath|PSPath|LP)$') {
                if ($element.Argument) { return $element.Argument.Extent.Text }
                if ($i + 1 -lt $elements.Count) { return $elements[$i + 1].Extent.Text }
            } elseif (-not $element.Argument) { $i++ }   # a named value that is not the path; switches are rare on these
            continue
        }
        return $element.Extent.Text
    }
    return $null
}

function Get-PatternFindings([string]$File) {
    $errors = $null
    $ast = [System.Management.Automation.Language.Parser]::ParseFile($File, [ref]$null, [ref]$errors)
    $found = [System.Collections.Generic.List[object]]::new()
    $add = { param($Rule, $Node, $Detail) $found.Add([pscustomobject]@{ Rule = $Rule; Line = $Node.Extent.StartLineNumber; Detail = $Detail }) }
    foreach ($e in @($errors)) { $found.Add([pscustomobject]@{ Rule = 'parse-error'; Line = $e.Extent.StartLineNumber; Detail = $e.Message }) }
    $nodes = $ast.FindAll({ $true }, $true)
    foreach ($n in $nodes) {
        if ($n -is [System.Management.Automation.Language.ContinueStatementAst] -or $n -is [System.Management.Automation.Language.BreakStatementAst]) {
            $escape = Get-JumpEscape $n
            if ($escape) { & $add 'pipeline-continue' $n "$($n.Extent.Text) $escape" }
        } elseif ($n -is [System.Management.Automation.Language.BinaryExpressionAst]) {
            if ($n.Operator -in 'Ieq', 'Ine', 'Ceq', 'Cne' -and $n.Right -is [System.Management.Automation.Language.VariableExpressionAst] -and $n.Right.VariablePath.UserPath -eq 'null') {
                & $add 'null-on-right' $n $n.Extent.Text
            }
        } elseif ($n -is [System.Management.Automation.Language.CommandAst]) {
            $name = $n.GetCommandName()
            if (-not $name) { continue }
            if ($name -in 'Invoke-Expression', 'iex') { & $add 'invoke-expression' $n $name }
            if ($name -in $windowsAliases -and $n.InvocationOperator -ne 'Ampersand') { & $add 'windows-alias' $n $name }
            if ($name -eq 'Set-StrictMode' -and @($n.CommandElements | Where-Object { $_ -is [System.Management.Automation.Language.StringConstantExpressionAst] -and $_.Value -eq 'Latest' }).Count) {
                & $add 'strictmode-latest' $n $n.Extent.Text
            }
            if ($name -in 'Get-Content', 'gc' -and $n.Parent -is [System.Management.Automation.Language.PipelineAst]) {
                $source = Get-PathArgument $n
                $later = @($n.Parent.PipelineElements | Select-Object -Skip 1)
                foreach ($writer in $later) {
                    if ($writer -is [System.Management.Automation.Language.CommandAst] -and $writer.GetCommandName() -in $writers -and $source -and (Get-PathArgument $writer) -eq $source) {
                        & $add 'same-file-pipeline' $n "$name $source | $($writer.GetCommandName()) $source"
                    }
                }
            }
        } elseif ($n -is [System.Management.Automation.Language.MemberExpressionAst]) {
            $member = $n.Member.Extent.Text.Trim("'", '"')
            if ($n.Static -and $n.Expression -is [System.Management.Automation.Language.TypeExpressionAst]) {
                $type = $n.Expression.TypeName.FullName
                if ($type -match '^(System\.)?IO\.Path$' -and $member -eq 'Combine') { & $add 'path-combine' $n $n.Extent.Text }
                $fileApi = ($type -match '^(System\.)?IO\.(File|Directory)$') -or ($type -match '^(System\.)?IO\.Path$' -and $member -eq 'GetFullPath') -or
                    ($type -match '^(System\.)?IO\.(FileInfo|DirectoryInfo|StreamReader|StreamWriter|FileStream)$' -and $member -eq 'new')
                if ($fileApi -and $n -is [System.Management.Automation.Language.InvokeMemberExpressionAst] -and @($n.Arguments).Count) {
                    $first = @($n.Arguments)[0]
                    if (($first -is [System.Management.Automation.Language.StringConstantExpressionAst] -or $first -is [System.Management.Automation.Language.ExpandableStringExpressionAst]) -and
                        $first.Value -notmatch '^(\$|[/\\]|[A-Za-z]:[/\\])') {
                        & $add 'relative-dotnet-path' $n $n.Extent.Text
                    }
                }
            } elseif (-not $n.Static -and $n.Expression -is [System.Management.Automation.Language.VariableExpressionAst] -and
                $n.Expression.VariablePath.UserPath -eq 'PSBoundParameters' -and $member -notin $boundAllowed) {
                & $add 'boundparams-dot' $n $n.Extent.Text
            }
        } elseif ($n -is [System.Management.Automation.Language.AssignmentStatementAst]) {
            if ($n.Left -is [System.Management.Automation.Language.VariableExpressionAst] -and ($n.Left.VariablePath.UserPath -replace '^\w+:', '') -eq 'ErrorActionPreference' -and
                $n.Right.Extent.Text -match '^\s*(\[[\w.]*ActionPreference\]::)?[''"]?(SilentlyContinue|Continue|Ignore|Inquire|Suspend|Break)[''"]?\s*$') {
                & $add 'lowered-erroraction' $n $n.Extent.Text
            }
        }
    }
    return $found
}

# --- The fixture: each check fires on its own file, at exactly the marked lines, and stays quiet on the clean file.
foreach ($rule in $rules.Keys) {
    $file = Join-Path $fixtureDir "$rule.ps1"
    if (-not (Test-Path -LiteralPath $file -PathType Leaf)) { Assert-True $false "$rule has a fixture file"; continue }
    $want = @(Select-String -LiteralPath $file -Pattern '#\s*flagged\b' | ForEach-Object LineNumber)
    $findings = @(Get-PatternFindings $file)
    $got = @($findings | Where-Object Rule -eq $rule | ForEach-Object Line | Sort-Object -Unique)
    $others = @($findings | Where-Object Rule -ne $rule | ForEach-Object { "$($_.Rule):$($_.Line)" })
    $ok = $want.Count -gt 0 -and (($want -join ',') -eq ($got -join ',')) -and $others.Count -eq 0
    Assert-True $ok "$rule.ps1 flags lines $($want -join ', ') as $rule$(if (-not $ok) { " (got $($got -join ', '); other rules: $($others -join ', '))" })"
}
$noise = @(Get-PatternFindings (Join-Path $fixtureDir 'clean.ps1'))
Assert-True ($noise.Count -eq 0) "clean.ps1 has no findings$(if ($noise) { ': ' + (@($noise | ForEach-Object { "$($_.Rule):$($_.Line) $($_.Detail)" }) -join '; ') })"

# --- The repository: every tracked .ps1 (and any new one not yet committed), except the deliberately bad fixture.
$listed = @(& git -C $root ls-files --cached --others --exclude-standard -- '*.ps1' 2>$null)
if ($LASTEXITCODE -ne 0 -or $listed.Count -eq 0) {
    $listed = @(Get-ChildItem -LiteralPath $root -Recurse -File -Filter '*.ps1' | ForEach-Object { [System.IO.Path]::GetRelativePath($root, $_.FullName) -replace '\\', '/' })
}
$files = @($listed | Where-Object { $_ -notlike 'tests/powershell-patterns-fixture/*' } | Sort-Object -Unique)
$repoFindings = @(foreach ($relative in $files) {
    foreach ($f in @(Get-PatternFindings (Join-Path $root $relative))) { "${relative}:$($f.Line) $($f.Rule): $($f.Detail)" }
})
foreach ($finding in $repoFindings) { Write-Host "       $finding" -ForegroundColor Red }
Assert-True ($files.Count -gt 0 -and $repoFindings.Count -eq 0) "$($files.Count) .ps1 files in the repository hold none of the $($rules.Count) patterns$(if ($repoFindings) { " ($($repoFindings.Count) found; the rules: docs/powershell.md)" })"
if ($repoFindings) { foreach ($rule in $rules.Keys) { if (@($repoFindings -match " ${rule}: ").Count) { Write-Host "       ${rule}: $($rules[$rule])" } } }

if ($failures.Count) { Write-Host "$($failures.Count) PowerShell pattern check(s) failed" -ForegroundColor Red; exit 1 }
Write-Host 'PowerShell pattern self-test passed'
exit 0
