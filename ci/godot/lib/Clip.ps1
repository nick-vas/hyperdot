# `clip`: a short recording of a scene, for a trailer, a post or the weekly marketing brief. Godot's Movie Maker plays the
# scene at a fixed 30 fps under a display (Xvfb on Linux) and writes every frame and the sound, so the clip is the same on
# any machine however slow; ffmpeg turns it into an MP4 (H.264 and AAC, for posts and Steam) and a small looping GIF (480
# wide, 15 fps, for an issue or a chat). Writes <name>.mp4, <name>.gif and clip.json in -Output (default clips).
# Movie Maker records at the project's viewport size: the MP4 is scaled to -Resolution when given, else a small pixel-art
# viewport is scaled up to 720 lines (nearest neighbour, so pixels stay sharp), and either way to even sides, which H.264 needs.
# On Linux the scene is drawn with OpenGL (the Compatibility renderer), what a virtual display can draw; elsewhere with the
# project's own renderer.

$script:ClipFps = 30
$script:ClipMaxSeconds = 30
$script:ClipGifWidth = 480
$script:ClipGifFps = 15
$script:ClipMinHeight = 720

function Assert-Ffmpeg([string]$What) {
    if (-not (Get-Command ffmpeg -CommandType Application -ErrorAction SilentlyContinue)) {
        $how = if ($IsWindows) { 'winget install Gyan.FFmpeg' } elseif ($IsMacOS) { 'brew install ffmpeg' } else { 'sudo apt-get install ffmpeg' }
        Stop-GodotCi "$What encodes video with ffmpeg, which is not installed. Install it ($how) and run again" 'no-ffmpeg'
    }
}

# The clip's file name: -Label, else the scene's file name, else "main"; letters, digits, dots, hyphens and underscores.
function Get-ClipName([string]$Label, [string]$Scene) {
    $base = if ($Label) { $Label } elseif ($Scene) { [System.IO.Path]::GetFileNameWithoutExtension($Scene) } else { 'main' }
    $safe = ($base -replace '[^A-Za-z0-9._-]+', '-').Trim('-', '.')
    return $safe ? $safe : 'clip'
}

function Get-ClipSize([string]$File) {
    if (-not (Get-Command ffprobe -CommandType Application -ErrorAction SilentlyContinue)) { return $null }
    $line = @(& ffprobe -v error -select_streams v:0 -show_entries stream=width,height -of csv=p=0 $File 2>$null)
    if ($LASTEXITCODE -ne 0 -or $line.Count -eq 0 -or "$($line[0])" -notmatch '^(\d+),(\d+)') { return $null }
    return [ordered]@{ width = [int]$Matches[1]; height = [int]$Matches[2] }
}

