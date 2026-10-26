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
$script:RepositoryFunctions = $null
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
    'resolve-path-wildcard' = 'Resolve-Path without -LiteralPath reads [ ] in a path as a wildcard and returns nothing; a piped string binds to -Path, so write Resolve-Path -LiteralPath'
    'start-process-arglist' = 'Start-Process -ArgumentList joins its elements with spaces and quotes none: wrap a path or any value that may hold a space in escaped quotes, or use -EncodedCommand'
    'replace-interpolated'  = 'a variable or interpolated string as the replacement of -replace reads $0, $1 and $& in the data as group references; double the dollars with .Replace(''$'', ''$$'') or use a script block'
    'pwsh-interactive'      = 'a child pwsh started with -File or -Command and no -NonInteractive hangs on a prompt instead of failing'
    'json-depth'            = 'ConvertTo-Json without -Depth stops at depth 2: nested data is cut to its type name and a warning reaches stdout; pass -Depth'
    'path-wildcard'         = 'a path cmdlet without -LiteralPath reads [ ] in a path from data as a wildcard and finds nothing, silently (a deliberate * or ? in the path is allowed)'
    'duplicate-parameter'   = 'a parameter given twice in one command fails to bind at run time, which no parse error shows'
    'undefined-command'     = 'a Verb-Noun command that is neither a function defined in the repository nor a cmdlet of this PowerShell fails only when that line runs (a test that needs a missing helper fails only on a machine without GODOT_BIN)'
    'same-file-pipeline'   = 'Get-Content X piped into Set-Content, Add-Content or Out-File X: on Linux it truncates the file without an error or never ends; read it whole in parentheses first'
}

$windowsAliases = @('cat', 'clear', 'compare', 'cp', 'diff', 'kill', 'ls', 'man', 'mount', 'mv', 'ps', 'rm', 'rmdir', 'sleep', 'sort', 'start', 'tee', 'write')
$pipelineCommands = @('ForEach-Object', 'Where-Object', '%', '?', 'foreach', 'where')
$boundAllowed = @('ContainsKey', 'Keys', 'Values', 'Count', 'Remove', 'Add', 'GetEnumerator', 'TryGetValue', 'Clear')
$pathCmdlets = @('Test-Path', 'Get-Item', 'Get-ChildItem', 'Remove-Item', 'Copy-Item', 'Move-Item', 'Get-Content', 'Set-Content', 'Add-Content', 'Rename-Item', 'Get-FileHash', 'Compress-Archive', 'Expand-Archive', 'Select-String', 'Clear-Content')
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

