#!/usr/bin/env bash
set -euo pipefail
bash "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/../scaffold-gdscript.sh"
# The bug: a pause menu that is not in the main scene yet, whose script does not compile (`flase`). No test loads it,
# so GUT passes and an import prints nothing about it; only a check that compiles every script finds it. It goes into
# the first commit, so the history does not point at it.
mkdir -p ui
cat > ui/pause_menu.gd <<'GD'
extends Control
## Pauses the game. Not in the main scene yet.

func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("ui_cancel"):
		visible = not visible
		get_tree().paused = visible

func _on_resume_pressed() -> void:
	visible = false
	get_tree().paused = flase
GD
cat > ui/pause_menu.tscn <<'TSCN'
[gd_scene load_steps=2 format=3]

[ext_resource type="Script" path="res://ui/pause_menu.gd" id="1_pause"]

[node name="PauseMenu" type="Control"]
process_mode = 3
visible = false
script = ExtResource("1_pause")
TSCN
git add -A
git -c user.name=eval -c user.email=eval@example.com commit -q --amend -m "Example game"
