# Deliberately bad: tests/Test-PowerShellPatterns.ps1 must flag every line marked "flagged" as null-on-right.
$value = @($null, 1)
if ($value -eq $null) { 'equal' }   # flagged
if ($value -ne $null) { 'not equal' }   # flagged
$same = $value -ceq $null   # flagged
