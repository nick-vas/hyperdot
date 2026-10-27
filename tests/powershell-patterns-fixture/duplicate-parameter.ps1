# Deliberately bad: tests/Test-PowerShellPatterns.ps1 must flag every line marked "flagged" as duplicate-parameter.
$rows = @(1, 2)
ConvertTo-Json -InputObject $rows -Depth 3 -Depth 4   # flagged
Get-ChildItem -LiteralPath $PSScriptRoot -Force -Force   # flagged
