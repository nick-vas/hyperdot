# Deliberately bad: tests/Test-PowerShellPatterns.ps1 must flag every line marked "flagged" as replace-interpolated.
$line = 'a$0b'
$text = 'x' -replace 'x', $line   # flagged
$text = 'x' -replace 'x', "[a]`n$line"   # flagged
