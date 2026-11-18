#!/usr/bin/env pwsh
# Self-test of `clip`: a scene recorded with Godot's Movie Maker and encoded with ffmpeg. A copy of examples/gdscript gets
# a scene that fills the window with red, so the frames can be checked: the MP4 lasts the seconds asked for and shows red,
# the GIF is there, clip.json describes both. Then the refusals: -Seconds out of range, two scenes, a scene that does not
# exist (clip-failed), and no display (no-display). Needs Godot, a display (Xvfb on Linux) and ffmpeg with ffprobe.
Set-StrictMode -Version 3.0
$ErrorActionPreference = 'Stop'
$root = Split-Path $PSScriptRoot
$ci = Join-Path $root 'ci/godot/hyperdot.ps1'
$failures = @()
function Assert-True([bool]$Condition, [string]$Name) {
    if ($Condition) { Write-Host "ok     $Name" } else { Write-Host "FAIL   $Name"; $script:failures += $Name }
}
$game = Join-Path ([System.IO.Path]::GetTempPath()) "clip-$([guid]::NewGuid().ToString('n').Substring(0, 8))"
Copy-Item -LiteralPath (Join-Path $root 'examples/gdscript') -Destination $game -Recurse
Set-Content -LiteralPath (Join-Path $game 'red.tscn') -Value "[gd_scene format=3]`n`n[node name=`"Red`" type=`"ColorRect`"]`noffset_right = 4000.0`noffset_bottom = 4000.0`ncolor = Color(1, 0, 0, 1)"
$out = Join-Path $game 'out'
function Invoke-Kit([string[]]$Arguments) {
    $text = & pwsh -NoProfile -NonInteractive -File $ci clip @Arguments -Json -Quiet -Project $game 2>$null | Out-String
    return @{ code = $LASTEXITCODE; doc = ($text | ConvertFrom-Json -Depth 10) }
}
try {
    $run = Invoke-Kit @('-Scene', 'res://red.tscn', '-Seconds', '2', '-Label', 'red storm', '-Output', $out)
    $clip = $run.doc.clip
    Assert-True ($run.code -eq 0 -and $run.doc.ok -and $clip.name -eq 'red-storm' -and $clip.fps -eq 30 -and $clip.seconds -eq 2) "clip records the scene, named after -Label: $(if ($run.doc.PSObject.Properties["error"]) { $run.doc.error.message })"
    $mp4 = Join-Path $out 'red-storm.mp4'; $gif = Join-Path $out 'red-storm.gif'
    Assert-True ((Test-Path -LiteralPath $mp4) -and (Test-Path -LiteralPath $gif) -and -not (Test-Path -LiteralPath (Join-Path $out 'red-storm.avi'))) 'it writes an MP4 and a GIF and removes the raw recording'
    $duration = [double]::Parse((@(& ffprobe -v error -show_entries format=duration -of csv=p=0 $mp4)[0]), [cultureinfo]::InvariantCulture)
    Assert-True ([math]::Abs($duration - 2) -lt 0.1) "the MP4 lasts the seconds asked for: $duration s"
    $codecs = @(& ffprobe -v error -show_entries stream=codec_name -of csv=p=0 $mp4)
    Assert-True ($codecs -contains 'h264' -and $codecs -contains 'aac') "H.264 video and AAC sound, for posts and Steam: $($codecs -join ', ')"
    # One pixel, written to a file: PowerShell would decode a native program's binary stdout as text.
    $raw = Join-Path $game 'pixel.rgb'
    & ffmpeg -hide_banner -loglevel error -y -ss 1 -i $mp4 -frames:v 1 -vf 'crop=2:2:100:100' -f rawvideo -pix_fmt rgb24 $raw
    $pixel = @([System.IO.File]::ReadAllBytes($raw) | Select-Object -First 3)
    Assert-True ($pixel.Count -eq 3 -and $pixel[0] -gt 200 -and $pixel[1] -lt 40 -and $pixel[2] -lt 40) "the frames show the scene, not an empty window: $($pixel -join ',')"
    $gifWidth = @(& ffprobe -v error -select_streams v:0 -show_entries stream=width -of csv=p=0 $gif)[0]
    Assert-True ($gifWidth -eq '480') "the GIF is 480 wide: $gifWidth"
    $json = Get-Content -LiteralPath (Join-Path $out 'clip.json') -Raw | ConvertFrom-Json
    Assert-True ($json.mp4 -eq $mp4 -and $json.gif -eq $gif -and $json.width -gt 0 -and $json.mp4Bytes -gt 0 -and $json.scene -eq 'res://red.tscn') 'clip.json names the files, the size and the scene'

    foreach ($bad in '0', '31') {
        $run = Invoke-Kit @('-Seconds', $bad, '-Output', $out)
        Assert-True ($run.code -ne 0 -and $run.doc.error.code -eq 'invalid-arguments') "-Seconds $bad is invalid-arguments"
    }
    $run = Invoke-Kit @('-Scene', 'res://red.tscn,res://main.tscn', '-Output', $out)
    Assert-True ($run.doc.error.code -eq 'invalid-arguments') 'clip records one scene'
    $run = Invoke-Kit @('-Scene', 'res://nope.tscn', '-Seconds', '1', '-Output', $out)
    Assert-True ($run.code -ne 0 -and $run.doc.error.code -eq 'clip-failed') 'a scene that does not exist is clip-failed'
    if ($IsLinux) {
        $display = $env:DISPLAY; $env:DISPLAY = $null
        try { $run = Invoke-Kit @('-Seconds', '1', '-Output', $out) } finally { $env:DISPLAY = $display }
        Assert-True ($run.doc.error.code -eq 'no-display') 'without a display it is no-display'
    }
} finally { Remove-Item -LiteralPath $game -Recurse -Force -ErrorAction SilentlyContinue }

if ($failures.Count) { Write-Host "`n$($failures.Count) failed"; exit 1 }
Write-Host "`nclip self-test passed"
exit 0
