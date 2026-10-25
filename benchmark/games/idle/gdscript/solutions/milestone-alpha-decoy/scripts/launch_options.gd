class_name LaunchOptions
extends RefCounted
## The game's own flags, after "--" on the command line: --no-save, --speed=N.

var no_save := false
## Seconds of play per second of game time (1 to 600).
var speed := 1.0


static func parse(args: PackedStringArray) -> LaunchOptions:
	var options := LaunchOptions.new()
	for arg in args:
		if arg == "--no-save":
			options.no_save = true
		elif arg.begins_with("--speed="):
			options.speed = clampf(float(arg.get_slice("=", 1)), 1.0, 600.0)
	return options


static func from_command_line() -> LaunchOptions:
	return parse(OS.get_cmdline_user_args())