function Invoke-Clip($Info, [string]$Scene, [double]$Seconds, [string]$Resolution, [string[]]$GameArgs, [string]$Label, [string]$OutputDir) {
    if ($Seconds -lt 1 -or $Seconds -gt $script:ClipMaxSeconds) { Stop-GodotCi "-Seconds for clip is 1 to $($script:ClipMaxSeconds), not $Seconds" 'invalid-arguments' }
    if ($Resolution -and $Resolution -notmatch '^\d+x\d+$') { Stop-GodotCi "-Resolution is WIDTHxHEIGHT, like 1280x720, not $Resolution" 'invalid-arguments' }
    Assert-Display 'clip'
    Assert-Ffmpeg 'clip'
    New-Item -ItemType Directory -Force $OutputDir | Out-Null
    $name = Get-ClipName $Label $Scene
    $movie = Join-Path $OutputDir "$name.avi"
    $mp4 = Join-Path $OutputDir "$name.mp4"
    $gif = Join-Path $OutputDir "$name.gif"
    $log = Join-Path $OutputDir "$name.log"
    $frames = [int][math]::Ceiling($Seconds * $script:ClipFps)
    # OpenGL asks the least of a virtual display; Movie Maker renders every frame at the fixed rate, however long each takes.
    $engine = @('--path', $Info.ProjectDir) + $(if ($IsLinux) { @('--rendering-driver', 'opengl3') }) +
        @('--write-movie', $movie, '--fixed-fps', "$($script:ClipFps)", '--quit-after', "$frames") + $(if ($Scene) { $Scene }) + $(if ($GameArgs) { @('--') + $GameArgs })
    Start-LogGroup "Record $(if ($Scene) { $Scene } else { 'the main scene' }) for $Seconds s"
    $code = Invoke-Logged $env:GODOT_BIN $engine $log
    Stop-LogGroup
    if ($code -ne 0 -or -not (Test-Path -LiteralPath $movie)) { Stop-GodotCi "Godot exited with $code while recording; see $log" 'clip-failed' }

    # ffmpeg's messages go to the clip's log too, so "see <log>" finds them.
    $toLog = { param($Line) Write-RunLog "$Line"; Add-Content -LiteralPath $log -Value "ffmpeg: $Line" }
    $size = if ($Resolution) {
        $w, $h = @($Resolution -split 'x' | ForEach-Object { [int]$_ })
        "scale=$([math]::Max(2, $w - $w % 2)):$([math]::Max(2, $h - $h % 2)):flags=neighbor"
    } else { "scale=-2:'if(lt(ih,$($script:ClipMinHeight)),$($script:ClipMinHeight),trunc(ih/2)*2)':flags=neighbor" }
    & ffmpeg -hide_banner -loglevel error -y -i $movie -vf $size -c:v libx264 -preset veryfast -crf 23 -pix_fmt yuv420p -movflags +faststart -c:a aac -b:a 128k $mp4 2>&1 |
        ForEach-Object { & $toLog $_ }
    if ($LASTEXITCODE -ne 0 -or -not (Test-Path -LiteralPath $mp4)) { Stop-GodotCi "ffmpeg could not encode $movie as MP4; see $log" 'clip-failed' }
    $palette = "fps=$($script:ClipGifFps),scale=$($script:ClipGifWidth):-2:flags=lanczos,split[a][b];[a]palettegen[p];[b][p]paletteuse"
    & ffmpeg -hide_banner -loglevel error -y -i $movie -vf $palette -loop 0 $gif 2>&1 | ForEach-Object { & $toLog $_ }
    if ($LASTEXITCODE -ne 0 -or -not (Test-Path -LiteralPath $gif)) { Stop-GodotCi "ffmpeg could not make a GIF of $movie; see $log" 'clip-failed' }
    Remove-Item -LiteralPath $movie

    $size = Get-ClipSize $mp4
    $result = [ordered]@{
        name = $name; scene = $(if ($Scene) { $Scene } else { 'main scene' }); seconds = $Seconds; fps = $script:ClipFps; gameArgs = @($GameArgs)
        mp4 = $mp4; gif = $gif; log = $log; width = $(if ($size) { $size.width } else { $null }); height = $(if ($size) { $size.height } else { $null })
        mp4Bytes = (Get-Item -LiteralPath $mp4).Length; gifBytes = (Get-Item -LiteralPath $gif).Length
    }
    $result | ConvertTo-Json -Depth 4 | Set-Content -LiteralPath (Join-Path $OutputDir 'clip.json') -Encoding utf8
    Set-JsonField clip $result
    Write-CiLog "Recorded $($result.scene) for $Seconds s: $mp4 ($([math]::Round($result.mp4Bytes / 1MB, 1)) MB), $gif ($([math]::Round($result.gifBytes / 1MB, 1)) MB)"
    # A clip is footage, not a test: errors the game printed are reported, and the clip is kept.
    $errors = @(Get-Content -LiteralPath $log -ErrorAction SilentlyContinue | Where-Object { $_ -match '^(ERROR|SCRIPT ERROR|USER ERROR):' } | Select-Object -First 3)
    if ($errors.Count) {
        Set-JsonField warnings @("The game printed errors while it was recorded: $($errors -join ' | ') (see $log)")
        Write-CiLog "WARNING: the game printed errors while it was recorded; see $log"
    }
}
