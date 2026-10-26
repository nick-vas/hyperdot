class_name LaunchOptions
extends RefCounted
## The game's own flags, after "--" on the command line: --autoplay, --no-save, --speed=N.

var autoplay := false
var no_save := false
## Seconds of play per second of game time: a bot run plays hours in minutes (1 to 600).
var speed := 1.0


static func parse(args: PackedStringArray) -> LaunchOptions:
	var options := LaunchOptions.new()
	for arg in args:
		if arg == "--autoplay":
			options.autoplay = true
		elif arg == "--no-save":
			options.no_save = true
		elif arg.begins_with("--speed="):
			options.speed = clampf(float(arg.get_slice("=", 1)), 1.0, 600.0)
	return options


static func from_command_line() -> LaunchOptions:
	return parse(OS.get_cmdline_user_args())