# The functions the repository defines, found once.
function Get-RepositoryFunctions {
    if ($null -eq $script:RepositoryFunctions) {
        $names = [System.Collections.Generic.HashSet[string]]::new([System.StringComparer]::OrdinalIgnoreCase)
        $all = @(& git -C $root ls-files --cached --others --exclude-standard -- '*.ps1' 2>$null)
        if ($LASTEXITCODE -ne 0 -or $all.Count -eq 0) { $all = @(Get-ChildItem -LiteralPath $root -Recurse -File -Filter '*.ps1' | ForEach-Object { [System.IO.Path]::GetRelativePath($root, $_.FullName) }) }
        foreach ($relative in $all) {
            if ($relative -like 'tests/powershell-patterns-fixture/*') { continue }
            $tree = [System.Management.Automation.Language.Parser]::ParseFile((Join-Path $root $relative), [ref]$null, [ref]$null)
            foreach ($definition in $tree.FindAll({ $args[0] -is [System.Management.Automation.Language.FunctionDefinitionAst] }, $true)) { $null = $names.Add($definition.Name) }
        }
        $script:RepositoryFunctions = $names
    }
    return $script:RepositoryFunctions
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
            if ($n.Operator -in 'Ireplace', 'Creplace' -and $n.Right -is [System.Management.Automation.Language.ArrayLiteralAst] -and @($n.Right.Elements).Count -eq 2) {
                $replacement = @($n.Right.Elements)[1]
                $dynamic = ($replacement -is [System.Management.Automation.Language.ExpandableStringExpressionAst] -and @($replacement.NestedExpressions).Count) -or
                    $replacement -is [System.Management.Automation.Language.VariableExpressionAst] -or $replacement -is [System.Management.Automation.Language.ParenExpressionAst]
                if ($dynamic -and $replacement.Extent.Text -notmatch '\.Replace\(') { & $add 'replace-interpolated' $n $n.Extent.Text }
            }
            if ($n.Operator -in 'Ieq', 'Ine', 'Ceq', 'Cne' -and $n.Right -is [System.Management.Automation.Language.VariableExpressionAst] -and $n.Right.VariablePath.UserPath -eq 'null') {
                & $add 'null-on-right' $n $n.Extent.Text
            }
        } elseif ($n -is [System.Management.Automation.Language.CommandAst]) {
            $name = $n.GetCommandName()
            if (-not $name) { continue }
            if ($name -cmatch '^[A-Z][A-Za-z]+-[A-Za-z]' -and -not (Get-RepositoryFunctions).Contains($name) -and -not (Get-Command -Name $name -ErrorAction Ignore)) { & $add 'undefined-command' $n $name }
            if ($name -in 'Invoke-Expression', 'iex') { & $add 'invoke-expression' $n $name }
            if ($name -in $windowsAliases -and $n.InvocationOperator -ne 'Ampersand') { & $add 'windows-alias' $n $name }
            if ($name -eq 'Set-StrictMode' -and @($n.CommandElements | Where-Object { $_ -is [System.Management.Automation.Language.StringConstantExpressionAst] -and $_.Value -eq 'Latest' }).Count) {
                & $add 'strictmode-latest' $n $n.Extent.Text
            }
            $seen = @($n.CommandElements | Where-Object { $_ -is [System.Management.Automation.Language.CommandParameterAst] } | ForEach-Object { $_.ParameterName.ToLowerInvariant() })
            if ($name -cmatch '^[A-Z][A-Za-z]+-[A-Z]' -and @($seen | Group-Object | Where-Object Count -gt 1).Count) { & $add 'duplicate-parameter' $n $n.Extent.Text }
            if ($name -eq 'ConvertTo-Json' -and @($n.CommandElements | Where-Object { $_ -is [System.Management.Automation.Language.CommandParameterAst] -and $_.ParameterName -match '^De(p(th?)?)?$' }).Count -eq 0) { & $add 'json-depth' $n $n.Extent.Text }
            if ($name -in $pathCmdlets -and ($File -notmatch '[\\/]tests[\\/]' -or $File -match 'patterns-fixture[\\/](path-wildcard|clean)\.ps1')) {
                $literal = @($n.CommandElements | Where-Object { $_ -is [System.Management.Automation.Language.CommandParameterAst] -and $_.ParameterName -match '^(L|Li|Lit|Lite|Liter|Litera|Literal|LiteralP|LiteralPa|LiteralPat|LiteralPath|LP|PSPath)$' }).Count
                $target = Get-PathArgument $n
                if (-not $literal -and $target -and $target -notmatch '^\$env:|^Env:' -and $target -notmatch '[*?]') { & $add 'path-wildcard' $n $n.Extent.Text }
            }
            if ($name -in 'Resolve-Path', 'rvpa') {
                $has = @($n.CommandElements | Where-Object { $_ -is [System.Management.Automation.Language.CommandParameterAst] -and $_.ParameterName -match '^(L|Li|Lit|Lite|Liter|Litera|Literal|LiteralP|LiteralPa|LiteralPat|LiteralPath|LP|PSPath)$' }).Count
                if (-not $has) { & $add 'resolve-path-wildcard' $n $n.Extent.Text }
            }
            if ($name -in 'Start-Process', 'saps') {
                $elements = @($n.CommandElements)
                for ($i = 1; $i -lt $elements.Count; $i++) {
                    $e = $elements[$i]
                    if ($e -isnot [System.Management.Automation.Language.CommandParameterAst] -or $e.ParameterName -notmatch '^(Arg|Argu|Argum|Argume|Argumen|Argument|ArgumentL|ArgumentLi|ArgumentLis|ArgumentList)$') { continue }
                    $value = if ($e.Argument) { $e.Argument } elseif ($i + 1 -lt $elements.Count) { $elements[$i + 1] } else { $null }
                    $items = if ($value -is [System.Management.Automation.Language.ArrayExpressionAst]) { @($value.SubExpression.Statements | ForEach-Object { if ($_ -is [System.Management.Automation.Language.PipelineAst]) { $_.PipelineElements | ForEach-Object { if ($_ -is [System.Management.Automation.Language.CommandExpressionAst]) { $_.Expression } } } }) | ForEach-Object { if ($_ -is [System.Management.Automation.Language.ArrayLiteralAst]) { $_.Elements } else { $_ } } }
                        elseif ($value -is [System.Management.Automation.Language.ArrayLiteralAst]) { @($value.Elements) } else { @($value) }
                    foreach ($item in @($items)) {
                        $bad = $item -is [System.Management.Automation.Language.VariableExpressionAst] -or $item -is [System.Management.Automation.Language.ParenExpressionAst] -or
                            $item -is [System.Management.Automation.Language.SubExpressionAst] -or ($item -is [System.Management.Automation.Language.InvokeMemberExpressionAst] -and $item.Extent.Text -notmatch 'ToBase64String') -or
                            ($item -is [System.Management.Automation.Language.StringConstantExpressionAst] -and $item.Value -match '\s' -and $item.Value -notmatch '^"')
                        if ($bad) { & $add 'start-process-arglist' $n "unquoted element $($item.Extent.Text)" }
                    }
                }
            }
            if ($name -in 'pwsh', 'pwsh.exe') {
                $texts = @($n.CommandElements | Select-Object -Skip 1 | ForEach-Object { $_.Extent.Text })
                $joined = $texts -join ' '
                if ($joined -match '(?i)-(File|f|Command|c)\b' -and $joined -notmatch '(?i)-NonInteractive') { & $add 'pwsh-interactive' $n $n.Extent.Text }
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

# --- Entry and test scripts pin strict mode (S11); the Stop hook's child pwsh cannot prompt (E6).
$noStrict = @($files | Where-Object { $_ -match '^tests/(Test|Get|New)-[^/]*\.ps1$' -or $_ -eq 'ci/godot/hyperdot.ps1' } | Where-Object {
    $text = [System.IO.File]::ReadAllText((Join-Path $root $_)); $text -notmatch '(?m)^\s*Set-StrictMode\s+-Version\s+3\.0\b' })
Assert-True ($noStrict.Count -eq 0) "every entry and test script pins Set-StrictMode -Version 3.0$(if ($noStrict) { ': ' + ($noStrict -join ', ') })"
$hook = Get-Content -LiteralPath (Join-Path $root 'hooks/hooks.json') -Raw | ConvertFrom-Json -AsHashtable
$hookArgs = @($hook['hooks']['Stop'][0]['hooks'][0]['args'])
Assert-True ($hookArgs -contains '-NonInteractive' -and [array]::IndexOf($hookArgs, '-NonInteractive') -lt [array]::IndexOf($hookArgs, '-File')) 'the Stop hook starts pwsh with -NonInteractive'

if ($failures.Count) { Write-Host "$($failures.Count) PowerShell pattern check(s) failed" -ForegroundColor Red; exit 1 }
Write-Host 'PowerShell pattern self-test passed'
exit 0
