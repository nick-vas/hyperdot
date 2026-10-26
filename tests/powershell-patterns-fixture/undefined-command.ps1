# Deliberately bad: tests/Test-PowerShellPatterns.ps1 must flag every line marked "flagged" as undefined-command.
$godot = (Install-Godot '4.7.2' $false).Binary   # flagged
Get-NoSuchThing -Name x   # flagged
