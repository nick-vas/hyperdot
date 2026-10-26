# Deliberately bad: tests/Test-PowerShellPatterns.ps1 must flag every line marked "flagged" as lowered-erroraction.
$ErrorActionPreference = 'SilentlyContinue'   # flagged
function Invoke-Quietly {
    $ErrorActionPreference = "Continue"   # flagged
    $script:ErrorActionPreference = [System.Management.Automation.ActionPreference]::Ignore   # flagged
}
