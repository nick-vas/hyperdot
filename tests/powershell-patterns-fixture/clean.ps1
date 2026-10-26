# Near misses: tests/Test-PowerShellPatterns.ps1 must report nothing here. Comments and strings that name the patterns,
# such as Invoke-Expression, [IO.Path]::Combine('a', '/b'), $x -eq $null or Set-StrictMode -Version Latest, are not code.
Set-StrictMode -Version 3.0
$ErrorActionPreference = 'Stop'
$message = 'never write $x -eq $null, Invoke-Expression or [IO.Path]::Combine'
foreach ($name in 'a', 'b') {
    if ($name -eq 'a') { continue }
    1..3 | ForEach-Object {
        foreach ($i in 1..2) { if ($i -eq 2) { break } }
        switch ($_) { 2 { continue } default { "$name $_" } }
        if ($_ -eq 3) { return }
    }
}
$list = @(1..3).Where({ $_ -gt 1 })
trap { continue }
:outer while ($true) { break outer }
do { $done = $true; if ($done) { break } } while (-not $done)
if ($null -eq $message -or $null -ne $list) { 'compared the right way' }
$joined = [IO.Path]::Join($PSScriptRoot, 'a')
$leaf = [IO.Path]::GetFileName('dir/file.txt')
$full = [IO.Path]::GetFullPath((Join-Path $PSScriptRoot 'build'))
$exists = [IO.File]::Exists("$PSScriptRoot/clean.ps1") -and [IO.Directory]::Exists('/tmp')
function Get-Thing([string]$Name) {
    if ($PSBoundParameters.ContainsKey('Name')) { $Name }
    $PSBoundParameters.Keys
    $PSBoundParameters['Name']
}
$saved = $ErrorActionPreference
$ErrorActionPreference = $saved
$sorted = 'b', 'a' | Sort-Object
& kill -0 $PID 2>$null
$copy = Join-Path $PSScriptRoot 'copy.txt'
(Get-Content -LiteralPath $PSCommandPath) | Set-Content -LiteralPath $copy
Get-Content -LiteralPath $PSCommandPath | Set-Content -LiteralPath $copy
Remove-Item -LiteralPath $copy
