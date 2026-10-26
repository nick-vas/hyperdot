# Deliberately bad: tests/Test-PowerShellPatterns.ps1 must flag every line marked "flagged" as path-combine.
$root = $PSScriptRoot
$a = [IO.Path]::Combine($root, '/etc')   # flagged
$b = [System.IO.Path]::Combine($root, 'a', 'b')   # flagged
