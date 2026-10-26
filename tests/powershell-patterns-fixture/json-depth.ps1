# Deliberately bad: tests/Test-PowerShellPatterns.ps1 must flag every line marked "flagged" as json-depth.
$data = @{ a = @{ b = @{ c = @{ d = 1 } } } }
$data | ConvertTo-Json   # flagged
$data | ConvertTo-Json -Compress   # flagged
ConvertTo-Json -InputObject $data -Compress   # flagged
