# Deliberately bad: tests/Test-PowerShellPatterns.ps1 must flag every line marked "flagged" as strictmode-latest.
Set-StrictMode -Version Latest   # flagged
Set-StrictMode -Version 'Latest'   # flagged
