# Deliberately bad: tests/Test-PowerShellPatterns.ps1 must flag every line marked "flagged" as start-process-arglist.
$file = Join-Path $PSScriptRoot 'a b.ps1'
Start-Process -FilePath pwsh -ArgumentList @('-NoProfile', '-NonInteractive', '-File', $file)   # flagged
Start-Process -FilePath pwsh -ArgumentList '-NoProfile', '-NonInteractive', '-File', (Join-Path $PSScriptRoot 'a b.ps1')   # flagged
Start-Process -FilePath pwsh -ArgumentList @('-NoProfile', '-NonInteractive', '-Command', 'Start-Sleep 5')   # flagged
