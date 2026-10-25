extends SceneTree
## Captures store screenshots: run with a display, --resolution 1920x1080, from the game folder.

const OUT := "/dev/shm/racing/shots/"


func _shot(name: String) -> void:
	await process_frame
	await process_frame
	await RenderingServer.frame_post_draw
	root.get_viewport().get_texture().get_image().save_png(OUT + name + ".png")
	print("shot ", name)


func _initialize() -> void:
	await process_frame
	root.size = Vector2i(1920, 1080)
	var main: Node = load("res://main.tscn").instantiate()
	root.add_child(main)
	main.queue_free()
	await process_frame
	for spec in [[3, 9.5, "hero"]]:
		var game: Node = load("res://game/game.tscn").instantiate()
		var options := LaunchOptions.parse(PackedStringArray(["--autoplay", "--seed=3", "--no-save", "--track=%d" % spec[0]]))
		game.setup(Tracks.from_files(), options, {})
		root.add_child(game)
		Engine.time_scale = 4.0
		while game.state == "countdown" or game.race.tick < roundi((spec[1] - 3.0) * 60):
			await physics_frame
		Engine.time_scale = 1.0
		game.get_node("HUD").visible = false
		game.camera.zoom = Vector2(1.3, 1.3)
		await _shot(spec[2])
		game.queue_free()
		await process_frame
	quit()
