#Requires -Version 7.6
# Every lib/*.ps1 is dot-sourced into one scope, so two files defining the same function leave only the one loaded last, with
# no error: status once called Audio.ps1's Get-Median instead of its own. Fails on a function defined twice, and on one named
# like a built-in alias or command (AGENTS.md: r is Invoke-History, rp is Remove-ItemProperty). Runs without Godot.
$ErrorActionPreference = 'Stop'
Set-StrictMode -Version 3.0
$root = Split-Path $PSScriptRoot
$defined = @{}
$failures = @()
$files = @(Get-ChildItem (Join-Path $root 'ci/godot/lib') -Filter '*.ps1') + @(Get-Item (Join-Path $root 'ci/godot/hyperdot.ps1'))
foreach ($file in $files) {
    $ast = [System.Management.Automation.Language.Parser]::ParseFile($file.FullName, [ref]$null, [ref]$null)
    foreach ($fn in $ast.FindAll({ param($n) $n -is [System.Management.Automation.Language.FunctionDefinitionAst] }, $true)) {
        # Helpers nested in another function are local; one in an if, try or loop block of the file is defined when that runs.
        $inside = $false
        for ($up = $fn.Parent; $up; $up = $up.Parent) { if ($up -is [System.Management.Automation.Language.FunctionDefinitionAst]) { $inside = $true; break } }
        if ($inside) { continue }
        $name = $fn.Name
        if ($defined.ContainsKey($name)) { $failures += "$name is defined in $($defined[$name]) and $($file.Name)" } else { $defined[$name] = $file.Name }
        $builtin = Get-Command -Name $name -CommandType Alias, Cmdlet, Function -ErrorAction SilentlyContinue
        if ($builtin) { $failures += "$name ($($file.Name)) shadows the built-in $($builtin.CommandType.ToString().ToLowerInvariant()) $name" }
    }
}
# Every parameter docs/reference.md documents exists on hyperdot.ps1: a lost edit once removed -FixedFps and
# -MaxChangedPercent from the script while the docs and tests still named them.
$entry = [System.Management.Automation.Language.Parser]::ParseFile((Join-Path $root 'ci/godot/hyperdot.ps1'), [ref]$null, [ref]$null)
# A flag can bind to a variable of another name (-Profile to $PlanProfile), so aliases count too.
$parameters = @($entry.ParamBlock.Parameters | ForEach-Object {
    $_.Name.VariablePath.UserPath
    foreach ($alias in @($_.Attributes | Where-Object { $_.TypeName.Name -eq 'Alias' })) { $alias.PositionalArguments | ForEach-Object Value }
})
$documented = @(Select-String -LiteralPath (Join-Path $root 'docs/reference.md') -Pattern '^\| `-(?<p>[A-Za-z]+)`' | ForEach-Object { $_.Matches[0].Groups['p'].Value } | Sort-Object -Unique)
foreach ($p in $documented) { if ($p -notin $parameters) { $failures += "docs/reference.md documents -$p, which hyperdot.ps1 does not have" } }
if ($failures) { $failures | ForEach-Object { Write-Host "FAIL $_" -ForegroundColor Red }; exit 1 }
Write-Host "$($defined.Count) functions in ci/godot, each defined once and none named like a built-in alias or cmdlet; $($documented.Count) documented parameters, all on hyperdot.ps1"
exit 0
