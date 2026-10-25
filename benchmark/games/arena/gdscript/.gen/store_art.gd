extends SceneTree
# Scratch generator: renders the store art and the icon from the running game. Run with a display.
var out := ""

func _initialize() -> void:
	out = OS.get_cmdline_user_args()[0]
	await process_frame
	root.size = Vector2i(1920, 1080)
	DisplayServer.window_set_size(Vector2i(1920, 1080))
	await _frames(5)
	_icon()
	var main: Node = load("res://main.tscn").instantiate()
	root.add_child(main)
	await _frames(10)
	_shot("screenshot_01_menu")
	main.free()
	var game := await _game(3, 40)
	_shot("screenshot_02_round")
	var full := root.get_texture().get_image()
	var title := _title_layer()
	await _frames(3)
	var titled := root.get_texture().get_image()
	_capsules(titled, full)
	title.free()
	await _until(game, func() -> bool: return game.client.view.round_number >= 2 and game.client.view.state == ArenaMatch.State.ROUND and game.client.view.state_ticks > 60, 4000)
	_shot("screenshot_03_hollow_ring")
	await _until(game, func() -> bool: return game.client.view.alive_slots().size() <= 2 and game.client.view.state == ArenaMatch.State.ROUND, 4000)
	await _frames(2)
	_shot("screenshot_04_last_two")
	game.free()
	TranslationServer.set_locale("fr")
	var game2 := await _game(5, 20)
	game2.get_node("ResultMenu").open(true, 1, 3, 1, true)
	await _frames(4)
	_shot("screenshot_05_victory")
	TranslationServer.set_locale("en")
	game2.free()
	await _logo()
	await _frames(2)
	quit()

func _frames(n: int) -> void:
	for i in n:
		await process_frame

func _until(game: Node, cond: Callable, limit: int) -> void:
	for i in limit:
		if cond.call():
			return
		await physics_frame

func _game(seed_value: int, ticks: int) -> Node:
	var game: Node = load("res://game/game.tscn").instantiate()
	game.setup("local", LaunchOptions.parse(PackedStringArray(["--autoplay", "--seed=%d" % seed_value, "--no-save"])))
	root.add_child(game)
	for i in ArenaMatch.WARMUP_TICKS + ticks:
		await physics_frame
	return game

func _shot(name: String) -> void:
	root.get_texture().get_image().save_png(out.path_join("game/store/steam/%s.png" % name))

func _title_layer() -> CanvasLayer:
	var layer := CanvasLayer.new()
	layer.layer = 50
	var shade := ColorRect.new()
	shade.color = Color(0, 0, 0, 0.35)
	shade.size = Vector2(1280, 720)
	layer.add_child(shade)
	var label := Label.new()
	label.text = "Glimmerpit"
	label.add_theme_font_size_override("font_size", 120)
	label.add_theme_color_override("font_color", Color(1.0, 0.85, 0.4))
	label.add_theme_color_override("font_outline_color", Color(0.1, 0.05, 0.15))
	label.add_theme_constant_override("outline_size", 18)
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	label.size = Vector2(1280, 720)
	layer.add_child(label)
	root.add_child(layer)
	return layer

func _fit(img: Image, w: int, h: int) -> Image:
	var copy := img.duplicate() as Image
	var scale := maxf(float(w) / copy.get_width(), float(h) / copy.get_height())
	copy.resize(int(ceil(copy.get_width() * scale)), int(ceil(copy.get_height() * scale)), Image.INTERPOLATE_LANCZOS)
	var x := (copy.get_width() - w) / 2
	var y := (copy.get_height() - h) / 2
	var cut := copy.get_region(Rect2i(x, y, w, h))
	cut.convert(Image.FORMAT_RGB8)
	return cut

func _capsules(titled: Image, plain: Image) -> void:
	var sizes := {"header_capsule": Vector2i(920, 430), "small_capsule": Vector2i(462, 174), "main_capsule": Vector2i(1232, 706),
		"vertical_capsule": Vector2i(748, 896), "library_capsule": Vector2i(600, 900), "library_header": Vector2i(920, 430)}
	for name: String in sizes:
		_fit(titled, sizes[name].x, sizes[name].y).save_png(out.path_join("game/store/steam/%s.png" % name))
	_fit(plain, 3840, 1240).save_png(out.path_join("game/store/steam/library_hero.png"))
	var capsule := _fit(titled, 600, 900)
	capsule.get_region(Rect2i(0, 0, 600, 800)).save_png(out.path_join("defects/library_capsule_600x800.png"))

func _glimmer(size: int) -> Image:
	var img := Image.create(size, size, false, Image.FORMAT_RGBA8)
	var c := Vector2(size, size) / 2.0
	for y in size:
		for x in size:
			var d := Vector2(x + 0.5, y + 0.5).distance_to(c) / (size / 2.0)
			var col := Color(0.1, 0.07, 0.16)
			if d < 0.62:
				col = Color(1.0, 0.82, 0.35).lerp(Color(1.0, 0.95, 0.8), clampf(1.0 - d / 0.62, 0.0, 1.0) * 0.6)
			elif d < 0.8:
				col = Color(0.98, 0.6, 0.25).lerp(Color(0.1, 0.07, 0.16), (d - 0.62) / 0.18)
			img.set_pixel(x, y, col)
	return img

func _icon() -> void:
	_glimmer(128).save_png(out.path_join("game/art/glimmer.png"))
	var shortcut := _glimmer(256)
	shortcut.convert(Image.FORMAT_RGB8)
	shortcut.save_png(out.path_join("game/store/steam/shortcut_icon.png"))
	var app := _glimmer(184)
	app.convert(Image.FORMAT_RGB8)
	app.save_jpg(out.path_join("game/store/steam/app_icon.jpg"), 0.92)

func _logo() -> void:
	var vp := SubViewport.new()
	vp.size = Vector2i(1280, 360)
	vp.transparent_bg = true
	vp.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	var label := Label.new()
	label.text = "Glimmerpit"
	label.add_theme_font_size_override("font_size", 200)
	label.add_theme_color_override("font_color", Color(1.0, 0.85, 0.4))
	label.add_theme_color_override("font_outline_color", Color(0.1, 0.05, 0.15))
	label.add_theme_constant_override("outline_size", 24)
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	label.size = Vector2(1280, 360)
	vp.add_child(label)
	root.add_child(vp)
	await _frames(4)
	var img := vp.get_texture().get_image()
	img.convert(Image.FORMAT_RGBA8)
	img.save_png(out.path_join("game/store/steam/library_logo.png"))
