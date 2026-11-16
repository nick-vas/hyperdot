# Deliberately bad: tests/Test-PowerShellPatterns.ps1 must flag every line marked "flagged" as csv-notypeinformation.
$rows = @([pscustomobject]@{ a = 1 })
$rows | Export-Csv -LiteralPath 'out.csv' -NoTypeInformation   # flagged
$rows | ConvertTo-Csv -NoType   # flagged
$rows | Export-Csv -LiteralPath 'out.csv' -NTI   # flagged
