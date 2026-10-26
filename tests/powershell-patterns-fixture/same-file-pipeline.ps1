# Deliberately bad: tests/Test-PowerShellPatterns.ps1 must flag every line marked "flagged" as same-file-pipeline.
$log = Join-Path $PSScriptRoot 'log.txt'
Get-Content $log | Where-Object { $_ } | Set-Content $log   # flagged
Get-Content -LiteralPath $log | Add-Content -LiteralPath $log   # flagged
Get-Content -Path $log | ForEach-Object { $_.Trim() } | Out-File $log   # flagged
