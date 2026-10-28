#!/usr/bin/env pwsh
# Self-test of the download failure code: when Godot cannot be downloaded (here a version that does not exist, or no
# network at all), `setup -Json` stops with `download-failed`, not `unexpected-error`, so an agent retries or checks the
# network instead of changing the game. It takes about 15 s: the download is tried four times with a growing pause.
# The checksum check of a download (Confirm-DownloadChecksum) runs against a stand-in server on 127.0.0.1.
Set-StrictMode -Version 3.0
$ErrorActionPreference = 'Stop'

$root = Split-Path $PSScriptRoot
$tools = Join-Path ([IO.Path]::GetTempPath()) "download-failed-$PID"
$saved = @{}
foreach ($name in @('GODOT_BIN', 'HYPERDOT_INSTALLED', 'GODOT_TOOLS_DIR', 'EVAL_GODOT_BIN')) {
    $saved[$name] = [Environment]::GetEnvironmentVariable($name)
    [Environment]::SetEnvironmentVariable($name, $null)
}
$env:GODOT_TOOLS_DIR = $tools
try {
    $json = & pwsh -NoProfile -NonInteractive -File (Join-Path $root 'ci/godot/hyperdot.ps1') setup -Json -Quiet `
        -Project (Join-Path $root 'examples/gdscript') -GodotVersion 0.0.0 2>$null
    $code = $LASTEXITCODE
} finally {
    foreach ($name in $saved.Keys) { [Environment]::SetEnvironmentVariable($name, $saved[$name]) }
    if (Test-Path -LiteralPath $tools) { Remove-Item -Recurse -Force -LiteralPath $tools }
}

$failures = @()
$doc = $json | ConvertFrom-Json
if ($code -ne 1) { $failures += "exit code $code, expected 1" }
if ($doc.ok -ne $false) { $failures += "ok is $($doc.ok), expected false" }
if ($doc.error.code -ne 'download-failed') { $failures += "error.code is '$($doc.error.code)', expected download-failed ($($doc.error.message))" }
if ($doc.error.message -notmatch 'Godot_v0\.0[.-]') { $failures += "message does not name the URL: $($doc.error.message)" }

# A download is checked against the SHA512-SUMS.txt Godot publishes beside the release (a stand-in server on 127.0.0.1): a match
# is used, a mismatch stops with checksum-mismatch and deletes the file, and a release without the file, or whose file does
# not list the archive, is used with a note.
$archive = [System.Text.Encoding]::UTF8.GetBytes('pretend this is a Godot editor archive')
$good = [System.BitConverter]::ToString([System.Security.Cryptography.SHA512]::HashData($archive)).Replace('-', '').ToLowerInvariant()
$wrong = ('0' * 128)
$probe = [System.Net.Sockets.TcpListener]::new([System.Net.IPAddress]::Loopback, 0)
$probe.Start(); $port = $probe.LocalEndpoint.Port; $probe.Stop()
$name = 'Godot_v9.9-stable_linux.zip'
$server = Start-ThreadJob -ArgumentList $port, $name, $good, $wrong -ScriptBlock {
    param($Port, $Name, $Good, $Wrong)
    $listener = [System.Net.HttpListener]::new()
    $listener.Prefixes.Add("http://127.0.0.1:$Port/")
    $listener.Start()
    try {
        while ($true) {
            $context = $listener.GetContext()
            $path = $context.Request.Url.AbsolutePath
            $reply = switch ($path) {
                '/ok/SHA512-SUMS.txt' { @(200, 'text/plain', "$Good  $Name`n$Wrong  other.zip`n") }
                '/binary/SHA512-SUMS.txt' { @(200, 'application/octet-stream', "$Good *$Name`n") }
                '/bad/SHA512-SUMS.txt' { @(200, 'text/plain', "$Wrong  $Name`n") }
                '/unlisted/SHA512-SUMS.txt' { @(200, 'text/plain', "$Good  some-other-file.zip`n") }
                '/stop' { $null }
                default { @(404, 'text/plain', 'not found') }
            }
            if ($null -eq $reply) { $context.Response.Close(); break }
            $bytes = [System.Text.Encoding]::UTF8.GetBytes($reply[2])
            $context.Response.StatusCode = $reply[0]; $context.Response.ContentType = $reply[1]
            $context.Response.OutputStream.Write($bytes, 0, $bytes.Length); $context.Response.Close()
        }
    } finally { $listener.Stop() }
}
$checkDir = Join-Path ([IO.Path]::GetTempPath()) "checksum-$PID"
New-Item -ItemType Directory -Force $checkDir | Out-Null
$child = Join-Path $checkDir 'check.ps1'
Set-Content -LiteralPath $child -Value @"
`$ErrorActionPreference = 'Stop'
. '$root/ci/godot/lib/Common.ps1'
. '$root/ci/godot/lib/Setup.ps1'
`$script:CatchStops = `$true
foreach (`$case in 'ok', 'binary', 'bad', 'unlisted', 'none') {
    `$file = Join-Path '$checkDir' "`$case.zip"
    [IO.File]::WriteAllBytes(`$file, [byte[]]($($archive -join ',')))
    `$result = try { Confirm-DownloadChecksum "http://127.0.0.1:$port/`$case" '$name' `$file; 'accepted' } catch { `$_.Exception.Data['HyperdotCode'] }
    "case:`$case `$result kept=`$(Test-Path -LiteralPath `$file)"
}
"@
$env:NO_PROXY = '127.0.0.1,localhost'; $env:no_proxy = '127.0.0.1,localhost'
try {
    $cases = @(& pwsh -NoProfile -NonInteractive -File $child 2>&1 | ForEach-Object { "$_" } | Where-Object { $_ -like 'case:*' })
} finally {
    try { Invoke-RestMethod "http://127.0.0.1:$port/stop" -NoProxy -TimeoutSec 5 | Out-Null } catch { Write-Host "stop: $($_.Exception.Message)" }
    Remove-Item Env:NO_PROXY, Env:no_proxy -ErrorAction SilentlyContinue
    Receive-Job $server -Wait -AutoRemoveJob -ErrorAction SilentlyContinue | Out-Null
    Remove-Item -Recurse -Force -LiteralPath $checkDir -ErrorAction SilentlyContinue
}
$expected = [ordered]@{
    'case:ok accepted kept=True' = 'a download that matches the published SHA-512 is used'
    'case:binary accepted kept=True' = 'a SHA512-SUMS.txt served as application/octet-stream, with a * before the name, is read too'
    'case:bad checksum-mismatch kept=False' = 'a download that does not match stops with checksum-mismatch and is deleted'
    'case:unlisted accepted kept=True' = 'a SHA512-SUMS.txt that does not list the archive is used with a note'
    'case:none accepted kept=True' = 'a release that publishes no SHA512-SUMS.txt is used with a note'
}
foreach ($line in $expected.Keys) { if ($line -notin $cases) { $failures += "$($expected[$line]) (wanted '$line', got: $($cases -join ' | '))" } }

if ($failures) {
    foreach ($failure in $failures) { Write-Host "FAIL $failure" }
    exit 1
}
Write-Host "A Godot download that fails stops setup with download-failed ($($doc.error.message)); one that does not match the published SHA-512 stops with checksum-mismatch"
exit 0
