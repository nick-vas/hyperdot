#!/usr/bin/env pwsh
# Self-test of the report pins add-on (ci/godot/templates/addons/hyperdot_report_pins) in a project made in a temporary
# folder: bug_report.gd saves a 3D and a 2D report with the scene, positions, seed and build; report_pins.gd finds them
# (not other JSON or a broken file), keeps a scene's own, puts a point in front of the camera on its screen and one
# behind it nowhere, and gives the camera back; then the editor, headless, loads the plugin on the scene the report came
# from, lists it and quits (Godot's own abort at exit allowed, see below). Needs Godot (GODOT_BIN, or the kit installs it).
Set-StrictMode -Version 3.0
$ErrorActionPreference = 'Stop'
$root = Split-Path $PSScriptRoot
foreach ($lib in 'Common', 'Setup') { . (Join-Path $root "ci/godot/lib/$lib.ps1") }
$failures = [System.Collections.Generic.List[string]]::new()
function Assert-True([bool]$Condition, [string]$What) {
    if ($Condition) { Write-Host "ok     $What" } else { Write-Host "FAILED $What" -ForegroundColor Red; $failures.Add($What) }
}
$godot = if ($env:GODOT_BIN) { $env:GODOT_BIN } else { Install-GodotTools -Version '4.7.2' -Mono $false 6>$null 4>$null; $env:GODOT_BIN }

$id = [guid]::NewGuid().ToString('N').Substring(0, 8)
$game = Join-Path ([IO.Path]::GetTempPath()) "report-pins-$id"
New-Item -ItemType Directory -Force (Join-Path $game 'addons'), (Join-Path $game 'reports') | Out-Null
Copy-Item -Recurse (Join-Path $root 'ci/godot/templates/addons/hyperdot_report_pins') (Join-Path $game 'addons/hyperdot_report_pins')
Set-Content -LiteralPath (Join-Path $game 'reports/.gdignore') -Value ''
# The project's name is its own, so its user:// folder (outside $game, removed at the end) starts empty.
Set-Content -LiteralPath (Join-Path $game 'project.godot') -Value @"
config_version=5

[application]
config/name="Report pins $id"

[editor_plugins]
enabled=PackedStringArray("res://addons/hyperdot_report_pins/plugin.cfg")
"@
Set-Content -LiteralPath (Join-Path $game 'level.tscn') -Value @'
[gd_scene format=3]

[node name="Level" type="Node3D"]

[node name="Camera" type="Camera3D" parent="."]
transform = Transform3D(1, 0, 0, 0, 1, 0, 0, 0, 1, 0, 2, 4)

[node name="Player" type="Node3D" parent="."]
transform = Transform3D(1, 0, 0, 0, 1, 0, 0, 0, 1, 2, 1, -5)
'@
Set-Content -LiteralPath (Join-Path $game 'level2d.tscn') -Value @'
[gd_scene format=3]

[node name="Level" type="Node2D"]

[node name="Camera" type="Camera2D" parent="."]
position = Vector2(300, 200)
zoom = Vector2(2, 2)

[node name="Player" type="Node2D" parent="."]
position = Vector2(320, 180)
'@
Set-Content -LiteralPath (Join-Path $game 'check.gd') -Value @'
extends SceneTree

