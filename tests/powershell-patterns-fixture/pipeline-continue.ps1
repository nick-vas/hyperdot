# Deliberately bad: tests/Test-PowerShellPatterns.ps1 must flag every line marked "flagged" as pipeline-continue.
foreach ($name in 'a', 'b') {
    1..3 | ForEach-Object {
        if ($_ -eq 2) { continue }   # flagged
        "$name $_"
    }
}
$kept = @(1..3 | Where-Object { if ($_ -gt 1) { break }; $true })   # flagged
1..3 | % -Process {
    if ($_ -eq 1) {
        continue   # flagged
    }
}
$doubled = (1..3).ForEach({ if ($_ -eq 3) { continue }; $_ * 2 })   # flagged
function Test-Skip([int]$Value) {
    if ($Value -lt 0) { break }   # flagged
    $Value
}
continue   # flagged
