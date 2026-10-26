# Deliberately bad: tests/Test-PowerShellPatterns.ps1 must flag every line marked "flagged" as windows-alias.
$names = 'b', 'a' | sort   # flagged
ls $PSScriptRoot   # flagged
sleep 1   # flagged
$text = cat $PSCommandPath   # flagged
