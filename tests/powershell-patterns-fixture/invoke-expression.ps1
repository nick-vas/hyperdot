# Deliberately bad: tests/Test-PowerShellPatterns.ps1 must flag every line marked "flagged" as invoke-expression.
$command = 'git status'
Invoke-Expression $command   # flagged
$out = iex "Get-Date"   # flagged
