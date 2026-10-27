# Deliberately bad: tests/Test-PowerShellPatterns.ps1 must flag every line marked "flagged" as pwsh-interactive.
pwsh -NoProfile -File x.ps1   # flagged
& pwsh -NoProfile -Command 'exit 0'   # flagged
