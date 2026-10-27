# Deliberately bad: tests/Test-PowerShellPatterns.ps1 must flag every line marked "flagged" as path-wildcard.
$base = Join-Path $PSScriptRoot 'x'
$item = Get-Item -Path (Join-Path $base 'file.txt') -Force   # flagged
$files = Get-ChildItem $base -Recurse   # flagged
Test-Path "$base/a.txt"   # flagged
Compress-Archive -Path (Join-Path $base 'a') -DestinationPath "$base.zip"   # flagged
