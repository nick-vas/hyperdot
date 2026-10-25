class_name LaunchOptions
extends RefCounted
## The game's own flags, after "--" on the command line: --autoplay, --seed=N, --no-save, --map=N, --speed=N.

var autoplay := false
## 0: no seed given, so each battle draws its own.
var run_seed := 0
var no_save := false
var map := 1
## Battle ticks per physics tick: 1 is normal speed; a bot run defaults to 3.
var speed := 1


static func parse(args: PackedStringArray) -> LaunchOptions:
	var options := LaunchOptions.new()
	var speed_given := false
	for arg in args:
		if arg == "--autoplay":
			options.autoplay = true
		elif arg == "--no-save":
			options.no_save = true
		elif arg.begins_with("--seed="):
			options.run_seed = int(arg.get_slice("=", 1))
		elif arg.begins_with("--map="):
			options.map = maxi(1, int(arg.get_slice("=", 1)))
		elif arg.begins_with("--speed="):
			options.speed = clampi(int(arg.get_slice("=", 1)), 1, 8)
			speed_given = true
	if options.autoplay and not speed_given:
		options.speed = 3
	return options


static func from_command_line() -> LaunchOptions:
	return parse(OS.get_cmdline_user_args())