const BugReport = preload("res://addons/hyperdot_report_pins/bug_report.gd")
const Pins = preload("res://addons/hyperdot_report_pins/report_pins.gd")


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	print("@@userdir ", OS.get_user_data_dir())
	var level: Node3D = load("res://level.tscn").instantiate()
	root.add_child(level)
	await process_frame
	var saved := BugReport.save("these rocks look wrong", level, level.get_node("Player"), level.get_node("Camera"), 7, "abc1234")
	print("@@saved ", saved)
	var flat: Node2D = load("res://level2d.tscn").instantiate()
	root.add_child(flat)
	await process_frame
	BugReport.save("a gap here", flat, flat.get_node("Player"), flat.get_node("Camera"), 8, "abc1234", BugReport.DIR, false)
	FileAccess.open("user://reports/notes.json", FileAccess.WRITE).store_string("{\"text\": \"not a report\"}")
	FileAccess.open("user://reports/broken.json", FileAccess.WRITE).store_string("{")
	var all := Pins.load_reports(["user://reports", "res://missing"])
	print("@@count ", all.size())
	var mine := Pins.for_scene(all, "res://level.tscn")
	print("@@scene ", mine.size(), " ", mine[0].get("text") if mine.size() else "", " ", Pins.for_scene(all, "").size())
	var camera: Camera3D = level.get_node("Camera")
	var at = Pins.screen_point(camera, Pins.vector(mine[0]["player"]))
	print("@@front ", at != null and Rect2(Vector2.ZERO, camera.get_viewport().get_visible_rect().size).has_point(at))
	print("@@behind ", Pins.screen_point(camera, Vector3(0, 2, 10)) == null)
	var view = Pins.camera_transform(mine[0])
	print("@@view ", view is Transform3D and view.is_equal_approx(camera.global_transform))
	var other := Pins.for_scene(all, "res://level2d.tscn")
	print("@@flat ", other.size() == 1 and Pins.vector(other[0]["player"]) == Vector2(320, 180) and Pins.camera_transform(other[0]) == null and not other[0].has("screenshot"))
	print("@@label ", Pins.label({"text": "x".repeat(60)}, 2).length(), " ", Pins.label({"text": "x".repeat(60)}, 2).begins_with("3  "))
	print("@@details ", Pins.details(mine[0]).contains("--seed=7"), " ", Pins.details(mine[0]).contains("abc1234"))
	var copy := FileAccess.open("res://reports/shared.json", FileAccess.WRITE)
	copy.store_string(FileAccess.get_file_as_string(saved))
	copy.close()
	quit(0)
'@

$value = @{}
try {
    $out = @(& $godot --headless --path $game --quit-after 600 -s check.gd 2>&1 | ForEach-Object { "$_" })
    foreach ($line in $out) { if ($line -match '^@@(\w+) (.*)$') { $value[$Matches[1]] = $Matches[2] } }
    Assert-True ($value.Contains('saved') -and $value['saved'] -match '^user://reports/\d{4}-\d\d-\d\dT\d\d-\d\d-\d\d-\d{3}(-\d+)?\.json$') "a report is saved under user://reports by its time: $($value['saved'])"
    Assert-True ($value['count'] -eq '2') "two reports found, not other JSON or a broken file: $($value['count'])"
    Assert-True ($value['scene'] -eq '1 these rocks look wrong 0') "a scene keeps its own report, and no scene has none: $($value['scene'])"
    Assert-True ($value['front'] -eq 'true') 'the player in front of the camera lands on its screen'
    Assert-True ($value['behind'] -eq 'true') 'a point behind the camera lands nowhere'
    Assert-True ($value['view'] -eq 'true') 'the camera comes back as it was'
    Assert-True ($value['flat'] -eq 'true') 'a 2D report keeps its position and has no 3D camera or screenshot'
    Assert-True ($value['label'] -eq '51 true') "a long line is cut, numbered from 1: $($value['label'])"
    Assert-True ($value['details'] -eq 'true true') 'the details name the seed to replay and the build'
    Assert-True (-not ($out -match 'ERROR')) "no errors, the broken file included: $(@($out -match 'ERROR') -join ' | ')"

    # The editor, headless, on the scene the shared report came from.
    $editor = @(& $godot --headless --editor --verbose --path $game --quit-after 120 res://level.tscn 2>&1 | ForEach-Object { "$_" })
    $code = $LASTEXITCODE
    Assert-True (@($editor -match 'report pins: 1 report\(s\) for res://level\.tscn').Count -ge 1) "the plugin lists the scene's report, once though it is in res://reports and user://: $(@($editor -match 'report pins') -join ' | ')"
    # Godot 4.7.2's headless editor aborts on --quit-after about one run in three with no plugin at all
    # ('Parameter "singleton" is null' in is_cmdline_mode, exit 134): that abort is the engine's, any other is not.
    $engineAbort = $code -eq 134 -and @($editor -match 'Parameter "singleton" is null').Count -gt 0
    Assert-True (-not ($editor -match 'SCRIPT ERROR|Parse Error') -and ($code -eq 0 -or $engineAbort)) "the editor loads it with no script error and quits (exit $code$(if ($engineAbort) { ', the engine''s known abort at exit' })): $(@($editor -match 'ERROR') | Select-Object -First 3)"
} finally {
    Remove-Item -LiteralPath $game -Recurse -Force -ErrorAction SilentlyContinue
    if ($value.Contains('userdir') -and $value['userdir'] -match "Report pins $id$") { Remove-Item -LiteralPath $value['userdir'] -Recurse -Force -ErrorAction SilentlyContinue }
}

if ($failures.Count) { throw "$($failures.Count) report pins check(s) failed" }
Write-Host 'report pins self-test passed'
exit 0
