# Deliberately bad: tests/Test-PowerShellPatterns.ps1 must flag every line marked "flagged" as resolve-path-wildcard.
$tool = (Join-Path $PSScriptRoot 'tool.gd' | Resolve-Path).Path   # flagged
$other = (Resolve-Path (Join-Path $PSScriptRoot 'x.gd')).Path   # flagged
