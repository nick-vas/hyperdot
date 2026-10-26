# Deliberately bad: tests/Test-PowerShellPatterns.ps1 must flag every line marked "flagged" as boundparams-dot.
function Get-Thing([string]$Name, [int]$Size) {
    if ($PSBoundParameters.Name) { $Name }   # flagged
    $PSBoundParameters.Size   # flagged
}
